import CoreGraphics
import Testing
@testable import MuseReaderiOS

struct DuoPosePolicyTests {
    private let wideWindow = CGSize(width: 900, height: 700)
    private let tallWindow = CGSize(width: 700, height: 900)

    @Test func noHingeIsNotADuo() {
        #expect(DuoPosePolicy.pose(hingeStatus: nil, foldFrame: nil, windowSize: wideWindow) == .notDuo)
    }

    @Test func closedAndOpenFollowTheHinge() {
        #expect(DuoPosePolicy.pose(hingeStatus: .closed, foldFrame: nil, windowSize: wideWindow) == .closed)
        #expect(DuoPosePolicy.pose(hingeStatus: .fullyOpen, foldFrame: nil, windowSize: wideWindow) == .open)
        #expect(DuoPosePolicy.pose(hingeStatus: .unknown, foldFrame: nil, windowSize: wideWindow) == .open)
    }

    @Test func halfOpenUsesTheFoldDirection() {
        let verticalFold = CGRect(x: 434, y: 0, width: 32, height: 700)
        let horizontalFold = CGRect(x: 0, y: 434, width: 700, height: 32)

        // The fold's shape wins over the window's.
        #expect(DuoPosePolicy.pose(hingeStatus: .partiallyOpen, foldFrame: verticalFold, windowSize: tallWindow) == .book)
        #expect(DuoPosePolicy.pose(hingeStatus: .partiallyOpen, foldFrame: horizontalFold, windowSize: wideWindow) == .stand)
    }

    @Test func halfOpenWithoutAFoldUsesTheWindowShape() {
        #expect(DuoPosePolicy.pose(hingeStatus: .partiallyOpen, foldFrame: nil, windowSize: wideWindow) == .book)
        #expect(DuoPosePolicy.pose(hingeStatus: .partiallyOpen, foldFrame: .zero, windowSize: tallWindow) == .stand)
    }

    @Test func simulatedFoldSitsInTheMiddle() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)

        #expect(DuoPosePolicy.simulatedFoldFrame(for: .book, windowBounds: bounds) == CGRect(x: 384, y: 0, width: 32, height: 600))
        #expect(DuoPosePolicy.simulatedFoldFrame(for: .stand, windowBounds: bounds) == CGRect(x: 0, y: 284, width: 800, height: 32))
        #expect(DuoPosePolicy.simulatedFoldFrame(for: .open, windowBounds: bounds) == nil)
    }

    @Test func fakeSwitchCyclesThroughEveryPose() {
        var pose = DuoPose.closed
        var visited: [DuoPose] = []
        for _ in 0..<4 {
            pose = DuoPosePolicy.nextSimulatedPose(after: pose)
            visited.append(pose)
        }
        #expect(visited == [.open, .book, .stand, .closed])
    }
}
