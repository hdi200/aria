//
//  MuseReaderAppModel.swift
//  MuseReaderiOS
//
//

import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class MuseReaderAppModel: ObservableObject {
    private enum PreviewConstants {
        static let libraryThumbnailPageIndex = 0
        static let libraryThumbnailDPI = 120
        static let closeRefreshDelay: Duration = .milliseconds(700)
        static let metadataRefreshDelay: Duration = .seconds(1)
    }

    @Published var recents: [ReaderRecentDocument]
    @Published var setlistFolders: [LibrarySetlistFolder]
    @Published var currentSession: ScoreSession?
    @Published var pendingImportedSession: ScoreSession?
    @Published var isImportingPresented = false
    @Published var isCreateScorePresented = false
    @Published var isLoading = false
    @Published var errorAlert: ReaderAlert?

    private let sessionService: any ScoreSessionService
    private let documentService: MuseScoreDocumentService
    private let recentStore: RecentDocumentsStore
    private let setlistStore: LibrarySetlistStore
    private let scoreLibrary: ManagedScoreLibrary
    private var libraryPreviewRefreshTask: Task<Void, Never>?
    private var libraryPreviewRefreshGeneration = 0

    init() {
        let sessionService = MuseScoreSessionService()
        let documentService = MuseScoreDocumentService()
        let recentStore = RecentDocumentsStore()
        let setlistStore = LibrarySetlistStore()
        let scoreLibrary = ManagedScoreLibrary()
        self.sessionService = sessionService
        self.documentService = documentService
        self.recentStore = recentStore
        self.setlistStore = setlistStore
        self.scoreLibrary = scoreLibrary
        self.recents = recentStore.load()
        self.setlistFolders = setlistStore.load()
        try? scoreLibrary.prepareStorageIfNeeded()
        try? scoreLibrary.migrateLegacyLibraryIfNeeded()
        Task {
            await refreshVisibleLibrary()
        }
    }

    var supportedContentTypes: [UTType] {
        [.museScoreArchive, .museScoreXML, .compressedMusicXML, .musicXML, .xml]
    }

    private var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
        []
    }

    func startImport() {
        isImportingPresented = true
    }

    func startCreateScore() {
        isCreateScorePresented = true
    }

    func createSetlistFolder(named rawName: String) {
        guard let name = rawName.trimmedToNil else {
            return
        }

        setlistFolders.append(LibrarySetlistFolder(name: uniqueSetlistFolderName(name)))
        setlistStore.save(setlistFolders)
    }

    func renameSetlistFolder(_ folder: LibrarySetlistFolder, to rawName: String) {
        guard let name = rawName.trimmedToNil,
              let index = setlistFolders.firstIndex(where: { $0.id == folder.id })
        else {
            return
        }

        setlistFolders[index].name = uniqueSetlistFolderName(name, excluding: folder.id)
        setlistStore.save(setlistFolders)
    }

    func addScore(_ score: ReaderRecentDocument, to folder: LibrarySetlistFolder) {
        addScoreKey(score.setlistKey, to: folder)
    }

    func addScoreKey(_ scoreKey: String, to folder: LibrarySetlistFolder) {
        guard let index = setlistFolders.firstIndex(where: { $0.id == folder.id }) else {
            return
        }

        if !setlistFolders[index].scoreKeys.contains(scoreKey) {
            setlistFolders[index].scoreKeys.append(scoreKey)
            setlistStore.save(setlistFolders)
        }
    }

    func removeScore(_ score: ReaderRecentDocument, from folder: LibrarySetlistFolder) {
        guard let index = setlistFolders.firstIndex(where: { $0.id == folder.id }) else {
            return
        }

        let oldCount = setlistFolders[index].scoreKeys.count
        setlistFolders[index].scoreKeys.removeAll { key in
            key == score.setlistKey || key == score.fileReference || key == score.libraryRelativePath
        }

        if setlistFolders[index].scoreKeys.count != oldCount {
            setlistStore.save(setlistFolders)
        }
    }

    func handleImport(result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            Task {
                await openImportedDocument(at: url)
            }
        case .failure(let error):
            presentError(title: "Import Failed", error: error)
        }
    }

    func handleImportSelection(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                presentError(title: "Import Failed", message: "The Files picker did not return a score.")
                return
            }

            handleImport(result: .success(url))
        case .failure(let error):
            handleImport(result: .failure(error))
        }
    }

    func handleOpenURL(_ url: URL) {
        handleImport(result: .success(url))
    }

    func openRecent(_ recent: ReaderRecentDocument) {
        Task {
            _ = await readerSession(for: recent)
        }
    }

    func readerSession(for recent: ReaderRecentDocument) async -> ScoreSession? {
        do {
            return try await loadSession(for: recent)
        } catch {
            presentError(title: "Could Not Open Score", error: error)
            return nil
        }
    }

    func createScore(from draft: NewScoreDraft) async -> ScoreSession? {
        cancelPendingLibraryPreviewRefresh(reason: "create-score")
        isLoading = true
        defer { isLoading = false }
        var createdLibraryRelativePaths: [String] = []

        do {
            let shouldReplaceQuickTemplateInstruments =
                draft.templateChoice.replacesTemplateInstruments &&
                draft.selectedInstruments != draft.templateChoice.instruments
            let sourceTemplate = shouldReplaceQuickTemplateInstruments ? NewScoreTemplate.blank.choice : draft.templateChoice
            let managedDocument = try scoreLibrary.createDocument(fromTemplate: sourceTemplate)
            createdLibraryRelativePaths.append(managedDocument.relativeMainFilePath)
            var session = try await sessionService.openSession(at: managedDocument.canonicalURL)

            if let liveRenderSession = session.liveRenderSession, session.capabilities.supportsEditing {
                if shouldReplaceQuickTemplateInstruments {
                    _ = try await liveRenderSession.replaceInstruments(draft.selectedInstruments.map(\.instrumentID))
                }
                _ = try await liveRenderSession.resetTemplateMeasures(draft.measureCount)
                try await liveRenderSession.updateMetadata(draft.metadata)
                try await liveRenderSession.updateInitialKeySignature(draft.keySignature.keyValue)
                _ = try await liveRenderSession.updateTimeSignature(draft.timeSignature.scoreValue, fromStart: true)
                if draft.hasPickupMeasure {
                    _ = try await liveRenderSession.setFirstMeasurePickup(
                        numerator: draft.pickupNumerator,
                        denominator: draft.pickupDenominator
                    )
                }
                _ = try await liveRenderSession.setRegularMeasureCount(draft.measureCount)
                _ = try await liveRenderSession.addTempo(beatUnit: .quarter, bpm: draft.tempo)
                let packagedDocument = try scoreLibrary.packagedDocumentDestination(
                    preferredName: draft.title.trimmedToNil ?? sourceTemplate.title
                )
                try await saveSession(liveRenderSession, to: packagedDocument.canonicalURL)
                createdLibraryRelativePaths.append(packagedDocument.relativeMainFilePath)
                try? scoreLibrary.removeDocument(atRelativePath: managedDocument.relativeMainFilePath)
                createdLibraryRelativePaths.removeAll { $0 == managedDocument.relativeMainFilePath }
                session = try await sessionService.openSession(at: packagedDocument.canonicalURL)
            } else {
                throw ScoreDocumentServiceError.bridgeFailure("Aria could not package this score as .mscz because live editing is unavailable.")
            }

            currentSession = session
            guard let libraryRelativePath = try scoreLibrary.relativePath(for: session.document.url), !libraryRelativePath.isEmpty else {
                throw ManagedScoreLibraryError.invalidLocation
            }
            recents = recentStore.record(
                document: session.document,
                libraryRelativePath: libraryRelativePath,
                in: recents
            )
            return session
        } catch {
            for createdLibraryRelativePath in createdLibraryRelativePaths {
                try? scoreLibrary.removeDocument(atRelativePath: createdLibraryRelativePath)
            }
            errorAlert = nil
            presentError(title: "Could Not Create Score", error: error)
            return nil
        }
    }

    func removeRecents(at offsets: IndexSet) {
        let removed = offsets.map { recents[$0] }
        for recent in removed {
            guard let libraryRelativePath = recent.libraryRelativePath else {
                continue
            }

            try? scoreLibrary.removeDocument(atRelativePath: libraryRelativePath)
        }

        for index in offsets.sorted(by: >) {
            recents.remove(at: index)
        }
        recentStore.save(recents)
        for recent in removed {
            removeScoreFromSetlists(recent)
        }

        if removed.contains(where: { $0.fileReference == currentSession?.document.fileReference }) {
            currentSession = nil
        }
    }

    func deleteScore(_ recent: ReaderRecentDocument) {
        do {
            if let libraryRelativePath = recent.libraryRelativePath {
                try scoreLibrary.removeDocument(atRelativePath: libraryRelativePath)
            }
            removeRecentRecord(for: recent)
        } catch ManagedScoreLibraryError.missingDocument {
            removeRecentRecord(for: recent)
        } catch {
            presentError(title: "Could Not Delete Score", error: error)
        }
    }

    func refreshVisibleLibrary() async {
        do {
            let existingRecents = recents
            let refreshedRecents = try await Task.detached(priority: .utility) {
                let scoreLibrary = ManagedScoreLibrary()
                let documentService = MuseScoreDocumentService()
                try scoreLibrary.prepareStorageIfNeeded()
                let managedDocuments = try scoreLibrary.visibleScoreDocuments()
                var refreshedRecents: [ReaderRecentDocument] = []

                for managedDocument in managedDocuments {
                    guard let document = try? documentService.inspectDocument(at: managedDocument.canonicalURL) else {
                        continue
                    }

                    let existing = existingRecents.first {
                        $0.libraryRelativePath == managedDocument.relativeMainFilePath
                            || $0.fileReference == document.fileReference
                    }
                    // Always carry the existing cached preview forward (rendered or
                    // embedded). A metadata refresh must never blank a thumbnail back
                    // to default; a stale image is replaced by a fresh render the next
                    // time the score is opened/saved/closed.
                    refreshedRecents.append(ReaderRecentDocument(
                        document: document,
                        libraryRelativePath: managedDocument.relativeMainFilePath,
                        previewImageData: existing?.previewImageData,
                        importedAt: existing?.importedAt ?? document.modificationDate ?? .now,
                        lastOpened: existing?.lastOpened ?? .distantPast
                    ))
                }

                return refreshedRecents.sorted {
                    if $0.lastOpened != $1.lastOpened {
                        return $0.lastOpened > $1.lastOpened
                    }
                    return $0.importedAt > $1.importedAt
                }
            }.value

            // While the refresh ran off the main actor, a post-open thumbnail render
            // may have written a newer preview into `recents`. Overlay those before the
            // wholesale assignment so freshly rendered thumbnails aren't clobbered.
            let latestRecents = recents
            let mergedRecents = refreshedRecents.map { refreshed -> ReaderRecentDocument in
                guard let live = latestRecents.first(where: { candidate in
                    if let path = refreshed.libraryRelativePath {
                        return candidate.libraryRelativePath == path
                    }
                    return candidate.fileReference == refreshed.fileReference
                }) else {
                    return refreshed
                }

                if let livePreview = live.previewImageData, livePreview != refreshed.previewImageData {
                    return refreshed.replacingPreviewImageData(livePreview)
                }
                return refreshed
            }

            recents = mergedRecents
            recentStore.save(recents)
            pruneMissingSetlistScores()

            if let currentSession,
               !recents.contains(where: { $0.fileReference == currentSession.document.fileReference })
            {
                self.currentSession = nil
            }
        } catch {
            presentError(title: "Could Not Refresh Library", error: error)
        }
    }

    func saveMetadata(_ metadata: ScoreEditableMetadata, for session: ScoreSession) async throws {
        guard let liveRenderSession = session.liveRenderSession, session.capabilities.supportsEditing else {
            throw ScoreDocumentServiceError.bridgeFailure("This score is not editable yet.")
        }

        isLoading = true
        defer { isLoading = false }

        let url = session.document.url
        try await liveRenderSession.updateMetadata(metadata)
        try await saveSession(liveRenderSession, to: url)

        let refreshedSession = try await sessionService.openSession(at: url)
        currentSession = refreshedSession

        if let libraryRelativePath = try scoreLibrary.relativePath(for: refreshedSession.document.url) {
            recents = recentStore.record(
                document: refreshedSession.document,
                libraryRelativePath: libraryRelativePath,
                in: recents
            )
            scheduleRenderedLibraryPreviewRefresh(
                for: refreshedSession,
                libraryRelativePath: libraryRelativePath,
                delay: PreviewConstants.metadataRefreshDelay,
                reason: "metadata"
            )
        }
    }

    func refreshLibraryPreviewAfterClosing(_ session: ScoreSession) async {
        guard let libraryRelativePath = try? scoreLibrary.relativePath(for: session.document.url) else {
            return
        }

        scheduleRenderedLibraryPreviewRefresh(
            for: session,
            libraryRelativePath: libraryRelativePath,
            delay: PreviewConstants.closeRefreshDelay,
            saveBeforeRender: true,
            reason: "close"
        )
    }

    private func cancelPendingLibraryPreviewRefresh(reason: String) {
        let hadTask = libraryPreviewRefreshTask != nil
        libraryPreviewRefreshGeneration += 1
        libraryPreviewRefreshTask?.cancel()
        libraryPreviewRefreshTask = nil
        if hadTask {
            print("Aria library thumbnail refresh canceled: reason=\(reason)")
        }
    }

    private func scheduleRenderedLibraryPreviewRefresh(for session: ScoreSession,
                                                       libraryRelativePath: String,
                                                       replacingFileReference: String? = nil,
                                                       delay: Duration,
                                                       saveBeforeRender: Bool = false,
                                                       reason: String)
    {
        libraryPreviewRefreshGeneration += 1
        let generation = libraryPreviewRefreshGeneration
        libraryPreviewRefreshTask?.cancel()
        libraryPreviewRefreshTask = Task { @MainActor [weak self] in
            do {
                if delay > .zero {
                    try await Task.sleep(for: delay)
                }
            } catch {
                print("Aria library thumbnail refresh canceled during delay: file=\(session.document.url.lastPathComponent) reason=\(reason)")
                return
            }

            guard let self, !Task.isCancelled, generation == self.libraryPreviewRefreshGeneration else {
                return
            }

            if saveBeforeRender,
               let liveRenderSession = session.liveRenderSession,
               session.capabilities.supportsEditing
            {
                do {
                    try await self.saveSession(liveRenderSession, to: session.document.url)
                } catch {
                    print("Aria library thumbnail save-before-refresh failed: file=\(session.document.url.lastPathComponent) error=\(error.localizedDescription)")
                    return
                }
            }

            guard !Task.isCancelled, generation == self.libraryPreviewRefreshGeneration else {
                return
            }

            print("Aria library thumbnail refresh begin: file=\(session.document.url.lastPathComponent) reason=\(reason)")
            await self.refreshRenderedLibraryPreviewIfPossible(
                for: session,
                libraryRelativePath: libraryRelativePath,
                replacingFileReference: replacingFileReference,
                generation: generation
            )

            if generation == self.libraryPreviewRefreshGeneration {
                self.libraryPreviewRefreshTask = nil
            }
        }
    }

    private func openImportedDocument(at url: URL) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let managedDocument = try importIntoLibrary(from: url)
            let session = try await openManagedDocument(
                at: managedDocument.canonicalURL,
                libraryRelativePath: managedDocument.relativeMainFilePath
            )
            pendingImportedSession = session
        } catch {
            presentError(title: "Import Failed", error: error)
        }
    }

    func consumePendingImportedSession() {
        pendingImportedSession = nil
    }

    private func reopen(recent: ReaderRecentDocument) async {
        _ = await readerSession(for: recent)
    }

    private func removeRecentRecord(for recent: ReaderRecentDocument) {
        recents.removeAll { $0.fileReference == recent.fileReference }
        recentStore.save(recents)
        removeScoreFromSetlists(recent)

        if currentSession?.document.fileReference == recent.fileReference {
            currentSession = nil
        }
    }

    private func uniqueSetlistFolderName(_ name: String, excluding excludedID: UUID? = nil) -> String {
        let existingNames = Set(setlistFolders.compactMap { folder -> String? in
            guard folder.id != excludedID else {
                return nil
            }
            return folder.name.lowercased()
        })
        guard existingNames.contains(name.lowercased()) else {
            return name
        }

        var suffix = 2
        while existingNames.contains("\(name) \(suffix)".lowercased()) {
            suffix += 1
        }
        return "\(name) \(suffix)"
    }

    private func removeScoreFromSetlists(_ score: ReaderRecentDocument) {
        let key = score.setlistKey
        var changed = false
        for index in setlistFolders.indices {
            let oldCount = setlistFolders[index].scoreKeys.count
            setlistFolders[index].scoreKeys.removeAll { $0 == key || $0 == score.fileReference || $0 == score.libraryRelativePath }
            changed = changed || oldCount != setlistFolders[index].scoreKeys.count
        }
        if changed {
            setlistStore.save(setlistFolders)
        }
    }

    private func pruneMissingSetlistScores() {
        let validKeys = Set(recents.flatMap { recent in
            [recent.setlistKey, recent.fileReference, recent.libraryRelativePath].compactMap { $0 }
        })
        var changed = false
        for index in setlistFolders.indices {
            let oldCount = setlistFolders[index].scoreKeys.count
            setlistFolders[index].scoreKeys.removeAll { !validKeys.contains($0) }
            changed = changed || oldCount != setlistFolders[index].scoreKeys.count
        }
        if changed {
            setlistStore.save(setlistFolders)
        }
    }

    private func importIntoLibrary(from externalURL: URL) throws -> ManagedLibraryDocument {
        let startedScopedAccess = externalURL.startAccessingSecurityScopedResource()
        print("Aria import security scope: file=\(externalURL.lastPathComponent) ext=\(externalURL.pathExtension) started=\(startedScopedAccess) url=\(externalURL.path)")
        defer {
            if startedScopedAccess {
                externalURL.stopAccessingSecurityScopedResource()
                print("Aria import security scope stopped: file=\(externalURL.lastPathComponent)")
            }
        }

        do {
            let document = try scoreLibrary.importDocument(from: externalURL)
            print("Aria import succeeded: file=\(externalURL.lastPathComponent) canonical=\(document.canonicalURL.path) relative=\(document.relativeMainFilePath)")
            return document
        } catch {
            print("Aria import failed: file=\(externalURL.lastPathComponent) url=\(externalURL.path) error=\(error)")
            throw error
        }
    }

    private func presentError(title: String, error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        presentError(title: title, message: message)
    }

    private func presentError(title: String, message: String) {
        let alert = ReaderAlert(title: title, message: message)
        if isCreateScorePresented {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)
                errorAlert = alert
            }
        } else {
            errorAlert = alert
        }
    }

    private func loadSession(for recent: ReaderRecentDocument) async throws -> ScoreSession
    {
        if let currentSession, currentSession.document.fileReference == recent.fileReference {
            if let liveRenderSession = currentSession.liveRenderSession {
                do {
                    let latestReport = try await liveRenderSession.corruptionReport()
                    if latestReport != currentSession.corruptionReport {
                        let refreshedSession = currentSession.replacingCorruptionReport(latestReport)
                        self.currentSession = refreshedSession
                        print("Aria library cached session corruption report refreshed: file=\(currentSession.document.url.lastPathComponent) issues=\(latestReport.issues.count)")
                        return refreshedSession
                    }
                } catch {
                    print("Aria library cached session corruption report refresh failed: file=\(currentSession.document.url.lastPathComponent) error=\(error.localizedDescription)")
                }
            }

            return currentSession
        }

        isLoading = true
        defer { isLoading = false }

        if let libraryRelativePath = recent.libraryRelativePath {
            let libraryURL = try scoreLibrary.url(forRelativePath: libraryRelativePath)
            return try await openManagedDocument(at: libraryURL, libraryRelativePath: libraryRelativePath)
        }

        guard let bookmarkData = recent.bookmarkData else {
            await refreshVisibleLibrary()
            throw NSError(
                domain: "Aria",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Aria could not restore this score. Import it again from Files."]
            )
        }

        var isStale = false
        let resolvedURL = try URL(
            resolvingBookmarkData: bookmarkData,
            options: bookmarkResolutionOptions,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        let managedDocument = try importIntoLibrary(from: resolvedURL)
        return try await openManagedDocument(
            at: managedDocument.canonicalURL,
            libraryRelativePath: managedDocument.relativeMainFilePath,
            replacingFileReference: recent.fileReference
        )
    }

    private func openManagedDocument(at url: URL,
                                     libraryRelativePath: String,
                                     replacingFileReference: String? = nil) async throws -> ScoreSession
    {
        cancelPendingLibraryPreviewRefresh(reason: "open")
        let startedAt = Date()
        print("Aria library open begin: file=\(url.lastPathComponent) relative=\(libraryRelativePath)")
        let session = try await sessionService.openSession(at: url)
        print(String(format: "Aria library open session ready: file=%@ pages=%d elapsed=%.3fs", url.lastPathComponent, session.pageCount, Date().timeIntervalSince(startedAt)))
        currentSession = session
        print("Aria library current session assigned: file=\(url.lastPathComponent)")
        recents = recentStore.record(
            document: session.document,
            libraryRelativePath: libraryRelativePath,
            replacingFileReference: replacingFileReference,
            in: recents
        )
        return session
    }

    private func refreshRenderedLibraryPreviewIfPossible(for session: ScoreSession,
                                                         libraryRelativePath: String,
                                                         replacingFileReference: String? = nil,
                                                         generation: Int? = nil) async
    {
        if let generation, generation != libraryPreviewRefreshGeneration {
            print("Aria library thumbnail render skipped: file=\(session.document.url.lastPathComponent) reason=stale-generation")
            return
        }

        guard
            let liveRenderSession = session.liveRenderSession,
            session.pageCount > PreviewConstants.libraryThumbnailPageIndex
        else {
            return
        }

        let document = session.document

        do {
            let startedAt = Date()
            print("Aria library thumbnail render begin: file=\(document.url.lastPathComponent)")
            let renderedPage = try await liveRenderSession.renderPage(
                at: PreviewConstants.libraryThumbnailPageIndex,
                dpi: PreviewConstants.libraryThumbnailDPI
            )
            if let generation, generation != libraryPreviewRefreshGeneration {
                print("Aria library thumbnail render discarded: file=\(document.url.lastPathComponent) reason=stale-generation")
                return
            }
            let previewImageData = renderedPage.imageData ?? renderedPage.rasterizedPNGData()
            print(String(format: "Aria library thumbnail render finished: file=%@ bytes=%d elapsed=%.3fs", document.url.lastPathComponent, previewImageData?.count ?? 0, Date().timeIntervalSince(startedAt)))

            recents = recentStore.record(
                document: document,
                libraryRelativePath: libraryRelativePath,
                previewImageData: previewImageData,
                replacingFileReference: replacingFileReference,
                in: recents
            )
        } catch {
            print("Aria library thumbnail render failed: file=\(document.url.lastPathComponent) error=\(error.localizedDescription)")
            return
        }
    }

    private func saveSession(_ liveRenderSession: LiveScoreRenderSession, to url: URL) async throws {
        if let _ = try scoreLibrary.relativePath(for: url) {
            try await liveRenderSession.save(to: url)
            return
        }

        let startedScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if startedScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        try await coordinateSave(of: url) { coordinatedURL in
            try await liveRenderSession.save(to: coordinatedURL)
        }
    }

    private func coordinateSave(of url: URL,
                                perform action: @escaping @Sendable (URL) async throws -> Void) async throws {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var capturedError: Error?

        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                defer { semaphore.signal() }
                do {
                    try await action(coordinatedURL)
                } catch {
                    capturedError = error
                }
            }
            semaphore.wait()
        }

        if let coordinationError {
            throw coordinationError
        }

        if let capturedError {
            throw capturedError
        }
    }
}

struct ReaderAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

extension UTType {
    static let museScoreArchive = UTType(filenameExtension: "mscz") ?? .data
    static let museScoreXML = UTType(filenameExtension: "mscx") ?? .xml
    static let compressedMusicXML = UTType(filenameExtension: "mxl") ?? .zip
    static let musicXML = UTType(filenameExtension: "musicxml") ?? .xml
}
