//
//  ScoreReaderView.swift
//  MuseReaderiOS
//
//

import SwiftUI
import UIKit
import AVFoundation

enum ScoreReaderSequenceDirection: Equatable {
    case previous
    case next
}

struct ScoreReaderSetlistNavigation {
    let previousScoreTitle: String?
    let nextScoreTitle: String?
    let positionLabel: String
    let transition: @MainActor (ScoreReaderSequenceDirection, ScoreReaderReadingStyle) async -> Bool
}

struct ScoreReaderPageSwipePolicy {
    static func direction(for translation: CGSize, threshold: CGFloat = 48) -> ScoreReaderSequenceDirection? {
        guard abs(translation.width) >= threshold,
              abs(translation.width) > abs(translation.height)
        else {
            return nil
        }
        return translation.width < 0 ? .next : .previous
    }
}

enum ScoreReaderTransposeScope {
    case selection
    case score
}

struct ScoreReaderTransposeSheetContext: Identifiable {
    let id = UUID()
    let currentKey: Int
    let scope: ScoreReaderTransposeScope
}

struct ScoreReaderViewKeyControl: View {
    @State var isKeyPickerPresented = false

    let currentKey: ScoreTransposeTargetKey
    let originalKey: ScoreTransposeTargetKey
    let isBusy: Bool
    let selectKey: (ScoreTransposeTargetKey) -> Void

    private var chipLabel: some View {
        HStack(spacing: 7) {
            if isBusy {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "music.note")
            }
            Text(currentKey.compactTitle)
                .font(.system(size: 13, weight: .semibold))
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(Color.black.opacity(0.78))
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: Color.black.opacity(0.10), radius: 10, y: 4)
    }

    var body: some View {
        #if os(Android)
        // Android: a dropdown menu from the chip, as Android pickers do (iOS: a popover list).
        Menu {
            ForEach(ScoreTransposeTargetKey.allCases, id: \.self) { key in
                Button {
                    selectKey(key)
                } label: {
                    let title = key == originalKey ? "\(key.title) (original)" : key.title
                    if key == currentKey {
                        Label(title, systemImage: "checkmark")
                    } else {
                        Text(title)
                    }
                }
            }
        } label: {
            chipLabel
        }
        .disabled(isBusy)
        .accessibilityLabel("Viewing key, \(currentKey.title)")
        .accessibilityHint("Choose a temporary key for this score view")
        #else
        Button {
            isKeyPickerPresented = true
        } label: {
            chipLabel
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel("Viewing key, \(currentKey.title)")
        .accessibilityHint("Choose a temporary key for this score view")
        .popover(isPresented: $isKeyPickerPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            ScoreReaderViewKeyPicker(
                currentKey: currentKey,
                originalKey: originalKey,
                selectKey: selectKey
            )
            .presentationCompactPopoverWhenAvailable()
        }
        #endif
    }
}

struct ScoreReaderViewKeyPicker: View {
    @Environment(\.dismiss) var dismiss

    let currentKey: ScoreTransposeTargetKey
    let originalKey: ScoreTransposeTargetKey
    let selectKey: (ScoreTransposeTargetKey) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("Viewing Key")
                    .font(.system(size: 16, weight: .semibold))

                Spacer(minLength: 8)

                Label("Original Key", systemImage: "music.note")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.blue)
            }
            .padding(.horizontal, 14)
            .frame(height: 46)

            Divider()

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 0) {
                        ForEach(ScoreTransposeTargetKey.allCases, id: \.self) { key in
                            Button {
                                selectKey(key)
                                dismiss()
                            } label: {
                                HStack(spacing: 10) {
                                    Text(key.title)
                                        .font(.system(size: 14, weight: key == currentKey ? .semibold : .regular))
                                        .foregroundStyle(Color.black.opacity(0.82))

                                    Spacer(minLength: 8)

                                    if key == originalKey {
                                        Image(systemName: "music.note")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(Color.blue)
                                            .accessibilityHidden(true)
                                    }

                                    if key == currentKey {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundStyle(Color.accentColor)
                                            .accessibilityHidden(true)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .background(key == currentKey ? Color.accentColor.opacity(0.10) : Color.clear)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(key)
                            .accessibilityLabel(key.title)
                            .accessibilityValue(accessibilityValue(for: key))

                            if key != ScoreTransposeTargetKey.allCases.last {
                                Divider()
                                    .padding(.leading, 14)
                            }
                        }
                    }
                }
                .task(id: currentKey) {
                    await Task.yield()
                    proxy.scrollTo(currentKey, anchor: .center)
                }
            }
        }
        .frame(width: 290, height: 360)
    }

    private func accessibilityValue(for key: ScoreTransposeTargetKey) -> String {
        var values: [String] = []
        if key == originalKey {
            values.append("Original key")
        }
        if key == currentKey {
            values.append("Currently displayed")
        }
        return values.joined(separator: ", ")
    }
}

struct ScoreReaderPlaybackScrollTarget: Equatable {
    let pageIndex: Int
    let normalizedRect: ScoreNormalizedRect
}

struct ScoreReaderTwoPageViewIcon: View {
    let isActive: Bool

    var body: some View {
        HStack(spacing: 3) {
            pageOutline
            pageOutline
        }
        .foregroundStyle(isActive ? Color.blue : Color.black.opacity(0.72))
        .frame(width: 24, height: 18)
    }

    private var pageOutline: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .stroke(lineWidth: 1.8)
            .frame(width: 9, height: 15)
    }
}

struct ScoreReaderView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) var scenePhase
    @AppStorage("ScoreReaderFloatingPaletteDockedLeft") var floatingPaletteDockedLeft = true
    @AppStorage("ScoreReaderTwoPageViewEnabled") var twoPageViewEnabled = false

    let session: ScoreSession
    private let initialRememberedState: ScoreReaderRememberedState

    #if os(Android)
    // Skip keeps only @State (the first object); see OwnedState.
    @State var readerState: ScoreReaderState
    @State var annotationController: ScoreAnnotationController
    #else
    @OwnedState private var readerState: ScoreReaderState
    @OwnedState private var annotationController: ScoreAnnotationController
    #endif
    @State var zoomScale: CGFloat = UIDevice.current.userInterfaceIdiom == .phone ? 2.2 : 1.0
    @State var lastPhoneLandscapeZoomMode: Bool?
    @State var selectedToolCategory: ScoreReaderToolCategory
    @State var textEditorDraft: ScoreReaderTextEditorDraft?
    @State var legacyRepairPrompt: ScoreLegacyRepairPrompt?
    @State var isPartsPanelPresented = false
    @State var isMixerPresented = false
    @State var isFeatureTourPresented = false
    private let featureTourStore = ScoreReaderFeatureTourStore()
    @State var isUpdateNoticePresented = false
    private let updateNoticeStore = UpdateNoticeStore()

    @MainActor
    private func presentReaderIntroductionIfNeeded() async {
        #if os(Android) && ARIA_PHONE_AUDIT
        return // Disposable benchmark app only: no tour interrupts its scripted input.
        #endif
        guard readerState.pageCount > 0, !isClosingScore, !isTransitioningScore, !Task.isCancelled else { return }
        if await updateNoticeStore.shouldPresentNotice() {
            guard !Task.isCancelled, !isClosingScore, !isTransitioningScore, legacyRepairPrompt == nil else { return }
            isUpdateNoticePresented = true
        } else {
            await presentFeatureTourIfNeeded()
        }
    }

    private func handleReaderAppear() {
        updatePhoneOrientation(for: readerState.interactionMode)
    }

    @MainActor
    private func presentFeatureTourIfNeeded() async {
        guard readerState.pageCount > 0, !isClosingScore, !isTransitioningScore,
              legacyRepairPrompt == nil, !isUpdateNoticePresented, !Task.isCancelled else { return }
        guard await featureTourStore.shouldPresentTour() else {
            return
        }
        guard !Task.isCancelled, !isClosingScore, !isTransitioningScore,
              legacyRepairPrompt == nil, !isUpdateNoticePresented else { return }
        isFeatureTourPresented = true
    }

    /// Waits for the first page so the tour never appears over an empty or failed
    /// reader. Informational only: neither step asks the reader to perform the action.
    @ViewBuilder
    private var featureTourOverlay: some View {
        if isFeatureTourPresented, readerState.pageCount > 0 {
            ScoreReaderFeatureTour(steps: ScoreReaderFeatureTour.defaultSteps) {
                featureTourStore.markTourSeen()
                withAnimation(.easeInOut(duration: 0.2)) {
                    isFeatureTourPresented = false
                }
            }
            .transition(.opacity)
        }
    }
    @State var isExportPanelPresented = false
    @State var exportDraft = ScoreReaderExportDraft()
    @State var sharedExportItems: ScoreReaderSharedExportItems?
    /// Finished videos, shown in the video sheet to watch and share.
    @State var completedVideoURLs: [URL] = []
    @State var exportTask: Task<Void, Never>?
    @State var videoPreviewCache = ScoreVideoPreviewCache()
    @State var isVideoSheetPresented = false
    @State var exportErrorMessage: String?
    @State var isPreparingExport = false
    @State var exportProgress: Double?
    @State var selectedPartID = "full-score"
    @State var isTempoEditorPresented = false
    @State var isTimeSignaturePresented = false
    @State var isKeySignaturePresented = false
    @State var isScoreSetupPresented = false
    @State var isPageSettingsPresented = false
    @State var isInstrumentLayoutPresented = false
    @State var instrumentReplacementContext: InstrumentReplacementContext?
    @State var transposeSheetContext: ScoreReaderTransposeSheetContext?
    @State var isAddMeasuresPresented = false
    @State var isAutoBreaksPresented = false
    @State var isAddInstrumentPresented = false
    @State var isClefPickerPresented = false
    @State var instrumentsToAdd: [NewScoreInstrument] = []
    @State var currentScoreInstruments: [NewScoreInstrument] = []
    @State var instrumentLayoutParts: [ScorePart] = []
    #if os(Android)
    @State var selectionCommandPresentation = AndroidSelectionCommandPresentation()
    #else
    @State var selectionCommandAnchor: ScoreReaderSelectionCommandAnchor?
    @State var dismissedSelectionCommandIdentity: String?
    #endif
    @State var pencilAutoNoteEntryAllowed = true
    @State var zoomScaleBeforeTextEntry: CGFloat?
    @State var isClosingScore = false
    @State var isTransitioningScore = false
    @State var measuredNoteEntryPanelHeight: CGFloat = 0
    @State var measuredTopChromeHeight: CGFloat = 0
    @State var didApplyInitialToolCategory = false
    @State var isChromeVisible = true
    @State var savedViewModeConfirmationIsVisible = false
    @State var readingStyle: ScoreReaderReadingStyle = .pageTurn
    @State var viewModeSaveErrorMessage: String?
    @State var isAnnotationModeActive = false
    @State var annotationsVisible = true
    @State var annotationTool = ScoreAnnotationTool.pen
    @AppStorage("ScoreReaderAnnotationMarkerColor") var annotationMarkerColor = ScoreAnnotationColor.black
    @AppStorage("ScoreReaderAnnotationMarkerWidth") var annotationMarkerWidth: Double = 4
    @AppStorage("ScoreReaderAnnotationHighlighterColor") var annotationHighlighterColor = ScoreAnnotationColor.yellow
    @AppStorage("ScoreReaderAnnotationHighlighterWidth") var annotationHighlighterWidth: Double = 4
    @State var readingStyleBeforeAnnotation: ScoreReaderReadingStyle?

    private let setlistNavigation: ScoreReaderSetlistNavigation?
    private let readerReadyAction: (@MainActor () -> Void)?

    init(
        session: ScoreSession,
        initialPageIndex: Int,
        initialToolCategory: ScoreReaderToolCategory = .select,
        initialInteractionMode: ScoreReaderInteractionMode = .view,
        resumesRememberedPage: Bool = true,
        initialReadingStyle: ScoreReaderReadingStyle? = nil,
        setlistNavigation: ScoreReaderSetlistNavigation? = nil,
        readerReadyAction: (@MainActor () -> Void)? = nil
    ) {
        self.session = session
        var rememberedState = initialInteractionMode == .view
            ? ScoreReaderRememberedStateStore().state(for: session.id)
            : ScoreReaderRememberedState()
        if !resumesRememberedPage {
            rememberedState.pageIndex = initialPageIndex
            rememberedState.selectedPartID = "full-score"
            rememberedState.viewTransposeKey = nil
        }
        if let initialReadingStyle {
            rememberedState.readingStyle = initialReadingStyle
        }
        self.initialRememberedState = rememberedState
        self.setlistNavigation = setlistNavigation
        self.readerReadyAction = readerReadyAction
        _zoomScale = State(
            initialValue: initialInteractionMode == .view
                ? ScoreReaderZoomLimits.minimumScale
                : (UIDevice.current.userInterfaceIdiom == .phone ? 2.2 : 1.0)
        )
        _selectedToolCategory = State(initialValue: initialToolCategory)
        _selectedPartID = State(initialValue: rememberedState.selectedPartID)
        _readingStyle = State(initialValue: rememberedState.readingStyle)
        #if os(Android)
        _readerState = State(
            initialValue: ScoreReaderState(
                session: session,
                initialPageIndex: initialInteractionMode == .view ? rememberedState.pageIndex : initialPageIndex,
                initialInteractionMode: initialInteractionMode,
                initialViewTransposeKey: initialInteractionMode == .view ? rememberedState.viewTransposeKey : nil
            )
        )
        _annotationController = State(initialValue: ScoreAnnotationController(documentURL: session.document.url))
        #else
        _readerState = OwnedState(
            wrappedValue: ScoreReaderState(
                session: session,
                initialPageIndex: initialInteractionMode == .view ? rememberedState.pageIndex : initialPageIndex,
                initialInteractionMode: initialInteractionMode,
                initialViewTransposeKey: initialInteractionMode == .view ? rememberedState.viewTransposeKey : nil
            )
        )
        _annotationController = OwnedState(wrappedValue: ScoreAnnotationController(documentURL: session.document.url))
        #endif
    }

    var body: some View {
        #if os(Android) && ARIA_PHONE_AUDIT
        let _ = AndroidPhoneAuditGeometry.evaluate("reader")
        #endif
        readerBody
            .overlay { featureTourOverlay }
            #if os(Android) && ARIA_PHONE_AUDIT
            .overlay(alignment: .top) {
                AndroidPhoneAuditControls(reader: readerState, zoom: $zoomScale, tool: $selectedToolCategory)
            }
            #endif
            #if os(Android)
            .environment(readerState.androidPlaybackVisualState)
            #endif
        #if os(Android) && ARIA_PHONE_AUDIT
        let _ = AndroidInteractionTrace.point("evaluate_reader_end")
        #endif
    }

    private var readerBody: some View {
        readerPresentedBody
    }

    private var readerContent: some View {
        ZStack {
            ScoreReaderBackground(usesImmersiveWhite: readerState.interactionMode == .view)

            if readerState.pageCount == 0 {
                ScoreReaderUnavailableView(detailText: session.renderPipeline.detailText)
                    .padding(28)
            } else {
                isolatedReaderCanvas
                    .animation(.easeInOut(duration: 0.22), value: readerState.interactionMode)
                    .overlay(alignment: .center) {
                        if readerState.isCountingIn, let beat = readerState.countInBeatNumber {
                            Text("\(beat)")
                                .font(.system(size: isPhoneInterface ? 88 : 120, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(Color.blue.opacity(0.78))
                                .shadow(color: .white.opacity(0.9), radius: 12)
                                .id(beat)
                                .transition(.opacity.combined(with: .scale(scale: 0.7)))
                                .animation(.easeOut(duration: 0.18), value: beat)
                                .allowsHitTesting(false)
                                .accessibilityLabel("Count-in beat \(beat)")
                        }
                    }
                    .overlay(alignment: .bottom) {
                        #if os(Android)
                        AndroidReaderObservationScope { noteEntryOverlay }
                        #else
                        noteEntryOverlay
                        #endif
                    }
                    .overlay(alignment: floatingPaletteAlignment) {
                        #if os(Android)
                        AndroidReaderObservationScope { floatingPaletteOverlay }
                        #else
                        floatingPaletteOverlay
                        #endif
                    }
                    .overlay(alignment: .top) {
                        #if os(Android)
                        AndroidReaderObservationScope { readerChromeOverlay }
                        #else
                        readerChromeOverlay
                        #endif
                    }
                    .overlay(alignment: .bottom) {
                        if isMixerPresented && UIDevice.current.userInterfaceIdiom != .phone {
                            GeometryReader { proxy in
                                VStack(spacing: 0) {
                                    Spacer(minLength: 0)
                                    ScoreReaderMixerPanel(readerState: readerState, selectedPartID: selectedPartID) {
                                        withAnimation(.easeInOut(duration: 0.2)) { isMixerPresented = false }
                                    }
                                    .frame(height: min(max(proxy.size.height * 0.40, 390), 410))
                                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                                    .shadow(color: .black.opacity(0.16), radius: 18, y: -2)
                                    .padding(.horizontal, 8)
                                    .padding(.bottom, 8)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                                }
                            }
                        }
                    }
                    #if os(Android)
                    // The tablet mixer is an overlay, not a sheet; Back closes it.
                    .androidBackAction(isEnabled: isMixerPresented && UIDevice.current.userInterfaceIdiom != .phone) {
                        withAnimation(.easeInOut(duration: 0.2)) { isMixerPresented = false }
                    }
                    #endif
                    .overlay(alignment: .top) {
                        if isAnnotationModeActive && !isPhoneInterface {
                            ScoreReaderAnnotationPalette(
                                tool: $annotationTool,
                                color: annotationColorBinding,
                                width: annotationWidthBinding,
                                annotationsVisible: annotationsVisible,
                                canUndo: annotationController.canUndo,
                                canRedo: annotationController.canRedo,
                                hasSelection: annotationController.hasSelection,
                                undoAction: annotationController.undo,
                                redoAction: annotationController.redo,
                                toggleVisibilityAction: { annotationsVisible.toggle() },
                                deleteSelectionAction: annotationController.deleteSelection,
                                doneAction: exitAnnotationMode
                            )
                            .padding(.top, max(measuredTopChromeHeight, 62) + 8)
                            .padding(.horizontal, 32)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .overlay(alignment: .top) {
                        if let playbackPreparationMessage = readerState.playbackPreparationMessage {
                            ScoreReaderPlaybackPreparationHUD(message: playbackPreparationMessage)
                                .padding(.top, 88)
                        }
                    }
                    .overlay(alignment: .top) {
                        if let visibleSaveFailureMessage {
                            HStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(readerState.saveNeedsChordSymbolRemovalApproval ? "Chord Symbols Removed" : "Not Saved")
                                        .font(.system(size: 13, weight: .bold))
                                    Text(visibleSaveFailureMessage)
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                if readerState.saveNeedsChordSymbolRemovalApproval {
                                    Button("Save Without Chords", action: saveWithoutChordSymbols)
                                        .font(.system(size: 13, weight: .bold))
                                        .disabled(readerState.isEditingActionInFlight)
                                } else {
                                    Button("Retry Save", action: retryVisibleSaveFailure)
                                        .font(.system(size: 13, weight: .bold))
                                        .disabled(readerState.isEditingActionInFlight)
                                }
                            }
                            .foregroundStyle(Color.black.opacity(0.84))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .shadow(color: Color.black.opacity(0.14), radius: 14, y: 6)
                            .padding(.top, 76)
                            .padding(.horizontal, 16)
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
                        #if os(Android)
                        if readerState.isEditingMode {
                            AndroidSelectionCommandOverlayHost(presentation: selectionCommandPresentation) { anchor in
                                AnyView(selectionCommandOverlay(for: anchor))
                            }
                            .zIndex(100)
                        }
                        #else
                        if let selectionCommandAnchor, readerState.isEditingMode {
                            selectionCommandOverlay(for: selectionCommandAnchor)
                        }
                        #endif
                    }
                    .overlay(alignment: .top) {
                        if readerState.isExtendingSelection && readerState.isEditingMode {
                            ScoreReaderExtendSelectionBanner {
                                readerState.isExtendingSelection = false
                            }
                            .padding(.top, isPhoneInterface ? 72 : 84)
                            .transition(.opacity)
                        }
                    }
                    .overlay(alignment: .center) {
                        if isClosingScore {
                            ScoreReaderSavingHUD(label: "Saving…")
                        } else if isTransitioningScore {
                            ScoreReaderSavingHUD(label: adjacentScoreLoadingLabel)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if readerState.interactionMode == .view,
                           isChromeVisible,
                           !isMixerPresented,
                           !isAnnotationModeActive
                        {
                            viewModeBottomBar
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if isAnnotationModeActive,
                           readingStyle == .pageTurn,
                           readerState.pageCount > 1
                        {
                            ScoreReaderAnnotationPageNavigator(
                                currentPageIndex: readerState.selectedPageIndex,
                                pageCount: readerState.pageCount,
                                previousAction: showPreviousPage,
                                nextAction: showNextPage
                            )
                            .padding(.bottom, 12)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if savedViewModeConfirmationIsVisible {
                            Text("Saved · View mode")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.black.opacity(0.82))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(.regularMaterial, in: Capsule())
                                .padding(.bottom, 48)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if readerState.interactionMode == .view,
                           readerState.playbackState.status == .playing,
                           readerState.playbackFollowEnabled,
                           readerState.playbackFollowIsSuspended
                        {
                            Button(action: readerState.resumePlaybackFollow) {
                                Label("Resume Follow", systemImage: "location.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .padding(.horizontal, 14)
                                    .frame(height: 38)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.blue)
                            .background(.regularMaterial, in: Capsule())
                            .shadow(color: Color.black.opacity(0.12), radius: 12, y: 5)
                            .padding(.bottom, 48)
                        }
                    }
                    .allowsHitTesting(!isClosingScore && !isTransitioningScore)
            }
        }
    }

    @ViewBuilder
    private var noteEntryOverlay: some View {
        if readerState.isEditingMode && !plainTextEditorIsActive {
            ScoreReaderNoteEntrySurface(
                editingState: readerState.editingState,
                pendingPitchClass: readerState.pendingPitchClass,
                pendingMIDIPitch: readerState.pendingMIDIPitch,
                stackedChordInputEnabled: readerState.stackedChordInputEnabled,
                showsCompactModeToolbar: !isPhoneInterface,
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
                addLyricsHyphenAction: readerState.addLyricsHyphen,
                addLyricsMelismaAction: readerState.addLyricsMelisma,
                addRepeatJumpAction: readerState.addRepeatJump,
                addExpressionAction: readerState.addExpression,
                addLayoutBreakAction: requestLayoutBreak,
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
                openTransposeScoreAction: openTransposeScoreSheet,
                removeSelectedInstrumentAction: readerState.removeSelectedInstrument,
                openClefEditorAction: { isClefPickerPresented = true },
                openAutoBreaksAction: { isAutoBreaksPresented = true },
                openInstrumentLayoutAction: {
                    instrumentLayoutParts = displayedScoreParts
                    isInstrumentLayoutPresented = true
                },
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
                changeAccidentalAction: readerState.changeSelectedAccidental,
                removeChordPitchAction: readerState.removeMIDIPitchFromCurrentChord,
                semitoneShiftAction: readerState.shiftPitchBySemitones,
                octaveShiftAction: readerState.shiftPitchByOctaves
            )
            .padding(.bottom, 0)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { measuredNoteEntryPanelHeight = proxy.size.height }
                        .onChangeCompatible(of: proxy.size.height) { newHeight in
                            measuredNoteEntryPanelHeight = newHeight
                        }
                }
            )
        }
    }

    @ViewBuilder
    private var floatingPaletteOverlay: some View {
        if let floatingToolCategory, readerState.isEditingMode, !isPhoneInterface {
            ScoreReaderFloatingToolPalette(
                selectedToolCategory: floatingToolCategory,
                isDockedLeft: floatingPaletteDockedLeft,
                editingState: readerState.editingState,
                pendingPitchClass: readerState.pendingPitchClass,
                pendingAccidentalKind: readerState.pendingAccidentalKind,
                isBusy: readerState.isEditingActionInFlight,
                showsDockSideToggle: !isIPadLandscapeLayout,
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
                changeAccidentalAction: readerState.changeSelectedAccidental,
                openTempoEditorAction: { isTempoEditorPresented = true },
                toggleDockSideAction: { floatingPaletteDockedLeft.toggle() }
            )
            .scrollsVerticallyOnAndroid(maxHeight: floatingPaletteMaxHeight)
            .padding(.top, floatingPaletteTopPadding)
            .padding(floatingPaletteDockedLeft ? .leading : .trailing, 16)
        }
    }

    @ViewBuilder
    private var readerChromeOverlay: some View {
        if isChromeVisible || readerState.interactionMode != .view {
            ScoreReaderChromeBar(
            scoreTitle: readerState.scoreTitle,
            parts: displayedScoreParts,
            selectedPartID: $selectedPartID,
            isPartsPanelPresented: $isPartsPanelPresented,
            isExportPanelPresented: $isExportPanelPresented,
            supportsEditing: readerState.supportsEditing,
            interactionMode: readerState.interactionMode,
            readingStyle: $readingStyle,
            playbackFollowEnabled: $readerState.playbackFollowEnabled,
            supportsPlayback: session.capabilities.supportsPlayback,
            playbackState: readerState.playbackState,
            metronomeEnabled: readerState.metronomeEnabled,
            countInEnabled: readerState.countInEnabled,
            isCountingIn: readerState.isCountingIn,
            isEditingBusy: readerState.isEditingActionInFlight || isClosingScore || isTransitioningScore || isPreparingExport,
            isPlaybackBusy: readerState.isPlaybackActionInFlight || readerState.playbackPreparationMessage != nil,
            isExportBusy: isPreparingExport,
            supportsAnnotations: !isPhoneInterface && readerState.interactionMode == .view && annotationController.isEditable,
            annotationModeActive: isAnnotationModeActive,
            playbackPreparationMessage: readerState.playbackPreparationMessage,
            closeAction: closeReader,
            selectModeAction: selectModeFromToolbar,
            noteInputModeAction: noteInputModeFromToolbar,
            togglePlaybackAction: readerState.togglePlayback,
            stopPlaybackAction: readerState.stopPlayback,
            toggleMetronomeAction: readerState.toggleMetronome,
            toggleCountInAction: readerState.toggleCountIn,
            toggleMixerAction: {
                isPartsPanelPresented = false
                isExportPanelPresented = false
                withAnimation(.easeInOut(duration: 0.2)) { isMixerPresented.toggle() }
                isChromeVisible = true
            },
            isMixerPresented: isMixerPresented,
            exportAction: {
                isPartsPanelPresented = false
                if !isExportPanelPresented {
                    exportDraft.exportPartsInConcertPitch = readerState.concertPitchEnabled
                    exportDraft.exportPartsInOriginalKey = false
                    if selectedPartID == "full-score" {
                        exportDraft.includesFullScore = true
                        exportDraft.includesParts = false
                    } else {
                        exportDraft.includesFullScore = false
                        exportDraft.includesParts = true
                        exportDraft.selectedPartIDs = [selectedPartID]
                    }
                }
                isExportPanelPresented.toggle()
            },
            annotationAction: toggleAnnotationMode,
            editDoneAction: {
                if isAnnotationModeActive {
                    exitAnnotationMode()
                }
                toggleInteractionMode()
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
            allowsManagingParts: readerState.isEditingMode,
            exportPanelContent: {
                AnyView(
                    ScoreReaderExportPanel(
                        scoreTitle: readerState.scoreTitle,
                        sharingDescription: sharingDescription,
                        parts: displayedScoreParts,
                        isShowingTemporaryTransposedView: isShowingTemporaryTransposedView,
                        draft: $exportDraft,
                        isPreparingExport: isPreparingExport,
                        cancelAction: { isExportPanelPresented = false },
                        exportAction: exportScore,
                        exportProgress: exportProgress,
                        exportErrorMessage: exportErrorMessage,
                        openVideoSettingsAction: {
                            // A sheet shown from the popover stays small on iPad.
                            isExportPanelPresented = false
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(350))
                                isVideoSheetPresented = true
                            }
                        }
                    )
                )
            }
        )
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { measuredTopChromeHeight = proxy.size.height }
                    .onChangeCompatible(of: proxy.size.height) { newHeight in
                        measuredTopChromeHeight = newHeight
                    }
            }
        )
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var isolatedReaderCanvas: some View {
        #if os(Android)
        AndroidReaderObservationScope { readerCanvas }
        #else
        readerCanvas
        #endif
    }

    @ViewBuilder
    private var isolatedPhoneModeBar: some View {
        #if os(Android)
        AndroidReaderObservationScope { compactPhoneModeBar }
        #else
        compactPhoneModeBar
        #endif
    }

    private var readerLifecycleBody: some View {
        readerContent
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if readerState.isEditingMode && isPhoneInterface && !plainTextEditorIsActive {
                isolatedPhoneModeBar
            }
        }
        .onAppear { handleReaderAppear() }
        .task {
            readerState.playbackFollowEnabled = initialRememberedState.playbackFollowEnabled
            let rememberedPartIndex = rememberedPartIndexForInitialLoad()
            await readerState.prepareInitialViewState(
                rememberedViewKey: initialRememberedState.viewTransposeKey,
                partIndex: rememberedPartIndex
            )
            readerState.loadInitialPages()
            readerState.startPlaybackMonitoring()
            await readerState.prepareAnnotationMeasureRegionsIfNeeded()
            await readerState.prepareInitialInteractionMode()
            await reportReaderReadyWhenAvailable()
            if readerState.supportsEditing, let liveRenderSession = session.liveRenderSession {
                do {
                    let issues = try await liveRenderSession.legacyRepairIssues()
                    if !issues.isEmpty {
                        legacyRepairPrompt = ScoreLegacyRepairPrompt(issues: issues)
                    } else {
                        await presentReaderIntroductionIfNeeded()
                    }
                } catch {
                    // An inspection failure must never prevent the score from opening.
                    await presentReaderIntroductionIfNeeded()
                }
            } else {
                await presentReaderIntroductionIfNeeded()
            }
        }
        .onDisappear {
            unlockPhoneOrientation()
            saveRememberedReaderState()
            annotationController.flushSave()
            readerState.stopMIDIInput()
            readerState.shutdown()
        }
        .onChangeCompatible(of: scenePhase) { phase in
            switch phase {
            case .inactive, .background:
                readerState.saveRecoverySnapshotForBackground()
            case .active:
                readerState.resumeAutosaveAfterBackground()
            @unknown default:
                break
            }
        }
        #if os(Android)
        .background(AndroidReaderObservationScope { AndroidReaderEditObservers(reader: readerState,
            selectedToolCategory: $selectedToolCategory, clearSelectionMenu: clearSelectionCommandMenu,
            anchorAnnotations: { regions in
                annotationController.anchorPendingStrokes(partID: selectedPartID, regions: regions)
            }) })
        #else
        .onChangeCompatible(of: readerState.editingState.noteInputEnabled) { noteInputEnabled in
            selectedToolCategory = ScoreReaderToolModePolicy.category(
                afterSettingNoteInputEnabled: noteInputEnabled,
                currentCategory: selectedToolCategory
            )
        }
        .onChangeCompatible(of: readerState.editingState.selection?.kind) { selectionKind in
            if selectionKind == nil {
                clearSelectionCommandMenu()
            }

            if selectedToolCategory == .repeats && selectionKind == nil {
                selectedToolCategory = .select
            }
        }
        #endif
        .onChangeCompatible(of: readerState.interactionMode) { mode in
            updatePhoneOrientation(for: mode)
            isChromeVisible = true
            if mode != .edit {
                selectedToolCategory = .select
                clearSelectionCommandMenu()
                zoomScaleBeforeTextEntry = nil
            }
            if mode != .view, isAnnotationModeActive {
                exitAnnotationMode()
            }
            if mode == .edit, isPhoneInterface {
                // View mode intentionally returns to a full-page scale. Force the
                // preferred phone edit scale again on every edit invocation,
                // even when the device orientation has not changed.
                lastPhoneLandscapeZoomMode = nil
                applyPreferredPhoneZoomIfNeeded(for: UIScreen.main.bounds.size)
            } else if mode == .view {
                zoomScale = 1
            }
        }
        .onChangeCompatible(of: readerState.viewTransposeKey) { _ in
            saveRememberedReaderState()
        }
        .onChangeCompatible(of: readerState.selectedPageIndex) { _ in
            saveRememberedReaderState()
        }
        .onChangeCompatible(of: selectedPartID) { _ in
            annotationController.clearSelection()
            saveRememberedReaderState()
        }
        #if !os(Android)
        .onChangeCompatible(of: readerState.playbackMeasureRegions) { regions in
            annotationController.anchorPendingStrokes(partID: selectedPartID, regions: regions)
        }
        #endif
        .onChangeCompatible(of: zoomScale) { _ in
            saveRememberedReaderState()
        }
        .onChangeCompatible(of: readingStyle) { _ in
            zoomScale = 1
            saveRememberedReaderState()
        }
        .onChangeCompatible(of: readerState.playbackFollowEnabled) { enabled in
            if enabled {
                readerState.resumePlaybackFollow()
            }
            saveRememberedReaderState()
        }
        .onChangeCompatible(of: readerState.playbackState.status) { status in
            if status != .playing {
                isChromeVisible = true
            }
        }
        .onAppear {
            synchronizePartPresentation(with: displayedScoreParts, reselectActivePart: false)
        }
        .onChangeCompatible(of: readerState.scoreParts) { parts in
            synchronizePartPresentation(with: parts)
        }
    }

    private var readerSheetsBody: some View {
        readerLifecycleBody
        .scoreReaderSheet(item: $legacyRepairPrompt, onDismiss: {
            Task { await presentReaderIntroductionIfNeeded() }
        }) { prompt in
            ScoreLegacyRepairSheet(issues: prompt.issues) { selectedIndexes in
                try await applyLegacyRepairs(selectedIndexes, from: prompt)
            }
        }
        .scoreReaderSheet(isPresented: $isUpdateNoticePresented, onDismiss: {
            Task { await presentFeatureTourIfNeeded() }
        }) {
            UpdateNoticeSheet()
                .onAppear { updateNoticeStore.markNoticeSeen() }
        }
        .scoreReaderSheet(isPresented: Binding(
            get: { isMixerPresented && UIDevice.current.userInterfaceIdiom == .phone },
            set: { isMixerPresented = $0 }
        )) {
            ScoreReaderMixerPanel(readerState: readerState, selectedPartID: selectedPartID) {
                isMixerPresented = false
            }
            .presentationDetents([.height(285), .large])
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled)
        }
        .scoreReaderSheet(item: $textEditorDraft) { draft in
            ScoreReaderTextEditSheet(
                draft: draft,
                isBusy: readerState.isEditingActionInFlight,
                commitAction: { text, advanceToNextChord in
                    if draft.isLyrics {
                        readerState.addLyricsText(text, advanceToNextChord: advanceToNextChord)
                    } else if draft.isChordText {
                        if advanceToNextChord {
                            readerState.addChordTextAndSelectNext(text)
                        } else {
                            readerState.addChordText(text)
                        }
                    } else {
                        readerState.setSelectedText(text)
                    }
                    if !advanceToNextChord {
                        textEditorDraft = nil
                    }
                }
            )
        }
        .scoreReaderSheet(item: $sharedExportItems) { export in
            ScoreReaderShareSheetView(activityItems: export.urls)
        }
        .scoreReaderSheet(isPresented: $isVideoSheetPresented, onDismiss: {
            videoPreviewCache.reset()
            // A finished video returns to the score; otherwise back to the export options.
            if completedVideoURLs.isEmpty {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    isExportPanelPresented = true
                }
            }
            completedVideoURLs = []
        }) {
            ScoreReaderVideoExportSheet(
                draft: $exportDraft,
                isPreparingExport: isPreparingExport,
                exportProgress: exportProgress,
                exportErrorMessage: exportErrorMessage,
                exportAction: exportScore,
                cancelAction: { exportTask?.cancel() },
                completedVideos: completedVideoURLs,
                resetResultsAction: { completedVideoURLs = [] },
                renderPreview: { style, background in
                    guard let liveRenderSession = session.liveRenderSession else { return nil }
                    return await videoPreviewCache.image(
                        style: style, background: background, liveRenderSession: liveRenderSession,
                        pageCount: readerState.pageCount, title: readerState.scoreTitle,
                        composer: readerState.scoreMetadata.composer,
                        pinsStaffHeader: selectedPartID == "full-score" && pinsVideoStaffHeader,
                        vertical: exportDraft.videoVertical)
                }
            )
        }
        .scoreReaderSheet(isPresented: $isTempoEditorPresented) {
            ScoreReaderTempoEditorSheet(
                initialValue: readerState.editingState.selection?.tempoValue ?? TempoValue(beatUnit: .quarter, bpm: 112),
                isBusy: readerState.isEditingActionInFlight,
                commitAction: readerState.addTempo
            )
        }
        .scoreReaderSheet(isPresented: $isTimeSignaturePresented) {
            ScoreReaderTimeSignatureSheet(
                currentValue: readerState.editingState.selection?.currentTimeSignatureValue ?? ScoreTimeSignatureValue(numerator: 4, denominator: 4),
                isBusy: readerState.isEditingActionInFlight,
                commitAction: readerState.updateTimeSignature
            )
        }
        .scoreReaderSheet(isPresented: $isKeySignaturePresented) {
            ScoreReaderKeySignatureSheet(
                currentKeyValue: readerState.editingState.selection?.currentKey ?? 0,
                isBusy: readerState.isEditingActionInFlight,
                commitAction: readerState.updateKeySignature
            )
        }
        .scoreReaderSheet(item: $readerState.pickupEditorContext) { context in
            ScoreReaderPickupEditorSheet(
                context: context,
                isBusy: readerState.isEditingActionInFlight,
                applyAction: { numerator, denominator in
                    readerState.applyPickupMeasure(numerator: numerator, denominator: denominator)
                },
                removeAction: readerState.removePickupMeasure
            )
        }
        .scoreReaderSheet(isPresented: $isScoreSetupPresented) {
            ScoreReaderSetupSheet(
                metadata: readerState.scoreMetadata,
                isBusy: readerState.isEditingActionInFlight,
                loadAction: { await readerState.loadScoreMetadata() },
                commitAction: { try await readerState.updateScoreSetupMetadata($0) }
            )
        }
        .scoreReaderSheet(isPresented: $isPageSettingsPresented) {
            ScoreReaderPageSettingsSheet(
                initialValue: readerState.editingState.pageSettings,
                isBusy: readerState.isEditingActionInFlight,
                commitAction: readerState.updatePageLayout
            )
        }
        .scoreReaderSheet(isPresented: $isInstrumentLayoutPresented) {
            ScoreReaderInstrumentLayoutSheet(
                parts: $instrumentLayoutParts,
                isBusy: readerState.isEditingActionInFlight,
                setVisibilityAction: { partIndex, visible in
                    readerState.setInstrumentVisible(at: partIndex, visible: visible)
                },
                moveAction: { source, destination in
                    readerState.moveInstrument(from: source, to: destination)
                }
            )
        }
        .scoreReaderSheet(item: $instrumentReplacementContext) { context in
            ScoreReaderInstrumentReplacementSheet(
                context: context,
                isBusy: readerState.isEditingActionInFlight,
                replaceAction: { instrument, scope in
                    readerState.replaceInstrument(with: instrument, context: context, scope: scope)
                }
            )
        }
        .scoreReaderSheet(item: $transposeSheetContext) { context in
            ScoreReaderTransposePanel(
                currentKey: context.currentKey,
                title: context.scope == .score ? "Transpose Score" : "Transpose",
                isSheetStyle: true,
                cancelAction: { transposeSheetContext = nil },
                applyAction: { request in
                    transposeSheetContext = nil
                    switch context.scope {
                    case .selection:
                        readerState.transposeSelectedMeasureRange(request)
                    case .score:
                        readerState.transposeScore(request)
                    }
                }
            )
            .presentationDetents([.large])
        }
        .scoreReaderSheet(isPresented: $isAutoBreaksPresented) {
            ScoreReaderAutoSystemBreaksSheet(
                isBusy: readerState.isEditingActionInFlight,
                commitAction: readerState.applyAutoSystemBreaks
            )
        }
        .scoreReaderSheet(isPresented: $isAddMeasuresPresented) {
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
    }

    private var readerPresentedBody: some View {
        readerSheetsBody
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
        .alert("Edit Not Applied", isPresented: editErrorIsPresented) {
            Button("OK", role: .cancel) {
                readerState.editingErrorMessage = nil
            }
        } message: {
            Text(readerState.editingErrorMessage ?? "Aria could not apply that edit.")
        }
        .alert("View Key Not Changed", isPresented: viewTransposeErrorIsPresented) {
            Button("OK", role: .cancel) {
                readerState.viewTransposeErrorMessage = nil
            }
        } message: {
            Text(readerState.viewTransposeErrorMessage ?? "Aria could not change the temporary viewing key.")
        }
        // Drive the hidden state from scenePhase so locking/unlocking forces
        // SwiftUI to re-push preferredStatusBarHidden. Otherwise the bar can stay
        // collapsed after unlock and the library underlaps the status bar.
        .statusBarHidden(scenePhase == .active)
        .background(
            ScoreReaderKeyboardShortcutView(
                isEnabled: keyboardShortcutsAreEnabled,
                action: handleKeyboardShortcut
            )
            .frame(width: 0, height: 0)
        )
    }

    @MainActor
    private func applyLegacyRepairs(_ indexes: [Int], from prompt: ScoreLegacyRepairPrompt) async throws {
        guard let liveRenderSession = session.liveRenderSession, !indexes.isEmpty else {
            throw ScoreDocumentServiceError.bridgeFailure("No score fixes were selected.")
        }
        guard await readerState.savePendingChanges() else {
            throw ScoreDocumentServiceError.bridgeFailure(readerState.editingErrorMessage ?? "Aria could not save current edits before making a backup.")
        }
        let currentIssues = try await liveRenderSession.legacyRepairIssues()
        guard currentIssues == prompt.issues else {
            throw ScoreDocumentServiceError.bridgeFailure("The score changed. Close and reopen it to review the fixes again.")
        }

        let scoreURL = session.document.url
        _ = try await Task.detached(priority: .userInitiated) {
            try ScoreLegacyRepairBackup.createUntouchedCopy(of: scoreURL)
        }.value

        let editingState = try await liveRenderSession.applyLegacyRepairs(indexes)
        let remaining = try await liveRenderSession.legacyRepairIssues()
        guard remaining.count == currentIssues.count - indexes.count else {
            throw ScoreDocumentServiceError.bridgeFailure("Aria made a repair, but could not verify every selected issue. The untouched backup is in Aria Backups.")
        }
        readerState.refreshAfterScoreMutation(with: editingState)
        guard await readerState.savePendingChanges() else {
            throw ScoreDocumentServiceError.bridgeFailure("The fixes could not be saved. The untouched backup is in Aria Backups.")
        }
    }

    private var floatingToolCategory: ScoreReaderToolCategory? {
        guard !isPhoneInterface else {
            return nil
        }

        switch selectedToolCategory {
        case .notes, .repeats, .text, .expression:
            return selectedToolCategory
        case .chord, .lyrics, .layout, .more:
            return nil
        case .select:
            break
        }

        guard let selection = readerState.editingState.selection else {
            return .notes
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
            return nil
        case .instrumentName, .instrumentChange:
            return nil
        case .layoutBreak:
            return nil
        case .dynamic, .expressionSpanner, .tie, .marker:
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

    private var sharingDescription: String {
        let scoreOrPart = selectedPartID == "full-score"
            ? "Full Score"
            : (displayedScoreParts.first(where: { $0.id == selectedPartID })?.name ?? "Current Part")
        let pitch = readerState.concertPitchEnabled ? "Concert Pitch" : "Written Pitch"
        return "\(scoreOrPart) · \(pitch)"
    }

    private var isPhoneInterface: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    private var compactPhoneModeBar: some View {
        ScoreReaderModeToolbar(
            isBusy: readerState.isEditingActionInFlight,
            isCompact: true,
            selectedToolCategory: $selectedToolCategory,
            selectModeAction: {
                selectedToolCategory = .select
                selectModeFromToolbar()
            },
            noteInputModeAction: {
                selectedToolCategory = .notes
                noteInputModeFromToolbar()
            },
            isMeasureSelection: readerState.editingState.selection?.kind == .measure,
            isSingleMeasureSelection: readerState.editingState.selection?.kind == .measure
                && readerState.editingState.selection?.isSingleMeasure == true
        )
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .padding(.bottom, 2)
        .background {
            compactPhoneModeBarBackground
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(height: 0.5)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var compactPhoneModeBarBackground: some View {
        let shape = Rectangle()

        if #available(iOS 26.0, *) {
            shape
                .fill(Color.white.opacity(0.22))
                .glassEffect(.regular, in: shape)
                .ignoresSafeArea(.container, edges: .bottom)
        } else {
            shape
                .fill(.regularMaterial)
                .ignoresSafeArea(.container, edges: .bottom)
        }
    }

    private func updatePhoneOrientation(for mode: ScoreReaderInteractionMode) {
        guard isPhoneInterface else {
            return
        }

        MuseReaderAppDelegate.updateSupportedInterfaceOrientations(
            mode == .edit ? .portrait : .all
        )
    }

    private func unlockPhoneOrientation() {
        guard isPhoneInterface else {
            return
        }

        MuseReaderAppDelegate.updateSupportedInterfaceOrientations(.all)
    }

    private var floatingPaletteTopPadding: CGFloat {
        let bounds = UIScreen.main.bounds
        if floatingToolCategory == .notes && bounds.width > bounds.height {
            return 108
        }
        return 148
    }

    /// The space between the palette's top and the bottom panel.
    private var floatingPaletteMaxHeight: CGFloat {
        UIScreen.main.bounds.height - floatingPaletteTopPadding - measuredNoteEntryPanelHeight - 16
    }

    private var isIPadLandscapeLayout: Bool {
        !isPhoneInterface && UIScreen.main.bounds.width > UIScreen.main.bounds.height
    }

    private var floatingPaletteAlignment: Alignment {
        floatingPaletteDockedLeft ? .topLeading : .topTrailing
    }

    private var floatingPanelTopPadding: CGFloat {
        isPhoneInterface ? 72 : 54
    }

    @ViewBuilder
    private var readerCanvas: some View {
        if readerState.interactionMode == .view, readingStyle == .pageTurn {
            pageTurnReaderCanvas
        } else {
            continuousReaderCanvas
        }
    }

    private var usesTwoPageSpread: Bool {
        readerState.interactionMode == .view
        && readingStyle == .pageTurn
        && twoPageViewEnabled
        && readerState.pageCount > 1
    }

    private var twoPageSpreadStartIndex: Int {
        guard readerState.pageCount > 0 else {
            return 0
        }

        let boundedIndex = min(max(readerState.selectedPageIndex, 0), readerState.pageCount - 1)
        return boundedIndex - (boundedIndex % 2)
    }

    private var twoPageSpreadIndices: [Int] {
        guard readerState.pageCount > 0 else {
            return []
        }

        return [twoPageSpreadStartIndex, twoPageSpreadStartIndex + 1]
            .filter { $0 < readerState.pageCount }
    }

    private var twoPageSpreadEndIndex: Int {
        min(twoPageSpreadStartIndex + 1, max(readerState.pageCount - 1, 0))
    }

    private var showsViewModePageControls: Bool {
        readingStyle == .pageTurn && readerState.pageCount > 1
    }

    /// View mode's bottom row. The side slots share the leftover width equally,
    /// so the page slider stays centred and never overlaps the side controls.
    private var viewModeBottomBar: some View {
        HStack(alignment: .bottom, spacing: 12) {
            Group {
                if showsViewModePageControls {
                    twoPageViewButton
                }
                #if os(Android)
                if !showsViewModePageControls {
                    // Skip removes an empty Group, including its width modifier.
                    // Keep the leading slot so a lone key chip stays at the right edge.
                    Color.clear.frame(width: 1, height: 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                #endif
            }
            #if os(Android)
            .frame(width: viewModeBottomBarWidths.side, alignment: .leading)
            #else
            .frame(maxWidth: .infinity, alignment: .leading)
            #endif

            if showsViewModePageControls {
                ScoreReaderPageScrubber(
                    pageCount: readerState.pageCount,
                    currentPageIndex: readerState.selectedPageIndex,
                    usesTwoPageSpread: usesTwoPageSpread,
                    commitAction: showPageFromScrubber
                )
                #if os(Android)
                .frame(width: viewModeBottomBarWidths.scrubber)
                #else
                .frame(minWidth: 120, maxWidth: 520)
                #endif
                .padding(.bottom, 10)
            }

            Group {
                if let viewKey = readerState.viewTransposeKey {
                    ScoreReaderViewKeyControl(
                        currentKey: viewKey,
                        originalKey: readerState.viewTransposeSourceKey ?? viewKey,
                        isBusy: readerState.isViewTransposeActionInFlight,
                        selectKey: readerState.setTemporaryViewKey
                    )
                    .padding(.bottom, 10)
                }
                #if os(Android)
                if readerState.viewTransposeKey == nil {
                    Color.clear.frame(width: 1, height: 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                #endif
            }
            #if os(Android)
            .frame(width: viewModeBottomBarWidths.side, alignment: .trailing)
            #else
            .frame(maxWidth: .infinity, alignment: .trailing)
            #endif
        }
        .padding(.horizontal, 14)
    }

    #if os(Android)
    /// Skip's HStack doesn't share width between flexible children (the slider took the
    /// whole row), so the iOS layout's widths are worked out here: the slider gets a
    /// third of the row, between 120 and 520, and the side slots split the rest.
    private var viewModeBottomBarWidths: (side: CGFloat, scrubber: CGFloat) {
        let available = UIScreen.main.bounds.width - 28 - (showsViewModePageControls ? 24 : 12)
        let scrubber = showsViewModePageControls ? min(520, max(120, available / 3)) : 0
        return (max((available - scrubber) / 2, 0), scrubber)
    }
    #endif

    private var twoPageViewButton: some View {
        Button(action: toggleTwoPageView) {
            VStack(spacing: 4) {
                ScoreReaderTwoPageViewIcon(isActive: twoPageViewEnabled)
                    .frame(width: 38, height: 34)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: Color.black.opacity(0.10), radius: 10, y: 4)

                Text("Two-page view")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.68))
                    .lineLimit(1)
            }
            .fixedSize()
        }
        .buttonStyle(.plain)
        .padding(.bottom, 10)
        .accessibilityLabel(twoPageViewEnabled ? "Use single-page view" : "Use two-page view")
        .accessibilityValue(twoPageViewEnabled ? "Two pages" : "One page")
    }

    private func toggleTwoPageView() {
        let spreadStartIndex = twoPageSpreadStartIndex
        withAnimation(.easeInOut(duration: 0.22)) {
            twoPageViewEnabled.toggle()
            zoomScale = 1
        }

        if twoPageViewEnabled {
            readerState.updatePageTurnSelection(to: spreadStartIndex)
            for pageIndex in twoPageSpreadIndices {
                readerState.prefetchPage(pageIndex)
            }
        }
    }

    private var pageTurnReaderCanvas: some View {
        GeometryReader { geometry in
            Group {
                if usesTwoPageSpread {
                    let spreadSpacing: CGFloat = 8
                    let spreadWidth = max(geometry.size.width - 24, 1)
                    let pageViewportWidth = max((spreadWidth - spreadSpacing) / 2, 1)
                    let pageViewportSize = CGSize(
                        width: pageViewportWidth,
                        height: max(geometry.size.height - 24, 1)
                    )

                    HStack(spacing: spreadSpacing) {
                        ForEach(twoPageSpreadIndices, id: \.self) { pageIndex in
                            scorePageCanvas(
                                pageIndex: pageIndex,
                                geometry: geometry,
                                isPageTurn: true,
                                pageTurnViewportOverride: pageViewportSize
                            )
                            .frame(width: pageViewportWidth, height: pageViewportSize.height)
                            .id(pageIndex)
                            .onAppear {
                                readerState.prefetchPage(pageIndex)
                            }
                        }
                    }
                    .frame(width: spreadWidth, height: pageViewportSize.height)
                    .overlay {
                        if geometry.size.width > geometry.size.height {
                            Color.clear
                                .frame(width: 44, height: pageViewportSize.height)
                                .contentShape(Rectangle())
                                .onTapGesture(perform: toggleViewChrome)
                                .accessibilityElement()
                                .accessibilityLabel("Show or hide viewer controls")
                                .accessibilityAddTraits(.isButton)
                        }
                    }
                } else {
                    ZStack {
                        ForEach(
                            ScorePageTurnPlan.residentIndices(
                                focusedPageIndex: readerState.selectedPageIndex,
                                pageCount: readerState.pageCount
                            ),
                            id: \.self
                        ) { pageIndex in
                            let isSelectedPage = pageIndex == readerState.selectedPageIndex
                            scorePageCanvas(
                                pageIndex: pageIndex,
                                geometry: geometry,
                                isPageTurn: true,
                                isActivePage: isSelectedPage
                            )
                            .id(pageIndex)
                            .opacity(isSelectedPage ? 1 : 0)
                            .zIndex(isSelectedPage ? 1 : 0)
                            .allowsHitTesting(isSelectedPage)
                            .accessibilityHidden(!isSelectedPage)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(12)
        }
        #if !os(Android)
        // Android's page-local pointer detector arbitrates held selection versus
        // page swipes. An ancestor simultaneous observer ignores consumed moves
        // and would turn the page even after the child owns a held range drag.
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    guard !isAnnotationModeActive else {
                        return
                    }
                    guard let direction = ScoreReaderPageSwipePolicy.direction(for: value.translation) else {
                        return
                    }
                    switch direction {
                    case .previous:
                        showPreviousPage()
                    case .next:
                        showNextPage()
                    }
                }
        )
        #endif
    }

    private var continuousReaderCanvas: some View {
        GeometryReader { geometry in
            let isCompactPhoneLayout = isPhoneInterface
            let isPhoneLandscapeLayout = isCompactPhoneLayout && geometry.size.width > geometry.size.height
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 28) {
                        ForEach(readerState.pageIndices, id: \.self) { pageIndex in
                            scorePageCanvas(pageIndex: pageIndex, geometry: geometry, isPageTurn: false)
                            .id(pageIndex)
                            .onAppear {
                                readerState.prefetchPage(pageIndex)
                            }
                        }

                        if readerState.interactionMode == .view, let setlistNavigation {
                            if let nextTitle = setlistNavigation.nextScoreTitle {
                                Button {
                                    transitionToAdjacentScore(.next)
                                } label: {
                                    VStack(spacing: 6) {
                                        Text("Next Score")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(Color.blue)
                                        Text(nextTitle)
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundStyle(Color.black.opacity(0.82))
                                            .lineLimit(2)
                                        Text(setlistNavigation.positionLabel)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(Color.black.opacity(0.52))
                                    }
                                    .frame(maxWidth: 520)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 20)
                                    .padding(.horizontal, 24)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .disabled(isTransitioningScore)
                                .accessibilityLabel("Next Score, \(nextTitle)")
                                .padding(.horizontal, 24)
                            } else {
                                VStack(spacing: 5) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 24, weight: .semibold))
                                        .foregroundStyle(Color.blue)
                                    Text("End of Setlist")
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundStyle(Color.black.opacity(0.78))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                    .padding(.top, readerState.isEditingMode ? 0 : 24)
                    .padding(.bottom, scrollContentBottomInset(isCompactPhoneLayout: isCompactPhoneLayout, isPhoneLandscapeLayout: isPhoneLandscapeLayout))
                    .padding(.horizontal, readerState.isEditingMode || isCompactPhoneLayout ? 0 : 24)
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { _ in
                            readerState.suspendPlaybackFollow()
                        }
                )
                .coordinateSpace(name: ScoreReaderSelectionCommandAnchor.coordinateSpaceName)
                #if os(Android)
                .environment(selectionCommandPresentation)
                #else
                .onPreferenceChange(ScoreReaderSelectionCommandAnchorPreferenceKey.self) { anchor in
                    if anchor?.identity == dismissedSelectionCommandIdentity {
                        // The dismissed selection is back (undo): keep its button hidden, and
                        // don't leave the previous selection's button on screen.
                        selectionCommandAnchor = nil
                    } else {
                        // A different selection: the earlier dismissal no longer applies.
                        dismissedSelectionCommandIdentity = nil
                        selectionCommandAnchor = anchor
                    }
                }
                #endif
                .task {
                    applyPreferredPhoneZoomIfNeeded(for: geometry.size)
                    proxy.scrollTo(readerState.selectedPageIndex, anchor: .top)
                }
                .onChangeCompatible(of: geometry.size) { newSize in
                    applyPreferredPhoneZoomIfNeeded(for: newSize)
                }
                .onChangeCompatible(of: readerState.selectedPageIndex) { newValue in
                    if activeNotationFocusIsActive, readerState.editingState.selection?.pageIndex == newValue {
                        revealActiveNotation(using: proxy)
                        DispatchQueue.main.async {
                            revealActiveNotation(using: proxy)
                        }
                        return
                    }

                    guard (readerState.playbackState.status == .playing && readerState.shouldFollowPlayback)
                        || readerState.isRepairingCorruption
                    else {
                        return
                    }

                    withAnimation(.easeInOut(duration: 0.24)) {
                        proxy.scrollTo(newValue, anchor: .top)
                    }
                }
                .onChangeCompatible(of: readerState.activeNotationAutoScrollRevision) { _ in
                    revealActiveNotation(using: proxy)
                    DispatchQueue.main.async {
                        revealActiveNotation(using: proxy)
                    }
                }
                .onChangeCompatible(of: playbackScrollTarget) { target in
                    guard
                        target != nil,
                        readerState.playbackState.status == .playing,
                        readerState.shouldFollowPlayback,
                        zoomScale <= 1.01
                    else {
                        return
                    }

                    revealPlayback(using: proxy)
                    DispatchQueue.main.async {
                        revealPlayback(using: proxy)
                    }
                }
                .onChangeCompatible(of: selectedToolCategory) { oldValue, newValue in
                    handleToolCategoryChange(from: oldValue, to: newValue)
                }
                .onAppear {
                    applyInitialToolCategoryIfNeeded()
                }
            }
        }
    }

    private func scorePageCanvas(
        pageIndex: Int,
        geometry: GeometryProxy,
        isPageTurn: Bool,
        isActivePage: Bool = true,
        pageTurnViewportOverride: CGSize? = nil
    ) -> some View {
        let isCompactPhoneLayout = isPhoneInterface
        let isPhoneLandscapeLayout = isCompactPhoneLayout && geometry.size.width > geometry.size.height
        let editingEnabled = readerState.isEditingMode
        let defaultPageTurnViewport = CGSize(
            width: max(geometry.size.width - 24, 1),
            height: max(geometry.size.height - 24, 1)
        )
        let pageTurnViewport = pageTurnViewportOverride ?? defaultPageTurnViewport
        let currentHighlight = readerState.playbackMeasureHighlight(for: pageIndex)
        #if os(Android)
        // Fractional playback position belongs to the child overlay model. The
        // page/follow inputs carry only the measure's spatial identity.
        let pageHighlight = currentHighlight.map {
            ScorePlaybackMeasureHighlight(pageIndex: $0.pageIndex, normalizedRect: $0.normalizedRect, progress: 0)
        }
        #else
        let pageHighlight = currentHighlight
        #endif

        return ScoreReaderPageCanvas(
            pageIndex: pageIndex,
            page: readerState.page(at: pageIndex),
            isLoading: readerState.isLoadingPage(pageIndex),
            errorText: readerState.pageErrorMessage(for: pageIndex),
            playbackHighlight: pageHighlight,
            playFromHereTarget: readerState.playFromHereTarget(for: pageIndex),
            playbackLoopRange: readerState.playbackLoopRange(for: pageIndex),
            playbackLoopIsActive: readerState.playbackLoopIsActive,
            selectedElement: editingEnabled ? readerState.selectedElement(for: pageIndex) : nil,
            noteEntryPreview: editingEnabled ? readerState.noteEntryPreview(for: pageIndex) : nil,
            zoomScale: isActivePage ? $zoomScale : .constant(1),
            availableWidth: isPageTurn || editingEnabled
                ? (isPageTurn ? pageTurnViewport.width : geometry.size.width)
                : geometry.size.width - (isCompactPhoneLayout ? 0 : 48),
            viewportSize: isPageTurn ? pageTurnViewport : geometry.size,
            isCompactPhoneLayout: isCompactPhoneLayout,
            floatingPaletteDockedLeft: floatingPaletteDockedLeft,
            activeNotationTopInset: editingEnabled ? activeNotationTopInset(isCompactPhoneLayout: isCompactPhoneLayout) : 0,
            activeNotationBottomInset: editingEnabled ? activeNotationBottomInset(isCompactPhoneLayout: isCompactPhoneLayout, isPhoneLandscapeLayout: isPhoneLandscapeLayout) : 0,
            allowsPencilInsertionFineTune: editingEnabled && readerState.editingState.noteInputEnabled,
            noteEntryPreviewPitchClass: editingEnabled ? readerState.pendingPitchClass : nil,
            noteEntryPreviewIsRest: editingEnabled && readerState.editingState.noteInputInsertsRests,
            noteEntryPreviewDuration: readerState.editingState.duration,
            showsLayoutMarkers: editingEnabled && selectedToolCategory == .layout,
            activeNotationAutoScrollRevision: readerState.activeNotationAutoScrollRevision,
            fitsPageToViewport: isPageTurn,
            allowsEditingInteractions: editingEnabled,
            allowsPlaybackFollow: readerState.shouldFollowPlayback,
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
            changeSelectedEnharmonicSpellingAction: readerState.changeSelectedEnharmonicSpelling,
            addExpressionAction: readerState.addExpression,
            tapAction: { normalizedPoint, inputKind in
                readerState.dismissPlayFromHere()
                if editingEnabled {
                    clearSelectionCommandMenu()
                    readerState.handlePageTap(
                        pageIndex: pageIndex,
                        normalizedPoint: normalizedPoint,
                        inputKind: inputKind
                    ) { selection in
                        if selection?.kind == .instrumentName {
                            presentInstrumentReplacement()
                        }
                    }
                } else if isPageTurn {
                    handleViewModePageTap(normalizedPoint, pageIndex: pageIndex)
                } else {
                    toggleViewChrome()
                }
            },
            selectedNoteDragAction: { dropPoint in
                readerState.dragSelectedNote(pageIndex: pageIndex, normalizedPoint: dropPoint)
            },
            expressionEndpointDragAction: { startEndpoint, dropPoint in
                readerState.retargetSelectedExpressionEndpoint(start: startEndpoint, pageIndex: pageIndex, normalizedPoint: dropPoint)
            },
            selectedMovableElementDragAction: { dropPoint in
                readerState.dragSelectedMovableElement(pageIndex: pageIndex, normalizedPoint: dropPoint)
            },
            measureRangePreviewAction: { startPoint, endPoint in
                readerState.previewMeasureRange(pageIndex: pageIndex, startNormalizedPoint: startPoint, endNormalizedPoint: endPoint)
            },
            measureRangePreviewEndAction: readerState.clearMeasureRangePreview,
            measureRangeDragAction: { startPoint, endPoint in
                readerState.selectMeasureRange(pageIndex: pageIndex, startNormalizedPoint: startPoint, endNormalizedPoint: endPoint)
            },
            pencilInsertionFineTuneAction: { startPoint, dropPoint in
                readerState.handlePencilNoteEntryFineTune(pageIndex: pageIndex, startNormalizedPoint: startPoint, dropNormalizedPoint: dropPoint)
            },
            pencilHoverPreviewAction: { normalizedPoint in
                readerState.updateNoteEntryPreview(pageIndex: pageIndex, normalizedPoint: normalizedPoint)
            },
            pencilInteractionStartAction: activatePencilNoteEntryMode,
            pencilDoubleTapAction: toggleNoteInputFromPencilDoubleTap,
            swipePreviousPageAction: showPreviousPage,
            swipeNextPageAction: showNextPage,
            viewModeLongPressAction: { startPoint, endPoint in
                presentViewModePlaybackSelection(
                    from: startPoint,
                    through: endPoint,
                    pageIndex: pageIndex
                )
            },
            playFromHereAction: readerState.playFromHere,
            loopFromHereAction: readerState.loopFromHere,
            togglePlaybackLoopAction: readerState.toggleSelectedPlaybackLoop,
            manualScrollAction: {
                readerState.suspendPlaybackFollow()
                readerState.dismissPlayFromHere()
            },
            annotationConfiguration: annotationConfiguration(for: pageIndex)
        )
        #if os(Android)
        .environment(\.ariaPlaybackPageIndex, pageIndex)
        .environment(\.ariaRasterVisible, isActivePage)
        #endif
    }

    private var annotationColor: ScoreAnnotationColor {
        annotationTool == .highlighter ? annotationHighlighterColor : annotationMarkerColor
    }

    private var annotationWidth: Double {
        annotationTool == .highlighter ? annotationHighlighterWidth : annotationMarkerWidth
    }

    private var annotationColorBinding: Binding<ScoreAnnotationColor> {
        Binding(
            get: { annotationColor },
            set: { color in
                if annotationTool == .highlighter {
                    annotationHighlighterColor = color
                } else {
                    annotationMarkerColor = color
                }
            }
        )
    }

    private var annotationWidthBinding: Binding<Double> {
        Binding(
            get: { annotationWidth },
            set: { width in
                if annotationTool == .highlighter {
                    annotationHighlighterWidth = width
                } else {
                    annotationMarkerWidth = width
                }
            }
        )
    }

    private func annotationConfiguration(for pageIndex: Int) -> ScoreAnnotationPageConfiguration {
        let regions = readerState.playbackMeasureRegions
        return ScoreAnnotationPageConfiguration(
            strokes: annotationController.renderedStrokes(
                pageIndex: pageIndex,
                partID: selectedPartID,
                regions: regions
            ),
            selectedStrokeIDs: annotationController.selectedStrokeIDs,
            isActive: isAnnotationModeActive,
            isVisible: annotationsVisible && readerState.interactionMode == .view,
            allowsInteraction: !isPhoneInterface && readerState.interactionMode == .view && annotationController.isEditable,
            tool: annotationTool,
            color: annotationColor,
            width: annotationWidth,
            interactionStartAction: beginAnnotationFromCanvas,
            strokeCommitAction: { pagePoints in
                annotationController.commitStroke(
                    pageIndex: pageIndex,
                    partID: selectedPartID,
                    tool: annotationTool,
                    color: annotationColor,
                    width: annotationWidth,
                    pagePoints: pagePoints,
                    regions: readerState.playbackMeasureRegions
                )
                finishAutomaticAnnotationEntryIfNeeded()
            },
            eraseAction: { pagePoints in
                #if os(Android)
                // Android erases as the finger moves (AndroidZoomableImageView); an empty
                // call ends the gesture.
                guard !pagePoints.isEmpty else {
                    annotationController.endEraseGesture()
                    return
                }
                annotationController.erase(
                    pageIndex: pageIndex,
                    partID: selectedPartID,
                    along: pagePoints,
                    regions: readerState.playbackMeasureRegions,
                    continuesGesture: true
                )
                #else
                annotationController.erase(
                    pageIndex: pageIndex,
                    partID: selectedPartID,
                    along: pagePoints,
                    regions: readerState.playbackMeasureRegions
                )
                #endif
            },
            lassoAction: { pageRect in
                annotationController.selectStrokes(
                    pageIndex: pageIndex,
                    partID: selectedPartID,
                    in: pageRect,
                    regions: readerState.playbackMeasureRegions
                )
            },
            moveSelectionAction: { delta in
                annotationController.moveSelectedStrokes(
                    by: delta,
                    regions: readerState.playbackMeasureRegions
                )
            }
        )
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

    private var playbackScrollTarget: ScoreReaderPlaybackScrollTarget? {
        guard let highlight = readerState.playbackMeasureHighlight else {
            return nil
        }

        return ScoreReaderPlaybackScrollTarget(
            pageIndex: highlight.pageIndex,
            normalizedRect: highlight.normalizedRect
        )
    }

    private var isShowingTemporaryTransposedView: Bool {
        readerState.interactionMode == .view
            && readerState.viewTransposeKey != nil
            && readerState.viewTransposeKey != readerState.viewTransposeSourceKey
    }

    private func revealPlayback(using proxy: ScrollViewProxy) {
        guard let target = playbackScrollTarget else {
            return
        }

        withAnimation(.easeInOut(duration: 0.22)) {
            proxy.scrollTo(
                ScoreReaderPageCanvas.playbackAnchorID(for: target.pageIndex),
                anchor: .top
            )
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

    private var keyboardShortcutsAreEnabled: Bool {
        !isClosingScore
            && !isTransitioningScore
            && !textEntryFocusIsActive
            && textEditorDraft == nil
            && !isPartsPanelPresented
            && !isMixerPresented
            && !isExportPanelPresented
            && sharedExportItems == nil
            && !isTempoEditorPresented
            && !isTimeSignaturePresented
            && !isKeySignaturePresented
            && !isScoreSetupPresented
            && !isPageSettingsPresented
            && !isInstrumentLayoutPresented
            && instrumentReplacementContext == nil
            && transposeSheetContext == nil
            && !isAddMeasuresPresented
            && !isAutoBreaksPresented
            && !isAddInstrumentPresented
            && !isClefPickerPresented
            && readerState.pickupEditorContext == nil
            && exportErrorMessage == nil
            && readerState.editingErrorMessage == nil
    }

    private func handleKeyboardShortcut(_ shortcut: ScoreReaderKeyboardShortcut) {
        guard keyboardShortcutsAreEnabled else {
            return
        }

        guard readerState.isEditingMode else {
            switch shortcut {
            case .togglePlayback:
                readerState.togglePlayback()
            // Page-turn pedals send Page Up/Down or the arrow keys.
            case .previousPage, .selectPrevious, .movePitch(up: true):
                showPreviousPage()
            case .nextPage, .selectNext, .movePitch(up: false):
                showNextPage()
            default:
                break
            }
            return
        }

        switch shortcut {
        case .undo:
            readerState.undoEdit()
        case .redo:
            readerState.redoEdit()
        case .copy:
            readerState.copySelectedMeasureRange()
        case .cut:
            readerState.cutSelectedMeasureRange()
        case .paste:
            readerState.pasteMeasureRange()
        case .selectAll:
            readerState.selectAll()
        case .delete:
            readerState.deleteSelection()
        case .togglePlayback:
            readerState.togglePlayback()
        case .clearSelection:
            clearSelectionCommandMenu()
            readerState.clearSelection()
        case .selectPrevious:
            readerState.selectPreviousElement()
        case .selectNext:
            readerState.selectNextElement()
        case .toggleNoteInput:
            readerState.toggleNoteInput()
        case .enterPitch(let pitchClass):
            readerState.handleKeyboardPitch(pitchClass, midiPitch: nil, preferFlats: false)
        case .applyDuration(let duration):
            readerState.applyDuration(duration)
        case .enterRest:
            readerState.toggleRest()
        case .toggleDot:
            readerState.toggleDot()
        case .toggleTie:
            readerState.toggleTie()
        case .addSlur:
            readerState.addSlur()
        case .selectVoice(let voice):
            readerState.setCurrentVoice(voice)
        case .movePitch(let up):
            readerState.movePitch(up: up)
        case .shiftOctave(let octaveDelta):
            readerState.shiftPitchByOctaves(octaveDelta)
        case .shiftSemitone(let semitoneDelta):
            readerState.shiftPitchBySemitones(semitoneDelta)
        case .previousPage, .nextPage:
            // Editing scrolls the score instead of turning pages.
            break
        }
    }

    /// Whether auto-scroll should keep the selected bar inside the unobstructed
    /// viewport. Active for chord/lyric entry and for continuous note input,
    /// where the bottom note-entry keyboard can otherwise hide the active bar.
    private var activeNotationFocusIsActive: Bool {
        guard readerState.isEditingMode else {
            return false
        }

        return textEntryFocusIsActive || readerState.editingState.noteInputEnabled
    }

    private func scrollContentBottomInset(isCompactPhoneLayout: Bool, isPhoneLandscapeLayout: Bool) -> CGFloat {
        guard readerState.isEditingMode else {
            return 40
        }

        if plainTextEditorIsActive {
            return 40
        }

        if measuredNoteEntryPanelHeight > 0 {
            return measuredNoteEntryPanelHeight + 12
        }

        if isPhoneLandscapeLayout {
            if selectedToolCategory == .chord || selectedToolCategory == .lyrics {
                return 170
            }
            return selectedToolCategory == .notes || selectedToolCategory == .select ? 230 : 150
        }

        if isCompactPhoneLayout {
            if selectedToolCategory == .chord || selectedToolCategory == .lyrics {
                return 190
            }
            return selectedToolCategory == .notes || selectedToolCategory == .select ? 340 : 150
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
        zoomScale = ScoreReaderPhoneZoomPolicy.preferredEditScale(for: size)
    }

    private func closeReader() {
        guard !isClosingScore else {
            return
        }

        saveRememberedReaderState()
        isClosingScore = true
        Task { @MainActor in
            await readerState.resetToFullScoreBeforeClosing()
            let canClose = await readerState.saveBeforeClosing()
            if canClose {
                dismiss()
            } else {
                isClosingScore = false
            }
        }
    }

    private func rememberedPartIndexForInitialLoad() -> Int? {
        guard
            readerState.interactionMode == .view,
            initialRememberedState.selectedPartID != "full-score",
            let part = displayedScoreParts.first(where: { $0.id == initialRememberedState.selectedPartID })
        else {
            if initialRememberedState.selectedPartID != "full-score" {
                selectedPartID = "full-score"
            }
            return nil
        }

        selectedPartID = part.id
        return part.index
    }

    private func reportReaderReadyWhenAvailable() async {
        while !Task.isCancelled,
              readerState.page(at: readerState.selectedPageIndex) == nil
        {
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return
            }
        }

        guard !Task.isCancelled else { return }
        readerReadyAction?()
    }

    private func saveRememberedReaderState() {
        guard !isClosingScore, !isTransitioningScore, readerState.interactionMode != .leavingEdit else {
            return
        }

        ScoreReaderRememberedStateStore().save(
            ScoreReaderRememberedState(
                pageIndex: readerState.selectedPageIndex,
                selectedPartID: selectedPartID,
                zoomScale: Double(min(max(zoomScale, ScoreReaderZoomLimits.minimumScale), 3.0)),
                readingStyle: readingStyle,
                playbackFollowEnabled: readerState.playbackFollowEnabled,
                viewTransposeKey: readerState.viewTransposeKey != readerState.viewTransposeSourceKey
                    ? readerState.viewTransposeKey?.coreKey
                    : nil
            ),
            for: session.id
        )
    }

    private func toggleInteractionMode() {
        switch readerState.interactionMode {
        case .view:
            viewModeSaveErrorMessage = nil
            isChromeVisible = true
            selectedToolCategory = .select
            pencilAutoNoteEntryAllowed = ScoreReaderToolModePolicy.allowsAutomaticPencilNoteEntry(after: .enterEditMode)
            readerState.enterEditMode()
        case .edit:
            finishEditingAndEnterViewMode()
        case .leavingEdit:
            break
        }
    }

    private func presentViewModePlaybackSelection(
        from startPoint: CGPoint,
        through endPoint: CGPoint,
        pageIndex: Int
    ) {
        guard
            readerState.interactionMode == .view,
            readerState.supportsPlayback,
            !isClosingScore,
            !isTransitioningScore,
            !isPreparingExport
        else {
            return
        }

        if startPoint == endPoint {
            readerState.presentPlayFromHere(atNormalizedPoint: startPoint, pageIndex: pageIndex)
        } else {
            readerState.updatePlaybackLoopSelection(
                fromNormalizedPoint: startPoint,
                toNormalizedPoint: endPoint,
                pageIndex: pageIndex
            )
        }
    }

    private func finishEditingAndEnterViewMode() {
        guard !readerState.isEditingActionInFlight else {
            return
        }

        dismissEditingPresentations()
        Task { @MainActor in
            let succeeded = await readerState.finishEditingAndEnterViewMode()
            if succeeded {
                viewModeSaveErrorMessage = nil
                showSavedViewModeConfirmation()
            } else {
                viewModeSaveErrorMessage = readerState.editingErrorMessage
                    ?? "Changes could not be saved. The score remains protected in View mode."
                readerState.editingErrorMessage = nil
            }
        }
    }

    private func dismissEditingPresentations() {
        textEditorDraft = nil
        isTempoEditorPresented = false
        isTimeSignaturePresented = false
        isKeySignaturePresented = false
        isScoreSetupPresented = false
        isPageSettingsPresented = false
        isInstrumentLayoutPresented = false
        instrumentReplacementContext = nil
        transposeSheetContext = nil
        isAddMeasuresPresented = false
        isAutoBreaksPresented = false
        isAddInstrumentPresented = false
        isClefPickerPresented = false
        readerState.pickupEditorContext = nil
        clearSelectionCommandMenu()
        exitTextEntryFocusIfNeeded()
        selectedToolCategory = .select
    }

    private func presentInstrumentReplacement() {
        instrumentReplacementContext = readerState.instrumentReplacementContext()
    }

    private func retryViewModeSave() {
        Task { @MainActor in
            if await readerState.savePendingChanges() {
                viewModeSaveErrorMessage = nil
                readerState.editingErrorMessage = nil
                showSavedViewModeConfirmation()
            } else {
                viewModeSaveErrorMessage = readerState.editingErrorMessage ?? "Changes could not be saved."
                readerState.editingErrorMessage = nil
            }
        }
    }

    private var visibleSaveFailureMessage: String? {
        viewModeSaveErrorMessage ?? readerState.autosaveFailureMessage
    }

    private func saveWithoutChordSymbols() {
        Task { @MainActor in
            await readerState.approveChordSymbolRemoval()
            retryVisibleSaveFailure()
        }
    }

    private func retryVisibleSaveFailure() {
        if viewModeSaveErrorMessage != nil {
            retryViewModeSave()
        } else {
            readerState.retryAutosave()
        }
    }

    private func showSavedViewModeConfirmation() {
        withAnimation(.easeInOut(duration: 0.18)) {
            savedViewModeConfirmationIsVisible = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.easeInOut(duration: 0.18)) {
                savedViewModeConfirmationIsVisible = false
            }
        }
    }

    private func handleViewModePageTap(_ normalizedPoint: CGPoint, pageIndex: Int) {
        if usesTwoPageSpread {
            if pageIndex == twoPageSpreadStartIndex, normalizedPoint.x <= 0.50 {
                showPreviousPage()
            } else if pageIndex == twoPageSpreadEndIndex, normalizedPoint.x >= 0.50 {
                showNextPage()
            } else {
                toggleViewChrome()
            }
            return
        }

        if normalizedPoint.x <= 0.20 {
            showPreviousPage()
        } else if normalizedPoint.x >= 0.80 {
            showNextPage()
        } else {
            toggleViewChrome()
        }
    }

    private func toggleViewChrome() {
        guard readerState.interactionMode == .view else {
            return
        }
        guard !isPartsPanelPresented, !isMixerPresented,
              !isExportPanelPresented,
              sharedExportItems == nil,
              !isPreparingExport,
              readerState.playbackPreparationMessage == nil,
              readerState.playbackErrorMessage == nil,
              readerState.editingErrorMessage == nil,
              exportErrorMessage == nil,
              viewModeSaveErrorMessage == nil
        else {
            isChromeVisible = true
            return
        }

        withAnimation(.easeInOut(duration: 0.18)) {
            isChromeVisible.toggle()
        }
    }

    private func toggleAnnotationMode() {
        isAnnotationModeActive ? exitAnnotationMode() : enterAnnotationMode()
    }

    private func enterAnnotationMode() {
        guard !isPhoneInterface, readerState.interactionMode == .view, annotationController.isEditable else { return }
        if !isAnnotationModeActive {
            readingStyleBeforeAnnotation = readingStyle
        }
        isPartsPanelPresented = false
        isExportPanelPresented = false
        isMixerPresented = false
        annotationsVisible = true
        isChromeVisible = true
        withAnimation(.easeInOut(duration: 0.18)) {
            isAnnotationModeActive = true
            readingStyle = .pageTurn
        }
        Task { await readerState.prepareAnnotationMeasureRegionsIfNeeded() }
    }

    private func beginAnnotationFromCanvas() {
        guard !isPhoneInterface, readerState.interactionMode == .view else { return }
        if !isAnnotationModeActive {
            readingStyleBeforeAnnotation = readingStyle
        }
        annotationsVisible = true
        isChromeVisible = true
        withAnimation(.easeInOut(duration: 0.18)) {
            isAnnotationModeActive = true
        }
        Task { await readerState.prepareAnnotationMeasureRegionsIfNeeded() }
    }

    private func finishAutomaticAnnotationEntryIfNeeded() {
        guard isAnnotationModeActive, readingStyle != .pageTurn else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            readingStyle = .pageTurn
        }
    }

    private func exitAnnotationMode() {
        guard isAnnotationModeActive else { return }
        annotationController.clearSelection()
        annotationController.flushSave()
        let restoredReadingStyle = readingStyleBeforeAnnotation
        readingStyleBeforeAnnotation = nil
        withAnimation(.easeInOut(duration: 0.18)) {
            isAnnotationModeActive = false
            if let restoredReadingStyle {
                readingStyle = restoredReadingStyle
            }
        }
    }

    private func showPreviousPage() {
        let targetPageIndex = usesTwoPageSpread
            ? twoPageSpreadStartIndex - 2
            : readerState.selectedPageIndex - 1
        guard readerState.interactionMode == .view else {
            return
        }
        guard targetPageIndex >= 0 else {
            if setlistNavigation?.previousScoreTitle != nil {
                transitionToAdjacentScore(.previous)
            }
            return
        }
        zoomScale = 1
        readerState.updatePageTurnSelection(to: targetPageIndex)
    }

    private func showPageFromScrubber(_ pageIndex: Int) {
        guard readerState.interactionMode == .view else {
            return
        }
        let targetPageIndex = usesTwoPageSpread ? pageIndex - (pageIndex % 2) : pageIndex
        zoomScale = 1
        readerState.updatePageTurnSelection(to: targetPageIndex)
    }

    private func showNextPage() {
        let targetPageIndex = usesTwoPageSpread
            ? twoPageSpreadStartIndex + 2
            : readerState.selectedPageIndex + 1
        guard readerState.interactionMode == .view else {
            return
        }
        guard targetPageIndex < readerState.pageCount else {
            if setlistNavigation?.nextScoreTitle != nil {
                transitionToAdjacentScore(.next)
            }
            return
        }
        zoomScale = 1
        readerState.updatePageTurnSelection(to: targetPageIndex)
    }

    private var adjacentScoreLoadingLabel: String {
        guard let setlistNavigation else {
            return "Opening score…"
        }
        let title = isTransitioningTowardPreviousScore
            ? setlistNavigation.previousScoreTitle
            : setlistNavigation.nextScoreTitle
        return title.map { "Opening \($0)…" } ?? "Opening score…"
    }

    @State var isTransitioningTowardPreviousScore = false

    private func transitionToAdjacentScore(_ direction: ScoreReaderSequenceDirection) {
        guard let setlistNavigation,
              readerState.interactionMode == .view,
              !isClosingScore,
              !isTransitioningScore
        else {
            return
        }

        switch direction {
        case .previous:
            guard setlistNavigation.previousScoreTitle != nil else { return }
            isTransitioningTowardPreviousScore = true
        case .next:
            guard setlistNavigation.nextScoreTitle != nil else { return }
            isTransitioningTowardPreviousScore = false
        }

        saveRememberedReaderState()
        readerState.stopPlayback()
        isTransitioningScore = true

        Task { @MainActor in
            await readerState.resetToFullScoreBeforeClosing()
            guard await readerState.saveBeforeClosing() else {
                isTransitioningScore = false
                return
            }

            let didTransition = await setlistNavigation.transition(direction, readingStyle)
            if !didTransition {
                isTransitioningScore = false
            }
        }
    }

    private func exportScore() {
        guard !isPreparingExport else {
            return
        }

        isPreparingExport = true
        exportProgress = nil
        exportErrorMessage = nil
        completedVideoURLs = []
        // Video renders can take minutes; keep the screen on so iOS does not suspend Aria.
        let keepsScreenAwake = exportDraft.format == .video
        if keepsScreenAwake {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        let videoMixerSnapshot = readerState.mixerSettings

        exportTask = Task {
            defer {
                Task { @MainActor in
                    exportProgress = nil
                    if keepsScreenAwake {
                        UIApplication.shared.isIdleTimerDisabled = false
                    }
                }
            }
            do {
                guard await readerState.savePendingChanges(
                    busyMessage: "Finish the current edit before sharing the score.",
                    unavailableMessage: "Aria could not save the latest score before sharing.",
                    waitsForInFlightAction: true
                ) else {
                    throw NSError(
                        domain: "ScoreReaderExport",
                        code: 2,
                        userInfo: [
                            NSLocalizedDescriptionKey: readerState.editingErrorMessage
                                ?? "Aria could not save the latest score before sharing."
                        ]
                    )
                }
                let urls = try await prepareExportURLs(videoMixerSettings: videoMixerSnapshot)
                try Task.checkCancellation()
                await MainActor.run {
                    isPreparingExport = false
                    if keepsScreenAwake {
                        // Videos stay in their sheet to be watched, then shared.
                        completedVideoURLs = urls
                    } else {
                        sharedExportItems = ScoreReaderSharedExportItems(urls: urls)
                        isExportPanelPresented = false
                    }
                }
            } catch {
                let cancelled = error is CancellationError || Task.isCancelled
                await MainActor.run {
                    // Cancelling is not a failure; return to the settings quietly.
                    exportErrorMessage = cancelled ? nil
                        : (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    readerState.editingErrorMessage = nil
                    isPreparingExport = false
                }
            }
        }
    }

    private func prepareExportURLs(videoMixerSettings: ScoreMixerSettings) async throws -> [URL] {
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
        case .video:
            return try await writeVideoExports(mixerSettings: videoMixerSettings)
        }
    }

    private func writeVideoExports(mixerSettings: ScoreMixerSettings) async throws -> [URL] {
        let style = exportDraft.videoStyle
        let vertical = exportDraft.videoVertical
        let backgroundImageData = exportDraft.videoBackgroundImageData
        let composer = readerState.scoreMetadata.composer
        let scoreTitle = readerState.scoreTitle
        let reportProgress: @Sendable (Double) -> Void = { value in
            Task { @MainActor in
                exportProgress = value
            }
        }
        return try await withExportTargets { target in
            guard let liveRenderSession = session.liveRenderSession else {
                throw ScoreReaderExportError.unsupportedFormat("Video")
            }

            let exportURL = try Self.exportURL(baseName: exportFileName(for: target), extension: "mp4")
            var title = scoreTitle
            var isPart = false
            if case .part(let part, _) = target {
                title += " – \(part.name)"
                isPart = true
            }
            let textFonts = await liveRenderSession.videoTextFonts()
            try await ScoreVideoExporter.export(
                liveRenderSession: liveRenderSession,
                pageCount: target.pageCount,
                to: exportURL,
                options: ScoreVideoExportOptions(style: style, title: title, composer: composer,
                                                 titleFont: textFonts.title, composerFont: textFonts.composer,
                                                 mixerSettings: mixerSettings,
                                                 backgroundImageData: backgroundImageData,
                                                 pinsStaffHeader: !isPart && pinsVideoStaffHeader,
                                                 vertical: vertical),
                progress: reportProgress
            )
            return exportURL
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
        let chunkDurationSeconds: TimeInterval = 30
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
            nextStartSeconds += max(audioData.durationSeconds, requestedDuration)
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
            if let liveRenderSession = session.liveRenderSession {
                let pdfData = try await liveRenderSession.pdfData()
                let exportURL = try Self.exportURL(baseName: exportFileName(for: target), extension: "pdf")
                try pdfData.write(to: exportURL, options: .atomic)
                return exportURL
            }

            let pages = try await renderedExportPages(for: target)
            guard !pages.isEmpty else {
                throw ScoreReaderExportError.noPages
            }
            #if os(Android)
            // Scores always open with a live session on Android, which writes the PDF above.
            throw ScoreReaderExportError.unsupportedFormat("PDF")
            #else
            let exportURL = try Self.exportURL(baseName: exportFileName(for: target), extension: "pdf")
            let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pages[0].size))
            try renderer.writePDF(to: exportURL) { context in
                for page in pages {
                    context.beginPage(withBounds: CGRect(origin: .zero, size: page.size), pageInfo: [:])
                    page.draw(in: CGRect(origin: .zero, size: page.size))
                }
            }
            return exportURL
            #endif
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
                if let image = page.rasterizedImage() {
                    pages.append(image)
                }
            }
            return pages
        }

        return readerState.pageIndices.compactMap { readerState.page(at: $0)?.rasterizedImage() }
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
        let temporaryViewKeyForExport: ScoreTransposeTargetKey? = {
            guard readerState.interactionMode == .view,
                  exportDraft.format.exportsDisplayedView,
                  let viewKey = readerState.viewTransposeKey,
                  viewKey != readerState.viewTransposeSourceKey
            else {
                return nil
            }
            return viewKey
        }()
        var results: [T] = []

        do {
            if exportDraft.includesFullScore {
                var fullScorePageCount = try await liveRenderSession.setFullScoreView()
                if let temporaryViewKeyForExport {
                    fullScorePageCount = try await liveRenderSession.setViewTransposeKey(temporaryViewKeyForExport.coreKey)
                }
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
                    if let temporaryViewKeyForExport, !exportDraft.exportPartsInOriginalKey {
                        partPageCount = try await liveRenderSession.setViewTransposeKey(temporaryViewKeyForExport.coreKey)
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
        displayedScoreParts.filter { exportDraft.selectedPartIDs.contains($0.id) }
    }

    private func scoreInstrumentsFromDocumentParts() -> [NewScoreInstrument] {
        displayedScoreParts.map { NewScoreInstrumentCatalog.instrument(from: $0) }
    }

    /// Scrolling videos pin the staff header only when there are several parts.
    private var pinsVideoStaffHeader: Bool {
        displayedScoreParts.count > 1
    }

    private var displayedScoreParts: [ScorePart] {
        readerState.scoreParts.isEmpty ? session.document.parts : readerState.scoreParts
    }

    private func synchronizePartPresentation(with parts: [ScorePart], reselectActivePart: Bool = true) {
        let authoritativeParts = parts.isEmpty ? session.document.parts : parts
        instrumentLayoutParts = authoritativeParts
        currentScoreInstruments = authoritativeParts.map { NewScoreInstrumentCatalog.instrument(from: $0) }

        if reselectActivePart, selectedPartID != "full-score" {
            if let selectedPart = authoritativeParts.first(where: { $0.id == selectedPartID }) {
                readerState.selectScorePart(index: selectedPart.index)
            } else {
                selectedPartID = "full-score"
                readerState.selectScorePart(index: nil)
            }
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
            let part = displayedScoreParts.first(where: { $0.id == selectedPartIDBeforeExport })
        {
            restoredPageCount = try await liveRenderSession.setActivePart(index: part.index)
        } else {
            restoredPageCount = try await liveRenderSession.setFullScoreView()
        }

        if await liveRenderSession.concertPitchEnabled() != concertPitchEnabled {
            restoredPageCount = try await liveRenderSession.setConcertPitchEnabled(concertPitchEnabled)
        }
        if let temporaryViewKey = readerState.viewTransposeKey,
           temporaryViewKey != readerState.viewTransposeSourceKey
        {
            restoredPageCount = try await liveRenderSession.setViewTransposeKey(temporaryViewKey.coreKey)
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

    private var editErrorIsPresented: Binding<Bool> {
        Binding(
            get: { readerState.editingErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    readerState.editingErrorMessage = nil
                }
            }
        )
    }

    private var viewTransposeErrorIsPresented: Binding<Bool> {
        Binding(
            get: { readerState.viewTransposeErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    readerState.viewTransposeErrorMessage = nil
                }
            }
        )
    }

    private func presentTextEditor(_ selection: ScoreSelectedElement) {
        // Like MuseScore, editing an instrument change means choosing its instrument.
        if selection.kind == .instrumentChange {
            presentInstrumentReplacement()
            return
        }

        guard selection.kind == .text || selection.kind == .chordText else {
            return
        }

        guard selection.allowsPlainTextEditing else {
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
        guard selectedToolCategory != .chord else {
            readerState.prepareChordTextEntry()
            enterTextEntryFocusIfNeeded()
            return
        }
        selectedToolCategory = .chord
    }

    private func openLyricsEntry() {
        guard selectedToolCategory != .lyrics else {
            readerState.prepareLyricsEntry()
            enterTextEntryFocusIfNeeded()
            return
        }
        selectedToolCategory = .lyrics
    }

    private func activatePencilNoteEntryMode() {
        guard readerState.isEditingMode, pencilAutoNoteEntryAllowed else {
            return
        }
        selectedToolCategory = .notes
        readerState.noteInputWasActivatedByPencil = true
        if !readerState.editingState.noteInputEnabled {
            readerState.setNoteInputEnabled(true)
        }
    }

    private func selectModeFromToolbar() {
        pencilAutoNoteEntryAllowed = ScoreReaderToolModePolicy.allowsAutomaticPencilNoteEntry(after: .chooseSelect)
        readerState.noteInputWasActivatedByPencil = false
        readerState.setNoteInputEnabled(false)
        exitTextEntryFocusIfNeeded()
    }

    private func noteInputModeFromToolbar() {
        pencilAutoNoteEntryAllowed = ScoreReaderToolModePolicy.allowsAutomaticPencilNoteEntry(after: .chooseNoteInput)
        readerState.noteInputWasActivatedByPencil = false
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

    private func selectionCommandOverlay(for anchor: ScoreReaderSelectionCommandAnchor) -> some View {
        ScoreReaderSelectionCommandOverlay(
            anchor: anchor,
            copyAction: readerState.copySelectedMeasureRange,
            cutAction: readerState.cutSelectedMeasureRange,
            pasteAction: readerState.pasteMeasureRange,
            deleteSelectionAction: readerState.deleteSelection,
            clearSelectedMeasureAction: readerState.clearSelectedMeasure,
            removeSelectedMeasureAction: readerState.removeSelectedMeasure,
            addMeasureAction: readerState.addMeasure,
            addMultipleMeasuresAction: { isAddMeasuresPresented = true },
            transposeAction: readerState.transposeSelectedMeasureRange,
            useTransposeSheet: isPhoneInterface,
            openTransposeSheetAction: openTransposeSheet,
            changeEnharmonicAction: readerState.changeSelectedEnharmonicSpelling,
            flipStemAction: readerState.flipSelectedStemDirection,
            changeInstrumentAction: presentInstrumentReplacement,
            keySignatureAction: { isKeySignaturePresented = true },
            timeSignatureAction: { isTimeSignaturePresented = true },
            tempoAction: { isTempoEditorPresented = true },
            pickupMeasureAction: { readerState.presentPickupEditor(createNewMeasure: false) },
            accentAction: readerState.addExpression,
            selectSimilarAction: { sameStaff in readerState.selectSimilar(sameStaff: sameStaff) },
            barLineAction: readerState.addRepeatJump,
            extendSelectionAction: { readerState.isExtendingSelection = true },
            dismissAction: dismissSelectionCommandMenu
        )
        .zIndex(100)
    }

    private func dismissSelectionCommandMenu(identity: String) {
        #if os(Android)
        selectionCommandPresentation.dismiss(identity: identity)
        #else
        dismissedSelectionCommandIdentity = identity
        selectionCommandAnchor = nil
        #endif
    }

    private func clearSelectionCommandMenu() {
        #if os(Android)
        selectionCommandPresentation.reset()
        #else
        dismissedSelectionCommandIdentity = nil
        selectionCommandAnchor = nil
        #endif
    }

    private func openTransposeSheet(currentKey: Int) {
        clearSelectionCommandMenu()
        transposeSheetContext = ScoreReaderTransposeSheetContext(currentKey: currentKey, scope: .selection)
    }

    private func openTransposeScoreSheet() {
        clearSelectionCommandMenu()
        Task { @MainActor in
            let currentKey = await readerState.scoreStartKey()
            guard readerState.isEditingMode else {
                return
            }
            transposeSheetContext = ScoreReaderTransposeSheetContext(currentKey: currentKey, scope: .score)
        }
    }

    private func requestLayoutBreak(_ breakKind: String) {
        readerState.addLayoutBreak(breakKind)
    }

    private func handleToolCategoryChange(from oldValue: ScoreReaderToolCategory, to newValue: ScoreReaderToolCategory) {
        let wasTextEntry = oldValue == .chord || oldValue == .lyrics
        let isTextEntry = newValue == .chord || newValue == .lyrics
        if oldValue == .lyrics && newValue != .lyrics {
            readerState.finishLyricsEntry()
        }

        if newValue == .chord {
            readerState.prepareChordTextEntry()
            enterTextEntryFocusIfNeeded()
        } else if newValue == .lyrics {
            readerState.prepareLyricsEntry()
            enterTextEntryFocusIfNeeded()
        } else if isTextEntry {
            enterTextEntryFocusIfNeeded()
        } else if wasTextEntry {
            exitTextEntryFocusIfNeeded()
        }
    }

    private func applyInitialToolCategoryIfNeeded() {
        guard !didApplyInitialToolCategory else {
            return
        }

        didApplyInitialToolCategory = true
        if readerState.isEditingMode, selectedToolCategory == .notes {
            noteInputModeFromToolbar()
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
        zoomScale = max(ScoreReaderZoomLimits.minimumScale, zoomScale - 0.15)
    }
}

struct ScoreReaderCorruptionMenu: View {
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

struct ScoreReaderSavingHUD: View {
    var label = "Saving…"

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(label)
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

// Skip Fuse constructs Boolean sheet content eagerly, even while it is closed.
// Keep model reads inside a deferred, concrete child on Android. iOS keeps its
// normal sheet content and presentation behavior.
private extension View {
    @ViewBuilder
    func scoreReaderSheet<Content: View>(isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(Android)
        sheet(isPresented: isPresented, onDismiss: onDismiss) {
            AndroidReaderObservationScope(content: content)
        }
        #else
        sheet(isPresented: isPresented, onDismiss: onDismiss, content: content)
        #endif
    }

    @ViewBuilder
    func scoreReaderSheet<Item: Identifiable, Content: View>(item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        #if os(Android)
        sheet(item: item, onDismiss: onDismiss) { item in
            AndroidReaderObservationScope { content(item) }
        }
        #else
        sheet(item: item, onDismiss: onDismiss, content: content)
        #endif
    }
}
