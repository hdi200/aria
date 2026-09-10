import Foundation
import Testing
@testable import MuseReaderiOS

struct PlaybackTimelineClockTests {
    @Test
    func resumePreservesPlayerSampleTimelineOrigin() {
        var clock = PlaybackTimelineClock()
        clock.reset(to: 12)

        #expect(clock.positionSeconds(playerSampleTimeSeconds: 3) == 15)

        clock.pauseFallback(at: 15)
        clock.startFallback(at: 15, now: Date(timeIntervalSinceReferenceDate: 100))

        #expect(clock.sampleTimeOriginSeconds == 12)
        #expect(clock.positionSeconds(playerSampleTimeSeconds: 4) == 16)
    }

    @Test
    func repeatedPauseResumeDoesNotDoubleCountElapsedSamples() {
        var clock = PlaybackTimelineClock()
        clock.reset(to: 5)

        clock.pauseFallback(at: 7)
        clock.startFallback(at: 7, now: Date(timeIntervalSinceReferenceDate: 100))
        #expect(clock.positionSeconds(playerSampleTimeSeconds: 3) == 8)

        clock.pauseFallback(at: 8)
        clock.startFallback(at: 8, now: Date(timeIntervalSinceReferenceDate: 200))
        #expect(clock.positionSeconds(playerSampleTimeSeconds: 4.5) == 9.5)
    }

    @Test
    func resetCreatesANewSampleTimelineAfterSeekOrQueueRebuild() {
        var clock = PlaybackTimelineClock()
        clock.reset(to: 10)
        clock.pauseFallback(at: 14)

        clock.reset(to: 40)

        #expect(clock.sampleTimeOriginSeconds == 40)
        #expect(clock.positionSeconds(playerSampleTimeSeconds: 2.25) == 42.25)
    }

    @Test
    func wallClockFallbackStartsAtPausedPosition() {
        var clock = PlaybackTimelineClock()
        let resumedAt = Date(timeIntervalSinceReferenceDate: 100)
        clock.reset(to: 10)
        clock.pauseFallback(at: 13)
        clock.startFallback(at: 13, now: resumedAt)

        #expect(clock.positionSeconds(
            playerSampleTimeSeconds: nil,
            now: resumedAt.addingTimeInterval(2.5)
        ) == 15.5)
    }

    @Test
    func freshStartFallbackWaitsForSilentPrerollButResumeDoesNot() {
        var clock = PlaybackTimelineClock()
        let startedAt = Date(timeIntervalSinceReferenceDate: 100)
        clock.reset(to: 12)
        clock.setPreroll(0.05)
        clock.startFallback(at: 12, waitsForPreroll: true, now: startedAt)

        #expect(clock.positionSeconds(
            playerSampleTimeSeconds: nil,
            now: startedAt.addingTimeInterval(0.04)
        ) == 12)
        #expect(abs(clock.positionSeconds(
            playerSampleTimeSeconds: nil,
            now: startedAt.addingTimeInterval(0.08)
        ) - 12.03) < 0.000_001)
        #expect(abs(clock.positionSeconds(playerSampleTimeSeconds: 0.08) - 12.03) < 0.000_001)

        clock.pauseFallback(at: 12.03)
        let resumedAt = Date(timeIntervalSinceReferenceDate: 200)
        clock.startFallback(at: 12.03, now: resumedAt)
        #expect(abs(clock.positionSeconds(
            playerSampleTimeSeconds: nil,
            now: resumedAt.addingTimeInterval(0.04)
        ) - 12.07) < 0.000_001)
    }

    @Test
    func consumedBufferDoesNotReplaceCapturedPausedPosition() {
        var progress = PlaybackBufferProgress()
        progress.reset(to: 0)

        progress.recordConsumedBuffer(
            startTimeSeconds: 0,
            durationSeconds: 6,
            playbackDurationSeconds: 18
        )

        #expect(progress.consumedUntilSeconds == 6)
        #expect(progress.positionWhenNotRendering(
            capturedPositionSeconds: 5.95,
            playbackDurationSeconds: 18,
            isPausedOrWaiting: true
        ) == 5.95)
    }

    @Test
    func finalBufferOnlyReportsScoreEndAfterPlaybackIsNoLongerPaused() {
        var progress = PlaybackBufferProgress()
        progress.reset(to: 12)
        progress.recordConsumedBuffer(
            startTimeSeconds: 12,
            durationSeconds: 6,
            playbackDurationSeconds: 18
        )

        #expect(progress.hasConsumedFinalBuffer)
        #expect(progress.positionWhenNotRendering(
            capturedPositionSeconds: 17.9,
            playbackDurationSeconds: 18,
            isPausedOrWaiting: true
        ) == 17.9)
        #expect(progress.positionWhenNotRendering(
            capturedPositionSeconds: 17.9,
            playbackDurationSeconds: 18,
            isPausedOrWaiting: false
        ) == 18)
    }
}
