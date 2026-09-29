//
//  ScoreAnnotationOverlayView.swift
//  MuseReaderiOS
//

import UIKit

final class ScoreAnnotationGestureRecognizer: UIGestureRecognizer {
    private(set) var locations: [CGPoint] = []
    private(set) var beganWithPencil = false
    private weak var trackedTouch: UITouch?

    override func reset() {
        super.reset()
        locations.removeAll(keepingCapacity: true)
        beganWithPencil = false
        trackedTouch = nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard trackedTouch == nil else {
            state = .cancelled
            return
        }
        guard let touch = touches.first, let view else {
            state = .failed
            return
        }
        trackedTouch = touch
        beganWithPencil = touch.type == .pencil
        append(touch: touch, event: event, in: view)
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = trackedTouch, touches.contains(touch), let view else { return }
        append(touch: touch, event: event, in: view)
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = trackedTouch, touches.contains(touch), let view else { return }
        append(touch: touch, event: event, in: view)
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .cancelled
    }

    private func append(touch: UITouch, event: UIEvent, in view: UIView) {
        let samples = event.coalescedTouches(for: touch) ?? [touch]
        for sample in samples {
            let point = sample.type == .pencil
                ? sample.preciseLocation(in: view)
                : sample.location(in: view)
            if let last = locations.last, hypot(last.x - point.x, last.y - point.y) < 0.35 {
                continue
            }
            locations.append(point)
        }
    }
}

final class ScoreAnnotationOverlayView: UIView {
    var strokes: [ScoreRenderedAnnotationStroke] = [] {
        didSet { setNeedsDisplay() }
    }
    var selectedStrokeIDs: Set<UUID> = [] {
        didSet { setNeedsDisplay() }
    }
    var annotationsVisible = true {
        didSet { setNeedsDisplay() }
    }
    var previewTool: ScoreAnnotationTool?
    var previewColor = ScoreAnnotationColor.red.rgba
    var previewWidth: Double = 4
    var previewPoints: [CGPoint] = []
    var selectionTranslation = CGPoint.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard annotationsVisible, let context = UIGraphicsGetCurrentContext() else { return }
        for stroke in strokes {
            let translation = selectedStrokeIDs.contains(stroke.id) ? selectionTranslation : .zero
            draw(
                points: stroke.points,
                tool: stroke.tool,
                color: stroke.color,
                width: stroke.width,
                translation: translation,
                in: context
            )
            if stroke.isOrphaned {
                drawOrphanIndicator(for: stroke.points, translation: translation, in: context)
            }
        }

        if let previewTool, !previewPoints.isEmpty {
            if previewTool == .lasso {
                drawLassoPreview(in: context)
            } else if previewTool == .eraser {
                drawEraserPreview(in: context)
            } else if previewTool.createsStroke {
                draw(
                    points: previewPoints,
                    tool: previewTool,
                    color: previewColor,
                    width: previewWidth,
                    translation: .zero,
                    in: context
                )
            }
        }

        if let selectionBounds = normalizedSelectionBounds {
            context.saveGState()
            context.setStrokeColor(UIColor.systemBlue.cgColor)
            context.setLineWidth(1.5)
            context.setLineDash(phase: 0, lengths: [5, 4])
            context.stroke(selectionBounds.insetBy(dx: -7, dy: -7).offsetBy(dx: selectionTranslation.x * bounds.width, dy: selectionTranslation.y * bounds.height))
            context.restoreGState()
        }
    }

    var normalizedSelectionBounds: CGRect? {
        let selectedPoints = strokes
            .filter { selectedStrokeIDs.contains($0.id) }
            .flatMap(\.points)
        guard let first = selectedPoints.first else { return nil }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in selectedPoints.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGRect(
            x: minX * bounds.width,
            y: minY * bounds.height,
            width: max((maxX - minX) * bounds.width, 1),
            height: max((maxY - minY) * bounds.height, 1)
        )
    }

    func setPreview(
        tool: ScoreAnnotationTool?,
        color: ScoreAnnotationRGBA,
        width: Double,
        points: [CGPoint],
        selectionTranslation: CGPoint = .zero
    ) {
        previewTool = tool
        previewColor = color
        previewWidth = width
        previewPoints = points
        self.selectionTranslation = selectionTranslation
        setNeedsDisplay()
    }

    func clearPreview() {
        previewTool = nil
        previewPoints = []
        selectionTranslation = .zero
        setNeedsDisplay()
    }

    private func draw(
        points: [CGPoint],
        tool: ScoreAnnotationTool,
        color: ScoreAnnotationRGBA,
        width: Double,
        translation: CGPoint,
        in context: CGContext
    ) {
        guard let first = points.first else { return }
        let projected = points.map {
            CGPoint(
                x: ($0.x + translation.x) * bounds.width,
                y: ($0.y + translation.y) * bounds.height
            )
        }
        let uiColor = UIColor(
            red: CGFloat(color.red),
            green: CGFloat(color.green),
            blue: CGFloat(color.blue),
            alpha: CGFloat(tool == .highlighter ? 0.30 : color.alpha)
        )
        context.saveGState()
        context.setStrokeColor(uiColor.cgColor)
        context.setFillColor(uiColor.cgColor)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(tool == .highlighter ? max(width * 3.2, 14) : width)
        if projected.count == 1 {
            let radius = max(CGFloat(width) * 0.5, 1)
            context.fillEllipse(in: CGRect(x: projected[0].x - radius, y: projected[0].y - radius, width: radius * 2, height: radius * 2))
        } else {
            context.beginPath()
            context.move(to: CGPoint(x: first.x * bounds.width + translation.x * bounds.width, y: first.y * bounds.height + translation.y * bounds.height))
            for point in projected.dropFirst() {
                context.addLine(to: point)
            }
            context.strokePath()
        }
        context.restoreGState()
    }

    private func drawLassoPreview(in context: CGContext) {
        guard let first = previewPoints.first, let last = previewPoints.last else { return }
        let selectionRect = CGRect(
            x: min(first.x, last.x) * bounds.width,
            y: min(first.y, last.y) * bounds.height,
            width: abs(last.x - first.x) * bounds.width,
            height: abs(last.y - first.y) * bounds.height
        )
        context.saveGState()
        context.setStrokeColor(UIColor.systemBlue.cgColor)
        context.setFillColor(UIColor.systemBlue.withAlphaComponent(0.07).cgColor)
        context.setLineWidth(1.5)
        context.setLineDash(phase: 0, lengths: [5, 4])
        context.fill(selectionRect)
        context.stroke(selectionRect)
        context.restoreGState()
    }

    private func drawEraserPreview(in context: CGContext) {
        let projected = previewPoints.map {
            CGPoint(x: $0.x * bounds.width, y: $0.y * bounds.height)
        }
        guard let first = projected.first else { return }
        let diameter = max(bounds.width * 0.024, 12)

        context.saveGState()
        context.setBlendMode(.clear)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(diameter)
        if projected.count == 1 {
            context.fillEllipse(
                in: CGRect(
                    x: first.x - diameter / 2,
                    y: first.y - diameter / 2,
                    width: diameter,
                    height: diameter
                )
            )
        } else {
            context.beginPath()
            context.move(to: first)
            for point in projected.dropFirst() {
                context.addLine(to: point)
            }
            context.strokePath()
        }
        context.restoreGState()
    }

    private func drawOrphanIndicator(for points: [CGPoint], translation: CGPoint, in context: CGContext) {
        guard let first = points.first else { return }
        let center = CGPoint(
            x: (first.x + translation.x) * bounds.width,
            y: (first.y + translation.y) * bounds.height
        )
        context.saveGState()
        context.setFillColor(UIColor.systemOrange.cgColor)
        context.fillEllipse(in: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8))
        context.restoreGState()
    }
}
