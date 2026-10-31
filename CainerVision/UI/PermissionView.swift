import SwiftUI

struct PermissionView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 28) {
                Spacer()
                VStack(alignment: .leading, spacing: 12) {
                    Text("CainerVision")
                        .font(.system(size: 40, weight: .semibold, design: .serif))
                        .foregroundStyle(Theme.ivory)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.copper)
                        .frame(width: 44, height: 4)
                    Text("Place 3D objects in the room in front of you, then record a video where they look like they belong there.")
                        .font(.body)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 16) {
                    reason("camera.fill", "Camera", "Sees the room and composites objects into it.")
                    reason("mic.fill", "Microphone", "Optional sound on the videos you record.")
                    reason("photo.fill", "Photos", "Saves finished clips to your library.")
                }
                Spacer()
                if model.cameraStatus == .denied || model.cameraStatus == .restricted {
                    Text("Camera access is off. Turn it on in Settings to use CainerVision.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.ivory)
                    Button("Open Settings") {
                        model.perform(noticeAction: .settings)
                    }
                    .buttonStyle(CopperButtonStyle())
                } else {
                    Button("Continue") {
                        Task { await model.requestCamera() }
                    }
                    .buttonStyle(CopperButtonStyle())
                    Text("You'll be asked for the camera next. The microphone and photo library are only asked for when you record or save.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(24)
        }
    }

    private func reason(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.copper)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.ivory)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }
        }
    }
}

struct UnsupportedView: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "iphone.gen3")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.copper)
                Text("CainerVision needs an iPhone")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.ivory)
                Text("World tracking uses the real camera, so it doesn't run in the Simulator. Open this project in Xcode, plug in your iPhone, and press Run.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.muted)
            }
            .padding(28)
        }
    }
}

struct CopperButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.copper.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
