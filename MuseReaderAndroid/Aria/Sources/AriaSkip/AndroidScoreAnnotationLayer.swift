// Android's ScoreAnnotationOverlayView (iOS draws the strokes with Core Graphics): the
// page's annotation strokes, the stroke being drawn, the lasso rectangle and the
// selection outline, in SwiftUI paths over the zoomed page.

// Not limited to Android: the Skip project's own iOS build (a build step only; the iOS
// app is MuseReaderiOS/Aria.xcodeproj) compiles it in place of the held-back iOS file.
import SwiftUI

struct AndroidScoreAnnotationLayer: View {
    let strokes: [ScoreRenderedAnnotationStroke]
    let selectedStrokeIDs: Set<UUID>
    let isVisible: Bool
    let pageSize: CGSize
    /// The stroke being drawn (normalized points), with its tool, color and width.
    let previewTool: ScoreAnnotationTool?
    let previewColor: ScoreAnnotationRGBA
    let previewWidth: Double
    let previewPoints: [CGPoint]
    /// How far the selected strokes are being moved (normalized).
    let selectionTranslation: CGPoint

    /// iOS composites highlighters at this alpha in one layer, so overlaps don't darken.
    static let highlighterAlpha = 0.30

    var body: some View {
        ZStack(alignment: .topLeading) {
            if isVisible {
                let highlighters = strokes.filter { $0.tool == .highlighter }
                let previewsHighlighter = previewTool == .highlighter && !previewPoints.isEmpty
                if !highlighters.isEmpty || previewsHighlighter {
                    ZStack(alignment: .topLeading) {
                        ForEach(highlighters) { stroke in
                            strokeView(points: stroke.points, color: stroke.color, alpha: 1, width: stroke.width,
                                       translation: translation(for: stroke))
                        }
                        if previewsHighlighter {
                            strokeView(points: previewPoints, color: previewColor, alpha: 1, width: previewWidth, translation: .zero)
                        }
                    }
                    .opacity(Self.highlighterAlpha)
                }
                ForEach(strokes.filter { $0.tool != .highlighter }) { stroke in
                    strokeView(points: stroke.points, color: stroke.color, alpha: stroke.color.alpha, width: stroke.width,
                               translation: translation(for: stroke))
                }
                ForEach(strokes.filter(\.isOrphaned)) { stroke in
                    if let first = stroke.points.first {
                        let t = translation(for: stroke)
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 8, height: 8)
                            .offset(x: (first.x + t.x) * pageSize.width - 4, y: (first.y + t.y) * pageSize.height - 4)
                    }
                }
                previewView
                if let bounds = selectionBounds {
                    Rectangle()
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .frame(width: bounds.width + 14, height: bounds.height + 14)
                        .offset(x: bounds.minX - 7 + selectionTranslation.x * pageSize.width,
                                y: bounds.minY - 7 + selectionTranslation.y * pageSize.height)
                }
            }
        }
        .frame(width: pageSize.width, height: pageSize.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var previewView: some View {
        if let previewTool, let first = previewPoints.first {
            switch previewTool {
            case .pen:
                strokeView(points: previewPoints, color: previewColor, alpha: previewColor.alpha, width: previewWidth, translation: .zero)
            case .eraser:
                // iOS cuts the eraser's path out of the strokes as a preview; Android shows it.
                let diameter = max(pageSize.width * 0.024, 12)
                path(for: previewPoints, translation: .zero)
                    .stroke(Color.gray.opacity(0.35), style: StrokeStyle(lineWidth: diameter, lineCap: .round, lineJoin: .round))
            case .lasso:
                if let last = previewPoints.last {
                    let rect = CGRect(x: min(first.x, last.x) * pageSize.width, y: min(first.y, last.y) * pageSize.height,
                                      width: abs(last.x - first.x) * pageSize.width, height: abs(last.y - first.y) * pageSize.height)
                    Rectangle()
                        .fill(Color.blue.opacity(0.07))
                        .overlay(Rectangle().stroke(Color.blue, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                        .frame(width: max(rect.width, 1), height: max(rect.height, 1))
                        .offset(x: rect.minX, y: rect.minY)
                }
            case .highlighter:
                EmptyView()
            }
        }
    }

    private func strokeView(points: [CGPoint], color: ScoreAnnotationRGBA, alpha: Double, width: Double,
                            translation: CGPoint) -> some View {
        let lineWidth = max(width * pageSize.width, 0.5)
        let swiftUIColor = Color(red: color.red, green: color.green, blue: color.blue).opacity(alpha)
        return path(for: points, translation: translation)
            .stroke(swiftUIColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }

    private func path(for points: [CGPoint], translation: CGPoint) -> Path {
        var path = Path()
        let projected = points.map {
            CGPoint(x: ($0.x + translation.x) * pageSize.width, y: ($0.y + translation.y) * pageSize.height)
        }
        guard let first = projected.first else { return path }
        path.move(to: first)
        if projected.count == 1 {
            // A dot: a zero-length round-capped line.
            path.addLine(to: CGPoint(x: first.x + 0.01, y: first.y))
        } else {
            for point in projected.dropFirst() {
                path.addLine(to: point)
            }
        }
        return path
    }

    private func translation(for stroke: ScoreRenderedAnnotationStroke) -> CGPoint {
        selectedStrokeIDs.contains(stroke.id) ? selectionTranslation : .zero
    }

    /// The selected strokes' bounds in page points (iOS normalizedSelectionBounds).
    var selectionBounds: CGRect? {
        Self.selectionBounds(strokes: strokes, selected: selectedStrokeIDs, pageSize: pageSize)
    }

    static func selectionBounds(strokes: [ScoreRenderedAnnotationStroke], selected: Set<UUID>, pageSize: CGSize) -> CGRect? {
        let points = strokes.filter { selected.contains($0.id) }.flatMap(\.points)
        guard let first = points.first else { return nil }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX * pageSize.width, y: minY * pageSize.height,
                      width: max((maxX - minX) * pageSize.width, 1), height: max((maxY - minY) * pageSize.height, 1))
    }
}
