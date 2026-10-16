//
//  ScoreReaderZoomModels.swift
//  MuseReaderiOS
//
//  Page zoom and layout math for the score page viewer (ZoomableImageView).
//

import UIKit

enum ScoreReaderZoomLimits {
    static let minimumScale: CGFloat = 1
}

enum ScoreReaderPageHorizontalAlignment: Equatable {
    case leading
    case center
    case trailing
}

enum ScoreReaderReadingGesturePolicy {
    static let allowsDoubleTapZoom = false
}

struct ScoreReaderZoomLayout {
    static func contentInsets(
        viewportSize: CGSize,
        pageSize: CGSize,
        zoomScale: CGFloat,
        horizontalAlignment: ScoreReaderPageHorizontalAlignment,
        centersVertically: Bool,
        restingHorizontalEdgePadding: CGFloat = 0,
        restingTopInset: CGFloat = 0
    ) -> UIEdgeInsets {
        let horizontalSpace = max(viewportSize.width - pageSize.width * zoomScale, 0)
        let verticalSpace = max(viewportSize.height - pageSize.height * zoomScale, 0)
        let left: CGFloat
        let right: CGFloat

        switch horizontalAlignment {
        case .leading:
            left = min(restingHorizontalEdgePadding, horizontalSpace)
            right = horizontalSpace - left
        case .center:
            left = horizontalSpace * 0.5
            right = horizontalSpace * 0.5
        case .trailing:
            right = min(restingHorizontalEdgePadding, horizontalSpace)
            left = horizontalSpace - right
        }

        let verticalInset = centersVertically ? verticalSpace * 0.5 : 0
        let restingInsetProgress = max(0, min(1, 2 - zoomScale))
        let top = centersVertically ? verticalInset : restingTopInset * restingInsetProgress
        return UIEdgeInsets(top: top, left: left, bottom: verticalInset, right: right)
    }

    static func clampedContentOffset(
        _ contentOffset: CGPoint,
        contentSize: CGSize,
        viewportSize: CGSize,
        contentInset: UIEdgeInsets
    ) -> CGPoint {
        let minOffset = CGPoint(x: -contentInset.left, y: -contentInset.top)
        let maxOffset = CGPoint(
            x: max(contentSize.width - viewportSize.width + contentInset.right, minOffset.x),
            y: max(contentSize.height - viewportSize.height + contentInset.bottom, minOffset.y)
        )
        return CGPoint(
            x: min(max(contentOffset.x, minOffset.x), maxOffset.x),
            y: min(max(contentOffset.y, minOffset.y), maxOffset.y)
        )
    }
}

struct ScoreReaderZoomViewport: Equatable {
    var zoomScale: CGFloat = 1
    var contentOrigin: CGPoint = .zero
    var contentSize: CGSize = .zero
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
