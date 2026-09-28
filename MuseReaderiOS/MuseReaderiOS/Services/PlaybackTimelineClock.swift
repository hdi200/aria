//
//  PlaybackTimelineClock.swift
//  MuseReaderiOS
//
//

import Foundation

/// Maps an ever-increasing audio timeline onto a bounded score-time loop.
struct PlaybackLoopTimeline: Equatable, Sendable {
    let startTimeSeconds: TimeInterval
    let endTimeSeconds: TimeInterval

    var durationSeconds: TimeInterval {
        endTimeSeconds - startTimeSeconds
    }

    func wrappedPosition(for timelinePosition: TimeInterval) -> TimeInterval {
        let elapsed = max(timelinePosition - startTimeSeconds, 0)
        return startTimeSeconds + elapsed.truncatingRemainder(dividingBy: durationSeconds)
    }

    func frameCount(sampleRate: Double) -> Int {
        max(1, Int((durationSeconds * sampleRate).rounded()))
    }
}

/// The score range of the next streamed chunk. Frames are score-time frames at
/// the playback sample rate, so repeated loop passes stay sample-exact.
struct PlaybackChunkRequest: Equatable {
    let startFrame: Int
    let frameCount: Int

    /// Returns nil once a non-looping stream has reached `endFrame`.
    static func next(
        renderFrame: Int,
        chunkFrames: Int,
        endFrame: Int,
        loopStartFrame: Int?,
        loopEndFrame: Int?
    ) -> PlaybackChunkRequest? {
        if let loopStartFrame, let loopEndFrame, loopEndFrame > loopStartFrame {
            let start = renderFrame >= loopEndFrame || renderFrame < loopStartFrame ? loopStartFrame : renderFrame
            return PlaybackChunkRequest(startFrame: start, frameCount: min(chunkFrames, loopEndFrame - start))
        }
        guard renderFrame < endFrame else {
            return nil
        }
        return PlaybackChunkRequest(startFrame: renderFrame, frameCount: chunkFrames)
    }
}

/// Maps an `AVAudioPlayerNode` sample timeline to score time.
///
/// Pausing a player node preserves its sample timeline. Resuming must therefore
/// preserve `sampleTimeOriginSeconds`; changing it to the paused score position
/// would count the elapsed samples a second time.
///
/// The player's sample time keeps advancing when its queue runs dry. Each such
/// silent gap is recorded so score time holds still while no audio is playing.
struct PlaybackTimelineClock {
    private struct SilentGap {
        let startSeconds: TimeInterval
        let durationSeconds: TimeInterval
    }

    private(set) var sampleTimeOriginSeconds: TimeInterval = 0
    private var fallbackStartPositionSeconds: TimeInterval = 0
    private var fallbackStartedAt: Date?
    private var silentGaps: [SilentGap] = []

    mutating func reset(to positionSeconds: TimeInterval) {
        sampleTimeOriginSeconds = positionSeconds
        fallbackStartPositionSeconds = positionSeconds
        fallbackStartedAt = nil
        silentGaps.removeAll()
    }

    /// Records player-timeline seconds during which no audio was scheduled.
    mutating func recordSilentGap(startingAtPlayerSeconds startSeconds: TimeInterval, durationSeconds: TimeInterval) {
        guard durationSeconds > 0 else { return }
        silentGaps.append(SilentGap(startSeconds: startSeconds, durationSeconds: durationSeconds))
    }

    private func audiblePlayerSeconds(_ playerSeconds: TimeInterval) -> TimeInterval {
        var silentSeconds: TimeInterval = 0
        for gap in silentGaps where playerSeconds > gap.startSeconds {
            silentSeconds += min(playerSeconds - gap.startSeconds, gap.durationSeconds)
        }
        return playerSeconds - silentSeconds
    }

    mutating func startFallback(
        at positionSeconds: TimeInterval,
        now: Date = Date()
    ) {
        fallbackStartPositionSeconds = positionSeconds
        fallbackStartedAt = now
    }

    mutating func pauseFallback(at positionSeconds: TimeInterval) {
        fallbackStartPositionSeconds = positionSeconds
        fallbackStartedAt = nil
    }

    func positionSeconds(playerSampleTimeSeconds: TimeInterval?, now: Date = Date()) -> TimeInterval {
        if let playerSampleTimeSeconds {
            return sampleTimeOriginSeconds + audiblePlayerSeconds(max(playerSampleTimeSeconds, 0))
        }

        guard let fallbackStartedAt else {
            return fallbackStartPositionSeconds
        }
        return fallbackStartPositionSeconds + max(now.timeIntervalSince(fallbackStartedAt), 0)
    }
}

/// Tracks rendered-buffer consumption independently of the user's playback
/// position. Buffer callbacks may arrive after a pause action, so they must not
/// be used as authoritative playback-position or paused-state updates.
struct PlaybackBufferProgress {
    private(set) var consumedUntilSeconds: TimeInterval = 0
    private(set) var hasConsumedFinalBuffer = false

    mutating func reset(to positionSeconds: TimeInterval) {
        consumedUntilSeconds = positionSeconds
        hasConsumedFinalBuffer = false
    }

    mutating func recordConsumedBuffer(
        startTimeSeconds: TimeInterval,
        durationSeconds: TimeInterval,
        playbackDurationSeconds: TimeInterval
    ) {
        consumedUntilSeconds = max(consumedUntilSeconds, startTimeSeconds + durationSeconds)
        if playbackDurationSeconds > 0,
           consumedUntilSeconds >= playbackDurationSeconds - 0.001 {
            hasConsumedFinalBuffer = true
        }
    }

    func positionWhenNotRendering(
        capturedPositionSeconds: TimeInterval,
        playbackDurationSeconds: TimeInterval,
        isPausedOrWaiting: Bool
    ) -> TimeInterval {
        if !isPausedOrWaiting, hasConsumedFinalBuffer {
            return playbackDurationSeconds
        }
        return capturedPositionSeconds
    }
}
