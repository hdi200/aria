//
//  NativePlaybackController.swift
//  MuseReaderiOS
//
//

import Accelerate
import AVFoundation
import Foundation

/// Streams rendered score audio to one `AVAudioPlayerNode`.
///
/// Audio moves through two queues. Raw per-part stems are rendered up to a few
/// seconds ahead, which absorbs stalls on the shared render-session actor (page
/// renders, edits). Only the next half second is mixed and scheduled on the
/// player, so fader, pan, mute, solo and metronome changes stay responsive.
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
                #if os(Android)
                return "Aria could not prepare the audio session: \(message)"
                #else
                return "Aria could not prepare the iPad audio session: \(message)"
                #endif
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

    /// A rendered chunk waiting to be mixed. `frameCount` may be shorter than the
    /// rendered audio when the chunk is cut at a loop end.
    private struct RenderedChunk {
        let audioData: MSRPlaybackAudioData
        let frameCount: Int
        let fadesIn: Bool
        let fadesOut: Bool
    }

    /// A count-in that is sounding, in host time, so score time can hold at the
    /// start position until the score player takes over.
    private struct ActiveCountIn {
        let countIn: MSRPlaybackCountIn
        let startHostTime: UInt64
        let endHostTime: UInt64
    }

    private let chunkDurationSeconds: TimeInterval = 0.125
    /// Mixed audio scheduled on the player. Mixer changes reach the output within this window.
    private let mixAheadDurationSeconds: TimeInterval = 0.5
    /// Rendered, unmixed audio kept ahead of the output, bounded by `renderAheadByteLimit`.
    private let maximumRenderAheadDurationSeconds: TimeInterval = 3
    private let renderAheadByteLimit = 32.0 * 1_024 * 1_024
    /// Lets the last notes and the reverb ring out after the final barline.
    private let tailDurationSeconds: TimeInterval = 2
    /// Desktop MuseScore's default send from each SoundFont instrument to its
    /// reverb aux channel; the metronome has no send.
    private let reverbSendLevel: Float = 0.3
    /// Short fades at loop wraps so notes cut at the loop end do not click.
    private let loopEdgeFadeFrames = 192

    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    /// Plays count-in clicks; the score player starts when the count-in ends.
    private var countInNode: AVAudioPlayerNode?
    /// Handed to `play(countIn:)` and played when the queue is ready to start.
    private var pendingCountIn: MSRPlaybackCountIn?
    private var activeCountIn: ActiveCountIn?
    private var reverb: MSRPlaybackReverb?
    private var renderedStemIDs: Set<String> = []
    private var nextScheduledSampleTime: AVAudioFramePosition = 0
    private var needsPlayerPriming = true
    private var mixerSettings = ScoreMixerSettings()
    private var meterLevelHandler: (([String: Float]) -> Void)?
    private var stemIDsHandler: ((Set<String>) -> Void)?
    private var meterPeaks: [String: Float] = [:]
    private var displayedMeterLevels: [String: Float] = [:]
    private var meterUpdateTask: Task<Void, Never>?
    private var isMeteringEnabled = false
    private var meterTapsInstalled = false
    private(set) var streamingErrorMessage: String?

    nonisolated static let masterMeterID = "__muse_reader_master__"
    /// The stem and mixer channel of every part's chord symbol playback.
    nonisolated static let chordSymbolsStemID = "chordsymbols"

    private var liveRenderSession: LiveScoreRenderSession?
    private var metronomeEnabled = false
    private var revision = 0
    private var sampleRate: Double = 48_000
    private var durationSeconds: TimeInterval = 0
    private var pendingStartSeconds: TimeInterval = 0
    /// Score-time frame of the next chunk to render.
    private var nextRenderFrame = 0
    private var previousChunkEndedLoopPass = false
    private var renderedChunks: [RenderedChunk] = []
    /// Audio-timeline ends of the rendered and the scheduled queues.
    private var renderedUntilSeconds: TimeInterval = 0
    private var queuedUntilSeconds: TimeInterval = 0
    private var timelineClock = PlaybackTimelineClock()
    private var bufferProgress = PlaybackBufferProgress()
    private var isPaused = false
    private var isScheduling = false
    private var schedulingTask: Task<Void, Never>?
    private var playWhenBuffered = false
    private var loopRange: PlaybackLoopTimeline?

    var isLoaded: Bool {
        engine != nil && playerNode != nil && liveRenderSession != nil
    }

    var isWaitingToStartPlayback: Bool {
        playWhenBuffered
    }

    func setMixerSettings(_ settings: ScoreMixerSettings) {
        mixerSettings = settings
        applyMixerSettings()
    }

    func setMeterLevelHandler(_ handler: (([String: Float]) -> Void)?) {
        meterLevelHandler = handler
    }

    /// Called with the rendered stems each time playback is prepared.
    func setStemIDsHandler(_ handler: ((Set<String>) -> Void)?) {
        stemIDsHandler = handler
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

        // The first chunk discovers the sample rate and stem layout.
        let startFrame = frame(forSeconds: pendingStartSeconds)
        let audioData = try await liveRenderSession.playbackAudioChunk(
            startTimeSeconds: Double(startFrame) / sampleRate,
            durationSeconds: chunkDurationSeconds,
            metronomeEnabled: true
        )
        try Task.checkCancellation()
        guard prepareRevision == revision else {
            throw CancellationError()
        }
        log("prepare audio sampleRate=\(audioData.sampleRate) channels=\(audioData.channelCount) stems=\(audioData.partSamples.count) duration=\(formatSeconds(audioData.durationSeconds))")
        guard audioData.channelCount == 2, !audioData.interleavedFloat32Samples.isEmpty else {
            throw PlaybackError.sequenceLoadFailed("The live playback render was empty or unsupported.")
        }

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(audioData.sampleRate),
            channels: 2,
            interleaved: false
        ) else {
            throw PlaybackError.playerInitializationFailed("The live playback audio format could not be created.")
        }

        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        let countInNode = AVAudioPlayerNode()
        engine.attach(playerNode)
        engine.attach(countInNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        engine.connect(countInNode, to: engine.mainMixerNode, format: format)
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
        self.countInNode = countInNode
        self.renderedStemIDs = Set(audioData.partSamples.keys)
        stemIDsHandler?(renderedStemIDs)
        applyMixerSettings()
        installMeterTapsIfPossible()
        self.liveRenderSession = liveRenderSession
        self.sampleRate = Double(audioData.sampleRate)
        self.durationSeconds = max(durationSeconds, audioData.durationSeconds)
        self.reverb = MSRPlaybackReverb(sampleRate: sampleRate)
        resetQueueState(to: pendingStartSeconds)
        self.isPaused = false

        let request = PlaybackChunkRequest(startFrame: startFrame, frameCount: chunkFrameCount)
        try appendRenderedChunk(audioData, for: request)
        try scheduleRenderedChunks()
        fillPlaybackQueue(revision: prepareRevision)
        log("prepare ready duration=\(formatSeconds(self.durationSeconds)) queuedUntil=\(formatSeconds(queuedUntilSeconds)) revision=\(revision)")
    }

    func state() -> ScorePlaybackState {
        guard let playerNode else {
            return ScorePlaybackState(isAvailable: true, status: .stopped, positionSeconds: pendingStartSeconds, durationSeconds: durationSeconds)
        }

        let timelinePosition = currentTimelinePositionSeconds()
        var positionSeconds = scorePosition(for: timelinePosition)
        var status: ScorePlaybackStatus = (playerNode.isPlaying || playWhenBuffered) ? .playing : (isPaused ? .paused : .stopped)

        if loopRange == nil, durationSeconds > 0, timelinePosition >= playbackEndSeconds - 0.001 {
            stopInternally()
            positionSeconds = 0
            status = .stopped
        }

        return ScorePlaybackState(isAvailable: true, status: status, positionSeconds: positionSeconds, durationSeconds: durationSeconds)
    }

    /// Starts or resumes playback. A count-in plays first, once enough audio
    /// is queued for the score to follow it without a gap.
    func play(countIn: MSRPlaybackCountIn? = nil) throws {
        guard let engine, let playerNode else {
            throw PlaybackError.playerUnavailable
        }

        streamingErrorMessage = nil
        pendingCountIn = countIn
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
            pendingCountIn = nil
            timelineClock.pauseFallback(at: pendingStartSeconds)
            isPaused = true
            log("pause armed playback position=\(formatSeconds(pendingStartSeconds)) revision=\(revision)")
            return
        }
        if isCountingIn {
            let position = pendingStartSeconds
            resetPlaybackQueue(to: position, wasPlaying: false)
            timelineClock.pauseFallback(at: position)
            isPaused = true
            log("pause count-in position=\(formatSeconds(position)) revision=\(revision)")
            return
        }
        guard playerNode.isPlaying else {
            return
        }

        pendingStartSeconds = currentPositionSeconds()
        timelineClock.pauseFallback(at: pendingStartSeconds)
        cancelCountIn()
        playerNode.pause()
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

        // A looping stream always restarts at the loop start. Keeping the visual
        // clock on the same origin avoids a scrub making the highlight disagree
        // with the audio.
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

    /// Loops a score-time range. The stream wraps to the loop start at each loop
    /// end; the renderer reproduces the start state exactly, so every pass sounds
    /// the same, and memory does not grow with the loop length.
    func setLoopRange(startTimeSeconds: TimeInterval, endTimeSeconds: TimeInterval) async throws {
        guard playerNode != nil, liveRenderSession != nil else {
            throw PlaybackError.playerUnavailable
        }

        // Quantize to frames so each pass is a whole number of samples and the
        // wrapped clock cannot drift from the audio.
        let startFrame = frame(forSeconds: bounded(startTimeSeconds))
        let endFrame = frame(forSeconds: bounded(endTimeSeconds))
        guard endFrame - startFrame > 1 else {
            throw PlaybackError.invalidLoopRange
        }

        loopRange = PlaybackLoopTimeline(
            startTimeSeconds: Double(startFrame) / sampleRate,
            endTimeSeconds: Double(endFrame) / sampleRate
        )
        resetPlaybackQueue(to: Double(startFrame) / sampleRate, wasPlaying: false)
        log("loop configured start=\(formatSeconds(startTimeSeconds)) end=\(formatSeconds(endTimeSeconds)) revision=\(revision)")
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
        cancelCountIn()
        playerNode?.stop()
        engine?.stop()
        cancelSchedulingTask()
        streamingErrorMessage = nil
        engine = nil
        playerNode = nil
        countInNode = nil
        reverb = nil
        liveRenderSession = nil
        revision += 1
        sampleRate = 48_000
        renderedStemIDs.removeAll()
        durationSeconds = 0
        loopRange = nil
        resetQueueState(to: 0)
        isPaused = false
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
        var peak: Float = 0
        for channel in 0..<Int(buffer.format.channelCount) {
            var channelPeak: Float = 0
            vDSP_maxmgv(channels[channel], 1, &channelPeak, vDSP_Length(buffer.frameLength))
            peak = max(peak, channelPeak)
        }
        guard peak > 0.000_01 else { return 0 }
        let decibels = 20 * log10(peak)
        return min(max((decibels + 60) / 60, 0), 1)
    }

    func visualLatencyCompensationSeconds() -> TimeInterval {
        guard playerNode?.isPlaying == true else {
            return 0
        }
        return outputLatencySeconds
    }

    private var outputLatencySeconds: TimeInterval {
        let audioSession = AVAudioSession.sharedInstance()
        let sessionLatency = audioSession.outputLatency + audioSession.ioBufferDuration
        let outputLatency = engine?.outputNode.presentationLatency ?? 0
        return min(max(max(sessionLatency, outputLatency), 0), 0.12)
    }

    func setMetronomeEnabled(_ enabled: Bool) {
        metronomeEnabled = enabled
    }

    // MARK: - Count-in

    /// True while count-in clicks sound and the score has not started yet.
    var isCountingIn: Bool {
        guard let activeCountIn else { return false }
        return mach_absolute_time() < activeCountIn.endHostTime
    }

    /// The click most recently heard, allowing for output latency, while a
    /// count-in sounds.
    func currentCountInClick() -> MSRPlaybackCountInClick? {
        guard let activeCountIn else { return nil }
        let now = mach_absolute_time()
        guard now < activeCountIn.endHostTime, now >= activeCountIn.startHostTime else {
            return nil
        }
        let elapsed = AVAudioTime.seconds(forHostTime: now - activeCountIn.startHostTime) - outputLatencySeconds
        return activeCountIn.countIn.clicks.last { $0.timeSeconds <= elapsed + 0.005 }
    }

    private func cancelCountIn() {
        countInNode?.stop()
        activeCountIn = nil
        pendingCountIn = nil
    }

    private func makeCountInBuffer(_ audioData: MSRPlaybackAudioData) -> AVAudioPCMBuffer? {
        let frameCount = audioData.interleavedFloat32Samples.count / MemoryLayout<Float>.size / 2
        guard audioData.channelCount == 2,
              Double(audioData.sampleRate) == sampleRate,
              frameCount > 0,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)),
              let left = buffer.floatChannelData?[0],
              let right = buffer.floatChannelData?[1] else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        audioData.interleavedFloat32Samples.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Float.self).baseAddress!
            cblas_scopy(Int32(frameCount), samples, 2, left, 1)
            cblas_scopy(Int32(frameCount), samples + 1, 2, right, 1)
        }
        return buffer
    }

    // MARK: - Queue

    private var playbackEndSeconds: TimeInterval {
        durationSeconds + tailDurationSeconds
    }

    private var chunkFrameCount: Int {
        max(1, frame(forSeconds: chunkDurationSeconds))
    }

    private var renderAheadDurationSeconds: TimeInterval {
        // The interleaved mix plus one stereo stem per part, as 32-bit floats.
        let bytesPerSecond = sampleRate * 2 * 4 * Double(renderedStemIDs.count + 1)
        return max(mixAheadDurationSeconds, min(maximumRenderAheadDurationSeconds, renderAheadByteLimit / bytesPerSecond))
    }

    private func nextChunkRequest() -> PlaybackChunkRequest? {
        let loopFrames = loopRange.map { (frame(forSeconds: $0.startTimeSeconds), frame(forSeconds: $0.endTimeSeconds)) }
        return PlaybackChunkRequest.next(
            renderFrame: nextRenderFrame,
            chunkFrames: chunkFrameCount,
            endFrame: durationSeconds > 0 ? frame(forSeconds: playbackEndSeconds) : Int.max,
            loopStartFrame: loopFrames?.0,
            loopEndFrame: loopFrames?.1
        )
    }

    /// Renders ahead on the render-session actor, handing each chunk to the mix
    /// queue as it arrives. Completion callbacks keep draining already rendered
    /// chunks while this task waits on the actor.
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

            while revision == self.revision,
                  self.renderedUntilSeconds < self.bufferProgress.consumedUntilSeconds + self.renderAheadDurationSeconds,
                  let request = self.nextChunkRequest() {
                do {
                    try Task.checkCancellation()
                    let audioData = try await liveRenderSession.playbackAudioChunk(
                        startTimeSeconds: Double(request.startFrame) / self.sampleRate,
                        durationSeconds: Double(request.frameCount) / self.sampleRate,
                        metronomeEnabled: true
                    )
                    try Task.checkCancellation()
                    guard revision == self.revision else {
                        return
                    }
                    try self.appendRenderedChunk(audioData, for: request)
                    try self.scheduleRenderedChunks()
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
                        self.handleStreamingFailure(error)
                    } else {
                        self.log("queue fill failed stale revision=\(revision) current=\(self.revision): \(error.localizedDescription)")
                    }
                    return
                }

                self.startPlaybackIfArmedAndBuffered()
            }
            self.startPlaybackIfArmedAndBuffered()
        }
    }

    private func startPlaybackIfArmedAndBuffered() {
        guard playWhenBuffered, hasEnoughAudioToStart, let playerNode else {
            return
        }
        do {
            try startPlaybackWhenBuffered(engine: engine, playerNode: playerNode)
        } catch {
            playWhenBuffered = false
            isPaused = true
            streamingErrorMessage = error.localizedDescription
            log("playback start failed: \(error.localizedDescription)")
        }
    }

    private func handleStreamingFailure(_ error: Error) {
        playWhenBuffered = false
        let position = currentPositionSeconds()
        cancelCountIn()
        playerNode?.stop()
        cancelSchedulingTask()
        revision += 1
        resetQueueState(to: position)
        isPaused = true
        streamingErrorMessage = error.localizedDescription
        print("MuseReader live playback render failed: \(error.localizedDescription)")
    }

    private func cancelSchedulingTask() {
        schedulingTask?.cancel()
        schedulingTask = nil
        isScheduling = false
    }

    private func resetQueueState(to positionSeconds: TimeInterval) {
        pendingStartSeconds = positionSeconds
        timelineClock.reset(to: positionSeconds)
        bufferProgress.reset(to: positionSeconds)
        nextRenderFrame = frame(forSeconds: positionSeconds)
        previousChunkEndedLoopPass = false
        renderedChunks.removeAll()
        renderedUntilSeconds = positionSeconds
        queuedUntilSeconds = positionSeconds
        nextScheduledSampleTime = 0
        needsPlayerPriming = true
        playWhenBuffered = false
        pendingCountIn = nil
        activeCountIn = nil
        reverb?.reset()
    }

    private func resetPlaybackQueue(to positionSeconds: TimeInterval, wasPlaying: Bool) {
        cancelCountIn()
        playerNode?.stop()
        cancelSchedulingTask()
        revision += 1
        resetQueueState(to: positionSeconds)
        isPaused = !wasPlaying
        fillPlaybackQueue(revision: revision)
    }

    private func appendRenderedChunk(_ audioData: MSRPlaybackAudioData, for request: PlaybackChunkRequest) throws {
        guard Set(audioData.partSamples.keys) == renderedStemIDs,
              Double(audioData.sampleRate) == sampleRate else {
            throw PlaybackError.sequenceLoadFailed("The instrument layout changed. Stop and restart playback.")
        }

        let renderedFrames = audioData.interleavedFloat32Samples.count / MemoryLayout<Float>.size / 2
        // The renderer may return a little more than requested (block alignment)
        // or less (end of the score). Loop audio is cut exactly at the loop end.
        var frameCount = renderedFrames
        var endsLoopPass = false
        if let loopRange {
            let framesToLoopEnd = frame(forSeconds: loopRange.endTimeSeconds) - request.startFrame
            frameCount = min(renderedFrames, framesToLoopEnd)
            endsLoopPass = frameCount == framesToLoopEnd
        }
        guard frameCount > 0 else {
            throw PlaybackError.sequenceLoadFailed("An instrument audio buffer was invalid.")
        }

        renderedChunks.append(RenderedChunk(
            audioData: audioData,
            frameCount: frameCount,
            fadesIn: previousChunkEndedLoopPass,
            fadesOut: endsLoopPass
        ))
        previousChunkEndedLoopPass = endsLoopPass
        nextRenderFrame = request.startFrame + frameCount
        renderedUntilSeconds += Double(frameCount) / sampleRate
    }

    /// Mixes rendered chunks and schedules them until the output holds the mix-ahead window.
    private func scheduleRenderedChunks() throws {
        while queuedUntilSeconds < bufferProgress.consumedUntilSeconds + mixAheadDurationSeconds,
              !renderedChunks.isEmpty {
            try schedule(renderedChunks.removeFirst())
        }
    }

    private func schedule(_ chunk: RenderedChunk) throws {
        guard let playerNode,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunk.frameCount)),
              let left = buffer.floatChannelData?[0],
              let right = buffer.floatChannelData?[1] else {
            throw PlaybackError.sequenceLoadFailed("An instrument audio buffer was invalid.")
        }

        buffer.frameLength = AVAudioFrameCount(chunk.frameCount)
        vDSP_vclr(left, 1, vDSP_Length(chunk.frameCount))
        vDSP_vclr(right, 1, vDSP_Length(chunk.frameCount))
        var reverbSend = [Float](repeating: 0, count: chunk.frameCount * 2)
        let partMeterLevels: [String: Float]
        do {
            partMeterLevels = try reverbSend.withUnsafeMutableBufferPointer { send in
                try StemSoftwareMixer.mix(
                    partSamples: chunk.audioData.partSamples,
                    frameCount: chunk.frameCount,
                    settings: mixerSettings,
                    metronomeEnabled: metronomeEnabled,
                    left: left,
                    right: right,
                    reverbSend: reverb == nil ? nil : send.baseAddress,
                    reverbSendLevel: reverbSendLevel
                )
            }
        } catch {
            throw PlaybackError.sequenceLoadFailed("An instrument audio buffer was invalid.")
        }
        // Fade the dry signal and the send at loop wraps; the reverb tail itself
        // keeps ringing across the wrap.
        reverbSend.withUnsafeMutableBufferPointer { send in
            let sendBase = send.baseAddress!
            if chunk.fadesIn {
                applyFade(left: left, right: right, frameCount: chunk.frameCount, fadingIn: true)
                applyFade(interleaved: sendBase, frameCount: chunk.frameCount, fadingIn: true)
            }
            if chunk.fadesOut {
                applyFade(left: left, right: right, frameCount: chunk.frameCount, fadingIn: false)
                applyFade(interleaved: sendBase, frameCount: chunk.frameCount, fadingIn: false)
            }
            if let reverb {
                reverb.processInterleavedStereo(sendBase, frameCount: chunk.frameCount)
                let count = vDSP_Length(chunk.frameCount)
                vDSP_vadd(sendBase, 2, left, 1, left, 1, count)
                vDSP_vadd(sendBase + 1, 2, right, 1, right, 1, count)
            }
        }

        // Schedule at an explicit player time. If the queue ran dry, start a
        // little ahead of the render position and record the silence, so the
        // score clock stays with the audio instead of running ahead of it.
        var startSampleTime = nextScheduledSampleTime
        if playerNode.isPlaying, !isCountingIn, let playerSampleTime = currentPlayerSampleTime() {
            let marginSeconds = AVAudioSession.sharedInstance().ioBufferDuration * 2 + 0.01
            let earliestSampleTime = playerSampleTime + AVAudioFramePosition(marginSeconds * sampleRate)
            if startSampleTime < earliestSampleTime {
                let gapFrames = earliestSampleTime - startSampleTime
                timelineClock.recordSilentGap(
                    startingAtPlayerSeconds: Double(startSampleTime) / sampleRate,
                    durationSeconds: Double(gapFrames) / sampleRate
                )
                log("underrun gap=\(formatSeconds(Double(gapFrames) / sampleRate))s position=\(formatSeconds(queuedUntilSeconds)) revision=\(revision)")
                startSampleTime = earliestSampleTime
            }
        }

        let revision = revision
        let timelineStart = queuedUntilSeconds
        let bufferDuration = Double(chunk.frameCount) / sampleRate
        playerNode.scheduleBuffer(
            buffer,
            at: AVAudioTime(sampleTime: startSampleTime, atRate: sampleRate),
            options: [],
            completionCallbackType: .dataRendered
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, revision == self.revision else { return }
                if self.isMeteringEnabled {
                    for (partID, level) in partMeterLevels {
                        self.recordMeterPeak(level, for: partID)
                    }
                }
                self.bufferProgress.recordConsumedBuffer(
                    startTimeSeconds: timelineStart, durationSeconds: bufferDuration,
                    playbackDurationSeconds: self.loopRange == nil ? self.playbackEndSeconds : 0)
                do {
                    try self.scheduleRenderedChunks()
                } catch {
                    self.handleStreamingFailure(error)
                    return
                }
                self.fillPlaybackQueue(revision: revision)
            }
        }

        nextScheduledSampleTime = startSampleTime + AVAudioFramePosition(chunk.frameCount)
        queuedUntilSeconds += bufferDuration
    }

    private func applyFade(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frameCount: Int, fadingIn: Bool) {
        forEachFadeGain(frameCount: frameCount, fadingIn: fadingIn) { frame, gain in
            left[frame] *= gain
            right[frame] *= gain
        }
    }

    private func applyFade(interleaved samples: UnsafeMutablePointer<Float>, frameCount: Int, fadingIn: Bool) {
        forEachFadeGain(frameCount: frameCount, fadingIn: fadingIn) { frame, gain in
            samples[frame * 2] *= gain
            samples[frame * 2 + 1] *= gain
        }
    }

    private func forEachFadeGain(frameCount: Int, fadingIn: Bool, _ body: (Int, Float) -> Void) {
        let fadeFrames = min(loopEdgeFadeFrames, frameCount)
        guard fadeFrames > 1 else { return }
        let offset = fadingIn ? 0 : frameCount - fadeFrames
        for index in 0..<fadeFrames {
            let progress = Float(index) / Float(fadeFrames - 1)
            body(offset + index, fadingIn ? progress : 1 - progress)
        }
    }

    // MARK: - Position

    private func currentPlayerSampleTime() -> AVAudioFramePosition? {
        guard let playerNode,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
              playerTime.sampleRate > 0 else {
            return nil
        }
        return AVAudioFramePosition((Double(playerTime.sampleTime) * sampleRate / playerTime.sampleRate).rounded())
    }

    /// Audio-timeline position: score time, before loop wrapping and clamping.
    private func currentTimelinePositionSeconds() -> TimeInterval {
        // The score player has a start time but no audible position yet.
        if isCountingIn {
            return pendingStartSeconds
        }
        if let playerNode, playerNode.isPlaying {
            guard let playerSampleTime = currentPlayerSampleTime() else {
                return timelineClock.positionSeconds(playerSampleTimeSeconds: nil)
            }
            // Hold still while the queue is dry; the gap is recorded when audio resumes.
            let audibleSampleTime = min(playerSampleTime, nextScheduledSampleTime)
            return timelineClock.positionSeconds(playerSampleTimeSeconds: Double(audibleSampleTime) / sampleRate)
        }

        return bufferProgress.positionWhenNotRendering(
            capturedPositionSeconds: pendingStartSeconds,
            playbackDurationSeconds: loopRange == nil ? playbackEndSeconds : 0,
            isPausedOrWaiting: isPaused || playWhenBuffered
        )
    }

    private func currentPositionSeconds() -> TimeInterval {
        scorePosition(for: currentTimelinePositionSeconds())
    }

    private func scorePosition(for timelinePosition: TimeInterval) -> TimeInterval {
        if let loopRange {
            return loopRange.wrappedPosition(for: timelinePosition)
        }
        return bounded(timelinePosition)
    }

    private func stopInternally() {
        cancelCountIn()
        playerNode?.stop()
        cancelSchedulingTask()
        revision += 1
        resetQueueState(to: loopRange?.startTimeSeconds ?? 0)
        isPaused = false
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
        // queue must not wait for the cushion required by a fresh start/seek.
        let isResumingPausedQueue = isPaused && !needsPlayerPriming
        guard isResumingPausedQueue || hasEnoughAudioToStart else {
            playWhenBuffered = true
            isPaused = false
            timelineClock.pauseFallback(at: pendingStartSeconds)
            log("play armed waiting for buffer position=\(formatSeconds(pendingStartSeconds)) revision=\(revision)")
            return
        }

        playWhenBuffered = false
        var primedFrameCount: AVAudioFrameCount = 0
        if needsPlayerPriming {
            primedFrameCount = AVAudioFrameCount(min(nextScheduledSampleTime, 4_096))
            playerNode.prepare(withFrameCount: primedFrameCount)
            needsPlayerPriming = false
        }
        let startHostTime = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.03)
        var scoreStartHostTime = startHostTime
        var countInSeconds: TimeInterval = 0
        // Both players run on the engine's render clock, so starting them at
        // host times one count-in apart keeps the score on the click grid.
        if let countIn = pendingCountIn,
           let countInNode,
           let buffer = makeCountInBuffer(countIn.audioData) {
            countInSeconds = countIn.durationSeconds
            scoreStartHostTime = startHostTime + AVAudioTime.hostTime(forSeconds: countInSeconds)
            countInNode.stop()
            countInNode.scheduleBuffer(buffer, at: nil, options: [])
            countInNode.play(at: AVAudioTime(hostTime: startHostTime))
            activeCountIn = ActiveCountIn(countIn: countIn, startHostTime: startHostTime, endHostTime: scoreStartHostTime)
        }
        pendingCountIn = nil
        timelineClock.startFallback(at: pendingStartSeconds, now: Date().addingTimeInterval(countInSeconds))
        playerNode.play(at: AVAudioTime(hostTime: scoreStartHostTime))
        isPaused = false
        let audioSession = AVAudioSession.sharedInstance()
        let outputFormat = engine?.outputNode.outputFormat(forBus: 0)
        let ioBufferMilliseconds = String(format: "%.2f", audioSession.ioBufferDuration * 1_000)
        let outputLatencyMilliseconds = String(format: "%.2f", audioSession.outputLatency * 1_000)
        let meterState = isMeteringEnabled ? "on" : "off"
        let startKind = (isResumingPausedQueue ? "resume" : "fresh") + (countInSeconds > 0 ? "+countIn(\(formatSeconds(countInSeconds))s)" : "")
        log("startup start kind=\(startKind) revision=\(revision) score=\(formatSeconds(pendingStartSeconds)) "
            + "queued=\(formatSeconds(queuedUntilSeconds - pendingStartSeconds))s "
            + "rendered=\(formatSeconds(renderedUntilSeconds - pendingStartSeconds))s "
            + "scheduledFrames=\(nextScheduledSampleTime) engineRate=\(Int(outputFormat?.sampleRate ?? 0)) "
            + "ioBuffer=\(ioBufferMilliseconds)ms outputLatency=\(outputLatencyMilliseconds)ms "
            + "meters=\(meterState) primedFrames=\(primedFrameCount)")
    }

    private var hasEnoughAudioToStart: Bool {
        let requiredDuration: TimeInterval
        if loopRange != nil || durationSeconds <= 0 {
            requiredDuration = mixAheadDurationSeconds
        } else {
            requiredDuration = min(mixAheadDurationSeconds, max(playbackEndSeconds - pendingStartSeconds, 0))
        }
        return queuedUntilSeconds - pendingStartSeconds + 0.000_001 >= requiredDuration
    }

    private func frame(forSeconds seconds: TimeInterval) -> Int {
        max(0, Int((seconds * sampleRate).rounded()))
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
