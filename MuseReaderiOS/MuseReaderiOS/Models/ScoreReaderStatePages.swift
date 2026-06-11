import Foundation

@MainActor
extension ScoreReaderState {
    func loadInitialPages() {
        ensurePagesAround(selectedPageIndex)
    }

    func loadConcertPitchState() {
        guard let liveRenderSession = session.liveRenderSession else {
            concertPitchEnabled = false
            hasConcertPitchRelevantTransposition = false
            return
        }

        Task { @MainActor [weak self] in
            self?.updateConcertPitchState(
                enabled: await liveRenderSession.concertPitchEnabled(),
                isRelevant: await liveRenderSession.hasConcertPitchRelevantTransposition()
            )
        }
    }

    func toggleConcertPitch() {
        setConcertPitchEnabled(!concertPitchEnabled)
    }

    func setConcertPitchEnabled(_ enabled: Bool) {
        guard
            supportsEditing,
            let liveRenderSession = session.liveRenderSession,
            !isEditingActionInFlight
        else {
            return
        }

        isEditingActionInFlight = true
        editingErrorMessage = nil

        Task { @MainActor [weak self] in
            defer {
                self?.isEditingActionInFlight = false
            }

            do {
                let updatedPageCount = try await liveRenderSession.setConcertPitchEnabled(enabled)
                guard let self else {
                    return
                }
                self.updateConcertPitchState(
                    enabled: enabled,
                    isRelevant: await liveRenderSession.hasConcertPitchRelevantTransposition()
                )
                self.activePageCount = max(updatedPageCount, 0)
                self.selectedPageIndex = ScoreReaderState.boundedIndex(self.selectedPageIndex, pageCount: self.activePageCount)
                self.invalidatePlaybackAfterScoreMutation()
                self.invalidateRenderedPages()
                self.loadEditingState()
                self.scheduleAutosave()
            } catch {
                self?.editingErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func updateSelection(to pageIndex: Int) {
        guard isValid(pageIndex) else {
            return
        }

        cancelDeferredPagePrefetch()
        selectedPageIndex = pageIndex
        ensurePagesAround(pageIndex)
    }

    func prefetchPage(_ pageIndex: Int) {
        ensureLivePageLoaded(pageIndex, priority: .utility)
    }

    func selectScorePart(index: Int?) {
        guard let liveRenderSession = session.liveRenderSession else {
            return
        }

        partSelectionTask?.cancel()
        partSelectionRevision += 1
        let selectionRevision = partSelectionRevision
        pendingScorePartIndex = index
        partSelectionErrorMessage = nil
        cancelDeferredPagePrefetch()
        loadTasks.values.forEach { $0.cancel() }
        loadTasks.removeAll()
        loadingPageIndices.removeAll()
        pageErrorMessages.removeAll()
        cachedPagesByIndex.removeAll()
        staleLivePageIndices.removeAll()
        playbackMeasureHighlight = nil
        playbackMeasureRegions.removeAll()
        playbackContextTask?.cancel()
        playbackContextTask = nil
        playbackWarmupTask?.cancel()
        playbackWarmupTask = nil
        playbackWarmupRevision += 1
        playbackController?.invalidate()
        playbackState = session.capabilities.supportsPlayback
            ? ScorePlaybackState(isAvailable: true, status: .stopped, positionSeconds: 0, durationSeconds: 0)
            : .unavailable
        playbackErrorMessage = nil
        playbackPreparationMessage = session.capabilities.supportsPlayback ? "Preparing part..." : nil

        let selectionTask = Task { @MainActor [weak self] in
            do {
                let updatedPageCount: Int
                if let index {
                    updatedPageCount = try await liveRenderSession.setActivePart(index: index)
                } else {
                    updatedPageCount = try await liveRenderSession.setFullScoreView()
                }
                try Task.checkCancellation()
                let concertPitchEnabled = await liveRenderSession.concertPitchEnabled()
                let hasConcertPitchRelevantTransposition = await liveRenderSession.hasConcertPitchRelevantTransposition()

                guard
                    let self,
                    self.partSelectionRevision == selectionRevision
                else {
                    return
                }

                self.activeScorePartIndex = index
                self.pendingScorePartIndex = nil
                self.partSelectionErrorMessage = nil
                self.partSelectionTask = nil
                self.playbackPreparationMessage = nil
                self.updateConcertPitchState(
                    enabled: concertPitchEnabled,
                    isRelevant: hasConcertPitchRelevantTransposition
                )
                self.activePageCount = max(updatedPageCount, 0)
                self.selectedPageIndex = ScoreReaderState.boundedIndex(self.selectedPageIndex, pageCount: self.activePageCount)
                self.ensurePagesAround(self.selectedPageIndex)
                self.loadEditingState()
                self.loadPlaybackContextIfNeeded()
                self.startPlaybackWarmup()
            } catch is CancellationError {
                guard
                    let self,
                    self.partSelectionRevision == selectionRevision
                else {
                    return
                }

                self.pendingScorePartIndex = nil
                self.partSelectionTask = nil
                self.playbackPreparationMessage = nil
            } catch {
                guard
                    let self,
                    self.partSelectionRevision == selectionRevision
                else {
                    return
                }

                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.pendingScorePartIndex = nil
                self.partSelectionErrorMessage = message
                self.partSelectionTask = nil
                self.playbackPreparationMessage = nil
                self.pageErrorMessages[self.selectedPageIndex] = message
            }
        }
        partSelectionTask = selectionTask
    }

    func ensurePagesAround(_ pageIndex: Int, excluding excludedPageIndices: Set<Int> = []) {
        guard pageCount > 0 else {
            return
        }

        let candidates = ((pageIndex - prefetchDistance)...(pageIndex + prefetchDistance))
            .filter { isValid($0) && !excludedPageIndices.contains($0) }
        print("Aria page prefetch window: focusPage=\(pageIndex + 1) candidates=\(candidates.map { $0 + 1 }) excluded=\(excludedPageIndices.sorted().map { $0 + 1 }) distance=\(prefetchDistance)")

        for candidate in (pageIndex - prefetchDistance)...(pageIndex + prefetchDistance) {
            guard !excludedPageIndices.contains(candidate) else {
                continue
            }

            ensureLivePageLoaded(candidate, priority: candidate == pageIndex ? .userInitiated : .utility)
        }
    }

    func updateConcertPitchState(enabled: Bool, isRelevant: Bool) {
        concertPitchEnabled = enabled
        hasConcertPitchRelevantTransposition = isRelevant
    }

    func ensureLivePageLoaded(_ pageIndex: Int, priority: TaskPriority? = nil) {
        guard isValid(pageIndex), let liveRenderSession = session.liveRenderSession else {
            return
        }

        let hasCachedLivePage = cachedPagesByIndex[pageIndex]?.source == .liveMuseScoreRenderer
        let isStale = staleLivePageIndices.contains(pageIndex)
        if
            let cachedPage = cachedPagesByIndex[pageIndex],
            cachedPage.source == .liveMuseScoreRenderer,
            !isStale
        {
            return
        }

        if loadingPageIndices.contains(pageIndex) {
            return
        }

        loadingPageIndices.insert(pageIndex)
        pageErrorMessages[pageIndex] = nil
        let preferredDPI = self.preferredDPI
        let queuedAt = Date()
        let priorityLabel = pageLoadPriorityLabel(priority)

        loadTasks[pageIndex]?.cancel()
        print(String(format: "Aria page load queued: page=%d dpi=%d priority=%@ cached=%@ stale=%@ inflight=%d",
                     pageIndex + 1,
                     preferredDPI,
                     priorityLabel,
                     hasCachedLivePage.description,
                     isStale.description,
                     loadingPageIndices.count))
        loadTasks[pageIndex] = Task(priority: priority) { [weak self] in
            do {
                let startedAt = Date()
                let queueWait = startedAt.timeIntervalSince(queuedAt)
                print(String(format: "Aria page load start: page=%d priority=%@ queueWait=%.3fs",
                             pageIndex + 1,
                             priorityLabel,
                             queueWait))
                try Task.checkCancellation()
                let page = try await liveRenderSession.renderPage(at: pageIndex, dpi: preferredDPI)
                guard !Task.isCancelled else {
                    print(String(format: "Aria page load canceled after render: page=%d totalElapsed=%.3fs",
                                 pageIndex + 1,
                                 Date().timeIntervalSince(queuedAt)))
                    return
                }

                let renderElapsed = Date().timeIntervalSince(startedAt)
                let totalElapsed = Date().timeIntervalSince(queuedAt)
                print(String(format: "Aria page load finished: page=%d dpi=%d renderElapsed=%.3fs totalElapsed=%.3fs",
                             pageIndex + 1,
                             preferredDPI,
                             renderElapsed,
                             totalElapsed))
                self?.storeLoadedPage(page, at: pageIndex)
            } catch {
                guard !Task.isCancelled else {
                    print(String(format: "Aria page load canceled: page=%d totalElapsed=%.3fs",
                                 pageIndex + 1,
                                 Date().timeIntervalSince(queuedAt)))
                    return
                }

                print(String(format: "Aria page load failed: page=%d elapsed=%.3fs error=%@",
                             pageIndex + 1,
                             Date().timeIntervalSince(queuedAt),
                             ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)))
                self?.storePageError(error, at: pageIndex)
            }
        }
    }

    func cancelDeferredPagePrefetch() {
        if deferredPagePrefetchTask != nil {
            print("Aria page prefetch deferred canceled")
            deferredPagePrefetchTask?.cancel()
        }
        deferredPagePrefetchTask = nil
    }

    @discardableResult
    func cancelPageLoads(except pageIndexToKeep: Int? = nil) -> Int {
        var canceledCount = 0
        for pageIndex in Array(loadTasks.keys) {
            guard pageIndex != pageIndexToKeep else {
                continue
            }

            loadTasks[pageIndex]?.cancel()
            loadTasks[pageIndex] = nil
            loadingPageIndices.remove(pageIndex)
            pageErrorMessages[pageIndex] = nil
            canceledCount += 1
        }

        if canceledCount > 0 {
            let keptPage = pageIndexToKeep.map { "\($0 + 1)" } ?? "none"
            print("Aria page load cancel batch: canceled=\(canceledCount) keptPage=\(keptPage)")
        }

        return canceledCount
    }

    func scheduleDeferredPagePrefetchAround(_ pageIndex: Int, delay: Duration = .milliseconds(650)) {
        cancelDeferredPagePrefetch()

        guard prefetchDistance > 0, pageCount > 1 else {
            return
        }

        let scheduledAt = Date()
        print("Aria page prefetch deferred scheduled: focusPage=\(pageIndex + 1) delay=\(String(describing: delay)) distance=\(prefetchDistance)")
        deferredPagePrefetchTask = Task { @MainActor [weak self] in
            if delay > .zero {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    print(String(format: "Aria page prefetch deferred canceled during sleep: focusPage=%d elapsed=%.3fs",
                                 pageIndex + 1,
                                 Date().timeIntervalSince(scheduledAt)))
                    return
                }
            }

            guard !Task.isCancelled, let self else {
                print(String(format: "Aria page prefetch deferred canceled before resume: focusPage=%d elapsed=%.3fs",
                             pageIndex + 1,
                             Date().timeIntervalSince(scheduledAt)))
                return
            }

            print(String(format: "Aria page prefetch deferred resume: focusPage=%d elapsed=%.3fs",
                         pageIndex + 1,
                         Date().timeIntervalSince(scheduledAt)))
            self.ensurePagesAround(pageIndex, excluding: [pageIndex])
            self.deferredPagePrefetchTask = nil
        }
    }

    func storeLoadedPage(_ page: ScorePage, at pageIndex: Int) {
        cachedPagesByIndex[pageIndex] = page
        loadingPageIndices.remove(pageIndex)
        pageErrorMessages[pageIndex] = nil
        staleLivePageIndices.remove(pageIndex)
        loadTasks[pageIndex] = nil
    }

    func storePageError(_ error: Error, at pageIndex: Int) {
        loadingPageIndices.remove(pageIndex)
        pageErrorMessages[pageIndex] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        loadTasks[pageIndex] = nil
    }

    func isValid(_ pageIndex: Int) -> Bool {
        pageIndex >= 0 && pageIndex < pageCount
    }

    func invalidateRenderedPages(scope: ScoreEditRefreshScope = .all, focusedPageIndex: Int? = nil) {
        let startedAt = Date()
        cancelDeferredPagePrefetch()
        let focusPageIndex = ScoreReaderState.boundedIndex(focusedPageIndex ?? selectedPageIndex, pageCount: pageCount)
        let cachedLivePageCount = cachedPagesByIndex.values.filter { $0.source == .liveMuseScoreRenderer }.count
        let staleCountBefore = staleLivePageIndices.count
        let indicesToInvalidate: Set<Int>
        switch scope {
        case .local:
            indicesToInvalidate = isValid(focusPageIndex) ? [focusPageIndex] : []
        case .nearby:
            indicesToInvalidate = Set(
                (focusPageIndex - prefetchDistance - 1)...(focusPageIndex + prefetchDistance + 1)
            ).filter { isValid($0) }
        case .all:
            indicesToInvalidate = Set(
                cachedPagesByIndex.compactMap { index, page in
                    page.source == .liveMuseScoreRenderer ? index : nil
                }
            )
        }

        let canceledCount: Int
        if scope == .all {
            canceledCount = loadTasks.count
            loadTasks.values.forEach { $0.cancel() }
            loadTasks.removeAll()
            loadingPageIndices.removeAll()
            pageErrorMessages.removeAll()
        } else {
            for pageIndex in indicesToInvalidate {
                loadTasks[pageIndex]?.cancel()
                loadTasks[pageIndex] = nil
                loadingPageIndices.remove(pageIndex)
                pageErrorMessages[pageIndex] = nil
            }

            canceledCount = cancelPageLoads(except: focusPageIndex)
        }

        staleLivePageIndices.formUnion(indicesToInvalidate)
        print(String(format: "Aria edit refresh invalidation: scope=%@ focusPage=%d cachedLive=%d staleBefore=%d staleAfter=%d canceledLoads=%d inflightAfter=%d elapsed=%.3fs invalidated=%@",
                     scope.rawValue,
                     focusPageIndex + 1,
                     cachedLivePageCount,
                     staleCountBefore,
                     staleLivePageIndices.count,
                     canceledCount,
                     loadingPageIndices.count,
                     Date().timeIntervalSince(startedAt),
                     "\(indicesToInvalidate.sorted().map { $0 + 1 })"))
        ensureLivePageLoaded(focusPageIndex, priority: .userInitiated)
        scheduleDeferredPagePrefetchAround(focusPageIndex)
    }

    private func pageLoadPriorityLabel(_ priority: TaskPriority?) -> String {
        switch priority {
        case .userInitiated:
            return "userInitiated"
        case .utility:
            return "utility"
        case .background:
            return "background"
        case .high:
            return "high"
        case .medium:
            return "medium"
        case .low:
            return "low"
        case .some(let priority):
            return String(describing: priority)
        case .none:
            return "default"
        }
    }

    static func boundedIndex(_ pageIndex: Int, pageCount: Int) -> Int {
        guard pageCount > 0 else {
            return 0
        }

        return max(0, min(pageIndex, pageCount - 1))
    }
}
