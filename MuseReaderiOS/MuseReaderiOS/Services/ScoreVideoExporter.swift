//
//  ScoreVideoExporter.swift
//  MuseReaderiOS
//

import AVFoundation
import Accelerate
import CoreGraphics
import CoreImage
import CoreMedia
import Metal
import UIKit

enum ScoreVideoStyle: String, CaseIterable, Identifiable, Sendable {
    /// The whole piece on one continuous line that scrolls past a fixed playhead.
    case scrolling
    case scrollingPhoto
    case pagesLandscape
    case pagesPortrait

    var id: String {
        rawValue
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
        }
    }

    var frameSize: CGSize {
        switch self {
        case .scrolling, .scrollingPhoto, .pagesLandscape:
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
        case .scrolling, .scrollingPhoto, .pagesLandscape:
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
    /// Desktop MuseScore's default reverb send, matching in-app playback.
    var reverbSendLevel: Float = 0.3
    var backgroundImageData: Data? = nil
    /// Scrolling only: keep part names, clefs and signatures at the left.
    /// Useful with several parts; a single part reads better without it.
    var pinsStaffHeader = true
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

    var errorDescription: String? {
        switch self {
        case .noPlayback:
            return "This score has no playback to put in a video."
        case .noPages:
            return "The score has no pages to put in a video."
        case .writerFailed(let message):
            return "The video could not be written: \(message)"
        case .missingBackgroundImage:
            return "Choose a background photo for the white notation video."
        }
    }
}

/// Renders a play-along video of the displayed score with its audio: either
/// the whole piece on one line scrolling past a fixed playhead, or the pages
/// with a camera that follows the music. Frames and audio are produced in
/// playback order and written as MP4.
enum ScoreVideoExporter {
    private static let tailSeconds: TimeInterval = 2
    private static let audioChunkSeconds: TimeInterval = 1

    static func export(
        liveRenderSession: LiveScoreRenderSession,
        pageCount: Int,
        to url: URL,
        options: ScoreVideoExportOptions,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        if options.style == .scrollingPhoto, options.backgroundImageData == nil {
            throw ScoreVideoExportError.missingBackgroundImage
        }
        let rendering = Task.detached(priority: .userInitiated) {
            guard options.style == .scrolling || options.style == .scrollingPhoto else {
                try await render(liveRenderSession: liveRenderSession, pageCount: pageCount, to: url, options: options, progress: progress)
                return
            }
            // Lay the score out as one line for the render, then restore pages.
            let linePageCount = try await liveRenderSession.setContinuousLayout(true)
            do {
                try await render(liveRenderSession: liveRenderSession, pageCount: linePageCount, to: url, options: options, progress: progress)
                _ = try await liveRenderSession.setContinuousLayout(false)
            } catch {
                _ = try? await liveRenderSession.setContinuousLayout(false)
                throw error
            }
        }
        try await withTaskCancellationHandler {
            try await rendering.value
        } onCancel: {
            rendering.cancel()
        }
    }

    /// What a preview frame is drawn from: the pages, timing and beat points
    /// of either the one-line layout (scrolling) or the page layout.
    struct PreviewMaterial: @unchecked Sendable {
        fileprivate let pages: [ScoreVideoPageSource]
        fileprivate let timeline: ScoreVideoTimeline
        fileprivate let beatPoints: [ScorePlaybackBeatPoint]
    }

    /// Reads what previews need. Scrolling switches the score to one line only
    /// while reading, and always switches it back, as the export does. Callers
    /// must not start an export until this returns.
    static func previewMaterial(liveRenderSession: LiveScoreRenderSession, pageCount: Int,
                                scrolling: Bool) async throws -> PreviewMaterial {
        guard scrolling else {
            let timeline = ScoreVideoTimeline(regions: try await liveRenderSession.playbackMeasureRegions())
            var pages: [ScoreVideoPageSource] = []
            // The opening frame shows at most the first two pages.
            for index in 0..<min(max(pageCount, 1), 2) {
                pages.append(ScoreVideoPageSource(page: try await liveRenderSession.renderPage(at: index, dpi: 144)))
            }
            return PreviewMaterial(pages: pages, timeline: timeline, beatPoints: [])
        }
        _ = try await liveRenderSession.setContinuousLayout(true)
        do {
            let timeline = ScoreVideoTimeline(regions: try await liveRenderSession.playbackMeasureRegions())
            let page = ScoreVideoPageSource(page: try await liveRenderSession.renderPage(at: 0, dpi: 144))
            let beatPoints = (try? await liveRenderSession.playbackBeatPoints()) ?? []
            _ = try await liveRenderSession.setContinuousLayout(false)
            return PreviewMaterial(pages: [page], timeline: timeline, beatPoints: beatPoints)
        } catch {
            _ = try? await liveRenderSession.setContinuousLayout(false)
            throw error
        }
    }

    /// The first frame of the video, drawn by the painter the export uses.
    static func previewFrame(_ material: PreviewMaterial, options: ScoreVideoExportOptions) -> CGImage? {
        guard material.timeline.endTimeSeconds > 0, let firstPage = material.pages.first else { return nil }
        let frameSize = options.style.frameSize
        let painter: ScoreVideoPainter
        let time: TimeInterval
        switch options.style {
        case .scrolling, .scrollingPhoto:
            let scrolling = ScoreVideoScrollingPainter(frameSize: frameSize, page: firstPage, timeline: material.timeline,
                                                       beatPoints: material.beatPoints, options: options)
            painter = scrolling
            time = 0
        case .pagesLandscape, .pagesPortrait:
            painter = ScoreVideoPagesPainter(frameSize: frameSize, pages: material.pages, timeline: material.timeline, options: options)
            time = 0
        }
        var buffer: CVPixelBuffer?
        let attributes: [String: Any] = [kCVPixelBufferMetalCompatibilityKey as String: true,
                                         kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
        CVPixelBufferCreate(nil, Int(frameSize.width), Int(frameSize.height), kCVPixelFormatType_32BGRA,
                            attributes as CFDictionary, &buffer)
        guard let buffer else { return nil }
        painter.draw(into: buffer, at: time, frameDuration: 1 / 30)
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        return CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(frameSize.width), height: Int(frameSize.height),
                         bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                         space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                         bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)?
            .makeImage()
    }

    private static func render(
        liveRenderSession: LiveScoreRenderSession,
        pageCount: Int,
        to url: URL,
        options: ScoreVideoExportOptions,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let timeline = ScoreVideoTimeline(regions: try await liveRenderSession.playbackMeasureRegions())
        guard timeline.endTimeSeconds > 0 else {
            throw ScoreVideoExportError.noPlayback
        }
        guard pageCount > 0 else {
            throw ScoreVideoExportError.noPages
        }

        var pages: [ScoreVideoPageSource] = []
        for pageIndex in 0..<pageCount {
            try Task.checkCancellation()
            pages.append(ScoreVideoPageSource(page: try await liveRenderSession.renderPage(at: pageIndex, dpi: 144)))
        }

        let frameSize = options.style.frameSize
        let duration = timeline.endTimeSeconds + tailSeconds
        let frameRate = Double(options.frameRate)
        let totalFrames = Int((duration * frameRate).rounded(.up))
        let isScrolling = options.style == .scrolling || options.style == .scrollingPhoto
        let beatPoints = isScrolling ? (try? await liveRenderSession.playbackBeatPoints()) ?? [] : []
        let painter: ScoreVideoPainter = isScrolling
            ? ScoreVideoScrollingPainter(frameSize: frameSize, page: pages[0], timeline: timeline, beatPoints: beatPoints, options: options)
            : ScoreVideoPagesPainter(frameSize: frameSize, pages: pages, timeline: timeline, options: options)

        // The first audio chunk tells us the sample rate the writer needs.
        let audio = ScoreVideoAudioStream(liveRenderSession: liveRenderSession, reverbSendLevel: options.reverbSendLevel)
        var pendingAudio = try await audio.nextChunk(durationSeconds: audioChunkSeconds)
        let totalAudioFrames = Int64((duration * pendingAudio.sampleRate).rounded(.up))

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(frameSize.width),
            AVVideoHeightKey: Int(frameSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 10_000_000,
                AVVideoMaxKeyFrameIntervalKey: Int(frameRate * 2),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ])
        videoInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(frameSize.width),
            kCVPixelBufferHeightKey as String: Int(frameSize.height),
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: pendingAudio.sampleRate,
            AVNumberOfChannelsKey: pendingAudio.channelCount,
            AVEncoderBitRateKey: 192_000
        ])
        audioInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput), writer.canAdd(audioInput) else {
            throw ScoreVideoExportError.writerFailed("Unsupported video settings.")
        }
        writer.add(videoInput)
        writer.add(audioInput)
        guard writer.startWriting() else {
            throw ScoreVideoExportError.writerFailed(writer.error?.localizedDescription ?? "The writer did not start.")
        }
        writer.startSession(atSourceTime: .zero)

        // One chunk ahead, on the session's audio actor. Keep only two seconds
        // of PCM resident and let frame composition proceed while it renders.
        let prefetch = ScoreVideoAudioPrefetch(stream: audio)
        await prefetch.start()

        do {
            var frameIndex = 0
            var audioFramesWritten: Int64 = 0
            var audioFinished = false
            var needsAudio = false

            // Feed whichever input the writer is ready for, preferring the one
            // that is behind. The writer may hold back one input until the other
            // catches up, so waiting on a fixed order can deadlock.
            while frameIndex < totalFrames || !audioFinished {
                try Task.checkCancellation()
                if writer.status == .failed {
                    throw ScoreVideoExportError.writerFailed(writer.error?.localizedDescription ?? "Unknown error.")
                }
                if needsAudio, let chunk = try await prefetch.takeIfReady() {
                    guard chunk.sampleRate == pendingAudio.sampleRate,
                          chunk.channelCount == pendingAudio.channelCount else {
                        throw ScoreVideoExportError.writerFailed("The audio format changed during export.")
                    }
                    pendingAudio = chunk
                    needsAudio = false
                    if audioFramesWritten + Int64(chunk.frameCount) < totalAudioFrames {
                        await prefetch.start()
                    }
                }

                let videoTime = Double(frameIndex) / frameRate
                let audioTime = Double(audioFramesWritten) / pendingAudio.sampleRate
                let audioReady = !audioFinished && !needsAudio && audioInput.isReadyForMoreMediaData
                let videoReady = frameIndex < totalFrames && videoInput.isReadyForMoreMediaData

                if audioReady, !videoReady || audioTime <= videoTime {
                    let remaining = totalAudioFrames - audioFramesWritten
                    let frames = min(Int64(pendingAudio.frameCount), remaining)
                    if frames > 0 {
                        let sampleBuffer = try pendingAudio.sampleBuffer(frameCount: Int(frames), startFrame: audioFramesWritten)
                        guard audioInput.append(sampleBuffer) else {
                            throw ScoreVideoExportError.writerFailed(writer.error?.localizedDescription ?? "Audio was rejected.")
                        }
                        audioFramesWritten += frames
                    }
                    if audioFramesWritten >= totalAudioFrames {
                        audioFinished = true
                        audioInput.markAsFinished()
                    } else {
                        needsAudio = true
                    }
                } else if videoReady {
                    guard let pool = adaptor.pixelBufferPool else {
                        throw ScoreVideoExportError.writerFailed("No pixel buffer pool.")
                    }
                    var pixelBuffer: CVPixelBuffer?
                    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
                    guard let pixelBuffer else {
                        throw ScoreVideoExportError.writerFailed("No pixel buffer.")
                    }
                    autoreleasepool {
                        painter.draw(into: pixelBuffer, at: videoTime, frameDuration: 1 / frameRate)
                    }
                    let presentationTime = CMTime(value: CMTimeValue(frameIndex), timescale: options.frameRate)
                    guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                        throw ScoreVideoExportError.writerFailed(writer.error?.localizedDescription ?? "A frame was rejected.")
                    }
                    frameIndex += 1
                    if frameIndex == totalFrames {
                        videoInput.markAsFinished()
                    }
                    if frameIndex % 15 == 0 {
                        progress(Double(frameIndex) / Double(totalFrames))
                    }
                } else {
                    try await Task.sleep(nanoseconds: 2_000_000)
                }
            }

            await prefetch.stop()
            await writer.finishWriting()
            guard writer.status == .completed else {
                throw ScoreVideoExportError.writerFailed(writer.error?.localizedDescription ?? "The video did not finish.")
            }
            progress(1)
        } catch {
            // Drain before restoring layout or switching to another part; an
            // outstanding native audio request still owns the current score.
            await prefetch.stop()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }
}

/// A page's picture: its vector PDF when the renderer produced one, otherwise
/// its raster image. Rasterized at the size the video needs when first used.
struct ScoreVideoPageSource {
    let size: CGSize
    private let pdfPage: CGPDFPage?
    private let image: CGImage?

    init(page: ScorePage) {
        if let pdfData = page.pdfData,
           let provider = CGDataProvider(data: pdfData as CFData),
           let document = CGPDFDocument(provider),
           let pdfPage = document.page(at: 1)
        {
            self.pdfPage = pdfPage
            self.image = nil
            size = pdfPage.getBoxRect(.mediaBox).size
        } else {
            let cgImage = page.rasterizedImage()?.cgImage
            self.pdfPage = nil
            self.image = cgImage
            size = cgImage.map { CGSize(width: $0.width, height: $0.height) } ?? CGSize(width: 612, height: 792)
        }
    }

    /// The whole page at `scale` pixels per point.
    func rasterized(width: CGFloat, height: CGFloat) -> CGImage? {
        tile(scale: width / max(size.width, 1), originX: 0, pixelWidth: Int(width.rounded()), pixelHeight: Int(height.rounded()))
    }

    /// A vertical strip of the page at `scale` pixels per point, starting
    /// `originX` pixels from the page's left edge.
    func tile(scale: CGFloat, originX: CGFloat, pixelWidth: Int, pixelHeight: Int) -> CGImage? {
        guard pixelWidth > 0, pixelHeight > 0,
              let context = CGContext(
                  data: nil,
                  width: pixelWidth,
                  height: pixelHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              )
        else {
            return nil
        }
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.interpolationQuality = .high
        let verticalScale = CGFloat(pixelHeight) / max(size.height, 1)
        if let pdfPage {
            let box = pdfPage.getBoxRect(.mediaBox)
            context.translateBy(x: -originX, y: 0)
            context.scaleBy(x: scale, y: verticalScale)
            context.translateBy(x: -box.minX, y: -box.minY)
            context.drawPDFPage(pdfPage)
        } else if let image {
            context.draw(image, in: CGRect(x: -originX, y: 0, width: size.width * scale, height: CGFloat(pixelHeight)))
        }
        return context.makeImage()
    }
}

/// Draws the frames of a video, in order.
protocol ScoreVideoPainter: AnyObject {
    func draw(into pixelBuffer: CVPixelBuffer, at time: TimeInterval, frameDuration: TimeInterval)
}

/// All coordinates use the same top-left pixel space as the CPU painter.
private struct ScoreVideoLayer {
    let image: CGImage?
    let color: UIColor?
    let rect: CGRect
    var alpha: CGFloat = 1

    init(image: CGImage, rect: CGRect, alpha: CGFloat = 1) {
        self.image = image
        color = nil
        self.rect = rect
        self.alpha = alpha
    }

    init(color: UIColor, rect: CGRect) {
        image = nil
        self.color = color
        self.rect = rect
    }
}

/// Core Image composes the cached, full resolution assets on Metal directly
/// into the encoder's IOSurface buffer. No CPU full-frame bitmap or upload of
/// the completed frame. Retain a bounded set of source images across frames.
private final class ScoreVideoGPUCompositor {
    private let context: CIContext
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private var images: [ObjectIdentifier: (bitmap: CGImage, image: CIImage)] = [:]
    private var order: [ObjectIdentifier] = []

    init?() {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        context = CIContext(mtlDevice: device, options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            .cacheIntermediates: false
        ])
    }

    private func source(_ image: CGImage) -> CIImage {
        let key = ObjectIdentifier(image)
        if let cached = images[key] { return cached.image }
        let result = CIImage(cgImage: image, options: [.colorSpace: colorSpace])
        images[key] = (bitmap: image, image: result)
        order.append(key)
        if order.count > 16 { images[order.removeFirst()] = nil }
        return result
    }

    func draw(_ layers: [ScoreVideoLayer], into buffer: CVPixelBuffer, size: CGSize) {
        let bounds = CGRect(origin: .zero, size: size)
        var frame = CIImage(color: .clear).cropped(to: bounds)
        for layer in layers where layer.rect.width > 0 && layer.rect.height > 0 && layer.alpha > 0 {
            let destination = CGRect(x: layer.rect.minX, y: size.height - layer.rect.maxY,
                                     width: layer.rect.width, height: layer.rect.height)
            guard destination.intersects(bounds) else { continue }
            var image: CIImage
            if let bitmap = layer.image {
                image = source(bitmap).transformed(by: CGAffineTransform(
                    a: destination.width / CGFloat(bitmap.width), b: 0, c: 0,
                    d: destination.height / CGFloat(bitmap.height),
                    tx: destination.minX, ty: destination.minY))
            } else if let color = layer.color {
                image = CIImage(color: CIColor(color: color)).cropped(to: destination)
            } else { continue }
            if layer.alpha < 1 {
                let alpha = layer.alpha
                image = image.applyingFilter("CIColorMatrix", parameters: [
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)
                ])
            }
            frame = image.composited(over: frame)
        }
        // This synchronous render completes before AVAssetWriter sees the buffer.
        context.render(frame, to: buffer, bounds: bounds, colorSpace: colorSpace)
    }
}

/// What every video style shares: the backdrop, the title card, the progress
/// bar and the measure highlight.
class ScoreVideoPainterBase {
    private struct OverlaySize: Hashable {
        let width: Int
        let height: Int
    }
    static let accent = UIColor(red: 0.36, green: 0.62, blue: 1.0, alpha: 1)
    static let highlightFadeSeconds: TimeInterval = 0.15

    let frameSize: CGSize
    let timeline: ScoreVideoTimeline
    let options: ScoreVideoExportOptions
    private lazy var backgroundImage: CGImage? = makeBackgroundImage()
    private let gpu = ScoreVideoGPUCompositor()
    private lazy var titleCard: ScoreVideoLayer? = makeTitleCard()
    private var highlightImages: [OverlaySize: CGImage] = [:]
    private var playheadImages: [OverlaySize: CGImage] = [:]

    fileprivate func compose(_ layers: [ScoreVideoLayer], into buffer: CVPixelBuffer) {
        if let gpu {
            gpu.draw(layers, into: buffer, size: frameSize)
        } else {
            // Older environments without Metal keep the exact same assets,
            // timing and dimensions through the Core Graphics path.
            withFrameContext(buffer) { context in
                for layer in layers {
                    context.saveGState()
                    context.setAlpha(layer.alpha)
                    if let image = layer.image {
                        drawImage(image, in: layer.rect, context: context)
                    } else if let color = layer.color {
                        context.setFillColor(color.cgColor)
                        context.fill(layer.rect)
                    }
                    context.restoreGState()
                }
            }
        }
    }

    fileprivate func backgroundLayer() -> ScoreVideoLayer {
        let rect = CGRect(origin: .zero, size: frameSize)
        if let backgroundImage { return ScoreVideoLayer(image: backgroundImage, rect: rect) }
        return ScoreVideoLayer(color: UIColor(red: 0.09, green: 0.11, blue: 0.14, alpha: 1), rect: rect)
    }

    fileprivate func titleLayer(time: TimeInterval) -> ScoreVideoLayer? {
        guard time < 4.5, var layer = titleCard else { return nil }
        layer.alpha = time < 3.5 ? 1 : max(0, 1 - CGFloat(time - 3.5))
        return layer
    }

    fileprivate func progressLayers(time: TimeInterval, onPaper: Bool = false, whiteInk: Bool = false) -> [ScoreVideoLayer] {
        let track = CGRect(x: 0, y: frameSize.height - 6, width: frameSize.width, height: 6)
        let fraction = min(max(time / max(timeline.endTimeSeconds, 0.001), 0), 1)
        return [
            ScoreVideoLayer(color: onPaper ? .black.withAlphaComponent(0.06) : .white.withAlphaComponent(0.12), rect: track),
            ScoreVideoLayer(color: whiteInk ? .white : Self.accent,
                            rect: CGRect(x: 0, y: track.minY, width: track.width * CGFloat(fraction), height: track.height))
        ]
    }

    fileprivate static func overlay(size: CGSize, draw: (CGContext) -> Void) -> CGImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext) }.cgImage
    }

    fileprivate func highlightLayer(rect: CGRect, alpha: CGFloat) -> ScoreVideoLayer? {
        let bounds = rect.insetBy(dx: -8, dy: -10).integral
        let key = OverlaySize(width: Int(bounds.width), height: Int(bounds.height))
        var image = highlightImages[key]
        if image == nil {
            image = Self.overlay(size: bounds.size) { context in
                self.drawHighlight(context, rect: rect.offsetBy(dx: -bounds.minX, dy: -bounds.minY), alpha: 1)
            }
            if highlightImages.count >= 8 { highlightImages.removeAll(keepingCapacity: true) }
            highlightImages[key] = image
        }
        guard let image else { return nil }
        return ScoreVideoLayer(image: image, rect: bounds, alpha: alpha)
    }

    fileprivate func playheadLayer(x: CGFloat, top: CGFloat, bottom: CGFloat, alpha: CGFloat) -> ScoreVideoLayer? {
        let bounds = CGRect(x: x - 8, y: top - 6, width: 16, height: bottom - top + 12)
        let key = OverlaySize(width: 16, height: Int(ceil(bounds.height)))
        var image = playheadImages[key]
        if image == nil {
            image = Self.overlay(size: CGSize(width: key.width, height: key.height)) { context in
                self.drawPlayhead(context, x: 8, top: 6, bottom: CGFloat(key.height) - 6, alpha: 1)
            }
            if playheadImages.count >= 8 { playheadImages.removeAll(keepingCapacity: true) }
            playheadImages[key] = image
        }
        guard let image else { return nil }
        return ScoreVideoLayer(image: image, rect: bounds, alpha: alpha)
    }

    init(frameSize: CGSize, timeline: ScoreVideoTimeline, options: ScoreVideoExportOptions) {
        self.frameSize = frameSize
        self.timeline = timeline
        self.options = options
    }

    func font(_ selected: ScoreVideoTextFont, size: CGFloat) -> UIFont {
        let requestedFamily = selected.family.trimmingCharacters(in: .whitespacesAndNewlines)
        let family = UIFont.familyNames.first { $0.caseInsensitiveCompare(requestedFamily) == .orderedSame }
            ?? requestedFamily
        let candidates = UIFont.fontNames(forFamilyName: family).compactMap { UIFont(name: $0, size: size) }
        if let exact = candidates.first(where: {
            let traits = $0.fontDescriptor.symbolicTraits
            return traits.contains(.traitBold) == selected.bold && traits.contains(.traitItalic) == selected.italic
        }) {
            return exact
        }
        if let candidate = candidates.first {
            var traits = candidate.fontDescriptor.symbolicTraits
            if selected.bold { traits.insert(.traitBold) } else { traits.remove(.traitBold) }
            if selected.italic { traits.insert(.traitItalic) } else { traits.remove(.traitItalic) }
            if let descriptor = candidate.fontDescriptor.withSymbolicTraits(traits) {
                return UIFont(descriptor: descriptor, size: size)
            }
            return candidate
        }
        if let named = UIFont(name: requestedFamily, size: size) {
            return named
        }
        // A score may name a desktop-only font unavailable on iPad.
        return UIFont(name: "Edwin-Roman", size: size) ?? UIFont.systemFont(ofSize: size)
    }

    /// Runs `body` with a top-left, UIKit-style context over the pixel buffer.
    func withFrameContext(_ pixelBuffer: CVPixelBuffer, _ body: (CGContext) -> Void) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: Int(frameSize.width),
            height: Int(frameSize.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return
        }
        context.translateBy(x: 0, y: frameSize.height)
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }
        body(context)
    }

    /// Draws a bitmap upright in the flipped frame context.
    func drawImage(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    private func makeBackgroundImage() -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: Int(frameSize.width),
            height: Int(frameSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }
        // Store an upright image matching the original frame gradient.
        let colors = [
            UIColor(red: 0.12, green: 0.14, blue: 0.18, alpha: 1).cgColor,
            UIColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1).cgColor
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: frameSize.height), end: .zero, options: [])
        }
        return context.makeImage()
    }

    func drawHighlight(_ context: CGContext, rect: CGRect, alpha: Double) {
        guard alpha > 0 else { return }
        let path = UIBezierPath(roundedRect: rect.insetBy(dx: -6, dy: -8), cornerRadius: 10).cgPath
        context.addPath(path)
        context.setFillColor(Self.accent.withAlphaComponent(0.14 * alpha).cgColor)
        context.fillPath()
        context.addPath(path)
        context.setStrokeColor(Self.accent.withAlphaComponent(0.55 * alpha).cgColor)
        context.setLineWidth(2.5)
        context.strokePath()
    }

    /// 1 while the music plays, fading to 0 over the tail.
    func endFade(_ time: TimeInterval) -> Double {
        time > timeline.endTimeSeconds ? max(0, 1 - (time - timeline.endTimeSeconds) / 0.6) : 1
    }

    func drawPlayhead(_ context: CGContext, x: CGFloat, top: CGFloat, bottom: CGFloat, alpha: Double) {
        context.setLineCap(.round)
        context.setStrokeColor(Self.accent.withAlphaComponent(0.25 * alpha).cgColor)
        context.setLineWidth(12)
        context.strokeLineSegments(between: [CGPoint(x: x, y: top), CGPoint(x: x, y: bottom)])
        context.setStrokeColor(Self.accent.withAlphaComponent(alpha).cgColor)
        context.setLineWidth(4)
        context.strokeLineSegments(between: [CGPoint(x: x, y: top), CGPoint(x: x, y: bottom)])
    }

    private func makeTitleCard() -> ScoreVideoLayer? {
        let title = options.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let scale = frameSize.width / 1920 * (frameSize.height > frameSize.width ? 1.6 : 1)
        let titleText = NSAttributedString(string: title, attributes: [
            .font: font(options.titleFont, size: 44 * scale),
            .foregroundColor: UIColor.white
        ])
        let composer = options.composer.trimmingCharacters(in: .whitespacesAndNewlines)
        let composerText = NSAttributedString(string: composer, attributes: [
            .font: font(options.composerFont, size: 26 * scale),
            .foregroundColor: UIColor.white.withAlphaComponent(0.72)
        ])
        let padding = 22 * scale
        let maxTextWidth = frameSize.width - 80 * scale - padding * 2
        let titleSize = titleText.boundingRect(with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
                                               options: .usesLineFragmentOrigin, context: nil).integral.size
        let composerSize = composer.isEmpty ? .zero : composerText.size()
        let box = CGRect(
            x: 40 * scale,
            y: 40 * scale,
            width: min(max(titleSize.width, composerSize.width), maxTextWidth) + padding * 2,
            height: titleSize.height + (composer.isEmpty ? 0 : composerSize.height + 6 * scale) + padding * 2
        )
        let bounds = box.integral
        let localBox = box.offsetBy(dx: -bounds.minX, dy: -bounds.minY)
        guard let image = Self.overlay(size: bounds.size, draw: { _ in
            UIColor.black.withAlphaComponent(0.55).setFill()
            UIBezierPath(roundedRect: localBox, cornerRadius: 18 * scale).fill()
            titleText.draw(with: CGRect(x: localBox.minX + padding, y: localBox.minY + padding, width: maxTextWidth, height: titleSize.height),
                           options: .usesLineFragmentOrigin, context: nil)
            if !composer.isEmpty {
                composerText.draw(at: CGPoint(x: localBox.minX + padding, y: localBox.minY + padding + titleSize.height + 6 * scale))
            }
        }) else { return nil }
        return ScoreVideoLayer(image: image, rect: bounds)
    }

}

/// The pages stacked in a column; a camera glides to each system as it plays.
final class ScoreVideoPagesPainter: ScoreVideoPainterBase, ScoreVideoPainter {
    private static let pageCacheLimit = 4
    /// Where the playing system sits in the frame, from the top.
    private static let focusFraction: CGFloat = 0.42
    /// The camera aims this far ahead, so it settles on a new system as it starts.
    private static let cameraLeadSeconds: TimeInterval = 0.4
    private static let shadowLayers: [(spread: CGFloat, alpha: CGFloat)] = [(14, 0.10), (8, 0.14), (3, 0.22)]

    private let canvas: ScoreVideoCanvas
    private let pages: [ScoreVideoPageSource]
    private var camera: ScoreVideoCamera?
    private var pageImages: [Int: CGImage] = [:]
    private var pageImageOrder: [Int] = []

    init(frameSize: CGSize, pages: [ScoreVideoPageSource], timeline: ScoreVideoTimeline, options: ScoreVideoExportOptions) {
        self.pages = pages
        canvas = ScoreVideoCanvas(pageSizes: pages.map(\.size), pageWidth: options.style.pageWidth)
        super.init(frameSize: frameSize, timeline: timeline, options: options)
    }

    /// The canvas height the camera should centre on: the playing system.
    func focusTarget(at time: TimeInterval) -> CGFloat {
        guard let index = timeline.regionIndex(at: time),
              let rect = canvas.rect(for: timeline.regions[index])
        else {
            return frameSize.height / 2
        }
        return rect.midY
    }

    func draw(into pixelBuffer: CVPixelBuffer, at time: TimeInterval, frameDuration: TimeInterval) {
        let target = focusTarget(at: time + Self.cameraLeadSeconds)
        var camera = self.camera ?? ScoreVideoCamera(position: target)
        camera.step(toward: target, deltaTime: CGFloat(frameDuration))
        self.camera = camera

        let origin = CGPoint(x: (frameSize.width - options.style.pageWidth) / 2,
                             y: frameSize.height * Self.focusFraction - camera.position)
        var layers = [backgroundLayer()]
        layers += pageLayers(origin: origin)
        if let index = timeline.regionIndex(at: time) {
            let sinceStart = time - timeline.regions[index].startTimeSeconds
            if index > 0, sinceStart >= 0, sinceStart < Self.highlightFadeSeconds,
               let previous = canvas.rect(for: timeline.regions[index - 1]),
               let layer = highlightLayer(rect: previous.offsetBy(dx: origin.x, dy: origin.y),
                                          alpha: CGFloat(1 - sinceStart / Self.highlightFadeSeconds)) {
                layers.append(layer)
            }
            if let current = canvas.rect(for: timeline.regions[index])?.offsetBy(dx: origin.x, dy: origin.y) {
                if let layer = highlightLayer(rect: current, alpha: CGFloat(endFade(time))) { layers.append(layer) }
                let x = current.minX + CGFloat(timeline.progress(inRegion: index, at: time)) * current.width
                if let layer = playheadLayer(x: x, top: current.minY - 10, bottom: current.maxY + 10,
                                             alpha: CGFloat(endFade(time))) { layers.append(layer) }
            }
        }
        if let title = titleLayer(time: time) { layers.append(title) }
        layers += progressLayers(time: time)
        compose(layers, into: pixelBuffer)
    }

    private func pageLayers(origin: CGPoint) -> [ScoreVideoLayer] {
        var layers: [ScoreVideoLayer] = []
        let visible = CGRect(origin: .zero, size: frameSize).insetBy(dx: 0, dy: -40)
        for (index, pageFrame) in canvas.pageFrames.enumerated() {
            let rect = pageFrame.offsetBy(dx: origin.x, dy: origin.y)
            guard rect.intersects(visible) else { continue }

            // A soft layered edge reads as a shadow without a per-frame blur.
            // Each layer is only the ring outside the page, which covers the rest.
            for layer in Self.shadowLayers {
                layers.append(ScoreVideoLayer(color: UIColor.black.withAlphaComponent(layer.alpha),
                                              rect: rect.insetBy(dx: -layer.spread, dy: -layer.spread).offsetBy(dx: 0, dy: layer.spread / 2)))
            }
            if let image = pageImage(index, size: rect.size) {
                layers.append(ScoreVideoLayer(image: image, rect: rect))
            } else {
                layers.append(ScoreVideoLayer(color: .white, rect: rect))
            }
        }
        return layers
    }

    private func pageImage(_ index: Int, size: CGSize) -> CGImage? {
        if let image = pageImages[index] {
            return image
        }
        guard pages.indices.contains(index),
              let image = pages[index].rasterized(width: size.width, height: size.height)
        else {
            return nil
        }
        pageImages[index] = image
        pageImageOrder.append(index)
        if pageImageOrder.count > Self.pageCacheLimit {
            pageImages[pageImageOrder.removeFirst()] = nil
        }
        return image
    }
}

/// The whole piece on one line on a white frame, like one long sheet of paper.
/// The music slides past a fixed playhead; what has played is dimmed and the
/// line fades out at the frame's edges.
final class ScoreVideoScrollingPainter: ScoreVideoPainterBase, ScoreVideoPainter {
    private static let maximumScale: CGFloat = 2.2
    private static let tileWidth = 1024
    private static let tileCacheLimit = 6
    private static let edgeFadeWidth: CGFloat = 110
    private static let cursorWidth = 140
    private static let cursorFadeDistance: CGFloat = 84
    private static let lineStartX: CGFloat = 100
    private static let photoScrimAlpha: CGFloat = 0.52

    private let page: ScoreVideoPageSource
    private let scale: CGFloat
    private let band: CGRect
    private let contentTop: CGFloat
    private let contentBottom: CGFloat
    private let lineRects: [CGRect]
    private let path: ScoreVideoScrollPath
    private let photoBackground: CGImage?
    private let cursorGlow: CGImage?
    private let cursorGlowTop: CGFloat
    private let firstBeatX: CGFloat?
    private var tiles: [Int: CGImage] = [:]
    private var tileOrder: [Int] = []
    private lazy var pinnedTitle: ScoreVideoLayer? = makePinnedTitle()
    private lazy var headerWidth: Int? = findHeaderWidth()
    private lazy var openingText: OpeningText? = makeOpeningText()
    private lazy var stickyHeader: StickyHeader? = makeStickyHeader()
    /// When the first-bar text has faded out: just before the score moves.
    private let openingTextFade: ClosedRange<TimeInterval>
    private lazy var leftFade = makeHorizontalFade(width: Self.edgeFadeWidth, startAlpha: 1, endAlpha: 0)
    private lazy var rightFade = makeHorizontalFade(width: Self.edgeFadeWidth, startAlpha: 0, endAlpha: 1)
    private lazy var playedFade = makeHorizontalFade(width: 24, startAlpha: 0.42, endAlpha: 0)

    init(frameSize: CGSize,
         page: ScoreVideoPageSource,
         timeline: ScoreVideoTimeline,
         beatPoints: [ScorePlaybackBeatPoint],
         options: ScoreVideoExportOptions) {
        self.page = page
        photoBackground = options.style == .scrollingPhoto
            ? Self.makePhotoBackground(options.backgroundImageData, size: frameSize) : nil
        // Use the notation bounds, not the generous PDF margins, to size the line.
        let top = timeline.regions.map { CGFloat($0.normalizedRect.y) * page.size.height }.min() ?? 0
        let bottom = timeline.regions.map { CGFloat($0.normalizedRect.y + $0.normalizedRect.height) * page.size.height }.max() ?? page.size.height
        // Fit the staves into 59% of the height, but never let a staff space
        // exceed 2.4% of it: a single staff would otherwise fill the frame.
        let fitScale = (frameSize.height * 0.59) / max(bottom - top, 1)
        let sampleRegion = timeline.regions.count > 1 ? timeline.regions[1] : timeline.regions.first
        if let sampleRegion,
           let staffSpace = Self.staffSpace(in: page, region: sampleRegion.normalizedRect) {
            scale = min(fitScale, frameSize.height * 0.024 / staffSpace)
        } else {
            let baseScale = min(Self.maximumScale, (frameSize.height - 200) / max(page.size.height, 1))
            scale = min(baseScale * 1.7, fitScale)
        }
        let bandHeight = (page.size.height * scale).rounded()
        // Full systems start 19% down; short ones are centred on the frame,
        // never ending lower than 78% of the height.
        let contentHeight = (bottom - top) * scale
        let staffTop = max(frameSize.height * 0.19,
                           min(frameSize.height * 0.5 - contentHeight / 2, frameSize.height * 0.78 - contentHeight))
        let bandY = staffTop - top * scale
        band = CGRect(x: 0, y: bandY.rounded(), width: frameSize.width, height: bandHeight)
        contentTop = bandY + top * scale
        contentBottom = bandY + bottom * scale
        cursorGlowTop = contentTop - Self.cursorFadeDistance
        cursorGlow = Self.makeCursorGlow(
            color: options.style == .scrollingPhoto ? .white : Self.accent,
            height: contentBottom - contentTop + 2 * Self.cursorFadeDistance
        )
        lineRects = timeline.regions.map { region in
            let rect = region.normalizedRect
            return CGRect(
                x: CGFloat(rect.x) * page.size.width,
                y: CGFloat(rect.y) * page.size.height,
                width: CGFloat(rect.width) * page.size.width,
                height: CGFloat(rect.height) * page.size.height
            )
        }
        // Start at the first playable beat rather than sweeping across the
        // clef, key and meter header. Later measures still follow bar times.
        var pathRects = lineRects
        var firstBeatX: CGFloat?
        if let firstBeat = beatPoints.first, let first = pathRects.first {
            let beatX = CGFloat(firstBeat.normalizedX) * page.size.width
            if beatX > first.minX && beatX < first.maxX {
                pathRects[0] = CGRect(x: beatX, y: first.minY, width: first.maxX - beatX, height: first.height)
                firstBeatX = beatX
            }
        }
        self.firstBeatX = firstBeatX
        path = ScoreVideoScrollPath(timeline: timeline, rects: pathRects)
        var scrollStart: TimeInterval = 0
        while scrollStart < timeline.endTimeSeconds,
              Self.lineStartX + path.x(at: scrollStart) * scale < frameSize.width * 0.5 - 80 {
            scrollStart += 0.05
        }
        let fadeEnd = max(0.6, scrollStart - 0.4)
        openingTextFade = max(0, fadeEnd - 1.2)...fadeEnd
        super.init(frameSize: frameSize, timeline: timeline, options: options)
    }

    func draw(into pixelBuffer: CVPixelBuffer, at time: TimeInterval, frameDuration: TimeInterval) {
        // Average a short span so bar-to-bar speed shifts are less perceptible.
        var smoothedX: CGFloat = 0
        var weightSum: CGFloat = 0
        for sample in -6...6 {
            let weight = CGFloat(7 - abs(sample))
            smoothedX += weight * path.x(at: time + Double(sample) * 0.1)
            weightSum += weight
        }
        let scoreX = smoothedX / weightSum * scale
        let naturalTrackerX = Self.lineStartX + scoreX
        let centerX = frameSize.width * 0.5
        // The page stays still while the tracker crosses its opening. The
        // final 160 pixels ease the camera into motion without a sudden jerk.
        let handoffStart = centerX - 80
        let handoffEnd = centerX + 80
        let openingTrackerX: CGFloat
        if naturalTrackerX <= handoffStart {
            openingTrackerX = naturalTrackerX
        } else if naturalTrackerX >= handoffEnd {
            openingTrackerX = centerX
        } else {
            let u = (naturalTrackerX - handoffStart) / (handoffEnd - handoffStart)
            openingTrackerX = handoffStart + 160 * u - 80 * u * u
        }
        let ending = min(max((time - (timeline.endTimeSeconds - 8)) / 8, 0), 1)
        let easedEnding = ending * ending * (3 - 2 * ending)
        let playheadX = (openingTrackerX + frameSize.width * 0.18 * easedEnding).rounded()
        let offsetX = (playheadX - scoreX).rounded()

        let frame = CGRect(origin: .zero, size: frameSize)
        var layers: [ScoreVideoLayer]
        if let photoBackground {
            layers = [ScoreVideoLayer(image: photoBackground, rect: frame),
                      ScoreVideoLayer(color: .black.withAlphaComponent(Self.photoScrimAlpha), rect: frame)]
        } else {
            layers = [ScoreVideoLayer(color: .white, rect: frame)]
        }
        layers += lineLayers(offsetX: offsetX)
        if let stickyHeader {
            // Stays where the line began; the music slides underneath it.
            if let backdrop = stickyHeader.backdrop {
                layers.append(ScoreVideoLayer(image: backdrop, rect: stickyHeader.rect))
            }
            layers.append(ScoreVideoLayer(image: stickyHeader.ink, rect: stickyHeader.rect))
            // Rehearsal marks, tempo and other text on the first bar fade out
            // before the score moves; they are drawn with the score, not pinned.
            let fade = (time - openingTextFade.lowerBound) / max(0.01, openingTextFade.upperBound - openingTextFade.lowerBound)
            let alpha = 1 - min(max(fade, 0), 1)
            if let openingText, alpha > 0 {
                layers.append(ScoreVideoLayer(image: openingText.ink,
                                              rect: openingText.bounds.offsetBy(dx: offsetX, dy: band.minY),
                                              alpha: CGFloat(alpha)))
            }
        }
        if photoBackground == nil {
            let dimEnd = playheadX - 28
            layers.append(ScoreVideoLayer(color: .white.withAlphaComponent(0.42),
                                         rect: CGRect(x: band.minX, y: band.minY, width: max(0, dimEnd - band.minX), height: band.height)))
            if let playedFade {
                layers.append(ScoreVideoLayer(image: playedFade,
                                              rect: CGRect(x: dimEnd, y: band.minY, width: 24, height: band.height)))
            }
            if let leftFade {
                layers.append(ScoreVideoLayer(image: leftFade,
                                              rect: CGRect(x: band.minX, y: band.minY, width: Self.edgeFadeWidth, height: band.height)))
            }
            if let rightFade {
                layers.append(ScoreVideoLayer(image: rightFade,
                                              rect: CGRect(x: band.maxX - Self.edgeFadeWidth, y: band.minY, width: Self.edgeFadeWidth, height: band.height)))
            }
        }
        if let cursorGlow {
            layers.append(ScoreVideoLayer(image: cursorGlow,
                                          rect: CGRect(x: playheadX - CGFloat(Self.cursorWidth) / 2,
                                                       y: cursorGlowTop, width: CGFloat(Self.cursorWidth),
                                                       height: CGFloat(cursorGlow.height)), alpha: CGFloat(endFade(time))))
        }
        if let pinnedTitle { layers.append(pinnedTitle) }
        layers += progressLayers(time: time, onPaper: photoBackground == nil, whiteInk: photoBackground != nil)
        compose(layers, into: pixelBuffer)
    }

    /// Title and composer centred above the music for the whole video.
    private func makePinnedTitle() -> ScoreVideoLayer? {
        let title = options.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let composer = options.composer.trimmingCharacters(in: .whitespacesAndNewlines)
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        centered.lineBreakMode = .byTruncatingTail
        let titleText = NSAttributedString(string: title, attributes: [
            .font: font(options.titleFont, size: 40),
            .foregroundColor: photoBackground == nil ? UIColor(red: 0.12, green: 0.14, blue: 0.18, alpha: 1) : UIColor.white,
            .paragraphStyle: centered
        ])
        let composerText = NSAttributedString(string: composer, attributes: [
            .font: font(options.composerFont, size: 24),
            .foregroundColor: photoBackground == nil ? UIColor(red: 0.12, green: 0.14, blue: 0.18, alpha: 0.6) : UIColor.white.withAlphaComponent(0.78),
            .paragraphStyle: centered
        ])
        let width = frameSize.width - 160
        let titleHeight = ceil(titleText.size().height)
        let composerHeight = composer.isEmpty ? 0 : ceil(composerText.size().height)
        let blockHeight = titleHeight + (composer.isEmpty ? 0 : 6 + composerHeight)
        // Centred above where full-height music starts, never closer than 40 pt
        // to the top. When short music sits lower, the title follows it,
        // keeping room for chord symbols and markings above the staff.
        let top = max(40, (frameSize.height * 0.19 - blockHeight) / 2,
                      contentTop - frameSize.height * 0.2 - blockHeight)
        let bounds = CGRect(x: 80, y: top, width: width, height: blockHeight).integral
        let localTop = top - bounds.minY
        guard let image = Self.overlay(size: bounds.size, draw: { _ in
            titleText.draw(in: CGRect(x: 0, y: localTop, width: width, height: titleHeight))
            if !composer.isEmpty {
                composerText.draw(in: CGRect(x: 0, y: localTop + titleHeight + 6, width: width, height: composerHeight))
            }
        }) else { return nil }
        return ScoreVideoLayer(image: image, rect: bounds)
    }

    private struct StickyHeader {
        /// Clefs, signatures, part names and brackets.
        let ink: CGImage
        let backdrop: CGImage?
        let rect: CGRect
    }

    /// Part names, clefs, key and time signature from the start of the line,
    /// kept at the left so each staff stays identifiable once they scroll off.
    /// It ends in the blank gap before the first note. Loose text in it, such
    /// as a rehearsal mark, is left out and fades separately (`OpeningText`).
    private func findHeaderWidth() -> Int? {
        guard options.pinsStaffHeader, let firstBeatX, let first = lineRects.first else { return nil }
        let beatPixelX = Int((firstBeatX * scale).rounded())
        let measurePixelX = Int((first.minX * scale).rounded())
        guard beatPixelX > measurePixelX + 8,
              let strip = page.tile(scale: scale, originX: 0, pixelWidth: beatPixelX + 1, pixelHeight: Int(band.height)),
              let headerWidth = Self.headerEnd(in: strip, searchFrom: measurePixelX,
                                               rows: Int(contentTop - band.minY)..<Int(contentBottom - band.minY)),
              CGFloat(headerWidth) < frameSize.width * 0.35
        else { return nil }
        return headerWidth
    }

    private func makeStickyHeader() -> StickyHeader? {
        // From the frame's left edge, so nothing that has scrolled past shows beside it.
        guard let headerWidth,
              let source = page.tile(scale: scale, originX: -Self.lineStartX,
                                     pixelWidth: Int(Self.lineStartX) + headerWidth, pixelHeight: Int(band.height)),
              let headerStrip = eraseOpeningText(from: source, originX: -Int(Self.lineStartX))
        else { return nil }
        let rect = CGRect(x: 0, y: band.minY, width: Self.lineStartX + CGFloat(headerWidth), height: band.height)
        guard let photoBackground else {
            // Paper tiles are opaque white, so the strip hides the music by itself.
            return StickyHeader(ink: headerStrip, backdrop: nil, rect: rect)
        }
        guard let ink = Self.whiteInkImage(from: headerStrip) else { return nil }
        // The same blurred, darkened photo that sits behind it, so it reads as one surface.
        let photo = UIImage(cgImage: photoBackground)
        let backdrop = Self.overlay(size: rect.size) { context in
            photo.draw(at: CGPoint(x: -rect.minX, y: -rect.minY))
            UIColor.black.withAlphaComponent(Self.photoScrimAlpha).setFill()
            context.fill(CGRect(origin: .zero, size: rect.size))
        }
        return StickyHeader(ink: ink, backdrop: backdrop, rect: rect)
    }

    /// Text on the first bar that is not attached to the staves (a rehearsal
    /// mark, tempo, chord symbol) and reaches into the pinned header. In
    /// score pixels: x = 0 is the left edge of the line.
    private struct OpeningText {
        let ink: CGImage
        let bounds: CGRect
        /// Row-major over `bounds`: pixels that belong to the text.
        let mask: [Bool]
    }

    private func makeOpeningText() -> OpeningText? {
        guard let headerWidth else { return nil }
        let lineWidth = Int((page.size.width * scale).rounded())
        // Wide enough to take in a long tempo marking that starts in the header.
        let width = min(lineWidth, headerWidth + 900)
        let height = Int(band.height)
        guard width > 0, height > 0,
              let source = page.tile(scale: scale, originX: 0, pixelWidth: width, pixelHeight: height),
              let gray = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                   space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let grayData = gray.data
        else { return nil }
        gray.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        let luminance = grayData.assumingMemoryBound(to: UInt8.self)
        let staffRows = max(0, Int(contentTop - band.minY))..<min(height, Int(contentBottom - band.minY))
        guard !staffRows.isEmpty else { return nil }

        // 0: unvisited, 1: attached to the staves, 2: loose component being read.
        var label = [UInt8](repeating: 0, count: width * height)
        var stack: [Int] = []
        func fill(from seeds: [Int], as value: UInt8) -> [Int] {
            var visited: [Int] = []
            stack = seeds
            for seed in seeds { label[seed] = value }
            while let index = stack.popLast() {
                visited.append(index)
                let x = index % width
                let y = index / width
                for ny in max(0, y - 1)...min(height - 1, y + 1) {
                    for nx in max(0, x - 1)...min(width - 1, x + 1) {
                        let neighbor = ny * width + nx
                        if label[neighbor] == 0 && luminance[neighbor] < 170 {
                            label[neighbor] = value
                            stack.append(neighbor)
                        }
                    }
                }
            }
            return visited
        }
        var seeds: [Int] = []
        for row in staffRows {
            for x in 0..<width where luminance[row * width + x] < 170 { seeds.append(row * width + x) }
        }
        _ = fill(from: seeds, as: 1)

        // Loose shapes that reach into the header.
        var textPixels: [Int] = []
        for y in 0..<height {
            for x in 0..<headerWidth {
                let index = y * width + x
                guard label[index] == 0 && luminance[index] < 170 else { continue }
                textPixels += fill(from: [index], as: 2)
            }
        }
        guard !textPixels.isEmpty else { return nil }
        // Letters that sit wholly past the header ("o" in a boxed "Intro") belong
        // to the same text: take in loose shapes within 4 px of it until none remain.
        var minX = width, minY = height, maxX = 0, maxY = 0
        var measured = 0
        while measured < textPixels.count {
            for index in textPixels[measured...] {
                minX = min(minX, index % width); maxX = max(maxX, index % width)
                minY = min(minY, index / width); maxY = max(maxY, index / width)
            }
            measured = textPixels.count
            for y in max(0, minY - 4)...min(height - 1, maxY + 4) {
                for x in max(0, minX - 4)...min(width - 1, maxX + 4) {
                    let index = y * width + x
                    if label[index] == 0 && luminance[index] < 170 {
                        textPixels += fill(from: [index], as: 2)
                    }
                }
            }
        }
        // Grow by two pixels so the antialiased fringe goes with the text.
        minX = max(0, minX - 2); minY = max(0, minY - 2)
        maxX = min(width - 1, maxX + 2); maxY = min(height - 1, maxY + 2)
        let boxWidth = maxX - minX + 1
        let boxHeight = maxY - minY + 1
        var mask = [Bool](repeating: false, count: boxWidth * boxHeight)
        for index in textPixels {
            let x = index % width - minX
            let y = index / width - minY
            for dy in max(0, y - 2)...min(boxHeight - 1, y + 2) {
                for dx in max(0, x - 2)...min(boxWidth - 1, x + 2) {
                    mask[dy * boxWidth + dx] = true
                }
            }
        }
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(data: nil, width: boxWidth, height: boxHeight, bitsPerComponent: 8,
                                      bytesPerRow: boxWidth * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo),
              let data = context.data
        else { return nil }
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        let whiteInk = photoBackground != nil
        for y in 0..<boxHeight {
            for x in 0..<boxWidth where mask[y * boxWidth + x] {
                let alpha = 255 - luminance[(y + minY) * width + x + minX]
                let byte = (y * boxWidth + x) * 4
                // Premultiplied: white ink stores its alpha in each channel, black stores 0.
                let channel = whiteInk ? alpha : 0
                bytes[byte] = channel
                bytes[byte + 1] = channel
                bytes[byte + 2] = channel
                bytes[byte + 3] = alpha
            }
        }
        guard let ink = context.makeImage() else { return nil }
        return OpeningText(ink: ink, bounds: CGRect(x: minX, y: minY, width: boxWidth, height: boxHeight), mask: mask)
    }

    /// The score image with the opening text painted out in paper white.
    /// `originX` is the image's left edge in score pixels.
    private func eraseOpeningText(from image: CGImage, originX: Int) -> CGImage? {
        guard let openingText else { return image }
        let bounds = openingText.bounds
        let left = max(Int(bounds.minX), originX)
        let right = min(Int(bounds.maxX), originX + image.width)
        guard left < right else { return image }
        let width = image.width
        let height = image.height
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo),
              let data = context.data
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        let boxWidth = Int(bounds.width)
        for y in Int(bounds.minY)..<min(height, Int(bounds.maxY)) {
            let maskRow = (y - Int(bounds.minY)) * boxWidth
            for x in left..<right where openingText.mask[maskRow + x - Int(bounds.minX)] {
                // The bitmap's first row is the top of the drawn image.
                let byte = (y * width + x - originX) * 4
                bytes[byte] = 255
                bytes[byte + 1] = 255
                bytes[byte + 2] = 255
                bytes[byte + 3] = 255
            }
        }
        return context.makeImage()
    }

    /// Distance between staff lines in page points, measured from a measure:
    /// rows that are dark across most of it are staff lines.
    private static func staffSpace(in page: ScoreVideoPageSource, region: ScoreNormalizedRect) -> CGFloat? {
        let probeScale: CGFloat = 3
        let rect = CGRect(x: CGFloat(region.x) * page.size.width, y: CGFloat(region.y) * page.size.height,
                          width: CGFloat(region.width) * page.size.width, height: CGFloat(region.height) * page.size.height)
        let pixelWidth = Int((rect.width * probeScale).rounded())
        let pixelHeight = Int((page.size.height * probeScale).rounded())
        guard pixelWidth > 8, pixelHeight > 8,
              let image = page.tile(scale: probeScale, originX: rect.minX * probeScale,
                                    pixelWidth: pixelWidth, pixelHeight: pixelHeight),
              let gray = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
                                   bytesPerRow: pixelWidth, space: CGColorSpaceCreateDeviceGray(),
                                   bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let data = gray.data
        else { return nil }
        gray.draw(image, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        let firstRow = max(0, Int((rect.minY * probeScale).rounded()) - 2)
        let lastRow = min(pixelHeight - 1, Int((rect.maxY * probeScale).rounded()) + 2)
        guard firstRow < lastRow else { return nil }
        var lines: [CGFloat] = []
        var runStart: Int?
        for row in firstRow...lastRow {
            var dark = 0
            let line = pixels + row * pixelWidth
            for x in 0..<pixelWidth where line[x] < 160 { dark += 1 }
            let isStaffLine = dark * 10 >= pixelWidth * 6
            if isStaffLine, runStart == nil { runStart = row }
            if !isStaffLine, let start = runStart {
                lines.append(CGFloat(start + row - 1) / 2)
                runStart = nil
            }
        }
        guard lines.count >= 5 else { return nil }
        // Within a staff the gaps are the smallest; gaps between staves are larger.
        let gaps = zip(lines.dropFirst(), lines).map { $0 - $1 }.sorted()
        let space = gaps[min(gaps.count - 1, gaps.count / 4)] / probeScale
        return space > 0.5 ? space : nil
    }

    /// Width of the header: the middle of the blank gap left of the first note.
    /// Columns there hold only staff lines, the fewest dark pixels in the strip.
    private static func headerEnd(in strip: CGImage, searchFrom minimumX: Int, rows: Range<Int>) -> Int? {
        let width = strip.width
        let height = strip.height
        let rowRange = max(0, rows.lowerBound)..<min(height, rows.upperBound)
        guard width > minimumX + 2, !rowRange.isEmpty,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let data = context.data
        else { return nil }
        context.draw(strip, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        var ink = [Int](repeating: 0, count: width)
        for row in rowRange {
            // The bitmap's first row is the top of the drawn image.
            let line = pixels + row * width
            for x in minimumX..<width where line[x] < 160 {
                ink[x] += 1
            }
        }
        let floor = ink[minimumX..<width].min() ?? 0
        let blank = floor + 2 + floor / 50
        // Walk left from the first note, past its glyph, to the gap.
        var x = width - 1
        while x > minimumX && ink[x] > blank { x -= 1 }
        let gapEnd = x
        while x > minimumX && ink[x] <= blank { x -= 1 }
        guard x > minimumX, gapEnd - x >= 3 else { return nil }
        return (x + gapEnd) / 2 + 1
    }

    /// Draws the tiles of the line that fall inside the frame.
    private func lineLayers(offsetX: CGFloat) -> [ScoreVideoLayer] {
        var layers: [ScoreVideoLayer] = []
        let lineWidth = Int((page.size.width * scale).rounded())
        let firstTile = max(0, Int(floor(-offsetX / CGFloat(Self.tileWidth))))
        let lastTile = min((lineWidth - 1) / Self.tileWidth, Int(floor((frameSize.width - offsetX) / CGFloat(Self.tileWidth))))
        guard firstTile <= lastTile else { return layers }
        for tileIndex in firstTile...lastTile {
            let originX = tileIndex * Self.tileWidth
            let width = min(Self.tileWidth, lineWidth - originX)
            guard let image = tile(tileIndex, width: width) else { continue }
            layers.append(ScoreVideoLayer(image: image, rect: CGRect(x: offsetX + CGFloat(originX), y: band.minY, width: CGFloat(width), height: band.height)))
        }
        return layers
    }

    private func tile(_ index: Int, width: Int) -> CGImage? {
        if let image = tiles[index] {
            return image
        }
        guard let renderedImage = page.tile(scale: scale, originX: CGFloat(index * Self.tileWidth),
                                            pixelWidth: width, pixelHeight: Int(band.height)),
              let sourceImage = eraseOpeningText(from: renderedImage, originX: index * Self.tileWidth) else {
            return nil
        }
        let image: CGImage
        if photoBackground != nil {
            guard let converted = Self.whiteInkImage(from: sourceImage) else { return nil }
            image = converted
        } else {
            image = sourceImage
        }
        tiles[index] = image
        tileOrder.append(index)
        if tileOrder.count > Self.tileCacheLimit {
            tiles[tileOrder.removeFirst()] = nil
        }
        return image
    }

    private static func makePhotoBackground(_ data: Data?, size: CGSize) -> CGImage? {
        guard let data, let photo = UIImage(data: data) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let fill = max(size.width / photo.size.width, size.height / photo.size.height)
            let photoSize = CGSize(width: photo.size.width * fill, height: photo.size.height * fill)
            photo.draw(in: CGRect(x: (size.width - photoSize.width) / 2,
                                  y: (size.height - photoSize.height) / 2,
                                  width: photoSize.width, height: photoSize.height))
        }
        guard let base = image.cgImage else { return nil }
        let width = Int(size.width)
        let height = Int(size.height)
        let rowBytes = width * 4
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let input = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: rowBytes, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo),
              let scratch = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: rowBytes, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo),
              let output = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                     bytesPerRow: rowBytes, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo),
              let inputData = input.data, let scratchData = scratch.data, let outputData = output.data
        else { return nil }
        input.draw(base, in: CGRect(origin: .zero, size: size))
        var source = vImage_Buffer(data: inputData, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: rowBytes)
        var middle = vImage_Buffer(data: scratchData, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: rowBytes)
        var destination = vImage_Buffer(data: outputData, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: rowBytes)
        let flags = vImage_Flags(kvImageEdgeExtend)
        guard vImageBoxConvolve_ARGB8888(&source, &middle, nil, 0, 0, 41, 41, nil, flags) == kvImageNoError,
              vImageBoxConvolve_ARGB8888(&middle, &destination, nil, 0, 0, 41, 41, nil, flags) == kvImageNoError
        else { return nil }
        return output.makeImage()
    }

    private static func whiteInkImage(from source: CGImage) -> CGImage? {
        let width = source.width
        let height = source.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
              let data = context.data else { return nil }
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        for pixel in 0..<(width * height) {
            let index = pixel * 4
            let luminance = (19 * Int(bytes[index]) + 183 * Int(bytes[index + 1])
                             + 54 * Int(bytes[index + 2]) + 128) >> 8
            let ink = UInt8(255 - luminance)
            bytes[index] = ink
            bytes[index + 1] = ink
            bytes[index + 2] = ink
            bytes[index + 3] = ink
        }
        return context.makeImage()
    }

    /// A cached cursor with a vertical taper, so its glow has no hard edge
    /// just above or below the staff. Both the soft band and center line fade.
    private static func makeCursorGlow(color: UIColor, height: CGFloat) -> CGImage? {
        let width = cursorWidth
        let pixelHeight = max(1, Int(ceil(height)))
        guard let context = CGContext(data: nil, width: width, height: pixelHeight,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                          | CGBitmapInfo.byteOrder32Little.rawValue),
              let data = context.data else { return nil }
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var colorAlpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &colorAlpha)
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        for y in 0..<pixelHeight {
            let distanceFromEnd = min(CGFloat(y), CGFloat(pixelHeight - 1 - y))
            let fraction = min(1, distanceFromEnd / cursorFadeDistance)
            let verticalFade = Double(fraction * fraction * (3 - 2 * fraction))
            for x in 0..<width {
                let distance = abs(Double(x) - Double(width - 1) / 2)
                let broadGlow = 0.16 * exp(-pow(distance / 38, 2))
                let centerLine = 0.45 * exp(-pow(distance / 1.15, 2))
                let alpha = min(1, (broadGlow + centerLine) * verticalFade)
                let index = (y * width + x) * 4
                bytes[index] = UInt8((blue * alpha * 255).rounded())
                bytes[index + 1] = UInt8((green * alpha * 255).rounded())
                bytes[index + 2] = UInt8((red * alpha * 255).rounded())
                bytes[index + 3] = UInt8((alpha * 255).rounded())
            }
        }
        return context.makeImage()
    }

    /// Rasterize the narrow fade strips once at their output size.
    private func makeHorizontalFade(width: CGFloat, startAlpha: CGFloat, endAlpha: CGFloat) -> CGImage? {
        let colors = [
            UIColor.white.withAlphaComponent(startAlpha).cgColor,
            UIColor.white.withAlphaComponent(endAlpha).cgColor
        ] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return nil }
        return Self.overlay(size: CGSize(width: width, height: band.height)) { context in
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: 0), options: [])
        }
    }
}

/// Renders the performance audio in order, adding the same reverb as in-app
/// playback: a send of every part's signal to MuseScore's default reverb.
actor ScoreVideoAudioStream {
    private let liveRenderSession: LiveScoreRenderSession
    private let reverbSendLevel: Float
    private var reverb: MSRPlaybackReverb?
    private var nextStartSeconds: TimeInterval = 0

    init(liveRenderSession: LiveScoreRenderSession, reverbSendLevel: Float) {
        self.liveRenderSession = liveRenderSession
        self.reverbSendLevel = reverbSendLevel
    }

    func nextChunk(durationSeconds: TimeInterval) async throws -> ScoreVideoAudioChunk {
        let audioData = try await liveRenderSession.playbackAudioChunk(
            startTimeSeconds: nextStartSeconds,
            durationSeconds: durationSeconds,
            metronomeEnabled: false,
            includePartSamples: false
        )
        let channelCount = max(audioData.channelCount, 1)
        let sampleRate = Double(audioData.sampleRate)
        var samples = [Float](repeating: 0, count: audioData.interleavedFloat32Samples.count / MemoryLayout<Float>.size)
        _ = samples.withUnsafeMutableBytes { audioData.interleavedFloat32Samples.copyBytes(to: $0) }
        let frameCount = samples.count / channelCount
        guard frameCount > 0, sampleRate > 0 else {
            throw ScoreReaderExportError.noAudio
        }

        // With every part at full volume, the send is the mix times the send level.
        if channelCount == 2, reverbSendLevel > 0 {
            let reverb = self.reverb ?? MSRPlaybackReverb(sampleRate: sampleRate)
            self.reverb = reverb
            var send = samples.map { $0 * reverbSendLevel }
            send.withUnsafeMutableBufferPointer { buffer in
                reverb.processInterleavedStereo(buffer.baseAddress!, frameCount: frameCount)
            }
            for index in samples.indices {
                samples[index] += send[index]
            }
        }

        nextStartSeconds += Double(frameCount) / sampleRate
        return ScoreVideoAudioChunk(samples: samples, channelCount: channelCount, sampleRate: sampleRate)
    }
}

/// A single producer, with a single buffered result. The writer polls without
/// awaiting synthesis, so a slow chunk never blocks ready video frames.
private actor ScoreVideoAudioPrefetch {
    private let stream: ScoreVideoAudioStream
    private var task: Task<Void, Never>?
    private var result: Result<ScoreVideoAudioChunk, Error>?

    init(stream: ScoreVideoAudioStream) {
        self.stream = stream
    }

    func start() {
        guard task == nil, result == nil else { return }
        task = Task {
            do {
                let chunk = try await stream.nextChunk(durationSeconds: 1)
                try Task.checkCancellation()
                result = .success(chunk)
            } catch {
                result = .failure(error)
            }
        }
    }

    func takeIfReady() throws -> ScoreVideoAudioChunk? {
        guard let result else { return nil }
        self.result = nil
        task = nil
        return try result.get()
    }

    func stop() async {
        let pending = task
        pending?.cancel()
        await pending?.value
        task = nil
        result = nil
    }
}

struct ScoreVideoAudioChunk: Sendable {
    let samples: [Float]
    let channelCount: Int
    let sampleRate: Double

    var frameCount: Int {
        samples.count / channelCount
    }

    func sampleBuffer(frameCount: Int, startFrame: Int64) throws -> CMSampleBuffer {
        var description = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(4 * channelCount),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(4 * channelCount),
            mChannelsPerFrame: UInt32(channelCount),
            mBitsPerChannel: 32,
            mReserved: 0
        )
        var format: CMAudioFormatDescription?
        var status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &description,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &format
        )
        let byteCount = frameCount * channelCount * MemoryLayout<Float>.size
        var block: CMBlockBuffer?
        if status == noErr {
            status = CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: byteCount,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: byteCount,
                flags: kCMBlockBufferAssureMemoryNowFlag,
                blockBufferOut: &block
            )
        }
        if status == noErr, let block {
            status = samples.withUnsafeBytes { bytes in
                CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: byteCount)
            }
        }
        var sampleBuffer: CMSampleBuffer?
        if status == noErr, let block, let format {
            status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                allocator: kCFAllocatorDefault,
                dataBuffer: block,
                formatDescription: format,
                sampleCount: frameCount,
                presentationTimeStamp: CMTime(value: startFrame, timescale: CMTimeScale(sampleRate)),
                packetDescriptions: nil,
                sampleBufferOut: &sampleBuffer
            )
        }
        guard status == noErr, let sampleBuffer else {
            throw ScoreVideoExportError.writerFailed("Audio could not be prepared (\(status)).")
        }
        return sampleBuffer
    }
}
