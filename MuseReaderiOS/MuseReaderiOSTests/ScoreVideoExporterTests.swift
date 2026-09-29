import CoreGraphics
import Testing
@testable import MuseReaderiOS

struct ScoreVideoExporterTests {
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
