import CryptoKit
import Foundation
import UIKit

struct ScoreRecoverySnapshotRecord: Codable, Sendable, Equatable {
    let sourcePath: String
    let snapshotFileName: String
    let preparedAt: Date
}

struct PendingScoreRecoverySnapshot: Sendable, Equatable {
    let record: ScoreRecoverySnapshotRecord
    let snapshotURL: URL
    let recordURL: URL
}

struct ScoreRecoveryStore: @unchecked Sendable {
    private enum Constants {
        static let directoryName = "Recovery"
        static let recordExtension = "json"
    }

    private let fileManager: FileManager
    private let rootURLOverride: URL?

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        self.rootURLOverride = rootURL
    }

    func prepareSnapshot(for sourceURL: URL) throws -> URL {
        let directoryURL = try recoveryDirectoryURL()
        try prepareDirectory(directoryURL)

        let key = recoveryKey(for: sourceURL)
        let snapshotFileName = "\(key).mscz"
        let record = ScoreRecoverySnapshotRecord(
            sourcePath: sourceURL.standardizedFileURL.path,
            snapshotFileName: snapshotFileName,
            preparedAt: .now
        )
        let recordData = try JSONEncoder().encode(record)
        try recordData.write(
            to: directoryURL.appendingPathComponent("\(key).\(Constants.recordExtension)", isDirectory: false),
            options: .atomic
        )

        return directoryURL.appendingPathComponent(snapshotFileName, isDirectory: false)
    }

    func pendingSnapshots() throws -> [PendingScoreRecoverySnapshot] {
        let directoryURL = try recoveryDirectoryURL()
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return []
        }

        let recordURLs = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension.lowercased() == Constants.recordExtension }

        return recordURLs.compactMap { recordURL in
            guard
                let data = try? Data(contentsOf: recordURL),
                let record = try? JSONDecoder().decode(ScoreRecoverySnapshotRecord.self, from: data)
            else {
                try? fileManager.removeItem(at: recordURL)
                return nil
            }

            return PendingScoreRecoverySnapshot(
                record: record,
                snapshotURL: directoryURL.appendingPathComponent(record.snapshotFileName, isDirectory: false),
                recordURL: recordURL
            )
        }
    }

    func removeSnapshot(for sourceURL: URL) throws {
        let directoryURL = try recoveryDirectoryURL()
        let key = recoveryKey(for: sourceURL)
        try removeIfPresent(directoryURL.appendingPathComponent("\(key).mscz", isDirectory: false))
        try removeIfPresent(directoryURL.appendingPathComponent("\(key).\(Constants.recordExtension)", isDirectory: false))
    }

    func removeSnapshot(_ pendingSnapshot: PendingScoreRecoverySnapshot) throws {
        try removeIfPresent(pendingSnapshot.snapshotURL)
        try removeIfPresent(pendingSnapshot.recordURL)
    }

    private func recoveryDirectoryURL() throws -> URL {
        if let rootURLOverride {
            return rootURLOverride
        }
        return try ManagedScoreLibraryPaths.privateRootURL(fileManager: fileManager)
            .appendingPathComponent(Constants.directoryName, isDirectory: true)
    }

    private func prepareDirectory(_ directoryURL: URL) throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
    }

    private func recoveryKey(for sourceURL: URL) -> String {
        let pathData = Data(sourceURL.standardizedFileURL.path.utf8)
        return SHA256.hash(data: pathData).map { String(format: "%02x", $0) }.joined()
    }

    private func removeIfPresent(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        try fileManager.removeItem(at: url)
    }
}

@MainActor
extension ScoreReaderState {
    func autosaveDelay(for refreshScope: ScoreEditRefreshScope) -> Duration {
        let partCount = session.liveRenderSession?.parts.count ?? 0
        let isLargeScore = pageCount >= 16 || partCount >= 6
        guard isLargeScore else {
            return refreshScope == .local ? .milliseconds(1800) : .milliseconds(900)
        }

        switch refreshScope {
        case .local:
            return .milliseconds(8000)
        case .nearby, .all:
            return .milliseconds(10000)
        }
    }

    func scheduleAutosave(delay: Duration = .milliseconds(900)) {
        guard session.capabilities.supportsEditing, let liveRenderSession = session.liveRenderSession else {
            return
        }

        autosaveRevision += 1
        hasUnsavedAutosaveChanges = true
        let saveRevision = autosaveRevision
        let destinationURL = session.document.url
        let scheduledAt = Date()
        let replacedPendingSave = autosaveTask != nil
        let partCount = session.liveRenderSession?.parts.count ?? 0

        autosaveTask?.cancel()
        print("Aria autosave scheduled: revision=\(saveRevision) delay=\(String(describing: delay)) pages=\(pageCount) parts=\(partCount) replacedPending=\(replacedPendingSave) destination=\"\(destinationURL.lastPathComponent)\"")
        autosaveTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: delay)
                try Task.checkCancellation()
                let startedAt = Date()
                print(String(format: "Aria autosave begin: revision=%d delayElapsed=%.3fs destination=\"%@\"",
                             saveRevision,
                             startedAt.timeIntervalSince(scheduledAt),
                             destinationURL.lastPathComponent))
                try await liveRenderSession.save(to: destinationURL)
                guard let self, self.autosaveRevision == saveRevision else {
                    return
                }
                let finishedAt = Date()
                print(String(format: "Aria autosave end: revision=%d saveElapsed=%.3fs totalElapsed=%.3fs",
                             saveRevision,
                             finishedAt.timeIntervalSince(startedAt),
                             finishedAt.timeIntervalSince(scheduledAt)))
                self.hasUnsavedAutosaveChanges = false
                self.autosaveFailureMessage = nil
                self.autosaveTask = nil
                self.removeRecoverySnapshotAfterCanonicalSave(to: destinationURL)
            } catch is CancellationError {
                print(String(format: "Aria autosave canceled: revision=%d elapsed=%.3fs",
                             saveRevision,
                             Date().timeIntervalSince(scheduledAt)))
            } catch {
                guard let self, self.autosaveRevision == saveRevision else {
                    return
                }
                print(String(format: "Aria autosave failed: revision=%d elapsed=%.3fs error=%@",
                             saveRevision,
                             Date().timeIntervalSince(scheduledAt),
                             ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)))
                self.recordSaveFailure(error)
                self.autosaveTask = nil
            }
        }
    }

    func retryAutosave() {
        guard
            hasUnsavedAutosaveChanges,
            autosaveFailureMessage != nil,
            let liveRenderSession = session.liveRenderSession,
            !isEditingActionInFlight
        else {
            return
        }

        autosaveTask?.cancel()
        autosaveTask = nil
        isEditingActionInFlight = true
        let destinationURL = session.document.url
        let saveRevision = autosaveRevision

        Task { @MainActor [weak self] in
            defer {
                self?.isEditingActionInFlight = false
            }

            do {
                try await liveRenderSession.save(to: destinationURL)
                guard let self, self.autosaveRevision == saveRevision else {
                    return
                }
                self.hasUnsavedAutosaveChanges = false
                self.autosaveFailureMessage = nil
                self.removeRecoverySnapshotAfterCanonicalSave(to: destinationURL)
            } catch {
                self?.recordSaveFailure(error)
            }
        }
    }

    func flushAutosaveOnShutdown() {
        saveRecoverySnapshotForBackground()
    }

    func saveBeforeClosing() async -> Bool {
        await savePendingChanges(
            busyMessage: "Finish the current edit before closing the score.",
            unavailableMessage: "MuseReader could not save this score before closing."
        )
    }

    func savePendingChanges(
        busyMessage: String = "Finish the current edit before saving the score.",
        unavailableMessage: String = "MuseReader could not save this score.",
        waitsForInFlightAction: Bool = false
    ) async -> Bool {
        guard supportsEditing else {
            return true
        }

        if waitsForInFlightAction {
            let deadline = Date().addingTimeInterval(5)
            while isEditingActionInFlight, Date() < deadline {
                try? await Task.sleep(for: .milliseconds(25))
            }
        }

        guard !isEditingActionInFlight else {
            editingErrorMessage = busyMessage
            return false
        }

        autosaveTask?.cancel()
        autosaveTask = nil

        guard hasUnsavedAutosaveChanges else {
            return true
        }

        guard let liveRenderSession = session.liveRenderSession else {
            editingErrorMessage = unavailableMessage
            return false
        }

        isEditingActionInFlight = true
        editingErrorMessage = nil
        let destinationURL = session.document.url
        let saveRevision = autosaveRevision

        defer {
            isEditingActionInFlight = false
        }

        do {
            let startedAt = Date()
            print("Aria autosave close flush begin: revision=\(saveRevision) destination=\"\(destinationURL.lastPathComponent)\"")
            try await liveRenderSession.save(to: destinationURL)
            print(String(format: "Aria autosave close flush end: revision=%d elapsed=%.3fs",
                         saveRevision,
                         Date().timeIntervalSince(startedAt)))
            if autosaveRevision == saveRevision {
                hasUnsavedAutosaveChanges = false
                autosaveFailureMessage = nil
                removeRecoverySnapshotAfterCanonicalSave(to: destinationURL)
            }
            return true
        } catch {
            recordSaveFailure(error)
            editingErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func recordSaveFailure(_ error: Error) {
        hasUnsavedAutosaveChanges = true
        autosaveFailureMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    func saveRecoverySnapshotForBackground() {
        guard
            hasUnsavedAutosaveChanges || isEditingActionInFlight,
            backgroundRecoveryTask == nil,
            let liveRenderSession = session.liveRenderSession
        else {
            return
        }

        autosaveTask?.cancel()
        autosaveTask = nil

        let application = UIApplication.shared
        backgroundTaskIdentifier = application.beginBackgroundTask(withName: "Aria score recovery") { [weak self] in
            Task { @MainActor in
                self?.endBackgroundExecutionIfNeeded()
            }
        }

        backgroundRecoveryTask = Task { @MainActor [self] in
            let startedAt = Date()
            var saveRevision = autosaveRevision
            defer {
                backgroundRecoveryTask = nil
                endBackgroundExecutionIfNeeded()
                if UIApplication.shared.applicationState == .active, hasUnsavedAutosaveChanges {
                    scheduleAutosave(delay: .zero)
                }
            }

            do {
                while isEditingActionInFlight {
                    try await Task.sleep(for: .milliseconds(25))
                }
                guard hasUnsavedAutosaveChanges else {
                    return
                }

                autosaveTask?.cancel()
                autosaveTask = nil
                saveRevision = autosaveRevision
                let sourceURL = session.document.url
                let recoveryURL = try recoveryStore.prepareSnapshot(for: sourceURL)
                print("Aria recovery save begin: revision=\(saveRevision) destination=\"\(recoveryURL.lastPathComponent)\"")
                try await liveRenderSession.save(to: recoveryURL)
                print(String(format: "Aria recovery save end: revision=%d elapsed=%.3fs",
                             saveRevision,
                             Date().timeIntervalSince(startedAt)))
                if autosaveRevision == saveRevision {
                    autosaveFailureMessage = nil
                }
            } catch {
                print(String(format: "Aria recovery save failed: revision=%d elapsed=%.3fs error=%@",
                             saveRevision,
                             Date().timeIntervalSince(startedAt),
                             ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)))
                recordSaveFailure(error)
            }
        }
    }

    func resumeAutosaveAfterBackground() {
        guard backgroundRecoveryTask == nil, hasUnsavedAutosaveChanges else {
            return
        }
        scheduleAutosave(delay: .zero)
    }

    private func endBackgroundExecutionIfNeeded() {
        guard backgroundTaskIdentifier != .invalid else {
            return
        }
        UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
        backgroundTaskIdentifier = .invalid
    }

    private func removeRecoverySnapshotAfterCanonicalSave(to destinationURL: URL) {
        do {
            try recoveryStore.removeSnapshot(for: destinationURL)
        } catch {
            print("Aria recovery cleanup failed: file=\(destinationURL.lastPathComponent) error=\(error.localizedDescription)")
        }
    }
}
