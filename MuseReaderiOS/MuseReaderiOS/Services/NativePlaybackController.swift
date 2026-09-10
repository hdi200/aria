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
            }
        }
    }

    private var chunkDurationSeconds: TimeInterval {
        let bytesPerSecond = sampleRate * 8 * Double(max(stemPlayers.count, 1))
        return min(0.5, max(0.05, 4 * 1_024 * 1_024 / bytesPerSecond))
    }
    private let prebufferChunks = 4
    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    /// A/B switch between the per-part stem path added with the mixer and the single mixed
    /// buffer the app played before it. The mixed buffer is exactly what the shipping build
    /// plays, so turning this off reproduces production audio. Per-part volume, pan, mute
    /// and solo have nothing to act on while it is off.
    static let stemPlaybackDefaultsKey = "AriaUsesStemPlayback"

    static var usesStemPlayback: Bool {
        get { UserDefaults.standard.object(forKey: stemPlaybackDefaultsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: stemPlaybackDefaultsKey) }
    }

    /// Stream id used when playing the single mixed buffer instead of per-part stems.
    private static let mixedStreamID = "mixed"

    private var stemPlayers: [String: AVAudioPlayerNode] = [:]
    /// All player nodes use this shared sample timeline. Scheduling with an explicit
    /// sample time keeps stems aligned even if their buffers are submitted on different
    /// turns of the audio render loop.
    private var nextScheduledSampleTime: AVAudioFramePosition = 0
    private struct StereoSample {
        let left: Float
        let right: Float
    }
    private var previousScheduledTailByStream: [String: StereoSample] = [:]
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
        let passthroughIDs: Set<String> = ["metronome", "silence", Self.mixedStreamID]
        let activeParts = Set(stemPlayers.keys.filter { !passthroughIDs.contains($0) })
        for (partID, player) in stemPlayers {
            if partID == Self.mixedStreamID {
                // Already contains every part, including the metronome, at its rendered level.
                player.volume = 1
                player.pan = 0
            } else if partID == "metronome" {
                player.volume = metronomeEnabled ? 1 : 0
                player.pan = 0
            } else {
                player.volume = mixerSettings.gain(for: partID, activePartIDs: activeParts)
                player.pan = min(max(mixerSettings.settings(for: partID).pan, -1), 1)
            }
        }

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
    private var scheduledBufferCount = 0
    private var playWhenBuffered = false

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
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .default, options: [])
            try audioSession.setActive(true)
        } catch {
            throw PlaybackError.audioSessionUnavailable(error.localizedDescription)
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
        let useStems = Self.usesStemPlayback && !audioData.partSamples.isEmpty
        let streamIDs = useStems ? audioData.partSamples.keys.sorted() : [Self.mixedStreamID]
        log("playback path=\(useStems ? "per-part stems" : "single mixed buffer (production path)") streams=\(streamIDs.count)")
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
        applyMixerSettings()
        installMeterTapsIfPossible()
        self.liveRenderSession = liveRenderSession
        self.sampleRate = Double(audioData.sampleRate)
        self.durationSeconds = max(durationSeconds, audioData.durationSeconds)
        self.queuedUntilSeconds = pendingStartSeconds
        self.timelineClock.reset(to: pendingStartSeconds)
        self.bufferProgress.reset(to: pendingStartSeconds)
        self.isPaused = false
        self.scheduledBufferCount = 0
        self.nextScheduledSampleTime = 0
        self.previousScheduledTailByStream.removeAll(keepingCapacity: true)
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

        if durationSeconds > 0, positionSeconds >= durationSeconds {
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

        let targetPosition = bounded(positionSeconds)
        let wasPlaying = playerNode?.isPlaying == true || playWhenBuffered
        let samePositionTolerance = 1 / max(sampleRate, 1)
        if !wasPlaying, abs(targetPosition - pendingStartSeconds) <= samePositionTolerance {
            log("seek reused prepared position=\(formatSeconds(targetPosition)) "
                + "queued=\(formatSeconds(max(queuedUntilSeconds - targetPosition, 0)))s revision=\(revision)")
            return
        }

        stemPlayers.values.forEach { $0.stop() }
        cancelSchedulingTask()
        revision += 1
        pendingStartSeconds = targetPosition
        timelineClock.reset(to: pendingStartSeconds)
        bufferProgress.reset(to: pendingStartSeconds)
        queuedUntilSeconds = pendingStartSeconds
        nextScheduledSampleTime = 0
        scheduledBufferCount = 0
        previousScheduledTailByStream.removeAll(keepingCapacity: true)
        needsPlayerPriming = true
        playWhenBuffered = false
        isPaused = !wasPlaying
        fillPlaybackQueue(revision: revision)
        log("seek position=\(formatSeconds(pendingStartSeconds)) wasPlaying=\(wasPlaying) revision=\(revision)")

        if wasPlaying {
            try play()
        }
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
        durationSeconds = 0
        queuedUntilSeconds = 0
        pendingStartSeconds = 0
        timelineClock.reset(to: 0)
        bufferProgress.reset(to: 0)
        isPaused = false
        isScheduling = false
        scheduledBufferCount = 0
        nextScheduledSampleTime = 0
        previousScheduledTailByStream.removeAll()
        needsPlayerPriming = true
        playWhenBuffered = false
        metronomeEnabled = false
        log("invalidate revision=\(revision)")
    }

    private func installMeterTapsIfPossible() {
        guard isMeteringEnabled, !meterTapsInstalled, let engine else { return }

        for (partID, player) in stemPlayers {
            player.installTap(onBus: 0, bufferSize: 1_024, format: nil) { [weak self] buffer, _ in
                let level = Self.normalizedMeterLevel(in: buffer)
                guard level > 0 else { return }
                Task { @MainActor [weak self] in
                    self?.recordMeterPeak(level, for: partID)
                }
            }
        }

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
        stemPlayers.values.forEach { $0.removeTap(onBus: 0) }
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
    }

    private func fillPlaybackQueue(revision: Int) {
        guard !isScheduling else {
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
                    try self.schedule(audioData: audioData, startsAt: startTime, revision: revision)
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
            // every stem has the complete startup cushion before any player begins.
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

    private func schedule(audioData: MSRPlaybackAudioData, startsAt startTime: TimeInterval, revision: Int) throws {
        guard revision == self.revision, let playerNode else {
            log("schedule skipped stale revision=\(revision) current=\(self.revision)")
            return
        }

        let streams = (Self.usesStemPlayback && !audioData.partSamples.isEmpty)
            ? audioData.partSamples
            : [Self.mixedStreamID: audioData.interleavedFloat32Samples]
        guard Set(streams.keys) == Set(stemPlayers.keys) else {
            throw PlaybackError.sequenceLoadFailed("The instrument layout changed. Stop and restart playback.")
        }
        // Convert and validate every stem before scheduling any, so errors cannot desynchronize parts.
        var buffers: [(String, AVAudioPCMBuffer)] = []
        for id in streams.keys.sorted() {
            guard let data = streams[id], data.count == audioData.interleavedFloat32Samples.count,
                  let buffer = makeBuffer(samples: data, sampleRate: audioData.sampleRate) else {
                throw PlaybackError.sequenceLoadFailed("An instrument audio buffer was invalid.")
            }
            buffers.append((id, buffer))
        }
        guard let first = buffers.first else { return }
        let bufferDuration = Double(first.1.frameLength) / first.1.format.sampleRate
        scheduledBufferCount += 1
        let bufferIndex = scheduledBufferCount
        let uniqueFrameLengths = Set(buffers.map(\.1.frameLength))
        guard uniqueFrameLengths.count == 1 else {
            throw PlaybackError.sequenceLoadFailed("Instrument audio buffers had different frame counts.")
        }
        let scheduledStartSample = nextScheduledSampleTime
        // A single mixed player can use AVAudioPlayerNode's natural append behavior.
        // Explicit sample times are only needed to keep multiple stem nodes locked.
        let scheduledTime: AVAudioTime? = buffers.count > 1
            ? AVAudioTime(sampleTime: scheduledStartSample, atRate: first.1.format.sampleRate)
            : nil
        logStartupPCM(
            buffers: buffers,
            bufferIndex: bufferIndex,
            scoreStartTime: startTime,
            scheduledSampleTime: scheduledStartSample
        )
        for (id, buffer) in buffers {
            guard let player = stemPlayers[id] else { continue }
            if player === playerNode {
                player.scheduleBuffer(
                    buffer,
                    at: scheduledTime,
                    options: [],
                    completionCallbackType: .dataRendered
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self, revision == self.revision else { return }
                        self.bufferProgress.recordConsumedBuffer(
                            startTimeSeconds: startTime, durationSeconds: bufferDuration,
                            playbackDurationSeconds: self.durationSeconds)
                        self.logRenderedStartupBuffer(
                            bufferIndex: bufferIndex,
                            scoreEndTime: startTime + bufferDuration,
                            scheduledEndSample: scheduledStartSample + AVAudioFramePosition(buffer.frameLength),
                            player: player
                        )
                        self.fillPlaybackQueue(revision: revision)
                    }
                }
            } else {
                player.scheduleBuffer(buffer, at: scheduledTime, options: [])
            }
        }

        nextScheduledSampleTime += AVAudioFramePosition(first.1.frameLength)
        queuedUntilSeconds = max(queuedUntilSeconds, startTime + bufferDuration)
    }

    private func makeBuffer(samples: Data, sampleRate: Int) -> AVAudioPCMBuffer? {
        let frameCount = samples.count / MemoryLayout<Float>.size / 2
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
            return bounded(timelineClock.positionSeconds(
                playerSampleTimeSeconds: Double(playerTime.sampleTime) / playerTime.sampleRate
            ))
        }

        if playerNode?.isPlaying == true {
            return bounded(timelineClock.positionSeconds(playerSampleTimeSeconds: nil))
        }

        return bounded(bufferProgress.positionWhenNotRendering(
            capturedPositionSeconds: pendingStartSeconds,
            playbackDurationSeconds: durationSeconds,
            isPausedOrWaiting: isPaused || playWhenBuffered
        ))
    }

    private func stopInternally() {
        stemPlayers.values.forEach { $0.stop() }
        cancelSchedulingTask()
        revision += 1
        queuedUntilSeconds = 0
        pendingStartSeconds = 0
        timelineClock.reset(to: 0)
        bufferProgress.reset(to: 0)
        isPaused = false
        isScheduling = false
        scheduledBufferCount = 0
        nextScheduledSampleTime = 0
        previousScheduledTailByStream.removeAll(keepingCapacity: true)
        needsPlayerPriming = true
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

        // pause() preserves every player's queue and sample position. Resuming that
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
        logStartupAlignmentSnapshots(revision: revision)
    }

    private var hasEnoughAudioToStart: Bool {
        let remainingDuration = durationSeconds > 0
            ? max(durationSeconds - pendingStartSeconds, 0)
            : targetPrebufferDuration
        let requiredDuration = min(targetPrebufferDuration, remainingDuration)
        return queuedUntilSeconds - pendingStartSeconds + 0.000_001 >= requiredDuration
    }

    /// Keep scheduled PCM under 32 MiB while retaining several chunks of headroom.
    /// Fresh starts and seeks wait for this complete cushion before starting the nodes.
    private var targetPrebufferDuration: TimeInterval {
        let bytesPerSecond = sampleRate * 2 * 4 * Double(max(stemPlayers.count, 1))
        return max(
            chunkDurationSeconds,
            min(chunkDurationSeconds * Double(prebufferChunks), 32 * 1_024 * 1_024 / bytesPerSecond)
        )
    }

    /// A bounded trace for the first few buffers after load or seek. It detects PCM
    /// discontinuities and clipping without logging from the real-time audio callback.
    private func logStartupPCM(
        buffers: [(String, AVAudioPCMBuffer)],
        bufferIndex: Int,
        scoreStartTime: TimeInterval,
        scheduledSampleTime: AVAudioFramePosition
    ) {
        guard bufferIndex <= 6 else { return }

        var largestPeak: Float = 0
        var peakStream = "none"
        var largestBoundaryJump: Float = 0
        var boundaryStream = "none"
        var largestInitialSample: Float = 0

        for (id, buffer) in buffers {
            guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { continue }
            let frameCount = Int(buffer.frameLength)
            let first = StereoSample(left: channels[0][0], right: channels[1][0])
            let last = StereoSample(left: channels[0][frameCount - 1], right: channels[1][frameCount - 1])
            largestInitialSample = max(largestInitialSample, max(abs(first.left), abs(first.right)))

            if let previous = previousScheduledTailByStream[id] {
                let jump = max(abs(first.left - previous.left), abs(first.right - previous.right))
                if jump > largestBoundaryJump {
                    largestBoundaryJump = jump
                    boundaryStream = id
                }
            }
            previousScheduledTailByStream[id] = last

            var peak: Float = 0
            for frame in 0..<frameCount {
                peak = max(peak, max(abs(channels[0][frame]), abs(channels[1][frame])))
            }
            if peak > largestPeak {
                largestPeak = peak
                peakStream = id
            }
        }

        let peakDescription = String(format: "%.4f", largestPeak)
        let initialDescription = String(format: "%.4f", largestInitialSample)
        let boundaryDescription = String(format: "%.4f", largestBoundaryJump)
        log("startup pcm chunk=\(bufferIndex) score=\(formatSeconds(scoreStartTime)) "
            + "sample=\(scheduledSampleTime) frames=\(buffers.first?.1.frameLength ?? 0) "
            + "peak=\(peakDescription)[\(peakStream)] initial=\(initialDescription) "
            + "boundaryJump=\(boundaryDescription)[\(boundaryStream)]")
    }

    private func logRenderedStartupBuffer(
        bufferIndex: Int,
        scoreEndTime: TimeInterval,
        scheduledEndSample: AVAudioFramePosition,
        player: AVAudioPlayerNode
    ) {
        guard bufferIndex <= 6 else { return }
        let renderedSample: AVAudioFramePosition? = player.lastRenderTime
            .flatMap { player.playerTime(forNodeTime: $0)?.sampleTime }
        let renderedDescription = renderedSample.map { String($0) } ?? "unavailable"
        log("startup rendered chunk=\(bufferIndex) scoreEnd=\(formatSeconds(scoreEndTime)) "
            + "scheduledEnd=\(scheduledEndSample) playerSample=\(renderedDescription) "
            + "queuedAhead=\(formatSeconds(max(queuedUntilSeconds - scoreEndTime, 0)))s")
    }

    private func logStartupAlignmentSnapshots(revision startRevision: Int) {
        Task { @MainActor [weak self] in
            let checkpoints: [(Duration, String)] = [
                (.milliseconds(40), "40ms"),
                (.milliseconds(160), "200ms"),
                (.milliseconds(600), "800ms")
            ]
            for (delay, label) in checkpoints {
                try? await Task.sleep(for: delay)
                guard let self, startRevision == self.revision else { return }

                var samples: [(String, AVAudioFramePosition)] = []
                var unavailable: [String] = []
                for id in self.stemPlayers.keys.sorted() {
                    guard let player = self.stemPlayers[id],
                          let nodeTime = player.lastRenderTime,
                          let playerTime = player.playerTime(forNodeTime: nodeTime) else {
                        unavailable.append(id)
                        continue
                    }
                    samples.append((id, playerTime.sampleTime))
                }
                let values = samples.map(\.1)
                let spread = (values.max() ?? 0) - (values.min() ?? 0)
                let positions = samples.map { "\($0.0)=\($0.1)" }.joined(separator: ",")
                self.log("startup alignment \(label) spreadFrames=\(spread) "
                    + "positions=[\(positions)] unavailable=[\(unavailable.joined(separator: ","))]")
            }
        }
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
