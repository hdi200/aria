import Foundation

@MainActor
extension ScoreReaderState {
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

        isPlaybackActionInFlight = true
        playbackErrorMessage = nil
        playbackPreparationMessage = playbackController.isLoaded ? nil : "Preparing playback..."

        Task { @MainActor [weak self] in
            defer {
                self?.isPlaybackActionInFlight = false
                self?.playbackPreparationMessage = nil
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
                    try playbackController.pause()
                } else if currentState.status == .paused {
                    try playbackController.play()
                } else {
                    let shouldUseSelection = self.editingState.selection != nil
                    let startTimeSeconds = shouldUseSelection
                        ? (self.playbackRegionForCurrentSelection()?.startTimeSeconds ?? 0)
                        : 0
                    try playbackController.seek(to: startTimeSeconds)
                    try playbackController.play()
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
                self?.playbackWasExplicitlyStopped = true
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

    func seekPlayback(to progress: Double) {
        guard
            let liveRenderSession = session.liveRenderSession,
            let playbackController,
            session.capabilities.supportsPlayback,
            !isPlaybackActionInFlight
        else {
            return
        }

        isPlaybackActionInFlight = true
        playbackErrorMessage = nil
        playbackPreparationMessage = playbackController.isLoaded ? nil : "Preparing playback..."

        Task { @MainActor [weak self] in
            defer {
                self?.isPlaybackActionInFlight = false
                self?.playbackPreparationMessage = nil
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

        isPlaybackActionInFlight = true
        playbackErrorMessage = nil
        playbackPreparationMessage = playbackController.isLoaded ? nil : "Preparing playback..."

        Task { @MainActor [weak self] in
            defer {
                self?.isPlaybackActionInFlight = false
                self?.playbackPreparationMessage = nil
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
                try playbackController.seek(to: region?.startTimeSeconds ?? 0)
                try playbackController.play()

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


    func updatePlaybackFollowState(with playbackState: ScorePlaybackState) {
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

        if playbackState.status == .playing, activeRegion.pageIndex != selectedPageIndex {
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

        let compensationSeconds = playbackController?.visualLatencyCompensationSeconds() ?? 0
        return min(rawPositionSeconds + compensationSeconds, playbackState.durationSeconds)
    }

}
