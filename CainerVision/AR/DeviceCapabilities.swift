import ARKit
import RealityKit
import SwiftUI

/// What this iPhone can do. LiDAR features are optional; placement and recording are not.
struct DeviceCapabilities: Equatable {
    var lidarMesh: Bool
    var peopleOcclusion: Bool
    var sceneDepth: Bool
    var objectCapture: Bool

    static var current: DeviceCapabilities {
        let people = ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth)
            || ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentation)
        return DeviceCapabilities(
            lidarMesh: ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh),
            peopleOcclusion: people,
            sceneDepth: ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth),
            objectCapture: objectCaptureSupported
        )
    }

    /// Object capture support is isolated to the main actor in the current SDK.
    private static var objectCaptureSupported: Bool {
        guard Thread.isMainThread else { return false }
        return MainActor.assumeIsolated {
            ObjectCaptureSession.isSupported && PhotogrammetrySession.isSupported
        }
    }

    static var trackingSupported: Bool {
        ARWorldTrackingConfiguration.isSupported
    }

    func makeConfiguration() -> ARWorldTrackingConfiguration {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .automatic
        configuration.worldAlignment = .gravity
        if lidarMesh {
            configuration.sceneReconstruction = .mesh
        }
        if sceneDepth {
            configuration.frameSemantics.insert(.sceneDepth)
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            configuration.frameSemantics.insert(.personSegmentationWithDepth)
        } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentation) {
            configuration.frameSemantics.insert(.personSegmentation)
        }
        return configuration
    }
}
