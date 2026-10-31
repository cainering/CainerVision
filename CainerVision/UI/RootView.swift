import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if !DeviceCapabilities.trackingSupported {
                UnsupportedView()
            } else if model.cameraStatus != .authorized {
                PermissionView()
            } else {
                StudioView()
            }
        }
        .task {
            model.bootstrap()
        }
        .onOpenURL { url in
            Task { await model.importURLs([url]) }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active, model.isRecording else { return }
            Task { await model.stopRecording() }
        }
    }
}
