import CoreGraphics
import Testing
@testable import MuseReaderiOS

struct ScoreVideoExporterTests {
    @Test func videoMasterMixUsesVolumeAndStereoBalance() {
        for (pan, expected): (Float, [Float]) in [
            (0, [0.1, 0.2]), (0.4, [0.06, 0.2]), (-0.4, [0.1, 0.12]),
            (1, [0, 0.2]), (-1, [0.1, 0])
        ] {
            var samples: [Float] = [0.2, 0.4]
            ScoreVideoAudioChunk.applyMasterMix(ScoreMixerSettings(masterVolume: 0.5, masterPan: pan),
                                               to: &samples, channelCount: 2)
            #expect(abs(samples[0] - expected[0]) < 0.000001)
            #expect(abs(samples[1] - expected[1]) < 0.000001)
        }
    }

    @Test func videoMasterMuteSilencesBothChannelsAndDefaultPreservesPCM() {
        let input: [Float] = [0.2, -0.4, 0, 0.8]
        var samples = input
        ScoreVideoAudioChunk.applyMasterMix(ScoreMixerSettings(), to: &samples, channelCount: 2)
        #expect(samples == input)
        ScoreVideoAudioChunk.applyMasterMix(ScoreMixerSettings(masterMuted: true), to: &samples, channelCount: 2)
        #expect(samples.allSatisfy { $0 == 0 })
    }

    private func region(_ measure: Int, page: Int, start: Double, end: Double, y: Double = 0.2) -> ScorePlaybackMeasureRegion {
        ScorePlaybackMeasureRegion(
            measureIndex: measure,
            pageIndex: page,
            startTimeSeconds: start,
            endTimeSeconds: end,
            normalizedRect: ScoreNormalizedRect(x: 0.1, y: y, width: 0.2, height: 0.1)
        )
    }

    @Test func timelineFollowsPlaybackOrderIncludingRepeats() {
        // A repeat plays measure 0 again after measure 1.
        let timeline = ScoreVideoTimeline(regions: [
            region(0, page: 0, start: 4, end: 6),
            region(0, page: 0, start: 0, end: 2),
            region(1, page: 0, start: 2, end: 4)
        ])

        #expect(timeline.regionIndex(at: -1) == 0)
        #expect(timeline.regionIndex(at: 3) == 1)
        #expect(timeline.regionIndex(at: 5).map { timeline.regions[$0].startTimeSeconds } == 4)
        #expect(timeline.progress(inRegion: 1, at: 3) == 0.5)
        #expect(timeline.endTimeSeconds == 6)
    }

    @Test func canvasStacksPagesAndPlacesMeasures() {
        let canvas = ScoreVideoCanvas(pageSizes: [CGSize(width: 612, height: 792), CGSize(width: 612, height: 792)], pageWidth: 1000)
        let pageHeight = 1000 * 792.0 / 612.0

        #expect(canvas.pageFrames[1].minY == pageHeight + ScoreVideoCanvas.pageGap)
        let rect = canvas.rect(for: region(3, page: 1, start: 0, end: 1, y: 0.5))
        #expect(rect?.minX == 100)
        #expect(rect?.minY == pageHeight + ScoreVideoCanvas.pageGap + pageHeight * 0.5)
        #expect(canvas.rect(for: region(3, page: 5, start: 0, end: 1)) == nil)
    }

    @Test func scrollPathHitsEveryBarlineOnTimeAndNeverMovesBack() {
        // Measures of different widths and lengths along one line.
        let timeline = ScoreVideoTimeline(regions: [
            region(0, page: 0, start: 0, end: 2),
            region(1, page: 0, start: 2, end: 3),
            region(2, page: 0, start: 3, end: 6)
        ])
        let rects = [CGRect(x: 100, y: 0, width: 200, height: 50),
                     CGRect(x: 300, y: 0, width: 50, height: 50),
                     CGRect(x: 350, y: 0, width: 300, height: 50)]
        let path = ScoreVideoScrollPath(timeline: timeline, rects: rects)

        #expect(path.segments.count == 1)
        #expect(path.x(at: 0) == 100)
        #expect(path.x(at: 2) == 300)
        #expect(path.x(at: 3) == 350)
        #expect(path.x(at: 6) == 650)
        #expect(path.x(at: 60) == 650)
        var previous = path.x(at: 0)
        for step in 1...600 {
            let x = path.x(at: Double(step) / 100)
            #expect(x >= previous)
            previous = x
        }
    }

    @Test func scrollPathJumpsBackAtARepeat() {
        let timeline = ScoreVideoTimeline(regions: [
            region(0, page: 0, start: 0, end: 2),
            region(1, page: 0, start: 2, end: 4),
            region(0, page: 0, start: 4, end: 6)
        ])
        let rects = [CGRect(x: 100, y: 0, width: 200, height: 50),
                     CGRect(x: 300, y: 0, width: 200, height: 50),
                     CGRect(x: 100, y: 0, width: 200, height: 50)]
        let path = ScoreVideoScrollPath(timeline: timeline, rects: rects)

        #expect(path.segments.count == 2)
        #expect(path.x(at: 3.999) > 490)
        #expect(path.x(at: 4) == 100)
        #expect(path.x(at: 5) > 100 && path.x(at: 5) < 300)
    }

    @Test func scrollPathFollowsNotePointsAndSplitsAtRepeats() {
        let points = [
            ScorePlaybackBeatPoint(pageIndex: 0, timeSeconds: 0, normalizedX: 0.10, startsSegment: true),
            ScorePlaybackBeatPoint(pageIndex: 0, timeSeconds: 1, normalizedX: 0.12, startsSegment: false),
            ScorePlaybackBeatPoint(pageIndex: 0, timeSeconds: 1, normalizedX: 0.13, startsSegment: false),
            ScorePlaybackBeatPoint(pageIndex: 0, timeSeconds: 3, normalizedX: 0.30, startsSegment: false),
            ScorePlaybackBeatPoint(pageIndex: 0, timeSeconds: 4, normalizedX: 0.40, startsSegment: false),
            ScorePlaybackBeatPoint(pageIndex: 0, timeSeconds: 4, normalizedX: 0.10, startsSegment: true),
            ScorePlaybackBeatPoint(pageIndex: 0, timeSeconds: 6, normalizedX: 0.40, startsSegment: false)
        ]
        let path = ScoreVideoScrollPath(beatPoints: points, lineWidth: 1000)

        #expect(path.segments.count == 2)
        #expect(path.segments[0].count == 4)
        #expect(path.x(at: 0) == 100)
        #expect(path.x(at: 1) == 120)
        #expect(path.x(at: 3) == 300)
        #expect(path.x(at: 3.999) > 390)
        #expect(path.x(at: 4) == 100)
        #expect(path.x(at: 6) == 400)
    }

    @Test func cameraSettlesOnTheTargetWithoutOvershooting() {
        var camera = ScoreVideoCamera(position: 0)
        var maximum: CGFloat = 0
        for _ in 0..<60 {
            camera.step(toward: 100, deltaTime: 1.0 / 30)
            maximum = max(maximum, camera.position)
        }

        #expect(maximum <= 100.0001)
        #expect(abs(camera.position - 100) < 1)
    }
}
