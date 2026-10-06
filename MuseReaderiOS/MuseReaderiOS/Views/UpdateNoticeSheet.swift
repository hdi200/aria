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

    // Annotations and video export release on October 1, 2026 at
    // 12:00 PM Eastern. AppTransaction supplies Apple's signed date for when this
    // customer first acquired the app, which survives the update itself.
    static let releaseDate = Date(timeIntervalSince1970: 1_790_870_400)

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

    private struct Item: Identifiable {
        let id: Int
        let systemImage: String
        let title: String
        let message: String
    }

    private let items: [Item] = [
        Item(
            id: 0,
            systemImage: "pencil.tip.crop.circle",
            title: "Mark up your scores",
            message: "Tap the annotation button to write, draw, or highlight with your Apple Pencil or finger. "
                + "Choose your colors and line widths, erase marks, and undo changes. "
                + "Your annotations are saved with this score, ready for your next practice or rehearsal."
        ),
        Item(
            id: 1,
            systemImage: "film",
            title: "Share a play-along video",
            message: "Open Share, choose Video, then tap Video Export. Make a smoothly scrolling score "
                + "or a video that follows the music through the pages, with playback using your saved mix. "
                + "Keep the score on a plain background or add a photo with white notation."
        )
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Two new ways to practice and share your music: handwritten annotations and play-along videos.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ForEach(items) { item in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: item.systemImage)
                                .font(.title2)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 32)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).font(.headline)
                                Text(item.message)
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
            .safeAreaInset(edge: .bottom) {
                Button {
                    dismiss()
                } label: {
                    Text("Continue").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
                .accessibilityIdentifier("updateNoticeContinue")
            }
            .navigationTitle("What's New in Aria")
            .navigationBarTitleDisplayMode(.inline)
        }
        .frame(maxWidth: 560)
        .presentationDetents([.large])
    }
}
