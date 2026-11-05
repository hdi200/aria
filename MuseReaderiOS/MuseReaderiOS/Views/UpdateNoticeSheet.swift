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
    static let currentVersion = 4

    // Anyone who got the app on or before November 5, 2026 (before November 6 at
    // 12:00 AM Eastern) sees the notice once, as soon as they have this update.
    // AppTransaction supplies Apple's signed date for when this customer first
    // acquired the app, which survives the update itself (on Android, the first install
    // time on the device).
    static let releaseDate = Date(timeIntervalSince1970: 1_793_941_200)

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
    @Environment(\.dismiss) var dismiss
    @State var page = 0

    /// iOS's system blue. Android's accent colour is the Material theme's slate.
    #if os(Android)
    static let accent = Color(red: 0.0, green: 0.478, blue: 1.0)
    #else
    static let accent = Color.accentColor
    #endif

    struct Page: Identifiable {
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
        /// Shown under `items`, headed "Fixes".
        var fixes: [Item] = []
    }

    struct Item: Identifiable {
        var id: String { title }
        let systemImage: String
        let title: String
        let detail: String
        /// Split View and Stage Manager are iPad-only, so iPhone skips the item.
        var isPadOnly = false
        /// Listed first on an iPhone Duo and last everywhere else.
        var isDuo = false
    }

    private static let fixes: [Item] = {
        let engine = Item(
            systemImage: "checkmark.circle",
            title: "MuseScore Studio 4.7.6",
            detail: "Aria now uses the same engine as the latest desktop release."
        )
        #if os(Android)
        return [
            Item(
                systemImage: "checkmark.circle",
                title: "Open with",
                detail: "Aria now shows up in Files by Google and other file managers that label scores "
                    + "as zip files. Opening a score while another is open now works too."
            ),
            engine,
        ]
        #else
        return [
            Item(
                systemImage: "checkmark.circle",
                title: "Playback cursor",
                detail: "It no longer covers tab numbers or notes at the edges of the bar."
            ),
            Item(
                systemImage: "checkmark.circle",
                title: "Opening scores from other apps",
                detail: "Opening a score while another is open now saves the first one and opens the new one."
            ),
            Item(
                systemImage: "checkmark.circle",
                title: "Highlighter marks",
                detail: "They keep their shape after you edit the score.",
                isPadOnly: true
            ),
            Item(
                systemImage: "checkmark.circle",
                title: "Transpose",
                detail: "The sheet now starts at the top instead of leaving a gap."
            ),
            engine,
        ]
        #endif
    }()

    private static let items: [Item] = {
        let shared = [
            Item(
                systemImage: "hand.point.up.left",
                title: "Fingering",
                detail: "Choose Text > Fingering and tap 1 to 5. Aria moves on to the next note by itself, skipping rests."
            ),
            Item(
                systemImage: "music.note.list",
                title: "More note entry tools",
                detail: "Tap the arrow at the end of the note-entry toolbar for 32nd and 64th notes, grace notes, "
                    + "trills, tremolos, double sharps and flats, and more."
            ),
            Item(
                systemImage: "doc.on.doc",
                title: "Duplicate scores",
                detail: "Touch and hold a score in the library, then choose Duplicate."
            ),
            Item(
                systemImage: "pianokeys",
                title: "Redesigned chord entry",
                detail: "Build chord symbols with buttons for the root, quality, extension and bass instead of "
                    + "typing them. Previous and Next step through the score."
            ),
            Item(
                systemImage: "metronome",
                title: "Tempo text",
                detail: "Add words like \"Allegro\" to a tempo marking. Playback still follows the number."
            ),
        ]
        #if os(Android)
        return shared
        #else
        return shared + [
            Item(
                systemImage: "rectangle.split.2x1",
                title: "Split View and Stage Manager",
                detail: "In a narrow window, Aria switches to its iPhone layout so everything fits.",
                isPadOnly: true
            ),
            Item(
                systemImage: "book.pages",
                title: "iPhone Duo",
                detail: "Read two pages side by side like a book, edit with your tools on the other page, "
                    + "or stand it up like a music stand.",
                isDuo: true
            ),
        ]
        #endif
    }()

    private let pages: [Page] = [
        Page(
            clip: nil,
            systemImage: "sparkles",
            title: "New in this update",
            message: "",
            items: items,
            fixes: fixes
        )
    ]
    .filter { !$0.isPadOnly || UIDevice.current.userInterfaceIdiom != .phone }
    .enumerated()
    .map { index, page in
        var page = page
        page.id = index
        return page
    }

    /// Drops iPad-only items on iPhone, and moves the iPhone Duo item to the top on a Duo
    /// (it stays last everywhere else). Read in `body`, so the order follows the pose
    /// monitor once it has heard from the hinge.
    private func shown(_ items: [Item]) -> [Item] {
        let isPhone = UIDevice.current.userInterfaceIdiom == .phone
        let fitting = items.filter { !$0.isPadOnly || !isPhone }
        #if os(Android)
        return fitting
        #else
        guard DuoPoseMonitor.shared.pose.isDuo else { return fitting }
        return fitting.filter(\.isDuo) + fitting.filter { !$0.isDuo }
        #endif
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
                    if pages.count > 1 {
                    HStack(spacing: 8) {
                        ForEach(pages) { item in
                            Circle()
                                .fill(item.id == page ? Self.accent : Color.secondary.opacity(0.3))
                                .frame(width: 7, height: 7)
                        }
                    }
                    .accessibilityHidden(true)
                    }
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
                    .tint(Self.accent)
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
        #if !os(Android)
        // Skip lays this out as a fixed 560-point width, wider than an Android phone.
        .frame(maxWidth: 560)
        #endif
        .tint(Self.accent)
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
                ForEach(shown(page.items)) { item in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Self.accent)
                            .frame(width: 44, height: 44)
                            .background(Self.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                if !page.fixes.isEmpty {
                    Text("Fixes")
                        .font(.title3.weight(.semibold))
                        .padding(.top, 6)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(shown(page.fixes)) { item in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: item.systemImage)
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(Self.accent)
                                .frame(width: 44, height: 24)
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
                            .foregroundStyle(Self.accent)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Self.accent.opacity(0.08))
                    }
                }
                #if os(Android)
                // Skip doesn't size this by aspect ratio; about 16:9 on a phone-width sheet.
                .frame(height: 200)
                #else
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                #endif
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
