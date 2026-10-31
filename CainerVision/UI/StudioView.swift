import SwiftUI
import UIKit

struct StudioView: View {
    @Environment(AppModel.self) private var model
    @State private var showAdd = false
    @State private var showImporter = false
    @State private var showCreate = false
    @State private var showScan = false
    @State private var showInfo = false
    @State private var scanToken = UUID()

    var body: some View {
        @Bindable var model = model
        ZStack {
            ARViewContainer(scene: model.scene)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                topBar
                if let message = model.trackingMessage {
                    statusPill(message)
                }
                if let notice = model.notice {
                    noticeBanner(notice)
                }
                Spacer(minLength: 0)
                if model.isBusy {
                    statusPill(model.busyText)
                }
                if let selected = model.selectedInstance {
                    selectionBar(selected)
                } else if let armed = model.armedAsset {
                    statusPill("Tap a surface to place \(armed.name)")
                }
                assetTray
                shutterRow
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .confirmationDialog("Add an object", isPresented: $showAdd, titleVisibility: .visible) {
            Button("Import from Files") { showImporter = true }
            Button("Create a shape or text") { showCreate = true }
            Button("Scan a real object") {
                scanToken = UUID()
                showScan = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: AppModel.importTypes, allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                Task { await model.importURLs(urls) }
            case .failure(let error):
                let cancelled = (error as NSError).code == NSUserCancelledError
                if !cancelled {
                    model.showNotice("That file couldn't be opened from Files.")
                }
            }
        }
        .sheet(isPresented: $showCreate) {
            CreateAssetSheet(onScan: {
                showCreate = false
                scanToken = UUID()
                showScan = true
            })
        }
        .sheet(isPresented: $showInfo) {
            InfoSheet()
        }
        .fullScreenCover(isPresented: $showScan) {
            ScanCaptureView { url in
                await model.addFinishedScan(url)
            }
            .id(scanToken)
        }
        .sheet(isPresented: $model.showShare) {
            if let url = model.clips.fileURL {
                ShareSheet(url: url)
                    .ignoresSafeArea()
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Text("CainerVision")
                .font(.system(size: 17, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.ivory)
                .lineLimit(1)
            Spacer(minLength: 8)
            if model.isRecording || model.isSaving {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Theme.record)
                        .frame(width: 8, height: 8)
                    Text(model.isSaving ? "Saving" : ClockFormat.string(from: model.recordingDuration))
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(0.55), in: Capsule())
                .accessibilityLabel(model.isSaving ? "Saving video" : "Recording \(ClockFormat.string(from: model.recordingDuration))")
            }
            Button {
                Task { await model.setMicrophoneEnabled(!model.micEnabled) }
            } label: {
                Image(systemName: model.micEnabled ? "mic.fill" : "mic.slash.fill")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(model.micEnabled ? Theme.copper : Theme.ivory)
            }
            .disabled(model.isRecording)
            .accessibilityLabel(model.micEnabled ? "Microphone on" : "Microphone off")
            Button {
                showInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(Theme.ivory)
            }
            .accessibilityLabel("About this iPhone")
        }
    }

    private var assetTray: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if model.library.sortedItems.isEmpty {
                    Text("No objects yet. Add one to start.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.ivory)
                        .padding(.horizontal, 8)
                }
                ForEach(model.library.sortedItems) { item in
                    assetCell(item)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
        }
        .background(.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .opacity(model.isRecording ? 0.45 : 1)
    }

    private func assetCell(_ item: AssetItem) -> some View {
        let armed = model.armedAssetID == item.id
        return Button {
            if armed {
                model.armedAssetID = nil
            } else {
                model.armedAssetID = item.id
                model.selectedInstanceID = nil
                model.scene.refreshSelectionRings()
                Haptics.tick()
            }
        } label: {
            VStack(spacing: 6) {
                AssetGlyph(item: item)
                    .frame(width: 64, height: 64)
                    .background(Color.white.opacity(armed ? 0.14 : 0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(armed ? Theme.copper : Color.white.opacity(0.08), lineWidth: armed ? 2 : 1)
                    }
                Text(item.name)
                    .font(.caption2)
                    .foregroundStyle(Theme.ivory)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 72, height: 28, alignment: .top)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.name)
        .accessibilityAddTraits(armed ? .isSelected : [])
        .contextMenu {
            Button("Delete from library", role: .destructive) {
                model.deleteAsset(item)
            }
        }
    }

    private func selectionBar(_ selected: PlacedInstance) -> some View {
        HStack(spacing: 4) {
            Text(selected.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ivory)
                .lineLimit(1)
            Spacer(minLength: 8)
            if selected.hasAnimation {
                barButton(selected.isPlaying ? "pause.fill" : "play.fill", selected.isPlaying ? "Pause animation" : "Play animation") {
                    model.scene.toggleAnimation()
                }
            }
            barButton("plus.square.on.square", "Duplicate") {
                model.scene.duplicateSelected()
            }
            barButton("trash", "Delete") {
                model.scene.deleteSelected()
            }
            barButton("xmark", "Deselect") {
                model.selectedInstanceID = nil
                model.scene.refreshSelectionRings()
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(.black.opacity(0.5), in: Capsule())
    }

    private func barButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 40, height: 40)
                .foregroundStyle(Theme.ivory)
        }
        .accessibilityLabel(label)
    }

    private var shutterRow: some View {
        HStack {
            clipButton
            Spacer()
            recordButton
            Spacer()
            Button {
                showAdd = true
            } label: {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(width: 56, height: 56)
                    .background(Theme.ivory, in: Circle())
            }
            .disabled(model.isRecording)
            .accessibilityLabel("Add an object")
        }
    }

    private var recordButton: some View {
        Button {
            model.toggleRecording()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(Color.white, lineWidth: 4)
                    .frame(width: 74, height: 74)
                if model.isSaving {
                    ProgressView()
                        .tint(.white)
                } else {
                    RoundedRectangle(cornerRadius: model.isRecording ? 8 : 31, style: .continuous)
                        .fill(Theme.record)
                        .frame(width: model.isRecording ? 30 : 60, height: model.isRecording ? 30 : 60)
                }
            }
        }
        .disabled(!model.canRecord)
        .opacity(model.canRecord ? 1 : 0.4)
        .accessibilityLabel(model.isRecording ? "Stop recording" : "Record")
    }

    private var clipButton: some View {
        Button {
            guard model.clips.fileURL != nil else { return }
            model.showShare = true
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                if let poster = model.clips.poster {
                    Image(uiImage: poster)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "film")
                        .foregroundStyle(Theme.ivory)
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.7), lineWidth: 1)
            }
        }
        .disabled(model.clips.fileURL == nil || model.isRecording)
        .opacity(model.clips.fileURL == nil ? 0.45 : 1)
        .accessibilityLabel("Share the last clip")
    }

    private func statusPill(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.ivory)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.black.opacity(0.5), in: Capsule())
            .frame(maxWidth: .infinity)
    }

    private func noticeBanner(_ notice: Notice) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(notice.text)
                .font(.subheadline)
                .foregroundStyle(Theme.ivory)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let title = notice.actionTitle, let action = notice.action {
                Button(title) {
                    model.perform(noticeAction: action)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.copper)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            model.notice = nil
        }
    }
}

private struct AssetGlyph: View {
    let item: AssetItem
    @Environment(AppModel.self) private var model
    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            } else {
                Image(systemName: item.symbolName)
                    .font(.title2)
                    .foregroundStyle(glyphColor)
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .task(id: item.id) {
            thumbnail = await model.library.thumbnail(for: item)
        }
    }

    private var glyphColor: Color {
        switch item.source {
        case .primitive(let spec):
            return Color(uiColor: ColorHex.uiColor(spec.hex))
        case .text(let spec):
            return Color(uiColor: ColorHex.uiColor(spec.hex))
        case .file:
            return Theme.ivory
        }
    }
}
