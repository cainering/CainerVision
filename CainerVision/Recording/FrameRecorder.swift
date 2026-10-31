import AVFoundation
import CoreVideo
import Foundation
import Metal
import os
import QuartzCore
import RealityKit

/// Writes the composited AR frame (camera + 3D objects) to an H.264 movie.
///
/// RealityKit's post-process callback receives the rendered view before UIKit draws
/// buttons on top, so the recording does not include the camera chrome. The callback
/// must copy `sourceColorTexture` into `targetColorTexture` or the live view freezes.
final class FrameRecorder {
    var onRuntimeFailure: ((String) -> Void)?

    private let log = Logger(subsystem: "com.cainering.CainerVision", category: "recorder")
    private let writerQueue = DispatchQueue(label: "com.cainering.CainerVision.writer")
    private let audioQueue = DispatchQueue(label: "com.cainering.CainerVision.audio")
    private let lock = NSLock()

    private var device: MTLDevice?
    private var pipeline: MTLRenderPipelineState?
    private var textureCache: CVMetalTextureCache?
    private var pixelBufferPool: CVPixelBufferPool?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var audioInput: AVAssetWriterInput?
    private var microphone: MicrophoneCapture?
    private var outputURL: URL?

    private var acceptingFrames = false
    private var sessionStarted = false
    private var sessionStart = CMTime.zero
    private var lastTimestamp: CFTimeInterval?
    private var frameCount = 0
    private var inFlight = 0
    private var finishStarted = false
    private var failure: String?
    private var drain: (() -> Void)?
    private var audioSettings: [String: Any] = [:]
    private var pendingAudio: [CMSampleBuffer] = []
    private var wantsAudio = false
    private var outputWidth = 0
    private var outputHeight = 0
    private var watchdog: DispatchWorkItem?

    /// Flip only if a device build shows the movie upside down. The default matches
    /// RealityKit's top-left frame to a top-left video buffer.
    private let flipVertically = false

    func prepareIfNeeded() throws {
        lock.lock()
        let ready = pipeline != nil
        lock.unlock()
        if ready { return }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw UserFacingError(message: "This iPhone can't record the AR view.")
        }
        let pipeline = try makePipeline(on: device)
        var cache: CVMetalTextureCache?
        let status = CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        guard status == kCVReturnSuccess, let cache else {
            throw UserFacingError(message: "This iPhone can't record the AR view.")
        }
        lock.lock()
        self.device = device
        self.pipeline = pipeline
        self.textureCache = cache
        lock.unlock()
    }

    func begin(includeAudio: Bool) throws {
        try prepareIfNeeded()
        lock.lock()
        let oldWriter = writer
        let oldMicrophone = microphone
        acceptingFrames = false
        sessionStarted = false
        finishStarted = false
        failure = nil
        frameCount = 0
        inFlight = 0
        lastTimestamp = nil
        pendingAudio.removeAll()
        writer = nil
        videoInput = nil
        audioInput = nil
        adaptor = nil
        pixelBufferPool = nil
        microphone = nil
        wantsAudio = includeAudio
        audioSettings = [:]
        lock.unlock()

        if oldWriter?.status == .writing {
            oldWriter?.cancelWriting()
        }
        oldMicrophone?.stop()

        if includeAudio {
            let mic = MicrophoneCapture()
            do {
                let settings = try mic.start(on: audioQueue) { [weak self] sample in
                    self?.writerQueue.async {
                        self?.appendAudio(sample)
                    }
                }
                lock.lock()
                microphone = mic
                audioSettings = settings
                lock.unlock()
            } catch {
                log.error("Microphone failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        lock.lock()
        acceptingFrames = true
        lock.unlock()
        armWatchdog()
    }

    /// Called on RealityKit's render thread once per displayed frame.
    func consume(_ context: ARView.PostProcessContext) {
        blitToScreen(context)

        lock.lock()
        let record = acceptingFrames && failure == nil
        lock.unlock()
        guard record else { return }

        let now = CACurrentMediaTime()
        lock.lock()
        if !acceptingFrames || failure != nil {
            lock.unlock()
            return
        }
        if let lastTimestamp, now - lastTimestamp < (1.0 / 30.0) {
            lock.unlock()
            return
        }
        lastTimestamp = now
        inFlight += 1
        lock.unlock()

        var handedToGPU = false
        do {
            handedToGPU = try encode(context, time: now)
        } catch {
            report(error.localizedDescription)
        }
        if !handedToGPU {
            completeInFlight()
        }
    }

    func finish() async throws -> URL {
        lock.lock()
        if finishStarted {
            lock.unlock()
            throw UserFacingError(message: "This recording is already being saved.")
        }
        finishStarted = true
        acceptingFrames = false
        let existing = failure
        lock.unlock()
        watchdog?.cancel()
        await waitForGPU()
        if let existing {
            microphone?.stop()
            writer?.cancelWriting()
            throw UserFacingError(message: existing)
        }
        return try await withCheckedThrowingContinuation { continuation in
            writerQueue.async {
                self.finishOnWriterQueue(continuation)
            }
        }
    }

    /// Returns true when a GPU completion handler will call `completeInFlight`.
    private func encode(_ context: ARView.PostProcessContext, time: CFTimeInterval) throws -> Bool {
        if context.device.registryID != device?.registryID || pipeline == nil {
            pipeline = try makePipeline(on: context.device)
            var cache: CVMetalTextureCache?
            let status = CVMetalTextureCacheCreate(nil, nil, context.device, nil, &cache)
            guard status == kCVReturnSuccess, let cache else {
                throw UserFacingError(message: "Couldn't read the camera view.")
            }
            textureCache = cache
            device = context.device
        }
        guard let pipeline, let textureCache else {
            throw UserFacingError(message: "Couldn't read the camera view.")
        }
        let source = context.sourceColorTexture
        guard source.textureType == .type2D else { return false }

        lock.lock()
        let needsSetup = writer == nil
        lock.unlock()
        if needsSetup {
            try setupWriter(sourceWidth: source.width, sourceHeight: source.height)
        }
        guard let pool = pixelBufferPool else { return false }

        var pixelBuffer: CVPixelBuffer?
        let poolStatus = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard poolStatus == kCVReturnSuccess, let pixelBuffer else { return false }

        var cvTexture: CVMetalTexture?
        let textureStatus = CVMetalTextureCacheCreateTextureFromImage(
            nil,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            outputWidth,
            outputHeight,
            0,
            &cvTexture
        )
        guard textureStatus == kCVReturnSuccess, let cvTexture, let destination = CVMetalTextureGetTexture(cvTexture) else {
            return false
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = destination
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = context.commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return false }
        encoder.setRenderPipelineState(pipeline)
        encoder.setViewport(MTLViewport(
            originX: 0,
            originY: 0,
            width: Double(destination.width),
            height: Double(destination.height),
            znear: 0,
            zfar: 1
        ))
        var uniforms = CVUniforms(applyGamma: needsGamma(source.pixelFormat) ? 1 : 0, flipY: flipVertically ? 1 : 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<CVUniforms>.stride, index: 0)
        encoder.setFragmentTexture(source, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        let pts = CMTime(seconds: time, preferredTimescale: 600)
        context.commandBuffer.addCompletedHandler { [weak self] _ in
            // Keep the Metal texture alive until the GPU copy finishes.
            _ = cvTexture
            guard let self else { return }
            self.writerQueue.async {
                self.appendVideo(pixelBuffer, at: pts)
                self.completeInFlight()
            }
        }
        return true
    }

    private func completeInFlight() {
        lock.lock()
        inFlight -= 1
        let done = inFlight == 0
        let signal = done ? drain : nil
        if done { drain = nil }
        lock.unlock()
        signal?()
    }

    private func setupWriter(sourceWidth: Int, sourceHeight: Int) throws {
        let size = Self.outputSize(width: sourceWidth, height: sourceHeight)
        outputWidth = size.0
        outputHeight = size.1
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CainerVision-\(UUID().uuidString).mp4")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let bitrate = Self.bitrate(width: size.0, height: size.1)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.0,
            AVVideoHeightKey: size.1,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoMaxKeyFrameIntervalKey: 30,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(videoInput) else {
            throw UserFacingError(message: "This iPhone couldn't start the video encoder.")
        }
        writer.add(videoInput)
        let bufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: size.0,
            kCVPixelBufferHeightKey as String: size.1,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: bufferAttributes
        )
        var pool: CVPixelBufferPool?
        let poolAttributes = [kCVPixelBufferPoolMinimumBufferCountKey as String: 8] as CFDictionary
        let poolStatus = CVPixelBufferPoolCreate(nil, poolAttributes, bufferAttributes as CFDictionary, &pool)
        guard poolStatus == kCVReturnSuccess, let pool else {
            throw UserFacingError(message: "This iPhone couldn't start the video encoder.")
        }

        lock.lock()
        let settings = audioSettings
        let recordAudio = wantsAudio && !settings.isEmpty
        lock.unlock()
        var audioInput: AVAssetWriterInput?
        if recordAudio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            }
        }
        guard writer.startWriting() else {
            throw writer.error ?? UserFacingError(message: "The video encoder didn't start.")
        }
        let start = CMTime(seconds: CACurrentMediaTime(), preferredTimescale: 600)
        writer.startSession(atSourceTime: start)

        lock.lock()
        self.writer = writer
        self.videoInput = videoInput
        self.adaptor = adaptor
        self.audioInput = audioInput
        self.pixelBufferPool = pool
        self.outputURL = url
        self.sessionStart = start
        self.sessionStarted = true
        lock.unlock()
        log.info("Recording \(size.0, privacy: .public)x\(size.1, privacy: .public) at about 30 fps")
        writerQueue.async { self.flushPendingAudio() }
    }

    private func appendVideo(_ pixelBuffer: CVPixelBuffer, at time: CMTime) {
        lock.lock()
        let input = videoInput
        let adaptor = adaptor
        let writer = writer
        let started = sessionStarted
        lock.unlock()
        guard started, let input, let adaptor, let writer, writer.status == .writing else { return }
        guard input.isReadyForMoreMediaData else { return }
        if !adaptor.append(pixelBuffer, withPresentationTime: time) {
            if writer.status == .failed {
                report(writer.error?.localizedDescription ?? "The recording stopped unexpectedly.")
            }
            return
        }
        lock.lock()
        frameCount += 1
        lock.unlock()
    }

    private func appendAudio(_ sample: CMSampleBuffer) {
        lock.lock()
        let started = sessionStarted
        if !started {
            if pendingAudio.count > 120 { pendingAudio.removeFirst() }
            pendingAudio.append(sample)
            lock.unlock()
            return
        }
        let input = audioInput
        let writer = writer
        let start = sessionStart
        lock.unlock()
        guard let input, let writer else { return }
        appendAudioBuffer(sample, input: input, writer: writer, start: start)
    }

    private func flushPendingAudio() {
        lock.lock()
        let buffered = pendingAudio
        pendingAudio.removeAll()
        let input = audioInput
        let writer = writer
        let start = sessionStart
        lock.unlock()
        guard let input, let writer else { return }
        for sample in buffered {
            appendAudioBuffer(sample, input: input, writer: writer, start: start)
        }
    }

    private func appendAudioBuffer(
        _ sample: CMSampleBuffer,
        input: AVAssetWriterInput,
        writer: AVAssetWriter,
        start: CMTime
    ) {
        guard writer.status == .writing, input.isReadyForMoreMediaData else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        guard pts.isValid, CMTimeCompare(pts, start) >= 0 else { return }
        if !input.append(sample), writer.status == .failed {
            report(writer.error?.localizedDescription ?? "Audio couldn't be added to the recording.")
        }
    }

    private func finishOnWriterQueue(_ continuation: CheckedContinuation<URL, Error>) {
        microphone?.stop()
        microphone = nil
        lock.lock()
        let writer = writer
        let videoInput = videoInput
        let audioInput = audioInput
        let url = outputURL
        let frames = frameCount
        lock.unlock()
        guard let writer, let videoInput, let url else {
            continuation.resume(throwing: UserFacingError(message: "The recording didn't capture any frames. Try again."))
            return
        }
        if frames == 0 {
            writer.cancelWriting()
            continuation.resume(throwing: UserFacingError(message: "The recording didn't capture any frames. Try again."))
            return
        }
        videoInput.markAsFinished()
        audioInput?.markAsFinished()
        writer.finishWriting {
            if writer.status == .completed {
                continuation.resume(returning: url)
            } else {
                let message = writer.error?.localizedDescription ?? "The video couldn't be saved."
                continuation.resume(throwing: UserFacingError(message: message))
            }
        }
    }

    private func waitForGPU() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if inFlight == 0 {
                lock.unlock()
                continuation.resume()
                return
            }
            drain = { continuation.resume() }
            lock.unlock()
            writerQueue.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self else { return }
                self.lock.lock()
                let pending = self.drain
                self.drain = nil
                self.lock.unlock()
                pending?()
            }
        }
    }

    private func armWatchdog() {
        watchdog?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let frames = self.frameCount
            let accepting = self.acceptingFrames
            self.lock.unlock()
            if accepting && frames == 0 {
                self.report("The camera view didn't produce a recording. Try again.")
            }
        }
        watchdog = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    private func report(_ message: String) {
        lock.lock()
        let already = failure != nil
        if !already { failure = message }
        acceptingFrames = false
        lock.unlock()
        guard !already else { return }
        log.error("\(message, privacy: .public)")
        DispatchQueue.main.async { [weak self] in
            self?.onRuntimeFailure?(message)
        }
    }

    private func blitToScreen(_ context: ARView.PostProcessContext) {
        guard let blit = context.commandBuffer.makeBlitCommandEncoder() else { return }
        let source = context.sourceColorTexture
        let target = context.targetColorTexture
        blit.copy(
            from: source,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: source.width, height: source.height, depth: 1),
            to: target,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        blit.endEncoding()
    }

    private func needsGamma(_ format: MTLPixelFormat) -> Bool {
        switch format {
        case .rgba16Float, .rgba32Float, .bgra8Unorm_srgb, .rgba8Unorm_srgb:
            return true
        default:
            return false
        }
    }

    private func makePipeline(on device: MTLDevice) throws -> MTLRenderPipelineState {
        let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
        guard let vertex = library.makeFunction(name: "cvFullscreenVertex"),
              let fragment = library.makeFunction(name: "cvCopyFragment") else {
            throw UserFacingError(message: "Couldn't prepare the video recorder.")
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    /// Short side is at least 1080, both sides are even, and the long side stays near 4K or below.
    private static func outputSize(width: Int, height: Int) -> (Int, Int) {
        let shortSide = min(width, height)
        let scale = shortSide >= 1080 ? 1.0 : 1080.0 / Double(max(shortSide, 1))
        var outWidth = evenUp(Int((Double(width) * scale).rounded(.up)))
        var outHeight = evenUp(Int((Double(height) * scale).rounded(.up)))
        let longSide = max(outWidth, outHeight)
        if longSide > 3840 {
            let down = 3840.0 / Double(longSide)
            outWidth = evenUp(Int((Double(outWidth) * down).rounded(.down)))
            outHeight = evenUp(Int((Double(outHeight) * down).rounded(.down)))
        }
        while min(outWidth, outHeight) < 1080 {
            if outWidth <= outHeight { outWidth += 2 } else { outHeight += 2 }
        }
        return (max(outWidth, 2), max(outHeight, 2))
    }

    private static func evenUp(_ value: Int) -> Int {
        let positive = max(value, 2)
        return positive % 2 == 0 ? positive : positive + 1
    }

    private static func bitrate(width: Int, height: Int) -> Int {
        let pixels = Double(width * height)
        let baseline = 1920.0 * 1080.0
        return Int(min(20_000_000, max(8_000_000, pixels / baseline * 12_000_000)))
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct CVUniforms {
        uint applyGamma;
        uint flipY;
    };

    struct CVVertexOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex CVVertexOut cvFullscreenVertex(uint vid [[vertex_id]]) {
        float2 pos[3] = {
            float2(-1.0, -1.0),
            float2( 3.0, -1.0),
            float2(-1.0,  3.0)
        };
        // Clip y +1 is the top of the screen. Texture (0,0) is the top-left of the AR frame.
        float2 uv[3] = {
            float2(0.0, 1.0),
            float2(2.0, 1.0),
            float2(0.0, -1.0)
        };
        CVVertexOut out;
        out.position = float4(pos[vid], 0.0, 1.0);
        out.uv = uv[vid];
        return out;
    }

    fragment float4 cvCopyFragment(CVVertexOut in [[stage_in]],
                                   constant CVUniforms &uniforms [[buffer(0)]],
                                   texture2d<float> source [[texture(0)]]) {
        constexpr sampler samp(coord::normalized, address::clamp_to_edge, filter::linear);
        float2 uv = in.uv;
        if (uniforms.flipY != 0u) {
            uv.y = 1.0 - uv.y;
        }
        float4 color = source.sample(samp, uv);
        if (uniforms.applyGamma != 0u) {
            color.rgb = pow(saturate(color.rgb), float3(1.0 / 2.2));
        }
        return float4(color.rgb, 1.0);
    }
    """
}

private struct CVUniforms {
    var applyGamma: UInt32
    var flipY: UInt32
}
