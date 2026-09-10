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
    /// Silence rendered ahead of the first score sample. The player's sample time
    /// counts those frames, so they are subtracted here to keep the score playhead
    /// parked at the requested position until audible audio actually begins.
    private(set) var prerollSeconds: TimeInterval = 0
    private var fallbackStartPositionSeconds: TimeInterval = 0
    private var fallbackStartedAt: Date?
    private var fallbackDelaySeconds: TimeInterval = 0

    mutating func reset(to positionSeconds: TimeInterval) {
        sampleTimeOriginSeconds = positionSeconds
        fallbackStartPositionSeconds = positionSeconds
        fallbackStartedAt = nil
        fallbackDelaySeconds = 0
        prerollSeconds = 0
    }

    /// Set when silent preroll is scheduled, before the nodes start. Cleared by `reset`,
    /// so a seek or stop cannot leave a stale offset behind.
    mutating func setPreroll(_ seconds: TimeInterval) {
        prerollSeconds = max(seconds, 0)
    }

    mutating func startFallback(
        at positionSeconds: TimeInterval,
        waitsForPreroll: Bool = false,
        now: Date = Date()
    ) {
        fallbackStartPositionSeconds = positionSeconds
        fallbackStartedAt = now
        fallbackDelaySeconds = waitsForPreroll ? prerollSeconds : 0
    }

    mutating func pauseFallback(at positionSeconds: TimeInterval) {
        fallbackStartPositionSeconds = positionSeconds
        fallbackStartedAt = nil
        fallbackDelaySeconds = 0
    }

    func positionSeconds(playerSampleTimeSeconds: TimeInterval?, now: Date = Date()) -> TimeInterval {
        if let playerSampleTimeSeconds {
            return sampleTimeOriginSeconds + max(playerSampleTimeSeconds - prerollSeconds, 0)
        }

        guard let fallbackStartedAt else {
            return fallbackStartPositionSeconds
        }
        return fallbackStartPositionSeconds
            + max(now.timeIntervalSince(fallbackStartedAt) - fallbackDelaySeconds, 0)
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
