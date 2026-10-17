//
//  ScoreVideoModels.swift
//  MuseReaderiOS
//
//  Video export settings and the timing and layout math, kept apart from the
//  drawing and encoding in ScoreVideoExporter and ScoreVideoPianoPainter.
//

import Foundation
#if !os(Android)
import CoreGraphics
#endif

enum ScoreVideoStyle: String, CaseIterable, Identifiable, Sendable {
    /// The whole piece on one continuous line that scrolls past a fixed playhead.
    case scrolling
    case scrollingPhoto
    case pagesLandscape
    case pagesPortrait
    /// Notes falling onto a piano keyboard, drawn from the playback MIDI:
    /// neon on black, the light piano roll, or over a blurred photo.
    case piano
    case pianoLight
    case pianoPhoto

    enum Layout: Hashable, Sendable {
        case scrolling
        case pages
        case piano
    }

    var id: String {
        rawValue
    }

    var layout: Layout {
        switch self {
        case .scrolling, .scrollingPhoto: return .scrolling
        case .pagesLandscape, .pagesPortrait: return .pages
        case .piano, .pianoLight, .pianoPhoto: return .piano
        }
    }

    /// Styles drawn over a photo the user chooses.
    var usesPhoto: Bool {
        self == .scrollingPhoto || self == .pianoPhoto
    }

    var title: String {
        switch self {
        case .scrolling:
            return "Scrolling"
        case .scrollingPhoto:
            return "Photo"
        case .pagesLandscape:
            return "Pages 16:9"
        case .pagesPortrait:
            return "Pages 9:16"
        case .piano:
            return "Piano"
        case .pianoLight:
            return "Piano light"
        case .pianoPhoto:
            return "Piano photo"
        }
    }

    var frameSize: CGSize {
        switch self {
        case .scrolling, .scrollingPhoto, .pagesLandscape, .piano, .pianoLight, .pianoPhoto:
            return CGSize(width: 1920, height: 1080)
        case .pagesPortrait:
            return CGSize(width: 1080, height: 1920)
        }
    }

    /// Width of each page in the page styles. Landscape keeps side margins so
    /// the notation stays large; portrait nearly fills the width.
    var pageWidth: CGFloat {
        switch self {
        case .pagesPortrait:
            return 1000
        case .scrolling, .scrollingPhoto, .pagesLandscape, .piano, .pianoLight, .pianoPhoto:
            return 1240
        }
    }
}

struct ScoreVideoTextFont: Sendable {
    var family: String = "Edwin"
    var bold = false
    var italic = false
}

struct ScoreVideoExportOptions: Sendable {
    var style: ScoreVideoStyle
    var title: String
    var composer: String
    var titleFont: ScoreVideoTextFont = ScoreVideoTextFont()
    var composerFont: ScoreVideoTextFont = ScoreVideoTextFont()
    var frameRate: Int32 = 30
    var mixerSettings = ScoreMixerSettings()
    /// Desktop MuseScore's default reverb send, matching in-app playback.
    var reverbSendLevel: Float = 0.3
    var backgroundImageData: Data? = nil
    /// Scrolling only: keep part names, clefs and signatures at the left.
    /// Useful with several parts; a single part reads better without it.
    var pinsStaffHeader = true
    /// Scrolling and Piano: 9:16 at 1080×1920 for Reels and TikTok. Pages has
    /// its own portrait style.
    var vertical = false

    /// The frame size written to the file.
    var frameSize: CGSize {
        vertical && style.layout != .pages ? CGSize(width: 1080, height: 1920) : style.frameSize
    }
}

/// Which measure is playing at a moment of the performance, and how far
/// through it the music is. Regions follow playback order, repeats included.
struct ScoreVideoTimeline: Equatable {
    let regions: [ScorePlaybackMeasureRegion]

    init(regions: [ScorePlaybackMeasureRegion]) {
        self.regions = regions
            .filter { $0.endTimeSeconds > $0.startTimeSeconds }
            .sorted { $0.startTimeSeconds < $1.startTimeSeconds }
    }

    var endTimeSeconds: TimeInterval {
        regions.last?.endTimeSeconds ?? 0
    }

    /// The last region starting at or before `time`, or the first region
    /// before the music starts.
    func regionIndex(at time: TimeInterval) -> Int? {
        guard !regions.isEmpty else { return nil }
        var low = 0
        var high = regions.count - 1
        var result = 0
        while low <= high {
            let middle = (low + high) / 2
            if regions[middle].startTimeSeconds <= time {
                result = middle
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        return result
    }

    func progress(inRegion index: Int, at time: TimeInterval) -> Double {
        let region = regions[index]
        let length = region.endTimeSeconds - region.startTimeSeconds
        return min(max((time - region.startTimeSeconds) / length, 0), 1)
    }
}

/// The pages stacked top to bottom, as the page-style camera sees them.
struct ScoreVideoCanvas: Equatable {
    static let pageGap: CGFloat = 56

    let pageFrames: [CGRect]

    init(pageSizes: [CGSize], pageWidth: CGFloat) {
        var frames: [CGRect] = []
        var top: CGFloat = 0
        for size in pageSizes {
            let height = size.width > 0 ? pageWidth * size.height / size.width : pageWidth * 11 / 8.5
            frames.append(CGRect(x: 0, y: top, width: pageWidth, height: height))
            top += height + Self.pageGap
        }
        pageFrames = frames
    }

    var height: CGFloat {
        pageFrames.last?.maxY ?? 0
    }

    func rect(for region: ScorePlaybackMeasureRegion) -> CGRect? {
        guard pageFrames.indices.contains(region.pageIndex) else { return nil }
        let page = pageFrames[region.pageIndex]
        let rect = region.normalizedRect
        return CGRect(
            x: page.minX + CGFloat(rect.x) * page.width,
            y: page.minY + CGFloat(rect.y) * page.height,
            width: CGFloat(rect.width) * page.width,
            height: CGFloat(rect.height) * page.height
        )
    }
}

/// A critically damped spring: the camera eases into each new system
/// without overshooting, and the motion is the same at any frame rate.
struct ScoreVideoCamera: Equatable {
    var position: CGFloat
    var velocity: CGFloat = 0
    var angularFrequency: CGFloat = 6.5

    mutating func step(toward target: CGFloat, deltaTime: CGFloat) {
        let offset = position - target
        let decay = exp(-angularFrequency * deltaTime)
        let term = (velocity + angularFrequency * offset) * deltaTime
        position = target + (offset + term) * decay
        velocity = (velocity - angularFrequency * term) * decay
    }
}

/// Where the continuous line is under the playhead over time. It passes each
/// note exactly when it sounds (or each barline, without note positions), and
/// blends the speed between them (monotone cubic interpolation) so uneven
/// spacing and tempo changes do not jolt. A repeat, or any jump that is not to
/// the next measure, starts a new segment, which the video cuts to.
struct ScoreVideoScrollPath: Equatable {
    struct Knot: Equatable {
        let time: TimeInterval
        let x: CGFloat
    }

    private(set) var segments: [[Knot]] = []
    private var tangents: [[CGFloat]] = []

    /// From the engine's note positions; `lineWidth` converts them to points.
    init(beatPoints: [ScorePlaybackBeatPoint], lineWidth: CGFloat) {
        var segments: [[Knot]] = []
        for point in beatPoints {
            let knot = Knot(time: point.timeSeconds, x: CGFloat(point.normalizedX) * lineWidth)
            if point.startsSegment || segments.isEmpty {
                segments.append([knot])
            } else if let last = segments[segments.count - 1].last, knot.time > last.time + 0.0005 {
                segments[segments.count - 1].append(knot)
            }
        }
        self.init(segments: segments)
    }

    private init(segments: [[Knot]]) {
        self.segments = segments.filter { !$0.isEmpty }
        tangents = self.segments.map(Self.monotoneTangents)
    }

    /// `rects` are the regions' positions on the line, in the same order as `timeline.regions`.
    init(timeline: ScoreVideoTimeline, rects: [CGRect], barlineTolerance: CGFloat = 2) {
        var segments: [[Knot]] = []
        var current: [Knot] = []
        for (index, region) in timeline.regions.enumerated() {
            let rect = rects[index]
            if let previousIndex = index > 0 ? index - 1 : nil, !current.isEmpty {
                let previous = rects[previousIndex]
                let previousRegion = timeline.regions[previousIndex]
                let continuesLine = abs(rect.minX - previous.maxX) <= barlineTolerance
                    && abs(region.startTimeSeconds - previousRegion.endTimeSeconds) < 0.001
                if !continuesLine {
                    current.append(Knot(time: previousRegion.endTimeSeconds, x: previous.maxX))
                    segments.append(current)
                    current = []
                }
            }
            current.append(Knot(time: region.startTimeSeconds, x: rect.minX))
        }
        if let last = timeline.regions.last, let lastRect = rects.last {
            current.append(Knot(time: last.endTimeSeconds, x: lastRect.maxX))
            segments.append(current)
        }
        self.init(segments: segments)
    }

    /// The times of the stretch playing at `time`, from its first note to the
    /// next jump. Smoothing stays inside it, so a repeat cuts instead of rewinding.
    func segmentTimes(at time: TimeInterval) -> ClosedRange<TimeInterval> {
        guard let segmentIndex = segments.lastIndex(where: { $0[0].time <= time }) else {
            let start = segments.first?.first?.time ?? 0
            let end = segments.count > 1 ? segments[1][0].time : .greatestFiniteMagnitude
            return -.greatestFiniteMagnitude...max(start, end)
        }
        let start = segments[segmentIndex][0].time
        let end = segmentIndex + 1 < segments.count ? segments[segmentIndex + 1][0].time : .greatestFiniteMagnitude
        // Just before the next stretch starts, so clamped samples stay in this one.
        return start...max(start, end - 0.0001)
    }

    func x(at time: TimeInterval) -> CGFloat {
        guard let first = segments.first?.first else { return 0 }
        if time <= first.time { return first.x }
        // The segment playing at `time`: the last one that has started.
        guard let segmentIndex = segments.lastIndex(where: { $0[0].time <= time }) else { return first.x }
        let knots = segments[segmentIndex]
        guard let last = knots.last, time < last.time else { return knots.last?.x ?? first.x }
        var knotIndex = 0
        while knotIndex + 1 < knots.count, knots[knotIndex + 1].time <= time {
            knotIndex += 1
        }
        let a = knots[knotIndex]
        let b = knots[knotIndex + 1]
        let h = CGFloat(b.time - a.time)
        guard h > 0 else { return b.x }
        let s = CGFloat(time - a.time) / h
        let s2 = s * s
        let s3 = s2 * s
        let m = tangents[segmentIndex]
        return (2 * s3 - 3 * s2 + 1) * a.x + (s3 - 2 * s2 + s) * h * m[knotIndex]
            + (-2 * s3 + 3 * s2) * b.x + (s3 - s2) * h * m[knotIndex + 1]
    }

    /// Fritsch–Carlson tangents: the curve never moves backwards within a segment.
    private static func monotoneTangents(_ knots: [Knot]) -> [CGFloat] {
        let count = knots.count
        guard count > 1 else { return Array(repeating: 0, count: count) }
        let slopes = (0..<(count - 1)).map { index -> CGFloat in
            let dt = CGFloat(knots[index + 1].time - knots[index].time)
            return dt > 0 ? (knots[index + 1].x - knots[index].x) / dt : 0
        }
        var tangents = [CGFloat](repeating: 0, count: count)
        tangents[0] = slopes[0]
        tangents[count - 1] = slopes[count - 2]
        for index in 1..<(count - 1) {
            tangents[index] = slopes[index - 1] * slopes[index] > 0 ? (slopes[index - 1] + slopes[index]) / 2 : 0
        }
        for index in 0..<(count - 1) {
            let slope = slopes[index]
            if slope == 0 {
                tangents[index] = 0
                tangents[index + 1] = 0
                continue
            }
            let a = tangents[index] / slope
            let b = tangents[index + 1] / slope
            let magnitude = a * a + b * b
            if magnitude > 9 {
                let tau = 3 / sqrt(magnitude)
                tangents[index] = tau * a * slope
                tangents[index + 1] = tau * b * slope
            }
        }
        return tangents
    }
}

enum ScoreVideoExportError: LocalizedError {
    case noPlayback
    case noPages
    case writerFailed(String)
    case missingBackgroundImage
    case noPianoNotes

    var errorDescription: String? {
        switch self {
        case .noPlayback:
            return "This score has no playback to put in a video."
        case .noPages:
            return "The score has no pages to put in a video."
        case .writerFailed(let message):
            return "The video could not be written: \(message)"
        case .missingBackgroundImage:
            return "Choose a background photo for this video."
        case .noPianoNotes:
            return "This score has no pitched notes to show on a piano."
        }
    }
}

/// One sounding note of the performance, in playback time.
struct ScoreVideoPianoNote: Equatable, Sendable {
    let pitch: Int
    let startSeconds: TimeInterval
    let endSeconds: TimeInterval
    /// The staff that plays it, from 0 in score order, so a piano's two
    /// hands, or each part, get their own colour.
    let track: Int
}

/// The keys shown, fitted to the music's range across the frame's width.
struct ScoreVideoPianoKeyboard: Equatable {
    static let lowestPianoPitch = 21
    static let highestPianoPitch = 108

    let lowestPitch: Int
    let highestPitch: Int
    let whiteKeyWidth: CGFloat
    private let leftEdge: Double

    var blackKeyWidth: CGFloat {
        whiteKeyWidth * 0.62
    }

    /// The music's range plus a little room, at least `minimumSpan`
    /// semitones, ending on white keys and within a real piano.
    init(pitches: [Int], width: CGFloat, minimumSpan: Int = 36) {
        var low = (pitches.min() ?? 48) - 2
        var high = (pitches.max() ?? 84) + 2
        if high - low < minimumSpan {
            let extra = minimumSpan - (high - low)
            low -= extra / 2
            high += extra - extra / 2
        }
        if low < Self.lowestPianoPitch {
            high += Self.lowestPianoPitch - low
            low = Self.lowestPianoPitch
        }
        if high > Self.highestPianoPitch {
            low -= high - Self.highestPianoPitch
            high = Self.highestPianoPitch
        }
        low = max(low, Self.lowestPianoPitch)
        // Both ends of a real piano are white keys, so this stays in range.
        while Self.isBlack(low) { low -= 1 }
        while Self.isBlack(high) { high += 1 }
        lowestPitch = low
        highestPitch = high
        leftEdge = Self.whitePosition(low) - 0.5
        whiteKeyWidth = width / CGFloat(Self.whitePosition(high) + 0.5 - leftEdge)
    }

    static func isBlack(_ pitch: Int) -> Bool {
        [1, 3, 6, 8, 10].contains(pitch % 12)
    }

    /// White keys sit at whole numbers; black keys on the boundary between two.
    static func whitePosition(_ pitch: Int) -> Double {
        let positions: [Double] = [0, 0.5, 1, 1.5, 2, 3, 3.5, 4, 4.5, 5, 5.5, 6]
        return Double(pitch / 12) * 7 + positions[pitch % 12]
    }

    var pitches: ClosedRange<Int> {
        lowestPitch...highestPitch
    }

    func centerX(of pitch: Int) -> CGFloat {
        CGFloat(Self.whitePosition(pitch) - leftEdge) * whiteKeyWidth
    }

    func keyWidth(of pitch: Int) -> CGFloat {
        Self.isBlack(pitch) ? blackKeyWidth : whiteKeyWidth
    }
}

/// How the piano video looks: neon notes on black, the light piano roll,
/// or glassy notes over the user's blurred photo.
enum ScoreVideoPianoTheme: Sendable {
    case dark
    case light
    case photo

    /// Soft bloom around the notes and flares, composed on the GPU.
    var glows: Bool {
        self != .light
    }
}
