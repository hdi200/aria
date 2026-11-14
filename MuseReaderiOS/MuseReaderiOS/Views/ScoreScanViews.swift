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

/// The three stages a page goes through, in the words a musician would use. The reader's own,
/// more technical status lines are mapped onto these (and still logged).
enum ScoreScanStage: Int, CaseIterable, Comparable {
    case preparing
    case detecting
    case recognizing

    var title: String {
        switch self {
        case .preparing: return "Preparing image"
        case .detecting: return "Detecting staves and measures"
        case .recognizing: return "Recognizing notes, rhythms & chords"
        }
    }

    static func < (lhs: ScoreScanStage, rhs: ScoreScanStage) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// The stage a reader status line belongs to, or nil for lines that don't move the stage.
    static func of(_ line: String) -> ScoreScanStage? {
        let text = line.lowercased()
        if text.hasPrefix("finding staff") || text.hasPrefix("finding notation") || text.hasPrefix("laying out") {
            return .detecting
        }
        if text.hasPrefix("reading the music") || text.hasPrefix("reading again") || text.hasPrefix("writing the score")
            || text.hasPrefix("checking the page") || text.hasPrefix("reading chord") || text.hasPrefix("reading title")
            || text.hasPrefix("reading staff text") || text.hasPrefix("reading the opening") {
            return .recognizing
        }
        if text.hasPrefix("reading the notes") || text.hasPrefix("loading") || text.hasPrefix("preparing") {
            return .preparing
        }
        return nil
    }
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
    /// The page being read (1-based), of `pageCount`.
    private(set) var currentPage = 1
    private(set) var pageCount = 1
    private(set) var stage: ScoreScanStage = .preparing
    /// All pages read; the reader is joining them into one score.
    private(set) var isCombining = false
    /// A passing note from the reader worth showing, such as Apple's model asking it to wait.
    private(set) var notice: String?
    private(set) var notesOnly = false
    private(set) var startedAt = Date()
    /// Set when the score was imported; the library opens it once the sheet has closed.
    private(set) var importedSession: ScoreSession?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var input: ScoreScanInput?
    @ObservationIgnored private var generation = UUID()

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
        currentPage = 1
        pageCount = max(1, input.pageCount)
        stage = .preparing
        isCombining = false
        notice = nil
        let notesOnly = notesOnly
        // A main-actor class is Sendable; the reader drops this closure when the reading ends.
        let controller = self
        let report: @Sendable (String) -> Void = { line in
            Task { @MainActor in
                guard controller.generation == run, controller.phase == .reading else {
                    return
                }
                controller.apply(line)
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
                print("Aria scan read: \(Self.summary(of: result))")
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

    /// Moves the page and stage forward from one reader status line ("Page 2 of 4: Finding staff
    /// lines"). The reader reads the next page's notes while the model reads this page's chords,
    /// so lines from an earlier page are ignored and progress never runs backwards.
    private func apply(_ line: String) {
        var text = line
        var page = currentPage
        if line.hasPrefix("Page "), let colon = line.firstIndex(of: ":") {
            let words = line[..<colon].split(separator: " ")
            if words.count == 4, let number = Int(words[1]), let total = Int(words[3]) {
                page = number
                pageCount = max(pageCount, total)
            }
            text = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        if text.lowercased().hasPrefix("combining") {
            isCombining = true
            currentPage = pageCount
            stage = .recognizing
            return
        }
        if text.lowercased().contains("throttling") {
            notice = "Apple’s model is busy. Waiting a moment, then trying again…"
            return
        }
        guard page >= currentPage, !isCombining else {
            return
        }
        if page > currentPage {
            currentPage = page
            stage = .preparing
        }
        if let next = ScoreScanStage.of(text), next > stage {
            stage = next
            notice = nil
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

/// A compact processing sheet: overall page progress, three plain stages for the current page, and
/// a quiet Cancel. Page progress is the only measure shown, because recognition time per page
/// varies too much for a meaningful percentage.
struct ScoreScanProgressSheet: View {
    let controller: ScoreScanController
    let model: MuseReaderAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 18)

            if case .failed(let message, let canReadNotesOnly) = controller.phase {
                failure(message: message, canReadNotesOnly: canReadNotesOnly)
            } else {
                Divider()
                progress
                    .padding(.vertical, 18)
                Divider()
                footnote
                    .padding(.top, 14)
                    .padding(.bottom, 16)
                if controller.phase != .importing {
                    secondaryButton(controller.phase == .cancelling ? "Cancelling…" : "Cancel") {
                        controller.cancel()
                    }
                    .disabled(controller.phase == .cancelling)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 20)
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

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isFailed ? Color.orange.opacity(0.14) : LibraryPalette.accentSoft)
                Image(systemName: isFailed ? "exclamationmark.triangle.fill" : "doc.viewfinder")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isFailed ? Color.orange : LibraryPalette.accent)
            }
            .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 3) {
                Text(isFailed ? "Couldn’t Read Score" : "Scanning Sheet Music")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(LibraryPalette.ink)
                if !isFailed {
                    TimelineView(.periodic(from: controller.startedAt, by: 1)) { context in
                        Text(subtitle(at: context.date))
                            .font(.system(size: 15, weight: .medium).monospacedDigit())
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

    private func subtitle(at date: Date) -> String {
        let pages = controller.pageCount == 1 ? "1 page" : "\(controller.pageCount) pages"
        let seconds = max(0, Int(date.timeIntervalSince(controller.startedAt)))
        return "\(pages) · \(seconds / 60):\(String(format: "%02d", seconds % 60)) elapsed"
    }

    // MARK: Progress

    private var progressTitle: String {
        if controller.phase == .importing {
            return "Opening your score"
        }
        if controller.isCombining {
            return "Putting the pages together"
        }
        if controller.pageCount == 1 {
            return "Reading your page"
        }
        return "Page \(controller.currentPage) of \(controller.pageCount)"
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(progressTitle)
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(LibraryPalette.ink)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.2), value: progressTitle)

            if controller.pageCount > 1 {
                pageBar
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(ScoreScanStage.allCases, id: \.self) { stage in
                    stageRow(stage)
                }
            }
            .padding(.top, 2)
        }
    }

    /// One segment per page, filled through the page being read. Long PDFs get a single bar.
    @ViewBuilder
    private var pageBar: some View {
        let filled = controller.isCombining || controller.phase == .importing
            ? controller.pageCount
            : controller.currentPage
        if controller.pageCount <= 12 {
            HStack(spacing: 6) {
                ForEach(1...controller.pageCount, id: \.self) { page in
                    Capsule()
                        .fill(page <= filled ? LibraryPalette.accent : LibraryPalette.divider)
                        .frame(height: 8)
                }
            }
            .animation(.easeOut(duration: 0.25), value: filled)
        } else {
            ProgressView(value: Double(filled), total: Double(controller.pageCount))
                .tint(LibraryPalette.accent)
        }
    }

    private func stageState(_ stage: ScoreScanStage) -> (done: Bool, active: Bool) {
        if controller.isCombining || controller.phase == .importing {
            return (true, false)
        }
        if stage < controller.stage {
            return (true, false)
        }
        return (false, stage == controller.stage)
    }

    private func stageRow(_ stage: ScoreScanStage) -> some View {
        let state = stageState(stage)
        return HStack(spacing: 12) {
            ZStack {
                if state.active {
                    ProgressView()
                        .controlSize(.small)
                        .tint(LibraryPalette.accent)
                } else if state.done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LibraryPalette.mutedInk.opacity(0.75))
                } else {
                    Circle()
                        .stroke(LibraryPalette.divider, lineWidth: 1.5)
                        .frame(width: 12, height: 12)
                }
            }
            .frame(width: 20, height: 20)

            Text(stage.title)
                .font(.system(size: 16, weight: state.active ? .semibold : .regular))
                .foregroundStyle(
                    state.active ? LibraryPalette.ink
                        : state.done ? LibraryPalette.mutedInk : LibraryPalette.mutedInk.opacity(0.55)
                )
        }
        .animation(.easeOut(duration: 0.2), value: state.active)
    }

    // MARK: Footnote and buttons

    private var footnote: some View {
        let text: String
        if let notice = controller.notice {
            text = notice
        } else if controller.notesOnly {
            text = "Chord names and text need Apple Intelligence, so only the notes are read. Your score will open automatically."
        } else {
            text = "Your score will open automatically when scanning finishes."
        }
        return Text(text)
            .font(.system(size: 14))
            .foregroundStyle(LibraryPalette.mutedInk)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private func failure(message: String, canReadNotesOnly: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(LibraryPalette.ink)
            if canReadNotesOnly {
                Text("Apple’s model reads the chord names and text. You can try again later, or read just the notes now.")
                    .font(.system(size: 15))
                    .foregroundStyle(LibraryPalette.mutedInk)
            }
            VStack(spacing: 10) {
                if canReadNotesOnly {
                    Button {
                        controller.readNotesOnly(model: model)
                    } label: {
                        Text("Read Notes Only")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(LibraryPalette.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                secondaryButton("Close") {
                    controller.close()
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A light grey, full-width button that doesn't compete with the progress for attention.
    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(LibraryPalette.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    LibraryPalette.mainBackground,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(LibraryPalette.divider, lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
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
