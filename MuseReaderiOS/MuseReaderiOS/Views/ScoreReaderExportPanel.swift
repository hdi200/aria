//
//  ScoreReaderExportPanel.swift
//  MuseReaderiOS
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers
import CoreImage
import ImageIO
import PhotosUI

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
    var scoreComposer = ""
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
                scoreComposer: scoreComposer,
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
    @State private var backgroundPhotoItem: PhotosPickerItem?
    @State private var isLoadingBackground = false
    @State private var backgroundError: String?
    @State private var previewImages = ScoreReaderVideoPreviewImages()
    @State private var previewRevision = 0
    @State private var isLoadingPreview = true
    @State private var preferredScrollingStyle: ScoreVideoStyle = .scrolling
    @State private var preferredPageStyle: ScoreVideoStyle = .pagesLandscape

    let scoreTitle: String
    let scoreComposer: String
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
            let title = scoreTitle
            let composer = scoreComposer
            let images = await Task.detached(priority: .userInitiated) {
                ScoreReaderVideoPreviewRenderer.makeImages(page: page, style: style, title: title, composer: composer,
                                                           backgroundData: backgroundData)
            }.value
            guard !Task.isCancelled else { return }
            previewImages = images
            isLoadingPreview = false
        }
        .fileImporter(isPresented: $isChoosingBackground, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url):
                loadBackground(named: url.lastPathComponent) {
                    let canAccess = url.startAccessingSecurityScopedResource()
                    defer { if canAccess { url.stopAccessingSecurityScopedResource() } }
                    return try Data(contentsOf: url)
                }
            case .failure(let error):
                backgroundError = error.localizedDescription
            }
        }
        .onChange(of: backgroundPhotoItem) { item in
            guard let item else { return }
            backgroundPhotoItem = nil
            loadBackground(named: "Photo from library") {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw ScoreReaderExportError.imageEncodingFailed
                }
                return data
            }
        }
    }

    /// Reads the chosen image off the main thread and checks that it decodes.
    private func loadBackground(named name: String, _ read: @escaping @Sendable () async throws -> Data) {
        isLoadingBackground = true
        backgroundError = nil
        Task {
            defer { isLoadingBackground = false }
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    let data = try await read()
                    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                          CGImageSourceGetCount(source) > 0 else {
                        throw ScoreReaderExportError.imageEncodingFailed
                    }
                    return data
                }.value
                draft.videoBackgroundImageData = data
                draft.videoBackgroundImageName = name
                previewRevision += 1
            } catch {
                backgroundError = "That image could not be opened. \(error.localizedDescription)"
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
            // Photos first; most backgrounds come from the camera roll.
            PhotosPicker(selection: $backgroundPhotoItem, matching: .images, photoLibrary: .shared()) {
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
            Button("Choose from Files") {
                isChoosingBackground = true
            }
            .font(.caption)
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
    private static let accent = UIColor(red: 0.36, green: 0.62, blue: 1.0, alpha: 1)

    static func makeImages(page: ScorePage?, style: ScoreVideoStyle, title: String, composer: String,
                           backgroundData: Data?) -> ScoreReaderVideoPreviewImages {
        let size = style == .pagesPortrait ? CGSize(width: 360, height: 640) : CGSize(width: 640, height: 360)
        let thumbnail = backgroundData.flatMap { downsample($0, maximumPixelSize: 960) }
        guard let page else { return ScoreReaderVideoPreviewImages(backgroundThumbnail: thumbnail) }
        guard style == .scrolling || style == .scrollingPhoto else {
            return ScoreReaderVideoPreviewImages(paper: pageImage(page: page, size: size), backgroundThumbnail: thumbnail)
        }
        guard let frame = ScrollingFrame(page: page, size: size) else {
            return ScoreReaderVideoPreviewImages(backgroundThumbnail: thumbnail)
        }
        let paper = frame.paperImage(title: title, composer: composer)
        let photo = thumbnail.flatMap { frame.photoImage(title: title, composer: composer, background: $0) }
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

    private struct PageSource {
        let pdf: CGPDFPage?
        let raster: UIImage?
        let size: CGSize

        init(page: ScorePage) {
            pdf = page.pdfData.flatMap { CGDataProvider(data: $0 as CFData) }.flatMap(CGPDFDocument.init)?.page(at: 1)
            raster = pdf == nil ? page.imageData.flatMap { downsample($0, maximumPixelSize: 1600) } : nil
            size = pdf?.getBoxRect(.mediaBox).size ?? raster?.size ?? CGSize(width: 612, height: 792)
        }

        /// Draws the page region `crop` (page points, top-left origin) into
        /// `rect` of a UIKit context, clipped to `clip`.
        func draw(_ crop: CGRect, in rect: CGRect, clip: CGRect, context: CGContext) {
            let scale = rect.width / max(crop.width, 1)
            context.saveGState()
            context.clip(to: clip)
            if let pdf {
                let box = pdf.getBoxRect(.mediaBox)
                context.translateBy(x: rect.minX, y: rect.maxY)
                context.scaleBy(x: scale, y: -scale)
                context.translateBy(x: -box.minX - crop.minX, y: -box.minY - (size.height - crop.maxY))
                context.drawPDFPage(pdf)
            } else if let raster {
                raster.draw(in: CGRect(x: rect.minX - crop.minX * scale, y: rect.minY - crop.minY * scale,
                                       width: size.width * scale, height: size.height * scale))
            }
            context.restoreGState()
        }
    }

    private static func pageImage(page: ScorePage, size: CGSize) -> UIImage {
        let source = PageSource(page: page)
        return renderer(size: size, opaque: true).image { rendererContext in
            UIColor.white.setFill()
            rendererContext.fill(CGRect(origin: .zero, size: size))
            let area = CGRect(origin: .zero, size: size).insetBy(dx: 20, dy: 16)
            let scale = min(area.width / source.size.width, area.height / source.size.height)
            let rect = CGRect(x: (size.width - source.size.width * scale) / 2, y: (size.height - source.size.height * scale) / 2,
                              width: source.size.width * scale, height: source.size.height * scale)
            source.draw(CGRect(origin: .zero, size: source.size), in: rect, clip: rect, context: rendererContext.cgContext)
        }
    }

    private static func renderer(size: CGSize, opaque: Bool) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = opaque
        return UIGraphicsImageRenderer(size: size, format: format)
    }

    /// One frame of the scrolling video, drawn from the displayed page's first
    /// system: the moment the cursor reaches the middle, before the score
    /// starts to move. Proportions follow `ScoreVideoScrollingPainter` at 1080p.
    private struct ScrollingFrame {
        let size: CGSize
        let notation: UIImage
        let contentTop: CGFloat
        let contentBottom: CGFloat
        let band: CGRect
        let cursorX: CGFloat

        init?(page: ScorePage, size: CGSize) {
            let source = PageSource(page: page)
            let systems = page.layoutMarkers.compactMap { marker -> CGRect? in
                guard case .system = marker.kind else { return nil }
                let rect = marker.normalizedRect
                return CGRect(x: CGFloat(rect.x) * source.size.width, y: CGFloat(rect.y) * source.size.height,
                              width: CGFloat(rect.width) * source.size.width, height: CGFloat(rect.height) * source.size.height)
            }.sorted { $0.minY < $1.minY }
            guard let system = systems.first, system.width > 0, system.height > 0 else { return nil }
            let unit = size.height / 1080
            // Staves fill 59% of the height, starting 19% down, as in the video.
            let scale = min(2.2 * 1.7 * unit, size.height * 0.59 / system.height)
            // Lyrics and markings around the staves, stopping short of the next system.
            let below = systems.dropFirst().first.map { ($0.minY - system.maxY) * 0.6 } ?? system.height * 0.4
            let crop = CGRect(x: system.minX, y: system.minY - system.height * 0.15,
                              width: system.width, height: system.height * 1.15 + max(below, 0))
            let origin = CGPoint(x: size.width * 0.09, y: size.height * 0.19 - system.height * 0.15 * scale)
            let rect = CGRect(x: origin.x, y: origin.y, width: crop.width * scale, height: crop.height * scale)
            band = CGRect(x: 0, y: rect.minY, width: size.width, height: rect.height)
            contentTop = size.height * 0.19
            contentBottom = contentTop + system.height * scale
            self.size = size
            cursorX = (size.width * 0.5).rounded()
            notation = ScoreReaderVideoPreviewRenderer.renderer(size: size, opaque: true).image { rendererContext in
                UIColor.white.setFill()
                rendererContext.fill(CGRect(origin: .zero, size: size))
                source.draw(crop, in: rect, clip: rect, context: rendererContext.cgContext)
            }
        }

        func paperImage(title: String, composer: String) -> UIImage {
            let unit = size.height / 1080
            return ScoreReaderVideoPreviewRenderer.renderer(size: size, opaque: true).image { rendererContext in
                let context = rendererContext.cgContext
                notation.draw(at: .zero)
                // Played music is dimmed; the line fades out at both edges.
                let dimEnd = cursorX - 28 * unit
                UIColor.white.withAlphaComponent(0.42).setFill()
                context.fill(CGRect(x: 0, y: band.minY, width: dimEnd, height: band.height))
                fade(context, from: 0.42, to: 0, in: CGRect(x: dimEnd, y: band.minY, width: 24 * unit, height: band.height))
                fade(context, from: 1, to: 0, in: CGRect(x: 0, y: band.minY, width: 110 * unit, height: band.height))
                fade(context, from: 0, to: 1, in: CGRect(x: size.width - 110 * unit, y: band.minY, width: 110 * unit, height: band.height))
                drawOverlays(context, title: title, composer: composer, ink: UIColor(red: 0.12, green: 0.14, blue: 0.18, alpha: 1),
                             cursor: ScoreReaderVideoPreviewRenderer.accent,
                             track: UIColor.black.withAlphaComponent(0.06), progress: ScoreReaderVideoPreviewRenderer.accent)
            }
        }

        func photoImage(title: String, composer: String, background: UIImage) -> UIImage? {
            guard let backgroundCGImage = background.cgImage, let notationCGImage = notation.cgImage else { return nil }
            let bounds = CGRect(origin: .zero, size: size)
            let photo = CIImage(cgImage: backgroundCGImage)
            let fill = max(size.width / photo.extent.width, size.height / photo.extent.height)
            let scaled = photo.transformed(by: CGAffineTransform(scaleX: fill, y: fill))
            let centered = scaled.transformed(by: CGAffineTransform(translationX: (size.width - scaled.extent.width) / 2,
                                                                    y: (size.height - scaled.extent.height) / 2))
            let blurred = centered.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 12]).cropped(to: bounds)
            let dim = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0.52)).cropped(to: bounds).composited(over: blurred)
            // Black engraving on paper becomes white ink with matching antialiasing.
            let ink = CIImage(cgImage: notationCGImage).applyingFilter("CIColorInvert").applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
                "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0)
            ])
            guard let base = ScoreReaderVideoPreviewRenderer.imageContext.createCGImage(ink.composited(over: dim), from: bounds) else { return nil }
            return ScoreReaderVideoPreviewRenderer.renderer(size: size, opaque: true).image { rendererContext in
                UIImage(cgImage: base).draw(at: .zero)
                drawOverlays(rendererContext.cgContext, title: title, composer: composer, ink: .white, cursor: .white,
                             track: UIColor.white.withAlphaComponent(0.12), progress: .white)
            }
        }

        private func fade(_ context: CGContext, from start: CGFloat, to end: CGFloat, in rect: CGRect) {
            let colors = [UIColor.white.withAlphaComponent(start).cgColor, UIColor.white.withAlphaComponent(end).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
            context.saveGState()
            context.clip(to: rect)
            context.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: 0), end: CGPoint(x: rect.maxX, y: 0), options: [])
            context.restoreGState()
        }

        /// Title, cursor and progress bar, as the video draws them.
        private func drawOverlays(_ context: CGContext, title: String, composer: String, ink: UIColor, cursor: UIColor,
                                  track: UIColor, progress: UIColor) {
            let unit = size.height / 1080
            // Cursor: a soft glow and a thin centre line, tapering above and below the staves.
            let taper = 84 * unit
            let top = contentTop - taper
            let height = contentBottom - contentTop + 2 * taper
            let halfWidth = 70 * unit
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            cursor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            let rows = max(1, Int(height.rounded()))
            for row in 0..<rows {
                let distance = min(CGFloat(row), CGFloat(rows - 1 - row))
                let t = min(1, distance / taper)
                let vertical = t * t * (3 - 2 * t)
                for column in -Int(halfWidth)...Int(halfWidth) {
                    let d = abs(CGFloat(column)) / unit
                    let value = min(1, (0.16 * exp(-pow(d / 38, 2)) + 0.45 * exp(-pow(d / 1.15, 2))) * vertical)
                    guard value > 0.004 else { continue }
                    context.setFillColor(red: red, green: green, blue: blue, alpha: value)
                    context.fill(CGRect(x: cursorX + CGFloat(column), y: top + CGFloat(row), width: 1, height: 1))
                }
            }

            // Title and composer centred above the music.
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedComposer = composer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedTitle.isEmpty {
                let centered = NSMutableParagraphStyle()
                centered.alignment = .center
                centered.lineBreakMode = .byTruncatingTail
                func text(_ string: String, size points: CGFloat, alpha: CGFloat) -> NSAttributedString {
                    let font = UIFont(name: "Edwin-Roman", size: points * unit) ?? UIFont(name: "Times New Roman", size: points * unit)
                        ?? UIFont.systemFont(ofSize: points * unit)
                    return NSAttributedString(string: string, attributes: [
                        .font: font, .foregroundColor: ink.withAlphaComponent(alpha), .paragraphStyle: centered
                    ])
                }
                let titleText = text(trimmedTitle, size: 40, alpha: 1)
                let composerText = text(trimmedComposer, size: 24, alpha: ink == .white ? 0.78 : 0.6)
                let titleHeight = ceil(titleText.size().height)
                let composerHeight = trimmedComposer.isEmpty ? 0 : ceil(composerText.size().height)
                let blockHeight = titleHeight + (trimmedComposer.isEmpty ? 0 : 6 * unit + composerHeight)
                let top = max(40 * unit, (contentTop - blockHeight) / 2)
                let width = size.width - 160 * unit
                titleText.draw(in: CGRect(x: 80 * unit, y: top, width: width, height: titleHeight))
                if !trimmedComposer.isEmpty {
                    composerText.draw(in: CGRect(x: 80 * unit, y: top + titleHeight + 6 * unit, width: width, height: composerHeight))
                }
            }

            let barHeight = max(2, 6 * unit)
            track.setFill()
            context.fill(CGRect(x: 0, y: size.height - barHeight, width: size.width, height: barHeight))
            progress.setFill()
            context.fill(CGRect(x: 0, y: size.height - barHeight, width: size.width * 0.3, height: barHeight))
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
