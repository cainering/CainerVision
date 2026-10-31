import AVFoundation
import Foundation
import Photos
import UIKit

/// Keeps the latest recorded clip on disk so it can be saved to Photos and shared.
@Observable
final class ClipStore {
    private(set) var poster: UIImage?
    private(set) var fileURL: URL?

    func loadExisting() {
        let url = Self.clipURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        fileURL = url
        Task { await refreshPoster() }
    }

    @discardableResult
    func adopt(temporaryFile: URL) throws -> URL {
        let destination = Self.clipURL()
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryFile, to: destination)
        fileURL = destination
        Task { await refreshPoster() }
        return destination
    }

    func refreshPoster() async {
        guard let fileURL else { return }
        let asset = AVURLAsset(url: fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 360, height: 360)
        let time = CMTime(seconds: 0.15, preferredTimescale: 600)
        guard let image = try? await generator.image(at: time).image else { return }
        poster = UIImage(cgImage: image)
    }

    func saveToPhotoLibrary() async throws {
        guard let fileURL else {
            throw UserFacingError(message: "There's no clip to save.")
        }
        let status = await requestAddAccess()
        guard status == .authorized else {
            throw UserFacingError(message: "Photo access is off, so the clip wasn't added to your library. You can still share the video.")
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: UserFacingError(message: "The video couldn't be saved to Photos."))
                }
            }
        }
    }

    private func requestAddAccess() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if current != .notDetermined { return current }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }

    private static func clipURL() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("CainerVision/Clips/CainerVision.mp4")
    }
}
