//
//  ScoreScanViews.swift
//  MuseReaderiOS
//
//  The library's Scan flow: pick a source (camera, photo, PDF or image file), read it with
//  ScoreScanService while a progress sheet shows the reader's status, then import the MusicXML
//  through the normal import path and open it in the reader. iOS only.
//

#if !os(Android)
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import VisionKit

// MARK: - Controller

/// One status line from the reader; the id keeps each row in place as new lines arrive.
struct ScoreScanStatusLine: Identifiable, Equatable {
    let id: Int
    let text: String
}

/// One scan from reading to import. The library slot is reserved by the app model before the
/// source opens; this releases it (through `scanDidEnd`) when no score comes of the scan.
@MainActor
@Observable
final class ScoreScanController {
    enum Phase: Equatable {
        case reading
        case cancelling
        case importing
        case failed(message: String, canReadNotesOnly: Bool)
    }

    var isPresented = false
    private(set) var phase: Phase = .reading
    /// The reader's recent status lines, oldest first; the last one is current.
    private(set) var statusLines: [ScoreScanStatusLine] = []
    private(set) var notesOnly = false
    private(set) var startedAt = Date()
    /// Set when the score was imported; the library opens it once the sheet has closed.
    private(set) var importedSession: ScoreSession?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var input: ScoreScanInput?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var nextLineID = 0

    var isBusy: Bool {
        switch phase {
        case .reading, .cancelling, .importing:
            return isPresented
        case .failed:
            return false
        }
    }

    func start(_ input: ScoreScanInput, model: MuseReaderAppModel) {
        guard !isBusy else {
            return
        }
        self.input = input
        importedSession = nil
        notesOnly = !ScoreScanService.cloudReadingAvailable
        isPresented = true
        run(model: model)
    }

    /// After Private Cloud Compute failed or throttled: read the same pages again, notes only.
    func readNotesOnly(model: MuseReaderAppModel) {
        guard input != nil else {
            return
        }
        notesOnly = true
        run(model: model)
    }

    func cancel() {
        guard phase == .reading else {
            return
        }
        phase = .cancelling
        append("Cancelling…")
        task?.cancel()
    }

    func close() {
        task?.cancel()
        isPresented = false
    }

    /// Called when the sheet has gone: opens the imported score, or frees the reserved slot.
    func sheetDidDismiss(model: MuseReaderAppModel) {
        task?.cancel()
        task = nil
        input = nil
        if let importedSession {
            self.importedSession = nil
            model.openScannedSession(importedSession)
        } else {
            model.scanDidEnd()
        }
    }

    private func run(model: MuseReaderAppModel) {
        guard let input else {
            return
        }
        let run = UUID()
        generation = run
        phase = .reading
        startedAt = Date()
        statusLines = []
        append(input.kind == .pdf ? "Opening the PDF" : "Reading the page")
        let notesOnly = notesOnly
        // A main-actor class is Sendable; the reader drops this closure when the reading ends.
        let controller = self
        let report: @Sendable (String) -> Void = { line in
            Task { @MainActor in
                guard controller.generation == run, controller.phase == .reading else {
                    return
                }
                controller.append(line)
            }
        }

        task = Task { @MainActor [weak self] in
            do {
                let result = try await ScoreScanService.read(input, notesOnly: notesOnly, progress: report)
                try Task.checkCancellation()
                guard let self, self.generation == run else {
                    return
                }
                self.phase = .importing
                self.append(Self.summary(of: result))
                let url = try ScoreScanService.writeTemporaryMusicXML(result, input: input)
                defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
                let session = try await model.importScannedScore(at: url)
                print("Aria scan imported: pages=\(result.pageCount) chords=\(result.chordCount) title=\(result.title != nil) notesOnly=\(notesOnly)")
                self.importedSession = session
                self.isPresented = false
            } catch {
                guard let self, self.generation == run else {
                    return
                }
                if error is CancellationError || Task.isCancelled {
                    self.isPresented = false
                    return
                }
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                print("Aria scan failed: \(message)")
                self.phase = .failed(
                    message: message,
                    canReadNotesOnly: !notesOnly && ScoreScanService.isCloudFailure(error)
                )
            }
        }
    }

    private func append(_ line: String) {
        guard statusLines.last?.text != line else {
            return
        }
        nextLineID += 1
        statusLines.append(ScoreScanStatusLine(id: nextLineID, text: line))
        if statusLines.count > 40 {
            statusLines.removeFirst(statusLines.count - 40)
        }
    }

    private static func summary(of result: ScoreScanResult) -> String {
        let pages = result.pageCount == 1 ? "1 page" : "\(result.pageCount) pages"
        guard result.readChordsAndText else {
            return "Read \(pages). Opening the score"
        }
        let chords = result.chordCount == 1 ? "1 chord" : "\(result.chordCount) chords"
        return "Read \(pages) and \(chords). Opening the score"
    }
}

// MARK: - Library flow

/// Opens the scan source the app model asks for, runs the scan, and hands the score back to the
/// library. Attached to `LibraryView` on iOS.
struct LibraryScanFlow: ViewModifier {
    @Bindable var model: MuseReaderAppModel
    @State private var controller = ScoreScanController()
    @State private var isCameraPresented = false
    @State private var isPhotoPickerPresented = false
    @State private var isFilePickerPresented = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isPreparingSource = false
    @State private var sourceError: String?
    /// Unattended checks: `--aria-scan-file <path>` scans that file at launch through the same
    /// reservation, reading and import as the Scan button, skipping only the file picker.
    @State private var launchScanFile: URL? = Self.launchScanFileArgument()

    func body(content: Content) -> some View {
        content
            .task {
                guard launchScanFile != nil else {
                    return
                }
                try? await Task.sleep(for: .seconds(2))
                model.startScan(from: .files)
            }
            .onChangeCompatible(of: model.pendingScanSource) { source in
                guard let source else {
                    return
                }
                model.pendingScanSource = nil
                if let file = launchScanFile {
                    launchScanFile = nil
                    prepare { try ScoreScanService.input(fromFileAt: file) }
                    return
                }
                open(source)
            }
            .fullScreenCover(isPresented: $isCameraPresented) {
                DocumentCameraView(
                    onFinish: { pages in
                        isCameraPresented = false
                        prepare { ScoreScanService.input(fromCameraPages: pages) }
                    },
                    onCancel: {
                        isCameraPresented = false
                        model.scanDidEnd()
                    },
                    onError: { error in
                        isCameraPresented = false
                        model.scanDidEnd()
                        print("Aria scan camera error: \(error)")
                        sourceError = "The camera couldn’t start. Check that Aria may use the camera in Settings › Privacy & Security › Camera, or choose a photo or PDF instead."
                    }
                )
                .ignoresSafeArea()
            }
            .photosPicker(isPresented: $isPhotoPickerPresented, selection: $photoItem, matching: .images)
            .onChangeCompatible(of: photoItem) { item in
                guard let item else {
                    return
                }
                photoItem = nil
                loadPhoto(item)
            }
            .onChangeCompatible(of: isPhotoPickerPresented) { isPresented in
                guard !isPresented else {
                    return
                }
                // A cancelled picker leaves no selection; give a chosen photo a moment to arrive.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(600))
                    if !isPreparingSource, !controller.isPresented, photoItem == nil {
                        model.scanDidEnd()
                    }
                }
            }
            // On its own view: two file importers on one view conflict.
            .background(
                Color.clear
                    .fileImporter(
                        isPresented: $isFilePickerPresented,
                        allowedContentTypes: [.pdf, .image],
                        allowsMultipleSelection: false
                    ) { result in
                        switch result {
                        case .success(let urls):
                            guard let url = urls.first else {
                                model.scanDidEnd()
                                return
                            }
                            prepare { try ScoreScanService.input(fromFileAt: url) }
                        case .failure(let error):
                            model.scanDidEnd()
                            if (error as? CocoaError)?.code != .userCancelled {
                                sourceError = error.localizedDescription
                            }
                        }
                    }
            )
            .sheet(isPresented: $controller.isPresented, onDismiss: {
                controller.sheetDidDismiss(model: model)
            }) {
                ScoreScanProgressSheet(controller: controller, model: model)
            }
            .overlay {
                if isPreparingSource {
                    Color.black.opacity(0.05)
                        .ignoresSafeArea()
                    ProgressView("Preparing scan…")
                        .padding(.horizontal, 22)
                        .padding(.vertical, 16)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .alert("Couldn’t Scan", isPresented: sourceErrorIsPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(sourceError ?? "")
            }
    }

    private static func launchScanFileArgument() -> URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--aria-scan-file"), index + 1 < arguments.count else {
            return nil
        }
        return URL(fileURLWithPath: arguments[index + 1])
    }

    private var sourceErrorIsPresented: Binding<Bool> {
        Binding(
            get: { sourceError != nil },
            set: { if !$0 { sourceError = nil } }
        )
    }

    private func open(_ source: ScoreScanSourceKind) {
        switch source {
        case .camera:
            guard DocumentCameraView.isSupported else {
                model.scanDidEnd()
                sourceError = "Camera scanning isn’t available on this device. Choose a photo or a PDF instead."
                return
            }
            isCameraPresented = true
        case .photos:
            isPhotoPickerPresented = true
        case .files:
            isFilePickerPresented = true
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) {
        isPreparingSource = true
        Task { @MainActor in
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw ScoreScanError.invalidImage
                }
                isPreparingSource = false
                prepare { try ScoreScanService.input(fromPhotoData: data) }
            } catch {
                isPreparingSource = false
                model.scanDidEnd()
                sourceError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// Builds the reader's input off the main thread (camera pages become a PNG or a PDF), then
    /// starts the scan once any picker has finished dismissing.
    private func prepare(_ makeInput: @escaping @Sendable () throws -> ScoreScanInput) {
        isPreparingSource = true
        Task { @MainActor in
            let started = Date()
            do {
                let input = try await Task.detached(priority: .userInitiated) {
                    try makeInput()
                }.value
                let waited = Date().timeIntervalSince(started)
                if waited < 0.5 {
                    try? await Task.sleep(for: .seconds(0.5 - waited))
                }
                isPreparingSource = false
                controller.start(input, model: model)
            } catch {
                isPreparingSource = false
                model.scanDidEnd()
                sourceError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

// MARK: - Progress sheet

struct ScoreScanProgressSheet: View {
    let controller: ScoreScanController
    let model: MuseReaderAppModel

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 28)
                .padding(.horizontal, 24)

            statusLog
                .padding(.horizontal, 24)
                .padding(.top, 20)

            if controller.notesOnly, !isFailed {
                Label(
                    "Chord names, title and text need Apple Intelligence (Private Cloud Compute), so only the notes are read.",
                    systemImage: "info.circle"
                )
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(LibraryPalette.mutedInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 14)
            }

            buttons
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .background(LibraryPalette.background.ignoresSafeArea())
        .presentationDragIndicator(.hidden)
        .modifier(ScoreScanSheetSizing())
        .interactiveDismissDisabled(true)
    }

    private var isFailed: Bool {
        if case .failed = controller.phase {
            return true
        }
        return false
    }

    private var title: String {
        switch controller.phase {
        case .reading:
            return "Reading Score"
        case .cancelling:
            return "Cancelling"
        case .importing:
            return "Opening Score"
        case .failed:
            return "Couldn’t Read Score"
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isFailed ? Color.orange.opacity(0.14) : LibraryPalette.accentSoft)
                Image(systemName: isFailed ? "exclamationmark.triangle.fill" : "doc.viewfinder")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isFailed ? Color.orange : LibraryPalette.accent)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(LibraryPalette.ink)
                if !isFailed {
                    TimelineView(.periodic(from: controller.startedAt, by: 1)) { context in
                        Text(Self.elapsed(from: controller.startedAt, to: context.date))
                            .font(.system(size: 14, weight: .medium).monospacedDigit())
                            .foregroundStyle(LibraryPalette.mutedInk)
                    }
                }
            }

            Spacer(minLength: 0)

            if !isFailed {
                ProgressView()
                    .controlSize(.regular)
            }
        }
    }

    @ViewBuilder
    private var statusLog: some View {
        if case .failed(let message, let canReadNotesOnly) = controller.phase {
            VStack(alignment: .leading, spacing: 10) {
                Text(message)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(LibraryPalette.ink)
                if canReadNotesOnly {
                    Text("Apple’s model reads the chord names and text. You can try again later, or read just the notes now.")
                        .font(.system(size: 15))
                        .foregroundStyle(LibraryPalette.mutedInk)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            let lines = Array(controller.statusLines.suffix(5))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(lines) { line in
                    let isCurrent = line.id == lines.last?.id
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: isCurrent ? "circle.dotted" : "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(isCurrent ? LibraryPalette.accent : LibraryPalette.mutedInk.opacity(0.6))
                            .frame(width: 14)
                        Text(line.text)
                            .font(.system(size: 15, weight: isCurrent ? .semibold : .regular))
                            .foregroundStyle(isCurrent ? LibraryPalette.ink : LibraryPalette.mutedInk.opacity(0.75))
                            .lineLimit(2)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .padding(16)
            .background(LibraryPalette.mainBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(LibraryPalette.cardBorder, lineWidth: 1)
            }
            .animation(.easeOut(duration: 0.2), value: controller.statusLines)
        }
    }

    @ViewBuilder
    private var buttons: some View {
        switch controller.phase {
        case .reading, .cancelling:
            sheetButton("Cancel", prominent: false) {
                controller.cancel()
            }
            .disabled(controller.phase == .cancelling)
        case .importing:
            EmptyView()
        case .failed(_, let canReadNotesOnly):
            VStack(spacing: 10) {
                if canReadNotesOnly {
                    sheetButton("Read Notes Only", prominent: true) {
                        controller.readNotesOnly(model: model)
                    }
                }
                sheetButton("Close", prominent: !canReadNotesOnly) {
                    controller.close()
                }
            }
        }
    }

    private func sheetButton(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(prominent ? Color.white : LibraryPalette.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(prominent ? LibraryPalette.accent : Color.white)
                )
                .overlay {
                    if !prominent {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(LibraryPalette.cardBorder, lineWidth: 1)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Phones get a half-height sheet; on iPad (iOS 18+) the form sheet fits its content instead of
/// standing tall and mostly empty.
private struct ScoreScanSheetSizing: ViewModifier {
    func body(content: Content) -> some View {
        if AriaWindowLayout.shared.usesPhoneLayout {
            content.presentationDetents([.medium, .large])
        } else if #available(iOS 18.0, *) {
            content.presentationSizing(.form.fitted(horizontal: false, vertical: true))
        } else {
            content
        }
    }
}

// MARK: - Document camera

/// VisionKit's page scanner (edge detection and perspective correction), ported from ScoreScanner.
struct DocumentCameraView: UIViewControllerRepresentable {
    var onFinish: ([UIImage]) -> Void
    var onCancel: () -> Void
    var onError: (Error) -> Void

    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let parent: DocumentCameraView

        init(_ parent: DocumentCameraView) {
            self.parent = parent
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            let pages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            parent.onFinish(pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            parent.onError(error)
        }
    }
}
#endif
