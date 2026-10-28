// Android's ZoomableImageView (Views/ZoomableImageView.swift on iOS, a UIScrollView with
// layered UIKit views): the score page with the same initializer, drawn in SwiftUI.
//
// Like the iOS scroll view it zooms (pinch, 1x to 6x) and pans the page inside its frame,
// keeps the page within the insets of ScoreReaderZoomLayout (shared with iOS), reports
// the visible viewport through `zoomViewport` (the canvas places its overlays with it),
// and scrolls to the active notation and the playing measure. It draws the page (PDF
// drawn to a bitmap at the zoomed resolution), the playback highlight, the selection, the
// note-entry preview and layout markers, and handles taps, swipes, reading long press,
// dragging a selected note or element, measure-range drags, and annotations (drawn by
// AndroidScoreAnnotationLayer). Not yet: Pencil-only features.

// Not limited to Android: the Skip project's own iOS build (a build step only; the iOS
// app is MuseReaderiOS/Aria.xcodeproj) compiles it in place of the held-back iOS file.
import Foundation
import SwiftUI

struct ZoomableImageView: View {
    let imageData: Data?
    let pdfData: Data?
    let prefersRasterAtRest: Bool
    let contentSize: CGSize
    let displayedPageSize: CGSize
    let playbackHighlight: ScorePlaybackMeasureHighlight?
    let selection: ScoreSelectedElement?
    let noteEntryPreview: ScoreNoteEntryPreview?
    let layoutMarkers: [ScoreLayoutMarker]
    @Binding var zoomScale: CGFloat
    @Binding var zoomViewport: ScoreReaderZoomViewport
    var activeNotationAutoScrollRevision = 0
    var activeNotationTopInset: CGFloat = 0
    var activeNotationBottomInset: CGFloat = 0
    var activeNotationViewportHeight: CGFloat = 0
    var pageHorizontalAlignment: ScoreReaderPageHorizontalAlignment = .center
    var centersPageVertically = false
    var restingHorizontalEdgePadding: CGFloat = 0
    var restingTopInset: CGFloat = 0
    var showsPageBoundary = true
    var allowsEditingInteractions = true
    var allowsPlaybackFollow = true
    var allowsPencilInsertionFineTune = false
    /// The shared call site passes "editing with note input on" as allowsPencilInsertionFineTune.
    /// Android has no Pencil fine-tune, so read it as note input.
    private var noteInputActive: Bool { allowsPencilInsertionFineTune }
    var noteEntryPreviewPitchClass: Int? = nil
    var noteEntryPreviewIsRest = false
    var noteEntryPreviewDuration: ScoreNoteDuration = .quarter
    var showsLayoutMarkers = false
    var onTap: ((CGPoint, ScorePageTapInputKind) -> Void)? = nil
    var onSelectedNoteDrag: ((CGPoint) -> Void)? = nil
    var onExpressionEndpointDrag: ((Bool, CGPoint) -> Void)? = nil
    var onSelectedMovableElementDrag: ((CGPoint) -> Void)? = nil
    var onMeasureRangePreview: ((CGPoint, CGPoint) -> Void)? = nil
    var onMeasureRangePreviewEnd: (() -> Void)? = nil
    var onMeasureRangeDrag: ((CGPoint, CGPoint) -> Void)? = nil
    var onPencilInsertionFineTune: ((CGPoint, CGPoint) -> Void)? = nil
    var onPencilHoverPreview: ((CGPoint?) -> Void)? = nil
    var onPencilInteractionStart: (() -> Void)? = nil
    var onPencilDoubleTap: (() -> Void)? = nil
    var onSwipePreviousPage: (() -> Void)? = nil
    var onSwipeNextPage: (() -> Void)? = nil
    var onReadingLongPress: ((CGPoint, CGPoint) -> Void)? = nil
    var onManualScroll: (() -> Void)? = nil
    var annotationStrokes: [ScoreRenderedAnnotationStroke] = []
    var selectedAnnotationStrokeIDs: Set<UUID> = []
    var annotationModeActive = false
    var annotationsVisible = true
    var allowsAnnotationInteraction = false
    var annotationTool: ScoreAnnotationTool = .pen
    var annotationColor: ScoreAnnotationColor = .black
    var annotationWidth: Double = 4
    var onAnnotationInteractionStart: (() -> Void)? = nil
    var onAnnotationStrokeCommit: (([CGPoint]) -> Void)? = nil
    var onAnnotationErase: (([CGPoint]) -> Void)? = nil
    var onAnnotationLasso: ((CGRect) -> Void)? = nil
    var onAnnotationMoveSelection: ((CGPoint) -> Void)? = nil

    @State var pageImage: UIImage?
    @State var pageImageScale: CGFloat = 0
    @State var selectionImage: UIImage?
    @State var previewImage: UIImage?
    @Environment(\.ariaRasterVisible) var isRasterVisible
    @State var pageRasterOwner = UUID()
    @State var selectionRasterOwner = UUID()
    @State var pageRasterGeneration = 0
    @State var selectionRasterGeneration = 0
    @State var viewportPublisher = AndroidViewportPublisher()
    @State var rasterWidthLimit: CGFloat = 4096
    /// UIScrollView's contentOffset: the visible origin within the zoomed page.
    @State var contentOffset: CGPoint = .zero
    @State var boundsSize: CGSize = .zero
    @State var liveScale: CGFloat?
    @State var pinchStart: (scale: CGFloat, offset: CGPoint, location: CGPoint)?
    @State var panStartOffset: CGPoint?
    @State var hasPlacedInitialOffset = false
    @State var lastActiveNotationRevision = 0
    @State var lastPlaybackRect: ScoreNormalizedRect?
    @State var dragMode: DragMode?
    @State var selectionDragOffset: CGSize = .zero
    @State var gestureStart = CGPoint.zero
    @State var readingDragStart: CGPoint?
    @State var annotationPoints: [CGPoint] = []
    @State var annotationMoveStart: CGPoint?
    /// A dragged slur or hairpin end, in page space.
    @State var expressionEndpointPreview: CGPoint?

    /// A held page drag selects a range, as on iOS. Fast movement pans unless it
    /// starts on an existing selected note, element, endpoint or measure edge.
    enum DragMode: Equatable {
        case pan(start: CGPoint)
        case selectedNote(start: CGPoint)
        case movableElement(start: CGPoint)
        case expressionEndpoint(isStart: Bool)
        case measureRange(start: CGPoint, anchor: CGRect?)
        case annotation(movesSelection: Bool)
        case swipe
    }

    static let maximumScale: CGFloat = 6

    private var scale: CGFloat {
        liveScale ?? min(max(zoomScale, ScoreReaderZoomLimits.minimumScale), Self.maximumScale)
    }

    private var pageSize: CGSize {
        CGSize(width: max(displayedPageSize.width, 1), height: max(displayedPageSize.height, 1))
    }

    private var zoomedPageSize: CGSize {
        CGSize(width: pageSize.width * scale, height: pageSize.height * scale)
    }

    /// One finger draws while annotating (iOS pans with two then).
    private var drawsAnnotations: Bool {
        annotationModeActive && allowsAnnotationInteraction
    }

    private var usesActiveNotationFocus: Bool {
        activeNotationTopInset > 0 || activeNotationBottomInset > 0
    }

    var body: some View {
        #if os(Android) && ARIA_PHONE_AUDIT
        let _ = AndroidPhoneAuditGeometry.evaluate("page")
        let _ = tracePage("page_evaluate")
        #endif
        #if ARIA_PERF_DIAGNOSTICS && os(Android)
        let _ = AriaJNILifecycle.record("PageEvaluate", created: true)
        #endif
        GeometryReader { proxy in
            #if os(Android) && ARIA_PHONE_AUDIT
            let _ = isRasterVisible ? AndroidPhoneAuditGeometry.setPageFrame(proxy.frame(in: .global)) : ()
            #endif
            if zoomScale > 1.01 || drawsAnnotations {
                // Skip lets an enclosing vertical scroll view take vertical drags. Inside a
                // (non-scrolling) horizontal scroll container, the page's own drag gesture
                // claims both directions, so a zoomed page pans freely as on iOS.
                ScrollView(.horizontal, showsIndicators: false) {
                    viewport(size: proxy.size)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .scrollDisabled(true)
                .frame(width: proxy.size.width, height: proxy.size.height)
            } else {
                viewport(size: proxy.size)
            }
        }
        .onChange(of: zoomScale) { _, _ in
            guard liveScale == nil else { return }
            clampOffset()
            publishViewport()
        }
        .onChange(of: displayedPageSize) { _, _ in
            updateRasterWidthLimit()
            clampOffset()
            publishViewport()
        }
        .onChange(of: activeNotationAutoScrollRevision) { _, revision in
            scrollToActiveNotation(revision: revision)
        }
        .onChange(of: playbackHighlight) { _, _ in
            followPlayback()
        }
        .onChange(of: isRasterVisible) { _, visible in
            #if ARIA_PHONE_AUDIT
            tracePage("page_visibility")
            #endif
            if visible { clampOffset(); publishViewport() }
            else { releaseRasterState() }
        }
        #if ARIA_PHONE_AUDIT
        .onAppear { tracePage("page_appear") }
        #endif
        .onDisappear {
            #if ARIA_PHONE_AUDIT
            tracePage("page_disappear")
            #endif
            releaseRasterState()
        }
        .task(id: PageKey(data: pdfData ?? imageData, width: pageSize.width, scale: rasterScale, visible: isRasterVisible)) {
            pageRasterGeneration &+= 1
            let generation = pageRasterGeneration
            #if ARIA_PHONE_AUDIT
            tracePage("page_task_start")
            #endif
            guard isRasterVisible else { pageImage = nil; pageImageScale = 0; return }
            #if ARIA_PHONE_AUDIT
            let visualToken = AndroidPhoneAuditLog.visualToken("note")
            #endif
            let target = rasterScale
            let density = UIScreen.main.scale
            let pixels = CGSize(width: (pageSize.width * target * density).rounded(),
                                height: (pageSize.height * target * density).rounded())
            await AndroidPageRasterScheduler.shared.render(owner: pageRasterOwner,
                pdf: pdfData, image: imageData, pixels: pixels) { image in
                guard pageRasterGeneration == generation, let image else { return }
                #if ARIA_PHONE_AUDIT
                AndroidPhoneAuditGeometry.registerVisual(image, kind: "note", token: visualToken)
                #endif

                #if os(Android) && ARIA_PHONE_AUDIT
                AndroidInteractionTrace.point("page_bitmap_assign_begin")
                #endif
                pageImage = image; pageImageScale = target
                #if os(Android) && ARIA_PHONE_AUDIT
                AndroidInteractionTrace.point("page_bitmap_assign_end")
                #endif

                #if ARIA_PHONE_AUDIT
                tracePage("page_image_published")
                #endif
                #if os(Android) && ARIA_PHONE_AUDIT
                AndroidPhoneAuditLog.mark("bitmap_published", value: generation)
                #endif
            }
        }
        .task(id: PageKey(data: selection?.overlayPDFData ?? selection?.overlayImageData, width: pageSize.width, scale: rasterScale, visible: isRasterVisible)) {

            #if os(Android) && ARIA_PHONE_AUDIT
            AndroidInteractionTrace.point("selection_task_enter")
            #endif
            selectionRasterGeneration &+= 1
            guard isRasterVisible else { selectionImage = nil; return }
            await updateSelectionImage(scale: rasterScale, generation: selectionRasterGeneration)
        }
        .task(id: PageKey(data: noteEntryPreview?.overlayImageData, width: pageSize.width, scale: 1, visible: isRasterVisible)) {
            previewImage = isRasterVisible ? noteEntryPreview.flatMap { UIImage(data: $0.overlayImageData) } : nil
        }

    #if os(Android) && ARIA_PHONE_AUDIT
    let _ = AndroidInteractionTrace.point("evaluate_page_end")
    #endif
    }

    @ViewBuilder
    private func viewport(size viewSize: CGSize) -> some View {
        let zoomed = zoomedPageSize
        let origin = contentOrigin
        ZStack(alignment: .topLeading) {
            // Placed by its centre: Compose centres a child larger than its parent,
            // so a top-leading offset would land elsewhere.
            pageContent(size: zoomed)
                .frame(width: zoomed.width, height: zoomed.height)
                .position(x: origin.x + zoomed.width / 2, y: origin.y + zoomed.height / 2)
        }
        .frame(width: viewSize.width, height: viewSize.height, alignment: .topLeading)
        .clipped()
        .contentShape(Rectangle())
        #if os(Android)
        .androidPageGestures(editing: allowsEditingInteractions,
            readingHold: scale <= 1.01 && !allowsEditingInteractions && !annotationModeActive,
            annotating: drawsAnnotations, canPan: canPan, event: pageGestureEvent)
        #endif
        .onAppear { updateBounds(viewSize) }
        .onChange(of: viewSize) { _, size in updateBounds(size) }
    }

    // MARK: Drawing

    @ViewBuilder
    private func pageContent(size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Color.white
            if let pageImage {
                Image(uiImage: pageImage)
                    .resizable()
                    .frame(width: size.width, height: size.height)
                    #if ARIA_PHONE_AUDIT
                    .background(AndroidPhoneAuditVisualProbe(image: pageImage, kind: "note"))
                    #endif
            }
            if showsLayoutMarkers {
                ForEach(Array(layoutMarkers.enumerated()), id: \.offset) { _, marker in
                    AndroidPageRect(rect: marker.normalizedRect, pageSize: size, padding: 1) {
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color(red: 0.0, green: 0.396, blue: 0.749).opacity(0.55), lineWidth: 1)
                    }
                }
            }
            AndroidPlaybackHighlightOverlay(fallback: playbackHighlight, pageSize: size)
            selectionLayer(size: size)
            chordAttachmentGuide(size: size)
            expressionEndpointHandles(size: size)
            if let noteEntryPreview, let previewImage {
                AndroidPageRect(rect: noteEntryPreview.overlayNormalizedRect, pageSize: size) {
                    Image(uiImage: previewImage).resizable()
                }
            }
            AndroidScoreAnnotationLayer(
                strokes: annotationStrokes,
                selectedStrokeIDs: selectedAnnotationStrokeIDs,
                isVisible: annotationsVisible,
                pageSize: size,
                previewTool: annotationPreviewTool,
                previewColor: annotationColor.rgba,
                previewWidth: annotationTool.lineWidth(forPaletteWidth: annotationWidth),
                previewPoints: annotationPreviewPoints,
                selectionTranslation: annotationSelectionTranslation
            )
        }
        .shadow(color: showsPageBoundary ? Color.black.opacity(0.15) : Color.clear,
                radius: showsPageBoundary ? 12 : 0, y: showsPageBoundary ? 6 : 0)
    }

    @ViewBuilder
    private func selectionLayer(size: CGSize) -> some View {
        selectionShapes(size: size)
            .offset(x: selectionDragOffset.width, y: selectionDragOffset.height)
    }

    @ViewBuilder
    private func selectionShapes(size: CGSize) -> some View {
        if let selection {
            if selection.overlayPDFData != nil, let selectionImage, let crop = selectionCrop {
                // The engine's overlay is the whole page with the selected shapes recoloured;
                // only the part around the selection is drawn.
                AndroidPageRect(rect: crop, pageSize: size) {
                    Image(uiImage: selectionImage).resizable()
                        #if ARIA_PHONE_AUDIT
                        .background(AndroidPhoneAuditVisualProbe(image: selectionImage, kind: "selection"))
                        #endif
                }
            } else if let overlayRect = selection.overlayNormalizedRect, let selectionImage {
                AndroidPageRect(rect: overlayRect, pageSize: size) {
                    Image(uiImage: selectionImage).resizable()
                        #if ARIA_PHONE_AUDIT
                        .background(AndroidPhoneAuditVisualProbe(image: selectionImage, kind: "selection"))
                        #endif
                }
            } else if selection.overlayPDFData == nil {
                let rects = selection.highlightRects.isEmpty ? [selection.normalizedRect] : selection.highlightRects
                let blue = Color(red: 0.0, green: 0.396, blue: 0.749)
                ForEach(Array(rects.enumerated()), id: \.offset) { _, rect in
                    AndroidPageRect(rect: rect, pageSize: size, padding: 2) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(blue.opacity(0.18))
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(blue, lineWidth: 2))
                    }
                }
            }
        }
    }

    /// While a chord symbol or fermata is dragged: a dashed line from it to the note it will
    /// attach to (iOS: updateChordAttachmentGuide in ZoomableImageView.swift).
    @ViewBuilder
    private func chordAttachmentGuide(size: CGSize) -> some View {
        if case .movableElement = dragMode, let selection,
           selection.kind == .chordText || (selection.kind == .other && !selection.attachmentTargets.isEmpty),
           let guide = chordAttachmentGuidePoints(selection: selection, size: size) {
            guidePath(from: guide.from, to: guide.to)
            .stroke(Color(red: 0.0, green: 0.396, blue: 0.749).opacity(0.82),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [4, 4]))
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(false)
        }
    }

    // MARK: Slur and hairpin ends

    private var expressionHandleSide: CGFloat {
        UIDevice.current.userInterfaceIdiom == .phone ? 12 : 14
    }

    private var expressionHandleHitSlop: CGFloat {
        UIDevice.current.userInterfaceIdiom == .phone ? 10 : 14
    }

    private func expressionHandlePoints(selection: ScoreSelectedElement) -> (start: CGPoint, end: CGPoint)? {
        guard selection.kind == .expressionSpanner,
              let start = selection.startHandlePoint, let end = selection.endHandlePoint else { return nil }
        let zoomed = zoomedPageSize
        return (CGPoint(x: start.x * zoomed.width, y: start.y * zoomed.height),
                CGPoint(x: end.x * zoomed.width, y: end.y * zoomed.height))
    }

    /// Which end of the selected slur or hairpin a drag starting at `pagePoint` takes.
    private func expressionEndpoint(at pagePoint: CGPoint, selection: ScoreSelectedElement) -> Bool? {
        guard let handles = expressionHandlePoints(selection: selection) else { return nil }
        let reach = expressionHandleSide * 0.5 + expressionHandleHitSlop
        let startDistance = hypot(pagePoint.x - handles.start.x, pagePoint.y - handles.start.y)
        let endDistance = hypot(pagePoint.x - handles.end.x, pagePoint.y - handles.end.y)
        guard min(startDistance, endDistance) <= reach else { return nil }
        return startDistance <= endDistance
    }

    /// The note a dragged end will attach to: the nearest system first (a system's targets
    /// share a height), then the nearest note across (iOS: snappedExpressionEndpointTarget).
    private func snappedExpressionEndpointTarget(near pagePoint: CGPoint) -> CGPoint? {
        guard let selection, selection.kind == .expressionSpanner, !selection.attachmentTargets.isEmpty else { return nil }
        let zoomed = zoomedPageSize
        let targets = selection.attachmentTargets.map { CGPoint(x: $0.x * zoomed.width, y: $0.y * zoomed.height) }
        guard let systemY = targets.min(by: { abs($0.y - pagePoint.y) < abs($1.y - pagePoint.y) })?.y else { return nil }
        return targets
            .filter { abs($0.y - systemY) < 0.5 }
            .min { abs($0.x - pagePoint.x) < abs($1.x - pagePoint.x) }
    }

    /// The selected slur or hairpin's end handles, and while one is dragged, a dashed line
    /// to the note it will attach to.
    @ViewBuilder
    private func expressionEndpointHandles(size: CGSize) -> some View {
        if let selection, let handles = expressionHandlePoints(selection: selection) {
            let draggedIsStart: Bool? = {
                if case .expressionEndpoint(let isStart) = dragMode { return isStart }
                return nil
            }()
            let preview = draggedIsStart == nil ? nil : expressionEndpointPreview
            if let preview, let target = snappedExpressionEndpointTarget(near: preview) {
                guidePath(from: preview, to: target)
                    .stroke(Color(red: 0.0, green: 0.396, blue: 0.749).opacity(0.82),
                            style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [4, 4]))
                    .frame(width: size.width, height: size.height)
                    .allowsHitTesting(false)
            }
            expressionHandle(at: draggedIsStart == true ? (preview ?? handles.start) : handles.start)
            expressionHandle(at: draggedIsStart == false ? (preview ?? handles.end) : handles.end)
        }
    }

    private func expressionHandle(at point: CGPoint) -> some View {
        Circle()
            .fill(Color(red: 0.0, green: 0.396, blue: 0.749))
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .shadow(color: Color.black.opacity(0.22), radius: 2, y: 1)
            .frame(width: expressionHandleSide, height: expressionHandleSide)
            .offset(x: point.x - expressionHandleSide * 0.5, y: point.y - expressionHandleSide * 0.5)
            .allowsHitTesting(false)
    }

    private func guidePath(from: CGPoint, to: CGPoint) -> Path {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        return path
    }

    private func chordAttachmentGuidePoints(selection: ScoreSelectedElement, size: CGSize) -> (from: CGPoint, to: CGPoint)? {
        let rect = selection.normalizedRect
        let moved = CGRect(x: rect.x * size.width + selectionDragOffset.width,
                           y: rect.y * size.height + selectionDragOffset.height,
                           width: rect.width * size.width, height: rect.height * size.height)
        let center = CGPoint(x: moved.midX, y: moved.midY)
        let targets = selection.attachmentTargets.isEmpty
            ? (selection.attachmentPoint.map { [$0] } ?? [])
            : selection.attachmentTargets
        // iOS's snap distance: horizontal distance counts, vertical distance much less.
        let anchor = targets
            .map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
            .min { hypot($0.x - center.x, ($0.y - center.y) * 0.12) < hypot($1.x - center.x, ($1.y - center.y) * 0.12) }
        guard let anchor else { return nil }
        // From the edge facing the note: the bottom above the staff, the top below it.
        let from = anchor.y >= center.y
            ? CGPoint(x: moved.midX, y: moved.maxY + 2)
            : CGPoint(x: moved.midX, y: moved.minY - 2)
        return (from, anchor)
    }

    /// The selection with room for stems, ledger lines and accidentals, within the page.
    private var selectionCrop: ScoreNormalizedRect? {
        guard let selection else { return nil }
        var minX = selection.normalizedRect.x
        var minY = selection.normalizedRect.y
        var maxX = selection.normalizedRect.x + selection.normalizedRect.width
        var maxY = selection.normalizedRect.y + selection.normalizedRect.height
        for rect in selection.highlightRects {
            minX = min(minX, rect.x)
            minY = min(minY, rect.y)
            maxX = max(maxX, rect.x + rect.width)
            maxY = max(maxY, rect.y + rect.height)
        }
        let padX = max((maxX - minX) * 0.5, 0.04)
        let padY = max((maxY - minY) * 0.5, 0.03)
        let x = max(0, minX - padX)
        let y = max(0, minY - padY)
        return ScoreNormalizedRect(x: x, y: y, width: min(1, maxX + padX) - x, height: min(1, maxY + padY) - y)
    }

    private var annotationIsMovingSelection: Bool {
        if case .annotation(true) = dragMode { return true }
        return false
    }

    private var annotationPreviewTool: ScoreAnnotationTool? {
        guard case .annotation = dragMode, !annotationIsMovingSelection else { return nil }
        return annotationTool
    }

    private var annotationPreviewPoints: [CGPoint] {
        annotationIsMovingSelection ? [] : annotationPoints
    }

    private var annotationSelectionTranslation: CGPoint {
        guard annotationIsMovingSelection, let start = annotationMoveStart, let last = annotationPoints.last else { return .zero }
        return CGPoint(x: last.x - start.x, y: last.y - start.y)
    }

    // MARK: Geometry (UIScrollView's, with the shared ScoreReaderZoomLayout)

    private var contentInset: UIEdgeInsets {
        var inset = ScoreReaderZoomLayout.contentInsets(
            viewportSize: boundsSize,
            pageSize: pageSize,
            zoomScale: scale,
            horizontalAlignment: pageHorizontalAlignment,
            centersVertically: centersPageVertically,
            restingHorizontalEdgePadding: restingHorizontalEdgePadding,
            restingTopInset: restingTopInset
        )
        // Room to lift the active bar above the bottom panel, as on iOS.
        if usesActiveNotationFocus {
            inset.bottom += activeNotationBottomInset
        }
        return inset
    }

    private var contentOrigin: CGPoint {
        CGPoint(x: -contentOffset.x, y: -contentOffset.y)
    }

    private func clamped(_ offset: CGPoint) -> CGPoint {
        ScoreReaderZoomLayout.clampedContentOffset(offset, contentSize: zoomedPageSize,
                                                   viewportSize: boundsSize, contentInset: contentInset)
    }

    private func clampOffset() {
        contentOffset = clamped(contentOffset)
    }

    private func updateBounds(_ size: CGSize) {
        guard size != boundsSize else { return }
        boundsSize = size
        updateRasterWidthLimit()
        if !hasPlacedInitialOffset, size.width > 0 {
            hasPlacedInitialOffset = true
            // Top of the page, horizontally where the insets put it (the score starts at
            // the left when zoomed in).
            contentOffset = clamped(CGPoint(x: -.greatestFiniteMagnitude, y: -.greatestFiniteMagnitude))
        } else {
            clampOffset()
        }
        publishViewport()
    }

    private func updateRasterWidthLimit() {
        // Full-page raster, not tiles: bound it to three physical screen areas.
        // Normal fit/phone edit resolutions remain sharp; extreme zoom upsamples
        // rather than keeping a 4K full-page bitmap for a small visible viewport.
        let density = UIScreen.main.scale
        let screen = UIScreen.main.bounds
        let screenWidth = max(screen.width * density, 1)
        let screenHeight = max(screen.height * density, 1)
        let aspect = max(pageSize.height / pageSize.width, 0.01)
        rasterWidthLimit = min(4096, max(screenWidth, sqrt(3 * screenWidth * screenHeight / aspect)))
    }

    private func publishViewport() {
        guard isRasterVisible else { return }
        let viewport = ScoreReaderZoomViewport(zoomScale: scale, contentOrigin: contentOrigin,
                                               contentSize: pageSize, boundsSize: boundsSize)
        #if os(Android) && ARIA_PHONE_AUDIT
        if AndroidPhoneAuditGeometry.viewport != viewport { AndroidPhoneAuditGeometry.viewportChanges += 1 }
        AndroidPhoneAuditGeometry.viewport = viewport
        #endif
        viewportPublisher.request(viewport, binding: $zoomViewport)
    }

    private func releaseRasterState() {
        #if ARIA_PHONE_AUDIT
        tracePage("page_release")
        #endif
        pageRasterGeneration &+= 1
        selectionRasterGeneration &+= 1
        pageImage = nil; pageImageScale = 0
        selectionImage = nil; previewImage = nil
        #if ARIA_PHONE_AUDIT
        AndroidPhoneAuditGeometry.clearSelectionRaster(owner: selectionRasterOwner)
        #endif
        viewportPublisher.cancel()
    }

    #if ARIA_PHONE_AUDIT
    private func tracePage(_ event: String) {
        AndroidPhoneAuditGeometry.pageTrace(event, owner: pageRasterOwner, generation: pageRasterGeneration,
            pdf: pdfData, image: imageData, size: pageSize, bounds: boundsSize,
            scale: rasterScale, visible: isRasterVisible, selected: selection != nil)
    }
    #endif

    /// A point in this view as a normalized page point, as iOS's overlay reports taps.
    private func normalizedPoint(at location: CGPoint, clampedToPage: Bool = false) -> CGPoint? {
        let zoomed = zoomedPageSize
        var x = (location.x - contentOrigin.x) / zoomed.width
        var y = (location.y - contentOrigin.y) / zoomed.height
        if clampedToPage {
            x = min(max(x, 0), 1)
            y = min(max(y, 0), 1)
        }
        guard (0...1).contains(x), (0...1).contains(y) else { return nil }
        return CGPoint(x: x, y: y)
    }

    private func frame(for rect: ScoreNormalizedRect) -> CGRect {
        let zoomed = zoomedPageSize
        return CGRect(x: rect.x * zoomed.width, y: rect.y * zoomed.height,
                      width: rect.width * zoomed.width, height: rect.height * zoomed.height)
    }

    private func setOffset(_ offset: CGPoint, animated: Bool) {
        let target = clamped(offset)
        guard hypot(target.x - contentOffset.x, target.y - contentOffset.y) > 1 else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.25)) { contentOffset = target }
        } else {
            contentOffset = target
        }
        publishViewport()
    }

    // MARK: Following

    private var activeNotationFrame: CGRect? {
        if let noteEntryPreview {
            return frame(for: noteEntryPreview.overlayNormalizedRect).insetBy(dx: -18, dy: -18)
        }
        if let selection,
           selection.kind == .note || selection.kind == .rest || selection.kind == .measure || selection.canDragMovableElement {
            return frame(for: selection.normalizedRect).insetBy(dx: -22, dy: -22)
        }
        return nil
    }

    private func scrollToActiveNotation(revision: Int) {
        guard revision > lastActiveNotationRevision, liveScale == nil, let target = activeNotationFrame else { return }
        lastActiveNotationRevision = revision
        let visibleHeight = activeNotationViewportHeight > 0 ? min(boundsSize.height, activeNotationViewportHeight) : boundsSize.height
        let desiredY: CGFloat
        if usesActiveNotationFocus {
            let usable = max(visibleHeight - activeNotationTopInset - activeNotationBottomInset, 80)
            desiredY = activeNotationTopInset + usable * 0.5
        } else {
            desiredY = visibleHeight * 0.38
        }
        let safeBottomY = max(activeNotationTopInset + 80, visibleHeight - activeNotationBottomInset - 36)
        setOffset(CGPoint(x: target.midX - boundsSize.width * 0.5,
                          y: max(target.midY - desiredY, target.maxY - safeBottomY)), animated: true)
    }

    private func followPlayback() {
        guard scale > 1.01, allowsPlaybackFollow, liveScale == nil, panStartOffset == nil,
              let playbackHighlight, playbackHighlight.normalizedRect != lastPlaybackRect else { return }
        lastPlaybackRect = playbackHighlight.normalizedRect
        let target = frame(for: playbackHighlight.normalizedRect)
        let visible = CGRect(origin: contentOffset, size: boundsSize)
        let safe = visible.insetBy(dx: min(visible.width * 0.16, 84), dy: min(visible.height * 0.18, 110))
        guard !safe.contains(CGPoint(x: target.midX, y: target.midY)) else { return }
        setOffset(CGPoint(x: target.midX - boundsSize.width * 0.5, y: target.midY - boundsSize.height * 0.42), animated: true)
    }

    // MARK: Gestures

    private var canPan: Bool {
        scale > 1.01 || usesActiveNotationFocus || zoomedPageSize.height > boundsSize.height + 1
    }

    /// Where a drag moves the selection, in view space: the selected note or element (and a
    /// slur's or hairpin's end handles), or a selected measure's edges. At zoom 1 the reader's
    /// vertical page scroll view takes vertical drags before the page's own gesture sees
    /// them, so these areas carry their own drag, which claims the touch at once. Drags
    /// elsewhere still scroll the pages.
    private var selectionDragRects: [CGRect] {
        guard allowsEditingInteractions, !annotationModeActive, !drawsAnnotations, let selection else { return [] }
        let origin = contentOrigin
        let frame = frame(for: selection.normalizedRect).offsetBy(dx: origin.x, dy: origin.y)
        switch selection.kind {
        case .measure:
            let edgeBand = min(max(frame.width * 0.18, 18), 44)
            let band = frame.insetBy(dx: -12, dy: -12)
            return [CGRect(x: band.minX, y: band.minY, width: edgeBand + 12, height: band.height),
                    CGRect(x: band.maxX - edgeBand - 12, y: band.minY, width: edgeBand + 12, height: band.height)]
        case .note:
            // In note input the selected note is the one just entered, under the finger that
            // will scroll next: drag it only after a hold, so a quick swipe scrolls.
            return noteInputActive ? [] : [frame.insetBy(dx: -18, dy: -18)]
        default:
            var rects: [CGRect] = []
            if selection.canDragMovableElement {
                rects.append(frame.insetBy(dx: -18, dy: -18))
            }
            if let handles = expressionHandlePoints(selection: selection) {
                let reach = expressionHandleSide * 0.5 + expressionHandleHitSlop
                for point in [handles.start, handles.end] {
                    rects.append(CGRect(x: point.x + origin.x - reach, y: point.y + origin.y - reach,
                                        width: reach * 2, height: reach * 2))
                }
            }
            return rects
        }
    }

    private func dragChanged(location: CGPoint, startLocation: CGPoint, translation: CGSize) {
        guard liveScale == nil else { return }
        let mode = dragMode ?? beginDrag(at: startLocation)
        if dragMode == nil {
            dragMode = mode
        }
        switch mode {
        case .pan(let start):
            contentOffset = clamped(CGPoint(x: start.x - translation.width,
                                            y: start.y - translation.height))
            publishViewport()
        case .selectedNote, .movableElement:
            selectionDragOffset = translation
        case .expressionEndpoint:
            expressionEndpointPreview = CGPoint(x: location.x - contentOrigin.x,
                                                y: location.y - contentOrigin.y)
        case .measureRange(let start, let anchor):
            if let from = measureRangeStartPoint(start: start, anchor: anchor, current: location),
               let to = normalizedPoint(at: location) {
                onMeasureRangePreview?(from, to)
            }
        case .annotation:
            if let point = normalizedPoint(at: location, clampedToPage: true) {
                if let last = annotationPoints.last,
                   hypot((last.x - point.x) * zoomedPageSize.width, (last.y - point.y) * zoomedPageSize.height) < 0.35 {
                    break
                }
                annotationPoints.append(point)
                if annotationTool == .eraser {
                    // Erase as the finger moves (iOS erases when it lifts).
                    onAnnotationErase?(Array(annotationPoints.suffix(2)))
                }
            }
        case .swipe:
            break
        }
    }

    private func dragEnded(location: CGPoint, translation: CGSize) {
        let mode = dragMode
        dragMode = nil
        selectionDragOffset = .zero
        switch mode {
        case .selectedNote(let start), .movableElement(let start):
            guard let selection else { return }
            // The selection's centre, moved by the drag, as iOS's drop point.
            let frame = frame(for: selection.normalizedRect)
            let dropCenter = CGPoint(x: frame.midX + location.x - start.x + contentOrigin.x,
                                     y: frame.midY + location.y - start.y + contentOrigin.y)
            guard let dropPoint = normalizedPoint(at: dropCenter) else { return }
            if case .selectedNote = mode {
                onSelectedNoteDrag?(dropPoint)
            } else {
                onSelectedMovableElementDrag?(dropPoint)
            }
        case .expressionEndpoint(let isStart):
            expressionEndpointPreview = nil
            let pagePoint = CGPoint(x: location.x - contentOrigin.x, y: location.y - contentOrigin.y)
            // Exactly the note the guide showed, as on iOS.
            let target = snappedExpressionEndpointTarget(near: pagePoint) ?? pagePoint
            if let dropPoint = normalizedPoint(at: CGPoint(x: target.x + contentOrigin.x, y: target.y + contentOrigin.y)) {
                onExpressionEndpointDrag?(isStart, dropPoint)
            }
        case .measureRange(let start, let anchor):
            if let from = measureRangeStartPoint(start: start, anchor: anchor, current: location),
               let to = normalizedPoint(at: location) {
                #if os(Android)
                AndroidPageGestureTrace.record("range drop from=\(from) to=\(to)")
                #endif
                onMeasureRangeDrag?(from, to)
            } else {
                onMeasureRangePreviewEnd?()
            }
        case .swipe:
            // Reading at rest: a horizontal swipe turns the page, as on iOS.
            let dx = translation.width
            guard abs(dx) > 40, abs(dx) > abs(translation.height) * 1.5 else { return }
            if dx < 0 {
                onSwipeNextPage?()
            } else {
                onSwipePreviousPage?()
            }
        case .annotation(let movesSelection):
            let points = annotationPoints
            annotationPoints = []
            let moveStart = annotationMoveStart
            annotationMoveStart = nil
            guard let first = points.first, let last = points.last else { return }
            switch annotationTool {
            case .lasso:
                if movesSelection, let moveStart {
                    onAnnotationMoveSelection?(CGPoint(x: last.x - moveStart.x, y: last.y - moveStart.y))
                } else {
                    onAnnotationLasso?(CGRect(x: min(first.x, last.x), y: min(first.y, last.y),
                                              width: abs(last.x - first.x), height: abs(last.y - first.y)))
                }
            case .eraser:
                // The moves erased as they came; a tap erases its point. An empty call
                // ends the gesture (its erases share one undo step).
                if points.count == 1 {
                    onAnnotationErase?(points)
                }
                onAnnotationErase?([])
            case .pen, .highlighter:
                onAnnotationStrokeCommit?(points)
            }
        case .pan, nil:
            break
        }
    }

    private func beginDrag(at location: CGPoint, held: Bool = false) -> DragMode {
        let pagePoint = CGPoint(x: location.x - contentOrigin.x, y: location.y - contentOrigin.y)
        if drawsAnnotations {
            onAnnotationInteractionStart?()
            let start = normalizedPoint(at: location, clampedToPage: true)
            annotationPoints = start.map { [$0] } ?? []
            annotationMoveStart = start
            // With the lasso, a drag that starts on the selection moves it.
            if annotationTool == .lasso,
               let bounds = AndroidScoreAnnotationLayer.selectionBounds(strokes: annotationStrokes, selected: selectedAnnotationStrokeIDs,
                                                                         pageSize: zoomedPageSize),
               bounds.insetBy(dx: -14, dy: -14).contains(pagePoint) {
                return .annotation(movesSelection: true)
            }
            return .annotation(movesSelection: false)
        }
        if allowsEditingInteractions, !annotationModeActive, let selection {
            if let isStart = expressionEndpoint(at: pagePoint, selection: selection) {
                return .expressionEndpoint(isStart: isStart)
            }
            let frame = frame(for: selection.normalizedRect)
            if selection.kind == .note, held || !noteInputActive, frame.insetBy(dx: -18, dy: -18).contains(pagePoint) {
                return .selectedNote(start: location)
            }
            if selection.canDragMovableElement, frame.insetBy(dx: -18, dy: -18).contains(pagePoint) {
                return .movableElement(start: location)
            }
            if selection.kind == .measure, frame.insetBy(dx: -12, dy: -12).contains(pagePoint) {
                let edgeBand = min(max(frame.width * 0.18, 18), 44)
                if pagePoint.x <= frame.minX + edgeBand || pagePoint.x >= frame.maxX - edgeBand {
                    return .measureRange(start: location, anchor: frame)
                }
            }
        }
        if held, allowsEditingInteractions, !annotationModeActive {
            let anchor: CGRect? = selection.flatMap {
                let rect = frame(for: $0.normalizedRect)
                return $0.kind == .measure && rect.insetBy(dx: -12, dy: -12).contains(pagePoint) ? rect : nil
            }
            return .measureRange(start: location, anchor: anchor)
        }
        if canPan {
            onManualScroll?()
            return .pan(start: contentOffset)
        }
        return .swipe
    }

    /// iOS's anchor rule: start just inside the selected measure, on the side away from
    /// the drag, since its edge is shared with the neighbouring measure.
    private func measureRangeStartPoint(start: CGPoint, anchor: CGRect?, current: CGPoint) -> CGPoint? {
        guard let anchor else { return normalizedPoint(at: start) }
        let currentPage = CGPoint(x: current.x - contentOrigin.x, y: current.y - contentOrigin.y)
        let startPage = CGPoint(x: start.x - contentOrigin.x, y: start.y - contentOrigin.y)
        let inset = min(2, anchor.width / 4)
        let anchorX = currentPage.x >= anchor.midX ? anchor.minX + inset : anchor.maxX - inset
        return normalizedPoint(at: CGPoint(x: anchorX + contentOrigin.x, y: startPage.y + contentOrigin.y))
    }

    /// A single native detector reports viewport-local coordinates. A held drag is
    /// distinct from pan; cancellation discards previews without changing the score.
    private func pageGestureEvent(_ event: Int32, _ x: Double, _ y: Double, _ a: Double, _ b: Double) -> Int32 {
        let point = CGPoint(x: x, y: y)
        switch event {
        case 0:
            if let normalized = normalizedPoint(at: point) { onTap?(normalized, .direct) }
        case 1:
            gestureStart = point
            dragMode = beginDrag(at: point, held: a != 0)
            return dragModeCode
        case 2:
            #if os(Android) && ARIA_PHONE_AUDIT
            if dragModeCode == 1 { AndroidPhoneAuditGeometry.panMoves += 1 }
            #endif
            dragChanged(location: point, startLocation: gestureStart,
                translation: CGSize(width: point.x - gestureStart.x, height: point.y - gestureStart.y))
            // How far a pan has gone past the page's top or bottom, in hundredths of a point.
            // AriaPageGestures hands it to the page list, so a zoomed page scrolls on to the
            // next page as on iOS, where the page's scroll view passes it on.
            if case .some(.pan(let start)) = dragMode {
                let wantedY = start.y - (point.y - gestureStart.y)
                return Int32(((wantedY - contentOffset.y) * 100).rounded())
            }
        case 3:
            let code = dragModeCode
            dragEnded(location: point,
                translation: CGSize(width: point.x - gestureStart.x, height: point.y - gestureStart.y))
            return code
        case 4:
            cancelPageGesture()
        case 5:
            guard let normalized = normalizedPoint(at: point) else { return 0 }
            readingDragStart = normalized
            onReadingLongPress?(normalized, normalized)
        case 6, 7:
            if let start = readingDragStart, let normalized = normalizedPoint(at: point) {
                onReadingLongPress?(start, normalized)
            }
            if event == 7 { readingDragStart = nil }
        case 8:
            pinchStart = (scale, contentOffset, point)
        case 9:
            guard let start = pinchStart else { return 0 }
            let newScale = min(max(start.scale * a, ScoreReaderZoomLimits.minimumScale), Self.maximumScale)
            let pagePoint = CGPoint(x: (start.location.x + start.offset.x) / start.scale,
                                    y: (start.location.y + start.offset.y) / start.scale)
            liveScale = newScale
            contentOffset = clamped(CGPoint(x: pagePoint.x * newScale - start.location.x,
                                            y: pagePoint.y * newScale - start.location.y))
            publishViewport()
        case 10:
            let finalScale = scale
            pinchStart = nil
            liveScale = nil
            if abs(zoomScale - finalScale) > 0.01 { zoomScale = finalScale }
            clampOffset()
            publishViewport()
        case 12:
            return selectionDragRects.contains(where: { $0.contains(point) }) ? 1 : 0
        default: break
        }
        return 0
    }

    private var dragModeCode: Int32 {
        switch dragMode {
        case .pan: return 1
        case .selectedNote: return 2
        case .movableElement: return 3
        case .expressionEndpoint: return 4
        case .measureRange: return 5
        case .annotation: return 6
        case .swipe: return 7
        case nil: return 0
        }
    }

    private func cancelPageGesture() {
        if case .measureRange = dragMode { onMeasureRangePreviewEnd?() }
        if case .annotation = dragMode, annotationTool == .eraser, !annotationPoints.isEmpty {
            // Erasing is intentionally applied during movement. Close its existing
            // undo group, without erasing another segment, if the stream is cancelled.
            onAnnotationErase?([])
        }
        if readingDragStart != nil { onManualScroll?() }
        dragMode = nil
        readingDragStart = nil
        selectionDragOffset = .zero
        expressionEndpointPreview = nil
        annotationPoints = []
        annotationMoveStart = nil
    }

    // MARK: Images

    /// The page's bitmap resolution: the zoom level, settled after a pinch, capped so a
    /// zoomed page stays within a sensible bitmap size.
    private var rasterScale: CGFloat {
        let settled = liveScale == nil ? scale : pageImageScale
        let maxScale = rasterWidthLimit / max(pageSize.width * UIScreen.main.scale, 1)
        return max(1, min((settled * 2).rounded() / 2, maxScale))
    }

    private func updateSelectionImage(scale: CGFloat, generation: Int) async {
        #if os(Android) && ARIA_PHONE_AUDIT
        AndroidInteractionTrace.point("selection_image_task_begin")
        #endif
        #if os(Android) && ARIA_PHONE_AUDIT
        defer { AndroidInteractionTrace.point("selection_image_task_end") }
        #endif

        guard let selection else { selectionImage = nil; return }
        #if ARIA_PHONE_AUDIT
        let visualToken = AndroidPhoneAuditLog.visualToken("selection")
        #endif
        if let pdfData = selection.overlayPDFData, !pdfData.isEmpty, let crop = selectionCrop {
            let screenScale = UIScreen.main.scale
            let pixelSize = CGSize(width: (pageSize.width * crop.width * scale * screenScale).rounded(),
                                   height: (pageSize.height * crop.height * scale * screenScale).rounded())
            let cropRect = CGRect(x: crop.x, y: crop.y, width: crop.width, height: crop.height)
            await AndroidPageRasterScheduler.shared.render(owner: selectionRasterOwner,
                pdf: pdfData, image: nil, pixels: pixelSize, opaque: false, crop: cropRect) { image in
                if selectionRasterGeneration == generation {

                    #if os(Android) && ARIA_PHONE_AUDIT
                    AndroidInteractionTrace.point("selection_bitmap_assign_begin")
                    #endif
                    selectionImage = image
                    #if os(Android) && ARIA_PHONE_AUDIT
                    AndroidInteractionTrace.point("selection_bitmap_assign_end")
                    #endif

                    #if ARIA_PHONE_AUDIT
                    AndroidPhoneAuditGeometry.registerVisual(image, kind: "selection", token: visualToken)
                    AndroidPhoneAuditGeometry.selectionRaster(owner: selectionRasterOwner, image: image, pdf: pdfData)
                    #endif
                }
            }
            return
        }
        guard selection.overlayNormalizedRect != nil else { selectionImage = nil; return }
        await AndroidPageRasterScheduler.shared.render(owner: selectionRasterOwner,
            pdf: nil, image: selection.overlayImageData, pixels: .zero, opaque: false) { image in
            if selectionRasterGeneration == generation {
                #if ARIA_PHONE_AUDIT
                AndroidPhoneAuditGeometry.registerVisual(image, kind: "selection", token: visualToken)
                #endif
                selectionImage = image
            }
        }
    }

    struct PageKey: Hashable {
        let data: Data?
        let width: CGFloat
        let scale: CGFloat
        let visible: Bool
    }
}

/// Places content over a normalized rectangle of the page.
struct AndroidPageRect<Content: View>: View {
    let rect: ScoreNormalizedRect
    let pageSize: CGSize
    var padding: CGFloat = 0
    @ViewBuilder let content: () -> Content

    var body: some View {
        let width = max(pageSize.width * rect.width + padding * 2, 1)
        let height = max(pageSize.height * rect.height + padding * 2, 1)
        content()
            .frame(width: width, height: height)
            .offset(x: pageSize.width * rect.x - padding, y: pageSize.height * rect.y - padding)
    }
}
