import CoreGraphics
import Foundation

private let playbackPreparationStartingMessage = "Preparing playback..."
private let playbackVisualSyncTrimSeconds: TimeInterval = 0.05

@MainActor
extension ScoreReaderState {
    func prepareAnnotationMeasureRegionsIfNeeded() async {
        guard playbackMeasureRegions.isEmpty, let liveRenderSession = session.liveRenderSession else {
            return
        }
        do {
            playbackMeasureRegions = try await liveRenderSession.playbackMeasureRegions()
        } catch {
            // Page-relative annotations still work when measure geometry is unavailable.
        }
    }

    func startPlaybackMonitoring() {
        guard session.capabilities.supportsPlayback, let playbackController else {
            playbackState = .unavailable
            return
        }

        startPlaybackWarmup()
        playbackMonitorTask?.cancel()
        playbackMonitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }

                let latestPlaybackState = playbackController.state()
                self.playbackState = latestPlaybackState
                let countingIn = playbackController.isCountingIn
                if self.isCountingIn != countingIn { self.isCountingIn = countingIn }
                let beat = countingIn ? playbackController.currentCountInClick()?.beatNumber : nil
                if self.countInBeatNumber != beat { self.countInBeatNumber = beat }
                self.updatePlaybackPreparationMessage(for: playbackController)
                self.updatePlaybackFollowState(with: latestPlaybackState)
                try? await Task.sleep(for: self.playbackMonitorInterval)
            }
        }
    }

    func shutdown() {
        loadTasks.values.forEach { $0.cancel() }
        loadTasks.removeAll()
        deferredPagePrefetchTask?.cancel()
        deferredPagePrefetchTask = nil
        playbackMonitorTask?.cancel()
        playbackMonitorTask = nil
        playbackContextTask?.cancel()
        playbackContextTask = nil
        playbackWarmupTask?.cancel()
        playbackWarmupTask = nil
        partSelectionTask?.cancel()
        partSelectionTask = nil
        editingStateTask?.cancel()
        editingStateTask = nil
        editingStateRevision += 1
        flushAutosaveOnShutdown()
        playbackMeasureHighlight = nil
        playbackController?.invalidate()
        notePreviewController.stopAll()
    }

    func togglePlayback() {
        guard
            let liveRenderSession = session.liveRenderSession,
            let playbackController,
            session.capabilities.supportsPlayback,
            !isPlaybackActionInFlight
        else {
            return
        }

        notePreviewController.stopAll()

        if playbackController.isWaitingToStartPlayback {
            playbackPreparationMessage = playbackPreparationStartingMessage
            return
        }

        isPlaybackActionInFlight = true
        playbackErrorMessage = nil
        playbackPreparationMessage = playbackController.isLoaded ? nil : playbackPreparationStartingMessage

        Task { @MainActor [weak self] in
            defer {
                self?.isPlaybackActionInFlight = false
                self?.updatePlaybackPreparationMessage(for: playbackController)
            }

            do {
                guard let self else {
                    return
                }

                try await self.waitForPendingPartSelection()
                if self.playbackMeasureRegions.isEmpty {
                    self.playbackMeasureRegions = try await liveRenderSession.playbackMeasureRegions()
                } else {
                    self.loadPlaybackContextIfNeeded()
                }
                try await self.preparePlaybackIfNeeded(
                    liveRenderSession: liveRenderSession,
                    playbackController: playbackController
                )

                let currentState = playbackController.state()
                if currentState.status == .playing {
                    if playbackController.isWaitingToStartPlayback {
                        self.playbackPreparationMessage = playbackPreparationStartingMessage
                    } else {
                        try playbackController.pause()
                    }
                } else if currentState.status == .paused {
                    try await self.playWithOptionalCountIn(
                        at: currentState.positionSeconds,
                        liveRenderSession: liveRenderSession,
                        playbackController: playbackController
                    )
                } else {
                    let shouldUseSelection = self.isEditingMode && self.editingState.selection != nil
                    let startTimeSeconds = shouldUseSelection
                        ? (self.playbackRegionForCurrentSelection()?.startTimeSeconds ?? 0)
                        : (self.playbackLoopIsActive ? (self.playbackLoopRange?.startTimeSeconds ?? 0) : 0)
                    try playbackController.seek(to: startTimeSeconds)
                    try await self.playWithOptionalCountIn(
                        at: startTimeSeconds,
                        liveRenderSession: liveRenderSession,
                        playbackController: playbackController
                    )
                    self.playbackWasExplicitlyStopped = false
                }

                let latestPlaybackState = playbackController.state()
                self.playbackState = latestPlaybackState
                self.updatePlaybackFollowState(with: latestPlaybackState)
                self.playbackErrorMessage = nil
            } catch {
                self?.playbackErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func stopPlayback() {
        guard
            let playbackController,
            session.capabilities.supportsPlayback,
            !isPlaybackActionInFlight
        else {
            return
        }

        isPlaybackActionInFlight = true
        playbackWasExplicitlyStopped = true
        playbackErrorMessage = nil
        playbackPreparationMessage = nil

        Task { @MainActor [weak self] in
            defer {
                self?.isPlaybackActionInFlight = false
            }

            do {
                self?.loadPlaybackContextIfNeeded()
                if playbackController.isLoaded {
                    try playbackController.stop()
                }
                let latestPlaybackState = playbackController.state()
                self?.playbackState = latestPlaybackState
                self?.updatePlaybackFollowState(with: latestPlaybackState)
                self?.playbackErrorMessage = nil
            } catch {
                self?.playbackErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func toggleMetronome() {
        guard session.capabilities.supportsPlayback else {
            return
        }

        metronomeEnabled.toggle()
        playbackController?.setMetronomeEnabled(metronomeEnabled)
    }

    func toggleCountIn() {
        guard session.capabilities.supportsPlayback else { return }
        countInEnabled.toggle()
        UserDefaults.standard.set(countInEnabled, forKey: "ScoreReader.countInEnabled")
    }

    private func playWithOptionalCountIn(
        at startTimeSeconds: TimeInterval,
        liveRenderSession: LiveScoreRenderSession,
        playbackController: NativePlaybackController
    ) async throws {
        let countIn = countInEnabled
            ? try await liveRenderSession.playbackCountIn(startTimeSeconds: startTimeSeconds)
            : nil
        try playbackController.play(countIn: countIn)
    }

    func seekPlayback(to progress: Double) {
        guard
            let liveRenderSession = session.liveRenderSession,
            let playbackController,
            session.capabilities.supportsPlayback,
            !isPlaybackActionInFlight
        else {
            return
        }

        if playbackController.isWaitingToStartPlayback {
            playbackPreparationMessage = playbackPreparationStartingMessage
            return
        }

        isPlaybackActionInFlight = true
        playbackErrorMessage = nil
        playbackPreparationMessage = playbackController.isLoaded ? nil : playbackPreparationStartingMessage

        Task { @MainActor [weak self] in
            defer {
                self?.isPlaybackActionInFlight = false
                self?.updatePlaybackPreparationMessage(for: playbackController)
            }

            do {
                guard let self else {
                    return
                }

                try await self.waitForPendingPartSelection()
                if self.playbackMeasureRegions.isEmpty {
                    self.playbackMeasureRegions = try await liveRenderSession.playbackMeasureRegions()
                } else {
                    self.loadPlaybackContextIfNeeded()
                }
                try await self.preparePlaybackIfNeeded(
                    liveRenderSession: liveRenderSession,
                    playbackController: playbackController
                )

                let latestDuration = max(
                    playbackController.state().durationSeconds,
                    self.playbackMeasureRegions.map(\.endTimeSeconds).max() ?? 0
                )
                let targetPosition = min(max(progress, 0), 1) * latestDuration
                try playbackController.seek(to: targetPosition)

                let latestPlaybackState = playbackController.state()
                self.playbackState = latestPlaybackState
                self.updatePlaybackFollowState(with: latestPlaybackState)
                self.playbackErrorMessage = nil
            } catch {
                self?.playbackErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func playFromSelection() {
        guard
            let liveRenderSession = session.liveRenderSession,
            let playbackController,
            session.capabilities.supportsPlayback,
            !isPlaybackActionInFlight
        else {
            return
        }

        notePreviewController.stopAll()

        isPlaybackActionInFlight = true
        playbackErrorMessage = nil
        playbackPreparationMessage = playbackController.isLoaded ? nil : playbackPreparationStartingMessage

        Task { @MainActor [weak self] in
            defer {
                self?.isPlaybackActionInFlight = false
                self?.updatePlaybackPreparationMessage(for: playbackController)
            }

            do {
                guard let self else {
                    return
                }

                try await self.waitForPendingPartSelection()
                if self.playbackMeasureRegions.isEmpty {
                    self.playbackMeasureRegions = try await liveRenderSession.playbackMeasureRegions()
                } else {
                    self.loadPlaybackContextIfNeeded()
                }
                try await self.preparePlaybackIfNeeded(
                    liveRenderSession: liveRenderSession,
                    playbackController: playbackController
                )

                let region = self.playbackRegionForCurrentSelection()
                let startTimeSeconds = region?.startTimeSeconds ?? 0
                try playbackController.seek(to: startTimeSeconds)
                try await self.playWithOptionalCountIn(
                    at: startTimeSeconds,
                    liveRenderSession: liveRenderSession,
                    playbackController: playbackController
                )

                let latestPlaybackState = playbackController.state()
                self.playbackState = latestPlaybackState
                self.updatePlaybackFollowState(with: latestPlaybackState)
                self.playbackErrorMessage = nil
            } catch {
                self?.playbackErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func loadPlaybackContextIfNeeded() {
        guard
            playbackContextTask == nil,
            partSelectionTask == nil,
            session.capabilities.supportsPlayback,
            let liveRenderSession = session.liveRenderSession
        else {
            return
        }

        playbackContextTask = Task { @MainActor [weak self] in
            defer {
                self?.playbackContextTask = nil
            }

            do {
                let playbackMeasureRegions = try await liveRenderSession.playbackMeasureRegions()
                self?.playbackMeasureRegions = playbackMeasureRegions
                if let playbackState = self?.playbackState {
                    self?.updatePlaybackFollowState(with: playbackState)
                }
            } catch {
                // Playback can still work without score-follow data.
            }
        }
    }

    func startPlaybackWarmup(delay: Duration = .milliseconds(450)) {
        guard
            playbackWarmupTask == nil,
            partSelectionTask == nil,
            session.capabilities.supportsPlayback,
            let liveRenderSession = session.liveRenderSession,
            let playbackController,
            !playbackController.isLoaded
        else {
            return
        }

        let warmupRevision = playbackWarmupRevision
        playbackWarmupTask = Task { @MainActor [weak self] in
            if delay > .zero {
                try await Task.sleep(for: delay)
            }

            let startedAt = Date()
            try Task.checkCancellation()
            let regions = try await liveRenderSession.playbackMeasureRegions()
            let durationSeconds = regions.map(\.endTimeSeconds).max() ?? 0
            try Task.checkCancellation()

            guard
                let self,
                self.playbackWarmupRevision == warmupRevision,
                !playbackController.isLoaded
            else {
                return
            }

            if self.playbackMeasureRegions.isEmpty {
                self.playbackMeasureRegions = regions
                self.updatePlaybackFollowState(with: self.playbackState)
            }

            try await playbackController.prepare(liveRenderSession: liveRenderSession, durationSeconds: durationSeconds, metronomeEnabled: metronomeEnabled)
            let elapsed = Date().timeIntervalSince(startedAt)
            print(String(format: "Aria playback warmup: duration=%.2fs elapsed=%.3fs revision=%d", durationSeconds, elapsed, warmupRevision))
        }
    }

    func preparePlaybackIfNeeded(
        liveRenderSession: LiveScoreRenderSession,
        playbackController: NativePlaybackController
    ) async throws {
        try await waitForPendingPartSelection()

        guard !playbackController.isLoaded else {
            return
        }

        if playbackWarmupTask == nil {
            startPlaybackWarmup(delay: .zero)
        }

        do {
            if let playbackWarmupTask {
                try await playbackWarmupTask.value
                self.playbackWarmupTask = nil
            }
        } catch is CancellationError {
            self.playbackWarmupTask = nil
        } catch {
            self.playbackWarmupTask = nil
            throw error
        }

        guard !playbackController.isLoaded else {
            return
        }

        let regions = try await liveRenderSession.playbackMeasureRegions()
        let durationSeconds = regions.map(\.endTimeSeconds).max() ?? 0
        try await playbackController.prepare(liveRenderSession: liveRenderSession, durationSeconds: durationSeconds, metronomeEnabled: metronomeEnabled)
    }

    func waitForPendingPartSelection() async throws {
        if let partSelectionTask {
            playbackPreparationMessage = "Preparing part..."
            await partSelectionTask.value
        }

        if let partSelectionErrorMessage {
            throw NSError(
                domain: "ScoreReaderPartSelection",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: partSelectionErrorMessage]
            )
        }
    }

    func invalidatePlaybackAfterScoreMutation(startWarmup: Bool = false) {
        let startedAt = Date()
        playbackContextTask?.cancel()
        playbackContextTask = nil
        playbackWarmupTask?.cancel()
        playbackWarmupTask = nil
        playbackWarmupRevision += 1
        playbackMeasureRegions = []
        playbackMeasureHighlight = nil
        playbackController?.invalidate()
        clearPlaybackLoop()
        playbackState = session.capabilities.supportsPlayback
            ? ScorePlaybackState(isAvailable: true, status: .stopped, positionSeconds: 0, durationSeconds: 0)
            : .unavailable
        playbackErrorMessage = nil
        playbackPreparationMessage = nil
        if startWarmup {
            startPlaybackWarmup(delay: .milliseconds(900))
        }
        let elapsed = Date().timeIntervalSince(startedAt)
        print(String(format: "Aria playback invalidated after edit: elapsed=%.3fs warmup=%@", elapsed, startWarmup.description))
    }

    private func updatePlaybackPreparationMessage(for playbackController: NativePlaybackController) {
        if let error = playbackController.streamingErrorMessage {
            playbackErrorMessage = error
        }
        if playbackController.isWaitingToStartPlayback {
            playbackPreparationMessage = playbackPreparationStartingMessage
        } else if !isPlaybackActionInFlight, playbackPreparationMessage == playbackPreparationStartingMessage {
            playbackPreparationMessage = nil
        }
    }

    func updatePlaybackFollowState(with playbackState: ScorePlaybackState) {
        if playbackState.status != .playing {
            playbackFollowIsSuspended = false
        }

        guard let activeRegion = activePlaybackMeasureRegion(for: playbackState) else {
            playbackMeasureHighlight = nil
            return
        }

        let followPositionSeconds = adjustedPlaybackPositionSeconds(for: playbackState)
        let regionDuration = max(activeRegion.endTimeSeconds - activeRegion.startTimeSeconds, 0.001)
        let playbackProgress = min(
            max((followPositionSeconds - activeRegion.startTimeSeconds) / regionDuration, 0),
            1
        )

        playbackMeasureHighlight = ScorePlaybackMeasureHighlight(
            pageIndex: activeRegion.pageIndex,
            normalizedRect: activeRegion.normalizedRect,
            progress: playbackProgress
        )

        if playbackState.status == .playing,
           shouldFollowPlayback,
           activeRegion.pageIndex != selectedPageIndex
        {
            updateSelection(to: activeRegion.pageIndex)
        }
    }

    func activePlaybackMeasureRegion(for playbackState: ScorePlaybackState) -> ScorePlaybackMeasureRegion? {
        guard
            !playbackMeasureRegions.isEmpty,
            playbackState.isAvailable,
            playbackState.status != .stopped,
            playbackState.status != .unavailable
        else {
            return nil
        }

        let positionSeconds = adjustedPlaybackPositionSeconds(for: playbackState)
        var lowerBound = 0
        var upperBound = playbackMeasureRegions.count

        while lowerBound < upperBound {
            let midpoint = (lowerBound + upperBound) / 2
            if playbackMeasureRegions[midpoint].startTimeSeconds <= positionSeconds {
                lowerBound = midpoint + 1
            } else {
                upperBound = midpoint
            }
        }

        let candidateIndex = max(lowerBound - 1, 0)
        let candidate = playbackMeasureRegions[candidateIndex]
        let playbackEpsilon = 0.02

        guard positionSeconds + playbackEpsilon >= candidate.startTimeSeconds else {
            return nil
        }

        if candidateIndex < playbackMeasureRegions.count - 1 {
            let nextRegion = playbackMeasureRegions[candidateIndex + 1]
            if positionSeconds >= nextRegion.startTimeSeconds {
                return nextRegion
            }
        }

        guard positionSeconds <= candidate.endTimeSeconds + playbackEpsilon || candidateIndex == playbackMeasureRegions.count - 1 else {
            return nil
        }

        return candidate
    }

    func playbackRegionForCurrentSelection() -> ScorePlaybackMeasureRegion? {
        guard let selection = editingState.selection else {
            return nil
        }

        if playbackMeasureRegions.isEmpty {
            loadPlaybackContextIfNeeded()
        }

        let selectionRects = selection.highlightRects.isEmpty ? [selection.normalizedRect] : selection.highlightRects
        let overlappedRegions = playbackMeasureRegions
            .filter { region in
                region.pageIndex == selection.pageIndex
                    && selectionRects.contains { overlapArea(region.normalizedRect, $0) > 0 }
            }
        return overlappedRegions.min { lhs, rhs in
            lhs.startTimeSeconds < rhs.startTimeSeconds
        } ?? playbackMeasureRegions
            .filter { $0.pageIndex == selection.pageIndex }
            .max { lhs, rhs in
                maxOverlapArea(lhs.normalizedRect, selectionRects) < maxOverlapArea(rhs.normalizedRect, selectionRects)
            }
    }

    private func overlapArea(_ lhs: ScoreNormalizedRect, _ rhs: ScoreNormalizedRect) -> Double {
        let minX = max(lhs.x, rhs.x)
        let minY = max(lhs.y, rhs.y)
        let maxX = min(lhs.x + lhs.width, rhs.x + rhs.width)
        let maxY = min(lhs.y + lhs.height, rhs.y + rhs.height)
        return max(maxX - minX, 0) * max(maxY - minY, 0)
    }

    private func maxOverlapArea(_ rect: ScoreNormalizedRect, _ candidates: [ScoreNormalizedRect]) -> Double {
        candidates.map { overlapArea(rect, $0) }.max() ?? 0
    }

    func adjustedPlaybackPositionSeconds(for playbackState: ScorePlaybackState) -> TimeInterval {
        let rawPositionSeconds = max(playbackState.positionSeconds, 0)
        guard playbackState.status == .playing else {
            return rawPositionSeconds
        }

        let compensationSeconds = (playbackController?.visualLatencyCompensationSeconds() ?? 0) + playbackVisualSyncTrimSeconds
        return min(max(rawPositionSeconds - compensationSeconds, 0), playbackState.durationSeconds)
    }

    // MARK: - View-mode playback selection

    /// View-mode long press: resolve the measure under the finger and offer to
    /// start playback from its first beat. Measure regions load lazily with
    /// playback prep, so a press before anything has played kicks the load and
    /// retries once it lands.
    func presentPlayFromHere(atNormalizedPoint point: CGPoint, pageIndex: Int) {
        guard session.capabilities.supportsPlayback else {
            return
        }

        clearPlaybackLoop()
        pendingPlaybackSelectionStartPoint = point
        pendingPlaybackSelectionEndPoint = point
        pendingPlaybackSelectionPageIndex = pageIndex

        if let region = playbackRegion(atNormalizedPoint: point, pageIndex: pageIndex) {
            playFromHereTarget = ScorePlayFromHereTarget(region: region)
            return
        }

        guard playbackMeasureRegions.isEmpty, let liveRenderSession = session.liveRenderSession else {
            return
        }

        Task { @MainActor [weak self] in
            guard
                let self,
                let regions = try? await liveRenderSession.playbackMeasureRegions()
            else {
                return
            }

            if self.playbackMeasureRegions.isEmpty {
                self.playbackMeasureRegions = regions
            }

            self.resolvePendingPlaybackSelection()
        }
    }

    /// Extends the view-mode long press into a measure range. Keeping this in
    /// playback state means the highlighted bars and loop times are resolved
    /// from the same MuseScore timeline.
    func updatePlaybackLoopSelection(
        fromNormalizedPoint startPoint: CGPoint,
        toNormalizedPoint endPoint: CGPoint,
        pageIndex: Int
    ) {
        guard session.capabilities.supportsPlayback else {
            return
        }

        pendingPlaybackSelectionStartPoint = startPoint
        pendingPlaybackSelectionEndPoint = endPoint
        pendingPlaybackSelectionPageIndex = pageIndex
        resolvePendingPlaybackSelection()
    }

    private func resolvePendingPlaybackSelection() {
        guard
            let startPoint = pendingPlaybackSelectionStartPoint,
            let endPoint = pendingPlaybackSelectionEndPoint,
            let pageIndex = pendingPlaybackSelectionPageIndex,
            let startRegion = playbackRegion(atNormalizedPoint: startPoint, pageIndex: pageIndex),
            let endRegion = playbackRegion(atNormalizedPoint: endPoint, pageIndex: pageIndex)
        else {
            return
        }

        guard startRegion.measureIndex != endRegion.measureIndex else {
            playbackLoopRange = nil
            playbackLoopIsActive = false
            playFromHereTarget = ScorePlayFromHereTarget(region: startRegion)
            return
        }

        guard let range = playbackLoopRange(from: startRegion, through: endRegion) else {
            return
        }

        playFromHereTarget = nil
        playbackLoopRange = range
        playbackLoopIsActive = false
    }

    private func playbackLoopRange(
        from firstRegion: ScorePlaybackMeasureRegion,
        through secondRegion: ScorePlaybackMeasureRegion
    ) -> ScorePlaybackLoopRange? {
        guard firstRegion.pageIndex == secondRegion.pageIndex else {
            return nil
        }

        let lowerMeasureIndex = min(firstRegion.measureIndex, secondRegion.measureIndex)
        let upperMeasureIndex = max(firstRegion.measureIndex, secondRegion.measureIndex)
        let pageRegions = playbackMeasureRegions.filter {
            $0.pageIndex == firstRegion.pageIndex
                && (lowerMeasureIndex...upperMeasureIndex).contains($0.measureIndex)
        }

        var visualRegionByMeasureIndex: [Int: ScorePlaybackMeasureRegion] = [:]
        for region in pageRegions where visualRegionByMeasureIndex[region.measureIndex] == nil {
            visualRegionByMeasureIndex[region.measureIndex] = region
        }
        let visualRegions = visualRegionByMeasureIndex.values.sorted {
            $0.measureIndex < $1.measureIndex
        }

        guard
            let timelineStart = pageRegions
                .filter({ $0.measureIndex == lowerMeasureIndex })
                .min(by: { $0.startTimeSeconds < $1.startTimeSeconds }),
            let timelineEnd = pageRegions
                .filter({
                    $0.measureIndex == upperMeasureIndex
                        && $0.startTimeSeconds >= timelineStart.startTimeSeconds
                })
                .min(by: { $0.startTimeSeconds < $1.startTimeSeconds }),
            timelineEnd.endTimeSeconds > timelineStart.startTimeSeconds,
            !visualRegions.isEmpty
        else {
            return nil
        }

        return ScorePlaybackLoopRange(
            pageIndex: firstRegion.pageIndex,
            startMeasureIndex: lowerMeasureIndex,
            endMeasureIndex: upperMeasureIndex,
            normalizedRects: visualRegions.map(\.normalizedRect),
            startTimeSeconds: timelineStart.startTimeSeconds,
            endTimeSeconds: timelineEnd.endTimeSeconds
        )
    }

    func dismissPlayFromHere() {
        playFromHereTarget = nil
        pendingPlaybackSelectionStartPoint = nil
        pendingPlaybackSelectionEndPoint = nil
        pendingPlaybackSelectionPageIndex = nil
        if !playbackLoopIsActive {
            playbackLoopRange = nil
        }
    }

    func clearPlaybackLoop() {
        playbackController?.clearLoopRange()
        playbackLoopIsActive = false
        playbackLoopRange = nil
        playFromHereTarget = nil
        pendingPlaybackSelectionStartPoint = nil
        pendingPlaybackSelectionEndPoint = nil
        pendingPlaybackSelectionPageIndex = nil
    }

    /// The measure containing `point`. A press landing in the gap between
    /// staves falls back to the nearest measure, preferring one whose
    /// horizontal span already covers the press so the choice tracks the
    /// column the finger is in.
    func playbackRegion(atNormalizedPoint point: CGPoint, pageIndex: Int) -> ScorePlaybackMeasureRegion? {
        let pageRegions = playbackMeasureRegions.filter { $0.pageIndex == pageIndex }
        guard !pageRegions.isEmpty else {
            return nil
        }

        let x = Double(point.x)
        let y = Double(point.y)

        if let hit = pageRegions.first(where: { $0.normalizedRect.contains(x: x, y: y) }) {
            return hit
        }

        let horizontallyAligned = pageRegions.filter { $0.normalizedRect.spansHorizontally(x) }
        if !horizontallyAligned.isEmpty {
            return horizontallyAligned.min {
                $0.normalizedRect.verticalDistance(to: y) < $1.normalizedRect.verticalDistance(to: y)
            }
        }

        return pageRegions.min {
            $0.normalizedRect.distanceSquared(toX: x, y: y) < $1.normalizedRect.distanceSquared(toX: x, y: y)
        }
    }

    /// Starts playback at the pending target. Mirrors `playFromSelection()`,
    /// which sources its region from the edit-mode selection instead.
    func playFromHere() {
        guard
            let target = playFromHereTarget,
            let liveRenderSession = session.liveRenderSession,
            let playbackController,
            session.capabilities.supportsPlayback,
            !isPlaybackActionInFlight
        else {
            return
        }

        notePreviewController.stopAll()

        playFromHereTarget = nil
        isPlaybackActionInFlight = true
        playbackErrorMessage = nil
        playbackPreparationMessage = playbackController.isLoaded ? nil : playbackPreparationStartingMessage

        Task { @MainActor [weak self] in
            defer {
                self?.isPlaybackActionInFlight = false
                self?.updatePlaybackPreparationMessage(for: playbackController)
            }

            do {
                guard let self else {
                    return
                }

                try await self.waitForPendingPartSelection()
                if self.playbackMeasureRegions.isEmpty {
                    self.playbackMeasureRegions = try await liveRenderSession.playbackMeasureRegions()
                } else {
                    self.loadPlaybackContextIfNeeded()
                }
                try await self.preparePlaybackIfNeeded(
                    liveRenderSession: liveRenderSession,
                    playbackController: playbackController
                )

                try playbackController.seek(to: target.startTimeSeconds)
                try await self.playWithOptionalCountIn(
                    at: target.startTimeSeconds,
                    liveRenderSession: liveRenderSession,
                    playbackController: playbackController
                )

                let latestPlaybackState = playbackController.state()
                self.playbackState = latestPlaybackState
                self.updatePlaybackFollowState(with: latestPlaybackState)
                self.playbackErrorMessage = nil
            } catch {
                self?.playbackErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func loopFromHere() {
        guard let target = playFromHereTarget else {
            return
        }

        playbackLoopRange = ScorePlaybackLoopRange(
            pageIndex: target.pageIndex,
            startMeasureIndex: target.measureIndex,
            endMeasureIndex: target.measureIndex,
            normalizedRects: [target.normalizedRect],
            startTimeSeconds: target.startTimeSeconds,
            endTimeSeconds: playbackMeasureRegions
                .first(where: {
                    $0.measureIndex == target.measureIndex
                        && $0.pageIndex == target.pageIndex
                        && $0.startTimeSeconds == target.startTimeSeconds
                })?.endTimeSeconds ?? target.startTimeSeconds
        )
        playFromHereTarget = nil
        startSelectedPlaybackLoop()
    }

    func toggleSelectedPlaybackLoop() {
        if playbackLoopIsActive {
            clearPlaybackLoop()
        } else {
            startSelectedPlaybackLoop()
        }
    }

    private func startSelectedPlaybackLoop() {
        guard
            let range = playbackLoopRange,
            range.endTimeSeconds > range.startTimeSeconds,
            let liveRenderSession = session.liveRenderSession,
            let playbackController,
            session.capabilities.supportsPlayback,
            !isPlaybackActionInFlight
        else {
            return
        }

        notePreviewController.stopAll()
        playbackLoopIsActive = true
        playbackWasExplicitlyStopped = false
        isPlaybackActionInFlight = true
        playbackErrorMessage = nil
        playbackPreparationMessage = playbackController.isLoaded ? nil : playbackPreparationStartingMessage

        Task { @MainActor [weak self] in
            defer {
                self?.isPlaybackActionInFlight = false
                self?.updatePlaybackPreparationMessage(for: playbackController)
            }

            do {
                guard let self else {
                    return
                }

                try await self.waitForPendingPartSelection()
                if self.playbackMeasureRegions.isEmpty {
                    self.playbackMeasureRegions = try await liveRenderSession.playbackMeasureRegions()
                } else {
                    self.loadPlaybackContextIfNeeded()
                }
                try await self.preparePlaybackIfNeeded(
                    liveRenderSession: liveRenderSession,
                    playbackController: playbackController
                )

                guard self.playbackLoopIsActive, self.playbackLoopRange == range else {
                    return
                }

                try await playbackController.setLoopRange(
                    startTimeSeconds: range.startTimeSeconds,
                    endTimeSeconds: range.endTimeSeconds
                )
                try await self.playWithOptionalCountIn(
                    at: range.startTimeSeconds,
                    liveRenderSession: liveRenderSession,
                    playbackController: playbackController
                )

                let latestPlaybackState = playbackController.state()
                self.playbackState = latestPlaybackState
                self.updatePlaybackFollowState(with: latestPlaybackState)
                self.playbackErrorMessage = nil
            } catch {
                self?.playbackController?.clearLoopRange()
                self?.playbackLoopIsActive = false
                self?.playbackErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

}

extension ScoreReaderState {
    func updateMixer(_ settings: ScoreMixerSettings) {
        mixerSettings = settings
        playbackController?.setMixerSettings(settings)
        ScoreMixerSettingsStore().save(settings, scoreID: session.document.id)
    }

    func setMixerMeteringEnabled(_ enabled: Bool) {
        playbackController?.setMeteringEnabled(enabled)
        if !enabled {
            mixerLevelMonitor.update([:])
        }
    }
}
