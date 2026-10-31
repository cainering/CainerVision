import Foundation

/// An error whose message is safe to show in the camera UI.
struct UserFacingError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}
