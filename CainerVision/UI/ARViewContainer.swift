import RealityKit
import SwiftUI

struct ARViewContainer: UIViewRepresentable {
    var scene: SceneController

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        view.backgroundColor = .black
        scene.attach(view)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
