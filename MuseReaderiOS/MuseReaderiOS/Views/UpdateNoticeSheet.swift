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
    static let currentVersion = 6

    // Anyone who got the app before November 18, 2026 (12:00 AM Eastern) sees the
    // notice once, as soon as they have this update.
    // AppTransaction supplies Apple's signed date for when this customer first
    // acquired the app, which survives the update itself (on Android, the first install
    // time on the device).
    static let releaseDate = Date(timeIntervalSince1970: 1_794_978_000)

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
        var textSymbol: String? = nil
        let title: String
        let detail: String
        /// Split View and Stage Manager are iPad-only, so iPhone skips the item.
        var isPadOnly = false
    }

    // Android shows only the SF Symbols Skip maps to Material icons (anything else is a "missing icon" warning):
    // camera.viewfinder, lock, list.bullet, square.and.arrow.up, play and checkmark.circle are on its list;
    // chords use a text glyph.
    private static let fixes: [Item] = {
        var fixes: [Item] = []
        #if !os(Android)
        fixes.append(Item(
            systemImage: "checkmark.circle",
            title: "Stylus input",
            detail: "Third-party styluses now enter notes instead of getting stuck in Select."
        ))
        #endif
        fixes += [
            Item(
                systemImage: "checkmark.circle",
                title: "Screen lock",
                detail: "The screen no longer locks during playback or the count-in."
            ),
            Item(
                systemImage: "checkmark.circle",
                title: "Replacing instruments",
                detail: "Sound, name and transposition now update in the score and its parts."
            ),
            Item(
                systemImage: "checkmark.circle",
                title: "Imported parts",
                detail: "Each part of an imported score opens with its own music."
            ),
            Item(
                systemImage: "checkmark.circle",
                title: "Reordering instruments",
                detail: "The new order now reaches the score."
            ),
        ]
        return fixes
    }()

    private static var items: [Item] {
        var items = [
            Item(
                systemImage: "camera.viewfinder",
                title: "Scan sheet music (Beta)",
                detail: "Tap Scan in your library to turn a PDF, an image or a photo into a score you can play, "
                    + "transpose and edit."
            ),
            Item(
                systemImage: "music.note",
                textSymbol: "♫",
                title: "Chords and lyrics too",
                detail: "Scanning reads chord symbols, lyrics, the title and composer, and repeats and endings, "
                    + "not just the notes."
            ),
            Item(
                systemImage: "list.bullet",
                title: "Multi-page PDFs",
                detail: "Every page is read into one score, keeping the printed line breaks."
            ),
            Item(
                systemImage: "lock",
                title: "Private and offline",
                detail: "Scanning runs entirely on your device. Nothing is uploaded."
            ),
        ]
        #if !os(Android)
        items.append(Item(
            systemImage: "square.and.arrow.up",
            title: "Share to Aria",
            detail: "Share a PDF or picture from Files, Photos or another app to scan it."
        ))
        #endif
        items.append(Item(
            systemImage: "music.note",
            textSymbol: "♪♪",
            title: "Voices on phones",
            detail: "Choose a voice when entering notes on your phone, not just on a tablet."
        ))
        items.append(Item(
            systemImage: "play",
            title: "D.S. and Coda play",
            detail: "D.S., D.C., To Coda and Fine now play as jumps in imported MusicXML files."
        ))
        return items
    }

    private var pages: [Page] {
        [
            Page(
                clip: nil,
                systemImage: "sparkles",
                title: "New in this update",
                message: "",
                items: Self.items,
                fixes: Self.fixes
            )
        ]
        .filter { !$0.isPadOnly || UIDevice.current.userInterfaceIdiom != .phone }
        .enumerated()
        .map { index, page in
            var page = page
            page.id = index
            return page
        }
    }

    private func shown(_ items: [Item]) -> [Item] {
        let isPhone = UIDevice.current.userInterfaceIdiom == .phone
        return items.filter { !$0.isPadOnly || !isPhone }
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
                        Group {
                            if let textSymbol = item.textSymbol {
                                Text(textSymbol)
                            } else {
                                Image(systemName: item.systemImage)
                            }
                        }
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
