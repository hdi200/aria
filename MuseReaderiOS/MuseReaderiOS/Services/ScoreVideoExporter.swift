//
//  ScoreVideoExporter.swift
//  MuseReaderiOS
//

import AVFoundation
import CoreGraphics
import CoreMedia
import UIKit

enum ScoreVideoStyle: String, CaseIterable, Identifiable, Sendable {
    /// The whole piece on one continuous line that scrolls past a fixed playhead.
    case scrolling
    case pagesLandscape
    case pagesPortrait

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .scrolling:
            return "Scrolling"
        case .pagesLandscape:
            return "Pages 16:9"
        case .pagesPortrait:
            return "Pages 9:16"
        }
    }

    var frameSize: CGSize {
        switch self {
        case .scrolling, .pagesLandscape:
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
        case .scrolling, .pagesLandscape:
            return 1240
        }
    }
}

struct ScoreVideoExportOptions: Sendable {
    var style: ScoreVideoStyle
    var title: String
    var composer: String
    var frameRate: Int32 = 30
    /// Desktop MuseScore's default reverb send, matching in-app playback.
    var reverbSendLevel: Float = 0.3
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
/// barline exactly when that measure starts, and blends the speed between
/// measures (monotone cubic interpolation) so tempo and width changes do not
/// jolt. A repeat, or any jump that is not to the next measure, starts a new
/// segment, which the video cuts to.
struct ScoreVideoScrollPath: Equatable {
    struct Knot: Equatable {
        let time: TimeInterval
        let x: CGFloat
    }

    private(set) var segments: [[Knot]] = []
    private var tangents: [[CGFloat]] = []

    /// `rects` are the regions' positions on the line, in the same order as `timeline.regions`.
    init(timeline: ScoreVideoTimeline, rects: [CGRect], barlineTolerance: CGFloat = 2) {
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
        tangents = segments.map(Self.monotoneTangents)
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

    var errorDescription: String? {
        switch self {
        case .noPlayback:
            return "This score has no playback to put in a video."
        case .noPages:
            return "The score has no pages to put in a video."
        case .writerFailed(let message):
            return "The video could not be written: \(message)"
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
        try await Task.detached(priority: .userInitiated) {
            guard options.style == .scrolling else {
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
        }.value
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
        let painter: ScoreVideoPainter = options.style == .scrolling
            ? ScoreVideoScrollingPainter(frameSize: frameSize, page: pages[0], timeline: timeline, options: options)
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
            kCVPixelBufferHeightKey as String: Int(frameSize.height)
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

        do {
            var frameIndex = 0
            var audioFramesWritten: Int64 = 0
            var audioFinished = false

            // Feed whichever input the writer is ready for, preferring the one
            // that is behind. The writer may hold back one input until the other
            // catches up, so waiting on a fixed order can deadlock.
            while frameIndex < totalFrames || !audioFinished {
                try Task.checkCancellation()
                if writer.status == .failed {
                    throw ScoreVideoExportError.writerFailed(writer.error?.localizedDescription ?? "Unknown error.")
                }

                let videoTime = Double(frameIndex) / frameRate
                let audioTime = Double(audioFramesWritten) / pendingAudio.sampleRate
                let audioReady = !audioFinished && audioInput.isReadyForMoreMediaData
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
                        pendingAudio = try await audio.nextChunk(durationSeconds: audioChunkSeconds)
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
                    painter.draw(into: pixelBuffer, at: videoTime, frameDuration: 1 / frameRate)
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

            await writer.finishWriting()
            guard writer.status == .completed else {
                throw ScoreVideoExportError.writerFailed(writer.error?.localizedDescription ?? "The video did not finish.")
            }
            progress(1)
        } catch {
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

/// What every video style shares: the backdrop, the title card, the progress
/// bar and the measure highlight.
class ScoreVideoPainterBase {
    static let accent = UIColor(red: 0.36, green: 0.62, blue: 1.0, alpha: 1)
    static let highlightFadeSeconds: TimeInterval = 0.15

    let frameSize: CGSize
    let timeline: ScoreVideoTimeline
    let options: ScoreVideoExportOptions
    private lazy var backgroundImage: CGImage? = makeBackgroundImage()

    init(frameSize: CGSize, timeline: ScoreVideoTimeline, options: ScoreVideoExportOptions) {
        self.frameSize = frameSize
        self.timeline = timeline
        self.options = options
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

    /// The gradient is drawn once; copying it each frame is much cheaper.
    func drawBackground(_ context: CGContext) {
        guard let backgroundImage else {
            context.setFillColor(UIColor(red: 0.09, green: 0.11, blue: 0.14, alpha: 1).cgColor)
            context.fill(CGRect(origin: .zero, size: frameSize))
            return
        }
        context.draw(backgroundImage, in: CGRect(origin: .zero, size: frameSize))
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
        // Dark at the top, a little lighter at the bottom once drawn into the
        // flipped frame context.
        let colors = [
            UIColor(red: 0.12, green: 0.14, blue: 0.18, alpha: 1).cgColor,
            UIColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1).cgColor
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: frameSize.height), options: [])
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

    /// Lights the playing measure and fades the previous one out.
    func drawMeasureHighlights(_ context: CGContext, time: TimeInterval, rect: (Int) -> CGRect?) -> CGRect? {
        guard let index = timeline.regionIndex(at: time) else { return nil }
        if index > 0 {
            let sinceStart = time - timeline.regions[index].startTimeSeconds
            if sinceStart >= 0, sinceStart < Self.highlightFadeSeconds, let previous = rect(index - 1) {
                drawHighlight(context, rect: previous, alpha: 1 - sinceStart / Self.highlightFadeSeconds)
            }
        }
        guard let current = rect(index) else { return nil }
        drawHighlight(context, rect: current, alpha: endFade(time))
        return current
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

    func drawTitle(time: TimeInterval) {
        let title = options.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, time < 4.5 else { return }
        let alpha = time < 3.5 ? 1 : max(0, 1 - (time - 3.5))
        let scale = frameSize.width / 1920 * (frameSize.height > frameSize.width ? 1.6 : 1)
        let titleText = NSAttributedString(string: title, attributes: [
            .font: UIFont.systemFont(ofSize: 44 * scale, weight: .semibold),
            .foregroundColor: UIColor.white.withAlphaComponent(alpha)
        ])
        let composer = options.composer.trimmingCharacters(in: .whitespacesAndNewlines)
        let composerText = NSAttributedString(string: composer, attributes: [
            .font: UIFont.systemFont(ofSize: 26 * scale, weight: .medium),
            .foregroundColor: UIColor.white.withAlphaComponent(0.72 * alpha)
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
        UIColor.black.withAlphaComponent(0.55 * alpha).setFill()
        UIBezierPath(roundedRect: box, cornerRadius: 18 * scale).fill()
        titleText.draw(with: CGRect(x: box.minX + padding, y: box.minY + padding, width: maxTextWidth, height: titleSize.height),
                       options: .usesLineFragmentOrigin, context: nil)
        if !composer.isEmpty {
            composerText.draw(at: CGPoint(x: box.minX + padding, y: box.minY + padding + titleSize.height + 6 * scale))
        }
    }

    func drawProgress(_ context: CGContext, time: TimeInterval, onPaper: Bool = false) {
        let height: CGFloat = 6
        let track = CGRect(x: 0, y: frameSize.height - height, width: frameSize.width, height: height)
        context.setFillColor((onPaper ? UIColor.black.withAlphaComponent(0.06) : UIColor.white.withAlphaComponent(0.12)).cgColor)
        context.fill(track)
        let fraction = min(max(time / max(timeline.endTimeSeconds, 0.001), 0), 1)
        context.setFillColor(Self.accent.cgColor)
        context.fill(CGRect(x: 0, y: track.minY, width: track.width * CGFloat(fraction), height: height))
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

        withFrameContext(pixelBuffer) { context in
            drawBackground(context)
            // Pages centred horizontally, the playing system held at the focus line.
            let origin = CGPoint(
                x: (frameSize.width - options.style.pageWidth) / 2,
                y: frameSize.height * Self.focusFraction - camera.position
            )
            drawPages(context, origin: origin)
            let current = drawMeasureHighlights(context, time: time) { index in
                self.canvas.rect(for: self.timeline.regions[index])?.offsetBy(dx: origin.x, dy: origin.y)
            }
            if let current, let index = timeline.regionIndex(at: time) {
                let x = current.minX + CGFloat(timeline.progress(inRegion: index, at: time)) * current.width
                drawPlayhead(context, x: x, top: current.minY - 10, bottom: current.maxY + 10, alpha: endFade(time))
            }
            drawTitle(time: time)
            drawProgress(context, time: time)
        }
    }

    private func drawPages(_ context: CGContext, origin: CGPoint) {
        let visible = CGRect(origin: .zero, size: frameSize).insetBy(dx: 0, dy: -40)
        for (index, pageFrame) in canvas.pageFrames.enumerated() {
            let rect = pageFrame.offsetBy(dx: origin.x, dy: origin.y)
            guard rect.intersects(visible) else { continue }

            // A soft layered edge reads as a shadow without a per-frame blur.
            // Each layer is only the ring outside the page, which covers the rest.
            for layer in Self.shadowLayers {
                context.addRect(rect.insetBy(dx: -layer.spread, dy: -layer.spread).offsetBy(dx: 0, dy: layer.spread / 2))
                context.addRect(rect)
                context.setFillColor(UIColor.black.withAlphaComponent(layer.alpha).cgColor)
                context.fillPath(using: .evenOdd)
            }
            if let image = pageImage(index, size: rect.size) {
                drawImage(image, in: rect, context: context)
            } else {
                context.setFillColor(UIColor.white.cgColor)
                context.fill(rect)
            }
        }
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
    private static let playheadFraction: CGFloat = 0.32
    private static let maximumScale: CGFloat = 2.2
    private static let tileWidth = 1024
    private static let tileCacheLimit = 6
    private static let edgeFadeWidth: CGFloat = 110

    private let page: ScoreVideoPageSource
    private let scale: CGFloat
    private let band: CGRect
    private let lineRects: [CGRect]
    private let path: ScoreVideoScrollPath
    private var tiles: [Int: CGImage] = [:]
    private var tileOrder: [Int] = []

    init(frameSize: CGSize, page: ScoreVideoPageSource, timeline: ScoreVideoTimeline, options: ScoreVideoExportOptions) {
        self.page = page
        // As large as the page styles, shrinking tall scores to fit the frame.
        scale = min(Self.maximumScale, (frameSize.height - 200) / max(page.size.height, 1))
        let bandHeight = (page.size.height * scale).rounded()
        band = CGRect(x: 0, y: ((frameSize.height - bandHeight) / 2).rounded(), width: frameSize.width, height: bandHeight)
        lineRects = timeline.regions.map { region in
            let rect = region.normalizedRect
            return CGRect(
                x: CGFloat(rect.x) * page.size.width,
                y: CGFloat(rect.y) * page.size.height,
                width: CGFloat(rect.width) * page.size.width,
                height: CGFloat(rect.height) * page.size.height
            )
        }
        path = ScoreVideoScrollPath(timeline: timeline, rects: lineRects)
        super.init(frameSize: frameSize, timeline: timeline, options: options)
    }

    func draw(into pixelBuffer: CVPixelBuffer, at time: TimeInterval, frameDuration: TimeInterval) {
        let playheadX = (frameSize.width * Self.playheadFraction).rounded()
        // Frame x of the line's left edge; the line position `path.x` sits under the playhead.
        let offsetX = (playheadX - path.x(at: time) * scale).rounded()

        withFrameContext(pixelBuffer) { context in
            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(origin: .zero, size: frameSize))
            drawLine(context, offsetX: offsetX)

            // Dim what has already played, easing into the playhead.
            let dimEnd = playheadX - 28
            context.setFillColor(UIColor.white.withAlphaComponent(0.42).cgColor)
            context.fill(CGRect(x: band.minX, y: band.minY, width: max(0, dimEnd - band.minX), height: band.height))
            drawHorizontalFade(context, from: dimEnd, to: playheadX - 4, startAlpha: 0.42, endAlpha: 0)
            drawHorizontalFade(context, from: band.minX, to: band.minX + Self.edgeFadeWidth, startAlpha: 1, endAlpha: 0)
            drawHorizontalFade(context, from: band.maxX, to: band.maxX - Self.edgeFadeWidth, startAlpha: 1, endAlpha: 0)

            let current = drawMeasureHighlights(context, time: time) { index in
                let rect = self.lineRects[index]
                return CGRect(x: offsetX + rect.minX * self.scale, y: self.band.minY + rect.minY * self.scale,
                              width: rect.width * self.scale, height: rect.height * self.scale)
            }
            let top = (current?.minY ?? band.minY) - 12
            let bottom = (current?.maxY ?? band.maxY) + 12
            drawPlayhead(context, x: playheadX, top: top, bottom: bottom, alpha: endFade(time))
            drawPinnedTitle()
            drawProgress(context, time: time, onPaper: true)
        }
    }

    /// Title and composer centred above the music for the whole video.
    private func drawPinnedTitle() {
        let title = options.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let composer = options.composer.trimmingCharacters(in: .whitespacesAndNewlines)
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        centered.lineBreakMode = .byTruncatingTail
        let titleText = NSAttributedString(string: title, attributes: [
            .font: UIFont.systemFont(ofSize: 40, weight: .semibold),
            .foregroundColor: UIColor(red: 0.12, green: 0.14, blue: 0.18, alpha: 1),
            .paragraphStyle: centered
        ])
        let composerText = NSAttributedString(string: composer, attributes: [
            .font: UIFont.systemFont(ofSize: 24, weight: .medium),
            .foregroundColor: UIColor(red: 0.12, green: 0.14, blue: 0.18, alpha: 0.6),
            .paragraphStyle: centered
        ])
        let width = frameSize.width - 160
        let titleHeight = ceil(titleText.size().height)
        let composerHeight = composer.isEmpty ? 0 : ceil(composerText.size().height)
        let blockHeight = titleHeight + (composer.isEmpty ? 0 : 6 + composerHeight)
        // Centred in the space above the music, never closer than 40 pt to the top.
        let top = max(40, (band.minY - blockHeight) / 2)
        titleText.draw(in: CGRect(x: 80, y: top, width: width, height: titleHeight))
        if !composer.isEmpty {
            composerText.draw(in: CGRect(x: 80, y: top + titleHeight + 6, width: width, height: composerHeight))
        }
    }

    /// Draws the tiles of the line that fall inside the frame.
    private func drawLine(_ context: CGContext, offsetX: CGFloat) {
        let lineWidth = Int((page.size.width * scale).rounded())
        let firstTile = max(0, Int(floor(-offsetX / CGFloat(Self.tileWidth))))
        let lastTile = min((lineWidth - 1) / Self.tileWidth, Int(floor((frameSize.width - offsetX) / CGFloat(Self.tileWidth))))
        guard firstTile <= lastTile else { return }
        for tileIndex in firstTile...lastTile {
            let originX = tileIndex * Self.tileWidth
            let width = min(Self.tileWidth, lineWidth - originX)
            guard let image = tile(tileIndex, width: width) else { continue }
            drawImage(image, in: CGRect(x: offsetX + CGFloat(originX), y: band.minY, width: CGFloat(width), height: band.height),
                      context: context)
        }
    }

    private func tile(_ index: Int, width: Int) -> CGImage? {
        if let image = tiles[index] {
            return image
        }
        guard let image = page.tile(scale: scale, originX: CGFloat(index * Self.tileWidth),
                                    pixelWidth: width, pixelHeight: Int(band.height)) else {
            return nil
        }
        tiles[index] = image
        tileOrder.append(index)
        if tileOrder.count > Self.tileCacheLimit {
            tiles[tileOrder.removeFirst()] = nil
        }
        return image
    }

    /// Paper-coloured fade over the band between two x positions.
    private func drawHorizontalFade(_ context: CGContext, from startX: CGFloat, to endX: CGFloat, startAlpha: CGFloat, endAlpha: CGFloat) {
        let colors = [
            UIColor.white.withAlphaComponent(startAlpha).cgColor,
            UIColor.white.withAlphaComponent(endAlpha).cgColor
        ] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
        context.saveGState()
        context.clip(to: CGRect(x: min(startX, endX), y: band.minY, width: abs(endX - startX), height: band.height))
        context.drawLinearGradient(gradient, start: CGPoint(x: startX, y: 0), end: CGPoint(x: endX, y: 0), options: [])
        context.restoreGState()
    }
}

/// Renders the performance audio in order, adding the same reverb as in-app
/// playback: a send of every part's signal to MuseScore's default reverb.
final class ScoreVideoAudioStream {
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
            metronomeEnabled: false
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

struct ScoreVideoAudioChunk {
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
