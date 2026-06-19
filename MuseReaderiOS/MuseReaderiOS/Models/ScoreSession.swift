//
//  ScoreSession.swift
//  MuseReaderiOS
//
//

import Foundation
import UIKit

struct ScorePackagePreviewAsset: Identifiable, Sendable, Equatable {
    let path: String
    let imageData: Data

    var id: String {
        path
    }
}

enum ScorePageAssetSource: String, Sendable, Equatable {
    case embeddedPackagePreview
    case liveMuseScoreRenderer

    var displayName: String {
        switch self {
        case .embeddedPackagePreview:
            return "Embedded Package Preview"
        case .liveMuseScoreRenderer:
            return "MuseScore Render Core"
        }
    }
}

enum ScoreRenderPipeline: Sendable, Equatable {
    case liveMuseScoreRenderer
    case embeddedPackagePreview(reason: String?)
    case waitingForLiveRenderer(reason: String)

    var summaryLabel: String {
        switch self {
        case .liveMuseScoreRenderer:
            return "Live MuseScore Renderer"
        case .embeddedPackagePreview:
            return "Embedded Package Preview"
        case .waitingForLiveRenderer:
            return "Live MuseScore Renderer Pending"
        }
    }

    var detailText: String {
        switch self {
        case .liveMuseScoreRenderer:
            return "This session is backed by the MuseScore engraving engine. The reader now requests pages on demand from a live score session so playback and editing can attach to the same open document later."
        case .embeddedPackagePreview(let reason):
            return reason ?? "This session is showing preview assets stored inside the MuseScore package. The reader shell is already session-oriented, so a live engraving renderer can replace these previews later without changing the app structure."
        case .waitingForLiveRenderer(let reason):
            return reason
        }
    }
}

struct ScoreSessionCapabilities: Sendable, Equatable {
    let supportsPackageInspection: Bool
    let supportsEmbeddedPreviews: Bool
    let supportsLivePageRendering: Bool
    let supportsPlayback: Bool
    let supportsEditing: Bool
}

struct ScorePage: Identifiable, Sendable, Equatable {
    let index: Int
    let title: String
    let sourcePath: String
    let source: ScorePageAssetSource
    let imageData: Data

    var id: String {
        "\(index)-\(sourcePath)"
    }

    var image: UIImage? {
        UIImage(data: imageData)
    }

    var sourceName: String {
        sourcePath.split(separator: "/").last.map(String.init) ?? sourcePath
    }
}

enum ScorePlaybackStatus: String, Sendable, Equatable {
    case unavailable
    case stopped
    case paused
    case playing
}

struct ScorePlaybackState: Sendable, Equatable {
    let isAvailable: Bool
    let status: ScorePlaybackStatus
    let positionSeconds: TimeInterval
    let durationSeconds: TimeInterval

    static let unavailable = ScorePlaybackState(
        isAvailable: false,
        status: .unavailable,
        positionSeconds: 0,
        durationSeconds: 0
    )

    var isPlaying: Bool {
        status == .playing
    }

    var currentTimeLabel: String {
        Self.formatTime(positionSeconds)
    }

    var durationLabel: String {
        Self.formatTime(durationSeconds)
    }

    var progress: Double {
        guard durationSeconds > 0 else {
            return 0
        }

        return min(max(positionSeconds / durationSeconds, 0), 1)
    }

    private static func formatTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(Int(seconds.rounded(.down)), 0)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

struct ScoreNormalizedRect: Sendable, Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    var center: CGPoint {
        CGPoint(x: x + width / 2, y: y + height / 2)
    }
}

struct ScorePlaybackMeasureRegion: Identifiable, Sendable, Equatable {
    let measureIndex: Int
    let pageIndex: Int
    let startTimeSeconds: TimeInterval
    let endTimeSeconds: TimeInterval
    let normalizedRect: ScoreNormalizedRect

    var id: String {
        "\(measureIndex)-\(pageIndex)-\(Int((startTimeSeconds * 1000).rounded()))"
    }
}

struct ScorePlaybackMeasureHighlight: Sendable, Equatable {
    let pageIndex: Int
    let normalizedRect: ScoreNormalizedRect
    let progress: Double
}

struct ScoreNoteEntryPreview: Sendable, Equatable {
    let pageIndex: Int
    let overlayNormalizedRect: ScoreNormalizedRect
    let overlayImageData: Data
}

enum ScoreNoteDuration: Int, CaseIterable, Identifiable, Sendable {
    case whole = 1
    case half = 2
    case quarter = 4
    case eighth = 8
    case sixteenth = 16

    var id: Int {
        rawValue
    }

    var shortLabel: String {
        switch self {
        case .whole:
            return "1"
        case .half:
            return "1/2"
        case .quarter:
            return "1/4"
        case .eighth:
            return "1/8"
        case .sixteenth:
            return "1/16"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .whole:
            return "Whole note"
        case .half:
            return "Half note"
        case .quarter:
            return "Quarter note"
        case .eighth:
            return "Eighth note"
        case .sixteenth:
            return "Sixteenth note"
        }
    }
}

enum ScoreSelectedElementKind: Sendable, Equatable {
    case note
    case rest
    case bar
    case measure
    case timeSignature
    case keySignature
    case tempo
    case expressionSpanner
    case dynamic
    case text
    case chordText
    case other
}

enum ScoreAccidentalKind: Int, Sendable, Equatable {
    case natural = 0
    case sharp = 1
    case flat = 2
}

struct ScorePickupMeasureState: Sendable, Equatable {
    let isPickup: Bool
    let actualNumerator: Int
    let actualDenominator: Int
    let nominalNumerator: Int
    let nominalDenominator: Int
}

struct ScorePickupEditorContext: Identifiable, Sendable, Equatable {
    let id = UUID()
    let isExistingPickup: Bool
    let createsNewMeasure: Bool
    let nominalNumerator: Int
    let nominalDenominator: Int
    let currentNumerator: Int
    let currentDenominator: Int
}

struct ScoreSelectedElement: Sendable, Equatable {
    let pageIndex: Int
    let kind: ScoreSelectedElementKind
    let isSingleMeasure: Bool
    let isFirstMeasure: Bool
    let isPickupMeasure: Bool
    let pickupNominalNumerator: Int
    let pickupNominalDenominator: Int
    let supportsBowingArticulations: Bool
    let canChangePitch: Bool
    let canFillWithSlashes: Bool
    let isDotted: Bool
    let isTiedForward: Bool
    let textContent: String?
    let textKind: String?
    let midiPitch: Int?
    let chordMidiPitches: [Int]
    let playbackBank: Int
    let playbackProgram: Int
    let playbackSetupData: String
    let duration: ScoreNoteDuration
    let accidentalKind: ScoreAccidentalKind?
    let diatonicStep: Int?
    let currentKey: Int
    let normalizedRect: ScoreNormalizedRect
    let actionRect: ScoreNormalizedRect
    let startHandlePoint: CGPoint?
    let endHandlePoint: CGPoint?
    let attachmentPoint: CGPoint?
    let attachmentTargets: [CGPoint]
    let highlightRects: [ScoreNormalizedRect]
    let overlayNormalizedRect: ScoreNormalizedRect?
    let overlayImageData: Data?

    var pitchClass: Int? {
        guard let midiPitch else {
            return nil
        }

        let value = midiPitch % 12
        return value >= 0 ? value : value + 12
    }

    var octave: Int? {
        guard let midiPitch else {
            return nil
        }

        return (midiPitch / 12) - 1
    }

    func pitchClass(for accidentalKind: ScoreAccidentalKind) -> Int? {
        let naturalPitchClasses = [0, 2, 4, 5, 7, 9, 11]
        let targetStep: Int
        if let diatonicStep, (0...6).contains(diatonicStep) {
            targetStep = diatonicStep
        } else if let pitchClass {
            targetStep = nearestNaturalStep(for: pitchClass, in: naturalPitchClasses)
        } else {
            return nil
        }

        let accidentalOffset: Int
        switch accidentalKind {
        case .natural:
            accidentalOffset = 0
        case .sharp:
            accidentalOffset = 1
        case .flat:
            accidentalOffset = -1
        }

        let rawPitchClass = naturalPitchClasses[targetStep] + accidentalOffset
        return (rawPitchClass + 12) % 12
    }

    func visibleSharpPitchClass(stepDirection: Int = 1) -> Int? {
        guard let pitchClass else {
            return nil
        }

        let naturalPitchClasses = [0, 2, 4, 5, 7, 9, 11]
        let currentStep = diatonicStep.flatMap { (0...6).contains($0) ? $0 : nil }
            ?? nearestNaturalStep(for: pitchClass, in: naturalPitchClasses)
        let candidateSteps = [currentStep, (currentStep + 1) % 7, (currentStep + 6) % 7]
        for step in candidateSteps {
            let sharpPitchClass = (naturalPitchClasses[step] + 1) % 12
            if sharpPitchClass != pitchClass {
                return sharpPitchClass
            }
        }

        return (pitchClass + stepDirection + 12) % 12
    }

    func visibleFlatPitchClass(stepDirection: Int = -1) -> Int? {
        guard let pitchClass else {
            return nil
        }

        let naturalPitchClasses = [0, 2, 4, 5, 7, 9, 11]
        let currentStep = diatonicStep.flatMap { (0...6).contains($0) ? $0 : nil }
            ?? nearestNaturalStep(for: pitchClass, in: naturalPitchClasses)
        let candidateSteps = [currentStep, (currentStep + 6) % 7, (currentStep + 1) % 7]
        for step in candidateSteps {
            let flatPitchClass = (naturalPitchClasses[step] + 11) % 12
            if flatPitchClass != pitchClass {
                return flatPitchClass
            }
        }

        return (pitchClass + stepDirection + 12) % 12
    }

    private func nearestNaturalStep(for pitchClass: Int, in naturalPitchClasses: [Int]) -> Int {
        var bestStep = 0
        var bestDistance = Int.max
        for (step, naturalPitchClass) in naturalPitchClasses.enumerated() {
            let upwardDistance = (pitchClass - naturalPitchClass + 12) % 12
            let distance = min(upwardDistance, 12 - upwardDistance)
            if distance < bestDistance {
                bestDistance = distance
                bestStep = step
            }
        }

        return bestStep
    }
}

enum ScoreEditRefreshScope: String, Sendable, Equatable {
    case local
    case nearby
    case all
}

struct ScoreEditingState: Sendable, Equatable {
    var selection: ScoreSelectedElement?
    var noteInputEnabled: Bool
    var noteInputInsertsRests: Bool
    var noteInputIsDotted: Bool
    var duration: ScoreNoteDuration
    var currentVoice: Int
    var canUndo: Bool
    var canRedo: Bool
    var activeStaffIsPercussion: Bool
    var createMultiMeasureRests: Bool
    var hideEmptyStaves: Bool
    var refreshScope: ScoreEditRefreshScope
    var pageCount: Int?

    static let inactive = ScoreEditingState(
        selection: nil,
        noteInputEnabled: false,
        noteInputInsertsRests: false,
        noteInputIsDotted: false,
        duration: .quarter,
        currentVoice: 0,
        canUndo: false,
        canRedo: false,
        activeStaffIsPercussion: false,
        createMultiMeasureRests: false,
        hideEmptyStaves: false,
        refreshScope: .local,
        pageCount: nil
    )

    var canDeleteSelection: Bool {
        selection != nil
    }

    var canChangePitch: Bool {
        selection?.canChangePitch ?? false
    }
}

struct ScoreEditableMetadata: Sendable, Equatable {
    var title: String
    var subtitle: String
    var composer: String
    var lyricist: String
    var arranger: String

    init(title: String = "", subtitle: String = "", composer: String = "", lyricist: String = "", arranger: String = "") {
        self.title = title
        self.subtitle = subtitle
        self.composer = composer
        self.lyricist = lyricist
        self.arranger = arranger
    }

    init(document: ScoreDocument) {
        self.init(
            title: document.title ?? "",
            subtitle: document.subtitle ?? "",
            composer: document.composer ?? "",
            lyricist: document.lyricist ?? "",
            arranger: document.arranger ?? ""
        )
    }
}

struct ScoreCorruptionIssue: Identifiable, Sendable, Equatable {
    let index: Int
    let measureNumber: Int
    let staffIndex: Int
    let voice: Int
    let repairable: Bool
    let kind: String
    let message: String

    var id: Int {
        index
    }

    var title: String {
        var parts = ["Measure \(measureNumber)", "Staff \(staffIndex + 1)"]
        if voice > 0 {
            parts.append("Voice \(voice)")
        }
        return parts.joined(separator: " · ")
    }
}

struct ScoreCorruptionReport: Sendable, Equatable {
    let isCorrupted: Bool
    let details: String
    let issues: [ScoreCorruptionIssue]

    nonisolated static let clean = ScoreCorruptionReport(isCorrupted: false, details: "", issues: [])
}

struct ScoreSession: Identifiable, Sendable {
    let document: ScoreDocument
    let previewPages: [ScorePage]
    let renderPipeline: ScoreRenderPipeline
    let capabilities: ScoreSessionCapabilities
    let liveRenderSession: LiveScoreRenderSession?
    let corruptionReport: ScoreCorruptionReport
    let totalPageCount: Int

    var id: String {
        document.id
    }

    var previewPageCount: Int {
        previewPages.count
    }

    var pageCount: Int {
        totalPageCount
    }

    var coverPage: ScorePage? {
        previewPages.first
    }

    func replacingCorruptionReport(_ report: ScoreCorruptionReport) -> ScoreSession {
        ScoreSession(
            document: document,
            previewPages: previewPages,
            renderPipeline: renderPipeline,
            capabilities: capabilities,
            liveRenderSession: liveRenderSession,
            corruptionReport: report,
            totalPageCount: totalPageCount
        )
    }
}
