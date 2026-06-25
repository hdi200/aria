//
//  ScoreReaderState.swift
//  MuseReaderiOS
//
//

import Combine
import Foundation
import CoreGraphics

@MainActor
final class ScoreReaderState: ObservableObject {
    let session: ScoreSession

    @Published var selectedPageIndex: Int
    @Published var cachedPagesByIndex: [Int: ScorePage]
    @Published var loadingPageIndices: Set<Int> = []
    @Published var pageErrorMessages: [Int: String] = [:]
    @Published var playbackState: ScorePlaybackState
    @Published var playbackErrorMessage: String?
    @Published var isPlaybackActionInFlight = false
    @Published var playbackPreparationMessage: String?
    @Published var playbackMeasureHighlight: ScorePlaybackMeasureHighlight?
    @Published var metronomeEnabled = false
    @Published var editingState: ScoreEditingState = .inactive
    @Published var measureRangePreviewSelection: ScoreSelectedElement?
    @Published var editingErrorMessage: String?
    @Published var isEditingActionInFlight = false
    @Published var pendingPitchClass: Int?
    @Published var pendingMIDIPitch: Int?
    @Published var pendingPreferFlats = false
    @Published var pendingAccidentalKind: ScoreAccidentalKind?
    @Published var stackedChordInputEnabled = false
    @Published var noteEntryPreview: ScoreNoteEntryPreview?
    @Published var activeNotationAutoScrollRevision = 0
    @Published var activePageCount: Int
    @Published var concertPitchEnabled = false
    @Published var hasConcertPitchRelevantTransposition = false
    @Published var corruptionReport: ScoreCorruptionReport
    @Published var pickupEditorContext: ScorePickupEditorContext?

    let preferredDPI: Int
    let playbackController: NativePlaybackController?
    let notePreviewController = NativeNotePreviewController()
    let midiInputController = MIDIInputController()
    let prefetchDistance = 1
    let playbackMonitorInterval = Duration.milliseconds(25)
    let midiChordReleaseSettleDelay = Duration.milliseconds(35)
    let midiChordMaxHoldDelay = Duration.milliseconds(700)
    var loadTasks: [Int: Task<Void, Never>] = [:]
    var staleLivePageIndices: Set<Int> = []
    var playbackMonitorTask: Task<Void, Never>?
    var playbackContextTask: Task<Void, Never>?
    var playbackWarmupTask: Task<Void, Error>?
    var autosaveTask: Task<Void, Never>?
    var deferredPagePrefetchTask: Task<Void, Never>?
    var editingStateTask: Task<Void, Never>?
    var noteEntryPreviewTask: Task<Void, Never>?
    var measureRangePreviewTask: Task<Void, Never>?
    var editingStateRevision = 0
    var noteEntryPreviewRevision = 0
    var measureRangePreviewRevision = 0
    var autosaveRevision = 0
    var hasUnsavedAutosaveChanges = false
    var playbackWarmupRevision = 0
    var playbackMeasureRegions: [ScorePlaybackMeasureRegion] = []
    var playbackWasExplicitlyStopped = false
    var activeScorePartIndex: Int?
    var pendingScorePartIndex: Int?
    var partSelectionRevision = 0
    var partSelectionTask: Task<Void, Never>?
    var partSelectionErrorMessage: String?
    var hasContinuousNoteInputCursor = false
    var noteInputWasActivatedByPencil = false
    var shouldEditSelectedPitchBeforeContinuingKeyboardInput = false
    var lastKeyboardInputCanReceiveAccidental = false
    var activeMIDIPitches: Set<Int> = []
    var pendingMIDIChordPitches: Set<Int> = []
    var midiChordCaptureTask: Task<Void, Never>?

    // Tracks the most recent Pencil aim (hover/fine-tune) so a note-entry tap can
    // commit exactly where the live preview ghost was shown, rather than the tap's
    // lift point, which drifts a few points as the tip comes down.
    var lastPencilAimNormalizedPoint: CGPoint?
    var lastPencilAimPageIndex: Int?
    var lastPencilAimTimestamp: Date?

    var pageCount: Int {
        activePageCount
    }

    var pageIndices: [Int] {
        Array(0..<pageCount)
    }

    var currentPage: ScorePage? {
        cachedPagesByIndex[selectedPageIndex]
    }

    var currentPageLabel: String {
        guard pageCount > 0 else {
            return "Reader Unavailable"
        }

        return "Page \(selectedPageIndex + 1) of \(pageCount)"
    }

    var currentSourceName: String {
        currentPage?.sourceName ?? session.renderPipeline.summaryLabel
    }

    var supportsEditing: Bool {
        session.capabilities.supportsEditing && !corruptionReport.isCorrupted
    }

    var isRepairingCorruption: Bool {
        session.liveRenderSession != nil && corruptionReport.isCorrupted
    }

    init(session: ScoreSession, initialPageIndex: Int, preferredDPI: Int = 144) {
        self.session = session
        self.preferredDPI = preferredDPI
        self.activePageCount = session.pageCount
        self.selectedPageIndex = ScoreReaderState.boundedIndex(initialPageIndex, pageCount: session.pageCount)
        self.cachedPagesByIndex = Dictionary(uniqueKeysWithValues: session.previewPages.map { ($0.index, $0) })
        self.corruptionReport = session.corruptionReport
        self.playbackController = session.capabilities.supportsPlayback ? NativePlaybackController() : nil
        self.playbackState = session.capabilities.supportsPlayback
            ? ScorePlaybackState(isAvailable: true, status: .stopped, positionSeconds: 0, durationSeconds: 0)
            : .unavailable
        midiInputController.noteOnHandler = { [weak self] midiPitch in
            Task { @MainActor [weak self] in
                self?.handleMIDINoteOn(midiPitch)
            }
        }
        midiInputController.noteOffHandler = { [weak self] midiPitch in
            Task { @MainActor [weak self] in
                self?.handleMIDINoteOff(midiPitch)
            }
        }
    }

    deinit {
        loadTasks.values.forEach { $0.cancel() }
        playbackMonitorTask?.cancel()
        playbackContextTask?.cancel()
        playbackWarmupTask?.cancel()
        partSelectionTask?.cancel()
        autosaveTask?.cancel()
        deferredPagePrefetchTask?.cancel()
        editingStateTask?.cancel()
        noteEntryPreviewTask?.cancel()
        measureRangePreviewTask?.cancel()
        midiChordCaptureTask?.cancel()
    }


    func page(at index: Int) -> ScorePage? {
        cachedPagesByIndex[index]
    }

    func isLoadingPage(_ index: Int) -> Bool {
        loadingPageIndices.contains(index)
    }

    func pageErrorMessage(for index: Int) -> String? {
        pageErrorMessages[index]
    }

    func playbackMeasureHighlight(for pageIndex: Int) -> ScorePlaybackMeasureHighlight? {
        guard playbackMeasureHighlight?.pageIndex == pageIndex else {
            return nil
        }

        return playbackMeasureHighlight
    }

    func noteEntryPreview(for pageIndex: Int) -> ScoreNoteEntryPreview? {
        guard noteEntryPreview?.pageIndex == pageIndex else {
            return nil
        }

        return noteEntryPreview
    }

    func selectedElement(for pageIndex: Int) -> ScoreSelectedElement? {
        if measureRangePreviewSelection?.pageIndex == pageIndex {
            return measureRangePreviewSelection
        }

        guard editingState.selection?.pageIndex == pageIndex else {
            return nil
        }

        return editingState.selection
    }
}
