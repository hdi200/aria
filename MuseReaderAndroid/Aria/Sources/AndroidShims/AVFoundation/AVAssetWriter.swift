// The part of AVAssetWriter the video export uses (ScoreVideoExporter.render): an MP4
// with one H.264 video input fed through a pixel buffer adaptor and one AAC audio input
// fed float PCM sample buffers. Encoding happens in Kotlin (AriaVideoWriter.kt); it is
// synchronous, so inputs are always ready for more.
#if os(Android)
import CoreMedia
import SkipFuse
import UIKit

public struct AVFileType: Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let mp4 = AVFileType(rawValue: "public.mpeg-4")
    public static let mov = AVFileType(rawValue: "com.apple.quicktime-movie")
}

public struct AVMediaType: Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let video = AVMediaType(rawValue: "vide")
    public static let audio = AVMediaType(rawValue: "soun")
}

public struct AVVideoCodecType: Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let h264 = AVVideoCodecType(rawValue: "avc1")
}

public let AVVideoCodecKey = "AVVideoCodecKey"
public let AVVideoWidthKey = "AVVideoWidthKey"
public let AVVideoHeightKey = "AVVideoHeightKey"
public let AVVideoCompressionPropertiesKey = "AVVideoCompressionPropertiesKey"
public let AVVideoAverageBitRateKey = "AverageBitRate"
public let AVVideoMaxKeyFrameIntervalKey = "MaxKeyFrameInterval"
public let AVVideoProfileLevelKey = "ProfileLevel"
public let AVVideoProfileLevelH264HighAutoLevel = "H264_High_AutoLevel"
public let AVEncoderBitRateKey = "AVEncoderBitRateKey"
public let kAudioFormatMPEG4AAC: UInt32 = 0x61616320

public struct AVAssetWriterError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}

public final class AVAssetWriter: @unchecked Sendable {
    public enum Status: Int, Sendable {
        case unknown = 0
        case writing = 1
        case completed = 2
        case failed = 3
        case cancelled = 4
    }

    public let outputURL: URL
    public private(set) var status: Status = .unknown
    public private(set) var error: Error?
    private var inputs: [AVAssetWriterInput] = []
    private let writer: AnyDynamicObject
    private var frameRate = 30

    public init(outputURL: URL, fileType: AVFileType) throws {
        self.outputURL = outputURL
        do {
            writer = try AnyDynamicObject(className: "aria.skip.AriaVideoWriter")
        } catch {
            throw AVAssetWriterError(message: "The video encoder is not available.")
        }
    }

    public func canAdd(_ input: AVAssetWriterInput) -> Bool {
        status == .unknown && !inputs.contains { $0.mediaType == input.mediaType }
    }

    public func add(_ input: AVAssetWriterInput) {
        input.writer = self
        inputs.append(input)
    }

    public func startWriting() -> Bool {
        guard let video = inputs.first(where: { $0.mediaType == .video })?.outputSettings,
              let audio = inputs.first(where: { $0.mediaType == .audio })?.outputSettings
        else {
            fail("The export needs a video and an audio input.")
            return false
        }
        let compression = video[AVVideoCompressionPropertiesKey] as? [String: Any] ?? [:]
        let width = Self.int(video[AVVideoWidthKey]) ?? 1920
        let height = Self.int(video[AVVideoHeightKey]) ?? 1080
        let bitRate = Self.int(compression[AVVideoAverageBitRateKey]) ?? 10_000_000
        let keyFrameInterval = Self.int(compression[AVVideoMaxKeyFrameIntervalKey]) ?? 60
        let sampleRate = Self.int(audio[AVSampleRateKey]) ?? 44100
        let channels = Self.int(audio[AVNumberOfChannelsKey]) ?? 2
        let audioBitRate = Self.int(audio[AVEncoderBitRateKey]) ?? 192_000
        // A key frame every two seconds at the usual 30 fps; the interval is in frames.
        frameRate = 30
        let opened: Bool = (try? writer.open(outputURL.path, width, height, frameRate, bitRate,
                                             max(1, keyFrameInterval / frameRate), sampleRate, channels, audioBitRate)) ?? false
        guard opened else {
            fail(writerError() ?? "The video encoder did not start.")
            return false
        }
        status = .writing
        return true
    }

    public func startSession(atSourceTime startTime: CMTime) {}

    public func finishWriting() async {
        guard status == .writing else { return }
        let finished: Bool = (try? writer.finish()) ?? false
        if finished {
            status = .completed
        } else {
            fail(writerError() ?? "The video did not finish.")
        }
    }

    public func cancelWriting() {
        guard status == .writing || status == .unknown else { return }
        try? writer.cancel() as Void?
        status = .cancelled
        try? FileManager.default.removeItem(at: outputURL)
    }

    func appendFrame(_ buffer: CVPixelBuffer, at time: CMTime) -> Bool {
        guard status == .writing else { return false }
        let micros = Int64((time.seconds * 1_000_000).rounded())
        let appended: Bool = (try? writer.appendFrame(buffer.bitmapID, micros)) ?? false
        if !appended { fail(writerError() ?? "A frame was rejected.") }
        return appended
    }

    func appendAudio(_ buffer: CMSampleBuffer) -> Bool {
        guard status == .writing else { return false }
        let micros = Int64((buffer.presentationTimeStamp.seconds * 1_000_000).rounded())
        let appended: Bool = (try? writer.appendAudio(buffer.samples, micros)) ?? false
        if !appended { fail(writerError() ?? "Audio was rejected.") }
        return appended
    }

    private func writerError() -> String? {
        let message: String = (try? writer.getError()) ?? ""
        return message.isEmpty ? nil : message
    }

    private func fail(_ message: String) {
        status = .failed
        error = AVAssetWriterError(message: message)
    }

    private static func int(_ value: Any?) -> Int? {
        switch value {
        case let value as Int: return value
        case let value as Double: return Int(value)
        case let value as Float: return Int(value)
        case let value as UInt32: return Int(value)
        case let value as Int32: return Int(value)
        default: return nil
        }
    }
}

public final class AVAssetWriterInput: @unchecked Sendable {
    public let mediaType: AVMediaType
    public let outputSettings: [String: Any]?
    public var expectsMediaDataInRealTime = false
    weak var writer: AVAssetWriter?
    private var finished = false

    public init(mediaType: AVMediaType, outputSettings: [String: Any]?) {
        self.mediaType = mediaType
        self.outputSettings = outputSettings
    }

    public var isReadyForMoreMediaData: Bool {
        !finished && writer?.status == .writing
    }

    public func append(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard !finished, mediaType == .audio else { return false }
        return writer?.appendAudio(sampleBuffer) ?? false
    }

    public func markAsFinished() {
        finished = true
    }
}

public final class AVAssetWriterInputPixelBufferAdaptor: @unchecked Sendable {
    public let assetWriterInput: AVAssetWriterInput
    public let pixelBufferPool: CVPixelBufferPool?

    public init(assetWriterInput input: AVAssetWriterInput, sourcePixelBufferAttributes: [String: Any]?) {
        assetWriterInput = input
        let width = sourcePixelBufferAttributes?[kCVPixelBufferWidthKey] as? Int
            ?? input.outputSettings?[AVVideoWidthKey] as? Int ?? 1920
        let height = sourcePixelBufferAttributes?[kCVPixelBufferHeightKey] as? Int
            ?? input.outputSettings?[AVVideoHeightKey] as? Int ?? 1080
        pixelBufferPool = CVPixelBufferPool(width: width, height: height)
    }

    public func append(_ pixelBuffer: CVPixelBuffer, withPresentationTime presentationTime: CMTime) -> Bool {
        guard assetWriterInput.isReadyForMoreMediaData else { return false }
        return assetWriterInput.writer?.appendFrame(pixelBuffer, at: presentationTime) ?? false
    }
}
#endif
