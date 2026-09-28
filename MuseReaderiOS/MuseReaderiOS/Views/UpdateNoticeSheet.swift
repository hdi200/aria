import StoreKit
import SwiftUI

/// Remembers whether the update notice has been shown. Like the reader feature tour,
/// it tells people who already had the app what changed, so it is only for installs
/// that predate the release; a first-time user has nothing to be told is new.
///
/// Versioned so a later release can show a new notice by bumping `currentVersion`
/// and `releaseDate`.
struct UpdateNoticeStore {
    static let currentVersion = 1

    // The MuseScore 4.7.5 engine update began its release on September 24, 2026 at
    // 12:00 PM Eastern. AppTransaction supplies Apple's signed date for when this
    // customer first acquired the app, which survives the update itself.
    static let releaseDate = Date(timeIntervalSince1970: 1_790_265_600)

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
    func shouldPresentNotice() async -> Bool {
        guard userDefaults.integer(forKey: defaultsKey) < Self.currentVersion else {
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
            systemImage: "wrench.and.screwdriver",
            title: "Fixed: markings missing from parts/full score",
            message: "Sorry about this one! Dynamics, tempo markings, and repeat signs you added in earlier versions of "
                + "Aria didn't carry between a part and the full score. If you now reopen a score with "
                + "this problem, Aria will offer to fix it for you. Nothing changes until you tap Fix, "
                + "and Aria saves a copy of the original when you do. From now on, these markings "
                + "stay in sync between the full score and its parts."
        ),
        Item(
            id: 1,
            systemImage: "desktopcomputer",
            title: "Now in sync with MuseScore Studio 4.7.5",
            message: "Aria now uses the same engine as MuseScore Studio 4.7.5, so your scores look "
                + "the same here as on your computer. Scores save in MuseScore 4.7 format."
        )
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("This update fixes scores affected by earlier versions of Aria and brings Aria in line with MuseScore Studio 4.7.5.")
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
