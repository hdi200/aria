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
    private var stemPlayers: [String: AVAudioPlayerNode] = [:]
    private var mixerSettings = ScoreMixerSettings()
    private(set) var streamingErrorMessage: String?

    func setMixerSettings(_ settings: ScoreMixerSettings) {
        mixerSettings = settings
        applyMixerSettings()
    }

    private func applyMixerSettings() {
        engine?.mainMixerNode.outputVolume = min(max(mixerSettings.masterVolume, 0), 1)
        let activeParts = Set(stemPlayers.keys.filter { $0 != "metronome" && $0 != "silence" })
        for (partID, player) in stemPlayers {
            if partID == "metronome" {
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
        let streamIDs = audioData.partSamples.isEmpty ? ["silence"] : audioData.partSamples.keys.sorted()
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

        let streams = audioData.partSamples.isEmpty
            ? ["silence": audioData.interleavedFloat32Samples] : audioData.partSamples
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
        for (id, buffer) in buffers {
            guard let player = stemPlayers[id] else { continue }
            if player === playerNode {
                player.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self, revision == self.revision else { return }
                        self.bufferProgress.recordConsumedBuffer(
                            startTimeSeconds: startTime, durationSeconds: bufferDuration,
                            playbackDurationSeconds: self.durationSeconds)
                        self.fillPlaybackQueue(revision: revision)
                    }
                }
            } else {
                player.scheduleBuffer(buffer, at: nil, options: [])
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
        for player in stemPlayers.values { player.play(at: start) }
        isPaused = false
        log("play started position=\(formatSeconds(pendingStartSeconds)) queuedUntil=\(formatSeconds(queuedUntilSeconds)) revision=\(revision)")
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
