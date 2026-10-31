import RealityKit
import SwiftUI

struct ScanCaptureView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var controller = ScanController()

    var onFinished: (URL) async -> Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            model.scene.pauseForScan()
        }
        .onChange(of: controller.phase) { _, phase in
            guard phase == .done, let url = controller.outputURL else { return }
            Task {
                let saved = await onFinished(url)
                if saved {
                    controller.deleteCaptureDirectory()
                }
                dismiss()
            }
        }
        .onDisappear {
            controller.cancel()
            model.scene.resumeAfterScan(clearScene: controller.captureStarted)
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        switch controller.phase {
        case .intro:
            intro
        case .reconstructing, .done:
            progressScreen
        case .failed:
            failedScreen
        default:
            captureScreen
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Text("Scan an object")
                .font(.system(size: 34, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.ivory)
            Text("Walk slowly around something textured and well lit. CainerVision turns those photos into a 3D model on this iPhone. Shiny, clear, and hair-thin things scan poorly.")
                .foregroundStyle(Theme.muted)
            if model.capabilities.objectCapture {
                Text("Starting a scan clears the objects currently placed in the scene, because the camera has to restart afterwards.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.ivory)
                Button("Start scanning") {
                    controller.start()
                }
                .buttonStyle(CopperButtonStyle())
            } else {
                Text("This iPhone can't build a model from photos. Object scanning needs a LiDAR camera, which is on iPhone 12 Pro and later Pro models. You can still import a USDZ or place the built-in shapes.")
                    .foregroundStyle(Theme.ivory)
            }
            Button("Close") { dismiss() }
                .font(.headline)
                .foregroundStyle(Theme.ivory)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            Spacer()
        }
        .padding(24)
    }

    private var captureScreen: some View {
        ZStack {
            if controller.showPointCloud {
                ObjectCapturePointCloudView(session: controller.session)
                    .ignoresSafeArea()
            } else {
                ObjectCaptureView(session: controller.session)
                    .ignoresSafeArea()
            }
            VStack {
                HStack {
                    Button("Close") { dismiss() }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.45), in: Capsule())
                    Spacer()
                    Text("\(controller.shotCount) shots")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.45), in: Capsule())
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Spacer()
                captureControls
            }
        }
    }

    private var captureControls: some View {
        VStack(spacing: 10) {
            if let hint = controller.hint {
                Text(hint)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }
            switch controller.phase {
            case .starting:
                ProgressView("Starting the camera…")
                    .tint(.white)
                    .foregroundStyle(.white)
            case .ready:
                Text("Frame the object in the box.")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                Button("Continue") { controller.session.startDetecting() }
                    .buttonStyle(CopperButtonStyle())
            case .detecting:
                Text("Fit the box, then start. Drag the handles if you need to.")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Button("Start capture") { controller.session.startCapturing() }
                    .buttonStyle(CopperButtonStyle())
                Button("Choose again") { controller.session.resetDetection() }
                    .foregroundStyle(.white)
            case .capturing:
                Text("Walk slowly around the object until the ring fills.")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Button("Create model now") { controller.session.finish() }
                    .font(.headline)
                    .foregroundStyle(.white)
            case .review:
                Text("That lap is full. Flip the object for the bottom, take another lap, or build the model.")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Button("Create model") { controller.finishCapture() }
                    .buttonStyle(CopperButtonStyle())
                Button("Another lap") { controller.anotherLap(flip: false) }
                    .foregroundStyle(.white)
                if controller.canFlip {
                    Button("Flip object and scan again") { controller.anotherLap(flip: true) }
                        .foregroundStyle(.white)
                }
                Button(controller.showPointCloud ? "Back to camera" : "Preview coverage") {
                    controller.showPointCloud.toggle()
                }
                .font(.subheadline)
                .foregroundStyle(Theme.copper)
            case .finishing:
                ProgressView("Saving photos…")
                    .tint(.white)
                    .foregroundStyle(.white)
            default:
                EmptyView()
            }
        }
        .padding(16)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private var progressScreen: some View {
        VStack(spacing: 16) {
            ProgressView(value: controller.phase == .done ? 1 : controller.progress)
                .tint(Theme.copper)
            Text(controller.phase == .done
                 ? "Adding the model to your library…"
                 : "Building the 3D model… \(Int((controller.progress * 100).rounded()))%")
                .font(.headline)
                .foregroundStyle(Theme.ivory)
                .multilineTextAlignment(.center)
            Text("This can take a few minutes. Keep CainerVision open and the phone unlocked.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.muted)
        }
        .padding(28)
    }

    private var failedScreen: some View {
        VStack(spacing: 16) {
            Text("The scan didn't finish")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.ivory)
            Text(controller.errorText ?? "Try again with more light and a slower walk around the object.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.muted)
            if controller.canRetryReconstruction {
                Button("Try building again") { controller.retryReconstruction() }
                    .buttonStyle(CopperButtonStyle())
            }
            Button("Close") { dismiss() }
                .foregroundStyle(Theme.ivory)
        }
        .padding(28)
    }
}

@MainActor
@Observable
final class ScanController {
    let session = ObjectCaptureSession()
    var phase: ScanPhase = .intro
    var shotCount = 0
    var hint: String?
    var progress: Double = 0
    var errorText: String?
    var outputURL: URL?
    var showPointCloud = false
    var canFlip = true
    var captureStarted = false
    var canRetryReconstruction = false

    private var imagesURL: URL?
    private var checkpointURL: URL?
    private var scanRoot: URL?
    private var photoSession: PhotogrammetrySession?
    private var monitor: Task<Void, Never>?
    private var reconstructTask: Task<Void, Never>?
    private var cancelled = false
    private var sawNotFlippable = false
    private var startedReconstruction = false

    func start() {
        guard ObjectCaptureSession.isSupported, PhotogrammetrySession.isSupported else {
            phase = .failed
            errorText = "This iPhone can't scan objects into 3D models."
            return
        }
        do {
            let base = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let root = base.appendingPathComponent("CainerVision/Scans/\(UUID().uuidString)", isDirectory: true)
            let images = root.appendingPathComponent("Images", isDirectory: true)
            let checkpoints = root.appendingPathComponent("Checkpoints", isDirectory: true)
            try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: checkpoints, withIntermediateDirectories: true)
            imagesURL = images
            checkpointURL = checkpoints
            scanRoot = root
            var configuration = ObjectCaptureSession.Configuration()
            configuration.checkpointDirectory = checkpoints
            configuration.isOverCaptureEnabled = false
            session.start(imagesDirectory: images, configuration: configuration)
            captureStarted = true
            phase = .starting
            beginMonitoring()
        } catch {
            phase = .failed
            errorText = "Couldn't prepare a folder for the scan."
        }
    }

    func anotherLap(flip: Bool) {
        showPointCloud = false
        if session.isPaused { session.resume() }
        if flip {
            session.beginNewScanPassAfterFlip()
        } else {
            session.beginNewScanPass()
        }
    }

    func finishCapture() {
        showPointCloud = false
        if session.isPaused { session.resume() }
        session.finish()
    }

    func retryReconstruction() {
        startedReconstruction = true
        errorText = nil
        canRetryReconstruction = false
        reconstructTask = Task { await reconstruct() }
    }

    func cancel() {
        cancelled = true
        monitor?.cancel()
        guard phase != .done else { return }
        reconstructTask?.cancel()
        photoSession?.cancel()
        if captureStarted, phase != .failed {
            session.cancel()
        }
    }

    func deleteCaptureDirectory() {
        guard let scanRoot else { return }
        try? FileManager.default.removeItem(at: scanRoot)
    }

    private func beginMonitoring() {
        monitor?.cancel()
        monitor = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                self.pull()
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    private func pull() {
        shotCount = session.numberOfShotsTaken
        if session.feedback.contains(.objectNotFlippable) {
            sawNotFlippable = true
        }
        canFlip = !sawNotFlippable
        hint = Self.hint(from: session.feedback)
        guard !startedReconstruction, phase != .failed else { return }
        switch session.state {
        case .initializing:
            phase = .starting
        case .ready:
            phase = .ready
        case .detecting:
            phase = .detecting
        case .capturing:
            phase = session.userCompletedScanPass ? .review : .capturing
        case .finishing:
            phase = .finishing
        case .completed:
            phase = .reconstructing
            if !startedReconstruction {
                startedReconstruction = true
                reconstructTask = Task { await reconstruct() }
            }
        case .failed(let error):
            phase = .failed
            errorText = error.localizedDescription
        @unknown default:
            break
        }
    }

    private func reconstruct() async {
        guard let imagesURL, let checkpointURL, let scanRoot else { return }
        phase = .reconstructing
        progress = 0
        let modelURL = scanRoot.appendingPathComponent("Model.usdz")
        do {
            var configuration = PhotogrammetrySession.Configuration()
            configuration.checkpointDirectory = checkpointURL
            let photo = try PhotogrammetrySession(input: imagesURL, configuration: configuration)
            photoSession = photo
            if FileManager.default.fileExists(atPath: modelURL.path) {
                try FileManager.default.removeItem(at: modelURL)
            }
            let request = PhotogrammetrySession.Request.modelFile(url: modelURL, detail: .reduced)
            let outputs = photo.outputs
            try photo.process(requests: [request])
            for try await event in outputs {
                if cancelled { return }
                switch event {
                case .requestProgress(_, let fraction):
                    progress = min(max(fraction, 0), 1)
                case .requestComplete(_, let result):
                    if case .modelFile(let url) = result {
                        outputURL = url
                    }
                case .requestError(_, let error):
                    throw error
                case .processingComplete:
                    if outputURL == nil, FileManager.default.fileExists(atPath: modelURL.path) {
                        outputURL = modelURL
                    }
                default:
                    break
                }
            }
            if outputURL == nil {
                throw UserFacingError(message: "The photos weren't enough to build a model. Try a slower lap with the whole object in frame.")
            }
            phase = .done
        } catch {
            if cancelled { return }
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            canRetryReconstruction = true
            phase = .failed
        }
    }

    private static func hint(from feedback: Set<ObjectCaptureSession.Feedback>) -> String? {
        if feedback.contains(.environmentTooDark) { return "It's too dark. Add more light." }
        if feedback.contains(.environmentLowLight) { return "A bit more light will help." }
        if feedback.contains(.movingTooFast) { return "Slow down." }
        if feedback.contains(.objectTooClose) { return "Move back a little." }
        if feedback.contains(.objectTooFar) { return "Move closer." }
        if feedback.contains(.outOfFieldOfView) { return "Keep the object in frame." }
        if feedback.contains(.objectNotDetected) { return "Point the box at the object." }
        if feedback.contains(.overCapturing) { return "That's plenty of photos. Create the model." }
        return nil
    }
}

enum ScanPhase: Equatable {
    case intro
    case starting
    case ready
    case detecting
    case capturing
    case review
    case finishing
    case reconstructing
    case done
    case failed
}
