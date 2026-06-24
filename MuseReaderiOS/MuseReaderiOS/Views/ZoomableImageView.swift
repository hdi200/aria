//
//  ZoomableImageView.swift
//  MuseReaderiOS
//
//

import AVFoundation
import QuartzCore
import SwiftUI
import UIKit

enum ScorePageTapInputKind {
    case direct
    case pencil
}

struct ScoreReaderZoomViewport: Equatable {
    var zoomScale: CGFloat = 1
    var contentOrigin: CGPoint = .zero
    var boundsSize: CGSize = .zero

    func project(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: contentOrigin.x + point.x * zoomScale,
            y: contentOrigin.y + point.y * zoomScale
        )
    }

    func project(_ rect: CGRect) -> CGRect {
        CGRect(
            x: contentOrigin.x + rect.minX * zoomScale,
            y: contentOrigin.y + rect.minY * zoomScale,
            width: rect.width * zoomScale,
            height: rect.height * zoomScale
        )
    }
}

struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage?
    let pdfData: Data?
    let contentSize: CGSize
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
    var allowsPencilInsertionFineTune = false
    var noteEntryPreviewPitchClass: Int? = nil
    var noteEntryPreviewIsRest = false
    var noteEntryPreviewDuration: ScoreNoteDuration = .quarter
    var showsLayoutMarkers = false
    var onTap: ((CGPoint, ScorePageTapInputKind) -> Void)? = nil
    var onSelectedNoteDrag: ((CGPoint) -> Void)? = nil
    var onExpressionEndpointDrag: ((Bool, CGPoint) -> Void)? = nil
    var onSelectedChordTextDrag: ((CGPoint) -> Void)? = nil
    var onMeasureRangePreview: ((CGPoint, CGPoint) -> Void)? = nil
    var onMeasureRangePreviewEnd: (() -> Void)? = nil
    var onMeasureRangeDrag: ((CGPoint, CGPoint) -> Void)? = nil
    var onPencilInsertionFineTune: ((CGPoint, CGPoint) -> Void)? = nil
    var onPencilHoverPreview: ((CGPoint?) -> Void)? = nil
    var onPencilInteractionStart: (() -> Void)? = nil
    var onPencilDoubleTap: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(
            zoomScale: $zoomScale,
            zoomViewport: $zoomViewport,
            onTap: onTap,
            onSelectedNoteDrag: onSelectedNoteDrag,
            onExpressionEndpointDrag: onExpressionEndpointDrag,
            onSelectedChordTextDrag: onSelectedChordTextDrag,
            onMeasureRangePreview: onMeasureRangePreview,
            onMeasureRangePreviewEnd: onMeasureRangePreviewEnd,
            onMeasureRangeDrag: onMeasureRangeDrag,
            onPencilInsertionFineTune: onPencilInsertionFineTune,
            onPencilHoverPreview: onPencilHoverPreview,
            onPencilInteractionStart: onPencilInteractionStart,
            onPencilDoubleTap: onPencilDoubleTap
        )
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = ScorePageZoomScrollView()
        scrollView.delegate = context.coordinator
        scrollView.shouldBeginPagePan = { [weak coordinator = context.coordinator] panGestureRecognizer, scrollView in
            coordinator?.shouldBeginPagePan(panGestureRecognizer, in: scrollView) ?? true
        }
        scrollView.minimumZoomScale = 0.8
        scrollView.maximumZoomScale = 6
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never

        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = .clear

        let contentView = ScorePageContentView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.configure(image: image, pdfData: pdfData, contentSize: contentSize)

        let overlayView = ScorePageOverlayView()
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.backgroundColor = .clear

        containerView.addSubview(contentView)
        containerView.addSubview(overlayView)
        scrollView.addSubview(containerView)

        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            containerView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            containerView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            containerView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            containerView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),

            contentView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: containerView.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            overlayView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: containerView.topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        let tapGestureRecognizer = ScorePageTapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tapGestureRecognizer.onPencilInteractionStart = context.coordinator.onPencilInteractionStart
        overlayView.addGestureRecognizer(tapGestureRecognizer)

        let noteDragGestureRecognizer = ScorePageLongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSelectedNoteDrag(_:)))
        noteDragGestureRecognizer.minimumPressDuration = 0.12
        noteDragGestureRecognizer.allowableMovement = 240
        noteDragGestureRecognizer.delegate = context.coordinator
        noteDragGestureRecognizer.onPencilInteractionStart = context.coordinator.onPencilInteractionStart
        overlayView.addGestureRecognizer(noteDragGestureRecognizer)

        let pencilHoverGestureRecognizer = UIHoverGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePencilHover(_:)))
        pencilHoverGestureRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        overlayView.addGestureRecognizer(pencilHoverGestureRecognizer)

        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = context.coordinator
        overlayView.addInteraction(pencilInteraction)

        context.coordinator.zoomView = containerView
        context.coordinator.contentView = contentView
        context.coordinator.overlayView = overlayView
        context.coordinator.tapGestureRecognizer = tapGestureRecognizer
        context.coordinator.noteDragGestureRecognizer = noteDragGestureRecognizer

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onSelectedNoteDrag = onSelectedNoteDrag
        context.coordinator.onExpressionEndpointDrag = onExpressionEndpointDrag
        context.coordinator.onSelectedChordTextDrag = onSelectedChordTextDrag
        context.coordinator.onMeasureRangePreview = onMeasureRangePreview
        context.coordinator.onMeasureRangePreviewEnd = onMeasureRangePreviewEnd
        context.coordinator.onMeasureRangeDrag = onMeasureRangeDrag
        context.coordinator.onPencilInsertionFineTune = onPencilInsertionFineTune
        context.coordinator.onPencilHoverPreview = onPencilHoverPreview
        context.coordinator.onPencilInteractionStart = onPencilInteractionStart
        context.coordinator.tapGestureRecognizer?.onPencilInteractionStart = onPencilInteractionStart
        context.coordinator.noteDragGestureRecognizer?.onPencilInteractionStart = onPencilInteractionStart
        context.coordinator.allowsPencilInsertionFineTune = allowsPencilInsertionFineTune
        context.coordinator.onPencilDoubleTap = onPencilDoubleTap
        context.coordinator.activeNotationAutoScrollRevision = activeNotationAutoScrollRevision
        context.coordinator.activeNotationTopInset = activeNotationTopInset
        context.coordinator.activeNotationBottomInset = activeNotationBottomInset
        context.coordinator.activeNotationViewportHeight = activeNotationViewportHeight
        context.coordinator.zoomScale = $zoomScale
        context.coordinator.zoomViewport = $zoomViewport
        context.coordinator.contentView?.configure(image: image, pdfData: pdfData, contentSize: contentSize)
        context.coordinator.overlayView?.imageSize = contentSize
        context.coordinator.overlayView?.playbackHighlight = playbackHighlight
        context.coordinator.overlayView?.selection = selection
        context.coordinator.overlayView?.noteEntryPreview = noteEntryPreview
        context.coordinator.overlayView?.layoutMarkers = layoutMarkers
        context.coordinator.overlayView?.allowsPencilHoverPreview = allowsPencilInsertionFineTune
        context.coordinator.overlayView?.noteEntryPreviewPitchClass = noteEntryPreviewPitchClass
        context.coordinator.overlayView?.noteEntryPreviewIsRest = noteEntryPreviewIsRest
        context.coordinator.overlayView?.noteEntryPreviewDuration = noteEntryPreviewDuration
        context.coordinator.overlayView?.showsLayoutMarkers = showsLayoutMarkers
        let clampedZoomScale = min(max(zoomScale, scrollView.minimumZoomScale), scrollView.maximumZoomScale)
        let allowsInnerPanning = clampedZoomScale > 1.01
        let usesActiveNotationFocus = context.coordinator.usesActiveNotationFocus

        scrollView.isScrollEnabled = allowsInnerPanning || usesActiveNotationFocus
        if !allowsInnerPanning && !usesActiveNotationFocus {
            scrollView.contentOffset = .zero
        }

        if !context.coordinator.isUserZooming, abs(scrollView.zoomScale - clampedZoomScale) > 0.01 {
            scrollView.setZoomScale(clampedZoomScale, animated: false)
        }
        scrollView.layoutIfNeeded()
        context.coordinator.updateActiveNotationContentInsets(in: scrollView)
        context.coordinator.scrollActiveNotationIntoViewIfNeeded(in: scrollView)
        context.coordinator.publishViewport(from: scrollView)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate, UIPencilInteractionDelegate {
        var zoomScale: Binding<CGFloat>
        var zoomViewport: Binding<ScoreReaderZoomViewport>
        var onTap: ((CGPoint, ScorePageTapInputKind) -> Void)?
        var onSelectedNoteDrag: ((CGPoint) -> Void)?
        var onExpressionEndpointDrag: ((Bool, CGPoint) -> Void)?
        var onSelectedChordTextDrag: ((CGPoint) -> Void)?
        var onMeasureRangePreview: ((CGPoint, CGPoint) -> Void)?
        var onMeasureRangePreviewEnd: (() -> Void)?
        var onMeasureRangeDrag: ((CGPoint, CGPoint) -> Void)?
        var onPencilInsertionFineTune: ((CGPoint, CGPoint) -> Void)?
        var onPencilHoverPreview: ((CGPoint?) -> Void)?
        var onPencilInteractionStart: (() -> Void)?
        var onPencilDoubleTap: (() -> Void)?
        var allowsPencilInsertionFineTune = false
        var activeNotationAutoScrollRevision = 0
        var activeNotationTopInset: CGFloat = 0
        var activeNotationBottomInset: CGFloat = 0
        var activeNotationViewportHeight: CGFloat = 0
        private var lastHandledActiveNotationAutoScrollRevision = 0
        weak var zoomView: UIView?
        weak var contentView: ScorePageContentView?
        weak var overlayView: ScorePageOverlayView?
        weak var tapGestureRecognizer: ScorePageTapGestureRecognizer?
        weak var noteDragGestureRecognizer: ScorePageLongPressGestureRecognizer?
        var isUserZooming = false
        private var selectedNoteDragStartPoint: CGPoint?
        private var selectedChordTextDragStartPoint: CGPoint?
        private var expressionEndpointDragIsStart: Bool?
        private var measureRangeDragStartPoint: CGPoint?
        private var measureRangeDragAnchorFrame: CGRect?
        private var insertionDragStartPoint: CGPoint?
        private var lastPencilHoverPoint: CGPoint?
        private let pencilHoverPreviewMovementThreshold: CGFloat = 4

        init(
            zoomScale: Binding<CGFloat>,
            zoomViewport: Binding<ScoreReaderZoomViewport>,
            onTap: ((CGPoint, ScorePageTapInputKind) -> Void)? = nil,
            onSelectedNoteDrag: ((CGPoint) -> Void)? = nil,
            onExpressionEndpointDrag: ((Bool, CGPoint) -> Void)? = nil,
            onSelectedChordTextDrag: ((CGPoint) -> Void)? = nil,
            onMeasureRangePreview: ((CGPoint, CGPoint) -> Void)? = nil,
            onMeasureRangePreviewEnd: (() -> Void)? = nil,
            onMeasureRangeDrag: ((CGPoint, CGPoint) -> Void)? = nil,
            onPencilInsertionFineTune: ((CGPoint, CGPoint) -> Void)? = nil,
            onPencilHoverPreview: ((CGPoint?) -> Void)? = nil,
            onPencilInteractionStart: (() -> Void)? = nil,
            onPencilDoubleTap: (() -> Void)? = nil
        ) {
            self.zoomScale = zoomScale
            self.zoomViewport = zoomViewport
            self.onTap = onTap
            self.onSelectedNoteDrag = onSelectedNoteDrag
            self.onExpressionEndpointDrag = onExpressionEndpointDrag
            self.onSelectedChordTextDrag = onSelectedChordTextDrag
            self.onMeasureRangePreview = onMeasureRangePreview
            self.onMeasureRangePreviewEnd = onMeasureRangePreviewEnd
            self.onMeasureRangeDrag = onMeasureRangeDrag
            self.onPencilInsertionFineTune = onPencilInsertionFineTune
            self.onPencilHoverPreview = onPencilHoverPreview
            self.onPencilInteractionStart = onPencilInteractionStart
            self.onPencilDoubleTap = onPencilDoubleTap
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            zoomView
        }

        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            isUserZooming = true
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            let allowsInnerPanning = scrollView.zoomScale > 1.01
            scrollView.isScrollEnabled = allowsInnerPanning || usesActiveNotationFocus
            if !allowsInnerPanning && !usesActiveNotationFocus {
                scrollView.contentOffset = .zero
            }
            updateActiveNotationContentInsets(in: scrollView)
            scrollActiveNotationIntoViewIfNeeded(in: scrollView)

            let currentZoomScale = scrollView.zoomScale
            if abs(zoomScale.wrappedValue - currentZoomScale) > 0.01 {
                DispatchQueue.main.async { [zoomScale] in
                    zoomScale.wrappedValue = currentZoomScale
                }
            }
            publishViewport(from: scrollView)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            publishViewport(from: scrollView)
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            isUserZooming = false
            if abs(zoomScale.wrappedValue - scale) > 0.01 {
                zoomScale.wrappedValue = scale
            }
            publishViewport(from: scrollView)
        }

        func publishViewport(from scrollView: UIScrollView) {
            let origin = zoomView.map {
                CGPoint(
                    x: $0.frame.minX - scrollView.contentOffset.x,
                    y: $0.frame.minY - scrollView.contentOffset.y
                )
            } ?? CGPoint(
                x: -scrollView.contentOffset.x,
                y: -scrollView.contentOffset.y
            )
            let nextViewport = ScoreReaderZoomViewport(
                zoomScale: scrollView.zoomScale,
                contentOrigin: origin,
                boundsSize: scrollView.bounds.size
            )
            guard zoomViewport.wrappedValue != nextViewport else {
                return
            }
            DispatchQueue.main.async { [zoomViewport] in
                zoomViewport.wrappedValue = nextViewport
            }
        }

        func updateActiveNotationContentInsets(in scrollView: UIScrollView) {
            // Keep extra scroll room even when zoomed out so programmatic
            // note-entry focus can lift the active bar above the bottom panel.
            let bottomInset = usesActiveNotationFocus ? activeNotationBottomScrollInset(for: scrollView) : 0
            let nextInset = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
            guard scrollView.contentInset != nextInset else {
                return
            }

            scrollView.contentInset = nextInset
            scrollView.scrollIndicatorInsets = nextInset
            clampContentOffsetIfNeeded(in: scrollView, animated: false)
        }

        private func activeNotationBottomScrollInset(for scrollView: UIScrollView) -> CGFloat {
            guard
                usesActiveNotationFocus,
                let targetFrame = overlayView?.activeNotationFrame
            else {
                return 0
            }

            let scale = scrollView.zoomScale
            let scaledTargetFrame = CGRect(
                x: targetFrame.minX * scale,
                y: targetFrame.minY * scale,
                width: targetFrame.width * scale,
                height: targetFrame.height * scale
            )
            let desiredViewportY = activeNotationDesiredViewportY(in: scrollView)
            let centeredTargetOffsetY = scaledTargetFrame.midY - desiredViewportY
            let visibleViewportHeight = activeNotationVisibleViewportHeight(in: scrollView)
            let safeBottomY = max(activeNotationTopInset + 80, visibleViewportHeight - activeNotationBottomInset - 36)
            let bottomProtectedTargetOffsetY = scaledTargetFrame.maxY - safeBottomY
            let targetOffsetY = max(centeredTargetOffsetY, bottomProtectedTargetOffsetY, 0)
            let naturalMaxOffsetY = max(scrollView.contentSize.height - scrollView.bounds.height, 0)
            return max(0, targetOffsetY - naturalMaxOffsetY + 24)
        }

        private func activeNotationVisibleViewportHeight(in scrollView: UIScrollView) -> CGFloat {
            guard activeNotationViewportHeight > 0 else {
                return scrollView.bounds.height
            }

            return min(scrollView.bounds.height, activeNotationViewportHeight)
        }

        private func activeNotationDesiredViewportY(in scrollView: UIScrollView) -> CGFloat {
            guard usesActiveNotationFocus else {
                return activeNotationVisibleViewportHeight(in: scrollView) * 0.38
            }

            // Center the active bar in the area left visible between the top
            // chrome and the bottom keyboard, matching the outer reader scroll.
            let visibleViewportHeight = activeNotationVisibleViewportHeight(in: scrollView)
            let usableHeight = max(visibleViewportHeight - activeNotationTopInset - activeNotationBottomInset, 80)
            return activeNotationTopInset + usableHeight * 0.5
        }

        private func clampContentOffsetIfNeeded(in scrollView: UIScrollView, animated: Bool) {
            let adjustedInset = scrollView.adjustedContentInset
            let minOffset = CGPoint(x: -adjustedInset.left, y: -adjustedInset.top)
            let maxOffset = CGPoint(
                x: max(scrollView.contentSize.width - scrollView.bounds.width + adjustedInset.right, minOffset.x),
                y: max(scrollView.contentSize.height - scrollView.bounds.height + adjustedInset.bottom, minOffset.y)
            )
            let clampedOffset = CGPoint(
                x: min(max(scrollView.contentOffset.x, minOffset.x), maxOffset.x),
                y: min(max(scrollView.contentOffset.y, minOffset.y), maxOffset.y)
            )

            guard hypot(scrollView.contentOffset.x - clampedOffset.x, scrollView.contentOffset.y - clampedOffset.y) > 1 else {
                return
            }
            scrollView.setContentOffset(clampedOffset, animated: animated)
        }

        func scrollActiveNotationIntoViewIfNeeded(in scrollView: UIScrollView) {
            guard
                activeNotationAutoScrollRevision > lastHandledActiveNotationAutoScrollRevision,
                !isUserZooming,
                let overlayView,
                let targetFrame = overlayView.activeNotationFrame
            else {
                return
            }

            scrollView.layoutIfNeeded()
            guard
                scrollView.bounds.width > 0,
                scrollView.bounds.height > 0,
                scrollView.contentSize.width > 0,
                scrollView.contentSize.height > 0
            else {
                return
            }

            let scale = scrollView.zoomScale
            let scaledTargetFrame = CGRect(
                x: targetFrame.minX * scale,
                y: targetFrame.minY * scale,
                width: targetFrame.width * scale,
                height: targetFrame.height * scale
            )
            let desiredViewportY = activeNotationDesiredViewportY(in: scrollView)
            let visibleViewportHeight = activeNotationVisibleViewportHeight(in: scrollView)
            let safeBottomY = max(activeNotationTopInset + 80, visibleViewportHeight - activeNotationBottomInset - 36)
            let centeredTargetOffsetY = scaledTargetFrame.midY - desiredViewportY
            let bottomProtectedTargetOffsetY = scaledTargetFrame.maxY - safeBottomY
            let targetOffset = CGPoint(
                x: scaledTargetFrame.midX - scrollView.bounds.width * 0.5,
                y: max(centeredTargetOffsetY, bottomProtectedTargetOffsetY)
            )
            let adjustedInset = scrollView.adjustedContentInset
            let minOffset = CGPoint(x: -adjustedInset.left, y: -adjustedInset.top)
            let maxOffset = CGPoint(
                x: max(scrollView.contentSize.width - scrollView.bounds.width + adjustedInset.right, minOffset.x),
                y: max(scrollView.contentSize.height - scrollView.bounds.height + adjustedInset.bottom, minOffset.y)
            )
            let clampedOffset = CGPoint(
                x: min(max(targetOffset.x, minOffset.x), maxOffset.x),
                y: min(max(targetOffset.y, minOffset.y), maxOffset.y)
            )
            lastHandledActiveNotationAutoScrollRevision = activeNotationAutoScrollRevision
            guard hypot(scrollView.contentOffset.x - clampedOffset.x, scrollView.contentOffset.y - clampedOffset.y) > 4 else {
                return
            }
            scrollView.setContentOffset(clampedOffset, animated: true)
        }

        var usesActiveNotationFocus: Bool {
            activeNotationTopInset > 0 || activeNotationBottomInset > 0
        }

        @objc
        func handleTap(_ gestureRecognizer: ScorePageTapGestureRecognizer) {
            guard
                let overlayView
            else {
                return
            }

            let pagePoint = gestureRecognizer.pageLocation(in: overlayView)
            guard let normalizedPoint = overlayView.normalizedLayoutMarkerTapPoint(at: pagePoint)
                ?? overlayView.normalizedPoint(at: pagePoint)
            else {
                return
            }

            onTap?(normalizedPoint, gestureRecognizer.inputKind)
        }

        @objc
        func handleSelectedNoteDrag(_ gestureRecognizer: ScorePageLongPressGestureRecognizer) {
            guard let overlayView else {
                return
            }

            let point = gestureRecognizer.pageLocation(in: overlayView)
            switch gestureRecognizer.state {
            case .began:
                let startPoint = gestureRecognizer.initialPageLocation(in: overlayView)
                if gestureRecognizer.inputKind == .pencil {
                    onPencilInteractionStart?()
                }
                if allowsPencilInsertionFineTune && gestureRecognizer.inputKind == .pencil {
                    selectedNoteDragStartPoint = nil
                    selectedChordTextDragStartPoint = nil
                    expressionEndpointDragIsStart = nil
                    measureRangeDragStartPoint = nil
                    measureRangeDragAnchorFrame = nil
                    insertionDragStartPoint = startPoint
                    overlayView.updateInsertionFineTune(at: point)
                    onPencilHoverPreview?(overlayView.normalizedPoint(at: point))
                } else if allowsPencilInsertionFineTune {
                    selectedNoteDragStartPoint = nil
                    selectedChordTextDragStartPoint = nil
                    expressionEndpointDragIsStart = nil
                    measureRangeDragStartPoint = startPoint
                    measureRangeDragAnchorFrame = overlayView.measureRangeDragAnchorFrame(at: startPoint)
                    insertionDragStartPoint = nil
                } else if overlayView.containsSelectedNote(at: point) {
                    selectedNoteDragStartPoint = startPoint
                    selectedChordTextDragStartPoint = nil
                    expressionEndpointDragIsStart = nil
                    measureRangeDragStartPoint = nil
                    measureRangeDragAnchorFrame = nil
                    insertionDragStartPoint = nil
                    overlayView.updateSelectedNoteDrag(startPoint: startPoint, currentPoint: point)
                } else if overlayView.containsSelectedChordText(at: point) {
                    selectedNoteDragStartPoint = nil
                    selectedChordTextDragStartPoint = startPoint
                    expressionEndpointDragIsStart = nil
                    measureRangeDragStartPoint = nil
                    measureRangeDragAnchorFrame = nil
                    insertionDragStartPoint = nil
                    overlayView.updateSelectedChordTextDrag(startPoint: startPoint, currentPoint: point)
                } else if let endpointIsStart = overlayView.expressionEndpoint(at: point) {
                    selectedNoteDragStartPoint = nil
                    selectedChordTextDragStartPoint = nil
                    expressionEndpointDragIsStart = endpointIsStart
                    measureRangeDragStartPoint = nil
                    measureRangeDragAnchorFrame = nil
                    insertionDragStartPoint = nil
                    overlayView.updateExpressionEndpointDragPreview(start: endpointIsStart, at: point)
                } else {
                    selectedNoteDragStartPoint = nil
                    selectedChordTextDragStartPoint = nil
                    expressionEndpointDragIsStart = nil
                    measureRangeDragStartPoint = startPoint
                    measureRangeDragAnchorFrame = overlayView.measureRangeDragAnchorFrame(at: startPoint)
                    insertionDragStartPoint = nil
                }

            case .changed:
                if let selectedNoteDragStartPoint {
                    overlayView.updateSelectedNoteDrag(startPoint: selectedNoteDragStartPoint, currentPoint: point)
                } else if let selectedChordTextDragStartPoint {
                    overlayView.updateSelectedChordTextDrag(startPoint: selectedChordTextDragStartPoint, currentPoint: point)
                } else if let expressionEndpointDragIsStart {
                    overlayView.updateExpressionEndpointDragPreview(start: expressionEndpointDragIsStart, at: point)
                } else if insertionDragStartPoint != nil {
                    overlayView.updateInsertionFineTune(at: point)
                    onPencilHoverPreview?(overlayView.normalizedPoint(at: point))
                } else if let measureRangeDragStartPoint,
                          let startPoint = overlayView.normalizedMeasureRangeDragStartPoint(
                            from: measureRangeDragStartPoint,
                            to: point,
                            anchorFrame: measureRangeDragAnchorFrame
                          ),
                          let endPoint = overlayView.normalizedPoint(at: point) {
                    overlayView.updateMeasureRangeDragPreview(startNormalizedPoint: startPoint, endPoint: point)
                    onMeasureRangePreview?(startPoint, endPoint)
                }

            case .ended:
                if let selectedNoteDragStartPoint {
                    let dropPoint = overlayView.selectedNoteDragDropPoint(startPoint: selectedNoteDragStartPoint, currentPoint: point)
                    self.selectedNoteDragStartPoint = nil
                    overlayView.clearSelectedNoteDrag()
                    if let dropPoint {
                        onSelectedNoteDrag?(dropPoint)
                    }
                } else if let selectedChordTextDragStartPoint {
                    let dropPoint = overlayView.selectedChordTextDragDropPoint(startPoint: selectedChordTextDragStartPoint, currentPoint: point)
                    self.selectedChordTextDragStartPoint = nil
                    overlayView.clearSelectedChordTextDrag()
                    if let dropPoint {
                        onSelectedChordTextDrag?(dropPoint)
                    }
                } else if let expressionEndpointDragIsStart {
                    self.expressionEndpointDragIsStart = nil
                    overlayView.clearExpressionEndpointDragPreview()
                    if let dropPoint = overlayView.normalizedPoint(at: point) {
                        onExpressionEndpointDrag?(expressionEndpointDragIsStart, dropPoint)
                    }
                } else if let insertionDragStartPoint {
                    self.insertionDragStartPoint = nil
                    let startPoint = overlayView.insertionFineTuneDropPoint(at: insertionDragStartPoint)
                    let dropPoint = overlayView.insertionFineTuneDropPoint(at: point)
                    overlayView.clearInsertionFineTune()
                    onPencilHoverPreview?(nil)
                    if let startPoint, let dropPoint {
                        onPencilInsertionFineTune?(startPoint, dropPoint)
                    }
                } else if let measureRangeDragStartPoint {
                    self.measureRangeDragStartPoint = nil
                    let startPoint = overlayView.normalizedMeasureRangeDragStartPoint(
                        from: measureRangeDragStartPoint,
                        to: point,
                        anchorFrame: measureRangeDragAnchorFrame
                    )
                    measureRangeDragAnchorFrame = nil
                    let endPoint = overlayView.normalizedPoint(at: point)
                    if let startPoint, let endPoint {
                        onMeasureRangeDrag?(startPoint, endPoint)
                    } else {
                        onMeasureRangePreviewEnd?()
                    }
                    overlayView.clearMeasureRangeDragPreview()
                }

            case .cancelled, .failed:
                selectedNoteDragStartPoint = nil
                selectedChordTextDragStartPoint = nil
                expressionEndpointDragIsStart = nil
                measureRangeDragStartPoint = nil
                measureRangeDragAnchorFrame = nil
                insertionDragStartPoint = nil
                lastPencilHoverPoint = nil
                overlayView.clearSelectedNoteDrag()
                overlayView.clearSelectedChordTextDrag()
                overlayView.clearExpressionEndpointDragPreview()
                overlayView.clearInsertionFineTune()
                overlayView.clearMeasureRangeDragPreview()
                onMeasureRangePreviewEnd?()
                onPencilHoverPreview?(nil)

            default:
                break
            }
        }

        @objc
        func handlePencilHover(_ gestureRecognizer: UIHoverGestureRecognizer) {
            guard let overlayView else {
                return
            }

            let point = gestureRecognizer.location(in: overlayView)
            switch gestureRecognizer.state {
            case .began, .changed:
                onPencilInteractionStart?()
                if let lastPencilHoverPoint,
                   hypot(point.x - lastPencilHoverPoint.x, point.y - lastPencilHoverPoint.y) < pencilHoverPreviewMovementThreshold {
                    return
                }
                lastPencilHoverPoint = point
                overlayView.updatePencilHoverPreview(at: point)
                onPencilHoverPreview?(overlayView.normalizedPoint(at: point))
            case .ended, .cancelled, .failed:
                lastPencilHoverPoint = nil
                overlayView.clearPencilHoverPreview()
                onPencilHoverPreview?(nil)
            default:
                break
            }
        }

        func shouldBeginPagePan(_ panGestureRecognizer: UIPanGestureRecognizer, in scrollView: UIScrollView) -> Bool {
            guard usesActiveNotationFocus, scrollView.zoomScale <= 1.01 else {
                return true
            }
            let velocity = panGestureRecognizer.velocity(in: scrollView)
            guard abs(velocity.y) > abs(velocity.x) else {
                return true
            }

            // At zoomed-out note-entry scale, the inner scroll view is only for
            // manually pulling earlier content back into view. Upward page drags
            // should remain positional so they do not fight automatic focus.
            return velocity.y > 0
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            false
        }

        func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
            onPencilDoubleTap?()
        }
    }
}

final class ScorePageContentView: UIView {
    private let imageView = UIImageView()
    private let pdfView = ScorePagePDFTileView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .clear

        pdfView.isHidden = true

        addSubview(imageView)
        addSubview(pdfView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        pdfView.frame = bounds
    }

    func configure(image: UIImage?, pdfData: Data?, contentSize: CGSize) {
        imageView.image = image
        let validContentSize = CGSize(
            width: max(contentSize.width, 1),
            height: max(contentSize.height, 1)
        )

        if
            let pdfData,
            !pdfData.isEmpty,
            pdfView.configure(pdfData: pdfData, contentSize: validContentSize)
        {
            pdfView.isHidden = false
            imageView.isHidden = true
        } else if image != nil {
            pdfView.clear()
            pdfView.isHidden = true
            imageView.isHidden = false
        } else {
            pdfView.clear()
            pdfView.isHidden = true
            imageView.isHidden = true
        }
    }
}

private final class ScorePagePDFTileView: UIView {
    private var currentPDFData: Data?
    private var pdfDocument: CGPDFDocument?
    private var pdfPage: CGPDFPage?
    private var contentSize = CGSize(width: 1, height: 1)

    override class var layerClass: AnyClass {
        CATiledLayer.self
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        isOpaque = true
        contentScaleFactor = UIScreen.main.scale

        if let tiledLayer = layer as? CATiledLayer {
            tiledLayer.levelsOfDetail = 4
            tiledLayer.levelsOfDetailBias = 4
            tiledLayer.tileSize = CGSize(width: 512, height: 512)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(pdfData: Data, contentSize: CGSize) -> Bool {
        let validContentSize = CGSize(
            width: max(contentSize.width, 1),
            height: max(contentSize.height, 1)
        )
        var needsRedraw = self.contentSize != validContentSize
        self.contentSize = validContentSize

        if currentPDFData != pdfData {
            guard
                let provider = CGDataProvider(data: pdfData as CFData),
                let document = CGPDFDocument(provider),
                let page = document.page(at: 1)
            else {
                clear()
                return false
            }

            currentPDFData = pdfData
            pdfDocument = document
            pdfPage = page
            needsRedraw = true
        }

        if needsRedraw {
            setNeedsDisplay()
        }

        return pdfPage != nil
    }

    func clear() {
        currentPDFData = nil
        pdfDocument = nil
        pdfPage = nil
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard
            let context = UIGraphicsGetCurrentContext(),
            let pdfPage,
            bounds.width > 0,
            bounds.height > 0
        else {
            return
        }

        context.saveGState()
        context.setFillColor(UIColor.white.cgColor)
        context.fill(rect)

        let contentRect = AVMakeRect(aspectRatio: contentSize, insideRect: bounds)
        let pageBox = pdfPage.getBoxRect(.mediaBox)
        guard contentRect.width > 0, contentRect.height > 0, pageBox.width > 0, pageBox.height > 0 else {
            context.restoreGState()
            return
        }

        context.translateBy(x: contentRect.minX, y: contentRect.maxY)
        context.scaleBy(x: contentRect.width / pageBox.width, y: -(contentRect.height / pageBox.height))
        context.translateBy(x: -pageBox.minX, y: -pageBox.minY)
        context.drawPDFPage(pdfPage)
        context.restoreGState()
    }
}

private final class ScoreOverlayPDFView: UIView {
    private var currentPDFData: Data?
    private var pdfDocument: CGPDFDocument?
    private var pdfPage: CGPDFPage?

    var hasDocument: Bool {
        pdfPage != nil
    }

    override class var layerClass: AnyClass {
        CATiledLayer.self
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentScaleFactor = UIScreen.main.scale

        if let tiledLayer = layer as? CATiledLayer {
            tiledLayer.levelsOfDetail = 4
            tiledLayer.levelsOfDetailBias = 4
            tiledLayer.tileSize = CGSize(width: 256, height: 256)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @discardableResult
    func configure(pdfData: Data?) -> Bool {
        guard let pdfData, !pdfData.isEmpty else {
            clear()
            return false
        }

        if currentPDFData != pdfData {
            guard
                let provider = CGDataProvider(data: pdfData as CFData),
                let document = CGPDFDocument(provider),
                let page = document.page(at: 1)
            else {
                clear()
                return false
            }

            currentPDFData = pdfData
            pdfDocument = document
            pdfPage = page
            setNeedsDisplay()
        }

        return pdfPage != nil
    }

    func clear() {
        currentPDFData = nil
        pdfDocument = nil
        pdfPage = nil
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard
            let context = UIGraphicsGetCurrentContext(),
            let pdfPage,
            bounds.width > 0,
            bounds.height > 0
        else {
            return
        }

        let pageBox = pdfPage.getBoxRect(.mediaBox)
        guard pageBox.width > 0, pageBox.height > 0 else {
            return
        }

        context.saveGState()
        context.clear(rect)
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: bounds.width / pageBox.width, y: -(bounds.height / pageBox.height))
        context.translateBy(x: -pageBox.minX, y: -pageBox.minY)
        context.drawPDFPage(pdfPage)
        context.restoreGState()
    }
}

private final class ScorePageZoomScrollView: UIScrollView {
    var shouldBeginPagePan: ((UIPanGestureRecognizer, UIScrollView) -> Bool)?

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if let panGestureRecognizer = gestureRecognizer as? UIPanGestureRecognizer,
           panGestureRecognizer === self.panGestureRecognizer {
            return shouldBeginPagePan?(panGestureRecognizer, self) ?? true
        }

        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
}

final class ScorePageTapGestureRecognizer: UITapGestureRecognizer {
    var onPencilInteractionStart: (() -> Void)?
    private weak var preciseLocationView: UIView?
    private var precisePencilLocation: CGPoint?
    private(set) var inputKind: ScorePageTapInputKind = .direct

    // Tighter slop for the Pencil so a slide during the tap fails (no stray note)
    // rather than placing one at the drifted spot. UITapGestureRecognizer has no
    // public allowableMovement, so enforce it manually for Pencil touches only;
    // finger taps keep the system's default slop.
    private let pencilAllowableMovement: CGFloat = 5
    private var trackedPencilStart: CGPoint?

    func pageLocation(in view: UIView) -> CGPoint {
        if preciseLocationView === view, let precisePencilLocation {
            return precisePencilLocation
        }

        return location(in: view)
    }

    override func reset() {
        super.reset()
        preciseLocationView = nil
        precisePencilLocation = nil
        inputKind = .direct
        trackedPencilStart = nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let pencilTouch = touches.first(where: { $0.type == .pencil }), let view {
            trackedPencilStart = pencilTouch.preciseLocation(in: view)
            onPencilInteractionStart?()
        }
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)

        guard
            state == .possible,
            let start = trackedPencilStart,
            let view,
            let pencilTouch = touches.first(where: { $0.type == .pencil })
        else {
            return
        }

        let current = pencilTouch.preciseLocation(in: view)
        if hypot(current.x - start.x, current.y - start.y) > pencilAllowableMovement {
            state = .failed
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if let pencilTouch = touches.first(where: { $0.type == .pencil }), let view {
            preciseLocationView = view
            precisePencilLocation = pencilTouch.preciseLocation(in: view)
            inputKind = .pencil
        }

        super.touchesEnded(touches, with: event)
    }
}

final class ScorePageLongPressGestureRecognizer: UILongPressGestureRecognizer {
    var onPencilInteractionStart: (() -> Void)?
    private(set) var inputKind: ScorePageTapInputKind = .direct
    private weak var preciseLocationView: UIView?
    private var precisePencilLocation: CGPoint?
    private weak var initialLocationView: UIView?
    private var initialLocation: CGPoint?

    func pageLocation(in view: UIView) -> CGPoint {
        if preciseLocationView === view, let precisePencilLocation {
            return precisePencilLocation
        }

        return location(in: view)
    }

    func initialPageLocation(in view: UIView) -> CGPoint {
        if initialLocationView === view, let initialLocation {
            return initialLocation
        }

        return pageLocation(in: view)
    }

    override func reset() {
        super.reset()
        inputKind = .direct
        preciseLocationView = nil
        precisePencilLocation = nil
        initialLocationView = nil
        initialLocation = nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let pencilTouch = touches.first(where: { $0.type == .pencil }), let view {
            inputKind = .pencil
            preciseLocationView = view
            precisePencilLocation = pencilTouch.preciseLocation(in: view)
            initialLocationView = view
            initialLocation = precisePencilLocation
            onPencilInteractionStart?()
        } else if let touch = touches.first, let view {
            initialLocationView = view
            initialLocation = touch.location(in: view)
        }

        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if let pencilTouch = touches.first(where: { $0.type == .pencil }), let view {
            inputKind = .pencil
            preciseLocationView = view
            precisePencilLocation = pencilTouch.preciseLocation(in: view)
        }

        super.touchesMoved(touches, with: event)
    }
}

final class ScorePageOverlayView: UIView {
    var imageSize: CGSize = .zero {
        didSet {
            guard oldValue != imageSize else {
                return
            }

            setNeedsLayout()
        }
    }

    var playbackHighlight: ScorePlaybackMeasureHighlight? {
        didSet {
            guard oldValue != playbackHighlight else {
                return
            }

            applyOverlayState()
        }
    }

    var selection: ScoreSelectedElement? {
        didSet {
            guard oldValue != selection else {
                return
            }

            selectionImageView.image = selection?.overlayImageData.flatMap(UIImage.init(data:))
            _ = selectionPDFView.configure(pdfData: selection?.overlayPDFData)
            applyOverlayState()
        }
    }

    var noteEntryPreview: ScoreNoteEntryPreview? {
        didSet {
            guard oldValue != noteEntryPreview else {
                return
            }

            updateNoteEntryPreviewImage()
            updateOverlayFrames()
        }
    }

    var layoutMarkers: [ScoreLayoutMarker] = [] {
        didSet {
            guard oldValue != layoutMarkers else {
                return
            }

            updateOverlayFrames()
        }
    }

    var allowsPencilHoverPreview = false {
        didSet {
            guard oldValue != allowsPencilHoverPreview else {
                return
            }

            if !allowsPencilHoverPreview {
                pencilHoverPreviewPoint = nil
            }
            updateOverlayFrames()
        }
    }

    var noteEntryPreviewPitchClass: Int? = nil {
        didSet {
            guard oldValue != noteEntryPreviewPitchClass else {
                return
            }

            updateNoteEntryPreviewImage()
            updateOverlayFrames()
        }
    }

    var noteEntryPreviewIsRest = false {
        didSet {
            guard oldValue != noteEntryPreviewIsRest else {
                return
            }

            updateNoteEntryPreviewImage()
            updateOverlayFrames()
        }
    }

    var noteEntryPreviewDuration: ScoreNoteDuration = .quarter {
        didSet {
            guard oldValue != noteEntryPreviewDuration else {
                return
            }

            updateNoteEntryPreviewImage()
            updateOverlayFrames()
        }
    }

    var showsLayoutMarkers = false {
        didSet {
            guard oldValue != showsLayoutMarkers else {
                return
            }

            applyOverlayState()
        }
    }

    private let playbackContainer = UIView()
    private let playbackProgressView = UIView()
    private let selectionContainer = UIView()
    private let selectionPDFView = ScoreOverlayPDFView()
    private let selectionImageView = UIImageView()
    private let notePreviewImageView = UIImageView()
    private let chordAttachmentGuideLayer = CAShapeLayer()
    private let expressionStartHandleView = UIView()
    private let expressionEndHandleView = UIView()
    private var selectionRangeContainers: [UIView] = []
    private let insertionFineTuneContainer = UIView()
    private var layoutMarkerViews: [ScoreLayoutMarkerBadgeView] = []
    private var selectedNoteDragOffset: CGPoint = .zero
    private var isDraggingSelectedNote = false
    private var selectedChordTextDragOffset: CGPoint = .zero
    private var isDraggingSelectedChordText = false
    private var measureRangePreviewStartPoint: CGPoint?
    private var measureRangePreviewEndPoint: CGPoint?
    private var expressionEndpointPreviewIsStart: Bool?
    private var expressionEndpointPreviewPoint: CGPoint?
    private var insertionFineTunePoint: CGPoint?
    private var pencilHoverPreviewPoint: CGPoint?
    private let noteEntryPreviewYOffset: CGFloat = -2

    var activeNotationFrame: CGRect? {
        if let previewFrame = noteEntryPreviewCoreFrame() {
            return previewFrame.insetBy(dx: -18, dy: -18)
        }
        if let selectionFrame,
           selection?.kind == .note || selection?.kind == .rest || selection?.kind == .measure || selection?.kind == .chordText || selection?.kind == .text {
            return selectionFrame.insetBy(dx: -22, dy: -22)
        }
        return nil
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        isUserInteractionEnabled = true

        playbackContainer.isHidden = true
        playbackContainer.layer.cornerRadius = 8
        playbackContainer.layer.borderWidth = 2
        playbackContainer.layer.borderColor = UIColor(red: 0.94, green: 0.69, blue: 0.21, alpha: 0.95).cgColor
        playbackContainer.backgroundColor = UIColor(red: 0.98, green: 0.82, blue: 0.19, alpha: 0.18)
        playbackContainer.clipsToBounds = true

        selectionContainer.isHidden = true
        configureSelectionOverlay(selectionContainer)
        selectionContainer.isUserInteractionEnabled = false
        selectionPDFView.isHidden = true
        selectionPDFView.isUserInteractionEnabled = false
        selectionImageView.isHidden = true
        selectionImageView.contentMode = .scaleToFill
        selectionImageView.isUserInteractionEnabled = false
        notePreviewImageView.isHidden = true
        notePreviewImageView.contentMode = .scaleAspectFit
        notePreviewImageView.isUserInteractionEnabled = false
        notePreviewImageView.alpha = 0.86
        updateNoteEntryPreviewImage()
        configureChordAttachmentGuide(chordAttachmentGuideLayer)
        configureExpressionHandle(expressionStartHandleView)
        configureExpressionHandle(expressionEndHandleView)

        insertionFineTuneContainer.isHidden = true
        configureSelectionOverlay(insertionFineTuneContainer)
        insertionFineTuneContainer.isUserInteractionEnabled = false

        playbackProgressView.backgroundColor = UIColor(red: 0.96, green: 0.72, blue: 0.12, alpha: 0.30)

        addSubview(selectionContainer)
        addSubview(selectionPDFView)
        addSubview(selectionImageView)
        addSubview(notePreviewImageView)
        layer.addSublayer(chordAttachmentGuideLayer)
        addSubview(expressionStartHandleView)
        addSubview(expressionEndHandleView)
        addSubview(insertionFineTuneContainer)
        addSubview(playbackContainer)
        playbackContainer.addSubview(playbackProgressView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateOverlayFrames()
    }

    func normalizedPoint(at point: CGPoint) -> CGPoint? {
        guard
            bounds.width > 0,
            bounds.height > 0,
            imageSize.width > 0,
            imageSize.height > 0
        else {
            return nil
        }

        let imageRect = AVMakeRect(aspectRatio: imageSize, insideRect: bounds)
        guard imageRect.contains(point) else {
            return nil
        }

        let normalizedX = (point.x - imageRect.minX) / imageRect.width
        let normalizedY = (point.y - imageRect.minY) / imageRect.height
        return CGPoint(x: normalizedX, y: normalizedY)
    }

    func normalizedLayoutMarkerTapPoint(at point: CGPoint) -> CGPoint? {
        guard showsLayoutMarkers, !layoutMarkers.isEmpty else {
            return nil
        }

        let visibleCount = min(layoutMarkers.count, layoutMarkerViews.count)
        guard visibleCount > 0 else {
            return nil
        }

        for index in 0..<visibleCount {
            let markerView = layoutMarkerViews[index]
            guard !markerView.isHidden else {
                continue
            }

            if markerView.frame.insetBy(dx: -10, dy: -10).contains(point) {
                return layoutMarkers[index].normalizedRect.center
            }
        }

        return nil
    }

    func containsSelectedNote(at point: CGPoint) -> Bool {
        guard selection?.kind == .note, let selectionFrame else {
            return false
        }

        return selectionFrame.insetBy(dx: -18, dy: -18).contains(point)
    }

    func containsSelectedChordText(at point: CGPoint) -> Bool {
        guard selection?.kind == .chordText, let selectionFrame else {
            return false
        }

        return selectionFrame.insetBy(dx: -18, dy: -18).contains(point)
    }

    func normalizedMeasureRangeDragStartPoint(from startPoint: CGPoint, to currentPoint: CGPoint) -> CGPoint? {
        normalizedMeasureRangeDragStartPoint(from: startPoint, to: currentPoint, anchorFrame: nil)
    }

    func measureRangeDragAnchorFrame(at startPoint: CGPoint) -> CGRect? {
        guard
            selection?.kind == .measure,
            let selectionFrame,
            selectionFrame.insetBy(dx: -12, dy: -12).contains(startPoint)
        else {
            return nil
        }

        let edgeBandWidth = min(max(selectionFrame.width * 0.18, 18), 44)
        let startsNearEdge = startPoint.x <= selectionFrame.minX + edgeBandWidth
            || startPoint.x >= selectionFrame.maxX - edgeBandWidth
        guard startsNearEdge else {
            return nil
        }

        return selectionFrame
    }

    func normalizedMeasureRangeDragStartPoint(from startPoint: CGPoint, to currentPoint: CGPoint, anchorFrame: CGRect?) -> CGPoint? {
        guard let anchorFrame else {
            return normalizedPoint(at: startPoint)
        }

        let anchorX = currentPoint.x >= anchorFrame.midX ? anchorFrame.minX : anchorFrame.maxX
        return normalizedPoint(at: CGPoint(x: anchorX, y: startPoint.y))
    }

    func updateMeasureRangeDragPreview(startNormalizedPoint: CGPoint, endPoint: CGPoint) {
        measureRangePreviewStartPoint = startNormalizedPoint
        measureRangePreviewEndPoint = normalizedPoint(at: endPoint)
        updateOverlayFrames()
    }

    func clearMeasureRangeDragPreview() {
        measureRangePreviewStartPoint = nil
        measureRangePreviewEndPoint = nil
        updateOverlayFrames()
    }

    func expressionEndpoint(at point: CGPoint) -> Bool? {
        guard selection?.kind == .expressionSpanner else {
            return nil
        }

        let candidates: [(isStart: Bool, frame: CGRect)] = [
            (true, expressionStartHandleView.frame),
            (false, expressionEndHandleView.frame)
        ]
        let hitSlop = expressionHandleHitSlop
        let hits = candidates.compactMap { candidate -> (isStart: Bool, distance: CGFloat)? in
            guard !candidate.frame.isEmpty,
                  candidate.frame.insetBy(dx: -hitSlop, dy: -hitSlop).contains(point)
            else {
                return nil
            }

            let center = CGPoint(x: candidate.frame.midX, y: candidate.frame.midY)
            return (candidate.isStart, hypot(point.x - center.x, point.y - center.y))
        }
        return hits.min { $0.distance < $1.distance }?.isStart
    }

    func updateExpressionEndpointDragPreview(start: Bool, at point: CGPoint) {
        expressionEndpointPreviewIsStart = start
        expressionEndpointPreviewPoint = point
        updateOverlayFrames()
    }

    func clearExpressionEndpointDragPreview() {
        expressionEndpointPreviewIsStart = nil
        expressionEndpointPreviewPoint = nil
        updateOverlayFrames()
    }

    func selectedNoteDragSemitoneDelta(from startPoint: CGPoint, to endPoint: CGPoint) -> Int {
        guard selection?.kind == .note, let start = normalizedPoint(at: startPoint), let end = normalizedPoint(at: endPoint) else {
            return 0
        }

        let stepHeight = max((selection?.normalizedRect.height ?? 0) * 0.55, 0.006)
        let rawSteps = -((end.y - start.y) / CGFloat(stepHeight))
        return Int(rawSteps.rounded())
    }

    func selectedNoteDragDropPoint(startPoint: CGPoint, currentPoint: CGPoint) -> CGPoint? {
        guard selection?.kind == .note, let selectionFrame else {
            return nil
        }

        let dropCenter = CGPoint(
            x: selectionFrame.midX + currentPoint.x - startPoint.x,
            y: selectionFrame.midY + currentPoint.y - startPoint.y
        )
        return normalizedPoint(at: dropCenter)
    }

    func updateSelectedNoteDrag(startPoint: CGPoint, currentPoint: CGPoint) {
        guard selection?.kind == .note else {
            clearSelectedNoteDrag()
            return
        }

        selectedNoteDragOffset = CGPoint(
            x: currentPoint.x - startPoint.x,
            y: currentPoint.y - startPoint.y
        )
        isDraggingSelectedNote = true
        updateOverlayFrames()
    }

    func clearSelectedNoteDrag() {
        selectedNoteDragOffset = .zero
        isDraggingSelectedNote = false
        updateOverlayFrames()
    }

    func selectedChordTextDragDropPoint(startPoint: CGPoint, currentPoint: CGPoint) -> CGPoint? {
        guard selection?.kind == .chordText, let selectionFrame else {
            return nil
        }

        let dropCenter = CGPoint(
            x: selectionFrame.midX + currentPoint.x - startPoint.x,
            y: selectionFrame.midY + currentPoint.y - startPoint.y
        )
        return normalizedPoint(at: dropCenter)
    }

    func updateSelectedChordTextDrag(startPoint: CGPoint, currentPoint: CGPoint) {
        guard selection?.kind == .chordText else {
            clearSelectedChordTextDrag()
            return
        }

        selectedChordTextDragOffset = CGPoint(
            x: currentPoint.x - startPoint.x,
            y: currentPoint.y - startPoint.y
        )
        isDraggingSelectedChordText = true
        updateOverlayFrames()
    }

    func clearSelectedChordTextDrag() {
        selectedChordTextDragOffset = .zero
        isDraggingSelectedChordText = false
        updateOverlayFrames()
    }

    func updateInsertionFineTune(at point: CGPoint) {
        insertionFineTunePoint = point
        pencilHoverPreviewPoint = nil
        updateOverlayFrames()
    }

    func insertionFineTuneDropPoint(at point: CGPoint) -> CGPoint? {
        normalizedPoint(at: point)
    }

    func clearInsertionFineTune() {
        insertionFineTunePoint = nil
        updateOverlayFrames()
    }

    func updatePencilHoverPreview(at point: CGPoint) {
        guard allowsPencilHoverPreview else {
            clearPencilHoverPreview()
            return
        }

        pencilHoverPreviewPoint = point
        updateOverlayFrames()
    }

    func clearPencilHoverPreview() {
        pencilHoverPreviewPoint = nil
        updateOverlayFrames()
    }

    private func applyOverlayState() {
        selectionContainer.isHidden = selection == nil
        for container in selectionRangeContainers {
            container.isHidden = selection == nil
        }
        playbackContainer.isHidden = playbackHighlight == nil
        for markerView in layoutMarkerViews {
            markerView.isHidden = !showsLayoutMarkers
        }
        updateOverlayFrames()
    }

    private func updateOverlayFrames() {
        guard
            bounds.width > 0,
            bounds.height > 0,
            imageSize.width > 0,
            imageSize.height > 0
        else {
            selectionContainer.isHidden = true
            selectionPDFView.isHidden = true
            selectionImageView.isHidden = true
            notePreviewImageView.isHidden = true
            chordAttachmentGuideLayer.isHidden = true
            expressionStartHandleView.isHidden = true
            expressionEndHandleView.isHidden = true
            for container in selectionRangeContainers {
                container.isHidden = true
            }
            playbackContainer.isHidden = true
            insertionFineTuneContainer.isHidden = true
            for markerView in layoutMarkerViews {
                markerView.isHidden = true
            }
            return
        }

        let imageRect = AVMakeRect(aspectRatio: imageSize, insideRect: bounds)
        updateLayoutMarkerFrames(in: imageRect)

        if let selection {
            if selectionPDFView.hasDocument,
               selection.kind == .note || selection.kind == .rest {
                var overlayFrame = imageRect
                if isDraggingSelectedNote {
                    overlayFrame = overlayFrame.offsetBy(dx: selectedNoteDragOffset.x, dy: selectedNoteDragOffset.y)
                }
                let hidesOverlay = overlayFrame.width <= 1 || overlayFrame.height <= 1
                selectionPDFView.isHidden = hidesOverlay
                selectionImageView.isHidden = true
                if !hidesOverlay {
                    selectionPDFView.frame = overlayFrame
                    selectionPDFView.setNeedsDisplay()
                }
                selectionContainer.isHidden = true
                for container in selectionRangeContainers {
                    container.isHidden = true
                }
            } else if let overlayRect = selection.overlayNormalizedRect,
                      selection.overlayImageData != nil,
                      selection.kind == .note || selection.kind == .rest {
                var overlayFrame = frame(for: overlayRect, inside: imageRect)
                if isDraggingSelectedNote {
                    overlayFrame = overlayFrame.offsetBy(dx: selectedNoteDragOffset.x, dy: selectedNoteDragOffset.y)
                }
                selectionPDFView.isHidden = true
                selectionImageView.isHidden = overlayFrame.width <= 1 || overlayFrame.height <= 1
                if !selectionImageView.isHidden {
                    selectionImageView.frame = overlayFrame
                }
                selectionContainer.isHidden = true
                for container in selectionRangeContainers {
                    container.isHidden = true
                }
            } else {
                selectionPDFView.isHidden = true
                selectionImageView.isHidden = true
                let highlightRects = selection.highlightRects.isEmpty ? [selection.normalizedRect] : selection.highlightRects
                ensureSelectionRangeContainers(count: highlightRects.count)
                for (index, rect) in highlightRects.enumerated() {
                    let container = index == 0 ? selectionContainer : selectionRangeContainers[index - 1]
                    var selectionFrame = frame(for: rect, inside: imageRect)
                    if isDraggingSelectedNote && index == 0 {
                        selectionFrame = selectionFrame.offsetBy(dx: selectedNoteDragOffset.x, dy: selectedNoteDragOffset.y)
                    } else if isDraggingSelectedChordText && selection.kind == .chordText && index == 0 {
                        selectionFrame = selectionFrame.offsetBy(dx: selectedChordTextDragOffset.x, dy: selectedChordTextDragOffset.y)
                    } else if index == 0 {
                        selectionFrame = locallyAdjustedRangePreviewFrame(selectionFrame, inside: imageRect)
                    }
                    if selection.kind == .chordText {
                        selectionFrame = paddedChordTextSelectionFrame(selectionFrame, inside: imageRect)
                    } else if selection.kind == .text || selection.kind == .tempo || selection.kind == .dynamic {
                        selectionFrame = paddedTextSelectionFrame(selectionFrame, inside: imageRect)
                    }
                    container.isHidden = selectionFrame.width <= 1 || selectionFrame.height <= 1
                    if !container.isHidden {
                        container.frame = selectionFrame
                        applySelectionOverlayStyle(to: container, selection: selection, frame: selectionFrame)
                    }
                }
                if selectionRangeContainers.count > max(0, highlightRects.count - 1) {
                    for index in max(0, highlightRects.count - 1)..<selectionRangeContainers.count {
                        selectionRangeContainers[index].isHidden = true
                    }
                }
            }
        } else {
            selectionContainer.isHidden = true
            selectionPDFView.isHidden = true
            selectionImageView.isHidden = true
            notePreviewImageView.isHidden = true
            chordAttachmentGuideLayer.isHidden = true
            expressionStartHandleView.isHidden = true
            expressionEndHandleView.isHidden = true
            for container in selectionRangeContainers {
                container.isHidden = true
            }
        }
        updateChordAttachmentGuide(in: imageRect)
        updateExpressionEndpointFrames(in: imageRect)

        if let previewPoint = insertionFineTunePoint ?? pencilHoverPreviewPoint {
            updateNoteEntryPreview(at: previewPoint)
        } else {
            notePreviewImageView.isHidden = true
            insertionFineTuneContainer.isHidden = true
        }

        if let playbackHighlight {
            let playbackFrame = frame(for: playbackHighlight.normalizedRect, inside: imageRect)
            playbackContainer.isHidden = playbackFrame.width <= 1 || playbackFrame.height <= 1
            if !playbackContainer.isHidden {
                playbackContainer.frame = playbackFrame

                let progressWidth = playbackFrame.width * CGFloat(min(max(playbackHighlight.progress, 0), 1))
                playbackProgressView.frame = CGRect(
                    x: 0,
                    y: 0,
                    width: progressWidth,
                    height: playbackFrame.height
                ).integral
            }
        } else {
            playbackContainer.isHidden = true
        }
    }

    private func ensureSelectionRangeContainers(count: Int) {
        let extraCount = max(0, count - 1)
        while selectionRangeContainers.count < extraCount {
            let container = UIView()
            container.isHidden = true
            configureSelectionOverlay(container)
            container.isUserInteractionEnabled = false
            insertSubview(container, aboveSubview: selectionContainer)
            selectionRangeContainers.append(container)
        }
    }

    private func locallyAdjustedRangePreviewFrame(_ selectionFrame: CGRect, inside imageRect: CGRect) -> CGRect {
        guard
            selection?.kind == .measure,
            let measureRangePreviewStartPoint,
            let measureRangePreviewEndPoint
        else {
            return selectionFrame
        }

        let startX = imageRect.minX + (imageRect.width * measureRangePreviewStartPoint.x)
        let endX = imageRect.minX + (imageRect.width * measureRangePreviewEndPoint.x)
        let minimumWidth: CGFloat = 2

        if startX <= endX {
            let left = min(max(startX, selectionFrame.minX), selectionFrame.maxX - minimumWidth)
            return CGRect(
                x: left,
                y: selectionFrame.minY,
                width: selectionFrame.maxX - left,
                height: selectionFrame.height
            )
        } else {
            let right = max(min(startX, selectionFrame.maxX), selectionFrame.minX + minimumWidth)
            return CGRect(
                x: selectionFrame.minX,
                y: selectionFrame.minY,
                width: right - selectionFrame.minX,
                height: selectionFrame.height
            )
        }
    }

    private func paddedChordTextSelectionFrame(_ frame: CGRect, inside imageRect: CGRect) -> CGRect {
        let horizontalPadding = max(frame.height * 0.28, 7)
        let verticalPadding = max(frame.height * 0.18, 4)
        let minimumWidth = max(frame.height * 1.6, 28)
        let minimumHeight = max(frame.height + (verticalPadding * 2), 20)
        var padded = frame.insetBy(dx: -horizontalPadding, dy: -verticalPadding)
        if padded.width < minimumWidth {
            padded = padded.insetBy(dx: -(minimumWidth - padded.width) / 2, dy: 0)
        }
        if padded.height < minimumHeight {
            padded = padded.insetBy(dx: 0, dy: -(minimumHeight - padded.height) / 2)
        }

        let minX = max(imageRect.minX, min(padded.minX, imageRect.maxX - padded.width))
        let minY = max(imageRect.minY, min(padded.minY, imageRect.maxY - padded.height))
        return CGRect(origin: CGPoint(x: minX, y: minY), size: padded.size)
    }

    private func paddedTextSelectionFrame(_ frame: CGRect, inside imageRect: CGRect) -> CGRect {
        let horizontalPadding = max(frame.height * 0.16, 5)
        let verticalPadding = max(frame.height * 0.14, 3)
        let minimumHeight = max(frame.height + (verticalPadding * 2), 18)
        var padded = frame.insetBy(dx: -horizontalPadding, dy: -verticalPadding)
        if padded.height < minimumHeight {
            padded = padded.insetBy(dx: 0, dy: -(minimumHeight - padded.height) / 2)
        }

        let minX = max(imageRect.minX, min(padded.minX, imageRect.maxX - padded.width))
        let minY = max(imageRect.minY, min(padded.minY, imageRect.maxY - padded.height))
        return CGRect(origin: CGPoint(x: minX, y: minY), size: padded.size)
    }

    private func updateChordAttachmentGuide(in imageRect: CGRect) {
        guard
            let selection,
            selection.kind == .chordText,
            isDraggingSelectedChordText,
            let selectionFrame
        else {
            chordAttachmentGuideLayer.isHidden = true
            chordAttachmentGuideLayer.path = nil
            return
        }

        let movedFrame = selectionFrame.offsetBy(dx: selectedChordTextDragOffset.x, dy: selectedChordTextDragOffset.y)
        let chordPoint = CGPoint(x: movedFrame.midX, y: movedFrame.maxY + 2)
        let dragCenter = CGPoint(x: movedFrame.midX, y: movedFrame.midY)
        guard let anchorPoint = snappedChordAttachmentPoint(for: dragCenter, selection: selection, inside: imageRect) else {
            chordAttachmentGuideLayer.isHidden = true
            chordAttachmentGuideLayer.path = nil
            return
        }

        let path = UIBezierPath()
        path.move(to: chordPoint)
        path.addLine(to: anchorPoint)
        chordAttachmentGuideLayer.path = path.cgPath
        chordAttachmentGuideLayer.isHidden = false
    }

    private func snappedChordAttachmentPoint(for dragCenter: CGPoint, selection: ScoreSelectedElement, inside imageRect: CGRect) -> CGPoint? {
        let targets = selection.attachmentTargets.isEmpty
            ? selection.attachmentPoint.map { [$0] } ?? []
            : selection.attachmentTargets
        guard !targets.isEmpty else {
            return nil
        }

        return targets
            .map { point(for: $0, inside: imageRect) }
            .min { lhs, rhs in
                let lhsDistance = chordAttachmentSnapDistance(from: dragCenter, to: lhs)
                let rhsDistance = chordAttachmentSnapDistance(from: dragCenter, to: rhs)
                return lhsDistance < rhsDistance
            }
    }

    private func chordAttachmentSnapDistance(from point: CGPoint, to target: CGPoint) -> CGFloat {
        let dx = target.x - point.x
        let dy = (target.y - point.y) * 0.12
        return hypot(dx, dy)
    }

    private func updateExpressionEndpointFrames(in imageRect: CGRect) {
        guard
            let selection,
            selection.kind == .expressionSpanner,
            let startHandlePoint = selection.startHandlePoint,
            let endHandlePoint = selection.endHandlePoint
        else {
            expressionStartHandleView.isHidden = true
            expressionEndHandleView.isHidden = true
            return
        }

        let startPoint = expressionEndpointPreviewIsStart == true && expressionEndpointPreviewPoint != nil
            ? expressionEndpointPreviewPoint!
            : point(for: startHandlePoint, inside: imageRect)
        let endPoint = expressionEndpointPreviewIsStart == false && expressionEndpointPreviewPoint != nil
            ? expressionEndpointPreviewPoint!
            : point(for: endHandlePoint, inside: imageRect)
        expressionStartHandleView.frame = expressionHandleFrame(centeredAt: startPoint)
        expressionEndHandleView.frame = expressionHandleFrame(centeredAt: endPoint)
        expressionStartHandleView.isHidden = false
        expressionEndHandleView.isHidden = false
    }

    private func point(for normalizedPoint: CGPoint, inside imageRect: CGRect) -> CGPoint {
        CGPoint(
            x: imageRect.minX + imageRect.width * normalizedPoint.x,
            y: imageRect.minY + imageRect.height * normalizedPoint.y
        )
    }

    private func expressionHandleFrame(centeredAt point: CGPoint) -> CGRect {
        let side = expressionHandleVisualSide
        return CGRect(x: point.x - side * 0.5, y: point.y - side * 0.5, width: side, height: side).integral
    }

    private var expressionHandleVisualSide: CGFloat {
        traitCollection.userInterfaceIdiom == .phone ? 12 : 14
    }

    private var expressionHandleHitSlop: CGFloat {
        traitCollection.userInterfaceIdiom == .phone ? 10 : 14
    }

    private func frame(for normalizedRect: ScoreNormalizedRect, inside imageRect: CGRect) -> CGRect {
        CGRect(
            x: imageRect.minX + (imageRect.width * CGFloat(normalizedRect.x)),
            y: imageRect.minY + (imageRect.height * CGFloat(normalizedRect.y)),
            width: imageRect.width * CGFloat(normalizedRect.width),
            height: imageRect.height * CGFloat(normalizedRect.height)
        )
    }

    private var selectionFrame: CGRect? {
        guard
            let selection,
            bounds.width > 0,
            bounds.height > 0,
            imageSize.width > 0,
            imageSize.height > 0
        else {
            return nil
        }

        let imageRect = AVMakeRect(aspectRatio: imageSize, insideRect: bounds)
        return frame(for: selection.normalizedRect, inside: imageRect)
    }

    private var insertionFineTuneMarkerSize: CGSize {
        guard
            let selection,
            selection.kind == .note || selection.kind == .rest,
            let selectionFrame
        else {
            return CGSize(width: 12, height: 12)
        }

        return selectionFrame.size
    }

    private func updateNoteEntryPreview(at point: CGPoint) {
        if let corePreviewFrame = noteEntryPreviewCoreFrame(),
           noteEntryPreview?.overlayImageData.isEmpty == false {
            notePreviewImageView.isHidden = false
            notePreviewImageView.frame = corePreviewFrame
            insertionFineTuneContainer.isHidden = true
            return
        }

        notePreviewImageView.isHidden = true
        insertionFineTuneContainer.isHidden = true
    }

    private func noteEntryPreviewCoreFrame() -> CGRect? {
        guard
            let noteEntryPreview,
            bounds.width > 0,
            bounds.height > 0,
            imageSize.width > 0,
            imageSize.height > 0
        else {
            return nil
        }

        let imageRect = AVMakeRect(aspectRatio: imageSize, insideRect: bounds)
        let previewFrame = frame(for: noteEntryPreview.overlayNormalizedRect, inside: imageRect)
        return previewFrame.width > 1 && previewFrame.height > 1 ? previewFrame.integral : nil
    }

    private func noteEntryPreviewFrame(centeredAt point: CGPoint) -> CGRect? {
        guard
            bounds.width > 0,
            bounds.height > 0,
            imageSize.width > 0,
            imageSize.height > 0
        else {
            return nil
        }

        let imageRect = AVMakeRect(aspectRatio: imageSize, insideRect: bounds)
        let referenceFrame: CGRect
        if let selection,
           canUseSelectionAsNoteEntryPreviewReference(selection),
           let overlayRect = selection.overlayNormalizedRect {
            referenceFrame = frame(for: overlayRect, inside: imageRect)
        } else {
            referenceFrame = noteEntryPreviewReferenceFrame(in: imageRect)
        }
        guard referenceFrame.width > 1, referenceFrame.height > 1 else {
            return nil
        }
        let previewCenter = snappedNoteEntryPreviewPoint(point, referenceFrame: referenceFrame)

        return CGRect(
            x: previewCenter.x - referenceFrame.width / 2,
            y: previewCenter.y - referenceFrame.height / 2 + noteEntryPreviewYOffset,
            width: referenceFrame.width,
            height: referenceFrame.height
        ).integral
    }

    private func noteEntryPreviewReferenceFrame(in imageRect: CGRect) -> CGRect {
        let pageRelativeHeight = imageRect.height * (noteEntryPreviewIsRest ? 0.030 : 0.040)
        let height = min(max(pageRelativeHeight, noteEntryPreviewIsRest ? 24 : 32), noteEntryPreviewIsRest ? 48 : 64)
        let width = height * (noteEntryPreviewIsRest ? 0.78 : 0.62)
        return CGRect(x: 0, y: 0, width: width, height: height)
    }

    private func canUseSelectionAsNoteEntryPreviewReference(_ selection: ScoreSelectedElement) -> Bool {
        if noteEntryPreviewIsRest {
            return selection.kind == .rest
        }

        return selection.kind == .note
    }

    private func snappedNoteEntryPreviewPoint(_ point: CGPoint, referenceFrame: CGRect) -> CGPoint {
        guard
            !noteEntryPreviewIsRest,
            let selection,
            selection.kind == .note,
            let selectionFrame
        else {
            return point
        }

        let stepHeight = max(selectionFrame.height * 0.28, referenceFrame.height * 0.14, 3)
        let snappedStep = ((point.y - selectionFrame.midY) / stepHeight).rounded()
        return CGPoint(
            x: point.x,
            y: selectionFrame.midY + snappedStep * stepHeight
        )
    }

    private func updateNoteEntryPreviewImage() {
        if let imageData = noteEntryPreview?.overlayImageData,
           let image = UIImage(data: imageData) {
            notePreviewImageView.image = image
        } else {
            notePreviewImageView.image = makeNoteEntryPreviewImage(
                duration: noteEntryPreviewDuration,
                isRest: noteEntryPreviewIsRest
            )
        }
    }

    private func makeNoteEntryPreviewImage(duration: ScoreNoteDuration, isRest: Bool) -> UIImage {
        let glyph = isRest ? duration.noteEntryRestPreviewGlyph : duration.bravuraTextGlyph
        let museScoreVoiceOneBlue = UIColor(red: 0.0, green: 0.396, blue: 0.749, alpha: 1.0)
        let fontSize: CGFloat = isRest ? 42 : 52
        let font = UIFont(name: MusicNotationFont.postScriptName, size: fontSize)
            ?? UIFont.systemFont(ofSize: fontSize, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: museScoreVoiceOneBlue
        ]
        let attributedString = NSAttributedString(string: glyph, attributes: attributes)
        let textSize = attributedString.boundingRect(
            with: CGSize(width: 96, height: 96),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).integral.size
        let canvasSize = CGSize(
            width: max(24, textSize.width + 10),
            height: max(28, textSize.height + 8)
        )
        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        return renderer.image { _ in
            attributedString.draw(
                in: CGRect(
                    x: (canvasSize.width - textSize.width) / 2,
                    y: (canvasSize.height - textSize.height) / 2,
                    width: textSize.width,
                    height: textSize.height
                )
            )
        }
    }

    private func configureSelectionOverlay(_ view: UIView) {
        view.layer.cornerRadius = 8
        view.layer.borderWidth = 2
        view.layer.borderColor = UIColor(red: 0.47, green: 0.67, blue: 0.98, alpha: 0.95).cgColor
        view.backgroundColor = UIColor(red: 0.42, green: 0.63, blue: 0.96, alpha: 0.16)
    }

    private func configureChordAttachmentGuide(_ layer: CAShapeLayer) {
        layer.isHidden = true
        layer.strokeColor = UIColor(red: 0.0, green: 0.396, blue: 0.749, alpha: 0.82).cgColor
        layer.lineWidth = 1.6
        layer.lineDashPattern = [4, 4]
        layer.lineCap = .round
        layer.fillColor = UIColor.clear.cgColor
    }

    private func configureExpressionHandle(_ view: UIView) {
        view.isHidden = true
        view.isUserInteractionEnabled = false
        view.layer.cornerRadius = 7
        view.layer.borderWidth = 2
        view.layer.borderColor = UIColor.white.cgColor
        view.backgroundColor = UIColor(red: 0.0, green: 0.396, blue: 0.749, alpha: 1.0)
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.22
        view.layer.shadowRadius = 3
        view.layer.shadowOffset = CGSize(width: 0, height: 1)
    }

    private func applySelectionOverlayStyle(to view: UIView, selection: ScoreSelectedElement, frame: CGRect) {
        switch selection.kind {
        case .note, .rest:
            let museScoreVoiceOneBlue = UIColor(red: 0.0, green: 0.396, blue: 0.749, alpha: 1.0)
            let shortestSide = min(frame.width, frame.height)
            let aspectRatio = frame.height > 0 ? frame.width / frame.height : 1
            let shouldUseOvalShape = aspectRatio > 0.45 && aspectRatio < 2.2
            view.layer.cornerRadius = shouldUseOvalShape ? shortestSide / 2 : min(3, shortestSide / 2)
            view.layer.borderWidth = 2
            view.layer.borderColor = museScoreVoiceOneBlue.cgColor
            view.backgroundColor = museScoreVoiceOneBlue.withAlphaComponent(0.18)
        case .chordText:
            let museScoreVoiceOneBlue = UIColor(red: 0.0, green: 0.396, blue: 0.749, alpha: 1.0)
            view.layer.cornerRadius = min(6, frame.height / 2)
            view.layer.borderWidth = 1.5
            view.layer.borderColor = museScoreVoiceOneBlue.withAlphaComponent(0.88).cgColor
            view.backgroundColor = museScoreVoiceOneBlue.withAlphaComponent(0.12)
        case .layoutBreak:
            view.layer.cornerRadius = 0
            view.layer.borderWidth = 0
            view.layer.borderColor = UIColor.clear.cgColor
            view.backgroundColor = .clear
            view.layer.shadowOpacity = 0
        default:
            configureSelectionOverlay(view)
        }
    }

    private func updateLayoutMarkerFrames(in imageRect: CGRect) {
        let visibleMarkers = showsLayoutMarkers ? layoutMarkers : []
        ensureLayoutMarkerViews(count: visibleMarkers.count)
        guard !visibleMarkers.isEmpty else {
            for markerView in layoutMarkerViews {
                markerView.isHidden = true
            }
            return
        }

        for (index, marker) in visibleMarkers.enumerated() {
            let markerView = layoutMarkerViews[index]
            let markerFrame = layoutMarkerFrame(for: marker, inside: imageRect)
            markerView.configure(kind: marker.kind, isSelected: isSelectedLayoutMarker(marker))
            markerView.frame = markerFrame
            markerView.isHidden = markerFrame.width <= 1 || markerFrame.height <= 1
            bringSubviewToFront(markerView)
        }

        if layoutMarkerViews.count > visibleMarkers.count {
            for index in visibleMarkers.count..<layoutMarkerViews.count {
                layoutMarkerViews[index].isHidden = true
            }
        }
    }

    private func ensureLayoutMarkerViews(count: Int) {
        while layoutMarkerViews.count < count {
            let markerView = ScoreLayoutMarkerBadgeView()
            markerView.isHidden = true
            markerView.isUserInteractionEnabled = false
            addSubview(markerView)
            layoutMarkerViews.append(markerView)
        }
    }

    private func layoutMarkerFrame(for marker: ScoreLayoutMarker, inside imageRect: CGRect) -> CGRect {
        let markerRect = frame(for: marker.normalizedRect, inside: imageRect)
        guard markerRect.width > 0, markerRect.height > 0 else {
            return .zero
        }

        let size = marker.kind.badgeSize
        let unclamped = CGRect(
            x: markerRect.maxX + 2,
            y: markerRect.maxY - size.height - 2,
            width: size.width,
            height: size.height
        )
        let x = min(max(unclamped.minX, imageRect.minX + 3), imageRect.maxX - size.width - 3)
        let y = min(max(unclamped.minY, imageRect.minY + 3), imageRect.maxY - size.height - 3)
        return CGRect(x: x, y: y, width: size.width, height: size.height).integral
    }

    private func isSelectedLayoutMarker(_ marker: ScoreLayoutMarker) -> Bool {
        guard
            let selection,
            selection.kind == .layoutBreak,
            selection.layoutBreakKind == marker.kind
        else {
            return false
        }

        let selectionCenter = selection.normalizedRect.center
        let markerCenter = marker.normalizedRect.center
        return abs(selectionCenter.x - markerCenter.x) < 0.006
            && abs(selectionCenter.y - markerCenter.y) < 0.006
    }
}

private final class ScoreLayoutMarkerBadgeView: UIView {
    private let label = UILabel()
    private let lockImageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        isUserInteractionEnabled = false
        layer.cornerRadius = 5
        layer.borderWidth = 0.6
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.04
        layer.shadowRadius = 1
        layer.shadowOffset = .zero
        layer.zPosition = 120

        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.72
        addSubview(label)

        lockImageView.translatesAutoresizingMaskIntoConstraints = false
        lockImageView.contentMode = .scaleAspectFit
        lockImageView.isHidden = true
        addSubview(lockImageView)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
            lockImageView.widthAnchor.constraint(equalToConstant: 7),
            lockImageView.heightAnchor.constraint(equalToConstant: 7),
            lockImageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            lockImageView.topAnchor.constraint(equalTo: topAnchor, constant: 1)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(kind: ScoreLayoutMarkerKind, isSelected: Bool) {
        label.text = kind.glyph
        label.font = .systemFont(ofSize: kind.badgeFontSize, weight: .semibold)
        label.transform = kind == .system || kind == .systemLock
            ? CGAffineTransform(translationX: 0, y: -1.5)
            : .identity
        label.textColor = isSelected
            ? UIColor(red: 0.0, green: 0.28, blue: 0.62, alpha: 0.72)
            : UIColor(white: 0.32, alpha: 0.48)
        lockImageView.isHidden = kind != .systemLock
        lockImageView.image = UIImage(
            systemName: "lock.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 7, weight: .bold)
        )
        lockImageView.tintColor = isSelected
            ? UIColor(red: 0.0, green: 0.28, blue: 0.62, alpha: 0.62)
            : UIColor(white: 0.25, alpha: 0.44)
        backgroundColor = isSelected
            ? UIColor(red: 0.86, green: 0.93, blue: 1.0, alpha: 0.58)
            : UIColor(white: 0.97, alpha: 0.42)
        layer.borderColor = isSelected
            ? UIColor(red: 0.0, green: 0.34, blue: 0.68, alpha: 0.22).cgColor
            : UIColor(white: 0.55, alpha: 0.24).cgColor
        accessibilityLabel = kind.accessibilityLabel
    }
}

private extension ScoreLayoutMarkerKind {
    var badgeSize: CGSize {
        switch self {
        case .system:
            return CGSize(width: 18, height: 18)
        case .systemLock:
            return CGSize(width: 20, height: 18)
        case .page:
            return CGSize(width: 20, height: 18)
        case .section, .noBreak:
            return CGSize(width: 18, height: 18)
        }
    }

    var badgeFontSize: CGFloat {
        switch self {
        case .system, .systemLock:
            return 12
        case .page:
            return 11
        case .section, .noBreak:
            return 12
        }
    }

    var glyph: String {
        switch self {
        case .system, .systemLock:
            return "↵"
        case .page:
            return "□"
        case .section:
            return "§"
        case .noBreak:
            return "∞"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .system:
            return "System break"
        case .systemLock:
            return "Locked system break"
        case .page:
            return "Page break"
        case .section:
            return "Section break"
        case .noBreak:
            return "Keep bars together"
        }
    }
}

private extension ScoreNoteDuration {
    var noteEntryRestPreviewGlyph: String {
        switch self {
        case .whole:
            return "\u{1D13B}"
        case .half:
            return "\u{1D13C}"
        case .quarter:
            return "\u{1D13D}"
        case .eighth:
            return "\u{1D13E}"
        case .sixteenth:
            return "\u{1D13F}"
        }
    }
}
