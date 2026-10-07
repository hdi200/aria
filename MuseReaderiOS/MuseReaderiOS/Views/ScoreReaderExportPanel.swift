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
import AVKit

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
            return "Scrolling score or piano"
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
    /// 9:16 for Reels and TikTok, for every layout (Pages uses its portrait style).
    var videoVertical = false
    var videoBackgroundImageData: Data? = nil
    var videoBackgroundImageName: String? = nil
    /// The built-in photo in use (`ScoreVideoBackgroundPhoto.id`), or nil for
    /// the person's own.
    var videoBackgroundPhotoID: String? = nil
    /// The person's own photo, kept while a built-in one is chosen.
    var videoCustomBackgroundData: Data? = nil

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
    @AppStorage(ScoreReaderVideoExportSheet.openedKey) private var hasOpenedVideoExport = false
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
    var exportErrorMessage: String? = nil
    /// Opens the video sheet. The reader presents it, not this popover, so it
    /// can take the full height of the screen on iPad.
    var openVideoSettingsAction: () -> Void = {}

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
                            openVideoSettingsAction()
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
                            Text(draft.format == .video ? "Video Export" : "Export")
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
            .contentShape(Rectangle())
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
                            .contentShape(Rectangle())
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
                openVideoSettingsAction()
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
                        // Until the video sheet has been opened once.
                        if format == .video && !hasOpenedVideoExport {
                            Text("New")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor, in: Capsule())
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
            .contentShape(Rectangle())
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
            openVideoSettingsAction()
        } label: {
            HStack {
                Text("Video settings")
                Spacer()
                Text(draft.videoStyle.title + (draft.videoVertical ? " · 9:16" : ""))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, isPhone ? 12 : 16)
            .frame(height: isPhone ? 42 : 54)
            .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 9))
            .overlay(panelBorder)
            .contentShape(Rectangle())
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
            .contentShape(Rectangle())
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
            .contentShape(Rectangle())
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

/// Nature photos bundled for photo backgrounds. All are CC0 (free for any use,
/// no attribution); sources are listed in VIDEO_EXPORT_HANDOFF.md.
struct ScoreVideoBackgroundPhoto: Identifiable, Sendable {
    /// The file name in Resources/VideoBackgrounds, without ".jpg".
    let id: String
    let name: String

    static let all: [ScoreVideoBackgroundPhoto] = [
        ScoreVideoBackgroundPhoto(id: "mount-fuji", name: "Mount Fuji"),
        ScoreVideoBackgroundPhoto(id: "grand-canyon", name: "Grand Canyon"),
        ScoreVideoBackgroundPhoto(id: "moonlit-fjord", name: "Moonlit fjord"),
        ScoreVideoBackgroundPhoto(id: "spruce-forest", name: "Spruce forest"),
        ScoreVideoBackgroundPhoto(id: "misty-mountains", name: "Misty mountains"),
        ScoreVideoBackgroundPhoto(id: "northern-lights", name: "Northern lights"),
        ScoreVideoBackgroundPhoto(id: "mountain-sunset", name: "Mountain sunset"),
        ScoreVideoBackgroundPhoto(id: "snowy-peaks", name: "Snowy peaks"),
        ScoreVideoBackgroundPhoto(id: "pink-bay", name: "Pink bay"),
        ScoreVideoBackgroundPhoto(id: "beach-sunset", name: "Beach sunset"),
        ScoreVideoBackgroundPhoto(id: "forest-river", name: "Forest river"),
        ScoreVideoBackgroundPhoto(id: "beech-ferns", name: "Beech and ferns"),
        ScoreVideoBackgroundPhoto(id: "blue-sky", name: "Blue sky")
    ]

    var url: URL? {
        Bundle.main.url(forResource: id, withExtension: "jpg")
            ?? Bundle.main.url(forResource: id, withExtension: "jpg", subdirectory: "VideoBackgrounds")
    }
}

struct ScoreReaderVideoExportSheet: View {
    /// Set once the sheet has been opened; the export panel's "New" badge goes away.
    static let openedKey = "VideoExport.hasOpened"
    @AppStorage(openedKey) private var hasOpenedVideoExport = false
    @Environment(\.dismiss) private var dismiss
    @State private var isChoosingPhoto = false
    @State private var backgroundPhotoItem: PhotosPickerItem?
    @State private var isLoadingBackground = false
    @State private var backgroundError: String?
    @State private var previewImage: UIImage?
    @State private var paperThumbnail: UIImage?
    @State private var photoThumbnail: UIImage?
    @State private var builtInThumbnails: [String: UIImage] = [:]
    @State private var customThumbnail: UIImage?
    @State private var pianoDarkThumbnail: UIImage?
    @State private var pianoLightThumbnail: UIImage?
    @State private var previewRevision = 0
    @State private var isLoadingPreview = true
    @State private var preferredScrollingStyle: ScoreVideoStyle = .scrolling
    @State private var preferredPianoStyle: ScoreVideoStyle = .piano
    @State private var player = AVPlayer()
    @State private var playingVideo: URL?
    @State private var isFullScreen = false
    @State private var videoDetails: [URL: String] = [:]
    @State private var availableWindowSize = CGSize.zero
    @State private var headerHeight: CGFloat = 76
    @State private var footerHeight: CGFloat = 115
    @State private var settingsControlsHeight: CGFloat = 300

    @Binding var draft: ScoreReaderExportDraft
    let isPreparingExport: Bool
    let exportProgress: Double?
    let exportErrorMessage: String?
    let exportAction: () -> Void
    let cancelAction: () -> Void
    let completedVideos: [URL]
    let resetResultsAction: () -> Void
    /// A frame of the video in the given style, drawn by the exporter.
    let renderPreview: (ScoreVideoStyle, Data?) async -> UIImage?

    private var isScrolling: Bool {
        draft.videoStyle.layout == .scrolling
    }

    private var isPiano: Bool {
        draft.videoStyle.layout == .piano
    }

    private var needsPhoto: Bool {
        draft.videoStyle.usesPhoto && draft.videoBackgroundImageData == nil
    }

    private var isTablet: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var horizontalPadding: CGFloat {
        isTablet ? 24 : 16
    }

    private var contentWidth: CGFloat {
        isTablet ? 752 : 560
    }

    private var preferredPanelSize: CGSize? {
        guard availableWindowSize.width > 96, availableWindowSize.height > 96 else { return nil }
        let width = min(800, max(580, availableWindowSize.width * 0.70), availableWindowSize.width - 48)
        let previewWidth = min(contentWidth, width - horizontalPadding * 2)
        // The preview area is 16:9 for both formats.
        let height = headerHeight + footerHeight + previewWidth * 9 / 16
            + 24 + settingsControlsHeight + 20
        return CGSize(width: width, height: min(ceil(height), availableWindowSize.height - 48))
    }

    private var previewTaskID: String {
        "\(draft.videoStyle.rawValue)-\(draft.videoVertical)-\(previewRevision)"
    }

    private var styleSummary: String {
        let aspect = draft.videoVertical ? "9:16 • Reels & TikTok" : "16:9"
        switch draft.videoStyle.layout {
        case .scrolling: return "\(aspect) • Scrolling"
        case .pages: return "\(aspect) • Pages"
        case .piano: return "\(aspect) • Piano"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
            if completedVideos.isEmpty {
                GeometryReader { geometry in
                    ScrollView {
                        column { settingsContent(compact: geometry.size.height < settingsControlsHeight + 150) }
                            .frame(idealHeight: geometry.size.height)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView { column { resultContent } }
            }
            footer
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
        }
        .background(Color(uiColor: .systemBackground).opacity(0.94))
        .background {
            ScoreReaderVideoWindowSizeReader { availableWindowSize = $0 }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .modifier(ScoreReaderVideoSheetSizing(preferredSize: preferredPanelSize))
        .presentationBackground(.regularMaterial)
        .presentationCornerRadius(26)
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(isPreparingExport)
        .onAppear {
            hasOpenedVideoExport = true
            switch draft.videoStyle.layout {
            case .scrolling: preferredScrollingStyle = draft.videoStyle
            case .pages: draft.videoVertical = draft.videoStyle == .pagesPortrait
            case .piano: preferredPianoStyle = draft.videoStyle
            }
        }
        .onDisappear { player.pause() }
        .task(id: previewTaskID) {
            isLoadingPreview = true
            let style = draft.videoStyle
            let background = draft.videoBackgroundImageData
            // The paper frame doubles as the "Score only" card.
            if isScrolling {
                let paper = await renderPreview(.scrolling, nil)
                guard !Task.isCancelled else { return }
                paperThumbnail = paper ?? paperThumbnail
                if style == .scrolling {
                    previewImage = paper
                }
            }
            if style != .scrolling, style != .piano, style != .pianoLight {
                let image = style.usesPhoto && background == nil ? nil : await renderPreview(style, background)
                guard !Task.isCancelled else { return }
                previewImage = image
            }
            // The dark and light frames double as the piano's appearance cards.
            if isPiano {
                let dark = await renderPreview(.piano, nil)
                guard !Task.isCancelled else { return }
                pianoDarkThumbnail = dark ?? pianoDarkThumbnail
                let light = await renderPreview(.pianoLight, nil)
                guard !Task.isCancelled else { return }
                pianoLightThumbnail = light ?? pianoLightThumbnail
                if style == .piano {
                    previewImage = dark
                } else if style == .pianoLight {
                    previewImage = light
                }
            }
            photoThumbnail = await Task.detached(priority: .userInitiated) {
                background.flatMap { ScoreReaderVideoThumbnail.make(from: $0, maximumPixelSize: 720) }
            }.value
            isLoadingPreview = false
        }
        .task(id: completedVideos) {
            guard let first = completedVideos.first else {
                playingVideo = nil
                player.replaceCurrentItem(with: nil)
                return
            }
            play(first)
            for url in completedVideos where videoDetails[url] == nil {
                videoDetails[url] = await Self.details(of: url)
            }
        }
        .fullScreenCover(isPresented: $isFullScreen) {
            ScoreReaderFullScreenVideo(player: player) { isFullScreen = false }
        }
        .photosPicker(isPresented: $isChoosingPhoto, selection: $backgroundPhotoItem, matching: .images, photoLibrary: .shared())
        .onChange(of: backgroundPhotoItem) { _, item in
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

    private func column<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: contentWidth)
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity)
    }

    // MARK: Header and footer

    private var header: some View {
        ZStack {
            Text(completedVideos.isEmpty ? "Video export" : "Video ready")
                .font(.title2.weight(.bold))
            HStack {
                if !completedVideos.isEmpty {
                    Button {
                        player.pause()
                        resetResultsAction()
                    } label: {
                        Label("Settings", systemImage: "chevron.left")
                            .font(.body.weight(.medium))
                    }
                    .accessibilityLabel("Back to video settings")
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 40, height: 40)
                        .background(Color(uiColor: .secondarySystemBackground), in: Circle())
                        .overlay(Circle().stroke(Color.black.opacity(0.06)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close video export")
                .disabled(isPreparingExport)
            }
        }
        .frame(maxWidth: contentWidth)
        .padding(.horizontal, horizontalPadding)
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Divider()
            Group {
                if !completedVideos.isEmpty {
                    HStack(spacing: 10) {
                        Button {
                            isFullScreen = true
                        } label: {
                            Label("Full screen", systemImage: "arrow.up.left.and.arrow.down.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(ScoreReaderVideoButtonStyle(isPrimary: false))
                        ShareLink(items: completedVideos) {
                            Label(completedVideos.count > 1 ? "Share all" : "Share", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(ScoreReaderVideoButtonStyle(isPrimary: true))
                    }
                } else if isPreparingExport {
                    let progress = exportProgress.map { min(max($0, 0), 1) }
                    VStack(spacing: 10) {
                        HStack {
                            Text(progress == nil ? "Preparing…" : "Rendering")
                            Spacer()
                            if let progress {
                                Text("\(Int((progress * 100).rounded()))%").monospacedDigit()
                            }
                        }
                        .font(.subheadline.weight(.medium))
                        ProgressView(value: progress ?? 0)
                        Text("Keep Aria open while rendering.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button(action: cancelAction) {
                            Text("Cancel").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(ScoreReaderVideoButtonStyle(isPrimary: false))
                    }
                } else {
                    VStack(spacing: 10) {
                        if let exportErrorMessage {
                            Text(exportErrorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }
                        Text("Keep Aria open while rendering.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button {
                            // A photo style without a photo asks for one instead of failing.
                            if needsPhoto {
                                isChoosingPhoto = true
                            } else {
                                exportAction()
                            }
                        } label: {
                            Text(needsPhoto ? "Choose photo" : "Render video").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(ScoreReaderVideoButtonStyle(isPrimary: true))
                        // The preview briefly switches the score's layout; wait for it.
                        .disabled(isLoadingPreview || isLoadingBackground || !draft.hasExportContent)
                    }
                }
            }
        }
        .frame(maxWidth: contentWidth)
        .padding(.horizontal, horizontalPadding)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 22)
    }

    // MARK: Settings

    private func settingsContent(compact: Bool = false) -> some View {
        ScoreReaderVideoSettingsLayout(spacing: compact ? 16 : 24) {
            preview
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: compact ? 16 : 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Format").font(.headline)
                    HStack(spacing: 14) {
                        formatCard(vertical: false, title: "Landscape · 16:9", subtitle: "YouTube", compact: compact)
                        formatCard(vertical: true, title: "Vertical · 9:16", subtitle: "Reels & TikTok", compact: compact)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Layout").font(.headline)
                    ScoreReaderVideoSegmentedControl(
                        options: [("Scrolling", ScoreVideoStyle.Layout.scrolling), ("Pages", .pages), ("Piano", .piano)],
                        selection: Binding(get: { draft.videoStyle.layout }, set: { layout in
                            guard layout != draft.videoStyle.layout else { return }
                            // Each layout remembers its own style while another is shown.
                            switch draft.videoStyle.layout {
                            case .scrolling: preferredScrollingStyle = draft.videoStyle
                            case .pages: break
                            case .piano: preferredPianoStyle = draft.videoStyle
                            }
                            switch layout {
                            case .scrolling: draft.videoStyle = preferredScrollingStyle
                            case .pages: draft.videoStyle = draft.videoVertical ? .pagesPortrait : .pagesLandscape
                            case .piano: draft.videoStyle = preferredPianoStyle
                            }
                        })
                    )
                    Group {
                        switch draft.videoStyle.layout {
                        case .scrolling: Text("A continuous score moves smoothly past the playhead.")
                        case .pages: Text("The camera follows the playing measure through the pages.")
                        case .piano: Text("Notes fall onto a piano keyboard and light each key as it plays.")
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                if isScrolling || isPiano {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text("Appearance").font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if isLoadingBackground {
                                ProgressView()
                            }
                        }
                        HStack(alignment: .top, spacing: 14) {
                            if isPiano {
                                appearanceCard(title: "Dark", selected: draft.videoStyle == .piano,
                                               height: compact ? 72 : nil) {
                                    draft.videoStyle = .piano
                                } content: {
                                    if let pianoDarkThumbnail {
                                        Image(uiImage: pianoDarkThumbnail).resizable().scaledToFill()
                                    } else {
                                        Color.black
                                    }
                                }
                                appearanceCard(title: "Light", selected: draft.videoStyle == .pianoLight,
                                               height: compact ? 72 : nil) {
                                    draft.videoStyle = .pianoLight
                                } content: {
                                    if let pianoLightThumbnail {
                                        Image(uiImage: pianoLightThumbnail).resizable().scaledToFill()
                                    } else {
                                        Color.white
                                    }
                                }
                            } else {
                                appearanceCard(title: "Score only", selected: draft.videoStyle == .scrolling,
                                               height: compact ? 72 : nil) {
                                    draft.videoStyle = .scrolling
                                } content: {
                                    if let paperThumbnail {
                                        Image(uiImage: paperThumbnail).resizable().scaledToFill()
                                    } else {
                                        Color.white
                                    }
                                }
                            }
                            appearanceCard(title: "Photo", selected: draft.videoStyle.usesPhoto,
                                           height: compact ? 72 : nil) {
                                draft.videoStyle = isPiano ? .pianoPhoto : .scrollingPhoto
                                // Start from the first built-in photo; the row below offers the rest.
                                if draft.videoBackgroundImageData == nil, let first = ScoreVideoBackgroundPhoto.all.first {
                                    selectBuiltInPhoto(first)
                                }
                            } content: {
                                if let photoThumbnail {
                                    Image(uiImage: photoThumbnail).resizable().scaledToFill()
                                } else {
                                    VStack(spacing: 6) {
                                        Image(systemName: "photo.on.rectangle").font(.title2)
                                        Text("Choose a photo").font(.footnote)
                                    }
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(Color(uiColor: .secondarySystemBackground))
                                }
                            }
                        }
                        if draft.videoStyle.usesPhoto {
                            photoRow(compact: compact)
                        }
                        if let backgroundError {
                            Text(backgroundError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                if !compact { settingsControlsHeight = height }
            }
        }
        .disabled(isPreparingExport)
    }

    /// Always a 16:9 area. Vertical video shows as a tall frame in the middle,
    /// over a blurred copy of itself.
    private var preview: some View {
        ZStack {
            Color.white
            if let previewImage {
                if draft.videoVertical {
                    // An overlay, so the filled image cannot grow the 16:9 area.
                    Color.clear
                        .overlay {
                            Image(uiImage: previewImage)
                                .resizable()
                                .scaledToFill()
                                .blur(radius: 18)
                                .opacity(0.85)
                        }
                        .clipped()
                        .transition(.opacity)
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFit()
                        .shadow(color: .black.opacity(0.12), radius: 8)
                        .transition(.opacity)
                } else {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFit()
                        .transition(.opacity)
                }
            } else if needsPhoto {
                Button {
                    isChoosingPhoto = true
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle").font(.title2)
                        Text("Choose a background photo").font(.subheadline)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .disabled(isPreparingExport || isLoadingBackground)
            } else if !isLoadingPreview {
                Label("Preview unavailable", systemImage: "doc.richtext")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if isLoadingPreview {
                ProgressView()
                    .padding(10)
                    .background(.regularMaterial, in: Circle())
            }
        }
        .animation(.easeOut(duration: 0.2), value: previewImage)
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .frame(maxWidth: .infinity, minHeight: 100)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.black.opacity(0.08)))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        .opacity(isPreparingExport ? 0.6 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Video preview, \(styleSummary)")
    }

    /// A format choice: an outline of the frame's shape, its name and where it fits.
    private func formatCard(vertical: Bool, title: String, subtitle: String, compact: Bool) -> some View {
        let selected = draft.videoVertical == vertical
        return Button {
            guard !selected else { return }
            draft.videoVertical = vertical
            if draft.videoStyle.layout == .pages {
                draft.videoStyle = vertical ? .pagesPortrait : .pagesLandscape
            }
        } label: {
            VStack(spacing: compact ? 4 : 6) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(selected ? Color.accentColor : Color.secondary, lineWidth: 2.5)
                    .frame(width: vertical ? 26 : 46, height: vertical ? 42 : 28)
                    .frame(height: compact ? 32 : 46)
                    .scaleEffect(compact ? 0.75 : 1)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? 10 : 16)
            .background(selected ? Color.accentColor.opacity(0.07) : Color(uiColor: .secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(selected ? Color.accentColor : Color.black.opacity(0.06), lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: selected)
        .accessibilityLabel("\(title), \(subtitle)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func appearanceCard<Content: View>(title: String, selected: Bool, height: CGFloat? = nil,
                                               action: @escaping () -> Void,
                                               @ViewBuilder content: () -> Content) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                content()
                    .frame(maxWidth: .infinity)
                    .frame(height: height ?? (isTablet ? 120 : 96))
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(selected ? Color.accentColor : Color.black.opacity(0.08), lineWidth: selected ? 2.5 : 1)
                    )
                Text(title)
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.accentColor : .primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Result

    private var resultContent: some View {
        let portrait = draft.videoVertical
        return VStack(alignment: .leading, spacing: 14) {
            ZStack {
                Color.black
                ScoreReaderVideoPlayerView(player: player)
            }
            .aspectRatio(portrait ? 9.0 / 16.0 : 16.0 / 9.0, contentMode: .fit)
            .frame(maxHeight: portrait ? 460 : nil)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if completedVideos.count > 1 {
                // One video per exported score or part.
                VStack(spacing: 0) {
                    ForEach(Array(completedVideos.enumerated()), id: \.element) { index, url in
                        Button {
                            play(url)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: playingVideo == url ? "play.circle.fill" : "play.circle")
                                    .foregroundStyle(playingVideo == url ? Color.accentColor : .secondary)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(url.deletingPathExtension().lastPathComponent).lineLimit(1)
                                    if let detail = videoDetails[url] {
                                        Text(detail).font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if index < completedVideos.count - 1 {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
                .background(Color(uiColor: .secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else if let url = completedVideos.first {
                VStack(alignment: .leading, spacing: 2) {
                    Text(url.lastPathComponent)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(videoDetails[url] ?? " ")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func play(_ url: URL) {
        guard playingVideo != url else { return }
        playingVideo = url
        // Play through the silent switch, like the score's own playback.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.play()
    }

    /// "0:40 · 38 MB" for a finished video.
    private static func details(of url: URL) async -> String {
        var parts: [String] = []
        if let duration = try? await AVURLAsset(url: url).load(.duration), duration.isNumeric {
            let seconds = Int(duration.seconds.rounded())
            parts.append(String(format: "%d:%02d", seconds / 60, seconds % 60))
        }
        if let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Photo choices

    /// The person's own photo first, then the built-in nature photos.
    private func photoRow(compact: Bool) -> some View {
        let size = compact ? CGSize(width: 64, height: 40) : CGSize(width: 96, height: 60)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // Tapping it again while selected chooses a different photo.
                let customSelected = draft.videoBackgroundPhotoID == nil && draft.videoBackgroundImageData != nil
                photoTile(selected: customSelected, size: size, label: "Your photo") {
                    if customSelected || draft.videoCustomBackgroundData == nil {
                        isChoosingPhoto = true
                    } else if let data = draft.videoCustomBackgroundData {
                        draft.videoBackgroundImageData = data
                        draft.videoBackgroundImageName = "Photo from library"
                        draft.videoBackgroundPhotoID = nil
                        previewRevision += 1
                    }
                } content: {
                    if let customThumbnail {
                        Image(uiImage: customThumbnail).resizable().scaledToFill()
                    } else {
                        VStack(spacing: 2) {
                            Image(systemName: "photo.badge.plus").font(compact ? .footnote : .title3)
                            if !compact {
                                Text("Your photo").font(.caption2.weight(.medium))
                            }
                        }
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.accentColor.opacity(0.08))
                    }
                }
                ForEach(ScoreVideoBackgroundPhoto.all) { photo in
                    photoTile(selected: draft.videoBackgroundPhotoID == photo.id, size: size, label: photo.name) {
                        selectBuiltInPhoto(photo)
                    } content: {
                        if let thumbnail = builtInThumbnails[photo.id] {
                            Image(uiImage: thumbnail).resizable().scaledToFill()
                        } else {
                            Color(uiColor: .secondarySystemBackground)
                        }
                    }
                }
            }
            .padding(3)
        }
        .disabled(isLoadingBackground)
        .task {
            guard builtInThumbnails.isEmpty else { return }
            for photo in ScoreVideoBackgroundPhoto.all {
                let url = photo.url
                let thumbnail = await Task.detached(priority: .userInitiated) {
                    url.flatMap { try? Data(contentsOf: $0) }
                        .flatMap { ScoreReaderVideoThumbnail.make(from: $0, maximumPixelSize: 240) }
                }.value
                builtInThumbnails[photo.id] = thumbnail
            }
        }
    }

    private func photoTile<Content: View>(selected: Bool, size: CGSize, label: String, action: @escaping () -> Void,
                                          @ViewBuilder content: () -> Content) -> some View {
        Button(action: action) {
            content()
                .frame(width: size.width, height: size.height)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(selected ? Color.accentColor : Color.black.opacity(0.08), lineWidth: selected ? 2.5 : 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func selectBuiltInPhoto(_ photo: ScoreVideoBackgroundPhoto) {
        guard draft.videoBackgroundPhotoID != photo.id else { return }
        let url = photo.url
        loadBackgroundData(named: photo.name, photoID: photo.id) {
            guard let url else { throw ScoreReaderExportError.imageEncodingFailed }
            return try Data(contentsOf: url)
        }
    }

    /// Reads a built-in photo off the main thread and makes it the background.
    private func loadBackgroundData(named name: String, photoID: String,
                                    _ read: @escaping @Sendable () throws -> Data) {
        isLoadingBackground = true
        backgroundError = nil
        Task {
            defer { isLoadingBackground = false }
            do {
                let data = try await Task.detached(priority: .userInitiated) { try read() }.value
                draft.videoBackgroundImageData = data
                draft.videoBackgroundImageName = name
                draft.videoBackgroundPhotoID = photoID
                draft.videoStyle = isPiano ? .pianoPhoto : .scrollingPhoto
                previewRevision += 1
            } catch {
                backgroundError = "That photo couldn't be loaded."
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
                draft.videoBackgroundPhotoID = nil
                draft.videoCustomBackgroundData = data
                draft.videoStyle = isPiano ? .pianoPhoto : .scrollingPhoto
                previewRevision += 1
                customThumbnail = await Task.detached(priority: .userInitiated) {
                    ScoreReaderVideoThumbnail.make(from: data, maximumPixelSize: 240)
                }.value
            } catch {
                backgroundError = "That image couldn't be opened. Try another one."
            }
        }
    }
}

/// A centered iPad panel with enough height for the preview and all settings.
private struct ScoreReaderVideoSheetSizing: ViewModifier {
    let preferredSize: CGSize?

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), UIDevice.current.userInterfaceIdiom == .pad {
            content.presentationSizing(ScoreReaderVideoPanelSizing(preferredSize: preferredSize))
        } else {
            content.presentationDetents([.large])
        }
    }
}

@available(iOS 18.0, *)
private struct ScoreReaderVideoPanelSizing: PresentationSizing {
    let preferredSize: CGSize?

    func proposedSize(for root: PresentationSizingRoot, context: PresentationSizingContext) -> ProposedViewSize {
        if let preferredSize { return ProposedViewSize(preferredSize) }
        return PagePresentationSizing.page.proposedSize(for: root, context: context)
    }
}

/// Read the presenting window, including Split View and Stage Manager resizing.
private struct ScoreReaderVideoWindowSizeReader: UIViewRepresentable {
    let onChange: (CGSize) -> Void

    func makeUIView(context: Context) -> WindowSizeView {
        let view = WindowSizeView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ view: WindowSizeView, context: Context) {
        view.onChange = onChange
        view.publishSize()
    }

    final class WindowSizeView: UIView {
        var onChange: ((CGSize) -> Void)?
        private var lastSize = CGSize.zero

        override func didMoveToWindow() {
            super.didMoveToWindow()
            publishSize()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            publishSize()
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            publishSize()
        }

        func publishSize() {
            guard let window else { return }
            let size = CGSize(width: window.bounds.width,
                              height: window.bounds.height - window.safeAreaInsets.top - window.safeAreaInsets.bottom)
            guard size != lastSize else { return }
            lastSize = size
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil else { return }
                self.onChange?(size)
            }
        }
    }
}

/// Measure the controls first and give the preview the remaining height.
private struct ScoreReaderVideoSettingsLayout: Layout {
    let spacing: CGFloat

    private func heights(proposal: ProposedViewSize, subviews: Subviews) -> (preview: CGFloat, controls: CGFloat) {
        let width = proposal.width ?? 592
        let controls = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        let remaining = proposal.height.map { max(0, $0 - controls - spacing) }
        let preview = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: remaining)).height
        return (preview, controls)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let heights = heights(proposal: proposal, subviews: subviews)
        return CGSize(width: proposal.width ?? 592, height: heights.preview + spacing + heights.controls)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let heights = heights(proposal: ProposedViewSize(bounds.size), subviews: subviews)
        subviews[0].place(at: bounds.origin, anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width, height: heights.preview))
        subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + heights.preview + spacing),
                          anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width, height: heights.controls))
    }
}

/// Two or more choices; the selected one is outlined in the accent colour.
private struct ScoreReaderVideoSegmentedControl<Value: Hashable>: View {
    let options: [(title: String, value: Value)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(.subheadline.weight(selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Color.accentColor : .primary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(uiColor: .systemBackground))
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.accentColor, lineWidth: 2))
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.easeOut(duration: 0.15), value: selection)
    }
}

private struct ScoreReaderVideoButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(isPrimary ? Color.white : Color.primary)
            .frame(height: 54)
            .background(
                isPrimary ? Color.accentColor.opacity(configuration.isPressed ? 0.8 : 1)
                    : Color(uiColor: .secondarySystemBackground).opacity(configuration.isPressed ? 0.7 : 1),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .contentShape(Rectangle())
    }
}

/// The system player inline, with its standard controls.
private struct ScoreReaderVideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = false
        controller.videoGravity = .resizeAspect
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
    }
}

/// The same player filling the screen; playback carries on where it was.
private struct ScoreReaderFullScreenVideo: View {
    let player: AVPlayer
    let closeAction: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            ScoreReaderVideoPlayerView(player: player)
                .ignoresSafeArea()
            Button(action: closeAction) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.5), in: Circle())
            }
            .accessibilityLabel("Exit full screen")
            .padding(16)
        }
        .statusBarHidden()
    }
}

/// Downsamples a chosen photo for its card.
private nonisolated enum ScoreReaderVideoThumbnail {
    static func make(from data: Data, maximumPixelSize: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
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
            .contentShape(Rectangle())
    }
}

struct ScoreReaderShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
