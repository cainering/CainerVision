import Foundation
import RealityKit

/// Marks the gesture wrapper for one object the user placed in the room.
struct PlacedObjectComponent: Component {
    var instanceID: UUID
    var assetID: UUID
    var title: String
    var hasAnimation: Bool

    static func registerIfNeeded() {
        guard !didRegister else { return }
        didRegister = true
        registerComponent()
    }

    private static var didRegister = false
}

extension Entity {
    /// Walks up from a tapped mesh to the wrapper that owns placement state.
    func placedWrapper() -> Entity? {
        if components[PlacedObjectComponent.self] != nil { return self }
        return parent?.placedWrapper()
    }
}
