// Android versions of the video export sheet's platform pieces (iOS:
// Views/ScoreReaderVideoPlatformViews.swift). The sheet itself is shared.

// Not limited to Android: the Skip project's own iOS build (a build step only; the iOS
// app is MuseReaderiOS/Aria.xcodeproj) compiles it in place of the held-back iOS file.
import AVFoundation
import Foundation
import SkipFuse
import SwiftUI

/// Shares the finished videos through Android's share chooser.
struct ScoreReaderVideoShareLink<Label: View>: View {
    let items: [URL]
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button {
            AndroidShareChooser.share(items)
        } label: {
            label()
        }
    }
}

/// The sheet fills the screen; Android has no iPad-style centered panel.
struct ScoreReaderVideoSheetSizing: ViewModifier {
    let preferredSize: CGSize?

    func body(content: Content) -> some View {
        content.presentationDetents([.large])
    }
}

/// The screen size: Android windows aren't resized like iPad's Split View.
struct ScoreReaderVideoWindowSizeReader: View {
    let onChange: (CGSize) -> Void

    var body: some View {
        Color.clear
            .onAppear { onChange(UIScreen.main.bounds.size) }
    }
}

/// The preview above the controls. iOS shrinks the preview to fit the iPad panel; the
/// Android sheet scrolls instead.
struct ScoreReaderVideoSettingsLayout<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
    }
}

/// The finished video's first frame; playing opens it in a video app.
struct ScoreReaderVideoPlayerView: View {
    let player: AVPlayer
    @State var poster: UIImage?
    @State var shownURL: URL?

    private var currentURL: URL? {
        (player.currentItem?.asset as? AVURLAsset)?.url
    }

    var body: some View {
        ZStack {
            if let poster {
                Image(uiImage: poster)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
            Button {
                Self.open(currentURL)
            } label: {
                Image(systemName: "play.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(Color.black.opacity(0.55), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play video")
            .disabled(currentURL == nil)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            // The player isn't observable here; follow its item while the sheet is open.
            while !Task.isCancelled {
                let url = currentURL
                if url != shownURL {
                    shownURL = url
                    poster = await Self.frame(of: url)
                }
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    private static func frame(of url: URL?) async -> UIImage? {
        guard let url else { return nil }
        let png = await Task.detached(priority: .userInitiated) { () -> Data? in
            guard let playback = try? AnyDynamicObject(className: "aria.skip.AriaVideoPlayback") else { return nil }
            return try? playback.frame(url.path, 1280)
        }.value
        return png.flatMap { UIImage(data: $0) }
    }

    private static func open(_ url: URL?) {
        guard let url, let playback = try? AnyDynamicObject(className: "aria.skip.AriaVideoPlayback") else { return }
        let opened: Bool? = try? playback.open(url.path)
        if opened != true {
            AndroidShareChooser.share([url])
        }
    }
}
