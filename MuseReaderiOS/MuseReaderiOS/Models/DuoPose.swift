//
//  DuoPose.swift
//  MuseReaderiOS
//

import Observation
#if os(Android)
// Skip's Observation bridge, so Android's UI redraws when these properties change.
import SkipFuse
#endif
import CoreGraphics
import Foundation

/// How an iPhone Duo is being held. Every other device reports `.notDuo`, so
/// Duo-only layouts never change how Aria looks anywhere else.
enum DuoPose: String, CaseIterable {
    case notDuo
    /// Folded shut, with Aria on the outer display.
    case closed
    /// Unfolded flat on the inner display.
    case open
    /// Half open with the fold running top to bottom, held like a book.
    case book
    /// Half open with the fold running side to side, standing like a laptop.
    case stand

    var isDuo: Bool {
        self != .notDuo
    }

    var title: String {
        switch self {
        case .notDuo:
            return "Not a Duo"
        case .closed:
            return "Closed"
        case .open:
            return "Open"
        case .book:
            return "Book"
        case .stand:
            return "Stand"
        }
    }
}

/// The hinge reading, kept separate from UIKit's type so the pose rules build
/// on every iOS version and on Android.
enum DuoHingeStatus: Equatable {
    case unknown
    case closed
    case partiallyOpen
    case fullyOpen
}

struct DuoPoseState: Equatable {
    var pose = DuoPose.notDuo
    /// Where the fold is while the device is half open, in window coordinates.
    var foldFrame: CGRect?
    /// True when the pose comes from the `AriaFakeDuoPose` launch argument.
    var isSimulated = false
}

enum DuoPosePolicy {
    /// The width of the stand-in fold drawn by the fake-pose switch.
    static let simulatedFoldThickness: CGFloat = 32

    /// A nil hinge status means the device has no hinge.
    static func pose(hingeStatus: DuoHingeStatus?, foldFrame: CGRect?, windowSize: CGSize) -> DuoPose {
        guard let hingeStatus else {
            return .notDuo
        }

        switch hingeStatus {
        case .closed:
            return .closed
        case .fullyOpen, .unknown:
            return .open
        case .partiallyOpen:
            // The fold's own shape is the most reliable guide. Without it, a
            // wide window is held like a book and a tall one stands like a laptop.
            if let foldFrame, !foldFrame.isEmpty {
                return foldFrame.height > foldFrame.width ? .book : .stand
            }
            return windowSize.width >= windowSize.height ? .book : .stand
        }
    }

    static func simulatedFoldFrame(for pose: DuoPose, windowBounds: CGRect) -> CGRect? {
        let thickness = simulatedFoldThickness
        switch pose {
        case .book:
            return CGRect(x: windowBounds.midX - thickness / 2, y: windowBounds.minY,
                          width: thickness, height: windowBounds.height)
        case .stand:
            return CGRect(x: windowBounds.minX, y: windowBounds.midY - thickness / 2,
                          width: windowBounds.width, height: thickness)
        case .notDuo, .closed, .open:
            return nil
        }
    }

    /// The fake-pose switch's cycle order.
    static func nextSimulatedPose(after pose: DuoPose) -> DuoPose {
        switch pose {
        case .notDuo, .stand:
            return .closed
        case .closed:
            return .open
        case .open:
            return .book
        case .book:
            return .stand
        }
    }
}

/// The app-wide Duo pose. A shared instance rather than an environment value,
/// because the reader is a full-screen cover outside the library's hierarchy.
///
/// To try Duo layouts on any simulator or device, launch Aria with
/// `-AriaFakeDuoPose closed|open|book|stand`, for example
/// `xcrun simctl launch booted com.hdi200.ariascore -AriaFakeDuoPose book`.
/// A small switch on screen then cycles through the poses.
@MainActor
@Observable
final class DuoPoseMonitor {
    static let shared = DuoPoseMonitor()

    static let fakePoseArgumentKey = "AriaFakeDuoPose"

    private(set) var state: DuoPoseState
    @ObservationIgnored private var hasReceivedHingeReading = false
    @ObservationIgnored private var pendingPoseTask: Task<Void, Never>?
    @ObservationIgnored private var lastWindowBounds = CGRect.zero

    /// How long a new pose must hold before layouts switch, so a hinge moving
    /// through an angle doesn't flip them back and forth.
    private let settleDelay = Duration.milliseconds(300)

    init(userDefaults: UserDefaults = .standard) {
        if let rawPose = userDefaults.string(forKey: Self.fakePoseArgumentKey),
           let fakePose = DuoPose(rawValue: rawPose),
           fakePose.isDuo
        {
            state = DuoPoseState(pose: fakePose, foldFrame: nil, isSimulated: true)
            print("Aria Duo pose: simulating \(fakePose.rawValue)")
        } else {
            state = DuoPoseState()
        }
    }

    var pose: DuoPose {
        state.pose
    }

    var isSimulated: Bool {
        state.isSimulated
    }

    /// Takes a hinge reading. The first one applies at once; later pose changes
    /// wait for the hinge to settle.
    func receive(hingeStatus: DuoHingeStatus?, foldFrame: CGRect?, windowSize: CGSize) {
        guard !state.isSimulated else {
            return
        }

        let pose = DuoPosePolicy.pose(hingeStatus: hingeStatus, foldFrame: foldFrame, windowSize: windowSize)
        let resolved = DuoPoseState(pose: pose, foldFrame: foldFrame, isSimulated: false)

        guard hasReceivedHingeReading, pose != state.pose else {
            hasReceivedHingeReading = true
            pendingPoseTask?.cancel()
            pendingPoseTask = nil
            apply(resolved)
            return
        }

        pendingPoseTask?.cancel()
        pendingPoseTask = Task { [weak self, settleDelay] in
            try? await Task.sleep(for: settleDelay)
            guard !Task.isCancelled else {
                return
            }
            self?.apply(resolved)
        }
    }

    /// Keeps the fake fold centred in the window as it resizes or rotates.
    func updateSimulatedWindowBounds(_ windowBounds: CGRect) {
        guard state.isSimulated, windowBounds != lastWindowBounds else {
            return
        }
        lastWindowBounds = windowBounds
        state.foldFrame = DuoPosePolicy.simulatedFoldFrame(for: state.pose, windowBounds: windowBounds)
    }

    func cycleSimulatedPose() {
        guard state.isSimulated else {
            return
        }
        let pose = DuoPosePolicy.nextSimulatedPose(after: state.pose)
        apply(DuoPoseState(
            pose: pose,
            foldFrame: DuoPosePolicy.simulatedFoldFrame(for: pose, windowBounds: lastWindowBounds),
            isSimulated: true
        ))
    }

    private func apply(_ newState: DuoPoseState) {
        guard newState != state else {
            return
        }
        if newState.pose != state.pose {
            print("Aria Duo pose: \(state.pose.rawValue) -> \(newState.pose.rawValue)\(newState.isSimulated ? " (simulated)" : "")")
        }
        state = newState
    }
}
