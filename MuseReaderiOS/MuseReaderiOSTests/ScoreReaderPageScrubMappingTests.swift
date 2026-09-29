import CoreGraphics
import Testing
@testable import MuseReaderiOS

struct ScoreReaderPageScrubMappingTests {
    @Test func trackPositionsSpanTheWholeScore() {
        let mapping = ScoreReaderPageScrubMapping(pageCount: 65, trackWidth: 256)

        #expect(mapping.pageIndex(atX: 0) == 0)
        #expect(mapping.pageIndex(atX: 256) == 64)
        #expect(mapping.pageIndex(atX: 236) == 59)
    }

    @Test func knobSitsOnTheSamePositionItSelects() {
        let mapping = ScoreReaderPageScrubMapping(pageCount: 65, trackWidth: 256)

        for pageIndex in [0, 1, 31, 59, 64] {
            #expect(mapping.pageIndex(atX: mapping.x(forPageIndex: pageIndex)) == pageIndex)
        }
    }

    @Test func positionsOutsideTheTrackClampToTheEnds() {
        let mapping = ScoreReaderPageScrubMapping(pageCount: 10, trackWidth: 120)

        #expect(mapping.pageIndex(atX: -40) == 0)
        #expect(mapping.pageIndex(atX: 500) == 9)
        #expect(ScoreReaderPageScrubMapping(pageCount: 1, trackWidth: 120).pageIndex(atX: 80) == 0)
    }
}
