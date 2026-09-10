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
    //! NOTE Diagnostic: buffers scheduled vs. actually consumed, per stem. Unlike
    //! playerTime.sampleTime (which just counts render time since play started, and so
    //! matches across stems even when one underruns) this tracks queue progress, which
    //! is what "the parts are offset" actually means.
    private var scheduledBuffersPerStem: [String: Int] = [:]
    private var consumedBuffersPerStem: [String: Int] = [:]
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

        //! NOTE Diagnostic: the last stage where the five stems are treated differently from
        //! each other, and the only one production has no equivalent of. At unity gain and
        //! centre pan the summed stems are mathematically identical to the mixed buffer, so
        //! anything non-default here is the only way this build can differ from production.
        let applied = stemPlayers.keys.sorted().map { id -> String in
            guard let player = stemPlayers[id] else { return "\(id)=?" }
            return String(format: "%@ vol=%.3f pan=%+.2f", id, player.volume, player.pan)
        }
        let allDefault = stemPlayers.values.allSatisfy { $0.volume == 1 && $0.pan == 0 }
        log("mixer applied  master vol=\(engine?.mainMixerNode.outputVolume ?? -1) "
            + "pan=\(engine?.mainMixerNode.pan ?? -1)  \(applied.joined(separator: "  "))"
            + (allDefault ? "  [all stems at unity/centre]" : "  [NON-DEFAULT]"))
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

        let wasPlaying = playerNode?.isPlaying == true || playWhenBuffered
        stemPlayers.values.forEach { $0.stop() }
        cancelSchedulingTask()
        revision += 1
        pendingStartSeconds = bounded(positionSeconds)
        timelineClock.reset(to: pendingStartSeconds)
        bufferProgress.reset(to: pendingStartSeconds)
        queuedUntilSeconds = pendingStartSeconds
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
            log("queue fill skipped: already scheduling revision=\(revision)")
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

            self.log("queue fill begin pending=\(self.formatSeconds(self.pendingStartSeconds)) queuedUntil=\(self.formatSeconds(self.queuedUntilSeconds)) duration=\(self.formatSeconds(self.durationSeconds)) revision=\(revision)")
            // Keep scheduled PCM under 32 MiB, with at least one chunk per stream.
            let bytesPerSecond = self.sampleRate * 2 * 4 * Double(max(self.stemPlayers.count, 1))
            let prebufferDuration = max(self.chunkDurationSeconds,
                min(self.chunkDurationSeconds * Double(self.prebufferChunks), 32 * 1_024 * 1_024 / bytesPerSecond))
            while revision == self.revision,
                  self.queuedUntilSeconds < self.bufferProgress.consumedUntilSeconds + prebufferDuration {
                let startTime = self.queuedUntilSeconds
                if self.durationSeconds > 0, startTime >= self.durationSeconds {
                    return
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
            self.log("queue fill end queuedUntil=\(self.formatSeconds(self.queuedUntilSeconds)) revision=\(revision)")
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
        //! NOTE Diagnostic: every stem must carry an identical frame count for the
        //! `at: nil` appends below to stay in lockstep. A mismatch here is a desync.
        let frameCounts = buffers.map { "\($0.0):\($0.1.frameLength)" }.joined(separator: " ")
        let uniqueFrameLengths = Set(buffers.map(\.1.frameLength))
        log("chunk #\(scheduledBufferCount) start=\(formatSeconds(startTime)) dur=\(formatSeconds(bufferDuration)) "
            + "frames=[\(frameCounts)]\(uniqueFrameLengths.count == 1 ? "" : "  ⚠️ FRAME COUNT MISMATCH")")
        for (id, buffer) in buffers {
            guard let player = stemPlayers[id] else { continue }
            scheduledBuffersPerStem[id, default: 0] += 1
            if player === playerNode {
                player.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self, revision == self.revision else { return }
                        self.consumedBuffersPerStem[id, default: 0] += 1
                        self.bufferProgress.recordConsumedBuffer(
                            startTimeSeconds: startTime, durationSeconds: bufferDuration,
                            playbackDurationSeconds: self.durationSeconds)
                        self.logStemAlignment("chunk boundary \(self.formatSeconds(startTime))")
                        self.fillPlaybackQueue(revision: revision)
                    }
                }
            } else {
                player.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self, revision == self.revision else { return }
                        self.consumedBuffersPerStem[id, default: 0] += 1
                    }
                }
            }
        }

        queuedUntilSeconds = max(queuedUntilSeconds, startTime + bufferDuration)
        if playWhenBuffered, queuedUntilSeconds > pendingStartSeconds + 0.001 {
            try startPlaybackWhenBuffered(playerNode: playerNode)
        }
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
        scheduledBuffersPerStem.removeAll()
        consumedBuffersPerStem.removeAll()
        playWhenBuffered = false
        log("stop revision=\(revision)")
    }

    private func startPlaybackWhenBuffered(engine: AVAudioEngine? = nil, playerNode: AVAudioPlayerNode) throws {
        if let engine, !engine.isRunning {
            try engine.start()
        }

        guard !playerNode.isPlaying else {
            //! NOTE Diagnostic: this early return only inspects the lead stem. If other
            //! stems are stopped here they never get started at all.
            let idle = stemPlayers.filter { !$0.value.isPlaying }.keys.sorted()
            if !idle.isEmpty {
                log("⚠️ lead stem already playing but these never started: \(idle.joined(separator: " "))")
            }
            playWhenBuffered = false
            return
        }

        guard queuedUntilSeconds > pendingStartSeconds + 0.001 else {
            playWhenBuffered = true
            isPaused = false
            timelineClock.pauseFallback(at: pendingStartSeconds)
            log("play armed waiting for buffer position=\(formatSeconds(pendingStartSeconds)) revision=\(revision)")
            return
        }

        timelineClock.startFallback(at: pendingStartSeconds)
        playWhenBuffered = false
        let start = AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.03))
        let startedIDs = stemPlayers.keys.sorted()
        for player in stemPlayers.values { player.play(at: start) }
        isPaused = false
        log("play started position=\(formatSeconds(pendingStartSeconds)) queuedUntil=\(formatSeconds(queuedUntilSeconds)) revision=\(revision)")
        //! NOTE Diagnostic: all stems are handed one shared host time here. If they still
        //! drift, the divergence is upstream of the start, not in this call.
        log("play issued to \(startedIDs.count) stems at one host time: \(startedIDs.joined(separator: " "))")
        logStemAlignmentAfterStart()
    }

    private func bounded(_ positionSeconds: TimeInterval) -> TimeInterval {
        if durationSeconds > 0 {
            return min(max(positionSeconds, 0), durationSeconds)
        }
        return max(positionSeconds, 0)
    }

    /// Diagnostic: prints every stem's current playback position alongside its drift
    /// from the lead stem. Parts that are audibly offset show up here as a non-zero
    /// delta; a stem reporting `idle` while others advance means it never started.
    private func logStemAlignment(_ label: String) {
        guard !stemPlayers.isEmpty else {
            return
        }

        var reference: (sampleTime: AVAudioFramePosition, sampleRate: Double)?
        var columns: [String] = []

        for id in stemPlayers.keys.sorted() {
            guard let player = stemPlayers[id] else { continue }
            guard player.isPlaying,
                  let nodeTime = player.lastRenderTime,
                  let playerTime = player.playerTime(forNodeTime: nodeTime) else {
                columns.append("\(id)=idle")
                continue
            }

            if reference == nil {
                reference = (playerTime.sampleTime, playerTime.sampleRate)
            }

            let deltaFrames = playerTime.sampleTime - (reference?.sampleTime ?? playerTime.sampleTime)
            let deltaMilliseconds = Double(deltaFrames) / playerTime.sampleRate * 1000
            columns.append(String(format: "%@=%lld(%+.2fms)", id, playerTime.sampleTime, deltaMilliseconds))
        }

        log("stem alignment [\(label)] \(columns.joined(separator: "  "))")

        // Queue progress: sched/consumed. Any stem whose consumed count trails the others
        // is playing older audio than they are — that is an audible offset.
        let queueColumns = stemPlayers.keys.sorted().map { id in
            "\(id)=\(scheduledBuffersPerStem[id] ?? 0)/\(consumedBuffersPerStem[id] ?? 0)"
        }
        let consumedCounts = Set(stemPlayers.keys.map { consumedBuffersPerStem[$0] ?? 0 })
        log("stem queue    [\(label)] sched/consumed \(queueColumns.joined(separator: "  "))"
            + (consumedCounts.count == 1 ? "" : "  ⚠️ STEMS OUT OF STEP"))
    }

    /// Diagnostic: samples alignment on its own timer rather than from inside a stem's
    /// completion callback. A callback-driven sample always reads the callback's own stem
    /// as one buffer ahead of stems whose callbacks have not run yet, which shows up as a
    /// fixed ±1 that is an artifact, not drift. These samples are taken with no callback
    /// in flight, so a difference here is real.
    private func logStemAlignmentAfterStart() {
        let startRevision = revision
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, startRevision == self.revision else { return }
            self.logStemAlignment("250ms after start")

            var sample = 1
            while startRevision == self.revision, self.playerNode?.isPlaying == true, sample <= 20 {
                try? await Task.sleep(for: .milliseconds(750))
                guard startRevision == self.revision else { return }
                self.logStemAlignment("neutral sample \(sample)")
                sample += 1
            }
        }
    }

    private func log(_ message: String) {
        print("MuseReader native playback: \(message)")
    }

    private func formatSeconds(_ value: TimeInterval) -> String {
        String(format: "%.2f", value)
    }
}
