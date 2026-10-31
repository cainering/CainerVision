import AVFoundation
import Foundation
import Observation
import UIKit
import UniformTypeIdentifiers

struct Notice: Equatable {
    var text: String
    var actionTitle: String?
    var action: NoticeAction?
}

enum NoticeAction: Equatable {
    case settings
    case share
}

@Observable
final class AppModel {
    let library = LibraryStore()
    let scene = SceneController()
    let clips = ClipStore()

    var capabilities = DeviceCapabilities.current
    var cameraStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    var armedAssetID: UUID?
    var selectedInstanceID: UUID?
    var placed: [PlacedInstance] = []
    var trackingReady = false
    var trackingMessage: String?
    var notice: Notice?
    var isBusy = false
    var busyText = ""
    var isRecording = false
    var isSaving = false
    var recordingDuration: TimeInterval = 0
    var micEnabled = true
    var showShare = false

    private var noticeToken = 0
    private var recordingTimer: Timer?
    private var finishingRecording = false
    private let recordingLimit: TimeInterval = 5 * 60

    var armedAsset: AssetItem? {
        guard let armedAssetID else { return nil }
        return library.items.first { $0.id == armedAssetID }
    }

    var selectedInstance: PlacedInstance? {
        guard let selectedInstanceID else { return nil }
        return placed.first { $0.id == selectedInstanceID }
    }

    var canRecord: Bool {
        if isSaving { return false }
        if isRecording { return true }
        return trackingReady && !isBusy
    }

    init() {
        scene.model = self
    }

    func bootstrap() {
        capabilities = DeviceCapabilities.current
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        do {
            try library.load()
        } catch {
            showNotice("The object library couldn't be opened. \(error.localizedDescription)")
        }
        clips.loadExisting()
    }

    func requestCamera() async {
        let granted = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { granted in
                continuation.resume(returning: granted)
            }
        }
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if !granted && cameraStatus == .denied {
            showNotice("Camera access is off. CainerVision needs it to see the room.", actionTitle: "Settings", action: .settings)
        }
    }

    func toggleRecording() {
        if isRecording {
            Task { await stopRecording(hitTimeLimit: false) }
        } else {
            Task { await startRecording() }
        }
    }

    func startRecording() async {
        guard !isRecording, !isSaving else { return }
        var recordAudio = false
        if micEnabled {
            recordAudio = await requestMicrophone()
            if !recordAudio {
                micEnabled = false
                showNotice("Microphone is off, so this clip will be silent.", actionTitle: "Settings", action: .settings)
            }
        }
        AppDelegate.lockCurrentOrientation()
        do {
            try scene.startRecording(includeAudio: recordAudio)
            isRecording = true
            recordingDuration = 0
            let started = Date()
            recordingTimer?.invalidate()
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.recordingDuration = Date().timeIntervalSince(started)
                if self.recordingDuration >= self.recordingLimit {
                    Task { await self.stopRecording(hitTimeLimit: true) }
                }
            }
            Haptics.record()
        } catch {
            AppDelegate.unlockOrientation()
            isRecording = false
            showNotice((error as? LocalizedError)?.errorDescription ?? "Couldn't start recording.")
        }
    }

    func stopRecording(hitTimeLimit: Bool = false) async {
        guard isRecording, !finishingRecording else { return }
        finishingRecording = true
        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecording = false
        isSaving = true
        defer {
            isSaving = false
            finishingRecording = false
            AppDelegate.unlockOrientation()
        }
        do {
            let temporary = try await scene.stopRecording()
            let saved = try clips.adopt(temporaryFile: temporary)
            do {
                try await clips.saveToPhotoLibrary()
                Haptics.success()
                if hitTimeLimit {
                    showNotice("Saved a 5 minute clip to Photos.", actionTitle: "Share", action: .share)
                } else {
                    showNotice("Saved to Photos.", actionTitle: "Share", action: .share)
                }
            } catch {
                showShare = true
                showNotice((error as? LocalizedError)?.errorDescription ?? "The clip is ready to share.", actionTitle: "Share", action: .share)
            }
            _ = saved
        } catch {
            showNotice((error as? LocalizedError)?.errorDescription ?? "The recording couldn't be saved.")
        }
    }

    func handleRecordingFailure(_ message: String) async {
        if isRecording {
            await stopRecording(hitTimeLimit: false)
        }
        showNotice(message)
    }

    func setMicrophoneEnabled(_ enabled: Bool) async {
        guard !isRecording else { return }
        if !enabled {
            micEnabled = false
            return
        }
        let allowed = await requestMicrophone()
        micEnabled = allowed
        if !allowed {
            showNotice("Microphone access is off.", actionTitle: "Settings", action: .settings)
        }
    }

    func importURLs(_ urls: [URL]) async {
        guard !urls.isEmpty, !isRecording else { return }
        isBusy = true
        busyText = "Importing…"
        defer { isBusy = false }
        var last: AssetItem?
        for url in urls {
            do {
                last = try await library.importFile(from: url)
            } catch {
                showNotice((error as? LocalizedError)?.errorDescription ?? "That file couldn't be imported.")
            }
        }
        if let last {
            armedAssetID = last.id
            selectedInstanceID = nil
            showNotice("Imported \(last.name). Tap a surface to place it.")
        }
    }

    func addCreated(_ item: AssetItem) {
        armedAssetID = item.id
        selectedInstanceID = nil
        showNotice("\(item.name) is ready. Tap a surface to place it.")
    }

    @discardableResult
    func addFinishedScan(_ url: URL) async -> Bool {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        do {
            let item = try library.addScan(at: url, name: "Scan \(formatter.string(from: Date()))")
            armedAssetID = item.id
            showNotice("Scan added. Tap a surface to place it.")
            return true
        } catch {
            showNotice("The scan couldn't be added to your library.")
            return false
        }
    }

    func deleteAsset(_ item: AssetItem) {
        do {
            try library.delete(item)
            if armedAssetID == item.id { armedAssetID = nil }
        } catch {
            showNotice("That object couldn't be removed from the library.")
        }
    }

    func restoreSamples() {
        do {
            try library.restoreBuiltIns()
            showNotice("Sample objects are back in the tray.")
        } catch {
            showNotice("The sample objects couldn't be restored.")
        }
    }

    func showNotice(_ text: String, actionTitle: String? = nil, action: NoticeAction? = nil) {
        noticeToken += 1
        let token = noticeToken
        notice = Notice(text: text, actionTitle: actionTitle, action: action)
        Task {
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            if noticeToken == token {
                notice = nil
            }
        }
    }

    func perform(noticeAction: NoticeAction) {
        switch noticeAction {
        case .settings:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        case .share:
            showShare = true
        }
    }

    static var importTypes: [UTType] {
        var types: [UTType] = []
        let identifiers = [
            "com.pixar.universal-scene-description-mobile",
            "com.pixar.universal-scene-description",
            "com.cainering.wavefront-obj",
            "com.cainering.reality-file",
        ]
        for identifier in identifiers {
            if let type = UTType(identifier) {
                types.append(type)
            }
        }
        for ext in ["usdz", "usd", "usda", "usdc", "obj", "reality"] {
            if let type = UTType(filenameExtension: ext), !types.contains(type) {
                types.append(type)
            }
        }
        return types.isEmpty ? [.data] : types
    }

    private func requestMicrophone() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }
}

enum ClockFormat {
    static func string(from interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
