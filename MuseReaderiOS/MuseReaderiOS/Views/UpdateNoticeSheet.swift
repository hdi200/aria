import AVFoundation
import StoreKit
import SwiftUI

/// Remembers whether the update notice has been shown. Like the reader feature tour,
/// it tells people who already had the app what changed, so it is only for installs
/// that predate the release; a first-time user has nothing to be told is new.
///
/// Versioned so a later release can show a new notice by bumping `currentVersion`
/// and `releaseDate`.
struct UpdateNoticeStore {
    static let currentVersion = 2

    // Annotations and video export release on October 14, 2026 at
    // 12:00 AM Eastern: anyone who got the app before then sees the notice once.
    // AppTransaction supplies Apple's signed date for when this customer first
    // acquired the app, which survives the update itself.
    static let releaseDate = Date(timeIntervalSince1970: 1_791_950_400)

    private let defaultsKey = "UpdateNotice.seenVersion"
    private var audienceKey: String {
        "UpdateNotice.v\(Self.currentVersion).isExistingInstall"
    }
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    static func isExistingInstall(originalPurchaseDate: Date) -> Bool {
        originalPurchaseDate < releaseDate
    }

    /// A missing or unverified App Store transaction is left unresolved so a later
    /// launch can retry, instead of deciding the customer is new while offline.
    func shouldPresentNotice(now: Date = Date()) async -> Bool {
        guard now >= Self.releaseDate,
              userDefaults.integer(forKey: defaultsKey) < Self.currentVersion else {
            return false
        }
        if userDefaults.object(forKey: audienceKey) != nil {
            return userDefaults.bool(forKey: audienceKey)
        }

        guard let originalPurchaseDate = await verifiedOriginalPurchaseDate() else {
            return false
        }

        guard userDefaults.integer(forKey: defaultsKey) < Self.currentVersion else {
            return false
        }
        if userDefaults.object(forKey: audienceKey) != nil {
            return userDefaults.bool(forKey: audienceKey)
        }

        let isExistingInstall = Self.isExistingInstall(originalPurchaseDate: originalPurchaseDate)
        userDefaults.set(isExistingInstall, forKey: audienceKey)
        return isExistingInstall
    }

    func markNoticeSeen() {
        userDefaults.set(Self.currentVersion, forKey: defaultsKey)
    }

    private func verifiedOriginalPurchaseDate() async -> Date? {
        do {
            guard case .verified(let transaction) = try await AppTransaction.shared else {
                return nil
            }
            return transaction.originalPurchaseDate
        } catch {
            return nil
        }
    }
}

struct UpdateNoticeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private struct Page: Identifiable {
        /// Position among the pages shown on this device.
        var id = 0
        /// A looping clip in Resources/WhatsNew, or a symbol when there is none.
        let clip: String?
        let systemImage: String
        let title: String
        let message: String
        /// Annotations are iPad-only, so iPhone skips their page.
        var isPadOnly = false
        /// A list page of smaller changes, shown instead of the picture and message.
        var items: [Item] = []
    }

    private struct Item: Identifiable {
        var id: String { title }
        let systemImage: String
        let title: String
        let detail: String
    }

    // The clips are real exports: Bach's Orchestral Suite No. 2 scrolling over
    // a photo, and the Goldberg Aria on the piano over the moonlit fjord.
    private let pages: [Page] = [
        Page(
            clip: "whats-new-scrolling",
            systemImage: "film",
            title: "Turn your score into a video",
            message: "Open Share and choose Video. Your score scrolls smoothly as it plays, with playback "
                + "using your saved mix. Keep it on paper or set it over a photo, in landscape for YouTube "
                + "or vertical for Reels and TikTok."
        ),
        Page(
            clip: "whats-new-piano",
            systemImage: "pianokeys",
            title: "Or watch it on a piano",
            message: "Choose the Piano layout and the notes fall onto a keyboard, lighting each key as it plays. "
                + "Pick dark, light, or one of the nature photos."
        ),
        Page(
            clip: nil,
            systemImage: "pencil.tip.crop.circle",
            title: "Mark up your scores",
            message: "In View mode, tap the annotation button to write, draw, or highlight with your Apple Pencil "
                + "or finger. Each mark stays with its spot in the music, even when the layout changes. "
                + "Your annotations are saved with this score, ready for your next practice or rehearsal.",
            isPadOnly: true
        ),
        Page(
            clip: nil,
            systemImage: "sparkles",
            title: "Also in this update",
            message: "",
            items: [
                Item(
                    systemImage: "metronome",
                    title: "Count-in",
                    detail: "Touch and hold the metronome button to play one bar of clicks before playback starts."
                ),
                Item(
                    systemImage: "book.pages",
                    title: "Page scrubber",
                    detail: "Drag the slider at the bottom of the score to jump to any page."
                ),
                Item(
                    systemImage: "music.note.list",
                    title: "Swing and instruments",
                    detail: "Swing markings now swing in playback, and added instruments get the right key and drum staff."
                ),
            ]
        )
    ]
    .filter { !$0.isPadOnly || UIDevice.current.userInterfaceIdiom != .phone }
    .enumerated()
    .map { index, page in
        var page = page
        page.id = index
        return page
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $page) {
                ForEach(pages) { page in
                    pageView(page)
                        .tag(page.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 14) {
                    HStack(spacing: 8) {
                        ForEach(pages) { item in
                            Circle()
                                .fill(item.id == page ? Color.accentColor : Color.secondary.opacity(0.3))
                                .frame(width: 7, height: 7)
                        }
                    }
                    .accessibilityHidden(true)
                    Button {
                        if page < pages.count - 1 {
                            withAnimation { page += 1 }
                        } else {
                            dismiss()
                        }
                    } label: {
                        Text(page < pages.count - 1 ? "Next" : "Continue").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("updateNoticeContinue")
                }
                .padding()
            }
            .navigationTitle("What's New in Aria")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if page < pages.count - 1 {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Skip") { dismiss() }
                    }
                }
            }
        }
        .frame(maxWidth: 560)
        .presentationDetents([.large])
    }

    @ViewBuilder
    private func pageView(_ page: Page) -> some View {
        if page.items.isEmpty {
            mediaPageView(page)
        } else {
            listPageView(page)
        }
    }

    private func listPageView(_ page: Page) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(page.title)
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                ForEach(page.items) { item in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 44, height: 44)
                            .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(.body.weight(.semibold))
                            Text(item.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding()
        }
    }

    private func mediaPageView(_ page: Page) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Group {
                    if let clip = page.clip,
                       let url = Bundle.main.url(forResource: clip, withExtension: "mp4")
                        ?? Bundle.main.url(forResource: clip, withExtension: "mp4", subdirectory: "WhatsNew") {
                        UpdateNoticeLoopingVideo(url: url)
                    } else {
                        Image(systemName: page.systemImage)
                            .font(.system(size: 56))
                            .foregroundStyle(Color.accentColor)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.accentColor.opacity(0.08))
                    }
                }
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text(page.title).font(.title3.weight(.semibold))
                    Text(page.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            .padding()
        }
    }
}

/// A silent clip that loops without controls.
private struct UpdateNoticeLoopingVideo: UIViewRepresentable {
    let url: URL

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        var looper: AVPlayerLooper?
    }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        let player = AVQueuePlayer()
        // The clips have no sound; muting also keeps other audio playing.
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        view.looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        player.play()
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {}

    static func dismantleUIView(_ view: PlayerView, coordinator: ()) {
        view.playerLayer.player?.pause()
        view.looper = nil
    }
}
