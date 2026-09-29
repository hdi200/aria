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

    /// Converts a palette width, in points on a page shown at the reference
    /// width, to a line width stored as a fraction of the page width. Ink then
    /// keeps its size relative to the notation in every page layout.
    func lineWidth(forPaletteWidth paletteWidth: Double) -> Double {
        let points = self == .highlighter ? max(paletteWidth * 3.2, 14) : paletteWidth
        return points / ScoreAnnotationStroke.referencePageWidth
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
    /// The measure's page rect when the stroke was drawn.
    let sourceRect: ScoreAnnotationRect
    /// Page point the stroke's shape hangs from. After reflow it keeps its
    /// relative position in the measure, and the shape around it scales
    /// uniformly with the measure height so ink is never stretched.
    var origin: ScoreAnnotationPoint
}

struct ScoreAnnotationStroke: Identifiable, Codable, Equatable, Sendable {
    /// Page width, in points, at which palette widths are drawn at face value.
    static let referencePageWidth: Double = 800

    let id: UUID
    /// Shared by the per-measure pieces of one gesture so they select, move
    /// and delete together.
    var groupID: UUID
    let partID: String
    let fallbackPageIndex: Int
    var tool: ScoreAnnotationTool
    var color: ScoreAnnotationRGBA
    /// Line width as a fraction of the page width.
    var width: Double
    var anchor: ScoreAnnotationMeasureAnchor?
    /// Normalized page points in the layout the stroke was drawn in.
    var points: [ScoreAnnotationPoint]
    var createdAt: Date
}

struct ScoreAnnotationDocument: Codable, Equatable, Sendable {
    static let currentVersion = 2

    var version = currentVersion
    var strokes: [ScoreAnnotationStroke] = []
}

struct ScoreRenderedAnnotationStroke: Identifiable, Equatable, Sendable {
    let id: UUID
    let tool: ScoreAnnotationTool
    let color: ScoreAnnotationRGBA
    /// Line width as a fraction of the page width.
    let width: Double
    let points: [CGPoint]
    let isOrphaned: Bool
}

private struct ScoreAnnotationLoadResult {
    var document = ScoreAnnotationDocument()
    var isWritable = true
    var needsSave = false
    var message: String?
}

private struct ScoreAnnotationStore {
    let fileURL: URL
    /// Files written before annotations were keyed by library-relative path.
    let legacyFileURL: URL
    private let fileManager = FileManager.default

    init(documentURL: URL) {
        let documentPath = documentURL.standardizedFileURL.path
        let key: String
        if let relativePath = try? ManagedScoreLibrary().relativePath(for: documentURL), !relativePath.isEmpty {
            // Library-relative, so the key survives app container path changes.
            key = "library:" + relativePath
        } else {
            key = "file:" + documentPath
        }

        let rootURL = (try? ManagedScoreLibraryPaths.privateRootURL())
            ?? FileManager.default.temporaryDirectory.appendingPathComponent(ManagedScoreLibraryPaths.privateRootDirectoryName, isDirectory: true)
        let directoryURL = rootURL.appendingPathComponent("Annotations", isDirectory: true)
        fileURL = directoryURL.appendingPathComponent(Self.fileName(for: key), isDirectory: false)
        legacyFileURL = directoryURL.appendingPathComponent(Self.fileName(for: documentPath), isDirectory: false)
    }

    func load() -> ScoreAnnotationLoadResult {
        let sourceURL: URL
        let isLegacy: Bool
        if fileManager.fileExists(atPath: fileURL.path) {
            sourceURL = fileURL
            isLegacy = false
        } else if fileManager.fileExists(atPath: legacyFileURL.path) {
            sourceURL = legacyFileURL
            isLegacy = true
        } else {
            return ScoreAnnotationLoadResult()
        }

        let data: Data
        do {
            data = try Data(contentsOf: sourceURL)
        } catch {
            // The file may still be fine; never overwrite what could not be read.
            return ScoreAnnotationLoadResult(isWritable: false, message: "Annotations could not be read, so changes won't be saved.")
        }

        let decoder = JSONDecoder()
        guard let version = try? decoder.decode(VersionProbe.self, from: data).version else {
            return setAside(sourceURL)
        }
        if version > ScoreAnnotationDocument.currentVersion {
            return ScoreAnnotationLoadResult(
                isWritable: false,
                message: "These annotations were made by a newer version of Aria and can't be edited here."
            )
        }

        let document: ScoreAnnotationDocument
        do {
            if version == 1 {
                document = try decoder.decode(LegacyDocumentV1.self, from: data).migrated()
            } else {
                document = try decoder.decode(ScoreAnnotationDocument.self, from: data)
            }
        } catch {
            return setAside(sourceURL)
        }
        return ScoreAnnotationLoadResult(document: document, needsSave: isLegacy || version != ScoreAnnotationDocument.currentVersion)
    }

    func save(_ document: ScoreAnnotationDocument) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(document).write(to: fileURL, options: .atomic)
        if legacyFileURL != fileURL, fileManager.fileExists(atPath: legacyFileURL.path) {
            try? fileManager.removeItem(at: legacyFileURL)
        }
    }

    /// Keeps an undecodable file next to the store instead of overwriting it.
    private func setAside(_ url: URL) -> ScoreAnnotationLoadResult {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let keptURL = url.deletingPathExtension()
            .appendingPathExtension("unreadable-\(formatter.string(from: Date()))")
            .appendingPathExtension("json")
        do {
            try fileManager.moveItem(at: url, to: keptURL)
        } catch {
            return ScoreAnnotationLoadResult(isWritable: false, message: "Annotations could not be read, so changes won't be saved.")
        }
        return ScoreAnnotationLoadResult(message: "Earlier annotations could not be read and were kept aside.")
    }

    private static func fileName(for key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined() + ".json"
    }

    private struct VersionProbe: Decodable {
        let version: Int
    }
}

/// Version 1 stored measure-relative points and widths in screen points.
private struct LegacyDocumentV1: Decodable {
    struct Anchor: Decodable {
        let measureEID: String
        let fallbackMeasureIndex: Int
        let fallbackPageIndex: Int
        let sourceRect: ScoreAnnotationRect
    }

    struct Stroke: Decodable {
        let id: UUID
        let partID: String
        let fallbackPageIndex: Int
        let tool: ScoreAnnotationTool
        let color: ScoreAnnotationRGBA
        let width: Double
        let anchor: Anchor?
        let points: [ScoreAnnotationPoint]
        let createdAt: Date
    }

    let strokes: [Stroke]

    func migrated() -> ScoreAnnotationDocument {
        ScoreAnnotationDocument(strokes: strokes.map { stroke in
            let source = stroke.anchor?.sourceRect
            let pagePoints = stroke.points.map { point -> CGPoint in
                guard let source, source.width > 0, source.height > 0 else { return point.cgPoint }
                return CGPoint(x: source.x + point.x * source.width, y: source.y + point.y * source.height)
            }
            return ScoreAnnotationStroke(
                id: stroke.id,
                groupID: stroke.id,
                partID: stroke.partID,
                fallbackPageIndex: stroke.fallbackPageIndex,
                tool: stroke.tool,
                color: stroke.color,
                width: stroke.tool.lineWidth(forPaletteWidth: stroke.width),
                anchor: stroke.anchor.map { anchor in
                    ScoreAnnotationMeasureAnchor(
                        measureEID: anchor.measureEID,
                        fallbackMeasureIndex: anchor.fallbackMeasureIndex,
                        fallbackPageIndex: anchor.fallbackPageIndex,
                        sourceRect: anchor.sourceRect,
                        origin: ScoreAnnotationPoint(ScoreAnnotationGeometry.boundsCenter(of: pagePoints))
                    )
                },
                points: pagePoints.map(ScoreAnnotationPoint.init),
                createdAt: stroke.createdAt
            )
        })
    }
}

/// Measure regions deduplicated across repeats, with lookups for anchors.
private struct ScoreAnnotationRegionIndex {
    let regions: [ScorePlaybackMeasureRegion]
    private let regionsByEID: [String: ScorePlaybackMeasureRegion]
    private let regionsByMeasureIndex: [Int: ScorePlaybackMeasureRegion]

    init(_ playbackRegions: [ScorePlaybackMeasureRegion]) {
        var seen: Set<String> = []
        regions = playbackRegions
            .sorted { lhs, rhs in
                lhs.measureIndex == rhs.measureIndex
                    ? lhs.startTimeSeconds < rhs.startTimeSeconds
                    : lhs.measureIndex < rhs.measureIndex
            }
            .filter { seen.insert(Self.identity(of: $0)).inserted }
        regionsByEID = Dictionary(
            regions.filter { !$0.measureEID.isEmpty }.map { ($0.measureEID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        regionsByMeasureIndex = Dictionary(
            regions.map { ($0.measureIndex, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    static func identity(of region: ScorePlaybackMeasureRegion) -> String {
        region.measureEID.isEmpty ? "index:\(region.measureIndex)" : "eid:\(region.measureEID)"
    }

    func regions(onPage pageIndex: Int) -> [ScorePlaybackMeasureRegion] {
        regions.filter { $0.pageIndex == pageIndex }
    }

    func region(for anchor: ScoreAnnotationMeasureAnchor) -> (region: ScorePlaybackMeasureRegion?, isExact: Bool) {
        if !anchor.measureEID.isEmpty, let exact = regionsByEID[anchor.measureEID] {
            return (exact, true)
        }
        return (regionsByMeasureIndex[anchor.fallbackMeasureIndex], false)
    }
}

private enum ScoreAnnotationGeometry {
    static func boundsCenter(of points: [CGPoint]) -> CGPoint {
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
    }
}

@MainActor
final class ScoreAnnotationController: ObservableObject {
    @Published private(set) var document: ScoreAnnotationDocument {
        didSet { renderCache = nil }
    }
    @Published private(set) var selectedStrokeIDs: Set<UUID> = []
    @Published private(set) var saveErrorMessage: String?
    /// False when the stored file can't be safely overwritten.
    let isEditable: Bool

    private let store: ScoreAnnotationStore
    private var undoStack: [[ScoreAnnotationStroke]] = []
    private var redoStack: [[ScoreAnnotationStroke]] = []
    private var saveTask: Task<Void, Never>?
    /// Strokes drawn before measure geometry arrived; anchored once it does.
    private var unanchoredStrokeIDs: Set<UUID> = []
    private var renderCache: RenderCache?

    private struct RenderCache {
        let partID: String
        let regions: [ScorePlaybackMeasureRegion]
        let strokesByPage: [Int: [ScoreRenderedAnnotationStroke]]
    }

    init(documentURL: URL) {
        store = ScoreAnnotationStore(documentURL: documentURL)
        let result = store.load()
        document = result.document
        isEditable = result.isWritable
        saveErrorMessage = result.message
        if result.needsSave {
            saveNow()
        }
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
        if let renderCache, renderCache.partID == partID, renderCache.regions == regions {
            return renderCache.strokesByPage[pageIndex] ?? []
        }

        let regionIndex = ScoreAnnotationRegionIndex(regions)
        var strokesByPage: [Int: [ScoreRenderedAnnotationStroke]] = [:]
        for stroke in document.strokes where stroke.partID == partID {
            let resolved = Self.resolve(stroke: stroke, in: regionIndex)
            strokesByPage[resolved.pageIndex, default: []].append(
                ScoreRenderedAnnotationStroke(
                    id: stroke.id,
                    tool: stroke.tool,
                    color: stroke.color,
                    width: stroke.width * resolved.scale,
                    points: resolved.points,
                    isOrphaned: resolved.isOrphaned
                )
            )
        }
        renderCache = RenderCache(partID: partID, regions: regions, strokesByPage: strokesByPage)
        return strokesByPage[pageIndex] ?? []
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
        guard isEditable, tool.createsStroke, !pagePoints.isEmpty else { return }
        let template = ScoreAnnotationStroke(
            id: UUID(),
            groupID: UUID(),
            partID: partID,
            fallbackPageIndex: pageIndex,
            tool: tool,
            color: color.rgba,
            width: tool.lineWidth(forPaletteWidth: width),
            anchor: nil,
            points: pagePoints.map(ScoreAnnotationPoint.init),
            createdAt: Date()
        )
        let strokes = Self.anchoredPieces(of: template, in: ScoreAnnotationRegionIndex(regions))

        recordUndoSnapshot()
        document.strokes.append(contentsOf: strokes)
        if regions.isEmpty {
            unanchoredStrokeIDs.formUnion(strokes.map(\.id))
        }
        selectedStrokeIDs.removeAll()
        scheduleSave()
    }

    /// Anchors strokes drawn before the measure geometry finished loading.
    func anchorPendingStrokes(partID: String, regions: [ScorePlaybackMeasureRegion]) {
        guard isEditable, !unanchoredStrokeIDs.isEmpty, !regions.isEmpty else { return }
        let regionIndex = ScoreAnnotationRegionIndex(regions)
        var anchoredIDs: Set<UUID> = []
        func anchorPending(in strokes: [ScoreAnnotationStroke]) -> [ScoreAnnotationStroke] {
            strokes.flatMap { stroke -> [ScoreAnnotationStroke] in
                guard unanchoredStrokeIDs.contains(stroke.id), stroke.anchor == nil, stroke.partID == partID else {
                    return [stroke]
                }
                anchoredIDs.insert(stroke.id)
                return Self.anchoredPieces(of: stroke, in: regionIndex)
            }
        }

        // Rewrite history too, so undo never brings back an unanchored copy.
        document.strokes = anchorPending(in: document.strokes)
        undoStack = undoStack.map(anchorPending)
        redoStack = redoStack.map(anchorPending)
        guard !anchoredIDs.isEmpty else { return }
        unanchoredStrokeIDs.subtract(anchoredIDs)
        selectedStrokeIDs.subtract(anchoredIDs)
        scheduleSave()
    }

    func erase(
        pageIndex: Int,
        partID: String,
        along pagePoints: [CGPoint],
        regions: [ScorePlaybackMeasureRegion]
    ) {
        guard isEditable, !pagePoints.isEmpty else { return }
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

            // Fragments keep the anchor origin so they stay aligned after reflow.
            replacements[stroke.id] = retainedPointGroups.map { retainedPoints in
                ScoreAnnotationStroke(
                    id: UUID(),
                    groupID: stroke.groupID,
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
        guard isEditable, pageRect.width > 0.002, pageRect.height > 0.002 else {
            selectedStrokeIDs.removeAll()
            return
        }
        let hitIDs = Set(
            renderedStrokes(pageIndex: pageIndex, partID: partID, regions: regions)
                .filter { stroke in stroke.points.contains(where: { pageRect.contains($0) }) }
                .map(\.id)
        )
        // Select whole gestures, including pieces in other measures.
        let hitGroupIDs = Set(document.strokes.filter { hitIDs.contains($0.id) }.map(\.groupID))
        selectedStrokeIDs = Set(
            document.strokes
                .filter { $0.partID == partID && hitGroupIDs.contains($0.groupID) }
                .map(\.id)
        )
    }

    func moveSelectedStrokes(
        by pageDelta: CGPoint,
        regions: [ScorePlaybackMeasureRegion]
    ) {
        guard isEditable, !selectedStrokeIDs.isEmpty, pageDelta != .zero else { return }
        let regionIndex = ScoreAnnotationRegionIndex(regions)
        recordUndoSnapshot()
        for index in document.strokes.indices where selectedStrokeIDs.contains(document.strokes[index].id) {
            var stroke = document.strokes[index]
            // Stored points are in the drawing-time layout. Convert the on-screen
            // delta back through the measure's current-to-source size ratio.
            var storedDelta = pageDelta
            if var anchor = stroke.anchor {
                let source = anchor.sourceRect.normalizedRect
                if let region = regionIndex.region(for: anchor).region,
                   region.normalizedRect.width > 0,
                   region.normalizedRect.height > 0 {
                    storedDelta = CGPoint(
                        x: pageDelta.x * source.width / region.normalizedRect.width,
                        y: pageDelta.y * source.height / region.normalizedRect.height
                    )
                }
                anchor.origin.x += storedDelta.x
                anchor.origin.y += storedDelta.y
                stroke.anchor = anchor
            }
            for pointIndex in stroke.points.indices {
                stroke.points[pointIndex].x += storedDelta.x
                stroke.points[pointIndex].y += storedDelta.y
            }
            document.strokes[index] = stroke
        }
        scheduleSave()
    }

    func deleteSelection() {
        guard isEditable, !selectedStrokeIDs.isEmpty else { return }
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
        guard saveTask != nil else { return }
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
            self?.saveTask = nil
            self?.saveNow()
        }
    }

    private func saveNow() {
        guard isEditable else { return }
        do {
            try store.save(document)
            saveErrorMessage = nil
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    /// Splits a page-relative stroke into one anchored piece per measure it
    /// crosses. Pieces share the stroke's group, width and creation time.
    private static func anchoredPieces(
        of stroke: ScoreAnnotationStroke,
        in regionIndex: ScoreAnnotationRegionIndex
    ) -> [ScoreAnnotationStroke] {
        let pageRegions = regionIndex.regions(onPage: stroke.fallbackPageIndex)
        guard !pageRegions.isEmpty else { return [stroke] }

        var groups: [(region: ScorePlaybackMeasureRegion, points: [CGPoint])] = []
        for point in stroke.points.map(\.cgPoint) {
            guard let region = region(containingOrNearest: point, in: pageRegions) else { continue }
            if let last = groups.indices.last,
               ScoreAnnotationRegionIndex.identity(of: groups[last].region) == ScoreAnnotationRegionIndex.identity(of: region) {
                groups[last].points.append(point)
            } else if let previousPoint = groups.last?.points.last {
                // Start at the previous point so the pieces join without a gap.
                groups.append((region, [previousPoint, point]))
            } else {
                groups.append((region, [point]))
            }
        }

        return groups.map { group in
            ScoreAnnotationStroke(
                id: UUID(),
                groupID: stroke.groupID,
                partID: stroke.partID,
                fallbackPageIndex: stroke.fallbackPageIndex,
                tool: stroke.tool,
                color: stroke.color,
                width: stroke.width,
                anchor: ScoreAnnotationMeasureAnchor(
                    measureEID: group.region.measureEID,
                    fallbackMeasureIndex: group.region.measureIndex,
                    fallbackPageIndex: group.region.pageIndex,
                    sourceRect: ScoreAnnotationRect(group.region.normalizedRect),
                    origin: ScoreAnnotationPoint(ScoreAnnotationGeometry.boundsCenter(of: group.points))
                ),
                points: group.points.map(ScoreAnnotationPoint.init),
                createdAt: stroke.createdAt
            )
        }
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

    private static func resolve(
        stroke: ScoreAnnotationStroke,
        in regionIndex: ScoreAnnotationRegionIndex
    ) -> (pageIndex: Int, points: [CGPoint], scale: Double, isOrphaned: Bool) {
        let storedPoints = stroke.points.map(\.cgPoint)
        guard let anchor = stroke.anchor else {
            return (stroke.fallbackPageIndex, storedPoints, 1, false)
        }

        let match = regionIndex.region(for: anchor)
        let isOrphaned = !match.isExact && !anchor.measureEID.isEmpty
        let source = anchor.sourceRect.normalizedRect
        guard let region = match.region, source.width > 0, source.height > 0, region.normalizedRect.height > 0 else {
            return (anchor.fallbackPageIndex, storedPoints, 1, isOrphaned)
        }

        // The origin follows the measure proportionally, so a mark over beat 3
        // stays over beat 3. The shape scales uniformly with the measure height.
        let rect = region.normalizedRect
        let scale = rect.height / source.height
        let origin = anchor.origin.cgPoint
        let movedOrigin = CGPoint(
            x: rect.x + (origin.x - source.x) / source.width * rect.width,
            y: rect.y + (origin.y - source.y) / source.height * rect.height
        )
        let points = storedPoints.map { point in
            CGPoint(
                x: movedOrigin.x + (point.x - origin.x) * scale,
                y: movedOrigin.y + (point.y - origin.y) * scale
            )
        }
        return (region.pageIndex, points, scale, isOrphaned)
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
