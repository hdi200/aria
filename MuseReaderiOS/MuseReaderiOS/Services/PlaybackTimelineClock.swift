//
//  PlaybackTimelineClock.swift
//  MuseReaderiOS
//
//

import Foundation

/// Maps an `AVAudioPlayerNode` sample timeline to score time.
///
/// Pausing a player node preserves its sample timeline. Resuming must therefore
/// preserve `sampleTimeOriginSeconds`; changing it to the paused score position
/// would count the elapsed samples a second time.
struct PlaybackTimelineClock {
    private(set) var sampleTimeOriginSeconds: TimeInterval = 0
    private var fallbackStartPositionSeconds: TimeInterval = 0
    private var fallbackStartedAt: Date?

    mutating func reset(to positionSeconds: TimeInterval) {
        sampleTimeOriginSeconds = positionSeconds
        fallbackStartPositionSeconds = positionSeconds
        fallbackStartedAt = nil
    }

    mutating func startFallback(at positionSeconds: TimeInterval, now: Date = Date()) {
        fallbackStartPositionSeconds = positionSeconds
        fallbackStartedAt = now
    }

    mutating func pauseFallback(at positionSeconds: TimeInterval) {
        fallbackStartPositionSeconds = positionSeconds
        fallbackStartedAt = nil
    }

    func positionSeconds(playerSampleTimeSeconds: TimeInterval?, now: Date = Date()) -> TimeInterval {
        if let playerSampleTimeSeconds {
            return sampleTimeOriginSeconds + max(playerSampleTimeSeconds, 0)
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
