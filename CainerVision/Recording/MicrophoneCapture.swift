import AVFoundation
import Foundation

/// Records microphone audio alongside an ARKit camera session.
/// An audio-only capture session can run next to ARKit; a second camera session cannot.
final class MicrophoneCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private var onSample: ((CMSampleBuffer) -> Void)?

    func start(on queue: DispatchQueue, handler: @escaping (CMSampleBuffer) -> Void) throws -> [String: Any] {
        onSample = handler
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playAndRecord, mode: .videoRecording, options: [.mixWithOthers, .defaultToSpeaker])
        try audio.setActive(true)

        session.beginConfiguration()
        session.automaticallyConfiguresApplicationAudioSession = false
        guard let device = AVCaptureDevice.default(for: .audio) else {
            throw UserFacingError(message: "This iPhone has no microphone.")
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw UserFacingError(message: "The microphone couldn't be started.")
        }
        session.addInput(input)
        output.setSampleBufferDelegate(self, queue: queue)
        session.addOutput(output)
        session.commitConfiguration()
        let settings = output.recommendedAudioSettingsForAssetWriter(writingTo: .mp4) as? [String: Any] ?? [:]
        session.startRunning()
        return settings
    }

    func stop() {
        if session.isRunning {
            session.stopRunning()
        }
        session.beginConfiguration()
        for input in session.inputs {
            session.removeInput(input)
        }
        if session.outputs.contains(where: { $0 === output }) {
            session.removeOutput(output)
        }
        session.commitConfiguration()
        onSample = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        onSample?(sampleBuffer)
    }
}
