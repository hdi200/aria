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

    private let chunkDurationSeconds: TimeInterval = 6.0
    private let prebufferChunks = 2
    private let edgeFadeSeconds: TimeInterval = 0.0015
    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var liveRenderSession: LiveScoreRenderSession?
    private var metronomeEnabled = false
    private var revision = 0
    private var sampleRate: Double = 48_000
    private var durationSeconds: TimeInterval = 0
    private var queuedUntilSeconds: TimeInterval = 0
    private var pendingStartSeconds: TimeInterval = 0
    private var scheduledStartSeconds: TimeInterval = 0
    private var playbackStartedAt: Date?
    private var isPaused = false
    private var isScheduling = false
    private var schedulingTask: Task<Void, Never>?
    private var scheduledBufferCount = 0

    var isLoaded: Bool {
        engine != nil && playerNode != nil && liveRenderSession != nil
    }

    func prepare(liveRenderSession: LiveScoreRenderSession, durationSeconds: TimeInterval, metronomeEnabled: Bool) async throws {
        guard !isLoaded else {
            log("prepare skipped: already loaded revision=\(revision)")
            return
        }

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
            durationSeconds: chunkDurationSeconds,
            metronomeEnabled: metronomeEnabled
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
        let playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
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
        self.liveRenderSession = liveRenderSession
        self.sampleRate = Double(audioData.sampleRate)
        self.durationSeconds = max(durationSeconds, audioData.durationSeconds)
        self.queuedUntilSeconds = pendingStartSeconds
        self.scheduledStartSeconds = pendingStartSeconds
        self.playbackStartedAt = nil
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
        var status: ScorePlaybackStatus = playerNode.isPlaying ? .playing : (isPaused ? .paused : .stopped)

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

        if !engine.isRunning {
            try engine.start()
        }

        guard !playerNode.isPlaying else {
            return
        }

        playbackStartedAt = Date()
        scheduledStartSeconds = pendingStartSeconds
        playerNode.play()
        isPaused = false
        fillPlaybackQueue(revision: revision)

        log("play position=\(formatSeconds(pendingStartSeconds)) duration=\(formatSeconds(durationSeconds)) queuedUntil=\(formatSeconds(queuedUntilSeconds)) revision=\(revision)")
    }

    func pause() throws {
        guard let playerNode else {
            throw PlaybackError.playerUnavailable
        }
        guard playerNode.isPlaying else {
            return
        }

        pendingStartSeconds = currentPositionSeconds()
        playerNode.pause()
        playbackStartedAt = nil
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

        let wasPlaying = playerNode?.isPlaying == true
        playerNode?.stop()
        cancelSchedulingTask()
        revision += 1
        pendingStartSeconds = bounded(positionSeconds)
        scheduledStartSeconds = pendingStartSeconds
        queuedUntilSeconds = pendingStartSeconds
        playbackStartedAt = nil
        isPaused = !wasPlaying
        fillPlaybackQueue(revision: revision)
        log("seek position=\(formatSeconds(pendingStartSeconds)) wasPlaying=\(wasPlaying) revision=\(revision)")

        if wasPlaying {
            try play()
        }
    }

    func invalidate() {
        playerNode?.stop()
        engine?.stop()
        cancelSchedulingTask()
        engine = nil
        playerNode = nil
        liveRenderSession = nil
        revision += 1
        sampleRate = 48_000
        durationSeconds = 0
        queuedUntilSeconds = 0
        pendingStartSeconds = 0
        scheduledStartSeconds = 0
        playbackStartedAt = nil
        isPaused = false
        isScheduling = false
        scheduledBufferCount = 0
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
        guard metronomeEnabled != enabled else {
            return
        }

        let wasLoaded = isLoaded
        let wasPlaying = playerNode?.isPlaying == true
        let currentPosition = currentPositionSeconds()
        metronomeEnabled = enabled

        guard wasLoaded else {
            return
        }

        playerNode?.stop()
        cancelSchedulingTask()
        revision += 1
        pendingStartSeconds = currentPosition
        scheduledStartSeconds = pendingStartSeconds
        queuedUntilSeconds = pendingStartSeconds
        playbackStartedAt = nil
        isPaused = !wasPlaying
        isScheduling = false
        scheduledBufferCount = 0
        fillPlaybackQueue(revision: revision)

        if wasPlaying {
            playerNode?.play()
            playbackStartedAt = Date()
            isPaused = false
        }

        log("metronome \(enabled ? "enabled" : "disabled") position=\(formatSeconds(pendingStartSeconds)) revision=\(revision)")
    }

    private func fillPlaybackQueue(revision: Int) {
        guard !isScheduling else {
            log("queue fill skipped: already scheduling revision=\(revision)")
            return
        }

        isScheduling = true
        schedulingTask = Task { @MainActor [weak self] in
            defer {
                self?.isScheduling = false
                self?.schedulingTask = nil
            }

            guard let self, let liveRenderSession = self.liveRenderSession else {
                return
            }

            self.log("queue fill begin pending=\(self.formatSeconds(self.pendingStartSeconds)) queuedUntil=\(self.formatSeconds(self.queuedUntilSeconds)) duration=\(self.formatSeconds(self.durationSeconds)) revision=\(revision)")
            while revision == self.revision,
                  self.queuedUntilSeconds < max(self.pendingStartSeconds + (self.chunkDurationSeconds * Double(self.prebufferChunks)), self.durationSeconds == 0 ? self.chunkDurationSeconds : min(self.durationSeconds, self.pendingStartSeconds + (self.chunkDurationSeconds * Double(self.prebufferChunks)))) {
                let startTime = self.queuedUntilSeconds
                if self.durationSeconds > 0, startTime >= self.durationSeconds {
                    return
                }

                do {
                    try Task.checkCancellation()
                    let audioData = try await liveRenderSession.playbackAudioChunk(
                        startTimeSeconds: startTime,
                        durationSeconds: self.chunkDurationSeconds,
                        metronomeEnabled: self.metronomeEnabled
                    )
                    try Task.checkCancellation()
                    try self.schedule(audioData: audioData, startsAt: startTime, revision: revision)
                } catch {
                    print("MuseReader live playback render failed: \(error.localizedDescription)")
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

        guard let buffer = makeBuffer(from: audioData) else {
            throw PlaybackError.sequenceLoadFailed("The live playback render could not be converted to an audio buffer.")
        }

        let bufferDuration = Double(buffer.frameLength) / buffer.format.sampleRate
        applyEdgeFade(to: buffer, startsAt: startTime, duration: bufferDuration)
        scheduledBufferCount += 1
        log("schedule buffer=\(scheduledBufferCount) start=\(formatSeconds(startTime)) duration=\(formatSeconds(bufferDuration)) frames=\(buffer.frameLength) revision=\(revision)")
        playerNode.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, revision == self.revision else {
                    return
                }
                self.pendingStartSeconds = self.bounded(startTime + bufferDuration)
                self.isPaused = false
                self.log("buffer complete start=\(self.formatSeconds(startTime)) nextPending=\(self.formatSeconds(self.pendingStartSeconds)) revision=\(revision)")
                self.fillPlaybackQueue(revision: revision)
            }
        }

        queuedUntilSeconds = max(queuedUntilSeconds, startTime + bufferDuration)
    }

    private func makeBuffer(from audioData: MSRPlaybackAudioData) -> AVAudioPCMBuffer? {
        let frameCount = audioData.interleavedFloat32Samples.count / MemoryLayout<Float>.size / audioData.channelCount
        guard frameCount > 0 else {
            return nil
        }

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(audioData.sampleRate),
            channels: AVAudioChannelCount(audioData.channelCount),
            interleaved: false
        ),
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))
        else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        audioData.interleavedFloat32Samples.withUnsafeBytes { rawBuffer in
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
            return bounded(scheduledStartSeconds + (Double(playerTime.sampleTime) / playerTime.sampleRate))
        }

        if playerNode?.isPlaying == true {
            return bounded(scheduledStartSeconds)
        }

        if let playbackStartedAt {
            return bounded(scheduledStartSeconds + Date().timeIntervalSince(playbackStartedAt))
        }

        return bounded(pendingStartSeconds)
    }

    private func stopInternally() {
        playerNode?.stop()
        cancelSchedulingTask()
        revision += 1
        queuedUntilSeconds = 0
        pendingStartSeconds = 0
        scheduledStartSeconds = 0
        playbackStartedAt = nil
        isPaused = false
        isScheduling = false
        scheduledBufferCount = 0
        log("stop revision=\(revision)")
    }

    private func bounded(_ positionSeconds: TimeInterval) -> TimeInterval {
        if durationSeconds > 0 {
            return min(max(positionSeconds, 0), durationSeconds)
        }
        return max(positionSeconds, 0)
    }

    private func applyEdgeFade(to buffer: AVAudioPCMBuffer, startsAt startTime: TimeInterval, duration: TimeInterval) {
        guard let channels = buffer.floatChannelData else {
            return
        }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else {
            return
        }

        let sampleRate = buffer.format.sampleRate
        let fadeFrames = min(frameCount / 2, max(1, Int(edgeFadeSeconds * sampleRate)))
        let shouldFadeIn = startTime > 0.001
        let shouldFadeOut = durationSeconds <= 0 || startTime + duration < durationSeconds - 0.001

        for channel in 0..<Int(buffer.format.channelCount) {
            let channelData = channels[channel]
            if shouldFadeIn {
                for frame in 0..<fadeFrames {
                    channelData[frame] *= Float(frame) / Float(fadeFrames)
                }
            }
            if shouldFadeOut {
                for frame in 0..<fadeFrames {
                    let index = frameCount - 1 - frame
                    channelData[index] *= Float(frame) / Float(fadeFrames)
                }
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
