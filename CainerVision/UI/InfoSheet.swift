import SwiftUI

struct InfoSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            List {
                Section("This iPhone") {
                    capability("Room lighting and reflections", true, "Objects pick up the color of the room, and metal shows reflections.")
                    capability("People occlusion", model.capabilities.peopleOcclusion, "People walking in front of an object can hide it when this phone supports it.")
                    capability("LiDAR occlusion", model.capabilities.lidarMesh, "Furniture and walls can hide objects. This needs a Pro iPhone with LiDAR.")
                    capability("Object scanning", model.capabilities.objectCapture, "Turn a real object into a 3D model. iPhone 12 Pro and later Pro models.")
                }
                Section("Scene") {
                    Button("Remove objects from the scene", role: .destructive) {
                        confirmClear = true
                    }
                    Button("Reset tracking") {
                        model.scene.resetTracking()
                        dismiss()
                    }
                    Button("Restore sample objects") {
                        model.restoreSamples()
                        dismiss()
                    }
                }
                Section("How to shoot") {
                    Text("Choose an object in the tray, then tap a floor or wall to place it. Drag to move it, pinch to resize, and twist with two fingers to rotate. The record button saves the camera and the 3D objects, not the buttons.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Section("Limits") {
                    Text("LiDAR occlusion and object scanning are only on Pro iPhones with a LiDAR scanner. Scans are the mobile detail level and struggle with shiny, clear, or very thin things. Clips stop at 5 minutes. The scene is not saved when you leave the app.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("CainerVision")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .confirmationDialog("Remove every object from the scene?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Remove objects", role: .destructive) {
                model.scene.clearPlaced()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func capability(_ title: String, _ on: Bool, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(on ? "On" : "Not on this phone")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(on ? Theme.copper : .secondary)
            }
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
