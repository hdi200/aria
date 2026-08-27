//
//  MuseReaderAppModel.swift
//  MuseReaderiOS
//
//

import Combine
import Foundation
import UniformTypeIdentifiers

private struct PreparedManagedScoreSession {
    let document: ManagedLibraryDocument
    let session: ScoreSession
    let sourceDocumentToRemove: ManagedLibraryDocument?
}

private enum PendingLibraryAction {
    case createScore
    case importScores([ScoreImportCandidate])
    case reopenLegacyDocument(ReaderRecentDocument)
}

private enum LibraryAdmissionError: LocalizedError {
    case unlockPresentationHandled
    case missingReservation

    var errorDescription: String? {
        switch self {
        case .unlockPresentationHandled:
            return "Unlock Aria Pro to add another score."
        case .missingReservation:
            return "Aria could not reserve room for this score. Please try again."
        }
    }
}

struct ScoreImportProgress: Equatable {
    let itemNumber: Int
    let totalCount: Int

    var message: String {
        guard totalCount > 1 else {
            return "Importing score…"
        }
        return "Importing score \(itemNumber) of \(totalCount)…"
    }
}

struct ScoreImportFailure: Equatable {
    let fileName: String
    let message: String
}

struct ScoreImportBatchOutcome {
    let totalCount: Int
    let importedCount: Int
    let failures: [ScoreImportFailure]

    var alert: ReaderAlert {
        let title: String
        let summary: String
        if failures.isEmpty {
            title = "Import Complete"
            summary = "\(importedCount) scores were imported into your library."
        } else if importedCount == 0 {
            title = "Import Failed"
            summary = "None of the \(totalCount) selected scores could be imported."
        } else {
            title = "Import Partially Complete"
            summary = "\(importedCount) of \(totalCount) scores were imported into your library."
        }

        guard !failures.isEmpty else {
            return ReaderAlert(title: title, message: summary)
        }

        let visibleFailures = failures.prefix(5).map { "\($0.fileName): \($0.message)" }
        let hiddenFailureCount = failures.count - visibleFailures.count
        let hiddenFailureMessage = hiddenFailureCount > 0 ? "\n…and \(hiddenFailureCount) more." : ""
        return ReaderAlert(
            title: title,
            message: summary + "\n\nCouldn’t import:\n" + visibleFailures.joined(separator: "\n") + hiddenFailureMessage
        )
    }
}

enum ScoreImportBatchRunner {
    @MainActor
    static func run(urls: [URL],
                    progress: (ScoreImportProgress) -> Void,
                    importDocument: (URL) async throws -> Void) async -> ScoreImportBatchOutcome
    {
        var importedCount = 0
        var failures: [ScoreImportFailure] = []

        for (index, url) in urls.enumerated() {
            progress(ScoreImportProgress(itemNumber: index + 1, totalCount: urls.count))
            do {
                try await importDocument(url)
                importedCount += 1
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                failures.append(ScoreImportFailure(fileName: url.lastPathComponent, message: message))
            }
        }

        return ScoreImportBatchOutcome(
            totalCount: urls.count,
            importedCount: importedCount,
            failures: failures
        )
    }
}

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
    @Published var importProgress: ScoreImportProgress?
    @Published var errorAlert: ReaderAlert?
    @Published private(set) var managedScoreCount = 0
    @Published var libraryAccessSheet: LibraryAccessSheet?

    let libraryAccessController: LibraryAccessController

    private let sessionService: any ScoreSessionService
    private let documentService: MuseScoreDocumentService
    private let recentStore: RecentDocumentsStore
    private let setlistStore: LibrarySetlistStore
    private let scoreLibrary: ManagedScoreLibrary
    private let recoveryStore: ScoreRecoveryStore
    private var libraryPreviewRefreshTask: Task<Void, Never>?
    private var libraryPreviewRefreshGeneration = 0
    private var didAttemptLaunchRecovery = false
    private var reservedScoreSlots = 0
    private var isCreateScoreSlotReserved = false
    private var pendingLibraryAction: PendingLibraryAction?
    private var didPresentEarlySupporterMessageThisLaunch = false

    private enum AccessUIKeys {
        static let earlySupporterMessageShown = "Aria.LibraryAccess.EarlySupporterMessageShown"
    }

    init() {
        let sessionService = MuseScoreSessionService()
        let documentService = MuseScoreDocumentService()
        let recentStore = RecentDocumentsStore()
        let setlistStore = LibrarySetlistStore()
        let scoreLibrary = ManagedScoreLibrary()
        let recoveryStore = ScoreRecoveryStore()
        let libraryAccessController = LibraryAccessController()
        self.sessionService = sessionService
        self.documentService = documentService
        self.recentStore = recentStore
        self.setlistStore = setlistStore
        self.scoreLibrary = scoreLibrary
        self.recoveryStore = recoveryStore
        self.libraryAccessController = libraryAccessController
        self.recents = recentStore.load()
        self.setlistFolders = setlistStore.load()
        try? scoreLibrary.prepareStorageIfNeeded()
        try? scoreLibrary.migrateLegacyLibraryIfNeeded()
        Task {
            await libraryAccessController.start()
            await refreshVisibleLibrary()
        }
    }

    var supportedContentTypes: [UTType] {
        [.museScoreArchive, .museScoreXML, .compressedMusicXML, .musicXML, .xml]
    }

    private var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
        []
    }

    var freeScoreLimit: Int {
        LibraryAccessPolicy.freeScoreLimit
    }

    var remainingFreeScoreSlots: Int {
        LibraryScoreAllowance(
            status: libraryAccessController.status,
            usedScoreCount: managedScoreCount,
            reservedScoreCount: reservedScoreSlots,
            freeLimit: freeScoreLimit
        ).remainingSlots
    }

    func startImport() {
        isImportingPresented = true
    }

    func startCreateScore() {
        synchronizeManagedScoreCount()
        guard reserveScoreSlots(1) else {
            pendingLibraryAction = .createScore
            libraryAccessSheet = .paywall(.createScore)
            return
        }

        isCreateScoreSlotReserved = !libraryAccessController.status.hasUnlimitedScores
        isCreateScorePresented = true
    }

    func createScoreFlowDidDismiss() {
        releaseCreateScoreReservation()
    }

    func presentUnlimitedScoresFromSettings() {
        pendingLibraryAction = nil
        libraryAccessSheet = .paywall(.settings)
    }

    func presentEarlySupporterMessageIfNeeded() {
        guard libraryAccessController.status == .unlimited(.earlySupporter),
              !didPresentEarlySupporterMessageThisLaunch,
              libraryAccessController.isUsingDevelopmentOverride
                || !UserDefaults.standard.bool(forKey: AccessUIKeys.earlySupporterMessageShown),
              libraryAccessSheet == nil,
              !isCreateScorePresented,
              !isImportingPresented
        else {
            return
        }

        didPresentEarlySupporterMessageThisLaunch = true
        if !libraryAccessController.isUsingDevelopmentOverride {
            UserDefaults.standard.set(true, forKey: AccessUIKeys.earlySupporterMessageShown)
        }
        libraryAccessSheet = .earlySupporter
    }

    func cancelPendingLibraryAction() {
        pendingLibraryAction = nil
    }

    func resumePendingLibraryActionAfterUnlock() {
        guard libraryAccessController.status.hasUnlimitedScores else {
            return
        }

        let action = pendingLibraryAction
        pendingLibraryAction = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            switch action {
            case .createScore:
                self.startCreateScore()
            case .importScores(let candidates):
                await self.beginImportingCandidates(candidates)
            case .reopenLegacyDocument(let recent):
                self.openRecent(recent)
            case nil:
                break
            }
        }
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
                await prepareImportCandidates(for: [url])
            }
        case .failure(let error):
            presentError(title: "Import Failed", error: error)
        }
    }

    func handleImportSelection(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else {
                presentError(title: "Import Failed", message: "The Files picker did not return a score.")
                return
            }

            Task {
                await prepareImportCandidates(for: urls)
            }
        case .failure(let error):
            handleImport(result: .failure(error))
        }
    }

    func handleOpenURL(_ url: URL) {
        handleImport(result: .success(url))
    }

    func confirmImportReview(_ candidates: [ScoreImportCandidate]) {
        libraryAccessSheet = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            await self.beginImportingCandidates(candidates)
        }
    }

    func unlockAndImport(_ candidates: [ScoreImportCandidate]) {
        pendingLibraryAction = .importScores(candidates)
        libraryAccessSheet = .paywall(.importScore(count: candidates.count))
    }

    func openRecent(_ recent: ReaderRecentDocument) {
        Task {
            _ = await readerSession(for: recent)
        }
    }

    func readerSession(for recent: ReaderRecentDocument) async -> ScoreSession? {
        do {
            return try await loadSession(for: recent)
        } catch LibraryAdmissionError.unlockPresentationHandled {
            return nil
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
            guard libraryAccessController.status.hasUnlimitedScores || isCreateScoreSlotReserved else {
                throw LibraryAdmissionError.missingReservation
            }
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
            synchronizeManagedScoreCount()
            releaseCreateScoreReservation()
            return session
        } catch {
            for createdLibraryRelativePath in createdLibraryRelativePaths {
                try? scoreLibrary.removeDocument(atRelativePath: createdLibraryRelativePath)
            }
            synchronizeManagedScoreCount()
            releaseCreateScoreReservation()
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
        synchronizeManagedScoreCount()
    }

    func deleteScore(_ recent: ReaderRecentDocument) {
        do {
            if let libraryRelativePath = recent.libraryRelativePath {
                try scoreLibrary.removeDocument(atRelativePath: libraryRelativePath)
            }
            removeRecentRecord(for: recent)
            synchronizeManagedScoreCount()
        } catch ManagedScoreLibraryError.missingDocument {
            removeRecentRecord(for: recent)
            synchronizeManagedScoreCount()
        } catch {
            presentError(title: "Could Not Delete Score", error: error)
        }
    }

    func refreshVisibleLibrary() async {
        do {
            if !didAttemptLaunchRecovery {
                didAttemptLaunchRecovery = true
                await restorePendingRecoverySnapshots()
            }

            let existingRecents = recents
            let refreshResult = try await Task.detached(priority: .utility) {
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

                let sortedRecents = refreshedRecents.sorted {
                    if $0.lastOpened != $1.lastOpened {
                        return $0.lastOpened > $1.lastOpened
                    }
                    return $0.importedAt > $1.importedAt
                }
                return (recents: sortedRecents, managedScoreCount: managedDocuments.count)
            }.value

            let refreshedRecents = refreshResult.recents
            managedScoreCount = refreshResult.managedScoreCount

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

    private func restorePendingRecoverySnapshots() async {
        let pendingSnapshots: [PendingScoreRecoverySnapshot]
        do {
            pendingSnapshots = try recoveryStore.pendingSnapshots()
        } catch {
            print("Aria launch recovery scan failed: error=\(error.localizedDescription)")
            return
        }

        for pendingSnapshot in pendingSnapshots {
            let sourceURL = URL(fileURLWithPath: pendingSnapshot.record.sourcePath).standardizedFileURL
            let managedRelativePath = try? scoreLibrary.relativePath(for: sourceURL)
            guard
                sourceURL.pathExtension.lowercased() == ScoreFileFormat.mscz.rawValue,
                let managedRelativePath,
                managedRelativePath.hasPrefix(ManagedScoreLibraryPaths.itemsDirectoryName + "/")
            else {
                try? recoveryStore.removeSnapshot(pendingSnapshot)
                continue
            }

            guard FileManager.default.fileExists(atPath: pendingSnapshot.snapshotURL.path) else {
                try? recoveryStore.removeSnapshot(pendingSnapshot)
                continue
            }

            let snapshotModificationDate = try? pendingSnapshot.snapshotURL
                .resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            let sourceModificationDate = try? sourceURL
                .resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate

            if let snapshotModificationDate,
               let sourceModificationDate,
               snapshotModificationDate <= sourceModificationDate
            {
                try? recoveryStore.removeSnapshot(pendingSnapshot)
                continue
            }

            do {
                print("Aria launch recovery begin: source=\(sourceURL.lastPathComponent) snapshot=\(pendingSnapshot.snapshotURL.lastPathComponent)")
                let recoverySession = try await sessionService.openSession(at: pendingSnapshot.snapshotURL)
                guard
                    recoverySession.capabilities.supportsEditing,
                    let liveRenderSession = recoverySession.liveRenderSession
                else {
                    throw ScoreDocumentServiceError.bridgeFailure("The recovery score could not be validated by the MuseScore engine.")
                }

                try await saveSession(liveRenderSession, to: sourceURL, clearsRecoverySnapshot: false)
                let validatedSession = try await sessionService.openSession(at: sourceURL)
                guard
                    validatedSession.document.format == .mscz,
                    validatedSession.capabilities.supportsEditing,
                    validatedSession.liveRenderSession != nil
                else {
                    throw ScoreDocumentServiceError.bridgeFailure("The recovered score could not be reopened safely.")
                }

                try recoveryStore.removeSnapshot(pendingSnapshot)
                print("Aria launch recovery complete: source=\(sourceURL.lastPathComponent)")
            } catch {
                print("Aria launch recovery retained snapshot: source=\(sourceURL.lastPathComponent) error=\(error.localizedDescription)")
            }
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

    private func prepareImportCandidates(for urls: [URL]) async {
        do {
            synchronizeManagedScoreCount()
            let managedDocuments = try scoreLibrary.visibleScoreDocuments()
            let documentsByName = Dictionary(
                managedDocuments.map { document in
                    (normalizedFileName(document.canonicalURL.lastPathComponent), document)
                },
                uniquingKeysWith: { first, _ in first }
            )

            let candidates = urls.map { url -> ScoreImportCandidate in
                let destinationFileName = scoreLibrary.preferredStoredFileName(for: url)
                let matchingDocument = documentsByName[normalizedFileName(destinationFileName)]
                let disposition: ScoreImportDisposition
                if let matchingDocument {
                    let existingReference = recents.first {
                        $0.libraryRelativePath == matchingDocument.relativeMainFilePath
                    }?.fileReference
                    disposition = .replace(
                        relativePath: matchingDocument.relativeMainFilePath,
                        existingFileReference: existingReference
                    )
                } else {
                    disposition = .new
                }
                return ScoreImportCandidate(
                    url: url,
                    destinationFileName: destinationFileName,
                    disposition: disposition
                )
            }

            let review = ScoreImportReview(
                candidates: candidates,
                availableNewSlots: remainingFreeScoreSlots,
                hasUnlimitedScores: libraryAccessController.status.hasUnlimitedScores
            )
            let requiresReview = review.replacementCount > 0
                || review.hasDuplicateDestinations
                || review.exceedsFreeCapacity

            if candidates.count == 1,
               candidates[0].disposition.usesNewSlot,
               review.exceedsFreeCapacity
            {
                pendingLibraryAction = .importScores(candidates)
                libraryAccessSheet = .paywall(.importScore(count: 1))
            } else if requiresReview {
                libraryAccessSheet = .importReview(review)
            } else {
                await beginImportingCandidates(candidates)
            }
        } catch {
            presentError(title: "Import Failed", error: error)
        }
    }

    private func beginImportingCandidates(_ candidates: [ScoreImportCandidate]) async {
        guard !candidates.isEmpty else {
            return
        }

        let destinationKeys = candidates.map(\.destinationKey)
        guard Set(destinationKeys).count == destinationKeys.count else {
            libraryAccessSheet = .importReview(
                ScoreImportReview(
                    candidates: candidates,
                    availableNewSlots: remainingFreeScoreSlots,
                    hasUnlimitedScores: libraryAccessController.status.hasUnlimitedScores
                )
            )
            return
        }

        synchronizeManagedScoreCount()
        let newScoreCount = candidates.filter(\.disposition.usesNewSlot).count
        guard reserveScoreSlots(newScoreCount) else {
            pendingLibraryAction = .importScores(candidates)
            libraryAccessSheet = .paywall(.importScore(count: candidates.count))
            return
        }

        let reservedImportSlots = libraryAccessController.status.hasUnlimitedScores ? 0 : newScoreCount
        var reservationsRemaining = reservedImportSlots
        isLoading = true
        defer {
            releaseScoreSlots(reservationsRemaining)
            importProgress = nil
            isLoading = false
            synchronizeManagedScoreCount()
        }

        var importedCount = 0
        var failures: [ScoreImportFailure] = []
        var singleImportedSession: ScoreSession?

        for (index, candidate) in candidates.enumerated() {
            importProgress = ScoreImportProgress(itemNumber: index + 1, totalCount: candidates.count)
            do {
                let session: ScoreSession
                switch candidate.disposition {
                case .new:
                    session = try await importDocument(
                        at: candidate.url,
                        setsCurrentSession: candidates.count == 1
                    )
                case .replace(let relativePath, let existingFileReference):
                    session = try await replaceImportedDocument(
                        at: candidate.url,
                        relativePath: relativePath,
                        existingFileReference: existingFileReference,
                        setsCurrentSession: candidates.count == 1
                    )
                }
                importedCount += 1
                if candidates.count == 1 {
                    singleImportedSession = session
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                failures.append(ScoreImportFailure(fileName: candidate.url.lastPathComponent, message: message))
            }

            if candidate.disposition.usesNewSlot, reservationsRemaining > 0 {
                releaseScoreSlots(1)
                reservationsRemaining -= 1
            }
            synchronizeManagedScoreCount()
        }

        if let singleImportedSession, failures.isEmpty {
            pendingImportedSession = singleImportedSession
        } else if candidates.count == 1, let failure = failures.first {
            presentError(title: "Import Failed", message: failure.message)
        } else {
            errorAlert = ScoreImportBatchOutcome(
                totalCount: candidates.count,
                importedCount: importedCount,
                failures: failures
            ).alert
        }
    }

    private func importDocument(at externalURL: URL, setsCurrentSession: Bool) async throws -> ScoreSession {
        guard libraryAccessController.status.hasUnlimitedScores || reservedScoreSlots > 0 else {
            throw LibraryAdmissionError.missingReservation
        }
        let managedDocument = try importIntoLibrary(from: externalURL)
        do {
            return try await openManagedDocument(
                at: managedDocument.canonicalURL,
                libraryRelativePath: managedDocument.relativeMainFilePath,
                setsCurrentSession: setsCurrentSession
            )
        } catch {
            do {
                try scoreLibrary.removeDocument(atRelativePath: managedDocument.relativeMainFilePath)
                print("Aria failed import cleanup removed: file=\(managedDocument.canonicalURL.lastPathComponent)")
            } catch let cleanupError {
                print("Aria failed import cleanup could not remove: file=\(managedDocument.canonicalURL.lastPathComponent) error=\(cleanupError.localizedDescription)")
            }
            throw error
        }
    }

    private func replaceImportedDocument(
        at externalURL: URL,
        relativePath: String,
        existingFileReference: String?,
        setsCurrentSession: Bool
    ) async throws -> ScoreSession {
        let existingURL = try scoreLibrary.url(forRelativePath: relativePath)
        let existingDocument = ManagedLibraryDocument(
            canonicalURL: existingURL,
            relativeMainFilePath: relativePath
        )
        let stagedDocument = try stageReplacement(from: externalURL)

        do {
            let preparedDocument = try await prepareStagedReplacement(stagedDocument)
            guard normalizedFileName(preparedDocument.canonicalURL.lastPathComponent)
                    == normalizedFileName(existingDocument.canonicalURL.lastPathComponent)
            else {
                throw ManagedScoreLibraryError.replacementFailed
            }

            if currentSession?.document.fileReference == existingFileReference {
                currentSession = nil
            }

            let committedDocument = try scoreLibrary.replaceDocument(
                with: preparedDocument,
                replacing: existingDocument
            )
            let session = try await openManagedDocument(
                at: committedDocument.canonicalURL,
                libraryRelativePath: committedDocument.relativeMainFilePath,
                replacingFileReference: existingFileReference,
                setsCurrentSession: setsCurrentSession
            )
            replaceSetlistScoreKeys(
                sourceDocument: existingDocument,
                replacingFileReference: existingFileReference,
                destinationDocument: committedDocument
            )
            return session
        } catch {
            scoreLibrary.discardStagedDocument(stagedDocument)
            throw error
        }
    }

    private func prepareStagedReplacement(
        _ stagedDocument: ManagedLibraryDocument
    ) async throws -> ManagedLibraryDocument {
        let sourceExtension = stagedDocument.canonicalURL.pathExtension.lowercased()
        let shouldNormalize = sourceExtension == ScoreFileFormat.mxl.rawValue
            || sourceExtension == ScoreFileFormat.musicxml.rawValue
            || sourceExtension == "xml"
        let sourceSession = try await sessionService.openSession(at: stagedDocument.canonicalURL)
        guard shouldNormalize else {
            return stagedDocument
        }

        guard sourceSession.capabilities.supportsEditing,
              let liveRenderSession = sourceSession.liveRenderSession
        else {
            throw ScoreDocumentServiceError.bridgeFailure("Aria could not convert this replacement into an editable MuseScore document.")
        }

        let preferredName = stagedDocument.canonicalURL.deletingPathExtension().lastPathComponent
        let packagedDocument = try scoreLibrary.stagedPackagedDocumentDestination(
            preferredName: preferredName,
            alongside: stagedDocument
        )
        try await saveSession(liveRenderSession, to: packagedDocument.canonicalURL)
        let packagedSession = try await sessionService.openSession(at: packagedDocument.canonicalURL)
        guard packagedSession.document.format == .mscz,
              packagedSession.capabilities.supportsEditing,
              packagedSession.liveRenderSession != nil
        else {
            throw ScoreDocumentServiceError.bridgeFailure("Aria converted the replacement but could not reopen it safely.")
        }
        return packagedDocument
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

    private func reserveScoreSlots(_ count: Int) -> Bool {
        guard count > 0 else {
            return true
        }
        guard !libraryAccessController.status.hasUnlimitedScores else {
            return true
        }
        let allowance = LibraryScoreAllowance(
            status: libraryAccessController.status,
            usedScoreCount: managedScoreCount,
            reservedScoreCount: reservedScoreSlots,
            freeLimit: freeScoreLimit
        )
        guard allowance.canReserve(count) else {
            return false
        }
        reservedScoreSlots += count
        return true
    }

    private func releaseScoreSlots(_ count: Int) {
        guard count > 0 else {
            return
        }
        reservedScoreSlots = max(0, reservedScoreSlots - count)
    }

    private func releaseCreateScoreReservation() {
        guard isCreateScoreSlotReserved else {
            return
        }
        isCreateScoreSlotReserved = false
        releaseScoreSlots(1)
    }

    private func synchronizeManagedScoreCount() {
        guard let count = try? scoreLibrary.visibleScoreDocuments().count else {
            return
        }
        managedScoreCount = count
    }

    private func normalizedFileName(_ fileName: String) -> String {
        fileName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func stageReplacement(from externalURL: URL) throws -> ManagedLibraryDocument {
        let startedScopedAccess = externalURL.startAccessingSecurityScopedResource()
        defer {
            if startedScopedAccess {
                externalURL.stopAccessingSecurityScopedResource()
            }
        }
        return try scoreLibrary.stageDocumentForReplacement(from: externalURL)
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
            return try await openManagedDocument(
                at: libraryURL,
                libraryRelativePath: libraryRelativePath,
                replacingFileReference: recent.fileReference
            )
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
        synchronizeManagedScoreCount()
        guard reserveScoreSlots(1) else {
            pendingLibraryAction = .reopenLegacyDocument(recent)
            libraryAccessSheet = .paywall(.importScore(count: 1))
            throw LibraryAdmissionError.unlockPresentationHandled
        }
        let reservedLegacySlot = libraryAccessController.status.hasUnlimitedScores ? 0 : 1
        defer {
            releaseScoreSlots(reservedLegacySlot)
            synchronizeManagedScoreCount()
        }

        guard libraryAccessController.status.hasUnlimitedScores || reservedScoreSlots > 0 else {
            throw LibraryAdmissionError.missingReservation
        }
        let managedDocument = try importIntoLibrary(from: resolvedURL)
        do {
            return try await openManagedDocument(
                at: managedDocument.canonicalURL,
                libraryRelativePath: managedDocument.relativeMainFilePath,
                replacingFileReference: recent.fileReference
            )
        } catch {
            try? scoreLibrary.removeDocument(atRelativePath: managedDocument.relativeMainFilePath)
            throw error
        }
    }

    private func openManagedDocument(at url: URL,
                                     libraryRelativePath: String,
                                     replacingFileReference: String? = nil,
                                     setsCurrentSession: Bool = true) async throws -> ScoreSession
    {
        cancelPendingLibraryPreviewRefresh(reason: "open")
        let startedAt = Date()
        print("Aria library open begin: file=\(url.lastPathComponent) relative=\(libraryRelativePath)")
        let sourceDocument = ManagedLibraryDocument(
            canonicalURL: url,
            relativeMainFilePath: libraryRelativePath
        )
        let preparedSession = try await prepareManagedScoreSession(sourceDocument)
        let session = preparedSession.session
        print(String(format: "Aria library open session ready: file=%@ pages=%d elapsed=%.3fs", session.document.url.lastPathComponent, session.pageCount, Date().timeIntervalSince(startedAt)))
        if setsCurrentSession {
            currentSession = session
            print("Aria library current session assigned: file=\(session.document.url.lastPathComponent)")
        }
        recents = recentStore.record(
            document: session.document,
            libraryRelativePath: preparedSession.document.relativeMainFilePath,
            replacingFileReference: replacingFileReference,
            in: recents
        )

        if let sourceDocumentToRemove = preparedSession.sourceDocumentToRemove {
            replaceSetlistScoreKeys(
                sourceDocument: sourceDocumentToRemove,
                replacingFileReference: replacingFileReference,
                destinationDocument: preparedSession.document
            )
            do {
                try scoreLibrary.removeDocument(atRelativePath: sourceDocumentToRemove.relativeMainFilePath)
                print("Aria import normalization removed source: file=\(sourceDocumentToRemove.canonicalURL.lastPathComponent)")
            } catch {
                print("Aria import normalization source cleanup failed: file=\(sourceDocumentToRemove.canonicalURL.lastPathComponent) error=\(error.localizedDescription)")
            }
        }

        return session
    }

    private func prepareManagedScoreSession(_ sourceDocument: ManagedLibraryDocument) async throws -> PreparedManagedScoreSession {
        let sourceExtension = sourceDocument.canonicalURL.pathExtension.lowercased()
        let shouldNormalize = sourceExtension == ScoreFileFormat.mxl.rawValue
            || sourceExtension == ScoreFileFormat.musicxml.rawValue
            || sourceExtension == "xml"

        let sourceSession = try await sessionService.openSession(at: sourceDocument.canonicalURL)
        guard shouldNormalize else {
            return PreparedManagedScoreSession(
                document: sourceDocument,
                session: sourceSession,
                sourceDocumentToRemove: nil
            )
        }

        guard
            sourceSession.capabilities.supportsEditing,
            let liveRenderSession = sourceSession.liveRenderSession
        else {
            throw ScoreDocumentServiceError.bridgeFailure("Aria imported this score but could not convert it into an editable MuseScore document.")
        }

        let preferredName = sourceDocument.canonicalURL.deletingPathExtension().lastPathComponent
        let packagedDocument = try scoreLibrary.packagedDocumentDestination(preferredName: preferredName)
        print("Aria import normalization begin: source=\(sourceDocument.canonicalURL.lastPathComponent) destination=\(packagedDocument.canonicalURL.lastPathComponent)")

        do {
            try await saveSession(liveRenderSession, to: packagedDocument.canonicalURL)
            let packagedSession = try await sessionService.openSession(at: packagedDocument.canonicalURL)
            guard
                packagedSession.document.format == .mscz,
                packagedSession.capabilities.supportsEditing,
                packagedSession.liveRenderSession != nil
            else {
                throw ScoreDocumentServiceError.bridgeFailure("Aria created the converted score but could not reopen it safely.")
            }

            print("Aria import normalization complete: source=\(sourceDocument.canonicalURL.lastPathComponent) destination=\(packagedDocument.canonicalURL.lastPathComponent)")
            return PreparedManagedScoreSession(
                document: packagedDocument,
                session: packagedSession,
                sourceDocumentToRemove: sourceDocument
            )
        } catch {
            try? scoreLibrary.removeDocument(atRelativePath: packagedDocument.relativeMainFilePath)
            print("Aria import normalization failed: source=\(sourceDocument.canonicalURL.lastPathComponent) error=\(error.localizedDescription)")
            throw error
        }
    }

    private func replaceSetlistScoreKeys(sourceDocument: ManagedLibraryDocument,
                                         replacingFileReference: String?,
                                         destinationDocument: ManagedLibraryDocument)
    {
        var oldKeys = Set([
            sourceDocument.relativeMainFilePath,
            sourceDocument.canonicalURL.standardizedFileURL.path
        ])
        if let replacingFileReference {
            oldKeys.insert(replacingFileReference)
        }
        let newKey = destinationDocument.relativeMainFilePath
        var changed = false

        for index in setlistFolders.indices {
            var seenKeys: Set<String> = []
            let updatedKeys = setlistFolders[index].scoreKeys.compactMap { key -> String? in
                let updatedKey = oldKeys.contains(key) ? newKey : key
                if updatedKey != key {
                    changed = true
                }
                return seenKeys.insert(updatedKey).inserted ? updatedKey : nil
            }
            if updatedKeys.count != setlistFolders[index].scoreKeys.count {
                changed = true
            }
            setlistFolders[index].scoreKeys = updatedKeys
        }

        if changed {
            setlistStore.save(setlistFolders)
        }
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

    private func saveSession(_ liveRenderSession: LiveScoreRenderSession,
                             to url: URL,
                             clearsRecoverySnapshot: Bool = true) async throws
    {
        if let _ = try scoreLibrary.relativePath(for: url) {
            try await liveRenderSession.save(to: url)
            if clearsRecoverySnapshot {
                try? recoveryStore.removeSnapshot(for: url)
            }
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
