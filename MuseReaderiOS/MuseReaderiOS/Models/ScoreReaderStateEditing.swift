import CoreGraphics
import Foundation

struct ScoreTransposeRequest {
    let mode: ScoreTransposeMode
    let direction: ScoreTransposeDirection
    let interval: Int
    let targetKey: Int
}

enum ScoreTransposeMode: Int, CaseIterable {
    case interval = 1
    case diatonic = 0
    case byKey = 2

    var title: String {
        switch self {
        case .diatonic:
            return "Diatonic"
        case .interval:
            return "Interval"
        case .byKey:
            return "To Key"
        }
    }
}

enum ScoreTransposeDirection: Int, CaseIterable {
    case up = 0
    case down = 1

    var title: String {
        switch self {
        case .up:
            return "Up"
        case .down:
            return "Down"
        }
    }
}

protocol ScoreReaderTransposeOption: Hashable {
    var title: String { get }
}

enum ScoreTransposeDiatonicStep: CaseIterable, ScoreReaderTransposeOption {
    case second
    case third
    case fourth
    case fifth
    case sixth
    case seventh
    case octave

    var title: String {
        switch self {
        case .second: return "2nd"
        case .third: return "3rd"
        case .fourth: return "4th"
        case .fifth: return "5th"
        case .sixth: return "6th"
        case .seventh: return "7th"
        case .octave: return "Octave"
        }
    }

    var coreInterval: Int {
        switch self {
        case .second: return 1
        case .third: return 2
        case .fourth: return 3
        case .fifth: return 4
        case .sixth: return 5
        case .seventh: return 6
        case .octave: return 25
        }
    }
}

enum ScoreTransposeInterval: CaseIterable, ScoreReaderTransposeOption {
    case minorSecond
    case majorSecond
    case minorThird
    case majorThird
    case perfectFourth
    case augmentedFourth
    case perfectFifth
    case minorSixth
    case majorSixth
    case minorSeventh
    case majorSeventh
    case diminishedOctave
    case perfectOctave

    var title: String {
        switch self {
        case .minorSecond: return "Minor 2nd"
        case .majorSecond: return "Major 2nd"
        case .minorThird: return "Minor 3rd"
        case .majorThird: return "Major 3rd"
        case .perfectFourth: return "Perfect 4th"
        case .augmentedFourth: return "Aug. 4th"
        case .perfectFifth: return "Perfect 5th"
        case .minorSixth: return "Minor 6th"
        case .majorSixth: return "Major 6th"
        case .minorSeventh: return "Minor 7th"
        case .majorSeventh: return "Major 7th"
        case .diminishedOctave: return "Dim. Octave"
        case .perfectOctave: return "Perfect Octave"
        }
    }

    var coreInterval: Int {
        switch self {
        case .minorSecond: return 3
        case .majorSecond: return 4
        case .minorThird: return 7
        case .majorThird: return 8
        case .perfectFourth: return 11
        case .augmentedFourth: return 12
        case .perfectFifth: return 14
        case .minorSixth: return 17
        case .majorSixth: return 18
        case .minorSeventh: return 21
        case .majorSeventh: return 22
        case .diminishedOctave: return 24
        case .perfectOctave: return 25
        }
    }
}

enum ScoreTransposeTargetKey: CaseIterable, ScoreReaderTransposeOption {
    case cMajor
    case gMajor
    case dMajor
    case aMajor
    case eMajor
    case bMajor
    case fSharpMajor
    case cSharpMajor
    case cFlatMajor
    case gFlatMajor
    case dFlatMajor
    case aFlatMajor
    case eFlatMajor
    case bFlatMajor
    case fMajor

    var title: String {
        switch self {
        case .cFlatMajor: return "Cb major / Ab minor"
        case .gFlatMajor: return "Gb major / Eb minor"
        case .dFlatMajor: return "Db major / Bb minor"
        case .aFlatMajor: return "Ab major / F minor"
        case .eFlatMajor: return "Eb major / C minor"
        case .bFlatMajor: return "Bb major / G minor"
        case .fMajor: return "F major / D minor"
        case .cMajor: return "C major / A minor"
        case .gMajor: return "G major / E minor"
        case .dMajor: return "D major / B minor"
        case .aMajor: return "A major / F# minor"
        case .eMajor: return "E major / C# minor"
        case .bMajor: return "B major / G# minor"
        case .fSharpMajor: return "F# major / D# minor"
        case .cSharpMajor: return "C# major / A# minor"
        }
    }

    var coreKey: Int {
        switch self {
        case .cMajor: return 0
        case .gMajor: return 1
        case .dMajor: return 2
        case .aMajor: return 3
        case .eMajor: return 4
        case .bMajor: return 5
        case .fSharpMajor: return 6
        case .cSharpMajor: return 7
        case .cFlatMajor: return -7
        case .gFlatMajor: return -6
        case .dFlatMajor: return -5
        case .aFlatMajor: return -4
        case .eFlatMajor: return -3
        case .bFlatMajor: return -2
        case .fMajor: return -1
        }
    }

    init?(coreKey: Int) {
        guard let key = Self.allCases.first(where: { $0.coreKey == coreKey }) else {
            return nil
        }
        self = key
    }
}

@MainActor
extension ScoreReaderState {
    func loadEditingState() {
        guard supportsEditing, let liveRenderSession = session.liveRenderSession else {
            editingState = .inactive
            return
        }

        editingStateTask?.cancel()
        editingStateRevision += 1
        let revision = editingStateRevision
        editingStateTask = Task { @MainActor [weak self] in
            defer {
                if self?.editingStateRevision == revision {
                    self?.editingStateTask = nil
                }
            }

            do {
                let editingState = try await liveRenderSession.currentEditingState()
                guard
                    !Task.isCancelled,
                    let self,
                    self.editingStateRevision == revision
                else {
                    return
                }
                self.applyEditingState(editingState)
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                self?.editingErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func handlePageTap(pageIndex: Int, normalizedPoint: CGPoint, inputKind: ScorePageTapInputKind = .direct) {
        guard
            supportsEditing,
            let liveRenderSession = session.liveRenderSession,
            !isEditingActionInFlight
        else {
            return
        }

        updateSelection(to: pageIndex)
        let shouldInsert = editingState.noteInputEnabled
        let selectionHitRadiusScale = inputKind == .pencil ? 0.52 : 1.0
        let pendingAccidentalKind = self.pendingAccidentalKind
        // WYSIWYG: when inserting with the Pencil, commit at the spot the live
        // preview ghost was last shown (hover/fine-tune) instead of the tap's lift
        // point, which drifts as the tip lands. Falls back to the tap point.
        let pencilInsertionPoint: CGPoint = (shouldInsert && inputKind == .pencil)
            ? (committedPencilAimPoint(forPage: pageIndex, near: normalizedPoint) ?? normalizedPoint)
            : normalizedPoint
        if shouldInsert && inputKind == .pencil {
            clearPencilAim()
        }
        isEditingActionInFlight = true
        editingErrorMessage = nil

        Task { @MainActor [weak self] in
            defer {
                self?.isEditingActionInFlight = false
            }

            do {
                let newState: ScoreEditingState
                if shouldInsert && inputKind == .pencil {
                    newState = try await liveRenderSession.insertNote(
                        pageIndex: pageIndex,
                        normalizedPoint: pencilInsertionPoint,
                        accidentalKind: pendingAccidentalKind
                    )
                } else if shouldInsert {
                    let selectedState = try await liveRenderSession.selectElement(
                        pageIndex: pageIndex,
                        normalizedPoint: normalizedPoint,
                        hitRadiusScale: selectionHitRadiusScale
                    )
                    if selectedState.selection?.kind == .note || selectedState.selection?.kind == .rest {
                        newState = try await liveRenderSession.setNoteInputEnabled(false)
                    } else {
                        newState = selectedState
                    }
                } else {
                    newState = try await liveRenderSession.selectElement(
                        pageIndex: pageIndex,
                        normalizedPoint: normalizedPoint,
                        hitRadiusScale: selectionHitRadiusScale
                    )
                }

                if shouldInsert {
                    if newState.noteInputEnabled {
                        self?.hasContinuousNoteInputCursor = true
                        self?.lastKeyboardInputCanReceiveAccidental = false
                        self?.pendingAccidentalKind = nil
                        self?.pendingPreferFlats = false
                        self?.refreshAfterScoreMutation(with: newState, auditionNote: true, revealActiveNotation: true)
                    } else {
                        self?.hasContinuousNoteInputCursor = false
                        self?.lastKeyboardInputCanReceiveAccidental = false
                        self?.pendingAccidentalKind = nil
                        self?.pendingPreferFlats = false
                        self?.applyEditingState(newState)
                    }
                } else {
                    self?.hasContinuousNoteInputCursor = false
                    self?.lastKeyboardInputCanReceiveAccidental = false
                    self?.applyEditingState(newState)
                }
            } catch {
                self?.editingErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// Returns the last Pencil aim point if it's fresh, on the same page, and close
    /// enough to the tap to represent the same target; otherwise nil (use tap point).
    private func committedPencilAimPoint(forPage pageIndex: Int, near tapPoint: CGPoint) -> CGPoint? {
        guard
            let aim = lastPencilAimNormalizedPoint,
            lastPencilAimPageIndex == pageIndex,
            let timestamp = lastPencilAimTimestamp,
            Date().timeIntervalSince(timestamp) <= 0.4
        else {
            return nil
        }

        let dx = aim.x - tapPoint.x
        let dy = aim.y - tapPoint.y
        guard (dx * dx + dy * dy).squareRoot() <= 0.05 else {
            return nil
        }

        return aim
    }

    private func clearPencilAim() {
        lastPencilAimNormalizedPoint = nil
        lastPencilAimPageIndex = nil
        lastPencilAimTimestamp = nil
    }

    func handlePencilNoteEntryFineTune(
        pageIndex: Int,
        startNormalizedPoint _: CGPoint,
        dropNormalizedPoint: CGPoint
    ) {
        guard
            supportsEditing,
            let liveRenderSession = session.liveRenderSession,
            !isEditingActionInFlight
        else {
            return
        }

        updateSelection(to: pageIndex)
        let pendingAccidentalKind = self.pendingAccidentalKind
        isEditingActionInFlight = true
        editingErrorMessage = nil

        Task { @MainActor [weak self] in
            defer {
                self?.isEditingActionInFlight = false
            }

            do {
                let insertedState = try await liveRenderSession.insertNote(
                    pageIndex: pageIndex,
                    normalizedPoint: dropNormalizedPoint,
                    accidentalKind: pendingAccidentalKind
                )
                self?.hasContinuousNoteInputCursor = true
                self?.lastKeyboardInputCanReceiveAccidental = false
                self?.pendingAccidentalKind = nil
                self?.pendingPreferFlats = false
                self?.refreshAfterScoreMutation(with: insertedState, auditionNote: true, revealActiveNotation: true)
            } catch {
                self?.editingErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func updateNoteEntryPreview(pageIndex: Int, normalizedPoint: CGPoint?) {
        if let normalizedPoint {
            lastPencilAimNormalizedPoint = normalizedPoint
            lastPencilAimPageIndex = pageIndex
            lastPencilAimTimestamp = Date()
        }

        noteEntryPreviewRevision += 1
        let revision = noteEntryPreviewRevision
        noteEntryPreviewTask?.cancel()

        guard
            let normalizedPoint,
            editingState.noteInputEnabled,
            supportsEditing,
            let liveRenderSession = session.liveRenderSession
        else {
            noteEntryPreview = nil
            return
        }

        let duration = editingState.duration
        let isRest = editingState.noteInputInsertsRests
        let accidentalKind = pendingAccidentalKind
        noteEntryPreviewTask = Task { @MainActor [weak self] in
            do {
                let preview = try await liveRenderSession.noteEntryPreview(
                    pageIndex: pageIndex,
                    normalizedPoint: normalizedPoint,
                    duration: duration,
                    isRest: isRest,
                    accidentalKind: accidentalKind
                )
                guard !Task.isCancelled, self?.noteEntryPreviewRevision == revision else {
                    return
                }
                if let preview {
                    self?.noteEntryPreview = preview
                }
            } catch {
                guard !Task.isCancelled, self?.noteEntryPreviewRevision == revision else {
                    return
                }
            }
        }
    }

    func selectMeasureRange(pageIndex: Int, startNormalizedPoint: CGPoint, endNormalizedPoint: CGPoint) {
        guard
            supportsEditing,
            let liveRenderSession = session.liveRenderSession,
            !isEditingActionInFlight
        else {
            return
        }

        updateSelection(to: pageIndex)
        isEditingActionInFlight = true
        editingErrorMessage = nil

        Task { @MainActor [weak self] in
            defer {
                self?.isEditingActionInFlight = false
            }

            do {
                let newState = try await liveRenderSession.selectMeasureRange(
                    pageIndex: pageIndex,
                    startPoint: startNormalizedPoint,
                    endPoint: endNormalizedPoint
                )
                self?.hasContinuousNoteInputCursor = false
                self?.lastKeyboardInputCanReceiveAccidental = false
                self?.applyEditingState(newState)
                self?.clearMeasureRangePreview()
            } catch {
                self?.editingErrorMessage = nil
                self?.clearMeasureRangePreview()
            }
        }
    }

    func previewMeasureRange(pageIndex: Int, startNormalizedPoint: CGPoint, endNormalizedPoint: CGPoint) {
        guard supportsEditing, let liveRenderSession = session.liveRenderSession else {
            clearMeasureRangePreview()
            return
        }

        measureRangePreviewRevision += 1
        let revision = measureRangePreviewRevision
        measureRangePreviewTask?.cancel()
        measureRangePreviewTask = Task { @MainActor [weak self] in
            do {
                let previewState = try await liveRenderSession.previewMeasureRange(
                    pageIndex: pageIndex,
                    startPoint: startNormalizedPoint,
                    endPoint: endNormalizedPoint
                )
                guard !Task.isCancelled, self?.measureRangePreviewRevision == revision else {
                    return
                }
                self?.measureRangePreviewSelection = previewState.selection
            } catch {
                guard !Task.isCancelled, self?.measureRangePreviewRevision == revision else {
                    return
                }
                self?.measureRangePreviewSelection = nil
            }
        }
    }

    func clearMeasureRangePreview() {
        measureRangePreviewRevision += 1
        measureRangePreviewTask?.cancel()
        measureRangePreviewTask = nil
        measureRangePreviewSelection = nil
    }

    func toggleNoteInput() {
        setNoteInputEnabled(!editingState.noteInputEnabled)
    }

    func setNoteInputEnabled(_ enabled: Bool) {
        guard
            supportsEditing,
            let liveRenderSession = session.liveRenderSession,
            !isEditingActionInFlight
        else {
            return
        }

        isEditingActionInFlight = true
        editingErrorMessage = nil
        let targetValue = enabled
        let preferredVoice = editingState.currentVoice

        Task { @MainActor [weak self] in
            defer {
                self?.isEditingActionInFlight = false
            }

            do {
                var newState = try await liveRenderSession.setNoteInputEnabled(targetValue)
                if targetValue && newState.currentVoice != preferredVoice {
                    newState = try await liveRenderSession.setCurrentVoice(preferredVoice)
                }
                if !targetValue {
                    self?.hasContinuousNoteInputCursor = false
                    self?.noteInputWasActivatedByPencil = false
                    self?.lastKeyboardInputCanReceiveAccidental = false
                    self?.stackedChordInputEnabled = false
                    self?.updateNoteEntryPreview(pageIndex: self?.selectedPageIndex ?? 0, normalizedPoint: nil)
                } else {
                    self?.lastKeyboardInputCanReceiveAccidental = false
                }
                self?.applyEditingState(newState)
                if targetValue {
                    self?.revealActiveSelection(in: newState)
                }
            } catch {
                self?.editingErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func applyDuration(_ duration: ScoreNoteDuration) {
        performEditingAction(mutatesScore: editingState.selection != nil) { liveRenderSession in
            try await liveRenderSession.applyDuration(duration)
        }
    }

    func toggleRest() {
        if !editingState.noteInputInsertsRests {
            stackedChordInputEnabled = false
        }
        let shouldEnterRestAtCursor = editingState.noteInputEnabled && !noteInputWasActivatedByPencil
        performEditingAction(mutatesScore: editingState.noteInputEnabled || editingState.selection != nil) { liveRenderSession in
            if shouldEnterRestAtCursor {
                return try await liveRenderSession.enterRestAtCursor()
            }
            return try await liveRenderSession.toggleRest()
        }
    }

    func toggleDot() {
        performEditingAction(mutatesScore: editingState.selection != nil) { liveRenderSession in
            try await liveRenderSession.toggleDot()
        }
    }

    func toggleTie() {
        performEditingAction(mutatesScore: true) { liveRenderSession in
            try await liveRenderSession.toggleTie()
        }
    }

    func addTuplet(_ tupletCount: Int) {
        guard (2...9).contains(tupletCount) else {
            editingErrorMessage = "Choose a tuplet from 2 through 9."
            return
        }

        performEditingAction(mutatesScore: true) { liveRenderSession in
            try await liveRenderSession.addTuplet(tupletCount)
        }
    }

    func addText(_ textKind: String) {
        performEditingAction(mutatesScore: true) { liveRenderSession in
            try await liveRenderSession.addText(textKind)
        }
    }

    func prepareChordTextEntry() {
        performEditingAction(mutatesScore: false, revealActiveNotation: true) { liveRenderSession in
            _ = try await liveRenderSession.setNoteInputEnabled(false)
            return try await liveRenderSession.selectAttachedChordText()
        }
    }

    func prepareLyricsEntry() {
        performEditingAction(mutatesScore: false, revealActiveNotation: true) { liveRenderSession in
            _ = try await liveRenderSession.setNoteInputEnabled(false)
            return try await liveRenderSession.selectAttachedLyrics()
        }
    }

    func addChordText(_ chordText: String) {
        let trimmedChordText = chordText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedChordText.isEmpty else {
            editingErrorMessage = nil
            return
        }

        let anchorSelection = editingState.selection
        performEditingAction(mutatesScore: true, revealActiveNotation: true) { liveRenderSession in
            if anchorSelection?.kind != .chordText {
                _ = try await liveRenderSession.addText("Chord Text")
            }
            _ = try await liveRenderSession.setSelectedText(trimmedChordText)
            guard let anchorSelection else {
                let selectedState = try await liveRenderSession.selectAdjacentElement(next: false)
                self.auditionChordText(trimmedChordText, in: selectedState)
                return selectedState
            }
            let anchorPoint = anchorSelection.kind == .chordText
                ? (anchorSelection.attachmentPoint ?? anchorSelection.normalizedRect.center)
                : anchorSelection.normalizedRect.center
            let anchorState = try await liveRenderSession.selectElement(pageIndex: anchorSelection.pageIndex, normalizedPoint: anchorPoint)
            self.auditionChordText(trimmedChordText, in: anchorState)
            return anchorState
        }
    }

    func addChordTextAndSelectNext(_ chordText: String) {
        let trimmedChordText = chordText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedChordText.isEmpty else {
            editingErrorMessage = nil
            return
        }

        let anchorSelection = editingState.selection
        performEditingAction(mutatesScore: true, revealActiveNotation: true) { liveRenderSession in
            if anchorSelection?.kind != .chordText {
                _ = try await liveRenderSession.addText("Chord Text")
            }
            let editedState = try await liveRenderSession.setSelectedText(trimmedChordText)
            self.auditionChordText(trimmedChordText, in: editedState)
            return try await liveRenderSession.selectAdjacentElement(next: true)
        }
    }

    func setSelectedText(_ text: String) {
        performEditingAction(mutatesScore: true) { liveRenderSession in
            try await liveRenderSession.setSelectedText(text)
        }
    }

    func addLyricsText(_ text: String, advanceToNextChord: Bool) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty || advanceToNextChord else {
            editingErrorMessage = nil
            return
        }

        performEditingAction(mutatesScore: !trimmedText.isEmpty, revealActiveNotation: true) { liveRenderSession in
            try await liveRenderSession.addLyricsText(trimmedText, advanceToNextChord: advanceToNextChord)
        }
    }

    func addRepeatJump(_ repeatJumpKind: String) {
        performEditingAction(mutatesScore: true) { liveRenderSession in
            try await liveRenderSession.addRepeatJump(repeatJumpKind)
        }
    }

    func addExpression(_ expressionKind: String) {
        performEditingAction(mutatesScore: true) { liveRenderSession in
            try await liveRenderSession.addExpression(expressionKind)
        }
    }

    func retargetSelectedExpressionEndpoint(start: Bool, pageIndex: Int, normalizedPoint: CGPoint) {
        performEditingAction(mutatesScore: true) { liveRenderSession in
            try await liveRenderSession.retargetSelectedExpressionEndpoint(
                start: start,
                pageIndex: pageIndex,
                normalizedPoint: normalizedPoint
            )
        }
    }

    func dragSelectedChordText(pageIndex: Int, normalizedPoint: CGPoint) {
        performEditingAction(mutatesScore: true) { liveRenderSession in
            try await liveRenderSession.dragSelectedChordText(
                pageIndex: pageIndex,
                normalizedPoint: normalizedPoint
            )
        }
    }

    func addLayoutBreak(_ breakKind: String) {
        guard
            supportsEditing,
            let liveRenderSession = session.liveRenderSession,
            !isEditingActionInFlight
        else {
            return
        }

        isEditingActionInFlight = true
        editingErrorMessage = nil

        Task { @MainActor [weak self] in
            defer {
                self?.isEditingActionInFlight = false
            }

            do {
                let newState = try await liveRenderSession.addLayoutBreak(breakKind)
                guard let self else {
                    return
                }

                self.removeCachedLayoutMarkers()
                self.refreshAfterScoreMutation(with: newState)
            } catch {
                self?.editingErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func removeLayoutBreak() {
        guard
            supportsEditing,
            let liveRenderSession = session.liveRenderSession,
            !isEditingActionInFlight
        else {
            return
        }

        let removedSelection = editingState.selection
        isEditingActionInFlight = true
        editingErrorMessage = nil

        Task { @MainActor [weak self] in
            defer {
                self?.isEditingActionInFlight = false
            }

            do {
                let newState = try await liveRenderSession.removeLayoutBreak()
                guard let self else {
                    return
                }

                self.removeCachedLayoutMarkers()
                self.removeCachedLayoutMarker(for: removedSelection)
                self.refreshAfterScoreMutation(with: newState)
            } catch {
                self?.editingErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func addInstrument(_ instrument: NewScoreInstrument) {
        performEditingAction(mutatesScore: true) { liveRenderSession in
            try await liveRenderSession.addInstrument(instrument.instrumentID)
        }
    }

    func addInstruments(_ instruments: [NewScoreInstrument]) {
        let instrumentIDs = instruments.map(\.instrumentID)
        guard !instrumentIDs.isEmpty else {
            return
        }

        performEditingAction(mutatesScore: true) { liveRenderSession in
            var editState = try await liveRenderSession.addInstrument(instrumentIDs[0])
            for instrumentID in instrumentIDs.dropFirst() {
                editState = try await liveRenderSession.addInstrument(instrumentID)
            }
            return editState
        }
    }

    func removeSelectedInstrument() {
        performEditingAction(mutatesScore: true) { liveRenderSession in
            try await liveRenderSession.removeSelectedInstrument()
        }
    }

    func removeInstrument(at partIndex: Int) {
        performEditingAction(mutatesScore: true) { liveRenderSession in
            try await liveRenderSession.removeInstrument(at: partIndex)
        }
    }

    func moveInstrument(from sourceIndex: Int, to destinationIndex: Int) {
        performEditingAction(mutatesScore: true) { liveRenderSession in
            try await liveRenderSession.moveInstrument(from: sourceIndex, to: destinationIndex)
        }
    }

    func setInstrumentVisible(at partIndex: Int, visible: Bool) {
        performEditingAction(mutatesScore: true) { liveRenderSession in
            try await liveRenderSession.setInstrumentVisible(at: partIndex, visible: visible)
        }
    }

    func changeClef(_ clefKind: String) {
        performEditingAction(mutatesScore: true) { liveRenderSession in
            try await liveRenderSession.changeClef(clefKind)
        }
    }

    func fillSelectionWithSlashes() {
        performEditingAction(mutatesScore: true) { liveRenderSession in
            try await liveRenderSession.fillSelectionWithSlashes()
        }
    }

    func replaceSelectionWithRhythmicSlashes() {
        performEditingAction(mutatesScore: true) { liveRenderSession in
            try await liveRenderSession.replaceSelectionWithRhythmicSlashes()
        }
    }

    func applyAutoSystemBreaks(_ request: ScoreAutoSystemBreaksRequest) {
        performEditingAction(mutatesScore: true) { liveRenderSession in
            try await liveRenderSession.applyAutoSystemBreaks(request)
        }
    }

    func updateStaffSpacing(_ staffDistanceSpatium: Double) {
        performEditingAction(mutatesScore: true) { liveRenderSession in
            try await liveRenderSession.updateStaffSpacing(staffDistanceSpatium)
        }
    }

    func updatePageLayout(_ value: ScorePageSettingsValue) {
        performEditingAction(mutatesScore: true) { liveRenderSession in
            try await liveRenderSession.updatePageLayout(value)
        }
    }

    func updateLayoutOptions(_ value: ScoreLayoutOptionsValue) {
        performEditingAction(mutatesScore: true) { liveRenderSession in
            try await liveRenderSession.updateLayoutOptions(value)
        }
    }

    func addTempo(_ value: TempoValue) {
        performEditingAction(mutatesScore: true) { liveRenderSession in
            try await liveRenderSession.addTempo(beatUnit: value.beatUnit, bpm: value.bpm)
        }
    }

    func updateTimeSignature(_ value: ScoreTimeSignatureValue, applyScope: ScoreSignatureApplyScope) {
        performEditingAction(mutatesScore: true) { liveRenderSession in
            try await liveRenderSession.updateTimeSignature(value, fromStart: applyScope == .fromStart)
        }
    }

    func updateKeySignature(_ value: ScoreKeySignatureValue, applyScope: ScoreSignatureApplyScope) {
        performEditingAction(mutatesScore: true) { liveRenderSession in
            try await liveRenderSession.updateKeySignature(value.keyValue, fromStart: applyScope == .fromStart)
        }
    }

    func updateScoreSetupMetadata(_ metadata: ScoreEditableMetadata) {
        guard
            supportsEditing,
            let liveRenderSession = session.liveRenderSession,
            !isEditingActionInFlight
        else {
            return
        }

        isEditingActionInFlight = true
        editingErrorMessage = nil

        Task { @MainActor [weak self] in
            defer {
                self?.isEditingActionInFlight = false
            }

            do {
                try await liveRenderSession.updateMetadata(metadata)
                self?.invalidatePlaybackAfterScoreMutation()
                self?.invalidateRenderedPages()
                self?.scheduleAutosave()
            } catch {
                self?.editingErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func deleteSelection() {
        guard editingState.selection != nil else {
            editingErrorMessage = nil
            return
        }

        if editingState.selection?.kind == .layoutBreak {
            removeLayoutBreak()
            return
        }

        performEditingAction(mutatesScore: true) { liveRenderSession in
            try await liveRenderSession.deleteSelection()
        }
    }

    func clearSelectedMeasure() {
        guard editingState.selection?.kind == .measure else {
            editingErrorMessage = "Select a measure before clearing it."
            return
        }

        performEditingAction(mutatesScore: true) { liveRenderSession in
            try await liveRenderSession.clearSelectedMeasure()
        }
    }

    func selectCorruptionIssue(_ issue: ScoreCorruptionIssue) {
        guard
            let liveRenderSession = session.liveRenderSession,
            !isEditingActionInFlight
        else {
            return
        }

        isEditingActionInFlight = true
        editingErrorMessage = nil

        Task { @MainActor [weak self] in
            defer {
                self?.isEditingActionInFlight = false
            }

            do {
                let newState = try await liveRenderSession.selectCorruptionIssue(issue)
                self?.hasContinuousNoteInputCursor = false
                self?.lastKeyboardInputCanReceiveAccidental = false
                self?.applyEditingState(newState)
                if let selectedPageIndex = newState.selection?.pageIndex, self?.isValid(selectedPageIndex) == true {
                    self?.selectedPageIndex = selectedPageIndex
                }
            } catch {
                self?.editingErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func clearCorruptionIssue(_ issue: ScoreCorruptionIssue) {
        guard
            issue.repairable,
            let liveRenderSession = session.liveRenderSession,
            !isEditingActionInFlight
        else {
            editingErrorMessage = issue.repairable ? nil : "This issue is not repairable from the current score view."
            return
        }

        isEditingActionInFlight = true
        editingErrorMessage = nil

        Task { @MainActor [weak self] in
            defer {
                self?.isEditingActionInFlight = false
            }

            do {
                let (newState, report) = try await liveRenderSession.clearCorruptionIssue(issue)
                self?.corruptionReport = report
                self?.refreshAfterScoreMutation(with: newState)
            } catch {
                self?.editingErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func removeSelectedMeasure() {
        guard editingState.selection?.kind == .measure else {
            editingErrorMessage = "Select a measure before removing it."
            return
        }

        performEditingAction(mutatesScore: true) { liveRenderSession in
            try await liveRenderSession.removeSelectedMeasure()
        }
    }

    func addMeasure() {
        addMeasures(1)
    }

    func addMultipleMeasures() {
        addMeasures(4)
    }

    func addMeasures(_ count: Int) {
        guard editingState.selection?.kind == .measure else {
            editingErrorMessage = "Select a measure before adding measures."
            return
        }

        performEditingAction(mutatesScore: true) { liveRenderSession in
            try await liveRenderSession.addMeasures(count)
        }
    }

    /// Loads the first measure's current pickup state and opens the pickup editor.
    func presentPickupEditor(createNewMeasure: Bool = false) {
        guard
            supportsEditing,
            let liveRenderSession = session.liveRenderSession,
            !isEditingActionInFlight
        else {
            return
        }

        editingErrorMessage = nil
        Task { @MainActor [weak self] in
            do {
                let state = try await liveRenderSession.firstMeasurePickupState()
                self?.pickupEditorContext = ScorePickupEditorContext(
                    isExistingPickup: state.isPickup,
                    createsNewMeasure: createNewMeasure && !state.isPickup,
                    nominalNumerator: state.nominalNumerator > 0 ? state.nominalNumerator : 4,
                    nominalDenominator: state.nominalDenominator > 0 ? state.nominalDenominator : 4,
                    currentNumerator: state.isPickup ? state.actualNumerator : 0,
                    currentDenominator: state.isPickup ? state.actualDenominator : 0
                )
            } catch {
                self?.editingErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func dismissPickupEditor() {
        pickupEditorContext = nil
    }

    func applyPickupMeasure(numerator: Int, denominator: Int) {
        let createsNewMeasure = pickupEditorContext?.createsNewMeasure == true
        pickupEditorContext = nil
        performEditingAction(mutatesScore: true) { liveRenderSession in
            if createsNewMeasure {
                try await liveRenderSession.createFirstPickupMeasure(numerator: numerator, denominator: denominator)
            } else {
                try await liveRenderSession.setFirstMeasurePickup(numerator: numerator, denominator: denominator)
            }
        }
    }

    func removePickupMeasure() {
        pickupEditorContext = nil
        performEditingAction(mutatesScore: true) { liveRenderSession in
            try await liveRenderSession.clearFirstMeasurePickup()
        }
    }

    func copySelectedMeasureRange() {
        guard editingState.selection != nil else {
            editingErrorMessage = "Select something in the score before copying."
            return
        }

        performEditingAction(mutatesScore: false) { liveRenderSession in
            try await liveRenderSession.copySelectedMeasureRange()
        }
    }

    func cutSelectedMeasureRange() {
        guard editingState.selection != nil else {
            editingErrorMessage = "Select something in the score before cutting."
            return
        }

        performEditingAction(mutatesScore: true) { liveRenderSession in
            try await liveRenderSession.cutSelectedMeasureRange()
        }
    }

    func pasteMeasureRange() {
        guard editingState.selection != nil else {
            editingErrorMessage = "Select a paste destination in the score."
            return
        }

        performEditingAction(mutatesScore: true) { liveRenderSession in
            try await liveRenderSession.pasteMeasureRange()
        }
    }

    func selectAll() {
        performEditingAction(mutatesScore: false) { liveRenderSession in
            try await liveRenderSession.selectAll()
        }
    }

    func clearSelection() {
        if editingState.noteInputEnabled || hasContinuousNoteInputCursor {
            setNoteInputEnabled(false)
            return
        }

        guard editingState.selection != nil else {
            editingErrorMessage = nil
            return
        }

        performEditingAction(mutatesScore: false) { liveRenderSession in
            try await liveRenderSession.clearSelection()
        }
    }

    func transposeSelectedMeasureRange(_ request: ScoreTransposeRequest) {
        guard let selection = editingState.selection,
              selection.kind == .measure || selection.kind == .note || selection.kind == .rest else {
            editingErrorMessage = "Select a note, rest, or measure before transposing."
            return
        }

        performEditingAction(mutatesScore: true) { liveRenderSession in
            try await liveRenderSession.transposeSelectedMeasureRange(request)
        }
    }

    func movePitch(up: Bool) {
        performEditingAction(mutatesScore: true, auditionNote: true) { liveRenderSession in
            try await liveRenderSession.movePitch(up: up)
        }
    }

    func shiftPitchBySemitones(_ semitoneDelta: Int) {
        performEditingAction(mutatesScore: true, auditionNote: true) { liveRenderSession in
            try await liveRenderSession.shiftPitchBySemitones(semitoneDelta)
        }
    }

    func shiftPitchByOctaves(_ octaveDelta: Int) {
        performEditingAction(mutatesScore: true, auditionNote: true) { liveRenderSession in
            try await liveRenderSession.shiftPitchByOctaves(octaveDelta)
        }
    }

    func dragSelectedNote(pageIndex: Int, normalizedPoint: CGPoint) {
        guard
            supportsEditing,
            let liveRenderSession = session.liveRenderSession,
            !isEditingActionInFlight
        else {
            return
        }

        isEditingActionInFlight = true
        editingErrorMessage = nil

        Task { @MainActor [weak self] in
            defer {
                self?.isEditingActionInFlight = false
            }

            do {
                if self?.editingState.noteInputEnabled == true {
                    let selectState = try await liveRenderSession.setNoteInputEnabled(false)
                    self?.hasContinuousNoteInputCursor = false
                    self?.lastKeyboardInputCanReceiveAccidental = false
                    self?.applyEditingState(selectState)
                }

                let draggedState = try await liveRenderSession.setSelectedPitch(
                    pageIndex: pageIndex,
                    normalizedPoint: normalizedPoint
                )
                self?.refreshAfterScoreMutation(with: draggedState, auditionNote: true)
            } catch {
                self?.editingErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func setSelectedPitchClass(_ pitchClass: Int, preferFlats: Bool) {
        performEditingAction(mutatesScore: true, auditionNote: true) { liveRenderSession in
            try await liveRenderSession.setSelectedPitchClass(pitchClass, preferFlats: preferFlats)
        }
    }

    func setSelectedMIDIPitch(_ midiPitch: Int, preferFlats: Bool) {
        performEditingAction(mutatesScore: true, auditionNote: true) { liveRenderSession in
            try await liveRenderSession.setSelectedMIDIPitch(midiPitch, preferFlats: preferFlats)
        }
    }

    func changeSelectedEnharmonicSpelling() {
        performEditingAction(mutatesScore: true, auditionNote: true) { liveRenderSession in
            try await liveRenderSession.changeSelectedEnharmonicSpelling()
        }
    }

    func changeSelectedAccidental(_ accidentalKind: ScoreAccidentalKind) {
        performEditingAction(mutatesScore: true, auditionNote: true) { liveRenderSession in
            try await liveRenderSession.changeSelectedAccidental(accidentalKind)
        }
    }

    func handleKeyboardPitchClass(_ pitchClass: Int, preferFlats: Bool) {
        pendingPitchClass = pitchClass
        pendingMIDIPitch = nil
        pendingPreferFlats = preferFlats
        pendingAccidentalKind = nil

        guard !editingState.noteInputEnabled else {
            editingErrorMessage = nil
            return
        }

        guard editingState.selection?.canChangePitch == true || editingState.selection?.kind == .rest || editingState.selection?.kind == .measure else {
            editingErrorMessage = nil
            return
        }

        setSelectedPitchClass(pitchClass, preferFlats: preferFlats)
    }

    func handleKeyboardPitch(_ pitchClass: Int, midiPitch: Int?, preferFlats: Bool, exactMIDIPitch: Bool = false) {
        pendingPitchClass = pitchClass
        pendingMIDIPitch = midiPitch
        pendingPreferFlats = preferFlats
        pendingAccidentalKind = nil
        noteInputWasActivatedByPencil = false

        if shouldEditSelectedPitchBeforeContinuingKeyboardInput,
           editingState.selection?.canChangePitch == true {
            shouldEditSelectedPitchBeforeContinuingKeyboardInput = false
            changeSelectedPitchThenEnterNoteInput(pitchClass: pitchClass, midiPitch: midiPitch, preferFlats: preferFlats, exactMIDIPitch: exactMIDIPitch)
            return
        }

        let noteInputWasEnabled = editingState.noteInputEnabled
        let preferredVoice = editingState.currentVoice
        if noteInputWasEnabled || hasContinuousNoteInputCursor {
            let addToCurrentChord = stackedChordInputEnabled
                && !editingState.noteInputInsertsRests
            guard noteInputWasEnabled || hasContinuousNoteInputCursor || editingState.selection?.kind == .note || editingState.selection?.kind == .rest || editingState.selection?.kind == .measure else {
                editingErrorMessage = nil
                return
            }

            performEditingAction(mutatesScore: true, auditionNote: true, revealActiveNotation: true) { liveRenderSession in
                if !noteInputWasEnabled {
                    let enabledState = try await liveRenderSession.setNoteInputEnabled(true)
                    if enabledState.currentVoice != preferredVoice {
                        _ = try await liveRenderSession.setCurrentVoice(preferredVoice)
                    }
                }
                if exactMIDIPitch, let midiPitch {
                    return try await liveRenderSession.insertMIDIPitchAtCursor(midiPitch, preferFlats: preferFlats, addToCurrentChord: addToCurrentChord)
                }

                return try await liveRenderSession.insertPitchAtCursor(pitchClass, preferFlats: preferFlats, addToCurrentChord: addToCurrentChord)
            }
            hasContinuousNoteInputCursor = true
            lastKeyboardInputCanReceiveAccidental = true
        } else {
            if editingState.selection?.canChangePitch == true || editingState.selection?.kind == .rest || editingState.selection?.kind == .measure {
                changeSelectedPitchThenEnterNoteInput(pitchClass: pitchClass, midiPitch: midiPitch, preferFlats: preferFlats, exactMIDIPitch: exactMIDIPitch)
            } else {
                enableNoteInputThenInsertKeyboardPitch(pitchClass: pitchClass, midiPitch: midiPitch, preferFlats: preferFlats, exactMIDIPitch: exactMIDIPitch)
            }
        }
    }

    func enableNoteInputThenInsertKeyboardPitch(pitchClass: Int, midiPitch: Int?, preferFlats: Bool, exactMIDIPitch: Bool = false) {
        guard
            supportsEditing,
            let liveRenderSession = session.liveRenderSession,
            !isEditingActionInFlight
        else {
            return
        }

        isEditingActionInFlight = true
        editingErrorMessage = nil
        let preferredVoice = editingState.currentVoice
        let addToCurrentChord = stackedChordInputEnabled
            && !editingState.noteInputInsertsRests

        Task { @MainActor [weak self] in
            defer {
                self?.isEditingActionInFlight = false
            }

            do {
                let enabledState = try await liveRenderSession.setNoteInputEnabled(true)
                if enabledState.currentVoice != preferredVoice {
                    _ = try await liveRenderSession.setCurrentVoice(preferredVoice)
                }

                let insertedState: ScoreEditingState
                if exactMIDIPitch, let midiPitch {
                    insertedState = try await liveRenderSession.insertMIDIPitchAtCursor(midiPitch, preferFlats: preferFlats, addToCurrentChord: addToCurrentChord)
                } else {
                    insertedState = try await liveRenderSession.insertPitchAtCursor(pitchClass, preferFlats: preferFlats, addToCurrentChord: addToCurrentChord)
                }

                self?.hasContinuousNoteInputCursor = true
                self?.lastKeyboardInputCanReceiveAccidental = true
                self?.refreshAfterScoreMutation(with: insertedState, auditionNote: true, revealActiveNotation: true)
            } catch {
                self?.editingErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func toggleStackedChordInput() {
        stackedChordInputEnabled.toggle()
        if stackedChordInputEnabled && editingState.noteInputInsertsRests {
            toggleRest()
        }
    }

    func setCurrentVoice(_ voice: Int) {
        let clampedVoice = min(max(voice, 0), 3)
        guard clampedVoice != editingState.currentVoice else {
            return
        }

        noteEntryPreviewRevision += 1
        noteEntryPreviewTask?.cancel()
        noteEntryPreview = nil
        let changesSelectedVoice = !editingState.noteInputEnabled
            && (editingState.selection?.kind == .note || editingState.selection?.kind == .rest)
        performEditingAction(mutatesScore: changesSelectedVoice) { liveRenderSession in
            try await liveRenderSession.setCurrentVoice(clampedVoice)
        }
    }

    func startMIDIInput() {
        guard supportsEditing else {
            return
        }

        activeMIDIPitches.removeAll()
        pendingMIDIChordPitches.removeAll()
        midiChordCaptureTask?.cancel()
        midiChordCaptureTask = nil
        midiInputController.start()
    }

    func stopMIDIInput() {
        midiInputController.stop()
        activeMIDIPitches.removeAll()
        pendingMIDIChordPitches.removeAll()
        midiChordCaptureTask?.cancel()
        midiChordCaptureTask = nil
    }

    func handleMIDINoteOn(_ midiPitch: Int) {
        guard (0...127).contains(midiPitch) else {
            return
        }

        if activeMIDIPitches.isEmpty, !pendingMIDIChordPitches.isEmpty {
            commitPendingMIDIChordCapture()
        }

        guard activeMIDIPitches.insert(midiPitch).inserted else {
            return
        }

        pendingMIDIChordPitches.insert(midiPitch)
        scheduleMIDIChordCaptureIfNeeded(after: midiChordMaxHoldDelay)
    }

    func handleMIDINoteOff(_ midiPitch: Int) {
        activeMIDIPitches.remove(midiPitch)
        if activeMIDIPitches.isEmpty, !pendingMIDIChordPitches.isEmpty {
            scheduleMIDIChordCapture(after: midiChordReleaseSettleDelay)
        }
    }

    func handleMIDIPitchInput(_ midiPitch: Int) {
        guard (0...127).contains(midiPitch) else {
            return
        }

        let pitchClass = normalizedPitchClass(midiPitch)
        handleKeyboardPitch(pitchClass, midiPitch: midiPitch, preferFlats: pendingPreferFlats, exactMIDIPitch: true)
    }

    private func scheduleMIDIChordCaptureIfNeeded(after delay: Duration) {
        guard midiChordCaptureTask == nil else {
            return
        }

        scheduleMIDIChordCapture(after: delay)
    }

    private func scheduleMIDIChordCapture(after delay: Duration) {
        midiChordCaptureTask?.cancel()
        midiChordCaptureTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            self?.commitPendingMIDIChordCapture()
        }
    }

    private func commitPendingMIDIChordCapture() {
        guard !isEditingActionInFlight else {
            scheduleMIDIChordCapture(after: midiChordReleaseSettleDelay)
            return
        }

        let midiPitches = pendingMIDIChordPitches.sorted()
        pendingMIDIChordPitches.removeAll()
        midiChordCaptureTask = nil

        guard !midiPitches.isEmpty else {
            return
        }

        guard midiPitches.count > 1 else {
            handleMIDIPitchInput(midiPitches[0])
            return
        }

        insertMIDIChordAtCursor(midiPitches, preferFlats: pendingPreferFlats)
    }

    private func insertMIDIChordAtCursor(_ midiPitches: [Int], preferFlats: Bool) {
        guard
            supportsEditing,
            let liveRenderSession = session.liveRenderSession,
            !isEditingActionInFlight
        else {
            return
        }

        let validPitches = midiPitches.filter { (0...127).contains($0) }
        guard !validPitches.isEmpty else {
            return
        }

        pendingMIDIPitch = validPitches.first
        pendingPitchClass = validPitches.first.map(normalizedPitchClass)
        pendingPreferFlats = preferFlats
        pendingAccidentalKind = nil

        isEditingActionInFlight = true
        editingErrorMessage = nil
        let noteInputWasEnabled = editingState.noteInputEnabled
        let preferredVoice = editingState.currentVoice

        Task { @MainActor [weak self] in
            defer {
                self?.isEditingActionInFlight = false
            }

            do {
                if !noteInputWasEnabled {
                    let enabledState = try await liveRenderSession.setNoteInputEnabled(true)
                    if enabledState.currentVoice != preferredVoice {
                        _ = try await liveRenderSession.setCurrentVoice(preferredVoice)
                    }
                }

                let insertedState = try await liveRenderSession.insertMIDIChordAtCursor(validPitches, preferFlats: preferFlats)
                self?.hasContinuousNoteInputCursor = true
                self?.lastKeyboardInputCanReceiveAccidental = true
                self?.refreshAfterScoreMutation(with: insertedState, auditionNote: true, revealActiveNotation: true)
            } catch {
                self?.editingErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func removeMIDIPitchFromCurrentChord(_ midiPitch: Int) {
        performEditingAction(mutatesScore: true, auditionNote: true, revealActiveNotation: true) { liveRenderSession in
            try await liveRenderSession.removeMIDIPitchFromCurrentChord(midiPitch)
        }
        hasContinuousNoteInputCursor = true
        lastKeyboardInputCanReceiveAccidental = false
    }

    private func normalizedPitchClass(_ midiPitch: Int) -> Int {
        let value = midiPitch % 12
        return value >= 0 ? value : value + 12
    }

    func changeSelectedPitchThenEnterNoteInput(pitchClass: Int, midiPitch: Int?, preferFlats: Bool, exactMIDIPitch: Bool = false) {
        guard
            supportsEditing,
            let liveRenderSession = session.liveRenderSession,
            !isEditingActionInFlight
        else {
            return
        }

        isEditingActionInFlight = true
        editingErrorMessage = nil
        let preferredVoice = editingState.currentVoice

        Task { @MainActor [weak self] in
            defer {
                self?.isEditingActionInFlight = false
            }

            do {
                let changedState: ScoreEditingState
                if exactMIDIPitch, let midiPitch {
                    changedState = try await liveRenderSession.setSelectedMIDIPitch(midiPitch, preferFlats: preferFlats)
                } else {
                    changedState = try await liveRenderSession.setSelectedPitchClass(pitchClass, preferFlats: preferFlats)
                }

                self?.refreshAfterScoreMutation(with: changedState, auditionNote: true)

                var noteInputState = try await liveRenderSession.setNoteInputEnabled(true)
                if noteInputState.currentVoice != preferredVoice {
                    noteInputState = try await liveRenderSession.setCurrentVoice(preferredVoice)
                }
                self?.hasContinuousNoteInputCursor = true
                self?.lastKeyboardInputCanReceiveAccidental = false
                self?.applyEditingState(noteInputState)
            } catch {
                self?.editingErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func prepareAccidental(_ accidentalKind: ScoreAccidentalKind) {
        if editingState.noteInputEnabled,
           hasContinuousNoteInputCursor,
           lastKeyboardInputCanReceiveAccidental,
           !noteInputWasActivatedByPencil {
            pendingAccidentalKind = nil
            pendingPreferFlats = accidentalKind == .flat
            changeSelectedAccidental(accidentalKind)
            return
        }

        if pendingAccidentalKind == accidentalKind {
            pendingAccidentalKind = nil
            pendingPreferFlats = false
        } else {
            pendingAccidentalKind = accidentalKind
            pendingPreferFlats = accidentalKind == .flat
        }
        editingErrorMessage = nil
    }

    func selectPreviousElement() {
        shouldEditSelectedPitchBeforeContinuingKeyboardInput = editingState.noteInputEnabled || hasContinuousNoteInputCursor
        lastKeyboardInputCanReceiveAccidental = false
        performEditingAction(mutatesScore: false) { liveRenderSession in
            try await liveRenderSession.selectAdjacentElement(next: false)
        }
    }

    func selectNextElement() {
        shouldEditSelectedPitchBeforeContinuingKeyboardInput = editingState.noteInputEnabled || hasContinuousNoteInputCursor
        lastKeyboardInputCanReceiveAccidental = false
        performEditingAction(mutatesScore: false, revealActiveNotation: true) { liveRenderSession in
            try await liveRenderSession.selectAdjacentElement(next: true)
        }
    }

    func undoEdit() {
        performEditingAction(mutatesScore: true) { liveRenderSession in
            try await liveRenderSession.undoEdit()
        }
    }

    func redoEdit() {
        performEditingAction(mutatesScore: true) { liveRenderSession in
            try await liveRenderSession.redoEdit()
        }
    }

    func saveEdits() {
        guard
            supportsEditing,
            let liveRenderSession = session.liveRenderSession,
            !isEditingActionInFlight
        else {
            return
        }

        autosaveTask?.cancel()
        autosaveTask = nil
        isEditingActionInFlight = true
        editingErrorMessage = nil
        let destinationURL = session.document.url
        let saveRevision = autosaveRevision

        Task { @MainActor [weak self] in
            defer {
                self?.isEditingActionInFlight = false
            }

            do {
                try await liveRenderSession.save(to: destinationURL)
                if self?.autosaveRevision == saveRevision {
                    self?.hasUnsavedAutosaveChanges = false
                }
            } catch {
                self?.editingErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func performEditingAction(
        mutatesScore: Bool,
        auditionNote: Bool = false,
        revealActiveNotation: Bool = false,
        action: @escaping (LiveScoreRenderSession) async throws -> ScoreEditingState
    ) {
        guard
            supportsEditing,
            let liveRenderSession = session.liveRenderSession,
            !isEditingActionInFlight
        else {
            return
        }

        isEditingActionInFlight = true
        editingErrorMessage = nil

        Task { @MainActor [weak self] in
            defer {
                self?.isEditingActionInFlight = false
            }

            do {
                let newState = try await action(liveRenderSession)
                if mutatesScore {
                    self?.refreshAfterScoreMutation(with: newState, auditionNote: auditionNote, revealActiveNotation: revealActiveNotation)
                } else {
                    self?.applyEditingState(newState)
                    if revealActiveNotation {
                        self?.revealActiveSelection(in: newState)
                    }
                }
            } catch {
                self?.editingErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func applyEditingState(_ editingState: ScoreEditingState) {
        self.editingState = editingState
        let selectedChordPitchCount = editingState.selection?.chordMidiPitches.count ?? 0
        if selectedChordPitchCount > 1 {
            stackedChordInputEnabled = true
        } else {
            stackedChordInputEnabled = false
        }
        if !editingState.noteInputEnabled {
            noteEntryPreviewTask?.cancel()
            noteEntryPreview = nil
            lastKeyboardInputCanReceiveAccidental = false
        }
        if editingState.selection?.canChangePitch != true {
            shouldEditSelectedPitchBeforeContinuingKeyboardInput = false
        }
        editingErrorMessage = nil
    }

    func removeCachedLayoutMarker(for selection: ScoreSelectedElement?) {
        guard
            let selection,
            selection.kind == .layoutBreak,
            let layoutBreakKind = selection.layoutBreakKind,
            isValid(selection.pageIndex),
            let cachedPage = cachedPagesByIndex[selection.pageIndex],
            cachedPage.source == .liveMuseScoreRenderer
        else {
            return
        }

        let remainingMarkers = cachedPage.layoutMarkers.filter { marker in
            guard marker.kind == layoutBreakKind else {
                return true
            }

            return !normalizedRectsReferToSameMarker(marker.normalizedRect, selection.normalizedRect)
        }
        guard remainingMarkers.count != cachedPage.layoutMarkers.count else {
            return
        }

        cachedPagesByIndex[selection.pageIndex] = ScorePage(
            index: cachedPage.index,
            title: cachedPage.title,
            sourcePath: cachedPage.sourcePath,
            source: cachedPage.source,
            imageData: cachedPage.imageData,
            pdfData: cachedPage.pdfData,
            renderedSize: cachedPage.renderedSize,
            layoutMarkers: remainingMarkers
        )
    }

    func removeCachedLayoutMarkers() {
        for (pageIndex, cachedPage) in cachedPagesByIndex where cachedPage.source == .liveMuseScoreRenderer && !cachedPage.layoutMarkers.isEmpty {
            cachedPagesByIndex[pageIndex] = ScorePage(
                index: cachedPage.index,
                title: cachedPage.title,
                sourcePath: cachedPage.sourcePath,
                source: cachedPage.source,
                imageData: cachedPage.imageData,
                pdfData: cachedPage.pdfData,
                renderedSize: cachedPage.renderedSize,
                layoutMarkers: []
            )
        }
    }

    private func normalizedRectsReferToSameMarker(_ lhs: ScoreNormalizedRect, _ rhs: ScoreNormalizedRect) -> Bool {
        let dx = Double(lhs.center.x - rhs.center.x)
        let dy = Double(lhs.center.y - rhs.center.y)
        let centerDistance = hypot(dx, dy)
        let markerExtent = max(max(lhs.width, lhs.height), max(rhs.width, rhs.height))
        let tolerance = max(markerExtent, 0.018) * 1.75
        return centerDistance <= tolerance
    }

    func refreshAfterScoreMutation(with editingState: ScoreEditingState, auditionNote: Bool = false, revealActiveNotation: Bool = false) {
        let startedAt = Date()
        applyEditingState(editingState)
        let appliedAt = Date()
        if auditionNote {
            auditionSelectedNote(in: editingState)
        }
        if let pageCount = editingState.pageCount {
            activePageCount = max(pageCount, 0)
            selectedPageIndex = ScoreReaderState.boundedIndex(selectedPageIndex, pageCount: activePageCount)
        }
        if revealActiveNotation {
            revealActiveSelection(in: editingState)
        } else if let selectedPageIndex = editingState.selection?.pageIndex, isValid(selectedPageIndex) {
            self.selectedPageIndex = selectedPageIndex
        }
        invalidatePlaybackAfterScoreMutation()
        let playbackInvalidatedAt = Date()
        invalidateRenderedPages(
            scope: editingState.refreshScope,
            focusedPageIndex: editingState.selection?.pageIndex ?? selectedPageIndex
        )
        let pagesInvalidatedAt = Date()
        let saveDelay = autosaveDelay(for: editingState.refreshScope)
        scheduleAutosave(delay: saveDelay)
        let elapsed = Date().timeIntervalSince(startedAt)
        print(String(format: "Aria edit mutation applied: scope=%@ page=%d apply=%.3fs playbackInvalidate=%.3fs pageInvalidate=%.3fs total=%.3fs autosaveDelay=%@",
                     editingState.refreshScope.rawValue,
                     selectedPageIndex + 1,
                     appliedAt.timeIntervalSince(startedAt),
                     playbackInvalidatedAt.timeIntervalSince(appliedAt),
                     pagesInvalidatedAt.timeIntervalSince(playbackInvalidatedAt),
                     elapsed,
                     String(describing: saveDelay)))
    }

    func revealActiveSelection(in editingState: ScoreEditingState) {
        if let selectedPageIndex = editingState.selection?.pageIndex, isValid(selectedPageIndex) {
            self.selectedPageIndex = selectedPageIndex
        }
        activeNotationAutoScrollRevision += 1
    }

    func auditionSelectedNote(in editingState: ScoreEditingState) {
        guard editingState.selection?.kind == .note else {
            return
        }

        notePreviewController.play(
            midiPitches: editingState.selection?.chordMidiPitches,
            fallbackMIDIPitch: editingState.selection?.midiPitch,
            playbackBank: editingState.selection?.playbackBank,
            playbackProgram: editingState.selection?.playbackProgram,
            playbackSetupData: editingState.selection?.playbackSetupData
        )
    }

    func auditionMIDIPitch(_ midiPitch: Int, in editingState: ScoreEditingState) {
        notePreviewController.play(
            midiPitches: nil,
            fallbackMIDIPitch: midiPitch,
            playbackBank: editingState.selection?.playbackBank,
            playbackProgram: editingState.selection?.playbackProgram,
            playbackSetupData: editingState.selection?.playbackSetupData
        )
    }

    func auditionChordText(_ chordText: String, in editingState: ScoreEditingState) {
        guard let midiPitches = midiPitches(forChordText: chordText) else {
            auditionSelectedNote(in: editingState)
            return
        }

        notePreviewController.play(
            midiPitches: midiPitches,
            fallbackMIDIPitch: nil,
            playbackBank: editingState.selection?.playbackBank,
            playbackProgram: editingState.selection?.playbackProgram,
            playbackSetupData: editingState.selection?.playbackSetupData
        )
    }

    private func midiPitches(forChordText chordText: String) -> [Int]? {
        let trimmed = chordText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let root = chordRootPitchClass(in: trimmed) else {
            return nil
        }

        let normalized = trimmed
            .replacingOccurrences(of: "♭", with: "b")
            .replacingOccurrences(of: "♯", with: "#")
        let suffixStart = normalized.index(after: normalized.startIndex)
        let suffix: String
        if normalized.indices.contains(suffixStart), normalized[suffixStart] == "#" || normalized[suffixStart] == "b" {
            suffix = String(normalized[normalized.index(after: suffixStart)...])
        } else {
            suffix = String(normalized[suffixStart...])
        }

        let intervals = chordIntervals(for: suffix)
        return intervals.map { min(127, 60 + root + $0) }
    }

    private func chordRootPitchClass(in chordText: String) -> Int? {
        let normalized = chordText
            .replacingOccurrences(of: "♭", with: "b")
            .replacingOccurrences(of: "♯", with: "#")
        guard let first = normalized.first else {
            return nil
        }

        let basePitchClass: Int
        switch String(first).uppercased() {
        case "C": basePitchClass = 0
        case "D": basePitchClass = 2
        case "E": basePitchClass = 4
        case "F": basePitchClass = 5
        case "G": basePitchClass = 7
        case "A": basePitchClass = 9
        case "B": basePitchClass = 11
        default: return nil
        }

        let secondIndex = normalized.index(after: normalized.startIndex)
        guard normalized.indices.contains(secondIndex) else {
            return basePitchClass
        }

        if normalized[secondIndex] == "#" {
            return (basePitchClass + 1) % 12
        }
        if normalized[secondIndex] == "b" {
            return (basePitchClass + 11) % 12
        }
        return basePitchClass
    }

    private func chordIntervals(for suffix: String) -> [Int] {
        let lowercaseSuffix = suffix.lowercased()
        var intervals: [Int]
        if lowercaseSuffix.hasPrefix("maj")
            || lowercaseSuffix.hasPrefix("major")
            || suffix.hasPrefix("M")
            || suffix.hasPrefix("^")
            || suffix.hasPrefix("△") {
            intervals = [0, 4, 7]
        } else if lowercaseSuffix.hasPrefix("min")
            || lowercaseSuffix.hasPrefix("mi")
            || lowercaseSuffix.hasPrefix("-")
            || lowercaseSuffix.hasPrefix("=")
            || (lowercaseSuffix.hasPrefix("m") && !lowercaseSuffix.hasPrefix("maj") && !lowercaseSuffix.hasPrefix("major")) {
            intervals = [0, 3, 7]
        } else if lowercaseSuffix.hasPrefix("ø") {
            intervals = [0, 3, 6, 10]
        } else if lowercaseSuffix.hasPrefix("°") || lowercaseSuffix.hasPrefix("dim") {
            intervals = [0, 3, 6]
        } else if lowercaseSuffix.hasPrefix("+") || lowercaseSuffix.hasPrefix("aug") {
            intervals = [0, 4, 8]
        } else if lowercaseSuffix.hasPrefix("sus") {
            intervals = [0, 5, 7]
        } else {
            intervals = [0, 4, 7]
        }

        if lowercaseSuffix.contains("maj7") || lowercaseSuffix.contains("major7") || lowercaseSuffix.contains("△7") {
            intervals.append(11)
        } else if lowercaseSuffix.contains("7") || lowercaseSuffix.contains("9") || lowercaseSuffix.contains("11") || lowercaseSuffix.contains("13") {
            intervals.append(10)
        } else if lowercaseSuffix.contains("6") {
            intervals.append(9)
        }

        if lowercaseSuffix.contains("b5"), let index = intervals.firstIndex(of: 7) {
            intervals[index] = 6
        } else if lowercaseSuffix.contains("#5"), let index = intervals.firstIndex(of: 7) {
            intervals[index] = 8
        }

        if lowercaseSuffix.contains("9") {
            intervals.append(lowercaseSuffix.contains("b9") ? 13 : (lowercaseSuffix.contains("#9") ? 15 : 14))
        }
        if lowercaseSuffix.contains("11") {
            intervals.append(lowercaseSuffix.contains("#11") ? 18 : 17)
        }
        if lowercaseSuffix.contains("13") {
            intervals.append(lowercaseSuffix.contains("b13") ? 20 : 21)
        }

        return Array(Set(intervals)).sorted()
    }
}
