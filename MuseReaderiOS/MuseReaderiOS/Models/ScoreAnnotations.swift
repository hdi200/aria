//
//  ScoreAnnotations.swift
//  MuseReaderiOS
//

import Combine
import CoreGraphics
import CryptoKit
import Foundation

enum ScoreAnnotationTool: String, Codable, CaseIterable, Sendable {
    case pen
    case highlighter
    case eraser
    case lasso

    var title: String {
        switch self {
        case .pen: return "Pen"
        case .highlighter: return "Highlighter"
        case .eraser: return "Eraser"
        case .lasso: return "Lasso"
        }
    }

    var systemImage: String {
        switch self {
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .eraser: return "eraser"
        case .lasso: return "lasso"
        }
    }

    var createsStroke: Bool {
        self == .pen || self == .highlighter
    }
}

enum ScoreAnnotationColor: String, Codable, CaseIterable, Sendable {
    case red
    case blue
    case green
    case yellow
    case black

    var rgba: ScoreAnnotationRGBA {
        switch self {
        case .red: return ScoreAnnotationRGBA(red: 0.93, green: 0.16, blue: 0.26, alpha: 0.96)
        case .blue: return ScoreAnnotationRGBA(red: 0.10, green: 0.39, blue: 0.91, alpha: 0.96)
        case .green: return ScoreAnnotationRGBA(red: 0.16, green: 0.67, blue: 0.34, alpha: 0.96)
        case .yellow: return ScoreAnnotationRGBA(red: 0.98, green: 0.73, blue: 0.10, alpha: 0.96)
        case .black: return ScoreAnnotationRGBA(red: 0.10, green: 0.11, blue: 0.10, alpha: 0.96)
        }
    }
}

struct ScoreAnnotationRGBA: Codable, Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
}

struct ScoreAnnotationPoint: Codable, Equatable, Sendable {
    var x: Double
    var y: Double

    init(_ point: CGPoint) {
        x = point.x
        y = point.y
    }

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

struct ScoreAnnotationRect: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(_ rect: ScoreNormalizedRect) {
        x = rect.x
        y = rect.y
        width = rect.width
        height = rect.height
    }

    var normalizedRect: ScoreNormalizedRect {
        ScoreNormalizedRect(x: x, y: y, width: width, height: height)
    }
}

struct ScoreAnnotationMeasureAnchor: Codable, Equatable, Sendable {
    let measureEID: String
    let fallbackMeasureIndex: Int
    let fallbackPageIndex: Int
    let sourceRect: ScoreAnnotationRect
    let previousMeasureEID: String?
    let nextMeasureEID: String?
}

struct ScoreAnnotationStroke: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let partID: String
    let fallbackPageIndex: Int
    var tool: ScoreAnnotationTool
    var color: ScoreAnnotationRGBA
    var width: Double
    var anchor: ScoreAnnotationMeasureAnchor?
    var points: [ScoreAnnotationPoint]
    var createdAt: Date
}

struct ScoreAnnotationDocument: Codable, Equatable, Sendable {
    var version = 1
    var strokes: [ScoreAnnotationStroke] = []
}

struct ScoreRenderedAnnotationStroke: Identifiable, Equatable, Sendable {
    let id: UUID
    let tool: ScoreAnnotationTool
    let color: ScoreAnnotationRGBA
    let width: Double
    let points: [CGPoint]
    let isOrphaned: Bool
}

private struct ScoreAnnotationStore {
    let scoreID: String
    private let fileManager = FileManager.default

    func load() -> ScoreAnnotationDocument {
        guard
            let data = try? Data(contentsOf: fileURL()),
            let document = try? JSONDecoder().decode(ScoreAnnotationDocument.self, from: data)
        else {
            return ScoreAnnotationDocument()
        }
        return document
    }

    func save(_ document: ScoreAnnotationDocument) throws {
        let destinationURL = fileURL()
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(document).write(to: destinationURL, options: .atomic)
    }

    private func fileURL() -> URL {
        let digest = SHA256.hash(data: Data(scoreID.utf8))
        let fileName = digest.map { String(format: "%02x", $0) }.joined() + ".json"
        let rootURL = (try? ManagedScoreLibraryPaths.privateRootURL())
            ?? fileManager.temporaryDirectory.appendingPathComponent(ManagedScoreLibraryPaths.privateRootDirectoryName, isDirectory: true)
        return rootURL
            .appendingPathComponent("Annotations", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }
}

@MainActor
final class ScoreAnnotationController: ObservableObject {
    @Published private(set) var document: ScoreAnnotationDocument
    @Published private(set) var selectedStrokeIDs: Set<UUID> = []
    @Published private(set) var saveErrorMessage: String?

    private let store: ScoreAnnotationStore
    private var undoStack: [[ScoreAnnotationStroke]] = []
    private var redoStack: [[ScoreAnnotationStroke]] = []
    private var saveTask: Task<Void, Never>?

    init(scoreID: String) {
        store = ScoreAnnotationStore(scoreID: scoreID)
        document = store.load()
    }

    deinit {
        saveTask?.cancel()
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var hasSelection: Bool { !selectedStrokeIDs.isEmpty }

    func renderedStrokes(
        pageIndex: Int,
        partID: String,
        regions: [ScorePlaybackMeasureRegion]
    ) -> [ScoreRenderedAnnotationStroke] {
        let visualRegions = Self.visualRegions(from: regions)
        return document.strokes.compactMap { stroke in
            guard stroke.partID == partID else { return nil }
            let resolved = Self.resolve(stroke: stroke, in: visualRegions)
            guard resolved.pageIndex == pageIndex else { return nil }
            return ScoreRenderedAnnotationStroke(
                id: stroke.id,
                tool: stroke.tool,
                color: stroke.color,
                width: stroke.width,
                points: resolved.points,
                isOrphaned: resolved.isOrphaned
            )
        }
    }

    func commitStroke(
        pageIndex: Int,
        partID: String,
        tool: ScoreAnnotationTool,
        color: ScoreAnnotationColor,
        width: Double,
        pagePoints: [CGPoint],
        regions: [ScorePlaybackMeasureRegion]
    ) {
        guard tool.createsStroke, !pagePoints.isEmpty else { return }
        let pageRegions = Self.visualRegions(from: regions).filter { $0.pageIndex == pageIndex }
        let allRegions = Self.visualRegions(from: regions)
        var groups: [(region: ScorePlaybackMeasureRegion?, points: [CGPoint])] = []

        for point in pagePoints {
            let region = Self.region(containingOrNearest: point, in: pageRegions)
            let currentIdentity = region.map(Self.regionIdentity)
            if let last = groups.indices.last,
               groups[last].region.map(Self.regionIdentity) == currentIdentity {
                groups[last].points.append(point)
            } else {
                if let previousPoint = groups.last?.points.last {
                    groups.append((region, [previousPoint, point]))
                } else {
                    groups.append((region, [point]))
                }
            }
        }

        recordUndoSnapshot()
        let rgba = color.rgba
        for group in groups where !group.points.isEmpty {
            let anchor = group.region.map { region in
                Self.anchor(for: region, allRegions: allRegions)
            }
            let localPoints = group.points.map { point -> ScoreAnnotationPoint in
                guard let sourceRect = anchor?.sourceRect.normalizedRect,
                      sourceRect.width > 0,
                      sourceRect.height > 0
                else {
                    return ScoreAnnotationPoint(point)
                }
                return ScoreAnnotationPoint(
                    CGPoint(
                        x: (point.x - sourceRect.x) / sourceRect.width,
                        y: (point.y - sourceRect.y) / sourceRect.height
                    )
                )
            }
            document.strokes.append(
                ScoreAnnotationStroke(
                    id: UUID(),
                    partID: partID,
                    fallbackPageIndex: pageIndex,
                    tool: tool,
                    color: rgba,
                    width: width,
                    anchor: anchor,
                    points: localPoints,
                    createdAt: Date()
                )
            )
        }
        selectedStrokeIDs.removeAll()
        scheduleSave()
    }

    func erase(
        pageIndex: Int,
        partID: String,
        along pagePoints: [CGPoint],
        regions: [ScorePlaybackMeasureRegion]
    ) {
        guard !pagePoints.isEmpty else { return }
        let renderedByID = Dictionary(
            uniqueKeysWithValues: renderedStrokes(pageIndex: pageIndex, partID: partID, regions: regions)
                .map { ($0.id, $0.points) }
        )
        var replacements: [UUID: [ScoreAnnotationStroke]] = [:]

        for stroke in document.strokes where stroke.partID == partID {
            guard let renderedPoints = renderedByID[stroke.id], renderedPoints.count == stroke.points.count else {
                continue
            }

            // Keep the eraser precise and split a line at the touched section.
            // This preserves the untouched ink on either side of the gesture.
            let erasedPoints = renderedPoints.indices.map { pointIndex in
                if Self.distance(from: renderedPoints[pointIndex], to: pagePoints) <= 0.012 {
                    return true
                }
                if pointIndex > 0,
                   Self.distance(
                       fromSegmentStart: renderedPoints[pointIndex - 1],
                       end: renderedPoints[pointIndex],
                       toPolyline: pagePoints
                   ) <= 0.012 {
                    return true
                }
                if pointIndex + 1 < renderedPoints.count,
                   Self.distance(
                       fromSegmentStart: renderedPoints[pointIndex],
                       end: renderedPoints[pointIndex + 1],
                       toPolyline: pagePoints
                   ) <= 0.012 {
                    return true
                }
                return false
            }
            guard erasedPoints.contains(true) else { continue }

            var retainedPointGroups: [[ScoreAnnotationPoint]] = []
            var currentGroup: [ScoreAnnotationPoint] = []
            for (point, isErased) in zip(stroke.points, erasedPoints) {
                if isErased {
                    if currentGroup.count >= 2 || (stroke.points.count == 1 && currentGroup.count == 1) {
                        retainedPointGroups.append(currentGroup)
                    }
                    currentGroup.removeAll(keepingCapacity: true)
                } else {
                    currentGroup.append(point)
                }
            }
            if currentGroup.count >= 2 || (stroke.points.count == 1 && currentGroup.count == 1) {
                retainedPointGroups.append(currentGroup)
            }

            replacements[stroke.id] = retainedPointGroups.map { retainedPoints in
                ScoreAnnotationStroke(
                    id: UUID(),
                    partID: stroke.partID,
                    fallbackPageIndex: stroke.fallbackPageIndex,
                    tool: stroke.tool,
                    color: stroke.color,
                    width: stroke.width,
                    anchor: stroke.anchor,
                    points: retainedPoints,
                    createdAt: stroke.createdAt
                )
            }
        }

        guard !replacements.isEmpty else { return }
        recordUndoSnapshot()
        document.strokes = document.strokes.flatMap { stroke in
            replacements[stroke.id] ?? [stroke]
        }
        selectedStrokeIDs.subtract(replacements.keys)
        scheduleSave()
    }

    func selectStrokes(
        pageIndex: Int,
        partID: String,
        in pageRect: CGRect,
        regions: [ScorePlaybackMeasureRegion]
    ) {
        guard pageRect.width > 0.002, pageRect.height > 0.002 else {
            selectedStrokeIDs.removeAll()
            return
        }
        selectedStrokeIDs = Set(
            renderedStrokes(pageIndex: pageIndex, partID: partID, regions: regions)
                .filter { stroke in stroke.points.contains(where: { pageRect.contains($0) }) }
                .map(\.id)
        )
    }

    func moveSelectedStrokes(
        by pageDelta: CGPoint,
        regions: [ScorePlaybackMeasureRegion]
    ) {
        guard !selectedStrokeIDs.isEmpty, pageDelta != .zero else { return }
        let visualRegions = Self.visualRegions(from: regions)
        recordUndoSnapshot()
        for index in document.strokes.indices where selectedStrokeIDs.contains(document.strokes[index].id) {
            if let anchor = document.strokes[index].anchor,
               let region = Self.region(for: anchor, in: visualRegions),
               region.normalizedRect.width > 0,
               region.normalizedRect.height > 0 {
                let localDelta = CGPoint(
                    x: pageDelta.x / region.normalizedRect.width,
                    y: pageDelta.y / region.normalizedRect.height
                )
                for pointIndex in document.strokes[index].points.indices {
                    document.strokes[index].points[pointIndex].x += localDelta.x
                    document.strokes[index].points[pointIndex].y += localDelta.y
                }
            } else {
                for pointIndex in document.strokes[index].points.indices {
                    document.strokes[index].points[pointIndex].x += pageDelta.x
                    document.strokes[index].points[pointIndex].y += pageDelta.y
                }
            }
        }
        scheduleSave()
    }

    func deleteSelection() {
        guard !selectedStrokeIDs.isEmpty else { return }
        recordUndoSnapshot()
        document.strokes.removeAll { selectedStrokeIDs.contains($0.id) }
        selectedStrokeIDs.removeAll()
        scheduleSave()
    }

    func clearSelection() {
        selectedStrokeIDs.removeAll()
    }

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(document.strokes)
        document.strokes = snapshot
        selectedStrokeIDs.removeAll()
        scheduleSave()
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(document.strokes)
        document.strokes = snapshot
        selectedStrokeIDs.removeAll()
        scheduleSave()
    }

    func flushSave() {
        saveTask?.cancel()
        saveTask = nil
        saveNow()
    }

    private func recordUndoSnapshot() {
        undoStack.append(document.strokes)
        if undoStack.count > 50 {
            undoStack.removeFirst(undoStack.count - 50)
        }
        redoStack.removeAll()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func saveNow() {
        do {
            try store.save(document)
            saveErrorMessage = nil
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private static func visualRegions(from regions: [ScorePlaybackMeasureRegion]) -> [ScorePlaybackMeasureRegion] {
        var seen: Set<String> = []
        return regions
            .sorted { lhs, rhs in
                lhs.measureIndex == rhs.measureIndex
                    ? lhs.startTimeSeconds < rhs.startTimeSeconds
                    : lhs.measureIndex < rhs.measureIndex
            }
            .filter { region in
                seen.insert(regionIdentity(region)).inserted
            }
    }

    private static func regionIdentity(_ region: ScorePlaybackMeasureRegion) -> String {
        region.measureEID.isEmpty ? "index:\(region.measureIndex)" : "eid:\(region.measureEID)"
    }

    private static func region(containingOrNearest point: CGPoint, in regions: [ScorePlaybackMeasureRegion]) -> ScorePlaybackMeasureRegion? {
        if let containing = regions.first(where: {
            $0.normalizedRect.contains(x: point.x, y: point.y)
        }) {
            return containing
        }
        return regions.min {
            $0.normalizedRect.distanceSquared(toX: point.x, y: point.y)
                < $1.normalizedRect.distanceSquared(toX: point.x, y: point.y)
        }
    }

    private static func anchor(
        for region: ScorePlaybackMeasureRegion,
        allRegions: [ScorePlaybackMeasureRegion]
    ) -> ScoreAnnotationMeasureAnchor {
        let previous = allRegions.last { $0.measureIndex < region.measureIndex }
        let next = allRegions.first { $0.measureIndex > region.measureIndex }
        return ScoreAnnotationMeasureAnchor(
            measureEID: region.measureEID,
            fallbackMeasureIndex: region.measureIndex,
            fallbackPageIndex: region.pageIndex,
            sourceRect: ScoreAnnotationRect(region.normalizedRect),
            previousMeasureEID: previous?.measureEID.trimmedToNil,
            nextMeasureEID: next?.measureEID.trimmedToNil
        )
    }

    private static func region(
        for anchor: ScoreAnnotationMeasureAnchor,
        in regions: [ScorePlaybackMeasureRegion]
    ) -> ScorePlaybackMeasureRegion? {
        if !anchor.measureEID.isEmpty,
           let exact = regions.first(where: { $0.measureEID == anchor.measureEID }) {
            return exact
        }
        return regions.first(where: { $0.measureIndex == anchor.fallbackMeasureIndex })
    }

    private static func resolve(
        stroke: ScoreAnnotationStroke,
        in regions: [ScorePlaybackMeasureRegion]
    ) -> (pageIndex: Int, points: [CGPoint], isOrphaned: Bool) {
        guard let anchor = stroke.anchor else {
            return (stroke.fallbackPageIndex, stroke.points.map(\.cgPoint), false)
        }

        let exactRegion = !anchor.measureEID.isEmpty
            ? regions.first(where: { $0.measureEID == anchor.measureEID })
            : nil
        let fallbackRegion = regions.first(where: { $0.measureIndex == anchor.fallbackMeasureIndex })
        let region = exactRegion ?? fallbackRegion
        let rect = region?.normalizedRect ?? anchor.sourceRect.normalizedRect
        let pageIndex = region?.pageIndex ?? anchor.fallbackPageIndex
        let points = stroke.points.map { point in
            CGPoint(
                x: rect.x + point.x * rect.width,
                y: rect.y + point.y * rect.height
            )
        }
        return (pageIndex, points, exactRegion == nil && !anchor.measureEID.isEmpty)
    }

    private static func distance(from point: CGPoint, to polyline: [CGPoint]) -> CGFloat {
        guard let first = polyline.first else { return .greatestFiniteMagnitude }
        guard polyline.count > 1 else { return hypot(point.x - first.x, point.y - first.y) }
        var best = CGFloat.greatestFiniteMagnitude
        for index in 1..<polyline.count {
            best = min(best, distance(from: point, toSegmentFrom: polyline[index - 1], to: polyline[index]))
        }
        return best
    }

    private static func distance(from point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - start.x, point.y - start.y) }
        let projection = min(max(((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared, 0), 1)
        let projected = CGPoint(x: start.x + projection * dx, y: start.y + projection * dy)
        return hypot(point.x - projected.x, point.y - projected.y)
    }

    private static func distance(
        fromSegmentStart start: CGPoint,
        end: CGPoint,
        toPolyline points: [CGPoint]
    ) -> CGFloat {
        guard let first = points.first else { return .greatestFiniteMagnitude }
        guard points.count > 1 else {
            return distance(from: first, toSegmentFrom: start, to: end)
        }

        var best = CGFloat.greatestFiniteMagnitude
        for index in 1..<points.count {
            let otherStart = points[index - 1]
            let otherEnd = points[index]
            if segmentsIntersect(start, end, otherStart, otherEnd) {
                return 0
            }
            best = min(
                best,
                distance(from: start, toSegmentFrom: otherStart, to: otherEnd),
                distance(from: end, toSegmentFrom: otherStart, to: otherEnd),
                distance(from: otherStart, toSegmentFrom: start, to: end),
                distance(from: otherEnd, toSegmentFrom: start, to: end)
            )
        }
        return best
    }

    private static func segmentsIntersect(
        _ firstStart: CGPoint,
        _ firstEnd: CGPoint,
        _ secondStart: CGPoint,
        _ secondEnd: CGPoint
    ) -> Bool {
        func cross(_ origin: CGPoint, _ first: CGPoint, _ second: CGPoint) -> CGFloat {
            (first.x - origin.x) * (second.y - origin.y)
                - (first.y - origin.y) * (second.x - origin.x)
        }

        let firstSideA = cross(firstStart, firstEnd, secondStart)
        let firstSideB = cross(firstStart, firstEnd, secondEnd)
        let secondSideA = cross(secondStart, secondEnd, firstStart)
        let secondSideB = cross(secondStart, secondEnd, firstEnd)
        let boundingBoxesOverlap = max(firstStart.x, firstEnd.x) >= min(secondStart.x, secondEnd.x)
            && max(secondStart.x, secondEnd.x) >= min(firstStart.x, firstEnd.x)
            && max(firstStart.y, firstEnd.y) >= min(secondStart.y, secondEnd.y)
            && max(secondStart.y, secondEnd.y) >= min(firstStart.y, firstEnd.y)
        return boundingBoxesOverlap
            && firstSideA * firstSideB <= 0
            && secondSideA * secondSideB <= 0
    }
}
