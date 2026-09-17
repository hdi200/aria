//
//  NativePlaybackController.swift
//  MuseReaderiOS
//
//

import AVFoundation
import Foundation

@MainActor
final class NativePlaybackController {
    enum PlaybackError: LocalizedError {
        case audioSessionUnavailable(String)
        case soundBankUnavailable(String)
        case sequenceLoadFailed(String)
        case playerInitializationFailed(String)
        case playerUnavailable
        case invalidLoopRange

        var errorDescription: String? {
            switch self {
            case .audioSessionUnavailable(let message):
                return "Aria could not prepare the iPad audio session: \(message)"
            case .soundBankUnavailable(let message):
                return "Aria could not find the MuseScore sound bank: \(message)"
            case .sequenceLoadFailed(let message):
                return "Aria could not prepare live playback audio: \(message)"
            case .playerInitializationFailed(let message):
                return "Aria could not prepare playback: \(message)"
            case .playerUnavailable:
                return "Playback is unavailable because the audio engine player is not ready yet."
            case .invalidLoopRange:
                return "The selected playback loop is too short."
            }
        }
    }

    private var chunkDurationSeconds: TimeInterval {
        if usesSoftwareStemPlayback {
            // A short queue keeps software-mixed fader, pan, mute, solo, and
            // metronome changes responsive without putting work on the audio thread.
            return 0.125
        }
        let bytesPerSecond = sampleRate * 8 * Double(max(stemPlayers.count, 1))
        return min(0.5, max(0.05, 4 * 1_024 * 1_024 / bytesPerSecond))
    }
    private let prebufferChunks = 4
    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?

    /// Stream ids for the one player node used by either playback source.
    private static let mixedStreamID = "mixed"
    private static let softwareStemMixStreamID = "stem-software-mix"

    private var stemPlayers: [String: AVAudioPlayerNode] = [:]
    private var usesSoftwareStemPlayback = false
    private var renderedStemIDs: Set<String> = []
    private var nextScheduledSampleTime: AVAudioFramePosition = 0
    private var needsPlayerPriming = true
    private var mixerSettings = ScoreMixerSettings()
    private var meterLevelHandler: (([String: Float]) -> Void)?
    private var meterPeaks: [String: Float] = [:]
    private var displayedMeterLevels: [String: Float] = [:]
    private var meterUpdateTask: Task<Void, Never>?
    private var isMeteringEnabled = false
    private var meterTapsInstalled = false
    private(set) var streamingErrorMessage: String?

    nonisolated static let masterMeterID = "__muse_reader_master__"

    func setMixerSettings(_ settings: ScoreMixerSettings) {
        mixerSettings = settings
        applyMixerSettings()
        refreshScheduledLoopBuffer()
    }

    func setMeterLevelHandler(_ handler: (([String: Float]) -> Void)?) {
        meterLevelHandler = handler
    }

    func setMeteringEnabled(_ enabled: Bool) {
        guard enabled != isMeteringEnabled else { return }
        isMeteringEnabled = enabled

        if enabled {
            installMeterTapsIfPossible()
            startMeterUpdates()
        } else {
            removeMeterTaps()
            meterUpdateTask?.cancel()
            meterUpdateTask = nil
            meterPeaks.removeAll()
            displayedMeterLevels.removeAll()
            meterLevelHandler?([:])
        }
    }

    private func applyMixerSettings() {
        engine?.mainMixerNode.outputVolume = mixerSettings.masterMuted
            ? 0 : min(max(mixerSettings.masterVolume, 0), 1)
        engine?.mainMixerNode.pan = min(max(mixerSettings.masterPan, -1), 1)
        playerNode?.volume = 1
        playerNode?.pan = 0
    }
    private var liveRenderSession: LiveScoreRenderSession?
    private var metronomeEnabled = false
    private var revision = 0
    private var sampleRate: Double = 48_000
    private var durationSeconds: TimeInterval = 0
    private var queuedUntilSeconds: TimeInterval = 0
    private var pendingStartSeconds: TimeInterval = 0
    private var timelineClock = PlaybackTimelineClock()
    private var bufferProgress = PlaybackBufferProgress()
    private var isPaused = false
    private var isScheduling = false
    private var schedulingTask: Task<Void, Never>?
    private var playWhenBuffered = false
    private var loopRange: PlaybackLoopTimeline?
    private var loopAudioData: MSRPlaybackAudioData?
    private var loopBufferIsScheduled = false
    private var loopPartMeterLevels: [String: Float] = [:]
    private var loopRemixTask: Task<Void, Never>?

    var isLoaded: Bool {
        engine != nil && playerNode != nil && liveRenderSession != nil
    }

    var isWaitingToStartPlayback: Bool {
        playWhenBuffered
    }

    func prepare(liveRenderSession: LiveScoreRenderSession, durationSeconds: TimeInterval, metronomeEnabled: Bool) async throws {
        guard !isLoaded else {
            log("prepare skipped: already loaded revision=\(revision)")
            return
        }

        streamingErrorMessage = nil
        let prepareRevision = revision
        log("prepare begin pendingStart=\(formatSeconds(pendingStartSeconds)) requestedDuration=\(formatSeconds(durationSeconds)) revision=\(revision)")
        self.metronomeEnabled = metronomeEnabled
        do {
            try await Task.detached(priority: .userInitiated) {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.playback, mode: .default, options: [])
                try audioSession.setActive(true)
            }.value
        } catch {
            throw PlaybackError.audioSessionUnavailable(error.localizedDescription)
        }
        try Task.checkCancellation()
        guard prepareRevision == revision else {
            throw CancellationError()
        }

        let audioData = try await liveRenderSession.playbackAudioChunk(
            startTimeSeconds: pendingStartSeconds,
            durationSeconds: 0.125, // Discover the stem layout without a large initial allocation.
            metronomeEnabled: true
        )
        try Task.checkCancellation()
        guard prepareRevision == revision else {
            throw CancellationError()
        }
        log("prepare audio sampleRate=\(audioData.sampleRate) channels=\(audioData.channelCount) bytes=\(audioData.interleavedFloat32Samples.count) duration=\(formatSeconds(audioData.durationSeconds))")
        guard audioData.channelCount == 2, !audioData.interleavedFloat32Samples.isEmpty else {
            throw PlaybackError.sequenceLoadFailed("The live playback render was empty or unsupported.")
        }

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(audioData.sampleRate),
            channels: AVAudioChannelCount(audioData.channelCount),
            interleaved: false
        ) else {
            throw PlaybackError.playerInitializationFailed("The live playback audio format could not be created.")
        }

        let engine = AVAudioEngine()
        let usesSoftwareStemMix = !audioData.partSamples.isEmpty
        let streamIDs = [usesSoftwareStemMix ? Self.softwareStemMixStreamID : Self.mixedStreamID]
        log("playback path=\(usesSoftwareStemMix ? "software-mixed stems" : "single mixed fallback") players=1")
        var players: [String: AVAudioPlayerNode] = [:]
        for id in streamIDs {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players[id] = player
        }
        let playerNode = players[streamIDs[0]]!
        engine.prepare()

        do {
            try engine.start()
        } catch {
            throw PlaybackError.playerInitializationFailed(error.localizedDescription)
        }
        guard prepareRevision == revision else {
            engine.stop()
            throw CancellationError()
        }

        self.engine = engine
        self.playerNode = playerNode
        self.stemPlayers = players
        self.usesSoftwareStemPlayback = usesSoftwareStemMix
        self.renderedStemIDs = Set(audioData.partSamples.keys)
        applyMixerSettings()
        installMeterTapsIfPossible()
        self.liveRenderSession = liveRenderSession
        self.sampleRate = Double(audioData.sampleRate)
        self.durationSeconds = max(durationSeconds, audioData.durationSeconds)
        self.queuedUntilSeconds = pendingStartSeconds
        self.timelineClock.reset(to: pendingStartSeconds)
        self.bufferProgress.reset(to: pendingStartSeconds)
        self.isPaused = false
        self.nextScheduledSampleTime = 0
        self.needsPlayerPriming = true

        try schedule(audioData: audioData, startsAt: pendingStartSeconds, revision: prepareRevision)
        fillPlaybackQueue(revision: prepareRevision)
        log("prepare ready duration=\(formatSeconds(self.durationSeconds)) queuedUntil=\(formatSeconds(queuedUntilSeconds)) revision=\(revision)")
    }

    func state() -> ScorePlaybackState {
        guard let playerNode else {
            return ScorePlaybackState(isAvailable: true, status: .stopped, positionSeconds: pendingStartSeconds, durationSeconds: durationSeconds)
        }

        var positionSeconds = currentPositionSeconds()
        var status: ScorePlaybackStatus = (playerNode.isPlaying || playWhenBuffered) ? .playing : (isPaused ? .paused : .stopped)

        if loopRange == nil, durationSeconds > 0, positionSeconds >= durationSeconds {
            stopInternally()
            positionSeconds = 0
            status = .stopped
        }

        return ScorePlaybackState(isAvailable: true, status: status, positionSeconds: positionSeconds, durationSeconds: durationSeconds)
    }

    func play() throws {
        guard let engine, let playerNode else {
            throw PlaybackError.playerUnavailable
        }

        streamingErrorMessage = nil
        if loopRange != nil, !loopBufferIsScheduled {
            try scheduleLoopBuffer()
        }
        try startPlaybackWhenBuffered(engine: engine, playerNode: playerNode)
        fillPlaybackQueue(revision: revision)

        log("play requested position=\(formatSeconds(pendingStartSeconds)) duration=\(formatSeconds(durationSeconds)) queuedUntil=\(formatSeconds(queuedUntilSeconds)) armed=\(playWhenBuffered) revision=\(revision)")
    }

    func pause() throws {
        guard let playerNode else {
            throw PlaybackError.playerUnavailable
        }
        if playWhenBuffered {
            playWhenBuffered = false
            timelineClock.pauseFallback(at: pendingStartSeconds)
            isPaused = true
            log("pause armed playback position=\(formatSeconds(pendingStartSeconds)) revision=\(revision)")
            return
        }
        guard playerNode.isPlaying else {
            return
        }

        pendingStartSeconds = currentPositionSeconds()
        timelineClock.pauseFallback(at: pendingStartSeconds)
        stemPlayers.values.forEach { $0.pause() }
        isPaused = true
        log("pause position=\(formatSeconds(pendingStartSeconds)) revision=\(revision)")
    }

    func stop() throws {
        guard playerNode != nil else {
            throw PlaybackError.playerUnavailable
        }

        stopInternally()
    }

    func seek(to positionSeconds: TimeInterval) throws {
        guard playerNode != nil else {
            throw PlaybackError.playerUnavailable
        }

        // A looping player always begins at the start of its cached PCM pass.
        // Keeping the visual clock on the same origin avoids a scrub action
        // making the highlight disagree with the audio.
        let targetPosition = loopRange?.startTimeSeconds ?? bounded(positionSeconds)
        let wasPlaying = playerNode?.isPlaying == true || playWhenBuffered
        let samePositionTolerance = 1 / max(sampleRate, 1)
        if !wasPlaying, abs(targetPosition - pendingStartSeconds) <= samePositionTolerance {
            log("seek reused prepared position=\(formatSeconds(targetPosition)) "
                + "queued=\(formatSeconds(max(queuedUntilSeconds - targetPosition, 0)))s revision=\(revision)")
            return
        }

        resetPlaybackQueue(to: targetPosition, wasPlaying: wasPlaying)
        log("seek position=\(formatSeconds(pendingStartSeconds)) wasPlaying=\(wasPlaying) revision=\(revision)")

        if wasPlaying {
            try play()
        }
    }

    /// Renders a score-time range once and schedules that exact PCM pass as a
    /// continuous audio-node loop.
    func setLoopRange(startTimeSeconds: TimeInterval, endTimeSeconds: TimeInterval) async throws {
        guard playerNode != nil, let liveRenderSession else {
            throw PlaybackError.playerUnavailable
        }

        let startTime = bounded(startTimeSeconds)
        let endTime = bounded(endTimeSeconds)
        guard endTime - startTime > 1 / max(sampleRate, 1) else {
            throw PlaybackError.invalidLoopRange
        }

        let requestedRange = PlaybackLoopTimeline(
            startTimeSeconds: startTime,
            endTimeSeconds: endTime
        )
        let loopAudioData = try await liveRenderSession.playbackAudioChunk(
            startTimeSeconds: startTime,
            durationSeconds: requestedRange.durationSeconds,
            metronomeEnabled: true
        )

        loopRange = requestedRange
        self.loopAudioData = loopAudioData
        resetPlaybackQueue(to: startTime, wasPlaying: false)
        try scheduleLoopBuffer()
        log("loop configured start=\(formatSeconds(startTime)) end=\(formatSeconds(endTime)) revision=\(revision)")
    }

    /// Leaves loop mode at the current musical position. If playback is
    /// running, rebuild the ordinary forward queue once and continue.
    func clearLoopRange() {
        guard loopRange != nil else {
            return
        }

        let resumePosition = currentPositionSeconds()
        let wasPlaying = playerNode?.isPlaying == true || playWhenBuffered
        loopRange = nil
        loopAudioData = nil
        loopBufferIsScheduled = false
        loopPartMeterLevels = [:]
        loopRemixTask?.cancel()
        loopRemixTask = nil

        guard playerNode != nil else {
            return
        }

        resetPlaybackQueue(to: resumePosition, wasPlaying: wasPlaying)
        if wasPlaying {
            do {
                try play()
            } catch {
                streamingErrorMessage = error.localizedDescription
            }
        }
        log("loop cleared position=\(formatSeconds(resumePosition)) revision=\(revision)")
    }

    func invalidate() {
        removeMeterTaps()
        stemPlayers.values.forEach { $0.stop() }
        engine?.stop()
        cancelSchedulingTask()
        streamingErrorMessage = nil
        engine = nil
        playerNode = nil
        stemPlayers.removeAll()
        liveRenderSession = nil
        revision += 1
        sampleRate = 48_000
        usesSoftwareStemPlayback = false
        renderedStemIDs.removeAll()
        durationSeconds = 0
        queuedUntilSeconds = 0
        pendingStartSeconds = 0
        timelineClock.reset(to: 0)
        bufferProgress.reset(to: 0)
        isPaused = false
        isScheduling = false
        nextScheduledSampleTime = 0
        needsPlayerPriming = true
        playWhenBuffered = false
        loopRange = nil
        loopAudioData = nil
        loopBufferIsScheduled = false
        loopPartMeterLevels = [:]
        loopRemixTask?.cancel()
        loopRemixTask = nil
        metronomeEnabled = false
        log("invalidate revision=\(revision)")
    }

    private func installMeterTapsIfPossible() {
        guard isMeteringEnabled, !meterTapsInstalled, let engine else { return }

        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1_024, format: nil) { [weak self] buffer, _ in
            let level = Self.normalizedMeterLevel(in: buffer)
            guard level > 0 else { return }
            Task { @MainActor [weak self] in
                self?.recordMeterPeak(level, for: Self.masterMeterID)
            }
        }
        meterTapsInstalled = true
    }

    private func removeMeterTaps() {
        guard meterTapsInstalled else { return }
        engine?.mainMixerNode.removeTap(onBus: 0)
        meterTapsInstalled = false
    }

    private func recordMeterPeak(_ level: Float, for id: String) {
        meterPeaks[id] = max(meterPeaks[id] ?? 0, level)
    }

    private func startMeterUpdates() {
        guard meterUpdateTask == nil else { return }
        meterUpdateTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.isMeteringEnabled else { return }
                if self.playerNode?.isPlaying == true {
                    for (partID, level) in self.loopPartMeterLevels {
                        self.recordMeterPeak(level, for: partID)
                    }
                }
                let ids = Set(self.displayedMeterLevels.keys).union(self.meterPeaks.keys)
                var nextLevels: [String: Float] = [:]
                for id in ids {
                    let peak = self.meterPeaks[id] ?? 0
                    let previous = self.displayedMeterLevels[id] ?? 0
                    // Fast attack and a gentler release absorb fluctuations
                    // between tap buffers without hiding note onsets.
                    let response: Float = peak >= previous ? 0.65 : 0.12
                    let level = previous + (peak - previous) * response
                    if level >= 0.01 {
                        nextLevels[id] = level
                    }
                }
                self.meterPeaks.removeAll(keepingCapacity: true)
                self.displayedMeterLevels = nextLevels
                self.meterLevelHandler?(nextLevels)
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    nonisolated private static func normalizedMeterLevel(in buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        var peak: Float = 0
        for channel in 0..<channelCount {
            let samples = channels[channel]
            for frame in 0..<frameCount {
                peak = max(peak, abs(samples[frame]))
            }
        }
        guard peak > 0.000_01 else { return 0 }
        let decibels = 20 * log10(peak)
        return min(max((decibels + 60) / 60, 0), 1)
    }

    func visualLatencyCompensationSeconds() -> TimeInterval {
        guard playerNode?.isPlaying == true else {
            return 0
        }

        let audioSession = AVAudioSession.sharedInstance()
        let sessionLatency = audioSession.outputLatency + audioSession.ioBufferDuration
        let outputLatency = engine?.outputNode.presentationLatency ?? 0
        return min(max(max(sessionLatency, outputLatency), 0), 0.12)
    }

    func setMetronomeEnabled(_ enabled: Bool) {
        metronomeEnabled = enabled
        applyMixerSettings()
        refreshScheduledLoopBuffer()
    }

    private func fillPlaybackQueue(revision: Int) {
        guard loopRange == nil, !isScheduling else {
            return
        }

        isScheduling = true
        schedulingTask = Task { @MainActor [weak self] in
            defer {
                if let self, revision == self.revision {
                    self.isScheduling = false
                    self.schedulingTask = nil
                }
            }

            guard let self, let liveRenderSession = self.liveRenderSession else {
                return
            }

            let prebufferDuration = self.targetPrebufferDuration
            while revision == self.revision,
                  self.queuedUntilSeconds < self.bufferProgress.consumedUntilSeconds + prebufferDuration {
                let startTime = self.queuedUntilSeconds
                if self.durationSeconds > 0, startTime >= self.durationSeconds {
                    break
                }

                do {
                    try Task.checkCancellation()
                    let audioData = try await liveRenderSession.playbackAudioChunk(
                        startTimeSeconds: startTime,
                        durationSeconds: self.chunkDurationSeconds,
                        metronomeEnabled: true
                    )
                    try Task.checkCancellation()
                    try self.schedule(
                        audioData: audioData,
                        startsAt: startTime,
                        revision: revision
                    )
                } catch is CancellationError {
                    if revision == self.revision {
                        self.playWhenBuffered = false
                        self.log("queue fill canceled revision=\(revision)")
                    } else {
                        self.log("queue fill canceled stale revision=\(revision) current=\(self.revision)")
                    }
                    return
                } catch {
                    if revision == self.revision {
                        self.playWhenBuffered = false
                        let position = self.currentPositionSeconds()
                        self.stemPlayers.values.forEach { $0.stop() }
                        self.revision += 1
                        self.pendingStartSeconds = position
                        self.queuedUntilSeconds = position
                        self.timelineClock.reset(to: position)
                        self.bufferProgress.reset(to: position)
                        self.isPaused = true
                        self.isScheduling = false
                        self.schedulingTask = nil
                        self.streamingErrorMessage = error.localizedDescription
                        print("MuseReader live playback render failed: \(error.localizedDescription)")
                    } else {
                        self.log("queue fill failed stale revision=\(revision) current=\(self.revision): \(error.localizedDescription)")
                    }
                    return
                }
            }

            // Do not start from inside schedule(_:). Let this fill pass finish first so
            // the output player has its complete startup cushion before it begins.
            if self.playWhenBuffered, self.hasEnoughAudioToStart, let playerNode = self.playerNode {
                do {
                    try self.startPlaybackWhenBuffered(engine: self.engine, playerNode: playerNode)
                } catch {
                    self.playWhenBuffered = false
                    self.isPaused = true
                    self.streamingErrorMessage = error.localizedDescription
                    self.log("playback start failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func cancelSchedulingTask() {
        schedulingTask?.cancel()
        schedulingTask = nil
        isScheduling = false
    }

    private func resetPlaybackQueue(to positionSeconds: TimeInterval, wasPlaying: Bool) {
        stemPlayers.values.forEach { $0.stop() }
        cancelSchedulingTask()
        revision += 1
        pendingStartSeconds = positionSeconds
        timelineClock.reset(to: pendingStartSeconds)
        bufferProgress.reset(to: pendingStartSeconds)
        queuedUntilSeconds = pendingStartSeconds
        nextScheduledSampleTime = 0
        needsPlayerPriming = true
        loopBufferIsScheduled = false
        loopRemixTask?.cancel()
        loopRemixTask = nil
        playWhenBuffered = false
        isPaused = !wasPlaying
        fillPlaybackQueue(revision: revision)
    }

    private struct PreparedPlaybackSamples {
        let streamID: String
        let samples: Data
        let partMeterLevels: [String: Float]
    }

    private func preparedPlaybackSamples(from audioData: MSRPlaybackAudioData) throws -> PreparedPlaybackSamples {
        let prepared: PreparedPlaybackSamples
        if usesSoftwareStemPlayback {
            guard !audioData.partSamples.isEmpty,
                  Set(audioData.partSamples.keys) == renderedStemIDs else {
                throw PlaybackError.sequenceLoadFailed(
                    "The instrument layout changed. Stop and restart playback."
                )
            }
            do {
                let mix = try StemSoftwareMixer.mix(
                    partSamples: audioData.partSamples,
                    settings: mixerSettings,
                    metronomeEnabled: metronomeEnabled
                )
                prepared = PreparedPlaybackSamples(
                    streamID: Self.softwareStemMixStreamID,
                    samples: mix.interleavedFloat32Samples,
                    partMeterLevels: mix.normalizedLevels
                )
            } catch {
                throw PlaybackError.sequenceLoadFailed("An instrument audio buffer was invalid.")
            }
        } else {
            prepared = PreparedPlaybackSamples(
                streamID: Self.mixedStreamID,
                samples: audioData.interleavedFloat32Samples,
                partMeterLevels: [:]
            )
        }

        guard Set(stemPlayers.keys) == Set([prepared.streamID]),
              prepared.samples.count == audioData.interleavedFloat32Samples.count else {
            throw PlaybackError.sequenceLoadFailed("The instrument layout changed. Stop and restart playback.")
        }
        return prepared
    }

    /// A loop reuses one complete rendered pass instead of asking the synth to
    /// reconstruct note state at every wrap. This keeps sustained notes exactly
    /// as they sounded on the first pass and leaves the audio thread gapless.
    private func scheduleLoopBuffer(
        options: AVAudioPlayerNodeBufferOptions = .loops
    ) throws {
        guard let loopRange, let loopAudioData, let playerNode else {
            throw PlaybackError.playerUnavailable
        }

        let prepared = try preparedPlaybackSamples(from: loopAudioData)
        let exactFrameCount = loopRange.frameCount(sampleRate: Double(loopAudioData.sampleRate))
        let availableFrameCount = prepared.samples.count / MemoryLayout<Float>.size / 2
        guard availableFrameCount >= exactFrameCount,
              let buffer = makeBuffer(
                samples: prepared.samples,
                sampleRate: loopAudioData.sampleRate,
                maximumFrameCount: exactFrameCount
              ) else {
            throw PlaybackError.sequenceLoadFailed("The selected loop audio was incomplete.")
        }

        let wasAlreadyScheduled = loopBufferIsScheduled
        playerNode.scheduleBuffer(buffer, at: nil, options: options)
        loopBufferIsScheduled = true
        loopPartMeterLevels = prepared.partMeterLevels
        if !wasAlreadyScheduled {
            nextScheduledSampleTime = AVAudioFramePosition(buffer.frameLength)
            queuedUntilSeconds = loopRange.startTimeSeconds
                + Double(buffer.frameLength) / buffer.format.sampleRate
        }
    }

    /// Software stem mixing can rebuild the cached pass immediately. When a
    /// pass is already sounding, AVAudioPlayerNode swaps it at the loop edge.
    private func refreshScheduledLoopBuffer() {
        loopRemixTask?.cancel()
        guard loopRange != nil, loopAudioData != nil else {
            loopRemixTask = nil
            return
        }

        // Fader drags can publish dozens of values per second. Coalesce them so
        // only the final mix is queued for the next loop boundary.
        loopRemixTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled, let self else { return }
            self.loopRemixTask = nil
            do {
                let options: AVAudioPlayerNodeBufferOptions = self.loopBufferIsScheduled
                    ? [.loops, .interruptsAtLoop]
                    : .loops
                try self.scheduleLoopBuffer(options: options)
            } catch {
                self.streamingErrorMessage = error.localizedDescription
            }
        }
    }

    private func schedule(audioData: MSRPlaybackAudioData, startsAt startTime: TimeInterval, revision: Int) throws {
        guard revision == self.revision, let playerNode else {
            log("schedule skipped stale revision=\(revision) current=\(self.revision)")
            return
        }

        let prepared = try preparedPlaybackSamples(from: audioData)
        guard let buffer = makeBuffer(samples: prepared.samples, sampleRate: audioData.sampleRate) else {
            throw PlaybackError.sequenceLoadFailed("An instrument audio buffer was invalid.")
        }
        let bufferDuration = Double(buffer.frameLength) / buffer.format.sampleRate
        playerNode.scheduleBuffer(
            buffer,
            at: nil,
            options: [],
            completionCallbackType: .dataRendered
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, revision == self.revision else { return }
                if self.isMeteringEnabled {
                    for (partID, level) in prepared.partMeterLevels {
                        self.recordMeterPeak(level, for: partID)
                    }
                }
                self.bufferProgress.recordConsumedBuffer(
                    startTimeSeconds: startTime, durationSeconds: bufferDuration,
                    playbackDurationSeconds: self.durationSeconds)
                self.fillPlaybackQueue(revision: revision)
            }
        }

        nextScheduledSampleTime += AVAudioFramePosition(buffer.frameLength)
        queuedUntilSeconds = max(queuedUntilSeconds, startTime + bufferDuration)
    }

    private func makeBuffer(
        samples: Data,
        sampleRate: Int,
        maximumFrameCount: Int? = nil
    ) -> AVAudioPCMBuffer? {
        let availableFrameCount = samples.count / MemoryLayout<Float>.size / 2
        let frameCount = min(availableFrameCount, maximumFrameCount ?? availableFrameCount)
        guard frameCount > 0 else {
            return nil
        }

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRate),
            channels: 2,
            interleaved: false
        ),
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))
        else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        samples.withUnsafeBytes { rawBuffer in
            guard let source = rawBuffer.bindMemory(to: Float.self).baseAddress else {
                return
            }

            let left = buffer.floatChannelData?[0]
            let right = buffer.floatChannelData?[1]
            for frame in 0..<frameCount {
                left?[frame] = source[frame * 2]
                right?[frame] = source[frame * 2 + 1]
            }
        }

        return buffer
    }

    private func currentPositionSeconds() -> TimeInterval {
        if let playerNode,
           playerNode.isPlaying,
           let nodeTime = playerNode.lastRenderTime,
           let playerTime = playerNode.playerTime(forNodeTime: nodeTime) {
            let timelinePosition = timelineClock.positionSeconds(
                playerSampleTimeSeconds: Double(playerTime.sampleTime) / playerTime.sampleRate
            )
            return scorePosition(for: timelinePosition)
        }

        if playerNode?.isPlaying == true {
            return scorePosition(for: timelineClock.positionSeconds(playerSampleTimeSeconds: nil))
        }

        let timelinePosition = bufferProgress.positionWhenNotRendering(
            capturedPositionSeconds: pendingStartSeconds,
            playbackDurationSeconds: durationSeconds,
            isPausedOrWaiting: isPaused || playWhenBuffered
        )
        return scorePosition(for: timelinePosition)
    }

    private func scorePosition(for timelinePosition: TimeInterval) -> TimeInterval {
        if let loopRange {
            return loopRange.wrappedPosition(for: timelinePosition)
        }
        return bounded(timelinePosition)
    }

    private func stopInternally() {
        stemPlayers.values.forEach { $0.stop() }
        cancelSchedulingTask()
        revision += 1
        let restartPosition = loopRange?.startTimeSeconds ?? 0
        queuedUntilSeconds = restartPosition
        pendingStartSeconds = restartPosition
        timelineClock.reset(to: restartPosition)
        bufferProgress.reset(to: restartPosition)
        isPaused = false
        isScheduling = false
        nextScheduledSampleTime = 0
        needsPlayerPriming = true
        loopBufferIsScheduled = false
        loopRemixTask?.cancel()
        loopRemixTask = nil
        playWhenBuffered = false
        log("stop revision=\(revision)")
    }

    private func startPlaybackWhenBuffered(engine: AVAudioEngine? = nil, playerNode: AVAudioPlayerNode) throws {
        if let engine, !engine.isRunning {
            try engine.start()
        }

        guard !playerNode.isPlaying else {
            playWhenBuffered = false
            return
        }

        // pause() preserves the player's queue and sample position. Resuming that
        // queue must not wait for the larger cushion required by a fresh start/seek.
        let isResumingPausedQueue = isPaused && !needsPlayerPriming
        guard isResumingPausedQueue || hasEnoughAudioToStart else {
            playWhenBuffered = true
            isPaused = false
            timelineClock.pauseFallback(at: pendingStartSeconds)
            log("play armed waiting for buffer position=\(formatSeconds(pendingStartSeconds)) revision=\(revision)")
            return
        }

        timelineClock.startFallback(at: pendingStartSeconds)
        playWhenBuffered = false
        var primedFrameCount: AVAudioFrameCount = 0
        if needsPlayerPriming {
            primedFrameCount = AVAudioFrameCount(min(nextScheduledSampleTime, 4_096))
            for player in stemPlayers.values {
                player.prepare(withFrameCount: primedFrameCount)
            }
            needsPlayerPriming = false
        }
        let start = AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.03))
        let startedIDs = stemPlayers.keys.sorted()
        for player in stemPlayers.values { player.play(at: start) }
        isPaused = false
        let audioSession = AVAudioSession.sharedInstance()
        let outputFormat = engine?.outputNode.outputFormat(forBus: 0)
        let ioBufferMilliseconds = String(format: "%.2f", audioSession.ioBufferDuration * 1_000)
        let outputLatencyMilliseconds = String(format: "%.2f", audioSession.outputLatency * 1_000)
        let meterState = isMeteringEnabled ? "on" : "off"
        let startKind = isResumingPausedQueue ? "resume" : "fresh"
        log("startup start kind=\(startKind) revision=\(revision) score=\(formatSeconds(pendingStartSeconds)) "
            + "queued=\(formatSeconds(queuedUntilSeconds - pendingStartSeconds))s streams=\(startedIDs.count) "
            + "scheduledFrames=\(nextScheduledSampleTime) engineRate=\(Int(outputFormat?.sampleRate ?? 0)) "
            + "ioBuffer=\(ioBufferMilliseconds)ms outputLatency=\(outputLatencyMilliseconds)ms "
            + "meters=\(meterState) primedFrames=\(primedFrameCount)")
    }

    private var hasEnoughAudioToStart: Bool {
        if loopRange != nil {
            return loopBufferIsScheduled
        }

        let requiredDuration: TimeInterval
        let remainingDuration = durationSeconds > 0
            ? max(durationSeconds - pendingStartSeconds, 0)
            : targetPrebufferDuration
        requiredDuration = min(targetPrebufferDuration, remainingDuration)
        return queuedUntilSeconds - pendingStartSeconds + 0.000_001 >= requiredDuration
    }

    /// Keep scheduled PCM under 32 MiB while retaining several chunks of headroom.
    /// Fresh starts and seeks wait for this complete cushion before starting the player.
    private var targetPrebufferDuration: TimeInterval {
        let bytesPerSecond = sampleRate * 2 * 4 * Double(max(stemPlayers.count, 1))
        return max(
            chunkDurationSeconds,
            min(chunkDurationSeconds * Double(prebufferChunks), 32 * 1_024 * 1_024 / bytesPerSecond)
        )
    }

    private func bounded(_ positionSeconds: TimeInterval) -> TimeInterval {
        if durationSeconds > 0 {
            return min(max(positionSeconds, 0), durationSeconds)
        }
        return max(positionSeconds, 0)
    }

    private func log(_ message: String) {
        print("MuseReader native playback: \(message)")
    }

    private func formatSeconds(_ value: TimeInterval) -> String {
        String(format: "%.2f", value)
    }
}
