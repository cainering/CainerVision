import SwiftUI
import UIKit

struct CreateAssetSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var onScan: () -> Void

    @State private var mode = 0
    @State private var shape: PrimitiveShape = .box
    @State private var name = "Cube"
    @State private var text = "Hello"
    @State private var font: TextFontChoice = .rounded
    @State private var hex = "E7D3C0"
    @State private var gloss: Double = 0.35
    @State private var metal: Double = 0
    @State private var depthMM: Double = 12
    @State private var errorText: String?

    private let swatches = ["F4EFE6", "E7D3C0", "C47A5A", "E39A4A", "C6A15A", "B87333", "3E6B56", "3C5C78", "2C2926", "F7F7F5"]

    var body: some View {
        NavigationStack {
            Form {
                Picker("Kind", selection: $mode) {
                    Text("Shape").tag(0)
                    Text("Text").tag(1)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                if mode == 0 {
                    shapeSection
                } else {
                    textSection
                }
                materialSection
                if let errorText {
                    Text(errorText)
                        .foregroundStyle(Theme.record)
                }
                Section {
                    Button("Scan a real object instead") {
                        onScan()
                    }
                } footer: {
                    Text(model.capabilities.objectCapture
                         ? "Scanning uses the LiDAR camera and builds a model on this iPhone. It clears whatever is currently placed in the scene."
                         : "Scanning needs an iPhone 12 Pro or a later Pro model. You can still create shapes and import files on this phone.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("New object")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add() }
                        .fontWeight(.semibold)
                }
            }
            .onChange(of: shape) { _, newShape in
                if mode == 0 { name = newShape.title }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var shapeSection: some View {
        Section("Shape") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 10)], spacing: 10) {
                ForEach(PrimitiveShape.allCases) { option in
                    Button {
                        shape = option
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: option.symbolName)
                                .font(.title3)
                            Text(option.title)
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(shape == option ? Color.black : Theme.ivory)
                        .background(shape == option ? Theme.copper : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
            TextField("Name", text: $name)
        }
    }

    private var textSection: some View {
        Section("Text") {
            TextField("Words", text: $text)
            Picker("Font", selection: $font) {
                ForEach(TextFontChoice.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            VStack(alignment: .leading) {
                Text("Thickness \(Int(depthMM)) mm")
                    .font(.subheadline)
                Slider(value: $depthMM, in: 2...30, step: 1)
            }
            TextField("Name", text: $name)
        }
    }

    private var materialSection: some View {
        Section("Look") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(swatches, id: \.self) { swatch in
                    Button {
                        hex = swatch
                    } label: {
                        Circle()
                            .fill(Color(uiColor: ColorHex.uiColor(swatch)))
                            .frame(height: 32)
                            .overlay {
                                Circle().strokeBorder(hex == swatch ? Color.white : Color.clear, lineWidth: 2)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Color \(swatch)")
                }
            }
            ColorPicker("Custom color", selection: customColor, supportsOpacity: false)
            VStack(alignment: .leading) {
                Text("Matte to glossy")
                Slider(value: $gloss, in: 0...1)
            }
            VStack(alignment: .leading) {
                Text("Plastic to metal")
                Slider(value: $metal, in: 0...1)
            }
        }
    }

    private var customColor: Binding<Color> {
        Binding(
            get: { Color(uiColor: ColorHex.uiColor(hex)) },
            set: { hex = ColorHex.hex(from: UIColor($0)) }
        )
    }

    private func add() {
        errorText = nil
        let roughness = Float(1 - gloss)
        let metallic = Float(metal)
        do {
            let item: AssetItem
            if mode == 0 {
                let spec = PrimitiveSpec(shape: shape, hex: hex, roughness: roughness, metallic: metallic, size: 0.1)
                item = try model.library.addPrimitive(spec, name: name.isEmpty ? shape.title : name)
            } else {
                let spec = TextSpec(
                    string: text,
                    hex: hex,
                    extrusion: Float(depthMM / 1000),
                    roughness: roughness,
                    metallic: metallic,
                    font: font
                )
                _ = try ModelLoader.text(spec)
                item = try model.library.addText(spec, name: name.isEmpty ? text : name)
            }
            model.addCreated(item)
            dismiss()
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? "That object couldn't be created."
        }
    }
}
