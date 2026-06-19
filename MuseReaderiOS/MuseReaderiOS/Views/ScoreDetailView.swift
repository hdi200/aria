//
//  ScoreDetailView.swift
//  MuseReaderiOS
//
//

import SwiftUI
import UIKit

struct ScoreDetailView: View {
    @ObservedObject var model: MuseReaderAppModel
    let session: ScoreSession

    @State private var readerPresentation: ReaderPresentation?
    @State private var exportedMIDIFile: SharedExportFile?
    @State private var exportErrorMessage: String?
    @State private var isPreparingMIDIExport = false
    @State private var editableMetadata = ScoreEditableMetadata()
    @State private var isEditingMetadataPresented = false
    @State private var isSavingMetadata = false
    @State private var metadataSaveErrorMessage: String?

    private var canOpenReader: Bool {
        session.pageCount > 0
    }

    private var canExportPlaybackMIDI: Bool {
        session.capabilities.supportsPlayback && session.liveRenderSession != nil
    }

    private var canEditMetadata: Bool {
        session.capabilities.supportsEditing && session.liveRenderSession != nil
    }

    var body: some View {
        contentView
            .sheet(item: $exportedMIDIFile, content: shareSheet)
            .sheet(isPresented: $isEditingMetadataPresented, content: metadataEditorSheet)
            .alert("Playback Export Error", isPresented: exportErrorIsPresented, actions: exportErrorActions, message: exportErrorMessageView)
            .alert("Could Not Save Score Info", isPresented: metadataSaveErrorIsPresented, actions: metadataSaveErrorActions, message: metadataSaveErrorMessageView)
    }

    private var contentView: some View {
        SwiftUI.ScrollView(.vertical, showsIndicators: true) {
            detailSections
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.96, blue: 0.93),
                    Color(red: 0.91, green: 0.89, blue: 0.84)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .navigationTitle(session.document.primaryTitle)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $readerPresentation) { presentation in
            ScoreReaderView(session: session, initialPageIndex: presentation.startPageIndex)
        }
    }

    private var detailSections: some View {
        VStack(alignment: .leading, spacing: 28) {
            ScoreHeroSection(
                session: session,
                openReaderAction: canOpenReader ? { openReader(at: session.coverPage?.index ?? 0) } : nil,
                editInfoAction: canEditMetadata ? { presentMetadataEditor() } : nil,
                exportMIDIAction: canExportPlaybackMIDI ? { exportPlaybackMIDI() } : nil,
                isSavingMetadata: isSavingMetadata,
                isPreparingMIDIExport: isPreparingMIDIExport
            )

            ScorePreviewStripSection(
                session: session,
                openPageAction: { pageIndex in
                    openReader(at: pageIndex)
                }
            )

            ScoreCapabilitiesSection(session: session)
            ScoreMetadataSection(
                document: session.document,
                editInfoAction: canEditMetadata ? { presentMetadataEditor() } : nil
            )
            ScorePackageContentsSection(entries: session.document.packageEntries)
            ScoreSourceSection(excerpt: session.document.scoreExcerpt)
        }
        .padding(28)
    }

    private func shareSheet(for export: SharedExportFile) -> some View {
        ShareSheetView(activityItems: [export.url])
    }

    private func exportErrorActions() -> some View {
        Button("OK", role: .cancel) {}
    }

    private func exportErrorMessageView() -> some View {
        Text(exportErrorMessage ?? "Aria could not export MIDI for this score.")
    }

    private func openReader(at pageIndex: Int) {
        guard canOpenReader else {
            return
        }

        readerPresentation = ReaderPresentation(startPageIndex: pageIndex)
    }

    private func exportPlaybackMIDI() {
        guard let liveRenderSession = session.liveRenderSession, !isPreparingMIDIExport else {
            return
        }

        isPreparingMIDIExport = true
        exportErrorMessage = nil

        Task {
            do {
                let midiData = try await liveRenderSession.playbackMIDIData()
                let exportedURL = try Self.writePlaybackMIDIFile(
                    midiData,
                    preferredBaseName: session.document.primaryTitle
                )

                await MainActor.run {
                    exportedMIDIFile = SharedExportFile(url: exportedURL)
                    isPreparingMIDIExport = false
                }
            } catch {
                await MainActor.run {
                    exportErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    isPreparingMIDIExport = false
                }
            }
        }
    }

    private func presentMetadataEditor() {
        editableMetadata = ScoreEditableMetadata(document: session.document)
        metadataSaveErrorMessage = nil
        isEditingMetadataPresented = true
    }

    private func saveEditedMetadata() {
        guard canEditMetadata, !isSavingMetadata else {
            return
        }

        isSavingMetadata = true
        metadataSaveErrorMessage = nil
        let metadataToSave = editableMetadata

        Task {
            do {
                try await model.saveMetadata(metadataToSave, for: session)
                await MainActor.run {
                    isSavingMetadata = false
                    isEditingMetadataPresented = false
                }
            } catch {
                await MainActor.run {
                    metadataSaveErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    isSavingMetadata = false
                }
            }
        }
    }

    private var exportErrorIsPresented: Binding<Bool> {
        Binding(
            get: { exportErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    exportErrorMessage = nil
                }
            }
        )
    }

    private var metadataSaveErrorIsPresented: Binding<Bool> {
        Binding(
            get: { metadataSaveErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    metadataSaveErrorMessage = nil
                }
            }
        )
    }

    private func metadataSaveErrorActions() -> some View {
        Button("OK", role: .cancel) {}
    }

    private func metadataSaveErrorMessageView() -> some View {
        Text(metadataSaveErrorMessage ?? "Aria could not save these score details.")
    }

    private func metadataEditorSheet() -> some View {
        NavigationStack {
            Form {
                Section("Title Page") {
                    TextField("Title", text: $editableMetadata.title)
                    TextField("Subtitle", text: $editableMetadata.subtitle)
                }

                Section("Credits") {
                    TextField("Composer", text: $editableMetadata.composer)
                    TextField("Arranger", text: $editableMetadata.arranger)
                    TextField("Lyricist", text: $editableMetadata.lyricist)
                }

                Section {
                    Text("These changes save back to Aria’s imported library copy and reopen the live score session.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Score Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isEditingMetadataPresented = false
                    }
                    .disabled(isSavingMetadata)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isSavingMetadata ? "Saving…" : "Save") {
                        saveEditedMetadata()
                    }
                    .disabled(isSavingMetadata)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private static func writePlaybackMIDIFile(_ midiData: Data, preferredBaseName: String) throws -> URL {
        let sanitizedBaseName = preferredBaseName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmptyOrFallback("Aria Export")

        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AriaExports", isDirectory: true)

        try FileManager.default.createDirectory(
            at: exportDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let exportURL = exportDirectory.appendingPathComponent("\(sanitizedBaseName).mid")
        if FileManager.default.fileExists(atPath: exportURL.path) {
            try FileManager.default.removeItem(at: exportURL)
        }

        try midiData.write(to: exportURL, options: .atomic)
        return exportURL
    }
}

private enum ScoreDetailPalette {
    static let accent = Color(red: 0.75, green: 0.28, blue: 0.19)
    static let accentSoft = Color(red: 0.96, green: 0.91, blue: 0.86)
    static let ink = Color(red: 0.18, green: 0.13, blue: 0.09)
    static let mutedInk = Color(red: 0.40, green: 0.31, blue: 0.22)
}

private struct ScoreHeroSection: View {
    let session: ScoreSession
    let openReaderAction: (() -> Void)?
    let editInfoAction: (() -> Void)?
    let exportMIDIAction: (() -> Void)?
    let isSavingMetadata: Bool
    let isPreparingMIDIExport: Bool

    private var heroImage: UIImage? {
        session.coverPage?.image ?? session.document.previewImage
    }

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    ScoreHeroChip(text: session.document.format.rawValue.uppercased(), symbol: "music.note.list")
                    ScoreHeroChip(text: session.renderPipeline.summaryLabel, symbol: "sparkles.rectangle.stack")

                    if let version = session.document.museScoreVersion?.trimmedToNil {
                        ScoreHeroChip(text: "MuseScore \(version)", symbol: "music.note")
                    }
                }

                Text(session.document.primaryTitle)
                    .font(.system(size: 42, weight: .bold, design: .serif))
                    .foregroundStyle(ScoreDetailPalette.ink)

                if let subtitle = session.document.subtitle?.trimmedToNil {
                    Text(subtitle)
                        .font(.title3)
                        .foregroundStyle(ScoreDetailPalette.mutedInk)
                }

                Text(session.renderPipeline.detailText)
                    .font(.body)
                    .foregroundStyle(ScoreDetailPalette.mutedInk)
                    .frame(maxWidth: 560, alignment: .leading)

                HStack(spacing: 16) {
                    ScoreHeroMetric(value: "\(session.pageCount)", label: session.pageCount == 1 ? "page" : "pages")
                    ScoreHeroMetric(value: "\(session.document.partCount)", label: session.document.partCount == 1 ? "part" : "parts")
                    ScoreHeroMetric(value: session.capabilities.supportsLivePageRendering ? "Live" : "Preview", label: "render path")
                }

                if openReaderAction != nil || editInfoAction != nil || exportMIDIAction != nil {
                    HStack(spacing: 12) {
                        if let openReaderAction {
                            Button("Open Reader", systemImage: "arrow.up.left.and.arrow.down.right", action: openReaderAction)
                                .buttonStyle(.borderedProminent)
                                .tint(ScoreDetailPalette.accent)
                        }

                        if let editInfoAction {
                            Button(action: editInfoAction) {
                                if isSavingMetadata {
                                    Label("Saving Info", systemImage: "square.and.pencil")
                                } else {
                                    Label("Edit Info", systemImage: "square.and.pencil")
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(ScoreDetailPalette.accent)
                            .disabled(isSavingMetadata)
                        }

                        if let exportMIDIAction {
                            Button(action: exportMIDIAction) {
                                if isPreparingMIDIExport {
                                    Label("Preparing MIDI", systemImage: "arrow.down.circle")
                                } else {
                                    Label("Export MIDI", systemImage: "square.and.arrow.up")
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(ScoreDetailPalette.accent)
                            .disabled(isPreparingMIDIExport)
                        }
                    }
                    .padding(.top, 6)
                }
            }

            Spacer(minLength: 0)

            ScoreHeroCover(image: heroImage, format: session.document.format)
                .frame(width: 290)
        }
        .padding(28)
        .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.04), radius: 18, y: 10)
    }
}

private struct ScoreHeroChip: View {
    let text: String
    let symbol: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ScoreDetailPalette.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(ScoreDetailPalette.accentSoft, in: Capsule())
    }
}

private struct ScoreHeroMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(.title2, design: .serif).weight(.bold))
                .foregroundStyle(ScoreDetailPalette.ink)
            Text(label.uppercased())
                .font(.caption.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 88, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct ScoreHeroCover: View {
    let image: UIImage?
    let format: ScoreFileFormat

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white)

            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        RoundedRectangle(cornerRadius: 999, style: .continuous)
                            .fill(Color(red: 0.93, green: 0.89, blue: 0.82))
                            .frame(width: 112, height: 116)
                            .overlay {
                                Image(systemName: "music.note")
                                    .font(.system(size: 34, weight: .bold))
                                    .foregroundStyle(ScoreDetailPalette.accent)
                            }

                        ForEach(0..<6, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 999, style: .continuous)
                                .fill(Color.black.opacity(index == 0 ? 0.10 : 0.06))
                                .frame(width: index.isMultiple(of: 2) ? 180 : 150, height: 8)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.98, green: 0.97, blue: 0.94),
                                Color(red: 0.93, green: 0.90, blue: 0.85)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

            Text(format.rawValue.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(ScoreDetailPalette.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(ScoreDetailPalette.accentSoft, in: Capsule())
                .padding(18)
        }
        .aspectRatio(0.74, contentMode: .fit)
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.06), radius: 16, y: 10)
    }
}

private struct ScorePreviewStripSection: View {
    let session: ScoreSession
    let openPageAction: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeadingView(title: "Session Pages")

            if session.previewPages.isEmpty {
                LiveRenderingCallout(
                    title: session.pageCount > 0 ? "Live reader is ready" : "No pages available yet",
                    detail: session.pageCount > 0
                        ? "This score does not have cached preview pages, but Aria can still open the score and render pages directly from the live session."
                        : session.renderPipeline.detailText,
                    buttonTitle: session.pageCount > 0 ? "Open Reader" : nil,
                    buttonAction: session.pageCount > 0 ? { openPageAction(0) } : nil
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
                        ForEach(session.previewPages) { page in
                            ScorePreviewCard(
                                page: page,
                                openAction: { openPageAction(page.index) }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

private struct ScorePreviewCard: View {
    let page: ScorePage
    let openAction: () -> Void

    var body: some View {
        Button(action: openAction) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white)

                    if let image = page.image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.white)
                            .overlay {
                                VStack(spacing: 10) {
                                    Image(systemName: "doc.text.magnifyingglass")
                                        .font(.system(size: 28, weight: .light))
                                    Text(page.title)
                                        .font(.headline)
                                }
                                .foregroundStyle(ScoreDetailPalette.mutedInk)
                            }
                    }

                    Text("Page \(page.index + 1)")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.94), in: Capsule())
                        .padding(14)
                }
                .frame(width: 240, height: 320)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.black.opacity(0.05), lineWidth: 1)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(page.source.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ScoreDetailPalette.ink)

                    Text("Open this page in the reader")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct LiveRenderingCallout: View {
    let title: String
    let detail: String
    let buttonTitle: String?
    let buttonAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.title3)
                    .foregroundStyle(ScoreDetailPalette.accent)

                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(ScoreDetailPalette.ink)
            }

            Text(detail)
                .font(.body)
                .foregroundStyle(ScoreDetailPalette.mutedInk)

            if let buttonTitle, let buttonAction {
                Button(buttonTitle, systemImage: "arrow.up.left.and.arrow.down.right", action: buttonAction)
                    .buttonStyle(.borderedProminent)
                    .tint(ScoreDetailPalette.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

private struct ScoreCapabilitiesSection: View {
    let session: ScoreSession

    private let columns = [
        GridItem(.adaptive(minimum: 220), spacing: 16)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeadingView(title: "Session Capabilities")

            LazyVGrid(columns: columns, spacing: 16) {
                CapabilityCard(
                    title: "Package Inspection",
                    isAvailable: session.capabilities.supportsPackageInspection,
                    detail: "Aria reads MuseScore archives and XML directly, including metadata, root score selection, package entries, and embedded previews."
                )

                CapabilityCard(
                    title: "Live Page Rendering",
                    isAvailable: session.capabilities.supportsLivePageRendering,
                    detail: session.capabilities.supportsLivePageRendering
                        ? "Pages are rendered on demand from the reusable MuseScore engraving core instead of being fully materialized up front."
                        : "This score is currently limited to embedded preview assets until the live render session is available."
                )

                CapabilityCard(
                    title: "Playback",
                    isAvailable: session.capabilities.supportsPlayback,
                    detail: session.capabilities.supportsPlayback
                        ? "Playback is available from this same live score session through MuseScore playback events and the native iPad audio stream."
                        : "Planned. Playback will attach to this same open score session once the engine layer is exposed."
                )

                CapabilityCard(
                    title: "Editing",
                    isAvailable: session.capabilities.supportsEditing,
                    detail: session.capabilities.supportsEditing
                        ? "Aria can now update core score information and save it back through the same live MuseScore session."
                        : "Planned. Edit commands and save-back will be layered onto the same score session after the reader is solid."
                )
            }
        }
    }
}

private struct ScoreMetadataSection: View {
    let document: ScoreDocument
    let editInfoAction: (() -> Void)?

    private let columns = [
        GridItem(.adaptive(minimum: 220), spacing: 16)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                SectionHeadingView(title: "Score Summary")

                Spacer(minLength: 0)

                if let editInfoAction {
                    Button("Edit Info", systemImage: "square.and.pencil", action: editInfoAction)
                        .buttonStyle(.bordered)
                        .tint(ScoreDetailPalette.accent)
                }
            }

            LazyVGrid(columns: columns, spacing: 16) {
                MetadataCard(title: "Composer", value: document.composer)
                MetadataCard(title: "Lyricist", value: document.lyricist)
                MetadataCard(title: "Arranger", value: document.arranger)
                MetadataCard(title: "Parts", value: "\(document.partCount)")
                MetadataCard(title: "Root Score File", value: document.rootFilePath)
                MetadataCard(title: "File Size", value: formattedFileSize)
                MetadataCard(title: "Last Modified", value: formattedDate)
                MetadataCard(title: "Package Entries", value: "\(document.packageEntries.count)")
            }
        }
    }

    private var formattedFileSize: String? {
        guard let fileSize = document.fileSize else {
            return nil
        }

        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    private var formattedDate: String? {
        guard let modificationDate = document.modificationDate else {
            return nil
        }

        return modificationDate.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct ScorePackageContentsSection: View {
    let entries: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeadingView(title: "Package Contents")

            VStack(alignment: .leading, spacing: 8) {
                ForEach(entries.prefix(30), id: \.self) { entry in
                    Text(entry)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.primary)
                }

                if entries.count > 30 {
                    Text("+ \(entries.count - 30) more")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(Color.white.opacity(0.80), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }
}

private struct ScoreSourceSection: View {
    let excerpt: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeadingView(title: "XML Excerpt")

            Text(excerpt)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(Color.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .foregroundStyle(Color.white.opacity(0.92))
        }
    }
}

private struct SectionHeadingView: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(.title2, design: .serif).weight(.bold))
            .foregroundStyle(ScoreDetailPalette.ink)
    }
}

private struct MetadataCard: View {
    let title: String
    let value: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            Text(value?.trimmedToNil ?? "—")
                .font(.headline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(Color.white.opacity(0.80), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct CapabilityCard: View {
    let title: String
    let isAvailable: Bool
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: isAvailable ? "checkmark.circle.fill" : "clock.arrow.circlepath")
                    .foregroundStyle(isAvailable ? Color.green : Color.orange)
            }
            .font(.headline)

            Text(isAvailable ? "Available" : "Planned")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            Text(detail)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.white.opacity(0.80), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct ReaderPresentation: Identifiable {
    let startPageIndex: Int

    var id: Int {
        startPageIndex
    }
}

private struct SharedExportFile: Identifiable {
    let url: URL

    var id: String {
        url.absoluteString
    }
}

private struct ShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private extension String {
    func nonEmptyOrFallback(_ fallback: String) -> String {
        trimmedToNil ?? fallback
    }
}
