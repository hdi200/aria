// The AVPlayer and AVURLAsset the video export sheet uses. Android shows the finished
// video's first frame and opens it in a video app (ScoreReaderVideoPlayerView,
// AriaVideoPlayback.kt), so the player only tracks its item.
#if os(Android)
import CoreMedia
import SkipFuse

public extension AVAudioSession.Mode {
    static let moviePlayback = AVAudioSession.Mode(name: "moviePlayback")
}

public struct AVAssetLoadKey: Sendable {
    let name: String
    public static let duration = AVAssetLoadKey(name: "duration")
}

public final class AVURLAsset: @unchecked Sendable {
    public let url: URL

    public init(url: URL, options: [String: Any]? = nil) {
        self.url = url
    }

    /// The duration (the one property the shared code loads).
    public func load(_ key: AVAssetLoadKey) async throws -> CMTime {
        let playback = try? AnyDynamicObject(className: "aria.skip.AriaVideoPlayback")
        let path = url.path
        let seconds: Double = (try? playback?.duration(path)) ?? 0
        return CMTime(value: CMTimeValue((seconds * 600).rounded()), timescale: 600)
    }
}

public final class AVPlayerItem: @unchecked Sendable {
    public let asset: AVURLAsset

    public init(url: URL) {
        asset = AVURLAsset(url: url)
    }
}

public final class AVPlayer: @unchecked Sendable {
    public private(set) var currentItem: AVPlayerItem?

    public init() {}

    public func replaceCurrentItem(with item: AVPlayerItem?) {
        currentItem = item
    }

    public func play() {}
    public func pause() {}
}
#endif
