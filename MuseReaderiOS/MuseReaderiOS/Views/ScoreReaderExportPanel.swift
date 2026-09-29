//
//  ScoreReaderExportPanel.swift
//  MuseReaderiOS
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers
import CoreImage
import ImageIO

enum ScoreReaderExportFormat: String, CaseIterable, Identifiable {
    case museScore
    case pdf
    case musicXML
    case midi
    case audio
    case images
    case video

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .museScore:
            return ".mscz"
        case .pdf:
            return "PDF"
        case .musicXML:
            return "MusicXML"
        case .midi:
            return "MIDI"
        case .audio:
            return "Audio"
        case .images:
            return "Images"
        case .video:
            return "Video"
        }
    }

    var subtitle: String {
        switch self {
        case .museScore:
            return "Native MuseScore file"
        case .pdf:
            return "Best for sharing & printing"
        case .musicXML:
            return ".musicxml or .xml"
        case .midi:
            return ".mid for playback / DAW"
        case .audio:
            return ".wav"
        case .images:
            return "PNG pages"
        case .video:
            return ".mp4 play-along"
        }
    }

    var systemImage: String {
        switch self {
        case .museScore:
            return "doc.badge.gearshape"
        case .pdf:
            return "doc.richtext"
        case .musicXML:
            return "doc.text"
        case .midi:
            return "music.note"
        case .audio:
            return "waveform"
        case .images:
            return "photo.on.rectangle"
        case .video:
            return "play.rectangle"
        }
    }

    var tint: Color {
        switch self {
        case .museScore:
            return Color.gray
        case .pdf:
            return Color.red
        case .musicXML:
            return Color.gray
        case .midi:
            return Color.purple
        case .audio:
            return Color.green
        case .images:
            return Color.blue
        case .video:
            return Color.orange
        }
    }

    var isAvailable: Bool {
        switch self {
        case .museScore, .pdf, .musicXML, .midi, .audio, .images, .video:
            return true
        }
    }

    var exportsDisplayedView: Bool {
        switch self {
        case .pdf, .images, .video:
            return true
        case .museScore, .musicXML, .midi, .audio:
            return false
        }
    }
}

struct ScoreReaderExportDraft {
    var includesFullScore = true
    var includesParts = false
    var format: ScoreReaderExportFormat = .pdf
    var selectedPartIDs: Set<String> = []
    var fileName = ""
    var exportPartsInConcertPitch = false
    var exportPartsInOriginalKey = false
    var videoStyle: ScoreVideoStyle = .scrolling
    var videoBackgroundImageData: Data? = nil
    var videoBackgroundImageName: String? = nil

    var hasExportContent: Bool {
        includesFullScore || includesParts
    }
}

struct ScoreReaderSharedExportItems: Identifiable {
    let urls: [URL]

    var id: String {
        urls.map(\.absoluteString).joined(separator: "|")
    }
}

enum ScoreReaderExportError: LocalizedError {
    case unsupportedFormat(String)
    case noContentSelected
    case noPages
    case noAudio
    case imageEncodingFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format):
            return "\(format) export is not available in the current render bridge."
        case .noContentSelected:
            return "Choose at least one export target."
        case .noPages:
            return "There are no rendered pages to export."
        case .noAudio:
            return "There is no playback audio to export."
        case .imageEncodingFailed:
            return "Aria could not encode one of the score pages."
        }
    }
}

enum ScoreReaderExportTarget {
    case fullScore(pageCount: Int)
    case part(ScorePart, pageCount: Int)

    var pageCount: Int {
        switch self {
        case .fullScore(let pageCount), .part(_, let pageCount):
            return pageCount
        }
    }
}

struct ScoreReaderExportPanel: View {
    @State private var isVideoSettingsPresented = false
    let scoreTitle: String
    let sharingDescription: String
    let parts: [ScorePart]
    let isShowingTemporaryTransposedView: Bool
    @Binding var draft: ScoreReaderExportDraft
    let isPreparingExport: Bool
    let cancelAction: () -> Void
    let exportAction: () -> Void
    /// Rendering progress for exports that take a while, such as video.
    var exportProgress: Double? = nil
    var videoPreviewPage: ScorePage? = nil
    var exportErrorMessage: String? = nil
    var videoExportCompleted = false
    var videoSheetDismissAction: () -> Void = {}

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: isPhone ? 10 : 18) {
                VStack(alignment: .leading, spacing: isPhone ? 2 : 4) {
                    Text("Export Score")
                        .font(.system(size: isPhone ? 18 : 20, weight: .semibold))
                    if !isPhone {
                        Text("Choose content and format")
                            .font(.subheadline)
                            .foregroundStyle(Color.black.opacity(0.52))
                    }
                    Text("Sharing: \(sharingDescription)")
                        .font(.system(size: isPhone ? 12 : 13, weight: .semibold))
                        .foregroundStyle(Color.blue.opacity(0.86))
                }

                VStack(alignment: .leading, spacing: isPhone ? 5 : 8) {
                    sectionTitle("What to export")
                    VStack(spacing: 0) {
                        exportContentRow(
                            title: "Full Score",
                            isSelected: draft.includesFullScore,
                            isRequiredSelection: !draft.includesParts
                        ) {
                            if draft.includesFullScore && !draft.includesParts {
                                return
                            }
                            draft.includesFullScore.toggle()
                        }
                        Divider().padding(.leading, 40)
                        exportContentRow(
                            title: "Parts",
                            isSelected: draft.includesParts,
                            isRequiredSelection: !draft.includesFullScore
                        ) {
                            if draft.includesParts && !draft.includesFullScore {
                                return
                            }
                            draft.includesParts.toggle()
                        }
                        if draft.includesParts, !parts.isEmpty {
                            Divider().padding(.leading, 40)
                            partSelector
                        }
                    }
                    .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(panelBorder)
                }

                VStack(alignment: .leading, spacing: isPhone ? 5 : 8) {
                    sectionTitle("Format")
                    VStack(spacing: 0) {
                        ForEach(Array(ScoreReaderExportFormat.allCases.enumerated()), id: \.element.id) { index, format in
                            if index > 0 {
                                Divider().padding(.leading, 54)
                            }
                            formatRow(format)
                        }
                    }
                    .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(panelBorder)
                }

                if draft.format == .video {
                    videoSettingsRow
                }

                if showsExportPartsInConcertRow {
                    exportPartsInConcertRow
                }

                if showsExportPartsInOriginalKeyRow {
                    exportPartsInOriginalKeyRow
                }

                filenameRow

                HStack(spacing: isPhone ? 8 : 10) {
                    Button(action: cancelAction) {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ScoreReaderExportFooterButtonStyle(isPrimary: false, isCompact: isPhone))

                    Button {
                        if draft.format == .video {
                            isVideoSettingsPresented = true
                        } else {
                            exportAction()
                        }
                    } label: {
                        if isPreparingExport, let exportProgress {
                            Text("Rendering \(Int((exportProgress * 100).rounded()))%")
                                .monospacedDigit()
                                .frame(maxWidth: .infinity)
                        } else if isPreparingExport {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(draft.format == .video ? "Video settings…" : "Export")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(ScoreReaderExportFooterButtonStyle(isPrimary: true, isCompact: isPhone))
                    .disabled(isPreparingExport || !draft.format.isAvailable || !draft.hasExportContent)
                }
            }
            .padding(isPhone ? 14 : 22)
        }
        .font(.system(size: isPhone ? 13 : 14, weight: .medium))
        .foregroundStyle(Color.black.opacity(0.86))
        .frame(width: panelWidth)
        .frame(maxHeight: panelMaxHeight)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.62), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.18), radius: 28, y: 16)
        .onAppear {
            if draft.fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft.fileName = scoreTitle
            }
            if draft.selectedPartIDs.isEmpty {
                draft.selectedPartIDs = Set(parts.map(\.id))
            }
        }
        .onChange(of: videoExportCompleted) { completed in
            if completed {
                isVideoSettingsPresented = false
            }
        }
        .sheet(isPresented: $isVideoSettingsPresented, onDismiss: videoSheetDismissAction) {
            ScoreReaderVideoExportSheet(
                scoreTitle: scoreTitle,
                sharingDescription: sharingDescription,
                previewPage: videoPreviewPage,
                draft: $draft,
                isPreparingExport: isPreparingExport,
                exportProgress: exportProgress,
                exportErrorMessage: exportErrorMessage,
                exportAction: exportAction
            )
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: isPhone ? 12 : 15, weight: .semibold))
            .foregroundStyle(Color.black.opacity(isPhone ? 0.58 : 0.86))
    }

    private var panelWidth: CGFloat {
        let phoneWidth: CGFloat = UIScreen.main.bounds.width > UIScreen.main.bounds.height ? 360 : 332
        return min(isPhone ? phoneWidth : 380, max(UIScreen.main.bounds.width - 24, 300))
    }

    private var panelMaxHeight: CGFloat {
        isPhone ? min(UIScreen.main.bounds.height - 72, 720) : min(UIScreen.main.bounds.height - 80, 940)
    }

    private var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    private func exportContentRow(
        title: String,
        isSelected: Bool,
        isRequiredSelection: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? Color.blue : Color.black.opacity(0.34))
                    .font(.system(size: isPhone ? 17 : 20, weight: .semibold))
                Text(title)
                Spacer()
                if isRequiredSelection && !isPhone {
                    Text("Required")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.black.opacity(0.38))
                }
            }
            .frame(height: isPhone ? 36 : 44)
            .padding(.horizontal, isPhone ? 11 : 14)
        }
        .buttonStyle(.plain)
    }

    private var partSelector: some View {
        VStack(alignment: .leading, spacing: isPhone ? 6 : 9) {
            Text("Select Parts")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.black.opacity(0.64))

            MobileHintingHorizontalScrollView(hintHeight: 25) {
                HStack(spacing: 7) {
                    ForEach(parts) { part in
                        Button {
                            togglePart(part.id)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: draft.selectedPartIDs.contains(part.id) ? "checkmark.square.fill" : "square")
                                Text(part.name)
                                    .lineLimit(1)
                            }
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.blue)
                            .padding(.horizontal, 7)
                            .frame(height: 25)
                            .background(Color.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, isPhone ? 11 : 14)
        .padding(.vertical, isPhone ? 8 : 12)
    }

    private func formatRow(_ format: ScoreReaderExportFormat) -> some View {
        Button {
            guard format.isAvailable else {
                return
            }
            draft.format = format
            if format == .video {
                isVideoSettingsPresented = true
            }
        } label: {
            HStack(spacing: isPhone ? 9 : 12) {
                Image(systemName: format.systemImage)
                    .font(.system(size: isPhone ? 16 : 20, weight: .semibold))
                    .foregroundStyle(format.tint)
                    .frame(width: isPhone ? 26 : 32, height: isPhone ? 26 : 32)
                    .background(format.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: isPhone ? 6 : 7, style: .continuous))

                VStack(alignment: .leading, spacing: isPhone ? 1 : 3) {
                    HStack(spacing: 6) {
                        Text(format.title)
                        if showsTransposedLabel(for: format) {
                            Text("(Transposed)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.blue.opacity(0.82))
                        }
                        if !format.isAvailable {
                            Text("Soon")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.black.opacity(0.42))
                        }
                    }
                    if !isPhone {
                        Text(format.subtitle)
                            .font(.caption)
                            .foregroundStyle(Color.black.opacity(0.50))
                    }
                }

                Spacer()

                Image(systemName: draft.format == format ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(draft.format == format ? Color.blue : Color.black.opacity(0.32))
                    .font(.system(size: isPhone ? 17 : 20, weight: .semibold))
            }
            .padding(.horizontal, isPhone ? 11 : 14)
            .frame(height: isPhone ? 42 : 62)
            .opacity(format.isAvailable ? 1 : 0.44)
        }
        .buttonStyle(.plain)
        .disabled(!format.isAvailable)
    }

    private var filenameRow: some View {
        HStack {
            Text("Filename")
            Spacer()
            TextField(scoreTitle, text: $draft.fileName)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.plain)
                .frame(maxWidth: isPhone ? 160 : 190)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.black.opacity(0.32))
        }
        .padding(.horizontal, isPhone ? 12 : 16)
        .frame(height: isPhone ? 42 : 54)
        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(panelBorder)
    }

    private var showsExportPartsInConcertRow: Bool {
        draft.format == .pdf && !parts.isEmpty
    }

    private func showsTransposedLabel(for format: ScoreReaderExportFormat) -> Bool {
        guard isShowingTemporaryTransposedView, format.exportsDisplayedView else {
            return false
        }

        return draft.includesFullScore || !draft.exportPartsInOriginalKey
    }

    private var showsExportPartsInOriginalKeyRow: Bool {
        isShowingTemporaryTransposedView && draft.format.exportsDisplayedView && !parts.isEmpty
    }

    private var videoSettingsRow: some View {
        Button {
            isVideoSettingsPresented = true
        } label: {
            HStack {
                Text("Video settings")
                Spacer()
                Text(draft.videoStyle.title)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, isPhone ? 12 : 16)
            .frame(height: isPhone ? 42 : 54)
            .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 9))
            .overlay(panelBorder)
        }
        .buttonStyle(.plain)
        .disabled(isPreparingExport)
    }

    private var exportPartsInConcertRow: some View {
        Button {
            draft.exportPartsInConcertPitch.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: draft.exportPartsInConcertPitch ? "checkmark.square.fill" : "square")
                    .foregroundStyle(draft.exportPartsInConcertPitch ? Color.blue : Color.black.opacity(0.34))
                    .font(.system(size: isPhone ? 17 : 20, weight: .semibold))
                Text("Export parts in concert")
                Spacer()
            }
            .padding(.horizontal, isPhone ? 12 : 16)
            .frame(height: isPhone ? 42 : 54)
            .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(panelBorder)
        }
        .buttonStyle(.plain)
        .disabled(!draft.includesParts)
        .opacity(draft.includesParts ? 1 : 0.46)
    }

    private var exportPartsInOriginalKeyRow: some View {
        Button {
            draft.exportPartsInOriginalKey.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: draft.exportPartsInOriginalKey ? "checkmark.square.fill" : "square")
                    .foregroundStyle(draft.exportPartsInOriginalKey ? Color.blue : Color.black.opacity(0.34))
                    .font(.system(size: isPhone ? 17 : 20, weight: .semibold))
                Text("Export parts in Original Key")
                Spacer()
            }
            .padding(.horizontal, isPhone ? 12 : 16)
            .frame(height: isPhone ? 42 : 54)
            .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(panelBorder)
        }
        .buttonStyle(.plain)
        .disabled(!draft.includesParts)
        .opacity(draft.includesParts ? 1 : 0.46)
    }

    private var panelBorder: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .stroke(Color.black.opacity(0.08), lineWidth: 1)
    }

    private func togglePart(_ id: String) {
        if draft.selectedPartIDs.contains(id) {
            if draft.selectedPartIDs.count > 1 {
                draft.selectedPartIDs.remove(id)
            }
        } else {
            draft.selectedPartIDs.insert(id)
        }
    }
}

private struct ScoreReaderVideoExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isChoosingBackground = false
    @State private var isLoadingBackground = false
    @State private var backgroundError: String?
    @State private var previewImages = ScoreReaderVideoPreviewImages()
    @State private var previewRevision = 0
    @State private var isLoadingPreview = true
    @State private var preferredScrollingStyle: ScoreVideoStyle = .scrolling
    @State private var preferredPageStyle: ScoreVideoStyle = .pagesLandscape

    let scoreTitle: String
    let sharingDescription: String
    let previewPage: ScorePage?
    @Binding var draft: ScoreReaderExportDraft
    let isPreparingExport: Bool
    let exportProgress: Double?
    let exportErrorMessage: String?
    let exportAction: () -> Void

    private var isScrolling: Bool {
        draft.videoStyle == .scrolling || draft.videoStyle == .scrollingPhoto
    }

    private var layoutSelection: Binding<Bool> {
        Binding(get: { isScrolling }, set: { scrolling in
            if scrolling {
                preferredPageStyle = draft.videoStyle
                draft.videoStyle = preferredScrollingStyle
            } else {
                preferredScrollingStyle = draft.videoStyle
                draft.videoStyle = preferredPageStyle
            }
        })
    }

    private var appearanceSelection: Binding<Bool> {
        Binding(get: { draft.videoStyle == .scrollingPhoto }, set: { photo in
            draft.videoStyle = photo ? .scrollingPhoto : .scrolling
        })
    }

    private var previewTaskID: String {
        "\(draft.videoStyle.rawValue)-\(previewPage?.id ?? "none")-\(previewRevision)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    preview

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Layout").font(.subheadline.weight(.semibold))
                        Picker("Layout", selection: layoutSelection) {
                            Text("Scrolling").tag(true)
                            Text("Pages").tag(false)
                        }
                        .pickerStyle(.segmented)
                        Text(isScrolling
                             ? "A continuous score moves smoothly past the playhead."
                             : "Follow the playing measure as the score pages move.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if isScrolling {
                        appearanceOptions
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Orientation").font(.subheadline.weight(.semibold))
                            Picker("Orientation", selection: $draft.videoStyle) {
                                Text("Landscape 16:9").tag(ScoreVideoStyle.pagesLandscape)
                                Text("Portrait 9:16").tag(ScoreVideoStyle.pagesPortrait)
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    if draft.videoStyle == .scrollingPhoto {
                        backgroundPhotoRow
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(scoreTitle) · \(sharingDescription)")
                            .font(.subheadline)
                        Text("Full HD · 30 fps · Score audio included")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(isPreparingExport)
                .frame(maxWidth: 560)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Video export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("Close video export")
                    .disabled(isPreparingExport)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                renderFooter
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(isPreparingExport)
        .onAppear {
            if isScrolling {
                preferredScrollingStyle = draft.videoStyle
            } else {
                preferredPageStyle = draft.videoStyle
            }
        }
        .task(id: previewTaskID) {
            isLoadingPreview = true
            let style = draft.videoStyle
            let backgroundData = draft.videoBackgroundImageData
            let page = previewPage
            let images = await Task.detached(priority: .userInitiated) {
                ScoreReaderVideoPreviewRenderer.makeImages(page: page, style: style, backgroundData: backgroundData)
            }.value
            guard !Task.isCancelled else { return }
            previewImages = images
            isLoadingPreview = false
        }
        .fileImporter(isPresented: $isChoosingBackground, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url):
                isLoadingBackground = true
                backgroundError = nil
                Task {
                    defer { isLoadingBackground = false }
                    do {
                        let data = try await Task.detached(priority: .userInitiated) {
                            let canAccess = url.startAccessingSecurityScopedResource()
                            defer { if canAccess { url.stopAccessingSecurityScopedResource() } }
                            let data = try Data(contentsOf: url)
                            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                                  CGImageSourceGetCount(source) > 0 else {
                                throw ScoreReaderExportError.imageEncodingFailed
                            }
                            return data
                        }.value
                        draft.videoBackgroundImageData = data
                        draft.videoBackgroundImageName = url.lastPathComponent
                        previewRevision += 1
                    } catch {
                        backgroundError = "That image could not be opened. \(error.localizedDescription)"
                    }
                }
            case .failure(let error):
                backgroundError = error.localizedDescription
            }
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemGroupedBackground))
                if let image = draft.videoStyle == .scrollingPhoto ? previewImages.photo : previewImages.paper {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else if draft.videoStyle == .scrollingPhoto && draft.videoBackgroundImageData == nil {
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                        Text("Choose a photo to preview white notation").font(.caption)
                    }
                    .foregroundStyle(.secondary)
                } else if isLoadingPreview {
                    ProgressView()
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.richtext")
                        Text("Score preview unavailable").font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .aspectRatio(draft.videoStyle == .pagesPortrait ? 9.0 / 16.0 : 16.0 / 9.0, contentMode: .fit)
            .frame(maxHeight: draft.videoStyle == .pagesPortrait ? 300 : 260)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel("Representative score appearance preview")
            HStack {
                Text("Score preview")
                Spacer()
                Text(draft.videoStyle == .pagesPortrait ? "9:16 · Pages" : isScrolling ? "16:9 · Scrolling" : "16:9 · Pages")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text("Appearance preview from the displayed score; video uses its own layout.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var appearanceOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Appearance").font(.subheadline.weight(.semibold))
            HStack(spacing: 12) {
                appearanceCard(title: "White paper", photo: false, image: previewImages.paper)
                appearanceCard(title: "Photo background", photo: true, image: previewImages.photo)
            }
        }
    }

    private func appearanceCard(title: String, photo: Bool, image: UIImage?) -> some View {
        let selected = appearanceSelection.wrappedValue == photo
        return Button {
            appearanceSelection.wrappedValue = photo
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    Color(uiColor: photo ? .darkGray : .white)
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        Image(systemName: photo ? "photo" : "doc.richtext")
                            .foregroundStyle(photo ? Color.white : Color.secondary)
                    }
                }
                .frame(height: 68)
                .clipped()
                HStack(spacing: 5) {
                    Text(title).font(.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var backgroundPhotoRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isChoosingBackground = true
            } label: {
                HStack(spacing: 12) {
                    if let image = previewImages.backgroundThumbnail {
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: 46, height: 38)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        Image(systemName: "photo").frame(width: 46, height: 38)
                    }
                    Text(draft.videoBackgroundImageName ?? "Choose background photo")
                        .lineLimit(1)
                    Spacer()
                    if isLoadingBackground {
                        ProgressView()
                    } else {
                        Text(draft.videoBackgroundImageData == nil ? "Choose" : "Change")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .font(.subheadline)
                .padding(12)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(isLoadingBackground)
            if let backgroundError {
                Text(backgroundError).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var renderFooter: some View {
        VStack(spacing: 10) {
            if let exportErrorMessage {
                Text(exportErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if isPreparingExport {
                if let exportProgress {
                    ProgressView(value: min(max(exportProgress, 0), 1))
                    Text("Rendering \(Int((min(max(exportProgress, 0), 1) * 100).rounded()))%")
                        .monospacedDigit()
                } else {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Preparing video…")
                    }
                }
            }
            Button(action: exportAction) {
                Text(isPreparingExport ? "Rendering…" : "Render video")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ScoreReaderExportFooterButtonStyle(isPrimary: true))
            .disabled(isPreparingExport || isLoadingBackground || !draft.hasExportContent
                      || (draft.videoStyle == .scrollingPhoto && draft.videoBackgroundImageData == nil))
            Text("Keep Aria open while rendering.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .frame(maxWidth: 560)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }
}

/// Immutable thumbnails cross back from the worker task after PDF/photo decoding.
private struct ScoreReaderVideoPreviewImages: @unchecked Sendable {
    var paper: UIImage?
    var photo: UIImage?
    var backgroundThumbnail: UIImage?
}

private nonisolated enum ScoreReaderVideoPreviewRenderer {
    private static let imageContext = CIContext(options: [.cacheIntermediates: false])

    static func makeImages(page: ScorePage?, style: ScoreVideoStyle, backgroundData: Data?) -> ScoreReaderVideoPreviewImages {
        let scrolling = style == .scrolling || style == .scrollingPhoto
        let size = style == .pagesPortrait ? CGSize(width: 360, height: 640) : CGSize(width: 640, height: 360)
        let thumbnail = backgroundData.flatMap { downsample($0, maximumPixelSize: 960) }
        guard let page else { return ScoreReaderVideoPreviewImages(backgroundThumbnail: thumbnail) }
        let paper = scoreImage(page: page, size: size, cropSystem: scrolling)
        guard let paperCGImage = paper.cgImage, let backgroundCGImage = thumbnail?.cgImage else {
            return ScoreReaderVideoPreviewImages(paper: paper, backgroundThumbnail: thumbnail)
        }
        let bounds = CGRect(origin: .zero, size: size)
        let background = CIImage(cgImage: backgroundCGImage)
        let scale = max(size.width / background.extent.width, size.height / background.extent.height)
        let scaled = background.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let centered = scaled.transformed(by: CGAffineTransform(translationX: (size.width - scaled.extent.width) / 2,
                                                                y: (size.height - scaled.extent.height) / 2))
        let blurred = centered.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 12]).cropped(to: bounds)
        let dim = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0.4)).cropped(to: bounds).composited(over: blurred)
        // Convert black engraving on paper to white ink with matching antialiasing.
        let inverted = CIImage(cgImage: paperCGImage).applyingFilter("CIColorInvert")
        let ink = inverted.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0)
        ])
        let photo = imageContext.createCGImage(ink.composited(over: dim), from: bounds).map { UIImage(cgImage: $0) }
        return ScoreReaderVideoPreviewImages(paper: paper, photo: photo, backgroundThumbnail: thumbnail)
    }

    private static func downsample(_ data: Data, maximumPixelSize: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    private static func scoreImage(page: ScorePage, size: CGSize, cropSystem: Bool) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { rendererContext in
            let context = rendererContext.cgContext
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let pdf = page.pdfData.flatMap { CGDataProvider(data: $0 as CFData) }.flatMap(CGPDFDocument.init)?.page(at: 1)
            let raster = pdf == nil ? page.imageData.flatMap { downsample($0, maximumPixelSize: 1600) } : nil
            let sourceSize = pdf?.getBoxRect(.mediaBox).size ?? raster?.size ?? CGSize(width: 612, height: 792)
            var crop = CGRect(origin: .zero, size: sourceSize)
            if cropSystem, let system = page.layoutMarkers.first(where: {
                if case .system = $0.kind { return true }
                return false
            }) {
                let rect = system.normalizedRect
                crop = CGRect(x: CGFloat(rect.x) * sourceSize.width,
                              y: CGFloat(rect.y) * sourceSize.height,
                              width: CGFloat(rect.width) * sourceSize.width,
                              height: CGFloat(rect.height) * sourceSize.height)
                    .insetBy(dx: -sourceSize.width * 0.015, dy: -sourceSize.height * 0.035)
                    .intersection(CGRect(origin: .zero, size: sourceSize))
            }
            guard crop.width > 0, crop.height > 0 else { return }
            let area = CGRect(origin: .zero, size: size).insetBy(dx: 20, dy: cropSystem ? 50 : 16)
            let scale = min(area.width / crop.width, area.height / crop.height)
            let drawingRect = CGRect(x: (size.width - crop.width * scale) / 2,
                                     y: (size.height - crop.height * scale) / 2,
                                     width: crop.width * scale, height: crop.height * scale)
            context.saveGState()
            context.clip(to: drawingRect)
            if let pdf {
                let box = pdf.getBoxRect(.mediaBox)
                context.translateBy(x: drawingRect.minX, y: drawingRect.maxY)
                context.scaleBy(x: scale, y: -scale)
                context.translateBy(x: -box.minX - crop.minX, y: -box.minY - (sourceSize.height - crop.maxY))
                context.drawPDFPage(pdf)
            } else if let raster {
                raster.draw(in: CGRect(x: drawingRect.minX - crop.minX * scale,
                                       y: drawingRect.minY - crop.minY * scale,
                                       width: sourceSize.width * scale, height: sourceSize.height * scale))
            }
            context.restoreGState()
        }
    }
}

private struct ScoreReaderExportFooterButtonStyle: ButtonStyle {
    let isPrimary: Bool
    var isCompact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: isCompact ? 14 : 15, weight: .semibold))
            .foregroundStyle(isPrimary ? Color.white : Color.black.opacity(0.86))
            .frame(height: isCompact ? 42 : 52)
            .background(
                isPrimary
                    ? Color.blue.opacity(configuration.isPressed ? 0.82 : 1)
                    : Color.white.opacity(configuration.isPressed ? 0.64 : 0.86),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.black.opacity(isPrimary ? 0 : 0.08), lineWidth: 1)
            }
    }
}

struct ScoreReaderShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
