//
//  ScoreReaderNoteEntrySurface.swift
//  MuseReaderiOS
//

import SwiftUI
import UIKit

struct ScoreReaderNoteEntrySurface: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var preferFlats = false

    let editingState: ScoreEditingState
    let pendingPitchClass: Int?
    let pendingMIDIPitch: Int?
    let stackedChordInputEnabled: Bool
    let isBusy: Bool
    let errorText: String?
    let selectModeAction: () -> Void
    let noteInputModeAction: () -> Void
    let deleteSelectionAction: () -> Void
    let clearSelectedMeasureAction: () -> Void
    let removeSelectedMeasureAction: () -> Void
    let addMeasureAction: () -> Void
    let addMultipleMeasuresAction: () -> Void
    let copySelectedMeasureRangeAction: () -> Void
    let cutSelectedMeasureRangeAction: () -> Void
    let pasteMeasureRangeAction: () -> Void
    let selectPreviousElementAction: () -> Void
    let selectNextElementAction: () -> Void
    let undoAction: () -> Void
    let redoAction: () -> Void
    let setCurrentVoiceAction: (Int) -> Void
    @Binding var selectedToolCategory: ScoreReaderToolCategory
    let pendingAccidentalKind: ScoreAccidentalKind?
    let applyDurationAction: (ScoreNoteDuration) -> Void
    let toggleDotAction: () -> Void
    let toggleRestAction: () -> Void
    let toggleTieAction: () -> Void
    let addTupletAction: (Int) -> Void
    let toggleStackedChordInputAction: () -> Void
    let editSelectedTextAction: (ScoreSelectedElement) -> Void
    let addTextAction: (String) -> Void
    let addChordTextAction: (String) -> Void
    let addChordTextAndSelectNextAction: (String) -> Void
    let openLyricsEntryAction: () -> Void
    let addLyricsTextAction: (String, Bool) -> Void
    let addRepeatJumpAction: (String) -> Void
    let addExpressionAction: (String) -> Void
    let addLayoutBreakAction: (String) -> Void
    let removeLayoutBreakAction: () -> Void
    let updateLayoutOptionsAction: (ScoreLayoutOptionsValue) -> Void
    let fillSelectionWithSlashesAction: () -> Void
    let replaceSelectionWithRhythmicSlashesAction: () -> Void
    let openAddInstrumentAction: () -> Void
    let removeSelectedInstrumentAction: () -> Void
    let openClefEditorAction: () -> Void
    let openAutoBreaksAction: () -> Void
    let openStaffSpacingAction: () -> Void
    let openPageSettingsAction: () -> Void
    let openScoreSetupAction: () -> Void
    let openTempoEditorAction: () -> Void
    let openTimeSignatureAction: () -> Void
    let openKeySignatureAction: () -> Void
    let openPickupMeasureAction: () -> Void
    let openCreatePickupMeasureAction: () -> Void
    let concertPitchEnabled: Bool
    let showsConcertPitchControl: Bool
    let toggleConcertPitchAction: () -> Void
    let setKeyboardPitchAction: (Int, Int?, Bool) -> Void
    let setPitchClassAction: (Int, Bool) -> Void
    let prepareAccidentalAction: (ScoreAccidentalKind) -> Void
    let semitoneShiftAction: (Int) -> Void
    let octaveShiftAction: (Int) -> Void

    var body: some View {
        if isCompactPhoneLayout {
            if isCompactPhoneLandscapeLayout && selectedToolCategory != .chord && selectedToolCategory != .lyrics {
                compactLandscapeBody
            } else {
                compactBody
            }
        } else {
            regularBody
        }
    }

    private var regularBody: some View {
        VStack(spacing: 0) {
            if let errorText = errorText?.trimmedToNil {
                Text(errorText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.red.opacity(0.76), in: Capsule())
                    .padding(.bottom, 8)
            }

            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        voiceSelectorSlot
                        undoRedoControls
                    }
                    .frame(width: topMenuSideSlotWidth, alignment: .trailing)

                    modeToolbar

                    HStack(spacing: 8) {
                        previousNextControls
                        globalDeleteButton
                    }
                    .frame(width: topMenuSideSlotWidth, alignment: .leading)
                }
                .padding(.horizontal, 24)

                detailToolbar

                if selectedToolCategory != .chord && selectedToolCategory != .lyrics {
                    pitchKeyboardRow
                }
            }
            .padding(.top, 14)
            .frame(maxWidth: .infinity)
            .scoreReaderRegularNoteEntryPanelBackground()
        }
    }

    private var globalDeleteButton: some View {
        Button(action: deleteSelectionAction) {
            Image(systemName: "trash")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.black.opacity(0.78))
        .disabled(!hasSelection || isBusy)
        .opacity(hasSelection && !isBusy ? 1 : 0.38)
        .accessibilityLabel("Delete Selection")
    }

    private var compactBody: some View {
        VStack(spacing: 0) {
            if let errorText = errorText?.trimmedToNil {
                Text(errorText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.76), in: Capsule())
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }

            if selectedToolCategory == .chord || selectedToolCategory == .lyrics {
                compactTextEntryHeader
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            } else {
                compactModeToolbar
                    .padding(.horizontal, 6)
                    .padding(.top, 8)
                    .padding(.bottom, 6)

                compactPanelDivider
            }

            compactDetailToolbar
                .padding(.horizontal, 6)
                .padding(.vertical, selectedToolCategory == .chord || selectedToolCategory == .lyrics ? 10 : 6)

            if selectedToolCategory != .chord && selectedToolCategory != .lyrics {
                compactPanelDivider

                compactPitchKeyboardRow
                    .padding(.horizontal, 6)
                    .padding(.top, 6)
                    .padding(.bottom, 8)
            }
        }
        .environment(\.scoreReaderCompactPanelEmbedded, true)
        .scoreReaderCompactNoteEntryPanelBackground()
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
        .background(alignment: .bottom) {
            Color.white.opacity(0.97)
                .frame(height: textEntryBottomFillHeight)
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private var textEntryBottomFillHeight: CGFloat {
        selectedToolCategory == .chord || selectedToolCategory == .lyrics ? 56 : 80
    }

    private var compactTextEntryHeader: some View {
        HStack(spacing: 10) {
            Text(selectedToolCategory == .chord ? "Chord" : "Lyrics")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.88))

            Spacer(minLength: 8)

            Button {
                selectedToolCategory = .select
                selectModeAction()
            } label: {
                Text("Done")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.0, green: 0.48, blue: 1.0))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }
    }

    private var compactPanelDivider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.06))
            .frame(height: 0.5)
            .padding(.horizontal, 10)
    }

    private var compactLandscapeBody: some View {
        VStack(spacing: 0) {
            if let errorText = errorText?.trimmedToNil {
                Text(errorText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.red.opacity(0.76), in: Capsule())
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
            }

            HStack(alignment: .bottom, spacing: 10) {
                VStack(spacing: 0) {
                    compactModeToolbar
                        .padding(.horizontal, 6)
                        .padding(.top, 8)
                        .padding(.bottom, 6)

                    compactPanelDivider

                    compactLandscapeDetailToolbar
                        .padding(.horizontal, 6)
                        .padding(.bottom, 8)
                }
                .frame(minWidth: 260, idealWidth: 340, maxWidth: 380)

                compactLandscapePitchKeyboardRow
                    .padding(.horizontal, 6)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
            }
        }
        .environment(\.scoreReaderCompactPanelEmbedded, true)
        .scoreReaderCompactNoteEntryPanelBackground()
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .background(alignment: .bottom) {
            Color.white.opacity(0.97)
                .frame(height: 100)
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private var pitchKeyboardRow: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ScoreReaderPitchNudgePair(
                title: "Octave",
                isEnabled: pitchEditEnabled && !isBusy,
                upAction: { octaveShiftAction(1) },
                downAction: { octaveShiftAction(-1) }
            )
            .frame(width: 58, height: 92)
            .padding(.trailing, 18)

            ScoreReaderWidePitchKeyboard(
                useFlats: preferFlats,
                activePitchClass: activePitchClass,
                activeMIDIPitch: activeMIDIPitch,
                followsActiveMIDIPitch: !editingState.noteInputEnabled && !isBusy,
                isEnabled: keyboardEnabled && !isBusy,
                action: { key in
                    setKeyboardPitchAction(key.pitchClass, key.midiPitch, preferFlats)
                }
            )
            .frame(height: 92)
            .frame(maxWidth: .infinity)

            ScoreReaderPitchNudgePair(
                title: "Half step",
                isEnabled: pitchEditEnabled && !isBusy,
                upAction: { semitoneShiftAction(1) },
                downAction: { semitoneShiftAction(-1) }
            )
            .frame(width: 58, height: 92)
            .padding(.leading, 18)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
    }

    private var compactPitchKeyboardRow: some View {
        HStack(alignment: .bottom, spacing: 4) {
            compactUndoRedoColumn

            ScoreReaderWidePitchKeyboard(
                useFlats: preferFlats,
                activePitchClass: activePitchClass,
                activeMIDIPitch: activeMIDIPitch,
                followsActiveMIDIPitch: !editingState.noteInputEnabled && !isBusy,
                isEnabled: keyboardEnabled && !isBusy,
                minimumVisibleNaturalKeyCount: 7,
                maximumVisibleNaturalKeyCount: 8,
                targetWhiteKeyWidth: 42,
                action: { key in
                    setKeyboardPitchAction(key.pitchClass, key.midiPitch, preferFlats)
                }
            )
            .frame(height: 86)
            .frame(maxWidth: .infinity)

            compactSelectionNavigationColumn
        }
    }

    private var compactLandscapePitchKeyboardRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            compactLandscapeUndoRedoColumn

            ScoreReaderWidePitchKeyboard(
                useFlats: preferFlats,
                activePitchClass: activePitchClass,
                activeMIDIPitch: activeMIDIPitch,
                followsActiveMIDIPitch: !editingState.noteInputEnabled && !isBusy,
                isEnabled: keyboardEnabled && !isBusy,
                minimumVisibleNaturalKeyCount: 5,
                maximumVisibleNaturalKeyCount: 7,
                targetWhiteKeyWidth: 35,
                action: { key in
                    setKeyboardPitchAction(key.pitchClass, key.midiPitch, preferFlats)
                }
            )
            .frame(height: 92)
            .frame(maxWidth: .infinity)

            compactLandscapeSelectionNavigationColumn
        }
    }

    private var compactUndoRedoColumn: some View {
        VStack(spacing: 0) {
            compactEditingSideButton(
                systemImage: "arrow.uturn.backward",
                accessibilityLabel: "Undo",
                isEnabled: editingState.canUndo && !isBusy,
                action: undoAction
            )

            compactSideButtonDivider

            compactEditingSideButton(
                systemImage: "arrow.uturn.forward",
                accessibilityLabel: "Redo",
                isEnabled: editingState.canRedo && !isBusy,
                action: redoAction
            )
        }
        .frame(width: 36, height: 80)
        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 0.5)
        }
    }

    private var compactLandscapeUndoRedoColumn: some View {
        compactSideColumn {
            compactEditingSideButton(
                systemImage: "arrow.uturn.backward",
                accessibilityLabel: "Undo",
                isEnabled: editingState.canUndo && !isBusy,
                width: 36,
                height: 36,
                fontSize: 16,
                action: undoAction
            )

            compactSideButtonDivider

            compactEditingSideButton(
                systemImage: "arrow.uturn.forward",
                accessibilityLabel: "Redo",
                isEnabled: editingState.canRedo && !isBusy,
                width: 36,
                height: 36,
                fontSize: 16,
                action: redoAction
            )
        }
    }

    private var compactSelectionNavigationColumn: some View {
        VStack(spacing: 0) {
            compactEditingSideButton(
                systemImage: "chevron.right",
                accessibilityLabel: "Select Next",
                isEnabled: canNavigateSelection && !isBusy,
                action: selectNextElementAction
            )

            compactSideButtonDivider

            compactEditingSideButton(
                systemImage: "chevron.left",
                accessibilityLabel: "Select Previous",
                isEnabled: canNavigateSelection && !isBusy,
                action: selectPreviousElementAction
            )
        }
        .frame(width: 36, height: 80)
        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 0.5)
        }
    }

    private var compactLandscapeSelectionNavigationColumn: some View {
        compactSideColumn {
            compactEditingSideButton(
                systemImage: "chevron.right",
                accessibilityLabel: "Select Next",
                isEnabled: canNavigateSelection && !isBusy,
                width: 36,
                height: 36,
                fontSize: 16,
                action: selectNextElementAction
            )

            compactSideButtonDivider

            compactEditingSideButton(
                systemImage: "chevron.left",
                accessibilityLabel: "Select Previous",
                isEnabled: canNavigateSelection && !isBusy,
                width: 36,
                height: 36,
                fontSize: 16,
                action: selectPreviousElementAction
            )
        }
    }

    private func compactSideColumn<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .frame(width: 36, height: 76)
        .background(Color.white.opacity(0.70), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.black.opacity(0.07), lineWidth: 0.5)
        }
    }

    private var compactSideButtonDivider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.08))
            .frame(width: 24, height: 1)
    }

    private func compactEditingSideButton(
        systemImage: String,
        accessibilityLabel: String,
        isEnabled: Bool,
        width: CGFloat = 38,
        height: CGFloat = 42,
        fontSize: CGFloat = 17,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: fontSize, weight: .semibold))
                .frame(width: width, height: height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.black.opacity(0.78))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var detailToolbar: some View {
        switch selectedToolCategory {
        case .chord:
            ScoreReaderChordEntryPanel(
                selectionID: editingState.selection?.textEditorID,
                initialText: editingState.selection?.kind == .chordText ? (editingState.selection?.textContent ?? "") : "",
                isInsertEnabled: hasSelection && !isBusy,
                insertAction: addChordTextAction,
                insertAndAdvanceAction: addChordTextAndSelectNextAction,
                nextAction: selectNextElementAction,
                cancelAction: {
                    selectedToolCategory = .select
                    selectModeAction()
                }
            )
            .padding(.bottom, 12)
            .padding(.horizontal, 24)

        case .lyrics:
            ScoreReaderLyricsEntryPanel(
                selectionID: editingState.selection?.textEditorID,
                initialText: editingState.selection?.textKind == "Lyrics" ? (editingState.selection?.textContent ?? "") : "",
                isInsertEnabled: lyricEntryEnabled && !isBusy,
                insertAction: addLyricsTextAction,
                cancelAction: {
                    selectedToolCategory = .select
                    selectModeAction()
                }
            )
            .padding(.bottom, 12)
            .padding(.horizontal, 24)

        case .repeats:
            HStack(spacing: 10) {
                ScoreReaderRepeatContextToolbar(
                    isEnabled: hasSelection && !isBusy,
                    addRepeatJumpAction: addRepeatJumpAction
                )
                .frame(maxWidth: .infinity)

                if isMeasureSelection {
                    Menu {
                        if isFirstMeasureSelection {
                            Button(isPickupMeasureSelection ? "Edit Pickup Measure..." : "Convert to Pickup Measure", action: openPickupMeasureAction)
                        }
                        Button("Clear", action: clearSelectedMeasureAction)
                        Button("Add Measure", action: addMeasureAction)
                        Button("Add Multiple Measures", action: addMultipleMeasuresAction)
                        Button("Copy", action: copySelectedMeasureRangeAction)
                        Button("Cut", action: cutSelectedMeasureRangeAction)
                        Button("Paste", action: pasteMeasureRangeAction)
                        Button("Delete Measure", role: .destructive, action: removeSelectedMeasureAction)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(red: 0.0, green: 0.38, blue: 0.95))
                            .frame(width: 46, height: 46)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.blue.opacity(0.22), lineWidth: 0.5)
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 52)

        case .text:
            ScoreReaderTextContextToolbar(
                isEnabled: hasSelection && !isBusy,
                addTextAction: addTextAction,
                openChordEntryAction: {
                    selectedToolCategory = .chord
                },
                openLyricsEntryAction: openLyricsEntryAction,
                openTempoEditorAction: openTempoEditorAction
            )
            .padding(.horizontal, 52)

        case .expression:
            ScoreReaderExpressionContextToolbar(
                hasSelection: hasSelection && !isBusy,
                hasNoteSelection: expressionArticulationEnabled,
                supportsBowingArticulations: supportsBowingArticulations,
                addExpressionAction: addExpressionAction
            )
            .padding(.horizontal, 52)

        case .layout:
            ScoreReaderLayoutContextToolbar(
                isEnabled: hasSelection && !isBusy,
                canOpenAutoBreaks: !isBusy,
                createMultiMeasureRests: editingState.createMultiMeasureRests,
                hideEmptyStaves: editingState.hideEmptyStaves,
                addLayoutBreakAction: addLayoutBreakAction,
                removeLayoutBreakAction: removeLayoutBreakAction,
                updateLayoutOptionsAction: updateLayoutOptionsAction,
                openAutoBreaksAction: openAutoBreaksAction,
                openStaffSpacingAction: openStaffSpacingAction,
                openPageSettingsAction: openPageSettingsAction
            )
            .padding(.horizontal, 52)

        case .more:
            ScoreReaderMoreContextToolbar(
                isEnabled: !isBusy,
                canFillWithSlashes: editingState.selection?.canFillWithSlashes == true && !isBusy,
                canReplaceWithRhythmicSlashes: hasSelection && !isBusy,
                openAddInstrumentAction: openAddInstrumentAction,
                removeSelectedInstrumentAction: removeSelectedInstrumentAction,
                openClefEditorAction: openClefEditorAction,
                openScoreSetupAction: openScoreSetupAction,
                openTempoEditorAction: openTempoEditorAction,
                openTimeSignatureAction: openTimeSignatureAction,
                openKeySignatureAction: openKeySignatureAction,
                openPickupMeasureAction: openCreatePickupMeasureAction,
                fillSelectionWithSlashesAction: fillSelectionWithSlashesAction,
                replaceSelectionWithRhythmicSlashesAction: replaceSelectionWithRhythmicSlashesAction,
                concertPitchEnabled: concertPitchEnabled,
                showsConcertPitchControl: showsConcertPitchControl,
                toggleConcertPitchAction: toggleConcertPitchAction
            )
            .padding(.horizontal, 52)

        case .notes, .select:
            ScoreReaderKeyboardContextToolbar(
                editingState: editingState,
                pendingPitchClass: pendingPitchClass,
                pendingAccidentalKind: pendingAccidentalKind,
                isBusy: isBusy,
                applyDurationAction: applyDurationAction,
                toggleDotAction: toggleDotAction,
                toggleRestAction: toggleRestAction,
                toggleTieAction: toggleTieAction,
                addTupletAction: addTupletAction,
                stackedChordInputEnabled: stackedChordInputEnabled,
                toggleStackedChordInputAction: toggleStackedChordInputAction,
                setPitchClassAction: setPitchClassAction,
                prepareAccidentalAction: prepareAccidentalAction,
                preferFlats: $preferFlats
            )
            .padding(.horizontal, 52)
        }
    }

    @ViewBuilder
    private var compactDetailToolbar: some View {
        switch selectedToolCategory {
        case .chord:
            ScoreReaderChordEntryPanel(
                selectionID: editingState.selection?.textEditorID,
                initialText: editingState.selection?.kind == .chordText ? (editingState.selection?.textContent ?? "") : "",
                isInsertEnabled: hasSelection && !isBusy,
                insertAction: addChordTextAction,
                insertAndAdvanceAction: addChordTextAndSelectNextAction,
                nextAction: selectNextElementAction,
                cancelAction: {
                    selectedToolCategory = .select
                    selectModeAction()
                }
            )
            .padding(.horizontal, 8)

        case .lyrics:
            ScoreReaderLyricsEntryPanel(
                selectionID: editingState.selection?.textEditorID,
                initialText: editingState.selection?.textKind == "Lyrics" ? (editingState.selection?.textContent ?? "") : "",
                isInsertEnabled: lyricEntryEnabled && !isBusy,
                insertAction: addLyricsTextAction,
                cancelAction: {
                    selectedToolCategory = .select
                    selectModeAction()
                }
            )
            .padding(.horizontal, 8)
        case .notes, .select:
            ScoreReaderKeyboardContextToolbar(
                editingState: editingState,
                pendingPitchClass: pendingPitchClass,
                pendingAccidentalKind: pendingAccidentalKind,
                isBusy: isBusy,
                isCompact: true,
                applyDurationAction: applyDurationAction,
                toggleDotAction: toggleDotAction,
                toggleRestAction: toggleRestAction,
                toggleTieAction: toggleTieAction,
                addTupletAction: addTupletAction,
                stackedChordInputEnabled: stackedChordInputEnabled,
                toggleStackedChordInputAction: toggleStackedChordInputAction,
                setPitchClassAction: setPitchClassAction,
                prepareAccidentalAction: prepareAccidentalAction,
                preferFlats: $preferFlats
            )
        default:
            // detailToolbar bakes in .padding(.horizontal, 52) — cancel it so
            // the HorizontalContextToolbar can span the full panel width on iPhone.
            detailToolbar
                .padding(.horizontal, -52)
        }
    }

    @ViewBuilder
    private var compactLandscapeDetailToolbar: some View {
        switch selectedToolCategory {
        case .notes, .select:
            ScoreReaderKeyboardContextToolbar(
                editingState: editingState,
                pendingPitchClass: pendingPitchClass,
                pendingAccidentalKind: pendingAccidentalKind,
                isBusy: isBusy,
                isCompact: true,
                applyDurationAction: applyDurationAction,
                toggleDotAction: toggleDotAction,
                toggleRestAction: toggleRestAction,
                toggleTieAction: toggleTieAction,
                addTupletAction: addTupletAction,
                stackedChordInputEnabled: stackedChordInputEnabled,
                toggleStackedChordInputAction: toggleStackedChordInputAction,
                setPitchClassAction: setPitchClassAction,
                prepareAccidentalAction: prepareAccidentalAction,
                preferFlats: $preferFlats
            )

        case .repeats:
            HStack(spacing: 8) {
                ScoreReaderRepeatContextToolbar(
                    isEnabled: hasSelection && !isBusy,
                    addRepeatJumpAction: addRepeatJumpAction
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                if isMeasureSelection {
                    Menu {
                        if isFirstMeasureSelection {
                            Button(isPickupMeasureSelection ? "Edit Pickup Measure..." : "Convert to Pickup Measure", action: openPickupMeasureAction)
                        }
                        Button("Clear", action: clearSelectedMeasureAction)
                        Button("Add Measure", action: addMeasureAction)
                        Button("Add Multiple Measures", action: addMultipleMeasuresAction)
                        Button("Copy", action: copySelectedMeasureRangeAction)
                        Button("Cut", action: cutSelectedMeasureRangeAction)
                        Button("Paste", action: pasteMeasureRangeAction)
                        Button("Delete Measure", role: .destructive, action: removeSelectedMeasureAction)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(red: 0.0, green: 0.38, blue: 0.95))
                            .frame(width: 42, height: 42)
                            .background(Color.white.opacity(0.80), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.blue.opacity(0.18), lineWidth: 0.5)
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)
                }
            }

        case .text:
            ScoreReaderTextContextToolbar(
                isEnabled: hasSelection && !isBusy,
                addTextAction: addTextAction,
                openChordEntryAction: {
                    selectedToolCategory = .chord
                },
                openLyricsEntryAction: openLyricsEntryAction,
                openTempoEditorAction: openTempoEditorAction
            )

        case .expression:
            ScoreReaderExpressionContextToolbar(
                hasSelection: hasSelection && !isBusy,
                hasNoteSelection: expressionArticulationEnabled,
                supportsBowingArticulations: supportsBowingArticulations,
                addExpressionAction: addExpressionAction
            )

        case .layout:
            ScoreReaderLayoutContextToolbar(
                isEnabled: hasSelection && !isBusy,
                canOpenAutoBreaks: !isBusy,
                createMultiMeasureRests: editingState.createMultiMeasureRests,
                hideEmptyStaves: editingState.hideEmptyStaves,
                addLayoutBreakAction: addLayoutBreakAction,
                removeLayoutBreakAction: removeLayoutBreakAction,
                updateLayoutOptionsAction: updateLayoutOptionsAction,
                openAutoBreaksAction: openAutoBreaksAction,
                openStaffSpacingAction: openStaffSpacingAction,
                openPageSettingsAction: openPageSettingsAction
            )

        case .more:
            ScoreReaderMoreContextToolbar(
                isEnabled: !isBusy,
                canFillWithSlashes: editingState.selection?.canFillWithSlashes == true && !isBusy,
                canReplaceWithRhythmicSlashes: hasSelection && !isBusy,
                openAddInstrumentAction: openAddInstrumentAction,
                removeSelectedInstrumentAction: removeSelectedInstrumentAction,
                openClefEditorAction: openClefEditorAction,
                openScoreSetupAction: openScoreSetupAction,
                openTempoEditorAction: openTempoEditorAction,
                openTimeSignatureAction: openTimeSignatureAction,
                openKeySignatureAction: openKeySignatureAction,
                openPickupMeasureAction: openCreatePickupMeasureAction,
                fillSelectionWithSlashesAction: fillSelectionWithSlashesAction,
                replaceSelectionWithRhythmicSlashesAction: replaceSelectionWithRhythmicSlashesAction,
                concertPitchEnabled: concertPitchEnabled,
                showsConcertPitchControl: showsConcertPitchControl,
                toggleConcertPitchAction: toggleConcertPitchAction
            )

        case .chord, .lyrics:
            compactDetailToolbar
        }
    }


    private var modeToolbar: some View {
        ScoreReaderModeToolbar(
            editingState: editingState,
            isBusy: isBusy,
            selectedToolCategory: $selectedToolCategory,
            selectModeAction: {
                selectedToolCategory = .select
                selectModeAction()
            },
            noteInputModeAction: {
                selectedToolCategory = .notes
                noteInputModeAction()
            },
            isMeasureSelection: isMeasureSelection,
            isSingleMeasureSelection: isSingleMeasureSelection
        )
    }

    private var compactModeToolbar: some View {
        ScoreReaderModeToolbar(
            editingState: editingState,
            isBusy: isBusy,
            isCompact: true,
            selectedToolCategory: $selectedToolCategory,
            selectModeAction: {
                selectedToolCategory = .select
                selectModeAction()
            },
            noteInputModeAction: {
                selectedToolCategory = .notes
                noteInputModeAction()
            },
            isMeasureSelection: isMeasureSelection,
            isSingleMeasureSelection: isSingleMeasureSelection
        )
    }

    private var previousNextControls: some View {
        ScoreReaderPreviousNextControls(
            isEnabled: canNavigateSelection && !isBusy,
            previousAction: selectPreviousElementAction,
            nextAction: selectNextElementAction
        )
    }

    private var voiceSelectorSlot: some View {
        HStack(spacing: 0) {
            voiceSelector
        }
        .frame(width: 70, alignment: .trailing)
    }

    private var voiceSelector: some View {
        Group {
            if selectedToolCategory == .notes {
                ScoreReaderVoiceSelector(
                    currentVoice: editingState.currentVoice,
                    isEnabled: !isBusy,
                    action: setCurrentVoiceAction
                )
            }
        }
    }

    private var toolbarFallbackControlsWidth: CGFloat {
        selectedToolCategory == .notes ? 520 : 440
    }

    private var topMenuSideSlotWidth: CGFloat {
        selectedToolCategory == .notes ? 152 : 126
    }

    private var isCompactPhoneLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    private var isCompactPhoneLandscapeLayout: Bool {
        isCompactPhoneLayout && verticalSizeClass == .compact
    }

    private var undoRedoControls: some View {
        ScoreReaderUndoRedoControls(
            canUndo: editingState.canUndo,
            canRedo: editingState.canRedo,
            isBusy: isBusy,
            undoAction: undoAction,
            redoAction: redoAction
        )
    }

    private var keyboardEnabled: Bool {
        editingState.noteInputEnabled
        || editingState.selection?.canChangePitch == true
        || editingState.selection?.kind == .rest
        || editingState.selection?.kind == .measure
    }

    private var hasSelection: Bool {
        editingState.selection != nil
    }

    private var isMeasureSelection: Bool {
        editingState.selection?.kind == .measure
    }

    private var isSingleMeasureSelection: Bool {
        editingState.selection?.kind == .measure && editingState.selection?.isSingleMeasure == true
    }

    private var isFirstMeasureSelection: Bool {
        editingState.selection?.isFirstMeasure == true
    }

    private var isPickupMeasureSelection: Bool {
        editingState.selection?.isPickupMeasure == true
    }

    private var canNavigateSelection: Bool {
        editingState.selection?.kind == .note || editingState.selection?.kind == .rest
    }

    private var lyricEntryEnabled: Bool {
        editingState.selection?.kind == .note
        || (editingState.selection?.kind == .text && editingState.selection?.textKind == "Lyrics")
    }

    private var pitchEditEnabled: Bool {
        editingState.selection?.canChangePitch == true
        || editingState.noteInputEnabled
        || editingState.selection?.kind == .measure
    }

    private var activePitchClass: Int? {
        editingState.noteInputEnabled ? (pendingPitchClass ?? editingState.selection?.pitchClass) : editingState.selection?.pitchClass
    }

    private var activeMIDIPitch: Int? {
        editingState.noteInputEnabled ? (pendingMIDIPitch ?? editingState.selection?.midiPitch) : editingState.selection?.midiPitch
    }

    private var selectedDuration: ScoreNoteDuration {
        editingState.noteInputEnabled ? editingState.duration : (editingState.selection?.duration ?? editingState.duration)
    }

    private var selectedIsRest: Bool {
        editingState.noteInputEnabled ? editingState.noteInputInsertsRests : editingState.selection?.kind == .rest
    }

    private var selectedAccidental: ScoreAccidentalKind? {
        editingState.selection?.accidentalKind
    }

    private var expressionArticulationEnabled: Bool {
        guard let selection = editingState.selection else {
            return false
        }

        return (selection.kind == .note || selection.kind == .measure) && !isBusy
    }

    private var supportsBowingArticulations: Bool {
        editingState.selection?.supportsBowingArticulations == true
    }
}

private struct ScoreReaderCompactPanelEmbeddedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var scoreReaderCompactPanelEmbedded: Bool {
        get { self[ScoreReaderCompactPanelEmbeddedKey.self] }
        set { self[ScoreReaderCompactPanelEmbeddedKey.self] = newValue }
    }
}

private extension View {
    @ViewBuilder
    func scoreReaderCompactNoteEntryPanelBackground() -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        if #available(iOS 26.0, *) {
            self
                .background(Color.white.opacity(0.22), in: shape)
                .glassEffect(.regular, in: shape)
                .overlay {
                    shape
                        .stroke(Color.white.opacity(0.38), lineWidth: 0.8)
                        .allowsHitTesting(false)
                }
                .shadow(color: Color.black.opacity(0.10), radius: 20, y: 8)
        } else {
            self
                .background(.regularMaterial, in: shape)
                .overlay {
                    shape
                        .stroke(Color.black.opacity(0.08), lineWidth: 0.6)
                        .allowsHitTesting(false)
                }
                .shadow(color: Color.black.opacity(0.08), radius: 14, y: 6)
        }
    }

    /// iPad note-entry dock: a single frosted glass slab with rounded top corners,
    /// matching the iPhone panel treatment instead of the old flat cream slab.
    @ViewBuilder
    func scoreReaderRegularNoteEntryPanelBackground() -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 28,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 28,
            style: .continuous
        )

        if #available(iOS 26.0, *) {
            self
                .background(Color.white.opacity(0.18), in: shape)
                .glassEffect(.regular, in: shape)
                .overlay(alignment: .top) {
                    shape
                        .stroke(Color.white.opacity(0.32), lineWidth: 0.8)
                        .allowsHitTesting(false)
                }
                .shadow(color: Color.black.opacity(0.10), radius: 24, y: -6)
        } else {
            self
                .background(.regularMaterial, in: shape)
                .overlay(alignment: .top) {
                    shape
                        .stroke(Color.black.opacity(0.09), lineWidth: 0.7)
                        .allowsHitTesting(false)
                }
                .shadow(color: Color.black.opacity(0.08), radius: 18, y: -5)
        }
    }
}
