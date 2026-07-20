import Foundation

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
            } catch {
                self?.recordSaveFailure(error)
            }
        }
    }

    func flushAutosaveOnShutdown() {
        autosaveTask?.cancel()
        autosaveTask = nil

        guard hasUnsavedAutosaveChanges, let liveRenderSession = session.liveRenderSession else {
            return
        }

        let destinationURL = session.document.url
        Task {
            let startedAt = Date()
            print("Aria autosave shutdown flush begin: destination=\"\(destinationURL.lastPathComponent)\"")
            try? await liveRenderSession.save(to: destinationURL)
            print(String(format: "Aria autosave shutdown flush end: elapsed=%.3fs",
                         Date().timeIntervalSince(startedAt)))
        }
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
}
