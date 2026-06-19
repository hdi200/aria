//
//  ScoreReaderView.swift
//  MuseReaderiOS
//
//

import SwiftUI
import UIKit
import AVFoundation

struct ScoreReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    let session: ScoreSession

    @StateObject private var readerState: ScoreReaderState
    @State private var zoomScale: CGFloat = UIDevice.current.userInterfaceIdiom == .phone ? 2.2 : 1.0
    @State private var lastPhoneLandscapeZoomMode: Bool?
    @State private var selectedToolCategory: ScoreReaderToolCategory = .select
    @State private var textEditorDraft: ScoreReaderTextEditorDraft?
    @State private var isPartsPanelPresented = false
    @State private var isExportPanelPresented = false
    @State private var exportDraft = ScoreReaderExportDraft()
    @State private var sharedExportItems: ScoreReaderSharedExportItems?
    @State private var exportErrorMessage: String?
    @State private var isPreparingExport = false
    @State private var selectedPartID = "full-score"
    @State private var isTempoEditorPresented = false
    @State private var isTimeSignaturePresented = false
    @State private var isKeySignaturePresented = false
    @State private var isScoreSetupPresented = false
    @State private var isStaffSpacingPresented = false
    @State private var isPageSettingsPresented = false
    @State private var isAddMeasuresPresented = false
    @State private var isAutoBreaksPresented = false
    @State private var isAddInstrumentPresented = false
    @State private var isClefPickerPresented = false
    @State private var instrumentsToAdd: [NewScoreInstrument] = []
    @State private var currentScoreInstruments: [NewScoreInstrument] = []
    @State private var selectionCommandAnchor: ScoreReaderSelectionCommandAnchor?
    @State private var dismissedSelectionCommandIdentity: String?
    @State private var pencilAutoNoteEntryAllowed = true
    @State private var zoomScaleBeforeTextEntry: CGFloat?
    @State private var isClosingScore = false
    @State private var measuredNoteEntryPanelHeight: CGFloat = 0
    @State private var measuredTopChromeHeight: CGFloat = 0

    init(session: ScoreSession, initialPageIndex: Int) {
        self.session = session
        _readerState = StateObject(wrappedValue: ScoreReaderState(session: session, initialPageIndex: initialPageIndex))
    }

    var body: some View {
        ZStack {
            ScoreReaderBackground()

            if readerState.pageCount == 0 {
                ScoreReaderUnavailableView(detailText: session.renderPipeline.detailText)
                    .padding(28)
            } else {
                readerCanvas
                    .overlay(alignment: .bottom) {
                        if readerState.supportsEditing && !plainTextEditorIsActive {
                            ScoreReaderNoteEntrySurface(
                                editingState: readerState.editingState,
                                pendingPitchClass: readerState.pendingPitchClass,
                                pendingMIDIPitch: readerState.pendingMIDIPitch,
                                stackedChordInputEnabled: readerState.stackedChordInputEnabled,
                                isBusy: readerState.isEditingActionInFlight,
                                errorText: nil,
                                selectModeAction: selectModeFromToolbar,
                                noteInputModeAction: noteInputModeFromToolbar,
                                deleteSelectionAction: readerState.deleteSelection,
                                clearSelectedMeasureAction: readerState.clearSelectedMeasure,
                                removeSelectedMeasureAction: readerState.removeSelectedMeasure,
                                addMeasureAction: readerState.addMeasure,
                                addMultipleMeasuresAction: { isAddMeasuresPresented = true },
                                copySelectedMeasureRangeAction: readerState.copySelectedMeasureRange,
                                cutSelectedMeasureRangeAction: readerState.cutSelectedMeasureRange,
                                pasteMeasureRangeAction: readerState.pasteMeasureRange,
                                selectPreviousElementAction: readerState.selectPreviousElement,
                                selectNextElementAction: readerState.selectNextElement,
                                undoAction: readerState.undoEdit,
                                redoAction: readerState.redoEdit,
                                setCurrentVoiceAction: readerState.setCurrentVoice,
                                selectedToolCategory: $selectedToolCategory,
                                pendingAccidentalKind: readerState.pendingAccidentalKind,
                                applyDurationAction: readerState.applyDuration,
                                toggleDotAction: readerState.toggleDot,
                                toggleRestAction: readerState.toggleRest,
                                toggleTieAction: readerState.toggleTie,
                                addTupletAction: readerState.addTuplet,
                                toggleStackedChordInputAction: readerState.toggleStackedChordInput,
                                editSelectedTextAction: presentTextEditor,
                                addTextAction: readerState.addText,
                                addChordTextAction: readerState.addChordText,
                                addChordTextAndSelectNextAction: readerState.addChordTextAndSelectNext,
                                openLyricsEntryAction: openLyricsEntry,
                                addLyricsTextAction: readerState.addLyricsText,
                                addRepeatJumpAction: readerState.addRepeatJump,
                                addExpressionAction: readerState.addExpression,
                                addLayoutBreakAction: readerState.addLayoutBreak,
                                removeLayoutBreakAction: readerState.removeLayoutBreak,
                                updateLayoutOptionsAction: readerState.updateLayoutOptions,
                                fillSelectionWithSlashesAction: readerState.fillSelectionWithSlashes,
                                replaceSelectionWithRhythmicSlashesAction: readerState.replaceSelectionWithRhythmicSlashes,
                                openAddInstrumentAction: {
                                    instrumentsToAdd = []
                                    if currentScoreInstruments.isEmpty {
                                        currentScoreInstruments = scoreInstrumentsFromDocumentParts()
                                    }
                                    isAddInstrumentPresented = true
                                },
                                removeSelectedInstrumentAction: readerState.removeSelectedInstrument,
                                openClefEditorAction: { isClefPickerPresented = true },
                                openAutoBreaksAction: { isAutoBreaksPresented = true },
                                openStaffSpacingAction: { isStaffSpacingPresented = true },
                                openPageSettingsAction: { isPageSettingsPresented = true },
                                openScoreSetupAction: { isScoreSetupPresented = true },
                                openTempoEditorAction: { isTempoEditorPresented = true },
                                openTimeSignatureAction: { isTimeSignaturePresented = true },
                                openKeySignatureAction: { isKeySignaturePresented = true },
                                openPickupMeasureAction: { readerState.presentPickupEditor(createNewMeasure: false) },
                                openCreatePickupMeasureAction: { readerState.presentPickupEditor(createNewMeasure: true) },
                                concertPitchEnabled: readerState.concertPitchEnabled,
                                showsConcertPitchControl: showsConcertPitchControl,
                                toggleConcertPitchAction: readerState.toggleConcertPitch,
                                setKeyboardPitchAction: { pitchClass, midiPitch, preferFlats in
                                    readerState.handleKeyboardPitch(pitchClass, midiPitch: midiPitch, preferFlats: preferFlats, exactMIDIPitch: true)
                                },
                                setPitchClassAction: readerState.handleKeyboardPitchClass,
                                prepareAccidentalAction: readerState.prepareAccidental,
                                semitoneShiftAction: readerState.shiftPitchBySemitones,
                                octaveShiftAction: readerState.shiftPitchByOctaves
                            )
                            .padding(.bottom, 0)
                            .background(
                                GeometryReader { proxy in
                                    Color.clear
                                        .onAppear { measuredNoteEntryPanelHeight = proxy.size.height }
                                        .onChange(of: proxy.size.height) { _, newHeight in
                                            measuredNoteEntryPanelHeight = newHeight
                                        }
                                }
                            )
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if let floatingToolCategory, readerState.supportsEditing, !isPhoneInterface {
                            ScoreReaderFloatingToolPalette(
                                selectedToolCategory: floatingToolCategory,
                                editingState: readerState.editingState,
                                pendingPitchClass: readerState.pendingPitchClass,
                                pendingAccidentalKind: readerState.pendingAccidentalKind,
                                isBusy: readerState.isEditingActionInFlight,
                                applyDurationAction: readerState.applyDuration,
                                toggleDotAction: readerState.toggleDot,
                                toggleRestAction: readerState.toggleRest,
                                toggleTieAction: readerState.toggleTie,
                                addTupletAction: readerState.addTuplet,
                                deleteSelectionAction: readerState.deleteSelection,
                                addTextAction: readerState.addText,
                                openChordEntryAction: openChordEntry,
                                openLyricsEntryAction: openLyricsEntry,
                                addRepeatJumpAction: readerState.addRepeatJump,
                                addExpressionAction: readerState.addExpression,
                                setPitchClassAction: readerState.handleKeyboardPitchClass,
                                prepareAccidentalAction: readerState.prepareAccidental,
                                openTempoEditorAction: { isTempoEditorPresented = true }
                            )
                            .padding(.top, floatingPaletteTopPadding)
                            .padding(.trailing, 16)
                        }
                    }
                    .overlay(alignment: .top) {
                        ScoreReaderChromeBar(
                            scoreTitle: session.document.primaryTitle,
                            parts: session.document.parts,
                            selectedPartID: $selectedPartID,
                            isPartsPanelPresented: $isPartsPanelPresented,
                            isExportPanelPresented: $isExportPanelPresented,
                            supportsEditing: readerState.supportsEditing,
                            supportsPlayback: session.capabilities.supportsPlayback,
                            editingState: readerState.editingState,
                            playbackState: readerState.playbackState,
                            metronomeEnabled: readerState.metronomeEnabled,
                            isEditingBusy: readerState.isEditingActionInFlight || isClosingScore,
                            isPlaybackBusy: readerState.isPlaybackActionInFlight,
                            playbackPreparationMessage: readerState.playbackPreparationMessage,
                            concertPitchEnabled: readerState.concertPitchEnabled,
                            showsConcertPitchControl: showsChromeConcertPitchControl,
                            closeAction: closeReader,
                            selectModeAction: selectModeFromToolbar,
                            noteInputModeAction: noteInputModeFromToolbar,
                            togglePlaybackAction: readerState.togglePlayback,
                            stopPlaybackAction: readerState.stopPlayback,
                            toggleMetronomeAction: readerState.toggleMetronome,
                            toggleConcertPitchAction: readerState.toggleConcertPitch,
                            exportAction: {
                                isPartsPanelPresented = false
                                if !isExportPanelPresented {
                                    exportDraft.exportPartsInConcertPitch = readerState.concertPitchEnabled
                                }
                                isExportPanelPresented.toggle()
                            },
                            selectPartAction: { partIndex in
                                readerState.selectScorePart(index: partIndex)
                            },
                            managePartsAction: {
                                isPartsPanelPresented = false
                                instrumentsToAdd = []
                                if currentScoreInstruments.isEmpty {
                                    currentScoreInstruments = scoreInstrumentsFromDocumentParts()
                                }
                                isAddInstrumentPresented = true
                            },
                            exportPanelContent: {
                                AnyView(
                                    ScoreReaderExportPanel(
                                        scoreTitle: session.document.primaryTitle,
                                        parts: session.document.parts,
                                        draft: $exportDraft,
                                        isPreparingExport: isPreparingExport,
                                        cancelAction: { isExportPanelPresented = false },
                                        exportAction: exportScore
                                    )
                                )
                            }
                        )
                        .background(
                            GeometryReader { proxy in
                                Color.clear
                                    .onAppear { measuredTopChromeHeight = proxy.size.height }
                                    .onChange(of: proxy.size.height) { _, newHeight in
                                        measuredTopChromeHeight = newHeight
                                    }
                            }
                        )
                    }
                    .overlay(alignment: .top) {
                        if let playbackPreparationMessage = readerState.playbackPreparationMessage {
                            ScoreReaderPlaybackPreparationHUD(message: playbackPreparationMessage)
                                .padding(.top, 88)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if readerState.isRepairingCorruption {
                            ScoreReaderCorruptionMenu(
                                report: readerState.corruptionReport,
                                isBusy: readerState.isEditingActionInFlight,
                                selectIssueAction: readerState.selectCorruptionIssue,
                                clearIssueAction: readerState.clearCorruptionIssue
                            )
                            .padding(.top, isPhoneInterface ? 72 : 84)
                            .padding(.trailing, isPhoneInterface ? 12 : 24)
                            .padding(.leading, isPhoneInterface ? 12 : 0)
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if let selectionCommandAnchor, readerState.supportsEditing {
                            ScoreReaderSelectionCommandOverlay(
                                anchor: selectionCommandAnchor,
                                copyAction: readerState.copySelectedMeasureRange,
                                cutAction: readerState.cutSelectedMeasureRange,
                                pasteAction: readerState.pasteMeasureRange,
                                deleteSelectionAction: readerState.deleteSelection,
                                clearSelectedMeasureAction: readerState.clearSelectedMeasure,
                                removeSelectedMeasureAction: readerState.removeSelectedMeasure,
                                addMeasureAction: readerState.addMeasure,
                                addMultipleMeasuresAction: { isAddMeasuresPresented = true },
                                transposeAction: readerState.transposeSelectedMeasureRange,
                                keySignatureAction: { isKeySignaturePresented = true },
                                timeSignatureAction: { isTimeSignaturePresented = true },
                                tempoAction: { isTempoEditorPresented = true },
                                pickupMeasureAction: { readerState.presentPickupEditor(createNewMeasure: false) },
                                accentAction: readerState.addExpression,
                                dismissAction: dismissSelectionCommandMenu
                            )
                            .zIndex(100)
                        }
                    }
                    .overlay(alignment: .center) {
                        if isClosingScore {
                            ScoreReaderSavingHUD()
                        }
                    }
                    .allowsHitTesting(!isClosingScore)
            }
        }
        .task {
            readerState.loadInitialPages()
            readerState.loadConcertPitchState()
            readerState.startPlaybackMonitoring()
            readerState.loadEditingState()
            readerState.startMIDIInput()
        }
        .onDisappear {
            readerState.stopMIDIInput()
            readerState.shutdown()
        }
        .onChange(of: readerState.editingState.noteInputEnabled) { _, noteInputEnabled in
            if noteInputEnabled {
                selectedToolCategory = .notes
            } else if selectedToolCategory == .notes && readerState.editingState.selection?.kind != .measure {
                selectedToolCategory = .select
            }
        }
        .onChange(of: readerState.editingState.selection?.kind) { _, selectionKind in
            if selectionKind == nil {
                clearSelectionCommandMenu()
            }

            if selectionKind == .measure && selectedToolCategory == .select {
                readerState.setNoteInputEnabled(false)
                selectedToolCategory = .notes
            } else if selectedToolCategory == .repeats && selectionKind == nil {
                selectedToolCategory = .select
            }
        }
        .onAppear {
            if currentScoreInstruments.isEmpty {
                currentScoreInstruments = scoreInstrumentsFromDocumentParts()
            }
        }
        .sheet(item: $textEditorDraft) { draft in
            ScoreReaderTextEditSheet(
                draft: draft,
                isBusy: readerState.isEditingActionInFlight,
                commitAction: { text, advanceToNextChord in
                    if draft.isLyrics {
                        readerState.addLyricsText(text, advanceToNextChord: advanceToNextChord)
                    } else {
                        readerState.setSelectedText(text)
                    }
                    if !advanceToNextChord {
                        textEditorDraft = nil
                    }
                }
            )
        }
        .sheet(item: $sharedExportItems) { export in
            ScoreReaderShareSheetView(activityItems: export.urls)
        }
        .sheet(isPresented: $isTempoEditorPresented) {
            ScoreReaderTempoEditorSheet(
                isBusy: readerState.isEditingActionInFlight,
                commitAction: readerState.addTempo
            )
        }
        .sheet(isPresented: $isTimeSignaturePresented) {
            ScoreReaderTimeSignatureSheet(
                isBusy: readerState.isEditingActionInFlight,
                commitAction: readerState.updateTimeSignature
            )
        }
        .sheet(isPresented: $isKeySignaturePresented) {
            ScoreReaderKeySignatureSheet(
                currentKeyValue: readerState.editingState.selection?.currentKey ?? 0,
                isBusy: readerState.isEditingActionInFlight,
                commitAction: readerState.updateKeySignature
            )
        }
        .sheet(item: $readerState.pickupEditorContext) { context in
            ScoreReaderPickupEditorSheet(
                context: context,
                isBusy: readerState.isEditingActionInFlight,
                applyAction: { numerator, denominator in
                    readerState.applyPickupMeasure(numerator: numerator, denominator: denominator)
                },
                removeAction: readerState.removePickupMeasure
            )
        }
        .sheet(isPresented: $isScoreSetupPresented) {
            ScoreReaderSetupSheet(
                metadata: ScoreEditableMetadata(document: session.document),
                isBusy: readerState.isEditingActionInFlight,
                commitAction: readerState.updateScoreSetupMetadata
            )
        }
        .sheet(isPresented: $isStaffSpacingPresented) {
            ScoreReaderStaffSpacingSheet(
                isBusy: readerState.isEditingActionInFlight,
                commitAction: readerState.updateStaffSpacing
            )
        }
        .sheet(isPresented: $isPageSettingsPresented) {
            ScoreReaderPageSettingsSheet(
                isBusy: readerState.isEditingActionInFlight,
                commitAction: readerState.updatePageLayout
            )
        }
        .sheet(isPresented: $isAutoBreaksPresented) {
            ScoreReaderAutoSystemBreaksSheet(
                isBusy: readerState.isEditingActionInFlight,
                commitAction: readerState.applyAutoSystemBreaks
            )
        }
        .sheet(isPresented: $isAddMeasuresPresented) {
            ScoreReaderAddMeasuresSheet(
                isBusy: readerState.isEditingActionInFlight,
                commitAction: { count in
                    readerState.addMeasures(count)
                    isAddMeasuresPresented = false
                }
            )
        }
        .fullScreenCover(isPresented: $isAddInstrumentPresented) {
            AddInstrumentSheet(
                selectedInstruments: $instrumentsToAdd,
                currentInstruments: $currentScoreInstruments,
                showsCurrentInstruments: true,
                addCurrentInstrumentAction: { instrument in
                    readerState.addInstrument(instrument)
                },
                removeCurrentInstrumentAction: { index, _ in
                    readerState.removeInstrument(at: index)
                },
                moveCurrentInstrumentAction: { source, destination in
                    readerState.moveInstrument(from: source, to: destination)
                }
            )
        }
        .confirmationDialog("Change Clef", isPresented: $isClefPickerPresented, titleVisibility: .visible) {
            Button("Treble Clef") { readerState.changeClef("Treble") }
            Button("Alto Clef") { readerState.changeClef("Alto") }
            Button("Tenor Clef") { readerState.changeClef("Tenor") }
            Button("Bass Clef") { readerState.changeClef("Bass") }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Export Failed", isPresented: exportErrorIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage ?? "Aria could not export this score.")
        }
        // Drive the hidden state from scenePhase so locking/unlocking forces
        // SwiftUI to re-push preferredStatusBarHidden. Otherwise the bar can stay
        // collapsed after unlock and the library underlaps the status bar.
        .statusBarHidden(scenePhase == .active)
    }

    private var floatingToolCategory: ScoreReaderToolCategory? {
        guard !isPhoneInterface else {
            return nil
        }

        if selectedToolCategory == .chord || selectedToolCategory == .lyrics {
            return nil
        }

        if selectedToolCategory != .select {
            return selectedToolCategory
        }

        guard let selection = readerState.editingState.selection else {
            return nil
        }

        switch selection.kind {
        case .note, .rest:
            return .notes
        case .bar:
            return .repeats
        case .measure:
            return .notes
        case .text, .chordText:
            return .text
        case .tempo, .timeSignature, .keySignature:
            return .more
        case .dynamic, .expressionSpanner:
            return .expression
        case .other:
            return .expression
        }
    }

    private var showsConcertPitchControl: Bool {
        readerState.supportsEditing
            && session.liveRenderSession != nil
            && (readerState.concertPitchEnabled || readerState.hasConcertPitchRelevantTransposition)
    }

    private var showsChromeConcertPitchControl: Bool {
        showsConcertPitchControl && !isPhoneInterface
    }

    private var isPhoneInterface: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    private var floatingPaletteTopPadding: CGFloat {
        let bounds = UIScreen.main.bounds
        if floatingToolCategory == .notes && bounds.width > bounds.height {
            return 108
        }
        return 148
    }

    private var floatingPanelTopPadding: CGFloat {
        isPhoneInterface ? 72 : 54
    }

    private var readerCanvas: some View {
        GeometryReader { geometry in
            let isCompactPhoneLayout = isPhoneInterface
            let isPhoneLandscapeLayout = isCompactPhoneLayout && geometry.size.width > geometry.size.height
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 28) {
                        ForEach(readerState.pageIndices, id: \.self) { pageIndex in
                            ScoreReaderPageCanvas(
                                pageIndex: pageIndex,
                                page: readerState.page(at: pageIndex),
                                isLoading: readerState.isLoadingPage(pageIndex),
                                errorText: readerState.pageErrorMessage(for: pageIndex),
                                playbackHighlight: readerState.playbackMeasureHighlight(for: pageIndex),
                                selectedElement: readerState.selectedElement(for: pageIndex),
                                noteEntryPreview: readerState.noteEntryPreview(for: pageIndex),
                                zoomScale: $zoomScale,
                                availableWidth: geometry.size.width - (isCompactPhoneLayout ? 0 : 48),
                                viewportSize: geometry.size,
                                isCompactPhoneLayout: isCompactPhoneLayout,
                                activeNotationTopInset: activeNotationTopInset(isCompactPhoneLayout: isCompactPhoneLayout),
                                activeNotationBottomInset: activeNotationBottomInset(isCompactPhoneLayout: isCompactPhoneLayout, isPhoneLandscapeLayout: isPhoneLandscapeLayout),
                                allowsPencilInsertionFineTune: readerState.editingState.noteInputEnabled,
                                noteEntryPreviewPitchClass: readerState.pendingPitchClass,
                                noteEntryPreviewIsRest: readerState.editingState.noteInputInsertsRests,
                                noteEntryPreviewDuration: readerState.editingState.duration,
                                showsLayoutMarkers: selectedToolCategory == .layout,
                                activeNotationAutoScrollRevision: readerState.activeNotationAutoScrollRevision,
                                editSelectedTextAction: presentTextEditor,
                                editTempoAction: { isTempoEditorPresented = true },
                                editTimeSignatureAction: { isTimeSignaturePresented = true },
                                editKeySignatureAction: { isKeySignaturePresented = true },
                                deleteSelectionAction: readerState.deleteSelection,
                                clearSelectedMeasureAction: readerState.clearSelectedMeasure,
                                removeSelectedMeasureAction: readerState.removeSelectedMeasure,
                                addMeasureAction: readerState.addMeasure,
                                addMultipleMeasuresAction: { isAddMeasuresPresented = true },
                                copySelectedMeasureRangeAction: readerState.copySelectedMeasureRange,
                                cutSelectedMeasureRangeAction: readerState.cutSelectedMeasureRange,
                                pasteMeasureRangeAction: readerState.pasteMeasureRange,
                                transposeSelectedMeasureRangeAction: readerState.transposeSelectedMeasureRange,
                                addExpressionAction: readerState.addExpression,
                                tapAction: { normalizedPoint, inputKind in
                                    clearSelectionCommandMenu()
                                    readerState.handlePageTap(
                                        pageIndex: pageIndex,
                                        normalizedPoint: normalizedPoint,
                                        inputKind: inputKind
                                    )
                                },
                                selectedNoteDragAction: { dropPoint in
                                    readerState.dragSelectedNote(pageIndex: pageIndex, normalizedPoint: dropPoint)
                                },
                                expressionEndpointDragAction: { startEndpoint, dropPoint in
                                    readerState.retargetSelectedExpressionEndpoint(
                                        start: startEndpoint,
                                        pageIndex: pageIndex,
                                        normalizedPoint: dropPoint
                                    )
                                },
                                selectedChordTextDragAction: { dropPoint in
                                    readerState.dragSelectedChordText(pageIndex: pageIndex, normalizedPoint: dropPoint)
                                },
                                measureRangeDragAction: { startPoint, endPoint in
                                    readerState.selectMeasureRange(
                                        pageIndex: pageIndex,
                                        startNormalizedPoint: startPoint,
                                        endNormalizedPoint: endPoint
                                    )
                                },
                                pencilInsertionFineTuneAction: { startPoint, dropPoint in
                                    readerState.handlePencilNoteEntryFineTune(
                                        pageIndex: pageIndex,
                                        startNormalizedPoint: startPoint,
                                        dropNormalizedPoint: dropPoint
                                    )
                                },
                                pencilHoverPreviewAction: { normalizedPoint in
                                    readerState.updateNoteEntryPreview(
                                        pageIndex: pageIndex,
                                        normalizedPoint: normalizedPoint
                                    )
                                },
                                pencilInteractionStartAction: activatePencilNoteEntryMode,
                                pencilDoubleTapAction: toggleNoteInputFromPencilDoubleTap
                            )
                            .id(pageIndex)
                            .onAppear {
                                readerState.prefetchPage(pageIndex)
                            }
                        }
                    }
                    .padding(.top, readerState.supportsEditing ? (isCompactPhoneLayout ? 82 : 104) : 92)
                    .padding(.bottom, scrollContentBottomInset(isCompactPhoneLayout: isCompactPhoneLayout, isPhoneLandscapeLayout: isPhoneLandscapeLayout))
                    .padding(.horizontal, isCompactPhoneLayout ? 0 : 24)
                }
                .coordinateSpace(name: ScoreReaderSelectionCommandAnchor.coordinateSpaceName)
                .onPreferenceChange(ScoreReaderSelectionCommandAnchorPreferenceKey.self) { anchor in
                    if anchor?.identity != dismissedSelectionCommandIdentity {
                        selectionCommandAnchor = anchor
                    }
                }
                .task {
                    applyPreferredPhoneZoomIfNeeded(for: geometry.size)
                    proxy.scrollTo(readerState.selectedPageIndex, anchor: .top)
                }
                .onChange(of: geometry.size) { _, newSize in
                    applyPreferredPhoneZoomIfNeeded(for: newSize)
                }
                .onChange(of: readerState.selectedPageIndex) { _, newValue in
                    if activeNotationFocusIsActive, readerState.editingState.selection?.pageIndex == newValue {
                        revealActiveNotation(using: proxy)
                        DispatchQueue.main.async {
                            revealActiveNotation(using: proxy)
                        }
                        return
                    }

                    guard readerState.playbackState.status == .playing || readerState.isRepairingCorruption else {
                        return
                    }

                    withAnimation(.easeInOut(duration: 0.24)) {
                        proxy.scrollTo(newValue, anchor: .top)
                    }
                }
                .onChange(of: readerState.activeNotationAutoScrollRevision) { _, _ in
                    revealActiveNotation(using: proxy)
                    DispatchQueue.main.async {
                        revealActiveNotation(using: proxy)
                    }
                }
                .onChange(of: selectedToolCategory) { oldValue, newValue in
                    handleToolCategoryChange(from: oldValue, to: newValue)
                }
            }
        }
    }

    private func revealActiveNotation(using proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.22)) {
            if activeNotationFocusIsActive, readerState.editingState.selection?.pageIndex == readerState.selectedPageIndex {
                // The anchor is placed so the selected bar lands in the middle
                // of the visible area between the chrome and entry controls.
                proxy.scrollTo(ScoreReaderPageCanvas.activeNotationAnchorID(for: readerState.selectedPageIndex), anchor: .top)
            } else {
                proxy.scrollTo(readerState.selectedPageIndex, anchor: .center)
            }
        }
    }

    private var scrollContentBottomInset: CGFloat {
        scrollContentBottomInset(isCompactPhoneLayout: false, isPhoneLandscapeLayout: false)
    }

    private var textEntryFocusIsActive: Bool {
        selectedToolCategory == .chord || selectedToolCategory == .lyrics
    }

    private var plainTextEditorIsActive: Bool {
        guard let textEditorDraft else {
            return false
        }

        return !textEditorDraft.isChordText && !textEditorDraft.isLyrics
    }

    /// Whether auto-scroll should keep the selected bar inside the unobstructed
    /// viewport. Active for chord/lyric entry and for continuous note input,
    /// where the bottom note-entry keyboard can otherwise hide the active bar.
    private var activeNotationFocusIsActive: Bool {
        guard readerState.supportsEditing else {
            return false
        }

        return textEntryFocusIsActive || readerState.editingState.noteInputEnabled
    }

    private func scrollContentBottomInset(isCompactPhoneLayout: Bool, isPhoneLandscapeLayout: Bool) -> CGFloat {
        guard readerState.supportsEditing else {
            return 40
        }

        if plainTextEditorIsActive {
            return 40
        }

        if isPhoneLandscapeLayout {
            if selectedToolCategory == .chord || selectedToolCategory == .lyrics {
                return 88
            }
            return 126
        }

        if isCompactPhoneLayout {
            if selectedToolCategory == .chord || selectedToolCategory == .lyrics {
                return 118
            }
            return 250
        }

        return 190
    }

    private func activeNotationTopInset(isCompactPhoneLayout: Bool) -> CGFloat {
        if textEntryFocusIsActive {
            return isCompactPhoneLayout ? 86 : 118
        }

        guard activeNotationFocusIsActive else {
            return 0
        }

        return measuredTopChromeHeight > 0 ? measuredTopChromeHeight : (isCompactPhoneLayout ? 82 : 104)
    }

    private func activeNotationBottomInset(isCompactPhoneLayout: Bool, isPhoneLandscapeLayout: Bool) -> CGFloat {
        if textEntryFocusIsActive {
            let entryPanelHeight = scrollContentBottomInset(
                isCompactPhoneLayout: isCompactPhoneLayout,
                isPhoneLandscapeLayout: isPhoneLandscapeLayout
            )
            let keyboardHeight = textEntryKeyboardHeight(isCompactPhoneLayout: isCompactPhoneLayout, isPhoneLandscapeLayout: isPhoneLandscapeLayout)
            return entryPanelHeight + keyboardHeight
        }

        guard activeNotationFocusIsActive else {
            return 0
        }

        // The live measured height of the note-entry panel keeps the math correct
        // across iPad/iPhone and portrait/landscape without per-layout constants.
        if measuredNoteEntryPanelHeight > 0 {
            return measuredNoteEntryPanelHeight + 12
        }

        return scrollContentBottomInset(
            isCompactPhoneLayout: isCompactPhoneLayout,
            isPhoneLandscapeLayout: isPhoneLandscapeLayout
        )
    }

    private func textEntryKeyboardHeight(isCompactPhoneLayout: Bool, isPhoneLandscapeLayout: Bool) -> CGFloat {
        if selectedToolCategory == .chord {
            return isCompactPhoneLayout ? 226 : 382
        }

        if isCompactPhoneLayout {
            return isPhoneLandscapeLayout ? 220 : 336
        }

        return 360
    }

    private func applyPreferredPhoneZoomIfNeeded(for size: CGSize) {
        guard isPhoneInterface, zoomScaleBeforeTextEntry == nil, size.width > 0, size.height > 0 else {
            return
        }

        let isLandscape = size.width > size.height
        guard lastPhoneLandscapeZoomMode != isLandscape else {
            return
        }

        lastPhoneLandscapeZoomMode = isLandscape
        zoomScale = isLandscape ? 1.2 : 2.2
    }

    private func closeReader() {
        guard !isClosingScore else {
            return
        }

        isClosingScore = true
        Task { @MainActor in
            let canClose = await readerState.saveBeforeClosing()
            isClosingScore = false
            if canClose {
                dismiss()
            }
        }
    }

    private func exportScore() {
        guard !isPreparingExport else {
            return
        }

        isPreparingExport = true
        exportErrorMessage = nil

        Task {
            do {
                let urls = try await prepareExportURLs()
                await MainActor.run {
                    sharedExportItems = ScoreReaderSharedExportItems(urls: urls)
                    isPreparingExport = false
                    isExportPanelPresented = false
                }
            } catch {
                await MainActor.run {
                    exportErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    isPreparingExport = false
                }
            }
        }
    }

    private func prepareExportURLs() async throws -> [URL] {
        switch exportDraft.format {
        case .museScore:
            return [try await writeMuseScoreExport()]
        case .pdf:
            return try await writePDFExports()
        case .musicXML:
            return try await writeMusicXMLExports()
        case .midi:
            return [try await writeMIDIExport()]
        case .audio:
            return try await writeAudioExports()
        case .images:
            return try await writePNGPageExports()
        }
    }

    private func writeMuseScoreExport() async throws -> URL {
        let exportURL = try Self.exportURL(
            baseName: exportDraft.fileName,
            extension: "mscz"
        )

        if let liveRenderSession = session.liveRenderSession {
            try await liveRenderSession.save(to: exportURL)
        } else {
            if FileManager.default.fileExists(atPath: exportURL.path) {
                try FileManager.default.removeItem(at: exportURL)
            }
            try FileManager.default.copyItem(at: session.document.url, to: exportURL)
        }

        return exportURL
    }

    private func writeMIDIExport() async throws -> URL {
        guard let liveRenderSession = session.liveRenderSession else {
            throw ScoreReaderExportError.unsupportedFormat("MIDI")
        }

        let midiData = try await liveRenderSession.playbackMIDIData()
        let exportURL = try Self.exportURL(baseName: exportDraft.fileName, extension: "mid")
        try midiData.write(to: exportURL, options: .atomic)
        return exportURL
    }

    private func writeAudioExports() async throws -> [URL] {
        try await withExportTargets { target in
            guard let liveRenderSession = session.liveRenderSession else {
                throw ScoreReaderExportError.unsupportedFormat("Audio")
            }

            let durationSeconds = try await liveRenderSession.playbackAudioExportDurationSeconds()
            guard durationSeconds > 0 else {
                throw ScoreReaderExportError.noAudio
            }

            let exportURL = try Self.exportURL(baseName: exportFileName(for: target), extension: "wav")
            try await writeWAVExport(
                to: exportURL,
                durationSeconds: durationSeconds + 1,
                liveRenderSession: liveRenderSession
            )
            return exportURL
        }
    }

    private func writeWAVExport(to exportURL: URL,
                                durationSeconds: TimeInterval,
                                liveRenderSession: LiveScoreRenderSession) async throws {
        let chunkDurationSeconds: TimeInterval = 10
        var nextStartSeconds: TimeInterval = 0
        var audioFile: AVAudioFile?
        var audioFormat: AVAudioFormat?

        while nextStartSeconds < durationSeconds {
            let requestedDuration = min(chunkDurationSeconds, durationSeconds - nextStartSeconds)
            let audioData = try await liveRenderSession.playbackAudioChunk(
                startTimeSeconds: nextStartSeconds,
                durationSeconds: requestedDuration,
                metronomeEnabled: false
            )

            guard let buffer = Self.makeAudioBuffer(from: audioData) else {
                throw ScoreReaderExportError.noAudio
            }

            if audioFile == nil {
                audioFormat = buffer.format
                audioFile = try AVAudioFile(forWriting: exportURL, settings: buffer.format.settings)
            } else if audioFormat?.sampleRate != buffer.format.sampleRate || audioFormat?.channelCount != buffer.format.channelCount {
                throw ScoreReaderExportError.unsupportedFormat("Audio")
            }

            try audioFile?.write(from: buffer)
            nextStartSeconds += requestedDuration
        }
    }

    private static func makeAudioBuffer(from audioData: MSRPlaybackAudioData) -> AVAudioPCMBuffer? {
        guard audioData.channelCount > 0 else {
            return nil
        }

        let frameCount = audioData.interleavedFloat32Samples.count / MemoryLayout<Float>.size / audioData.channelCount
        guard frameCount > 0 else {
            return nil
        }

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(audioData.sampleRate),
            channels: AVAudioChannelCount(audioData.channelCount),
            interleaved: false
        ),
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))
        else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        audioData.interleavedFloat32Samples.withUnsafeBytes { rawBuffer in
            guard let source = rawBuffer.bindMemory(to: Float.self).baseAddress else {
                return
            }

            for channel in 0..<audioData.channelCount {
                guard let destination = buffer.floatChannelData?[channel] else {
                    continue
                }
                for frame in 0..<frameCount {
                    destination[frame] = source[frame * audioData.channelCount + channel]
                }
            }
        }

        return buffer
    }

    private func writeMusicXMLExports() async throws -> [URL] {
        try await withExportTargets { target in
            guard let liveRenderSession = session.liveRenderSession else {
                throw ScoreReaderExportError.unsupportedFormat("MusicXML")
            }

            let musicXMLData = try await liveRenderSession.musicXMLData()
            let exportURL = try Self.exportURL(baseName: exportFileName(for: target), extension: "musicxml")
            try musicXMLData.write(to: exportURL, options: .atomic)
            return exportURL
        }
    }

    private func writePDFExports() async throws -> [URL] {
        try await withExportTargets { target in
            let pages = try await renderedExportPages(for: target)
            guard !pages.isEmpty else {
                throw ScoreReaderExportError.noPages
            }

            let exportURL = try Self.exportURL(baseName: exportFileName(for: target), extension: "pdf")
            let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pages[0].size))
            try renderer.writePDF(to: exportURL) { context in
                for page in pages {
                    context.beginPage(withBounds: CGRect(origin: .zero, size: page.size), pageInfo: [:])
                    page.draw(in: CGRect(origin: .zero, size: page.size))
                }
            }
            return exportURL
        }
    }

    private func writePNGPageExports() async throws -> [URL] {
        let groupedURLs = try await withExportTargets { target in
            let pages = try await renderedExportPages(for: target)
            guard !pages.isEmpty else {
                throw ScoreReaderExportError.noPages
            }

            return try pages.enumerated().map { index, page in
                let exportURL = try Self.exportURL(baseName: "\(exportFileName(for: target)) Page \(index + 1)", extension: "png")
                guard let data = page.pngData() else {
                    throw ScoreReaderExportError.imageEncodingFailed
                }
                try data.write(to: exportURL, options: .atomic)
                return exportURL
            }
        }

        return groupedURLs.flatMap { $0 }
    }

    private func renderedExportPages(for target: ScoreReaderExportTarget) async throws -> [UIImage] {
        if let liveRenderSession = session.liveRenderSession {
            var pages: [UIImage] = []
            for pageIndex in 0..<target.pageCount {
                let page = try await liveRenderSession.renderPage(at: pageIndex, dpi: readerState.preferredDPI)
                if let image = page.image {
                    pages.append(image)
                }
            }
            return pages
        }

        return readerState.pageIndices.compactMap { readerState.page(at: $0)?.image }
    }

    private func withExportTargets<T>(_ export: (ScoreReaderExportTarget) async throws -> T) async throws -> [T] {
        guard let liveRenderSession = session.liveRenderSession else {
            guard exportDraft.includesFullScore else {
                throw ScoreReaderExportError.unsupportedFormat("parts")
            }
            return [try await export(.fullScore(pageCount: readerState.pageCount))]
        }

        let selectedPartIDBeforeExport = selectedPartID
        let concertPitchBeforeExport = await liveRenderSession.concertPitchEnabled()
        var results: [T] = []

        do {
            if exportDraft.includesFullScore {
                let fullScorePageCount = try await liveRenderSession.setFullScoreView()
                results.append(try await export(.fullScore(pageCount: fullScorePageCount)))
            }

            if exportDraft.includesParts {
                for part in selectedExportParts {
                    var partPageCount = try await liveRenderSession.setActivePart(index: part.index)
                    if shouldExportPartsInConcertPitch,
                       await liveRenderSession.concertPitchEnabled() != exportDraft.exportPartsInConcertPitch
                    {
                        partPageCount = try await liveRenderSession.setConcertPitchEnabled(exportDraft.exportPartsInConcertPitch)
                    }
                    results.append(try await export(.part(part, pageCount: partPageCount)))
                }
            }

            if results.isEmpty {
                throw ScoreReaderExportError.noContentSelected
            }

            try await restoreActivePart(afterExporting: selectedPartIDBeforeExport, concertPitchEnabled: concertPitchBeforeExport)
            return results
        } catch {
            try? await restoreActivePart(afterExporting: selectedPartIDBeforeExport, concertPitchEnabled: concertPitchBeforeExport)
            throw error
        }
    }

    private var selectedExportParts: [ScorePart] {
        session.document.parts.filter { exportDraft.selectedPartIDs.contains($0.id) }
    }

    private func scoreInstrumentsFromDocumentParts() -> [NewScoreInstrument] {
        session.document.parts.map { part in
            NewScoreInstrumentCatalog.instrument(fromTemplateID: part.name.lowercased().replacingOccurrences(of: " ", with: "-"), name: part.name)
        }
    }

    private var shouldExportPartsInConcertPitch: Bool {
        exportDraft.format == .pdf
    }

    private func restoreActivePart(afterExporting selectedPartIDBeforeExport: String, concertPitchEnabled: Bool) async throws {
        guard let liveRenderSession = session.liveRenderSession else {
            return
        }

        var restoredPageCount: Int
        if
            selectedPartIDBeforeExport != "full-score",
            let part = session.document.parts.first(where: { $0.id == selectedPartIDBeforeExport })
        {
            restoredPageCount = try await liveRenderSession.setActivePart(index: part.index)
        } else {
            restoredPageCount = try await liveRenderSession.setFullScoreView()
        }

        if await liveRenderSession.concertPitchEnabled() != concertPitchEnabled {
            restoredPageCount = try await liveRenderSession.setConcertPitchEnabled(concertPitchEnabled)
        }
        let hasConcertPitchRelevantTransposition = await liveRenderSession.hasConcertPitchRelevantTransposition()

        await MainActor.run {
            readerState.updateConcertPitchState(
                enabled: concertPitchEnabled,
                isRelevant: hasConcertPitchRelevantTransposition
            )
            readerState.activePageCount = max(restoredPageCount, 0)
            readerState.updateSelection(to: min(readerState.selectedPageIndex, max(restoredPageCount - 1, 0)))
            readerState.invalidateRenderedPages()
            readerState.loadEditingState()
        }
    }

    private func exportFileName(for target: ScoreReaderExportTarget) -> String {
        switch target {
        case .fullScore:
            return exportDraft.fileName
        case .part(let part, _):
            return "\(exportDraft.fileName) - \(part.name)"
        }
    }

    private static func exportURL(baseName: String, extension pathExtension: String) throws -> URL {
        var sanitizedBaseName = baseName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmptyOrFallback("Aria Export")
        let dottedExtension = ".\(pathExtension)"
        if sanitizedBaseName.lowercased().hasSuffix(dottedExtension.lowercased()) {
            sanitizedBaseName.removeLast(dottedExtension.count)
        }
        sanitizedBaseName = sanitizedBaseName.nonEmptyOrFallback("Aria Export")

        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AriaExports", isDirectory: true)

        try FileManager.default.createDirectory(
            at: exportDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let exportURL = exportDirectory.appendingPathComponent("\(sanitizedBaseName).\(pathExtension)")
        if FileManager.default.fileExists(atPath: exportURL.path) {
            try FileManager.default.removeItem(at: exportURL)
        }
        return exportURL
    }

    private var exportErrorIsPresented: Binding<Bool> {
        Binding(
            get: { exportErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    exportErrorMessage = nil
                }
            }
        )
    }

    private func presentTextEditor(_ selection: ScoreSelectedElement) {
        guard selection.kind == .text || selection.kind == .chordText else {
            return
        }

        if selection.textKind == "Lyrics" {
            openLyricsEntry()
            return
        }

        if selection.kind == .chordText {
            openChordEntry()
            return
        }

        guard textEditorDraft == nil || textEditorDraft?.selectionID != selection.textEditorID else {
            return
        }

        textEditorDraft = ScoreReaderTextEditorDraft(selection: selection)
    }

    private func openChordEntry() {
        readerState.setNoteInputEnabled(false)
        guard selectedToolCategory != .chord else {
            enterTextEntryFocusIfNeeded()
            return
        }
        selectedToolCategory = .chord
    }

    private func openLyricsEntry() {
        readerState.setNoteInputEnabled(false)
        guard selectedToolCategory != .lyrics else {
            enterTextEntryFocusIfNeeded()
            return
        }
        selectedToolCategory = .lyrics
    }

    private func activatePencilNoteEntryMode() {
        guard readerState.supportsEditing, pencilAutoNoteEntryAllowed else {
            return
        }
        selectedToolCategory = .notes
        if !readerState.editingState.noteInputEnabled {
            readerState.setNoteInputEnabled(true)
        }
    }

    private func selectModeFromToolbar() {
        pencilAutoNoteEntryAllowed = false
        readerState.setNoteInputEnabled(false)
        exitTextEntryFocusIfNeeded()
    }

    private func noteInputModeFromToolbar() {
        pencilAutoNoteEntryAllowed = true
        readerState.setNoteInputEnabled(true)
        exitTextEntryFocusIfNeeded()
    }

    private func toggleNoteInputFromPencilDoubleTap() {
        if readerState.editingState.noteInputEnabled {
            selectModeFromToolbar()
        } else {
            noteInputModeFromToolbar()
        }
    }

    private func dismissSelectionCommandMenu(identity: String) {
        dismissedSelectionCommandIdentity = identity
        selectionCommandAnchor = nil
    }

    private func clearSelectionCommandMenu() {
        dismissedSelectionCommandIdentity = nil
        selectionCommandAnchor = nil
    }

    private func handleToolCategoryChange(from oldValue: ScoreReaderToolCategory, to newValue: ScoreReaderToolCategory) {
        let wasTextEntry = oldValue == .chord || oldValue == .lyrics
        let isTextEntry = newValue == .chord || newValue == .lyrics

        if isTextEntry {
            readerState.setNoteInputEnabled(false)
            enterTextEntryFocusIfNeeded()
        } else if wasTextEntry {
            exitTextEntryFocusIfNeeded()
        }
    }

    private func enterTextEntryFocusIfNeeded() {
        if zoomScaleBeforeTextEntry == nil {
            zoomScaleBeforeTextEntry = zoomScale
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            zoomScale = max(zoomScale, textEntryFocusZoomScale)
        }
        readerState.activeNotationAutoScrollRevision += 1
    }

    private func exitTextEntryFocusIfNeeded() {
        guard let previousZoomScale = zoomScaleBeforeTextEntry else {
            return
        }

        zoomScaleBeforeTextEntry = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            zoomScale = previousZoomScale
        }
    }

    private var textEntryFocusZoomScale: CGFloat {
        isPhoneInterface ? 2.35 : 1.7
    }

    private func zoomIn() {
        zoomScale = min(3, zoomScale + 0.15)
    }

    private func zoomOut() {
        zoomScale = max(0.8, zoomScale - 0.15)
    }
}

private struct ScoreReaderCorruptionMenu: View {
    let report: ScoreCorruptionReport
    let isBusy: Bool
    let selectIssueAction: (ScoreCorruptionIssue) -> Void
    let clearIssueAction: (ScoreCorruptionIssue) -> Void

    private var firstIssue: ScoreCorruptionIssue? {
        report.issues.first
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(red: 0.78, green: 0.10, blue: 0.08))

            VStack(alignment: .leading, spacing: 2) {
                Text("Fix score corruption")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.88))

                Text("\(report.issues.count) issue\(report.issues.count == 1 ? "" : "s") found. Editing is locked.")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.black.opacity(0.58))
            }

            Menu {
                if let firstIssue {
                    Button {
                        selectIssueAction(firstIssue)
                    } label: {
                        Label("Go to First Corrupt Bar", systemImage: "scope")
                    }
                }

                ForEach(Array(report.issues.prefix(12))) { issue in
                    Button {
                        selectIssueAction(issue)
                    } label: {
                        Label(issue.title, systemImage: "location")
                    }
                }

                if !report.issues.isEmpty {
                    Divider()
                }

                ForEach(Array(report.issues.prefix(12).filter(\.repairable))) { issue in
                    Button(role: .destructive) {
                        clearIssueAction(issue)
                    } label: {
                        Label("Clear \(issue.title)", systemImage: "eraser")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color(red: 0.78, green: 0.10, blue: 0.08), in: Circle())
                    .shadow(color: Color.black.opacity(0.16), radius: 8, y: 3)
            }
            .disabled(isBusy || report.issues.isEmpty)
            .accessibilityLabel("Corruption repair options")
        }
        .padding(.leading, 13)
        .padding(.trailing, 8)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(red: 0.78, green: 0.10, blue: 0.08).opacity(0.24), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.14), radius: 18, y: 8)
    }
}

private struct ScoreReaderSavingHUD: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Saving...")
                .font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(Color.black.opacity(0.82))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.16), radius: 18, y: 8)
    }
}

private extension String {
    func nonEmptyOrFallback(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
