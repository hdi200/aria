//
//  ScoreReaderPageCanvas.swift
//  MuseReaderiOS
//

import SwiftUI
import UIKit
import AVFoundation

enum ScoreReaderPhoneZoomPolicy {
    static func preferredEditScale(for viewportSize: CGSize) -> CGFloat {
        viewportSize.width > viewportSize.height ? 1.2 : 2.2
    }
}

struct ScorePageRenderSurfaceIdentity: Hashable {
    let pageIndex: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let viewportPixelWidth: Int
    let viewportPixelHeight: Int

    init(
        pageIndex: Int,
        pageSize: CGSize,
        viewportSize: CGSize? = nil,
        displayScale: CGFloat = UIScreen.main.scale
    ) {
        let safeScale = max(displayScale, 1)
        let viewportSize = viewportSize ?? pageSize
        self.pageIndex = pageIndex
        self.pixelWidth = Int((max(pageSize.width, 0) * safeScale).rounded())
        self.pixelHeight = Int((max(pageSize.height, 0) * safeScale).rounded())
        self.viewportPixelWidth = Int((max(viewportSize.width, 0) * safeScale).rounded())
        self.viewportPixelHeight = Int((max(viewportSize.height, 0) * safeScale).rounded())
    }
}

struct ScoreReaderBackground: View {
    let usesImmersiveWhite: Bool

    var body: some View {
        Group {
            if usesImmersiveWhite {
                Color.white
            } else {
                Color(red: 0.965, green: 0.965, blue: 0.955)
            }
        }
            .ignoresSafeArea()
    }
}

struct ScoreReaderPageLayoutPolicy: Equatable {
    let reservedPaletteGutter: CGFloat
    let horizontalAlignment: ScoreReaderPageHorizontalAlignment
    let usesFullCanvasZoom: Bool
    let topPagePadding: CGFloat
    let viewportEdgePadding: CGFloat
    let restingTopInset: CGFloat

    init(
        isEditing: Bool,
        fitsPageToViewport: Bool,
        isPortrait: Bool,
        isCompactPhoneLayout: Bool,
        floatingPaletteDockedLeft: Bool
    ) {
        usesFullCanvasZoom = true
        viewportEdgePadding = isEditing && !isCompactPhoneLayout ? 24 : 0

        topPagePadding = 0
        if !isEditing || fitsPageToViewport {
            restingTopInset = 0
        } else if isPortrait {
            restingTopInset = (isCompactPhoneLayout ? 82 : 104) + (isCompactPhoneLayout ? 18 : 90)
        } else {
            restingTopInset = (isCompactPhoneLayout ? 82 : 104) + 6
        }

        guard isEditing, !fitsPageToViewport, isPortrait, !isCompactPhoneLayout else {
            reservedPaletteGutter = 0
            horizontalAlignment = .center
            return
        }

        reservedPaletteGutter = 92
        horizontalAlignment = floatingPaletteDockedLeft ? .trailing : .leading
    }
}

struct ScoreAnnotationPageConfiguration {
    let strokes: [ScoreRenderedAnnotationStroke]
    let selectedStrokeIDs: Set<UUID>
    let isActive: Bool
    let isVisible: Bool
    let allowsInteraction: Bool
    let tool: ScoreAnnotationTool
    let color: ScoreAnnotationColor
    let width: Double
    let interactionStartAction: () -> Void
    let strokeCommitAction: ([CGPoint]) -> Void
    let eraseAction: ([CGPoint]) -> Void
    let lassoAction: (CGRect) -> Void
    let moveSelectionAction: (CGPoint) -> Void
}

struct ScoreReaderPageCanvas: View {
    static func activeNotationAnchorID(for pageIndex: Int) -> String {
        "active-notation-anchor-\(pageIndex)"
    }

    static func playbackAnchorID(for pageIndex: Int) -> String {
        "playback-anchor-\(pageIndex)"
    }

    let pageIndex: Int
    let page: ScorePage?
    let isLoading: Bool
    let errorText: String?
    let playbackHighlight: ScorePlaybackMeasureHighlight?
    let playFromHereTarget: ScorePlayFromHereTarget?
    let playbackLoopRange: ScorePlaybackLoopRange?
    let playbackLoopIsActive: Bool
    let selectedElement: ScoreSelectedElement?
    let noteEntryPreview: ScoreNoteEntryPreview?
    @Binding var zoomScale: CGFloat
    let availableWidth: CGFloat
    let viewportSize: CGSize
    var isCompactPhoneLayout = false
    var floatingPaletteDockedLeft = false
    var activeNotationTopInset: CGFloat = 0
    var activeNotationBottomInset: CGFloat = 0
    let allowsPencilInsertionFineTune: Bool
    let noteEntryPreviewPitchClass: Int?
    let noteEntryPreviewIsRest: Bool
    let noteEntryPreviewDuration: ScoreNoteDuration
    let showsLayoutMarkers: Bool
    let activeNotationAutoScrollRevision: Int
    var fitsPageToViewport = false
    var allowsEditingInteractions = true
    var allowsPlaybackFollow = true
    let editSelectedTextAction: (ScoreSelectedElement) -> Void
    let editTempoAction: () -> Void
    let editTimeSignatureAction: () -> Void
    let editKeySignatureAction: () -> Void
    let deleteSelectionAction: () -> Void
    let clearSelectedMeasureAction: () -> Void
    let removeSelectedMeasureAction: () -> Void
    let addMeasureAction: () -> Void
    let addMultipleMeasuresAction: () -> Void
    let copySelectedMeasureRangeAction: () -> Void
    let cutSelectedMeasureRangeAction: () -> Void
    let pasteMeasureRangeAction: () -> Void
    let transposeSelectedMeasureRangeAction: (ScoreTransposeRequest) -> Void
    let changeSelectedEnharmonicSpellingAction: () -> Void
    let addExpressionAction: (String) -> Void
    let tapAction: (CGPoint, ScorePageTapInputKind) -> Void
    let selectedNoteDragAction: (CGPoint) -> Void
    let expressionEndpointDragAction: (Bool, CGPoint) -> Void
    let selectedMovableElementDragAction: (CGPoint) -> Void
    let measureRangePreviewAction: (CGPoint, CGPoint) -> Void
    let measureRangePreviewEndAction: () -> Void
    let measureRangeDragAction: (CGPoint, CGPoint) -> Void
    let pencilInsertionFineTuneAction: (CGPoint, CGPoint) -> Void
    let pencilHoverPreviewAction: (CGPoint?) -> Void
    let pencilInteractionStartAction: () -> Void
    let pencilDoubleTapAction: () -> Void
    var swipePreviousPageAction: () -> Void = {}
    var swipeNextPageAction: () -> Void = {}
    var viewModeLongPressAction: (CGPoint, CGPoint) -> Void = { _, _ in }
    var playFromHereAction: () -> Void = {}
    var loopFromHereAction: () -> Void = {}
    var togglePlaybackLoopAction: () -> Void = {}
    var manualScrollAction: () -> Void = {}
    var annotationConfiguration: ScoreAnnotationPageConfiguration?

    var body: some View {
        #if os(Android) && ARIA_PHONE_AUDIT
        let _ = AndroidPhoneAuditGeometry.evaluate("canvas")
        #endif
        let fittedPageSize = fittedPageSize
        let pageWidth = fittedPageSize.width
        let pageHeight = fittedPageSize.height
        let zoomViewportWidth = pageLayoutPolicy.usesFullCanvasZoom
            ? max(availableWidth, pageWidth)
            : pageWidth
        let zoomViewportHeight = pageLayoutPolicy.usesFullCanvasZoom
            ? max(viewportSize.height, pageHeight)
            : pageHeight
        #if os(Android) && ARIA_PHONE_AUDIT
        let _ = AndroidPhoneAuditGeometry.surfaceTrace(page: pageIndex, size: fittedPageSize,
            viewport: CGSize(width: zoomViewportWidth, height: zoomViewportHeight))
        #endif
        let topPadding = topPagePadding
        let bottomPadding: CGFloat = fitsPageToViewport ? 0 : 6
        let usesActiveNotationFocus = selectedElement?.pageIndex == pageIndex
            && selectedElement?.isHighlightOnly == false
            && (activeNotationTopInset > 0 || activeNotationBottomInset > 0)
        let zoomActiveNotationTopInset = usesActiveNotationFocus ? activeNotationTopInset : 0
        let zoomActiveNotationBottomInset = usesActiveNotationFocus ? activeNotationBottomInset : 0

        ZStack(alignment: .topLeading) {
            ScoreReaderPageSurface(
                pageIndex: pageIndex,
                page: page,
                isLoading: isLoading,
                errorText: errorText,
                playbackHighlight: playbackHighlight,
                playFromHereTarget: playFromHereTarget,
                playbackLoopRange: playbackLoopRange,
                playbackLoopIsActive: playbackLoopIsActive,
                selectedElement: selectedElement,
                noteEntryPreview: noteEntryPreview,
                zoomScale: $zoomScale,
                displayedPageSize: fittedPageSize,
                pageHorizontalAlignment: zoomPageHorizontalAlignment,
                centersPageVertically: fitsPageToViewport,
                prefersRasterAtRest: fitsPageToViewport && !allowsEditingInteractions,
                viewportEdgePadding: pageLayoutPolicy.viewportEdgePadding,
                restingTopInset: pageLayoutPolicy.restingTopInset,
                allowsPencilInsertionFineTune: allowsPencilInsertionFineTune,
                noteEntryPreviewPitchClass: noteEntryPreviewPitchClass,
                noteEntryPreviewIsRest: noteEntryPreviewIsRest,
                noteEntryPreviewDuration: noteEntryPreviewDuration,
                showsLayoutMarkers: showsLayoutMarkers,
                activeNotationTopInset: zoomActiveNotationTopInset,
                activeNotationBottomInset: zoomActiveNotationBottomInset,
                activeNotationViewportHeight: viewportSize.height,
                activeNotationAutoScrollRevision: activeNotationAutoScrollRevision,
                allowsEditingInteractions: allowsEditingInteractions,
                allowsPlaybackFollow: allowsPlaybackFollow,
                editSelectedTextAction: editSelectedTextAction,
                editTempoAction: editTempoAction,
                editTimeSignatureAction: editTimeSignatureAction,
                editKeySignatureAction: editKeySignatureAction,
                deleteSelectionAction: deleteSelectionAction,
                clearSelectedMeasureAction: clearSelectedMeasureAction,
                removeSelectedMeasureAction: removeSelectedMeasureAction,
                addMeasureAction: addMeasureAction,
                addMultipleMeasuresAction: addMultipleMeasuresAction,
                copySelectedMeasureRangeAction: copySelectedMeasureRangeAction,
                cutSelectedMeasureRangeAction: cutSelectedMeasureRangeAction,
                pasteMeasureRangeAction: pasteMeasureRangeAction,
                transposeSelectedMeasureRangeAction: transposeSelectedMeasureRangeAction,
                changeSelectedEnharmonicSpellingAction: changeSelectedEnharmonicSpellingAction,
                addExpressionAction: addExpressionAction,
                tapAction: tapAction,
                selectedNoteDragAction: selectedNoteDragAction,
                expressionEndpointDragAction: expressionEndpointDragAction,
                selectedMovableElementDragAction: selectedMovableElementDragAction,
                measureRangePreviewAction: measureRangePreviewAction,
                measureRangePreviewEndAction: measureRangePreviewEndAction,
                measureRangeDragAction: measureRangeDragAction,
                pencilInsertionFineTuneAction: pencilInsertionFineTuneAction,
                pencilHoverPreviewAction: pencilHoverPreviewAction,
                pencilInteractionStartAction: pencilInteractionStartAction,
                pencilDoubleTapAction: pencilDoubleTapAction,
                swipePreviousPageAction: swipePreviousPageAction,
                swipeNextPageAction: swipeNextPageAction,
                viewModeLongPressAction: viewModeLongPressAction,
                playFromHereAction: playFromHereAction,
                loopFromHereAction: loopFromHereAction,
                togglePlaybackLoopAction: togglePlaybackLoopAction,
                manualScrollAction: manualScrollAction,
                annotationConfiguration: annotationConfiguration
            )
            // CATiledLayer renders PDF tiles asynchronously. A viewport-size
            // identity prevents tiles produced with pre-rotation bounds from
            // being composited into the resized page surface.
            .id(
                ScorePageRenderSurfaceIdentity(
                    pageIndex: pageIndex,
                    pageSize: fittedPageSize,
                    viewportSize: CGSize(width: zoomViewportWidth, height: zoomViewportHeight)
                )
            )
            .frame(width: zoomViewportWidth, height: zoomViewportHeight)
            .position(x: zoomViewportWidth * 0.5, y: topPadding + zoomViewportHeight * 0.5)

            #if os(Android)
            // Keep the page's parent child-ID list stable. Skip keys an all-tagged
            // ZStack's AnimatedContent by that list; inserting/removing a scroll
            // anchor would otherwise replace the unchanged page and its bitmaps.
            ZStack(alignment: .topLeading) {
                if let anchorY = activeNotationAnchorY(pageHeight: pageHeight, topPadding: topPadding) {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .position(x: zoomViewportWidth * 0.5, y: anchorY)
                        .id(Self.activeNotationAnchorID(for: pageIndex))
                        .accessibilityHidden(true)
                }
                if let anchorY = playbackAnchorY(pageHeight: pageHeight, topPadding: topPadding) {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .position(x: zoomViewportWidth * 0.5, y: anchorY)
                        .id(Self.playbackAnchorID(for: pageIndex))
                        .accessibilityHidden(true)
                }
            }
            .frame(width: zoomViewportWidth, height: zoomViewportHeight)
            .allowsHitTesting(false)
            .id("page-scroll-anchors-\(pageIndex)")
            #else
            if let anchorY = activeNotationAnchorY(pageHeight: pageHeight, topPadding: topPadding) {
                Color.clear
                    .frame(width: 1, height: 1)
                    .position(x: zoomViewportWidth * 0.5, y: anchorY)
                    .id(Self.activeNotationAnchorID(for: pageIndex))
                    .accessibilityHidden(true)
            }

            if let anchorY = playbackAnchorY(pageHeight: pageHeight, topPadding: topPadding) {
                Color.clear
                    .frame(width: 1, height: 1)
                    .position(x: zoomViewportWidth * 0.5, y: anchorY)
                    .id(Self.playbackAnchorID(for: pageIndex))
                    .accessibilityHidden(true)
            }
            #endif
        }
        .frame(width: zoomViewportWidth, height: topPadding + zoomViewportHeight + bottomPadding)
        .frame(maxWidth: .infinity, alignment: outerCanvasAlignment)
        #if os(Android) && ARIA_PHONE_AUDIT
        let _ = AndroidInteractionTrace.point("evaluate_canvas_end")
        #endif
    }

    private var isPortrait: Bool {
        viewportSize.height > viewportSize.width
    }

    private var reservedPaletteGutter: CGFloat {
        pageLayoutPolicy.reservedPaletteGutter
    }

    private var zoomPageHorizontalAlignment: ScoreReaderPageHorizontalAlignment {
        pageLayoutPolicy.horizontalAlignment
    }

    private var pageLayoutPolicy: ScoreReaderPageLayoutPolicy {
        ScoreReaderPageLayoutPolicy(
            isEditing: allowsEditingInteractions,
            fitsPageToViewport: fitsPageToViewport,
            isPortrait: isPortrait,
            isCompactPhoneLayout: isCompactPhoneLayout,
            floatingPaletteDockedLeft: floatingPaletteDockedLeft
        )
    }

    private var topPagePadding: CGFloat {
        pageLayoutPolicy.topPagePadding
    }

    private var outerCanvasAlignment: Alignment {
        switch pageLayoutPolicy.horizontalAlignment {
        case .leading:
            return .topLeading
        case .center:
            return .top
        case .trailing:
            return .topTrailing
        }
    }

    private var fittedPageSize: CGSize {
        guard fitsPageToViewport else {
            let width = min(
                max(
                    availableWidth - reservedPaletteGutter - pageLayoutPolicy.viewportEdgePadding * 2,
                    320
                ),
                980
            )
            return CGSize(width: width, height: preferredHeight(for: width))
        }

        let sourceSize = page?.displaySize ?? CGSize(width: 612, height: 792)
        let safeWidth = max(availableWidth, 1)
        let safeHeight = max(viewportSize.height, 1)
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return CGSize(width: safeWidth, height: safeHeight)
        }

        let scale = min(safeWidth / sourceSize.width, safeHeight / sourceSize.height)
        return CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
    }

    private func activeNotationAnchorY(pageHeight: CGFloat, topPadding: CGFloat) -> CGFloat? {
        guard
            let selectedElement,
            selectedElement.pageIndex == pageIndex,
            !selectedElement.isHighlightOnly,
            viewportSize.height > 0
        else {
            return nil
        }

        let zoomedOutScale = min(max(zoomScale, 0.01), 1)
        let visiblePageHeight = pageHeight * zoomedOutScale
        let selectionRect = selectedElement.normalizedRect
        let targetCenterY = topPadding + CGFloat(selectionRect.center.y) * visiblePageHeight
        let targetBottomY = topPadding + CGFloat(selectionRect.y + selectionRect.height) * visiblePageHeight
        // Aim for the middle of the viewport area left visible between the top
        // chrome and the bottom entry panel, but treat clearing the bottom
        // controls as a hard constraint on tight landscape/zoomed-out layouts.
        let usableHeight = max(viewportSize.height - activeNotationTopInset - activeNotationBottomInset, 80)
        let desiredViewportY = activeNotationTopInset + usableHeight * 0.5
        let centeredOffset = targetCenterY - desiredViewportY
        let safeBottomY = max(activeNotationTopInset + 80, viewportSize.height - activeNotationBottomInset - 36)
        let bottomProtectedOffset = targetBottomY - safeBottomY
        let targetOffset = max(centeredOffset, bottomProtectedOffset)
        return min(max(targetOffset, 0), topPadding + pageHeight)
    }

    private func playbackAnchorY(pageHeight: CGFloat, topPadding: CGFloat) -> CGFloat? {
        guard
            let playbackHighlight,
            playbackHighlight.pageIndex == pageIndex,
            viewportSize.height > 0
        else {
            return nil
        }

        let targetCenterY = topPadding + CGFloat(playbackHighlight.normalizedRect.center.y) * pageHeight
        let desiredViewportY = viewportSize.height * 0.38
        return min(max(targetCenterY - desiredViewportY, 0), topPadding + pageHeight)
    }

    private func preferredHeight(for width: CGFloat) -> CGFloat {
        guard let imageSize = page?.displaySize, imageSize.width > 0 else {
            return max(width * 1.35, 560)
        }

        return max(width * (imageSize.height / imageSize.width), 560)
    }
}

struct ScoreReaderPageSurface: View {
    @State var zoomViewport = ScoreReaderZoomViewport()

    let pageIndex: Int
    let page: ScorePage?
    let isLoading: Bool
    let errorText: String?
    let playbackHighlight: ScorePlaybackMeasureHighlight?
    let playFromHereTarget: ScorePlayFromHereTarget?
    let playbackLoopRange: ScorePlaybackLoopRange?
    let playbackLoopIsActive: Bool
    let selectedElement: ScoreSelectedElement?
    let noteEntryPreview: ScoreNoteEntryPreview?
    @Binding var zoomScale: CGFloat
    let displayedPageSize: CGSize
    let pageHorizontalAlignment: ScoreReaderPageHorizontalAlignment
    let centersPageVertically: Bool
    let prefersRasterAtRest: Bool
    let viewportEdgePadding: CGFloat
    let restingTopInset: CGFloat
    let allowsPencilInsertionFineTune: Bool
    let noteEntryPreviewPitchClass: Int?
    let noteEntryPreviewIsRest: Bool
    let noteEntryPreviewDuration: ScoreNoteDuration
    let showsLayoutMarkers: Bool
    let activeNotationTopInset: CGFloat
    let activeNotationBottomInset: CGFloat
    let activeNotationViewportHeight: CGFloat
    let activeNotationAutoScrollRevision: Int
    let allowsEditingInteractions: Bool
    let allowsPlaybackFollow: Bool
    let editSelectedTextAction: (ScoreSelectedElement) -> Void
    let editTempoAction: () -> Void
    let editTimeSignatureAction: () -> Void
    let editKeySignatureAction: () -> Void
    let deleteSelectionAction: () -> Void
    let clearSelectedMeasureAction: () -> Void
    let removeSelectedMeasureAction: () -> Void
    let addMeasureAction: () -> Void
    let addMultipleMeasuresAction: () -> Void
    let copySelectedMeasureRangeAction: () -> Void
    let cutSelectedMeasureRangeAction: () -> Void
    let pasteMeasureRangeAction: () -> Void
    let transposeSelectedMeasureRangeAction: (ScoreTransposeRequest) -> Void
    let changeSelectedEnharmonicSpellingAction: () -> Void
    let addExpressionAction: (String) -> Void
    let tapAction: (CGPoint, ScorePageTapInputKind) -> Void
    let selectedNoteDragAction: (CGPoint) -> Void
    let expressionEndpointDragAction: (Bool, CGPoint) -> Void
    let selectedMovableElementDragAction: (CGPoint) -> Void
    let measureRangePreviewAction: (CGPoint, CGPoint) -> Void
    let measureRangePreviewEndAction: () -> Void
    let measureRangeDragAction: (CGPoint, CGPoint) -> Void
    let pencilInsertionFineTuneAction: (CGPoint, CGPoint) -> Void
    let pencilHoverPreviewAction: (CGPoint?) -> Void
    let pencilInteractionStartAction: () -> Void
    let pencilDoubleTapAction: () -> Void
    let swipePreviousPageAction: () -> Void
    let swipeNextPageAction: () -> Void
    let viewModeLongPressAction: (CGPoint, CGPoint) -> Void
    let playFromHereAction: () -> Void
    let loopFromHereAction: () -> Void
    let togglePlaybackLoopAction: () -> Void
    let manualScrollAction: () -> Void
    let annotationConfiguration: ScoreAnnotationPageConfiguration?

    /// Selection actions belong to the selection's own page, not to pages that only show its highlight.
    private var actionableSelectedElement: ScoreSelectedElement? {
        selectedElement?.isHighlightOnly == true ? nil : selectedElement
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let page, page.hasRenderableContent {
                    ZoomableImageView(
                        imageData: page.imageData,
                        pdfData: page.pdfData,
                        prefersRasterAtRest: prefersRasterAtRest,
                        contentSize: page.displaySize ?? CGSize(width: 612, height: 792),
                        displayedPageSize: displayedPageSize,
                        playbackHighlight: playbackHighlight,
                        selection: selectedElement,
                        noteEntryPreview: noteEntryPreview,
                        layoutMarkers: page.layoutMarkers,
                        zoomScale: $zoomScale,
                        zoomViewport: $zoomViewport,
                        activeNotationAutoScrollRevision: activeNotationAutoScrollRevision,
                        activeNotationTopInset: activeNotationTopInset,
                        activeNotationBottomInset: activeNotationBottomInset,
                        activeNotationViewportHeight: activeNotationViewportHeight,
                        pageHorizontalAlignment: pageHorizontalAlignment,
                        centersPageVertically: centersPageVertically,
                        restingHorizontalEdgePadding: viewportEdgePadding,
                        restingTopInset: restingTopInset,
                        showsPageBoundary: allowsEditingInteractions,
                        allowsEditingInteractions: allowsEditingInteractions,
                        allowsPlaybackFollow: allowsPlaybackFollow,
                        allowsPencilInsertionFineTune: allowsPencilInsertionFineTune,
                        noteEntryPreviewPitchClass: noteEntryPreviewPitchClass,
                        noteEntryPreviewIsRest: noteEntryPreviewIsRest,
                        noteEntryPreviewDuration: noteEntryPreviewDuration,
                        showsLayoutMarkers: showsLayoutMarkers,
                        onTap: tapAction,
                        onSelectedNoteDrag: selectedNoteDragAction,
                        onExpressionEndpointDrag: expressionEndpointDragAction,
                        onSelectedMovableElementDrag: selectedMovableElementDragAction,
                        onMeasureRangePreview: measureRangePreviewAction,
                        onMeasureRangePreviewEnd: measureRangePreviewEndAction,
                        onMeasureRangeDrag: measureRangeDragAction,
                        onPencilInsertionFineTune: pencilInsertionFineTuneAction,
                        onPencilHoverPreview: pencilHoverPreviewAction,
                        onPencilInteractionStart: pencilInteractionStartAction,
                        onPencilDoubleTap: pencilDoubleTapAction,
                        onSwipePreviousPage: swipePreviousPageAction,
                        onSwipeNextPage: swipeNextPageAction,
                        onReadingLongPress: viewModeLongPressAction,
                        onManualScroll: manualScrollAction,
                        annotationStrokes: annotationConfiguration?.strokes ?? [],
                        selectedAnnotationStrokeIDs: annotationConfiguration?.selectedStrokeIDs ?? [],
                        annotationModeActive: annotationConfiguration?.isActive ?? false,
                        annotationsVisible: annotationConfiguration?.isVisible ?? true,
                        allowsAnnotationInteraction: annotationConfiguration?.allowsInteraction ?? false,
                        annotationTool: annotationConfiguration?.tool ?? .pen,
                        annotationColor: annotationConfiguration?.color ?? .black,
                        annotationWidth: annotationConfiguration?.width ?? 4,
                        onAnnotationInteractionStart: annotationConfiguration?.interactionStartAction,
                        onAnnotationStrokeCommit: annotationConfiguration?.strokeCommitAction,
                        onAnnotationErase: annotationConfiguration?.eraseAction,
                        onAnnotationLasso: annotationConfiguration?.lassoAction,
                        onAnnotationMoveSelection: annotationConfiguration?.moveSelectionAction
                    )
                } else {
                    ScoreReaderPagePlaceholder(
                        pageIndex: pageIndex,
                        isLoading: isLoading,
                        errorText: errorText
                    )
                    .frame(width: displayedPageSize.width, height: displayedPageSize.height)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .shadow(
                        color: allowsEditingInteractions ? Color.black.opacity(0.15) : Color.clear,
                        radius: allowsEditingInteractions ? 12 : 0,
                        y: allowsEditingInteractions ? 6 : 0
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: placeholderAlignment)
                }
            }

            if isLoading {
                ProgressView()
                    .tint(.black)
                    .padding(12)
                    .background(Color.white.opacity(0.96), in: Circle())
                    .padding(18)
            }

            ScoreReaderPageViewportOverlays(
                zoomViewport: $zoomViewport,
                selectedElement: actionableSelectedElement,
                imageSize: page?.displaySize,
                playFromHereTarget: playFromHereTarget,
                playbackLoopRange: playbackLoopRange,
                playbackLoopIsActive: playbackLoopIsActive,
                editSelectedTextAction: editSelectedTextAction,
                editTempoAction: editTempoAction,
                editTimeSignatureAction: editTimeSignatureAction,
                editKeySignatureAction: editKeySignatureAction,
                deleteSelectionAction: deleteSelectionAction,
                clearSelectedMeasureAction: clearSelectedMeasureAction,
                removeSelectedMeasureAction: removeSelectedMeasureAction,
                addMeasureAction: addMeasureAction,
                addMultipleMeasuresAction: addMultipleMeasuresAction,
                copySelectedMeasureRangeAction: copySelectedMeasureRangeAction,
                cutSelectedMeasureRangeAction: cutSelectedMeasureRangeAction,
                pasteMeasureRangeAction: pasteMeasureRangeAction,
                transposeSelectedMeasureRangeAction: transposeSelectedMeasureRangeAction,
                changeSelectedEnharmonicSpellingAction: changeSelectedEnharmonicSpellingAction,
                addExpressionAction: addExpressionAction,
                playFromHereAction: playFromHereAction,
                loopFromHereAction: loopFromHereAction,
                togglePlaybackLoopAction: togglePlaybackLoopAction
            )
        }
    }

    private var placeholderAlignment: Alignment {
        let horizontal: HorizontalAlignment
        switch pageHorizontalAlignment {
        case .leading:
            horizontal = .leading
        case .center:
            horizontal = .center
        case .trailing:
            horizontal = .trailing
        }
        return Alignment(horizontal: horizontal, vertical: centersPageVertically ? .center : .top)
    }
}

/// This child alone reads the published viewport; the page surface passes its binding.
/// The overlay geometry and actions are unchanged on both platforms.
struct ScoreReaderPageViewportOverlays: View {
    @Binding var zoomViewport: ScoreReaderZoomViewport
    let selectedElement: ScoreSelectedElement?
    let imageSize: CGSize?
    let playFromHereTarget: ScorePlayFromHereTarget?
    let playbackLoopRange: ScorePlaybackLoopRange?
    let playbackLoopIsActive: Bool
    let editSelectedTextAction: (ScoreSelectedElement) -> Void
    let editTempoAction: () -> Void
    let editTimeSignatureAction: () -> Void
    let editKeySignatureAction: () -> Void
    let deleteSelectionAction: () -> Void
    let clearSelectedMeasureAction: () -> Void
    let removeSelectedMeasureAction: () -> Void
    let addMeasureAction: () -> Void
    let addMultipleMeasuresAction: () -> Void
    let copySelectedMeasureRangeAction: () -> Void
    let cutSelectedMeasureRangeAction: () -> Void
    let pasteMeasureRangeAction: () -> Void
    let transposeSelectedMeasureRangeAction: (ScoreTransposeRequest) -> Void
    let changeSelectedEnharmonicSpellingAction: () -> Void
    let addExpressionAction: (String) -> Void
    let playFromHereAction: () -> Void
    let loopFromHereAction: () -> Void
    let togglePlaybackLoopAction: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let selectedElement = selectedElement, selectedElement.kind == .text || selectedElement.kind == .chordText || selectedElement.kind == .instrumentChange {
                ScoreReaderSelectedTextActions(
                    selectedElement: selectedElement,
                    imageSize: imageSize,
                    zoomViewport: $zoomViewport,
                    editAction: { editSelectedTextAction(selectedElement) },
                    deleteAction: deleteSelectionAction
                )
            }

            if let selectedElement = selectedElement, selectedElement.kind == .dynamic || selectedElement.kind == .tie || selectedElement.kind == .layoutBreak || selectedElement.kind == .marker || selectedElement.kind == .other {
                ScoreReaderSelectedDynamicActions(
                    selectedElement: selectedElement,
                    imageSize: imageSize,
                    zoomViewport: $zoomViewport,
                    deleteAction: deleteSelectionAction
                )
            }

            if let selectedElement = selectedElement, selectedElement.kind == .tempo || selectedElement.kind == .timeSignature || selectedElement.kind == .keySignature {
                ScoreReaderSelectedSignatureActions(
                    selectedElement: selectedElement,
                    imageSize: imageSize,
                    zoomViewport: $zoomViewport,
                    editAction: editAction(for: selectedElement.kind)
                )
            }

            if let selectedElement = selectedElement, selectedElement.kind == .measure {
                ScoreReaderSelectedMeasureActions(
                    selectedElement: selectedElement,
                    imageSize: imageSize,
                    zoomViewport: $zoomViewport,
                    clearAction: clearSelectedMeasureAction,
                    removeAction: removeSelectedMeasureAction,
                    addMeasureAction: addMeasureAction,
                    addMultipleMeasuresAction: addMultipleMeasuresAction,
                    copyAction: copySelectedMeasureRangeAction,
                    cutAction: cutSelectedMeasureRangeAction,
                    pasteAction: pasteMeasureRangeAction,
                    transposeAction: transposeSelectedMeasureRangeAction,
                    keySignatureAction: editKeySignatureAction,
                    timeSignatureAction: editTimeSignatureAction,
                    tempoAction: editTempoAction
                )
            }

            if let selectedElement = selectedElement, selectedElement.kind == .note || selectedElement.kind == .rest || selectedElement.kind == .bar {
                ScoreReaderSelectedNoteRestActions(
                    selectedElement: selectedElement,
                    imageSize: imageSize,
                    zoomViewport: $zoomViewport,
                    copyAction: copySelectedMeasureRangeAction,
                    cutAction: cutSelectedMeasureRangeAction,
                    pasteAction: pasteMeasureRangeAction,
                    deleteAction: deleteSelectionAction,
                    transposeAction: transposeSelectedMeasureRangeAction,
                    changeEnharmonicAction: changeSelectedEnharmonicSpellingAction,
                    accentAction: { expressionKind in
                        // Articulations only attach to notes (fermatas also go on rests);
                        // rests still get copy/paste/transpose.
                        if selectedElement.kind == .note || expressionKind == "Fermata" {
                            addExpressionAction(expressionKind)
                        }
                    }
                )
            }

            if let playFromHereTarget {
                ScoreReaderPlayFromHereOverlay(
                    target: playFromHereTarget,
                    imageSize: imageSize,
                    zoomViewport: $zoomViewport,
                    playAction: playFromHereAction,
                    loopAction: loopFromHereAction
                )
            }

            if let playbackLoopRange {
                ScoreReaderPlaybackLoopOverlay(
                    range: playbackLoopRange,
                    isActive: playbackLoopIsActive,
                    imageSize: imageSize,
                    zoomViewport: $zoomViewport,
                    toggleAction: togglePlaybackLoopAction
                )
            }
        }
    }

    private func editAction(for kind: ScoreSelectedElementKind) -> () -> Void {
        switch kind {
        case .tempo:
            return editTempoAction
        case .timeSignature:
            return editTimeSignatureAction
        case .keySignature:
            return editKeySignatureAction
        default:
            return {}
        }
    }
}

struct ScoreReaderSelectedSignatureActions: View {
    let selectedElement: ScoreSelectedElement
    let imageSize: CGSize?
    @Binding var zoomViewport: ScoreReaderZoomViewport
    let editAction: () -> Void

    var body: some View {
        GeometryReader { geometry in
            Button(action: editAction) {
                Label("Edit", systemImage: "pencil")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(red: 0.12, green: 0.36, blue: 0.88), in: Capsule())
                    .shadow(color: Color.black.opacity(0.16), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .position(actionPosition(in: geometry.size))
        }
        .allowsHitTesting(true)
    }

    private func actionPosition(in size: CGSize) -> CGPoint {
        let rect = actionAnchorCGRect(in: size)
        let rawX = rect.maxX + 28
        let rawY = rect.minY - 26
        return CGPoint(
            x: min(max(rawX, 42), max(size.width - 42, 42)),
            y: min(max(rawY, 26), max(size.height - 26, 26))
        )
    }

    private func actionAnchorCGRect(in size: CGSize) -> CGRect {
        coordinateSpace.rect(for: selectedElement.actionRect, in: size)
    }

    private var coordinateSpace: ScoreReaderOverlayCoordinateSpace {
        ScoreReaderOverlayCoordinateSpace(imageSize: imageSize, viewport: zoomViewport)
    }
}

struct ScoreReaderSelectedTextActions: View {
    let selectedElement: ScoreSelectedElement
    let imageSize: CGSize?
    @Binding var zoomViewport: ScoreReaderZoomViewport
    let editAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 6) {
                Button(action: editAction) {
                    Label("Edit", systemImage: "pencil")
                }

                Button(action: deleteAction) {
                    Label("Remove", systemImage: "trash")
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(red: 0.12, green: 0.36, blue: 0.88), in: Capsule())
            .shadow(color: Color.black.opacity(0.16), radius: 8, y: 3)
            .buttonStyle(.borderless)
            .position(actionPosition(in: geometry.size))
        }
        .allowsHitTesting(true)
    }

    private func actionPosition(in size: CGSize) -> CGPoint {
        let rect = actionAnchorCGRect(in: size)
        let rawX = rect.maxX + 28
        let rawY = rect.minY - 26
        return CGPoint(
            x: min(max(rawX, 42), max(size.width - 42, 42)),
            y: min(max(rawY, 26), max(size.height - 26, 26))
        )
    }

    private func actionAnchorCGRect(in size: CGSize) -> CGRect {
        let rect = selectedElement.highlightRects.first ?? selectedElement.actionRect
        return coordinateSpace.rect(for: rect, in: size)
    }

    private var coordinateSpace: ScoreReaderOverlayCoordinateSpace {
        ScoreReaderOverlayCoordinateSpace(imageSize: imageSize, viewport: zoomViewport)
    }
}

struct ScoreReaderSelectedDynamicActions: View {
    let selectedElement: ScoreSelectedElement
    let imageSize: CGSize?
    @Binding var zoomViewport: ScoreReaderZoomViewport
    let deleteAction: () -> Void

    var body: some View {
        GeometryReader { geometry in
            Button(action: deleteAction) {
                actionLabel
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(red: 0.12, green: 0.36, blue: 0.88), in: Capsule())
            .shadow(color: Color.black.opacity(0.16), radius: 8, y: 3)
            .buttonStyle(.plain)
            .position(actionPosition(in: geometry.size))
        }
        .allowsHitTesting(true)
    }

    @ViewBuilder
    private var actionLabel: some View {
        if selectedElement.kind == .layoutBreak {
            Text("Remove")
        } else {
            Label("Remove", systemImage: "trash")
        }
    }

    private func actionPosition(in size: CGSize) -> CGPoint {
        let rect = actionAnchorCGRect(in: size)
        let rawX = selectedElement.kind == .layoutBreak ? rect.midX : rect.maxX + 28
        let rawY = rect.minY - (selectedElement.kind == .layoutBreak ? 36 : 26)
        return CGPoint(
            x: min(max(rawX, 42), max(size.width - 42, 42)),
            y: min(max(rawY, 26), max(size.height - 26, 26))
        )
    }

    private func actionAnchorCGRect(in size: CGSize) -> CGRect {
        coordinateSpace.rect(for: selectedElement.actionRect, in: size)
    }

    private var coordinateSpace: ScoreReaderOverlayCoordinateSpace {
        ScoreReaderOverlayCoordinateSpace(imageSize: imageSize, viewport: zoomViewport)
    }
}

/// The view-mode long-press affordance: the pressed bar is outlined in place
/// and a pill offers to start playback from it. Both are anchored to score
/// content through the live zoom viewport, so they track the bar while the
/// reader pans and pinches.
struct ScoreReaderPlayFromHereOverlay: View {
    let target: ScorePlayFromHereTarget
    let imageSize: CGSize?
    @Binding var zoomViewport: ScoreReaderZoomViewport
    let playAction: () -> Void
    let loopAction: () -> Void

    private static let accent = Color(red: 0.12, green: 0.36, blue: 0.88)

    var body: some View {
        GeometryReader { geometry in
            let rect = coordinateSpace.rect(for: target.normalizedRect, in: geometry.size)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Self.accent.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Self.accent.opacity(0.55), lineWidth: 1.5)
                    )
                    .frame(width: max(rect.width, 1), height: max(rect.height, 1))
                    #if os(Android)
                    // Android: keep the decorative hit-test node at the bar's size.
                    // Skip's position wrapper fills the page and blocks page gestures.
                    .offset(x: rect.minX, y: rect.minY)
                    #else
                    .position(x: rect.midX, y: rect.midY)
                    #endif
                    .allowsHitTesting(false)

                HStack(spacing: 6) {
                    Button(action: playAction) {
                        Label("Play from here", systemImage: "play.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(Self.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button(action: loopAction) {
                        Label("Loop measure", systemImage: "repeat")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Self.accent)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(4)
                .background(.thinMaterial, in: Capsule())
                .shadow(color: Color.black.opacity(0.18), radius: 8, y: 3)
                .position(pillPosition(for: rect, in: geometry.size))
            }
        }
        .allowsHitTesting(true)
    }

    private func pillPosition(for rect: CGRect, in size: CGSize) -> CGPoint {
        // Sit above the bar, flipping underneath it when the bar is close
        // enough to the top edge that the pill would be clipped.
        let preferredY = rect.minY - 26
        let rawY = preferredY < 30 ? rect.maxY + 26 : preferredY
        return CGPoint(
            x: min(max(rect.midX, 132), max(size.width - 132, 132)),
            y: min(max(rawY, 30), max(size.height - 30, 30))
        )
    }

    private var coordinateSpace: ScoreReaderOverlayCoordinateSpace {
        ScoreReaderOverlayCoordinateSpace(imageSize: imageSize, viewport: zoomViewport)
    }
}

/// The range created by dragging after a view-mode long press. It stays
/// visible while looping so the repeat boundary remains obvious and provides
/// an in-place way to end the loop without entering Edit mode.
struct ScoreReaderPlaybackLoopOverlay: View {
    let range: ScorePlaybackLoopRange
    let isActive: Bool
    let imageSize: CGSize?
    @Binding var zoomViewport: ScoreReaderZoomViewport
    let toggleAction: () -> Void

    private static let accent = Color(red: 0.46, green: 0.24, blue: 0.82)

    var body: some View {
        GeometryReader { geometry in
            let rects = range.normalizedRects.map {
                coordinateSpace.rect(for: $0, in: geometry.size)
            }
            let highlightRects = mergedSystemRects(rects)
            let bounds = highlightRects.reduce(CGRect.null) { $0.union($1) }

            ZStack(alignment: .topLeading) {
                ForEach(Array(highlightRects.enumerated()), id: \.offset) { _, rect in
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Self.accent.opacity(isActive ? 0.18 : 0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(
                                    Self.accent.opacity(isActive ? 0.82 : 0.58),
                                    lineWidth: isActive ? 2 : 1.5
                                )
                        )
                        .frame(width: max(rect.width, 1), height: max(rect.height, 1))
                        #if os(Android)
                        .offset(x: rect.minX, y: rect.minY)
                        #else
                        .position(x: rect.midX, y: rect.midY)
                        #endif
                        .allowsHitTesting(false)
                }

                if !bounds.isNull {
                    Button(action: toggleAction) {
                        Label(
                            isActive ? "End loop" : "Loop range",
                            systemImage: isActive ? "repeat.circle.fill" : "repeat"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Self.accent, in: Capsule())
                        .shadow(color: Color.black.opacity(0.18), radius: 8, y: 3)
                    }
                    .buttonStyle(.plain)
                    .position(pillPosition(for: bounds, in: geometry.size))
                    .accessibilityLabel(isActive ? "End playback loop" : "Loop selected measures")
                    .accessibilityValue(
                        "\(range.measureCount) \(range.measureCount == 1 ? "measure" : "measures")"
                    )
                }
            }
        }
        .allowsHitTesting(true)
    }

    /// Adjacent selected measures share one highlight on each system. Ranges
    /// that wrap onto another system remain separate so the overlay does not
    /// cover unrelated music between the two rows.
    private func mergedSystemRects(_ rects: [CGRect]) -> [CGRect] {
        let sortedRects = rects.sorted {
            if abs($0.midY - $1.midY) > 1 {
                return $0.midY < $1.midY
            }
            return $0.minX < $1.minX
        }

        return sortedRects.reduce(into: [CGRect]()) { mergedRects, rect in
            guard let previous = mergedRects.last else {
                mergedRects.append(rect)
                return
            }

            let verticalOverlap = max(
                min(previous.maxY, rect.maxY) - max(previous.minY, rect.minY),
                0
            )
            let sharedSystem = verticalOverlap >= min(previous.height, rect.height) * 0.5
            if sharedSystem {
                mergedRects[mergedRects.count - 1] = previous.union(rect)
            } else {
                mergedRects.append(rect)
            }
        }
    }

    private func pillPosition(for rect: CGRect, in size: CGSize) -> CGPoint {
        let preferredY = rect.minY - 26
        let rawY = preferredY < 30 ? rect.maxY + 26 : preferredY
        return CGPoint(
            x: min(max(rect.midX, 82), max(size.width - 82, 82)),
            y: min(max(rawY, 30), max(size.height - 30, 30))
        )
    }

    private var coordinateSpace: ScoreReaderOverlayCoordinateSpace {
        ScoreReaderOverlayCoordinateSpace(imageSize: imageSize, viewport: zoomViewport)
    }
}

struct ScoreReaderOverlayCoordinateSpace {
    let imageSize: CGSize?
    let viewport: ScoreReaderZoomViewport

    func rect(for normalizedRect: ScoreNormalizedRect, in size: CGSize) -> CGRect {
        let pageSize = viewport.contentSize.width > 0 && viewport.contentSize.height > 0
            ? viewport.contentSize
            : size
        let imageRect = fittedImageRect(in: pageSize)
        let unzoomedRect = CGRect(
            x: imageRect.minX + CGFloat(normalizedRect.x) * imageRect.width,
            y: imageRect.minY + CGFloat(normalizedRect.y) * imageRect.height,
            width: CGFloat(normalizedRect.width) * imageRect.width,
            height: CGFloat(normalizedRect.height) * imageRect.height
        )
        return viewport.project(unzoomedRect)
    }

    private func fittedImageRect(in size: CGSize) -> CGRect {
        guard let imageSize, imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: size)
        }
        return AVMakeRect(aspectRatio: imageSize, insideRect: CGRect(origin: .zero, size: size))
    }
}

struct ScoreReaderSelectionCommandAnchor: Equatable {
    static let coordinateSpaceName = "ScoreReaderSelectionCommandOverlay"

    let selectedElement: ScoreSelectedElement
    let actionPosition: CGPoint
    let selectionRects: [CGRect]

    var identity: String {
        let rect = selectedElement.actionRect
        return "\(selectedElement.pageIndex)-\(selectedElement.kind)-\(rect.x)-\(rect.y)-\(rect.width)-\(rect.height)"
    }
}

struct ScoreReaderSelectionCommandAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: ScoreReaderSelectionCommandAnchor?

    static func reduce(value: inout ScoreReaderSelectionCommandAnchor?, nextValue: () -> ScoreReaderSelectionCommandAnchor?) {
        value = nextValue() ?? value
    }
}

struct ScoreReaderSelectedNoteRestActions: View {
    #if os(Android)
    @Environment(AndroidSelectionCommandPresentation.self) var commandPresentation: AndroidSelectionCommandPresentation?
    #endif
    let selectedElement: ScoreSelectedElement
    let imageSize: CGSize?
    @Binding var zoomViewport: ScoreReaderZoomViewport
    let copyAction: () -> Void
    let cutAction: () -> Void
    let pasteAction: () -> Void
    let deleteAction: () -> Void
    let transposeAction: (ScoreTransposeRequest) -> Void
    let changeEnharmonicAction: () -> Void
    let accentAction: (String) -> Void

    var body: some View {
        GeometryReader { geometry in
            #if os(Android)
            let anchor = commandAnchor(in: geometry)
            Color.clear
                .onChange(of: anchor, initial: true) { _, next in
                    commandPresentation?.publish(next, from: selectedElement.pageIndex)
                }
                .onDisappear {
                    commandPresentation?.remove(identity: anchor.identity, from: selectedElement.pageIndex)
                }
            #else
            Color.clear
                .preference(
                    key: ScoreReaderSelectionCommandAnchorPreferenceKey.self,
                    value: commandAnchor(in: geometry)
                )
            #endif
        }
        #if !os(Android)
        .allowsHitTesting(false)
        #endif
    }

    private func actionPosition(in size: CGSize) -> CGPoint {
        let rect = actionAnchorCGRect(in: size)
        let yOffset: CGFloat = selectedElement.kind == .rest || selectedElement.highlightRects.count > 1 ? 28 : 36
        return CGPoint(x: rect.maxX + 20, y: rect.minY - yOffset)
    }

    private func actionAnchorRect() -> ScoreNormalizedRect {
        selectedElement.highlightRects.first ?? selectedElement.actionRect
    }

    private func selectionAnchorRects(in size: CGSize) -> [CGRect] {
        let rects = selectedElement.highlightRects.isEmpty ? [actionAnchorRect()] : selectedElement.highlightRects
        return rects.map { rect in
            coordinateSpace.rect(for: rect, in: size).insetBy(dx: -10, dy: -10)
        }
    }

    private func actionAnchorCGRect(in size: CGSize) -> CGRect {
        coordinateSpace.rect(for: actionAnchorRect(), in: size)
    }

    private var coordinateSpace: ScoreReaderOverlayCoordinateSpace {
        ScoreReaderOverlayCoordinateSpace(imageSize: imageSize, viewport: zoomViewport)
    }

    private func commandAnchor(in geometry: GeometryProxy) -> ScoreReaderSelectionCommandAnchor {
        let frame = geometry.frame(in: .named(ScoreReaderSelectionCommandAnchor.coordinateSpaceName))
        let position = actionPosition(in: geometry.size)
        return ScoreReaderSelectionCommandAnchor(
            selectedElement: selectedElement,
            actionPosition: CGPoint(x: frame.minX + position.x, y: frame.minY + position.y),
            selectionRects: selectionAnchorRects(in: geometry.size).map { $0.offsetBy(dx: frame.minX, dy: frame.minY) }
        )
    }
}

struct ScoreReaderSelectionCommandOverlay: View {
    #if os(Android)
    @Environment(AndroidSelectionCommandPresentation.self) var commandPresentation: AndroidSelectionCommandPresentation?
    #endif
    @State var isMenuPresented = false
    @State var isTransposePresented = false

    let anchor: ScoreReaderSelectionCommandAnchor
    let copyAction: () -> Void
    let cutAction: () -> Void
    let pasteAction: () -> Void
    let deleteSelectionAction: () -> Void
    let clearSelectedMeasureAction: () -> Void
    let removeSelectedMeasureAction: () -> Void
    let addMeasureAction: () -> Void
    let addMultipleMeasuresAction: () -> Void
    let transposeAction: (ScoreTransposeRequest) -> Void
    let useTransposeSheet: Bool
    let openTransposeSheetAction: (Int) -> Void
    let changeEnharmonicAction: () -> Void
    let flipStemAction: () -> Void
    let changeInstrumentAction: () -> Void
    let keySignatureAction: () -> Void
    let timeSignatureAction: () -> Void
    let tempoAction: () -> Void
    let pickupMeasureAction: () -> Void
    let accentAction: (String) -> Void
    let selectSimilarAction: (Bool) -> Void
    let barLineAction: (String) -> Void
    let dismissAction: (String) -> Void

    // Keep observation of live geometry inside the small GeometryReader content.
    // Identity, action callbacks and semantic selection do not change during pan.
    private var positionAnchor: ScoreReaderSelectionCommandAnchor {
        #if os(Android)
        commandPresentation?.anchor ?? anchor
        #else
        anchor
        #endif
    }

    private var selectedElement: ScoreSelectedElement {
        anchor.selectedElement
    }

    private var isNoteRestSelection: Bool {
        selectedElement.kind == .note || selectedElement.kind == .rest
    }

    private var isNoteSelection: Bool {
        selectedElement.kind == .note
    }

    private var isInstrumentSelection: Bool {
        selectedElement.kind == .instrumentName || selectedElement.kind == .instrumentChange
    }

    private var isBarLineSelection: Bool {
        selectedElement.kind == .bar
    }

    private var showsEnharmonicAction: Bool {
        isNoteSelection
            && (selectedElement.accidentalKind == .sharp || selectedElement.accidentalKind == .flat)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                if isMenuPresented {
                    commandMenu
                        .position(menuPosition(in: geometry.size))
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topTrailing)))
                        .zIndex(1)
                }

                if isTransposePresented {
                    ScoreReaderTransposePanel(
                        currentKey: selectedElement.currentKey,
                        cancelAction: dismissTransposePanel,
                        applyAction: applyTranspose
                    )
                    .position(transposePosition(in: geometry.size))
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topTrailing)))
                    .zIndex(2)
                }

                Button {
                    withAnimation(.snappy(duration: 0.16)) {
                        isTransposePresented = false
                        isMenuPresented.toggle()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Color(red: 0.12, green: 0.36, blue: 0.88), in: Circle())
                        .shadow(color: Color.black.opacity(0.16), radius: 8, y: 3)
                        .accessibilityLabel(isInstrumentSelection ? "Instrument options" : (isBarLineSelection ? "Bar line options" : (isNoteRestSelection ? "Selection options" : "Measure options")))
                }
                .buttonStyle(.plain)
                #if os(Android)
                .androidSelectionOverlayPosition(commandPresentation?.positioner, fallback: anchor.actionPosition)
                #else
                .position(positionAnchor.actionPosition)
                #endif
                .zIndex(3)
            }
        }
        .id(anchor.identity)
        .allowsHitTesting(true)
    }

    @ViewBuilder
    private var commandMenu: some View {
        if isInstrumentSelection {
            VStack(spacing: 0) {
                ScoreReaderMeasureCommandRow(
                    title: "Change Instrument",
                    systemImage: "music.note.list",
                    action: perform(changeInstrumentAction)
                )
            }
            .padding(.vertical, 6)
            .frame(width: 238)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.14), radius: 16, y: 8)
        } else if isBarLineSelection {
            ScoreReaderBarLineCommandMenu(barLineAction: { barLineKind in
                perform { barLineAction(barLineKind) }()
            })
        } else if isNoteRestSelection {
            ScoreReaderNoteRestCommandMenu(
                isNoteSelection: isNoteSelection,
                supportsBowingArticulations: selectedElement.supportsBowingArticulations,
                copyAction: perform(copyAction),
                cutAction: perform(cutAction),
                pasteAction: perform(pasteAction),
                deleteAction: perform(deleteSelectionAction),
                transposeAction: presentTransposePanel,
                showsEnharmonicAction: showsEnharmonicAction,
                changeEnharmonicAction: perform(changeEnharmonicAction),
                flipStemAction: perform(flipStemAction),
                selectSimilarAction: { sameStaff in
                    perform { selectSimilarAction(sameStaff) }()
                },
                accentAction: { expressionKind in
                    perform { accentAction(expressionKind) }()
                }
            )
        } else {
            ScoreReaderMeasureCommandMenu(
                copyAction: perform(copyAction),
                cutAction: perform(cutAction),
                pasteAction: perform(pasteAction),
                showsSingleMeasureCommands: selectedElement.isSingleMeasure,
                isFirstMeasure: selectedElement.isFirstMeasure,
                isPickupMeasure: selectedElement.isPickupMeasure,
                addMeasureAction: perform(addMeasureAction),
                addMultipleMeasuresAction: perform(addMultipleMeasuresAction),
                transposeAction: presentTransposePanel,
                keySignatureAction: perform(keySignatureAction),
                timeSignatureAction: perform(timeSignatureAction),
                tempoAction: perform(tempoAction),
                pickupMeasureAction: perform(pickupMeasureAction),
                changeInstrumentAction: perform(changeInstrumentAction),
                removeAction: perform(removeSelectedMeasureAction),
                clearAction: perform(clearSelectedMeasureAction)
            )
        }
    }

    private func presentTransposePanel() {
        if useTransposeSheet {
            withAnimation(.snappy(duration: 0.12)) {
                isMenuPresented = false
                isTransposePresented = false
            }
            dismissAction(anchor.identity)
            openTransposeSheetAction(selectedElement.currentKey)
            return
        }

        withAnimation(.snappy(duration: 0.14)) {
            isMenuPresented = false
            isTransposePresented = true
        }
    }

    private func dismissTransposePanel() {
        withAnimation(.snappy(duration: 0.14)) {
            isTransposePresented = false
        }
    }

    private func applyTranspose(_ request: ScoreTransposeRequest) {
        withAnimation(.snappy(duration: 0.12)) {
            isTransposePresented = false
        }
        transposeAction(request)
    }

    private func perform(_ action: @escaping () -> Void) -> () -> Void {
        {
            withAnimation(.snappy(duration: 0.12)) {
                isMenuPresented = false
                isTransposePresented = false
            }
            dismissAction(anchor.identity)
            action()
        }
    }

    private func menuPosition(in size: CGSize) -> CGPoint {
        // Note selections also carry the Flip Stem row, rest selections do not.
        let menuSize: CGSize
        if isInstrumentSelection {
            menuSize = CGSize(width: 238, height: 56)
        } else if isBarLineSelection {
            menuSize = CGSize(width: 218, height: CGFloat(ScoreReaderBarLineCommandMenu.barLineTypes.count) * 36 + 16)
        } else if isNoteRestSelection {
            // Select Similar adds two rows.
            menuSize = CGSize(width: 218, height: (isNoteSelection ? (showsEnharmonicAction ? 464 : 428) : 216) + 72)
        } else {
            menuSize = CGSize(width: 238, height: selectedElement.isSingleMeasure ? 508 : 362)
        }
        let rawX = positionAnchor.actionPosition.x - menuSize.width / 2 + 2
        let rawY = positionAnchor.actionPosition.y + 16 + menuSize.height / 2
        return CGPoint(
            x: min(max(rawX, menuSize.width / 2 + 8), max(size.width - menuSize.width / 2 - 8, menuSize.width / 2 + 8)),
            y: clampedPopoverY(rawY, popoverSize: menuSize, x: rawX, in: size)
        )
    }

    private func transposePosition(in size: CGSize) -> CGPoint {
        let panelSize = CGSize(width: 288, height: 454)
        let rawX = positionAnchor.actionPosition.x - panelSize.width / 2 + 16
        let rawY = positionAnchor.actionPosition.y + 16 + panelSize.height / 2
        return CGPoint(
            x: min(max(rawX, panelSize.width / 2 + 8), max(size.width - panelSize.width / 2 - 8, panelSize.width / 2 + 8)),
            y: clampedPopoverY(rawY, popoverSize: panelSize, x: rawX, in: size)
        )
    }

    private func clampedPopoverY(_ rawY: CGFloat, popoverSize: CGSize, x rawX: CGFloat, in size: CGSize) -> CGFloat {
        let bottomDeckClearance: CGFloat = 300
        let popoverHeight = popoverSize.height
        let minimumY = popoverHeight / 2 + 8
        let unobscuredMaximumY = size.height - popoverHeight / 2 - bottomDeckClearance
        let maximumY = max(minimumY, unobscuredMaximumY)
        let clampedX = min(max(rawX, popoverSize.width / 2 + 8), max(size.width - popoverSize.width / 2 - 8, popoverSize.width / 2 + 8))
        let anchorRects = positionAnchor.selectionRects

        func clamp(_ y: CGFloat) -> CGFloat {
            min(max(y, minimumY), maximumY)
        }

        func frame(for y: CGFloat) -> CGRect {
            CGRect(
                x: clampedX - popoverSize.width / 2,
                y: y - popoverSize.height / 2,
                width: popoverSize.width,
                height: popoverSize.height
            )
        }

        let selectionTop = anchorRects.map(\.minY).min() ?? positionAnchor.actionPosition.y
        let selectionBottom = anchorRects.map(\.maxY).max() ?? positionAnchor.actionPosition.y
        let candidates = [
            rawY,
            positionAnchor.actionPosition.y - 28 - popoverHeight / 2,
            selectionTop - popoverHeight / 2 - 12,
            selectionBottom + popoverHeight / 2 + 12
        ].map(clamp)

        if let clearCandidate = candidates.first(where: { candidate in
            let popoverFrame = frame(for: candidate)
            return !anchorRects.contains(where: { $0.intersects(popoverFrame) })
        }) {
            return clearCandidate
        }

        return candidates.min { lhs, rhs in
            overlapArea(frame(for: lhs), selectionRects: anchorRects) < overlapArea(frame(for: rhs), selectionRects: anchorRects)
        } ?? clamp(rawY)
    }

    private func overlapArea(_ frame: CGRect, selectionRects: [CGRect]) -> CGFloat {
        selectionRects.reduce(CGFloat.zero) { partialResult, selectionRect in
            let intersection = frame.intersection(selectionRect)
            guard !intersection.isNull else {
                return partialResult
            }
            return partialResult + max(0, intersection.width) * max(0, intersection.height)
        }
    }
}

struct ScoreReaderNoteRestCommandMenu: View {
    let isNoteSelection: Bool
    let supportsBowingArticulations: Bool
    let copyAction: () -> Void
    let cutAction: () -> Void
    let pasteAction: () -> Void
    let deleteAction: () -> Void
    let transposeAction: () -> Void
    let showsEnharmonicAction: Bool
    let changeEnharmonicAction: () -> Void
    let flipStemAction: () -> Void
    let selectSimilarAction: (Bool) -> Void
    let accentAction: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScoreReaderMeasureCommandRow(
                title: "Copy",
                systemImage: "doc.on.doc",
                shortcut: "⌘C",
                action: copyAction
            )

            ScoreReaderMeasureCommandRow(
                title: "Cut",
                systemImage: "scissors",
                shortcut: "⌘X",
                action: cutAction
            )

            ScoreReaderMeasureCommandRow(
                title: "Paste",
                systemImage: "doc.on.clipboard",
                shortcut: "⌘V",
                action: pasteAction
            )

            ScoreReaderMeasureCommandRow(
                title: "Transpose",
                systemImage: "arrow.up.arrow.down",
                action: transposeAction
            )

            ScoreReaderMeasureCommandRow(
                title: "Select Similar",
                systemImage: "lasso",
                action: { selectSimilarAction(false) }
            )

            ScoreReaderMeasureCommandRow(
                title: "Similar on Staff",
                systemImage: "line.3.horizontal",
                action: { selectSimilarAction(true) }
            )

            if showsEnharmonicAction {
                ScoreReaderMeasureCommandRow(
                    title: "Respell",
                    symbolText: "#♭",
                    action: changeEnharmonicAction
                )
            }

            // Rests have no stem to flip, so this matches MuseScore's own flip
            // command and only appears for notes and chords.
            if isNoteSelection {
                ScoreReaderMeasureCommandRow(
                    title: "Flip Stem",
                    systemImage: "music.note",
                    action: flipStemAction
                )
            }

            ScoreReaderMeasureCommandDivider()

            let articulations = [ScoreReaderArticulationTools.fermata]
                + (isNoteSelection ? ScoreReaderArticulationTools.tools(supportsBowingArticulations: supportsBowingArticulations) : [])
            if !articulations.isEmpty {
                ForEach(articulations) { articulation in
                    ScoreReaderMeasureCommandRow(
                        title: articulation.title,
                        symbolText: articulation.symbol,
                        musicGlyph: articulation.musicGlyph,
                        action: { accentAction(articulation.token) }
                    )
                }

                ScoreReaderMeasureCommandDivider()
            }

            ScoreReaderMeasureCommandRow(
                title: "Delete",
                systemImage: "trash",
                role: .destructive,
                action: deleteAction
            )
        }
        .padding(.vertical, 8)
        .frame(width: 218)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
        }
        .shadow(color: Color.black.opacity(0.20), radius: 20, y: 10)
    }
}

/// Bar line types from MuseScore's Barlines palette. The kind names are the engine's
/// repeat-and-jump command keys.
struct ScoreReaderBarLineCommandMenu: View {
    struct BarLineType: Identifiable {
        let kind: String
        let title: String
        let musicGlyph: String

        var id: String { kind }
    }

    static let barLineTypes = [
        BarLineType(kind: "Normal barline", title: "Single", musicGlyph: "\u{E030}"),
        BarLineType(kind: "Double barline", title: "Double", musicGlyph: "\u{E031}"),
        BarLineType(kind: "Final barline", title: "Final", musicGlyph: "\u{E032}"),
        BarLineType(kind: "Reverse final barline", title: "Reverse Final", musicGlyph: "\u{E033}"),
        BarLineType(kind: "Heavy barline", title: "Heavy", musicGlyph: "\u{E034}"),
        BarLineType(kind: "Heavy double barline", title: "Heavy Double", musicGlyph: "\u{E035}"),
        BarLineType(kind: "Dashed barline", title: "Dashed", musicGlyph: "\u{E036}"),
        BarLineType(kind: "Dotted barline", title: "Dotted", musicGlyph: "\u{E037}")
    ]

    let barLineAction: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Self.barLineTypes) { barLineType in
                ScoreReaderMeasureCommandRow(
                    title: barLineType.title,
                    musicGlyph: barLineType.musicGlyph,
                    action: { barLineAction(barLineType.kind) }
                )
            }
        }
        .padding(.vertical, 8)
        .frame(width: 218)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
        }
        .shadow(color: Color.black.opacity(0.20), radius: 20, y: 10)
    }
}

struct ScoreReaderSelectedMeasureActions: View {
    #if os(Android)
    @Environment(AndroidSelectionCommandPresentation.self) var commandPresentation: AndroidSelectionCommandPresentation?
    #endif
    let selectedElement: ScoreSelectedElement
    let imageSize: CGSize?
    @Binding var zoomViewport: ScoreReaderZoomViewport
    let clearAction: () -> Void
    let removeAction: () -> Void
    let addMeasureAction: () -> Void
    let addMultipleMeasuresAction: () -> Void
    let copyAction: () -> Void
    let cutAction: () -> Void
    let pasteAction: () -> Void
    let transposeAction: (ScoreTransposeRequest) -> Void
    let keySignatureAction: () -> Void
    let timeSignatureAction: () -> Void
    let tempoAction: () -> Void

    var body: some View {
        GeometryReader { geometry in
            #if os(Android)
            let anchor = commandAnchor(in: geometry)
            Color.clear
                .onChange(of: anchor, initial: true) { _, next in
                    commandPresentation?.publish(next, from: selectedElement.pageIndex)
                }
                .onDisappear {
                    commandPresentation?.remove(identity: anchor.identity, from: selectedElement.pageIndex)
                }
            #else
            Color.clear
                .preference(
                    key: ScoreReaderSelectionCommandAnchorPreferenceKey.self,
                    value: commandAnchor(in: geometry)
                )
            #endif
        }
        #if !os(Android)
        .allowsHitTesting(false)
        #endif
    }

    private func actionPosition(in size: CGSize) -> CGPoint {
        let rect = actionAnchorCGRect(in: size)
        return CGPoint(x: rect.maxX + 20, y: rect.minY - 22)
    }

    private func actionAnchorRect() -> ScoreNormalizedRect {
        selectedElement.highlightRects.first ?? selectedElement.actionRect
    }

    private func actionAnchorCGRect(in size: CGSize) -> CGRect {
        coordinateSpace.rect(for: actionAnchorRect(), in: size)
    }

    private var coordinateSpace: ScoreReaderOverlayCoordinateSpace {
        ScoreReaderOverlayCoordinateSpace(imageSize: imageSize, viewport: zoomViewport)
    }

    private func commandAnchor(in geometry: GeometryProxy) -> ScoreReaderSelectionCommandAnchor {
        let frame = geometry.frame(in: .named(ScoreReaderSelectionCommandAnchor.coordinateSpaceName))
        let position = actionPosition(in: geometry.size)
        let selectionRect = actionAnchorCGRect(in: geometry.size).insetBy(dx: -10, dy: -10)
        return ScoreReaderSelectionCommandAnchor(
            selectedElement: selectedElement,
            actionPosition: CGPoint(x: frame.minX + position.x, y: frame.minY + position.y),
            selectionRects: [selectionRect.offsetBy(dx: frame.minX, dy: frame.minY)]
        )
    }
}

struct ScoreReaderMeasureCommandMenu: View {
    let copyAction: () -> Void
    let cutAction: () -> Void
    let pasteAction: () -> Void
    let showsSingleMeasureCommands: Bool
    let isFirstMeasure: Bool
    let isPickupMeasure: Bool
    let addMeasureAction: () -> Void
    let addMultipleMeasuresAction: () -> Void
    let transposeAction: () -> Void
    let keySignatureAction: () -> Void
    let timeSignatureAction: () -> Void
    let tempoAction: () -> Void
    let pickupMeasureAction: () -> Void
    let changeInstrumentAction: () -> Void
    let removeAction: () -> Void
    let clearAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScoreReaderMeasureCommandRow(
                title: "Copy",
                systemImage: "doc.on.doc",
                shortcut: "⌘C",
                action: copyAction
            )

            ScoreReaderMeasureCommandRow(
                title: "Cut",
                systemImage: "scissors",
                shortcut: "⌘X",
                action: cutAction
            )

            ScoreReaderMeasureCommandRow(
                title: "Paste",
                systemImage: "doc.on.clipboard",
                shortcut: "⌘V",
                action: pasteAction
            )

            ScoreReaderMeasureCommandDivider()

            ScoreReaderMeasureCommandRow(
                title: "Add Measure",
                systemImage: "pause",
                action: addMeasureAction
            )

            ScoreReaderMeasureCommandRow(
                title: "Add Multiple Measures...",
                systemImage: "rectangle.grid.1x2",
                action: addMultipleMeasuresAction
            )

            if isFirstMeasure {
                ScoreReaderMeasureCommandRow(
                    title: isPickupMeasure ? "Edit Pickup Measure..." : "Convert to Pickup Measure",
                    systemImage: "forward.end",
                    action: pickupMeasureAction
                )
            }

            ScoreReaderMeasureCommandDivider()

            ScoreReaderMeasureCommandRow(
                title: "Transpose",
                systemImage: "arrow.up.arrow.down",
                action: transposeAction
            )

            if showsSingleMeasureCommands {
                ScoreReaderMeasureCommandRow(
                    title: "Key Signature",
                    symbolText: "#♭",
                    action: keySignatureAction
                )

                ScoreReaderMeasureCommandRow(
                    title: "Time Signature",
                    symbolText: "4\n4",
                    action: timeSignatureAction
                )

                ScoreReaderMeasureCommandRow(
                    title: "Change Instrument",
                    systemImage: "music.note.list",
                    action: changeInstrumentAction
                )

            }

            ScoreReaderMeasureCommandRow(
                title: "Tempo",
                systemImage: "music.note",
                action: tempoAction
            )

            ScoreReaderMeasureCommandDivider()

            ScoreReaderMeasureCommandRow(
                title: "Delete Measure",
                systemImage: "trash",
                role: .destructive,
                action: removeAction
            )

            ScoreReaderMeasureCommandRow(
                title: "Clear Measure",
                systemImage: "eraser",
                action: clearAction
            )
        }
        .padding(.vertical, 8)
        .frame(width: 238)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
        }
        .shadow(color: Color.black.opacity(0.20), radius: 20, y: 10)
    }
}

struct ScoreReaderMeasureCommandRow: View {
    let title: String
    var systemImage: String? = nil
    var symbolText: String? = nil
    var musicGlyph: String? = nil
    var shortcut: String?
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 12) {
                iconView
                    .frame(width: 18, height: 18)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Spacer(minLength: 8)

                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.36))
                }
            }
            .foregroundStyle(role == .destructive ? Color.red : Color.black.opacity(0.82))
            .padding(.horizontal, 14)
            .frame(height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var iconView: some View {
        if let systemImage {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
        } else if let musicGlyph {
            Image(uiImage: ScoreReaderClefImage.image(for: musicGlyph))
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
        } else if let symbolText {
            Text(symbolText)
                .font(.system(size: symbolText.contains("\n") ? 11 : 15, weight: .bold))
                .multilineTextAlignment(.center)
                .lineSpacing(-4)
                .minimumScaleFactor(0.7)
        }
    }
}

struct ScoreReaderMeasureCommandDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.black.opacity(0.08))
            .frame(height: 0.5)
            .padding(.vertical, 5)
    }
}

struct ScoreReaderTransposePanel: View {
    @State var mode: ScoreTransposeMode = .interval
    @State var direction: ScoreTransposeDirection = .up
    @State var diatonicStep = ScoreTransposeDiatonicStep.third
    @State var interval = ScoreTransposeInterval.majorSecond
    @State var targetKey: ScoreTransposeTargetKey

    let title: String
    let isSheetStyle: Bool
    let cancelAction: () -> Void
    let applyAction: (ScoreTransposeRequest) -> Void

    init(
        currentKey: Int,
        title: String = "Transpose",
        isSheetStyle: Bool = false,
        cancelAction: @escaping () -> Void,
        applyAction: @escaping (ScoreTransposeRequest) -> Void
    ) {
        _targetKey = State(initialValue: ScoreTransposeTargetKey(coreKey: currentKey) ?? .cMajor)
        self.title = title
        self.isSheetStyle = isSheetStyle
        self.cancelAction = cancelAction
        self.applyAction = applyAction
    }

    var body: some View {
        VStack(spacing: 14) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.88))

            ScoreReaderTransposeSegmentedControl(selection: $mode)

            VStack(alignment: .leading, spacing: 9) {
                Text(sectionTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.48))

                switch mode {
                case .diatonic:
                    ScoreReaderTransposeListSelection(items: ScoreTransposeDiatonicStep.allCases, selection: $diatonicStep)
                case .interval:
                    ScoreReaderTransposeGridSelection(items: ScoreTransposeInterval.allCases, selection: $interval)
                case .byKey:
                    ScrollView {
                        ScoreReaderTransposeListSelection(items: ScoreTransposeTargetKey.allCases, selection: $targetKey)
                    }
                    .frame(maxHeight: 292)
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                Text("Direction")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.48))

                ScoreReaderDirectionToggle(selection: $direction)
            }

            HStack(spacing: 16) {
                Button(action: cancelAction) {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ScoreReaderTransposePanelButtonStyle(kind: .secondary))

                Button {
                    applyAction(request)
                } label: {
                    Text("Apply")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ScoreReaderTransposePanelButtonStyle(kind: .primary))
            }
        }
        .padding(isSheetStyle ? 20 : 16)
        .frame(width: isSheetStyle ? nil : 288)
        .frame(maxWidth: isSheetStyle ? 420 : nil)
        .background {
            if !isSheetStyle {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.regularMaterial)
            }
        }
        .overlay {
            if !isSheetStyle {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
            }
        }
        .shadow(color: Color.black.opacity(isSheetStyle ? 0 : 0.20), radius: 20, y: 10)
    }

    private var sectionTitle: String {
        switch mode {
        case .diatonic:
            return "Diatonic steps"
        case .interval:
            return "Interval"
        case .byKey:
            return "Target key"
        }
    }

    private var request: ScoreTransposeRequest {
        switch mode {
        case .diatonic:
            return ScoreTransposeRequest(mode: mode, direction: direction, interval: diatonicStep.coreInterval, targetKey: 0)
        case .interval:
            return ScoreTransposeRequest(mode: mode, direction: direction, interval: interval.coreInterval, targetKey: 0)
        case .byKey:
            return ScoreTransposeRequest(mode: mode, direction: direction, interval: 0, targetKey: targetKey.coreKey)
        }
    }
}

struct ScoreReaderTransposeSegmentedControl: View {
    @Binding var selection: ScoreTransposeMode

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ScoreTransposeMode.allCases, id: \.self) { mode in
                Button {
                    selection = mode
                } label: {
                    Text(mode.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selection == mode ? Color.black.opacity(0.86) : Color.black.opacity(0.72))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background {
                            if selection == mode {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.white)
                                    .shadow(color: Color.black.opacity(0.08), radius: 2, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.black.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ScoreReaderTransposeListSelection<Item: ScoreReaderTransposeOption>: View {
    let items: [Item]
    @Binding var selection: Item

    var body: some View {
        VStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                Button {
                    selection = item
                } label: {
                    HStack {
                        Text(item.title)
                        Spacer()
                        if selection == item {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(selection == item ? Color.blue : Color.black.opacity(0.84))
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(selection == item ? Color.blue.opacity(0.10) : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < items.index(before: items.endIndex) {
                    Rectangle()
                        .fill(Color.black.opacity(0.06))
                        .frame(height: 0.5)
                }
            }
        }
        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
        }
    }
}

struct ScoreReaderTransposeGridSelection<Item: ScoreReaderTransposeOption>: View {
    let items: [Item]
    @Binding var selection: Item

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        AriaGrid(columns: columns, spacing: 8, items: items, id: \.self) { item in
            Button {
                selection = item
            } label: {
                HStack(spacing: 6) {
                    Text(item.title)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                    if selection == item {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selection == item ? Color.blue : Color.black.opacity(0.82))
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Color.white.opacity(selection == item ? 0.96 : 0.74), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(selection == item ? Color.blue : Color.black.opacity(0.08), lineWidth: selection == item ? 1.2 : 0.5)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

struct ScoreReaderDirectionToggle: View {
    @Binding var selection: ScoreTransposeDirection

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ScoreTransposeDirection.allCases, id: \.self) { direction in
                Button {
                    selection = direction
                } label: {
                    Text(direction.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selection == direction ? Color.blue : Color.black.opacity(0.74))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background {
                            if selection == direction {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.white)
                                    .shadow(color: Color.black.opacity(0.07), radius: 2, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.black.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ScoreReaderTransposePanelButtonStyle: AriaLabelButtonStyle {
    enum Kind {
        case primary
        case secondary
    }

    let kind: Kind

    func styled(_ label: AnyView, isPressed: Bool) -> some View {
        label
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(kind == .primary ? Color.white : Color.black.opacity(0.82))
            .frame(height: 48)
            .background(background.opacity(isPressed ? 0.76 : 1), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                if kind == .secondary {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 0.8)
                }
            }
    }

    private var background: Color {
        kind == .primary ? Color.blue : Color.white.opacity(0.78)
    }
}

struct ScoreReaderPagePlaceholder: View {
    let pageIndex: Int
    let isLoading: Bool
    let errorText: String?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: errorText == nil ? "doc.text.magnifyingglass" : "exclamationmark.triangle")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Color.black.opacity(0.65))

            Text("Page \(pageIndex + 1)")
                .font(.title3.weight(.bold))
                .foregroundStyle(.black)

            Text(statusText)
                .font(.body)
                .foregroundStyle(.black.opacity(0.62))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            if isLoading {
                ProgressView()
                    .tint(.black)
            }
        }
        .padding(28)
    }

    private var statusText: String {
        if let errorText {
            return errorText
        }

        return isLoading
            ? "Aria is rendering this page from the live score session."
            : "This page has not been rendered yet."
    }
}

struct ScoreReaderFloatingControlButton: View {
    let systemImage: String
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))

                Text(title)
                    .font(.headline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .disabled(!isEnabled)
        .shadow(color: Color.black.opacity(0.20), radius: 24, y: 14)
    }
}

struct ScoreReaderFloatingPlaybackButton: View {
    let playbackState: ScorePlaybackState
    let isBusy: Bool
    let togglePlaybackAction: () -> Void

    var body: some View {
        Button(action: togglePlaybackAction) {
            Group {
                if isBusy {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: playbackState.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 54, height: 54)
            .background(.ultraThinMaterial, in: Circle())
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!playbackState.isAvailable || isBusy)
        .opacity(playbackState.isAvailable ? 1 : 0.45)
        .shadow(color: Color.black.opacity(0.20), radius: 24, y: 14)
    }
}

struct ScoreReaderZoomControls: View {
    let zoomPercent: Int
    let zoomInAction: () -> Void
    let zoomOutAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: zoomInAction) {
                Image(systemName: "plus.magnifyingglass")
                    .font(.headline)
                    .frame(width: 56, height: 52)
            }
            .buttonStyle(.plain)

            Divider()
                .overlay(Color.white.opacity(0.08))

            Text("\(zoomPercent)%")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.78))
                .frame(width: 56, height: 36)

            Divider()
                .overlay(Color.white.opacity(0.08))

            Button(action: zoomOutAction) {
                Image(systemName: "minus.magnifyingglass")
                    .font(.headline)
                    .frame(width: 56, height: 52)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct ScoreReaderUnavailableView: View {
    let detailText: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.white.opacity(0.82))

            Text("Full-screen reader is not available for this score yet.")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            Text(detailText)
                .font(.body)
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
        }
        .padding(32)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}
