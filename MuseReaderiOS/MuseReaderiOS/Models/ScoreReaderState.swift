//
//  ScoreReaderState.swift
//  MuseReaderiOS
//
//

import Observation
#if os(Android)
// Skip's Observation bridge, so Android's UI redraws when these properties change.
import SkipFuse
#endif
import Foundation
import UIKit

enum ScoreReaderInteractionMode: Equatable {
    case view
    case edit
    case leavingEdit

    var allowsScoreEditing: Bool {
        self == .edit
    }

    var isViewOnly: Bool {
        self != .edit
    }
}

enum ScoreReaderReadingStyle: String, CaseIterable, Codable {
    case pageTurn
    case continuousScroll

    var title: String {
        switch self {
        case .pageTurn:
            return "Page Turn"
        case .continuousScroll:
            return "Continuous Scroll"
        }
    }

    var systemImage: String {
        switch self {
        case .pageTurn:
            return "rectangle.portrait.on.rectangle.portrait"
        case .continuousScroll:
            return "scroll"
        }
    }
}

struct ScoreReaderRememberedState: Codable, Equatable {
    var pageIndex = 0
    var selectedPartID = "full-score"
    var zoomScale = 1.0
    var readingStyle = ScoreReaderReadingStyle.pageTurn
    var playbackFollowEnabled = true
    var viewTransposeKey: Int? = nil
}

struct ScoreReaderRememberedStateStore {
    private let userDefaults: UserDefaults
    private let keyPrefix = "ScoreReaderRememberedState."

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func state(for scoreID: String) -> ScoreReaderRememberedState {
        guard
            let data = userDefaults.data(forKey: keyPrefix + scoreID),
            let state = try? JSONDecoder().decode(ScoreReaderRememberedState.self, from: data)
        else {
            return ScoreReaderRememberedState()
        }
        return state
    }

    func save(_ state: ScoreReaderRememberedState, for scoreID: String) {
        guard let data = try? JSONEncoder().encode(state) else {
            return
        }
        userDefaults.set(data, forKey: keyPrefix + scoreID)
    }
}

@MainActor
@Observable
final class ScoreMixerLevelMonitor {
    private(set) var levels: [String: Float] = [:]

    func update(_ levels: [String: Float]) {
        self.levels = levels
    }
}

@MainActor
@Observable
final class ScoreReaderState {
    let session: ScoreSession

    var selectedPageIndex: Int
    var cachedPagesByIndex: [Int: ScorePage]
    var loadingPageIndices: Set<Int> = []
    var pageErrorMessages: [Int: String] = [:]
    #if os(Android)
    // Only status/capability/duration invalidate the reader. The accurate audio clock
    // remains available to logic, while its UI consumers observe the small child model.
    @ObservationIgnored private var currentPlaybackState: ScorePlaybackState = .unavailable
    let androidPlaybackVisualState = AndroidPlaybackVisualState()
    var playbackState: ScorePlaybackState {
        get {
            access(keyPath: \.playbackState)
            return currentPlaybackState
        }
        set {
            let old = currentPlaybackState
            if old.status != newValue.status || old.isAvailable != newValue.isAvailable
                || old.durationSeconds != newValue.durationSeconds {
                withMutation(keyPath: \.playbackState) { currentPlaybackState = newValue }
            } else {
                currentPlaybackState = newValue
            }
            androidPlaybackVisualState.publishClock(newValue)
        }
    }
    #else
    var playbackState: ScorePlaybackState
    #endif
    var playbackErrorMessage: String?
    var isPlaybackActionInFlight = false
    var playbackPreparationMessage: String?
    #if os(Android)
    @ObservationIgnored private var currentPlaybackHighlight: ScorePlaybackMeasureHighlight?
    var playbackMeasureHighlight: ScorePlaybackMeasureHighlight? {
        get {
            access(keyPath: \.playbackMeasureHighlight)
            return currentPlaybackHighlight
        }
        set {
            // Scrolling/following only depends on the measure rectangle, not progress.
            let old = currentPlaybackHighlight
            if old?.pageIndex != newValue?.pageIndex || old?.normalizedRect != newValue?.normalizedRect {
                withMutation(keyPath: \.playbackMeasureHighlight) { currentPlaybackHighlight = newValue }
            } else {
                currentPlaybackHighlight = newValue
            }
            androidPlaybackVisualState.publishHighlight(newValue)
        }
    }
    #else
    var playbackMeasureHighlight: ScorePlaybackMeasureHighlight?
    #endif
    var playFromHereTarget: ScorePlayFromHereTarget?
    var playbackLoopRange: ScorePlaybackLoopRange?
    var playbackLoopIsActive = false
    var mixerSettings = ScoreMixerSettings()
    /// Whether playback has a chord symbol channel, which the mixer then shows.
    var hasChordSymbolPlayback = false
    var metronomeEnabled = false
    var countInEnabled = UserDefaults.standard.bool(forKey: "ScoreReader.countInEnabled")
    var isCountingIn = false
    var countInBeatNumber: Int?
    var editingState: ScoreEditingState = .inactive
    var measureRangePreviewSelection: ScoreSelectedElement?
    var editingErrorMessage: String?
    var autosaveFailureMessage: String? {
        didSet {
            if autosaveFailureMessage == nil {
                saveNeedsChordSymbolRemovalApproval = false
            }
        }
    }
    /// The last save paused because every chord symbol was removed from the full score.
    var saveNeedsChordSymbolRemovalApproval = false
    var hasUnsavedAutosaveChanges = false
    var isEditingActionInFlight = false
    @ObservationIgnored var editingCommandQueue: [ScoreQueuedEditingCommand] = []
    @ObservationIgnored var editingCommandTask: Task<Void, Never>?
    @ObservationIgnored var queuedNoteInputIntent: ScoreNoteInputIntent?
    @ObservationIgnored var editingVisualRefreshDeferred = false
    @ObservationIgnored var pendingMIDIInputIntent: ScoreNoteInputIntent?
    @ObservationIgnored var pendingMIDIPreferFlats = false
    @ObservationIgnored var pendingMIDIReplacesSelection = false
    //! NOTE Live score info. session.document is a snapshot from when the score was opened,
    //! so it goes stale after metadata edits, on-page title edits, and undo/redo.
    var scoreMetadata: ScoreEditableMetadata
    var scoreMetadataRefreshRevision = 0
    private(set) var scoreParts: [ScorePart]
    var pendingPitchClass: Int?
    var pendingMIDIPitch: Int?
    var pendingPreferFlats = false
    var pendingAccidentalKind: ScoreAccidentalKind?
    var stackedChordInputEnabled = false
    var noteEntryPreview: ScoreNoteEntryPreview?
    var activeNotationAutoScrollRevision = 0
    var activePageCount: Int
    var concertPitchEnabled = false
    var hasConcertPitchRelevantTransposition = false
    var viewTransposeSourceKey: ScoreTransposeTargetKey?
    var viewTransposeKey: ScoreTransposeTargetKey?
    var isViewTransposeActionInFlight = false
    var viewTransposeErrorMessage: String?
    var corruptionReport: ScoreCorruptionReport
    var pickupEditorContext: ScorePickupEditorContext?
    private(set) var lastSelectedMeasureIndex: Int?
    private(set) var lastSelectedMeasureTick: Int64?
    private(set) var interactionMode: ScoreReaderInteractionMode
    var playbackFollowIsSuspended = false
    var playbackFollowEnabled = true

    let preferredDPI: Int
    let playbackController: NativePlaybackController?
    let mixerLevelMonitor = ScoreMixerLevelMonitor()
    let notePreviewController = NativeNotePreviewController()
    let midiInputController = MIDIInputController()
    let prefetchDistance = 1
    let playbackMonitorInterval = Duration.milliseconds(25)
    let midiChordReleaseSettleDelay = Duration.milliseconds(35)
    let midiChordMaxHoldDelay = Duration.milliseconds(700)
    @ObservationIgnored var loadTasks: [Int: Task<Void, Never>] = [:]
    var staleLivePageIndices: Set<Int> = []
    @ObservationIgnored var playbackMonitorTask: Task<Void, Never>?
    @ObservationIgnored var playbackContextTask: Task<Void, Never>?
    @ObservationIgnored var playbackWarmupTask: Task<Void, Error>?
    @ObservationIgnored var autosaveTask: Task<Void, Never>?
    @ObservationIgnored var backgroundRecoveryTask: Task<Void, Never>?
    @ObservationIgnored var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
    let recoveryStore = ScoreRecoveryStore()
    @ObservationIgnored var deferredPagePrefetchTask: Task<Void, Never>?
    @ObservationIgnored var editingStateTask: Task<Void, Never>?
    @ObservationIgnored var noteEntryPreviewTask: Task<Void, Never>?
    @ObservationIgnored var measureRangePreviewTask: Task<Void, Never>?
    var editingStateRevision = 0
    var noteEntryPreviewRevision = 0
    var measureRangePreviewRevision = 0
    var autosaveRevision = 0
    var playbackWarmupRevision = 0
    var playbackMeasureRegions: [ScorePlaybackMeasureRegion] = []
    var playbackWasExplicitlyStopped = false
    var pendingPlaybackSelectionStartPoint: CGPoint?
    var pendingPlaybackSelectionEndPoint: CGPoint?
    var pendingPlaybackSelectionPageIndex: Int?
    var activeScorePartIndex: Int?
    var pendingScorePartIndex: Int?
    var partSelectionRevision = 0
    @ObservationIgnored var partSelectionTask: Task<Void, Never>?
    var partSelectionErrorMessage: String?
    var hasContinuousNoteInputCursor = false
    var noteInputWasActivatedByPencil = false
    var shouldEditSelectedPitchBeforeContinuingKeyboardInput = false
    var lastKeyboardInputCanReceiveAccidental = false
    var activeMIDIPitches: Set<Int> = []
    var pendingMIDIChordPitches: Set<Int> = []
    @ObservationIgnored var midiChordCaptureTask: Task<Void, Never>?

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

    func updateScoreParts(_ parts: [ScorePart]) {
        guard scoreParts != parts else {
            return
        }
        scoreParts = parts
    }

    func updateLastSelectedMeasure(index: Int, tick: Int64) {
        lastSelectedMeasureIndex = index
        lastSelectedMeasureTick = tick
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

    var supportsPlayback: Bool {
        session.capabilities.supportsPlayback
    }

    var isEditingMode: Bool {
        interactionMode.allowsScoreEditing
    }

    var scoreTitle: String {
        scoreMetadata.title.trimmedToNil ?? session.document.displayName
    }

    var shouldFollowPlayback: Bool {
        playbackFollowEnabled && !playbackFollowIsSuspended
    }

    var isRepairingCorruption: Bool {
        session.liveRenderSession != nil && corruptionReport.isCorrupted
    }

    init(
        session: ScoreSession,
        initialPageIndex: Int,
        initialInteractionMode: ScoreReaderInteractionMode = .view,
        initialViewTransposeKey: Int? = nil,
        preferredDPI: Int = 144
    ) {
        self.session = session
        self.preferredDPI = preferredDPI
        self.interactionMode = session.capabilities.supportsEditing && !session.corruptionReport.isCorrupted
            ? initialInteractionMode
            : .view
        self.activePageCount = session.pageCount
        self.selectedPageIndex = ScoreReaderState.boundedIndex(initialPageIndex, pageCount: session.pageCount)
        self.scoreParts = session.document.parts
        self.scoreMetadata = ScoreEditableMetadata(document: session.document)
        self.cachedPagesByIndex = initialInteractionMode == .view && initialViewTransposeKey != nil
            ? [:]
            : Dictionary(uniqueKeysWithValues: session.previewPages.map { ($0.index, $0) })
        self.corruptionReport = session.corruptionReport
        self.playbackController = session.capabilities.supportsPlayback ? NativePlaybackController() : nil
        self.mixerSettings = ScoreMixerSettingsStore().load(scoreID: session.document.id)
        self.playbackState = session.capabilities.supportsPlayback
            ? ScorePlaybackState(isAvailable: true, status: .stopped, positionSeconds: 0, durationSeconds: 0)
            : .unavailable
        self.playbackController?.setMixerSettings(mixerSettings)
        self.playbackController?.setMeterLevelHandler { [weak self] levels in
            self?.mixerLevelMonitor.update(levels)
        }
        self.playbackController?.setStemIDsHandler { [weak self] stemIDs in
            let hasChordSymbols = stemIDs.contains(NativePlaybackController.chordSymbolsStemID)
            if self?.hasChordSymbolPlayback != hasChordSymbols {
                self?.hasChordSymbolPlayback = hasChordSymbols
            }
        }
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

    func enterEditMode() {
        guard
            supportsEditing,
            interactionMode == .view,
            let liveRenderSession = session.liveRenderSession,
            !isViewTransposeActionInFlight
        else {
            return
        }

        editingErrorMessage = nil
        clearPlaybackLoop()
        stopMIDIInput()
        isEditingActionInFlight = true
        Task { @MainActor [weak self] in
            defer {
                self?.isEditingActionInFlight = false
            }
            do {
                if self?.viewTransposeKey != self?.viewTransposeSourceKey {
                    let updatedPageCount = try await liveRenderSession.clearViewTranspose()
                    guard let self else {
                        return
                    }
                    self.viewTransposeKey = self.viewTransposeSourceKey
                    self.refreshAfterViewTranspose(pageCount: updatedPageCount, preparesPlayback: false)
                }
                self?.interactionMode = .edit
                var state = try await liveRenderSession.setNoteInputEnabled(false)
                state = try await liveRenderSession.clearSelection()
                self?.applyEditingState(state)
                self?.startMIDIInput()
            } catch {
                self?.interactionMode = .view
                self?.editingState = .inactive
                self?.stopMIDIInput()
                self?.editingErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func suspendPlaybackFollow() {
        guard interactionMode == .view, playbackFollowEnabled, playbackState.status == .playing else {
            return
        }
        playbackFollowIsSuspended = true
    }

    func resumePlaybackFollow() {
        playbackFollowIsSuspended = false
        if let playbackMeasureHighlight {
            updateSelection(to: playbackMeasureHighlight.pageIndex)
        }
    }

    func prepareInitialInteractionMode() async {
        guard supportsEditing, let liveRenderSession = session.liveRenderSession else {
            interactionMode = .view
            editingState = .inactive
            stopMIDIInput()
            return
        }

        if interactionMode == .edit {
            stopMIDIInput()
            do {
                var state = try await liveRenderSession.setNoteInputEnabled(false)
                state = try await liveRenderSession.clearSelection()
                applyEditingState(state)
                startMIDIInput()
            } catch {
                interactionMode = .view
                editingState = .inactive
                stopMIDIInput()
                editingErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            return
        }

        stopMIDIInput()
        do {
            var state = try await liveRenderSession.currentEditingState()
            if state.noteInputEnabled {
                state = try await liveRenderSession.setNoteInputEnabled(false)
            }
            state = try await liveRenderSession.clearSelection()
            applyEditingState(state)
        } catch {
            editingState = .inactive
            editingErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    @discardableResult
    func finishEditingAndEnterViewMode() async -> Bool {
        if isEditingMode { stopMIDIInput() }
        await editingCommandTask?.value
        guard supportsEditing else {
            interactionMode = .view
            return true
        }
        guard interactionMode == .edit, !isEditingActionInFlight else {
            return interactionMode == .view
        }

        interactionMode = .leavingEdit
        stopMIDIInput()
        clearMeasureRangePreview()
        clearPencilAimForModeTransition()
        noteEntryPreviewTask?.cancel()
        noteEntryPreviewTask = nil
        noteEntryPreview = nil
        pendingAccidentalKind = nil
        pendingPitchClass = nil
        pendingMIDIPitch = nil
        stackedChordInputEnabled = false
        pickupEditorContext = nil

        var transitionSucceeded = true
        if let liveRenderSession = session.liveRenderSession {
            do {
                if editingState.noteInputEnabled || hasContinuousNoteInputCursor {
                    let state = try await liveRenderSession.setNoteInputEnabled(false)
                    applyEditingState(state)
                }
                let state = try await liveRenderSession.clearSelection()
                applyEditingState(state)
                hasContinuousNoteInputCursor = false
                noteInputWasActivatedByPencil = false
            } catch {
                transitionSucceeded = false
                editingErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                editingState = .inactive
            }
        }

        let saveSucceeded = transitionSucceeded ? await savePendingChanges() : false
        if transitionSucceeded, let liveRenderSession = session.liveRenderSession {
            let coreKey = await liveRenderSession.scoreStartKey()
            if let key = ScoreTransposeTargetKey(coreKey: coreKey) {
                viewTransposeSourceKey = key
                viewTransposeKey = key
            }
        }
        interactionMode = .view
        return transitionSucceeded && saveSucceeded
    }

    deinit {
        loadTasks.values.forEach { $0.cancel() }
        playbackMonitorTask?.cancel()
        playbackContextTask?.cancel()
        playbackWarmupTask?.cancel()
        partSelectionTask?.cancel()
        autosaveTask?.cancel()
        backgroundRecoveryTask?.cancel()
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

    func playFromHereTarget(for pageIndex: Int) -> ScorePlayFromHereTarget? {
        guard playFromHereTarget?.pageIndex == pageIndex else {
            return nil
        }

        return playFromHereTarget
    }

    func playbackLoopRange(for pageIndex: Int) -> ScorePlaybackLoopRange? {
        guard playbackLoopRange?.pageIndex == pageIndex else {
            return nil
        }

        return playbackLoopRange
    }

    func noteEntryPreview(for pageIndex: Int) -> ScoreNoteEntryPreview? {
        guard noteEntryPreview?.pageIndex == pageIndex else {
            return nil
        }

        return noteEntryPreview
    }

    func selectedElement(for pageIndex: Int) -> ScoreSelectedElement? {
        guard isEditingMode else {
            return nil
        }

        if measureRangePreviewSelection?.pageIndex == pageIndex {
            return measureRangePreviewSelection
        }

        guard let selection = editingState.selection else {
            return nil
        }

        return selection.pageIndex == pageIndex ? selection : selection.highlightOnly(onPage: pageIndex)
    }
}
