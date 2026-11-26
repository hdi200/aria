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
    static let currentVersion = 7

    // Anyone who got the app before November 27, 2026 (12:00 AM Eastern) sees the
    // notice once, as soon as they have this update.
    // AppTransaction supplies Apple's signed date for when this customer first
    // acquired the app, which survives the update itself (on Android, the first install
    // time on the device).
    static let releaseDate = Date(timeIntervalSince1970: 1_795_755_600)

    /// The scanning release (version 6, November 18, 2026 12:00 AM Eastern). Customers
    /// who had the app before then but never saw that notice still get its scanning page.
    static let scannerVersion = 6
    static let scannerReleaseDate = Date(timeIntervalSince1970: 1_794_978_000)

    private let defaultsKey = "UpdateNotice.seenVersion"
    private var audienceKey: String {
        "UpdateNotice.v\(Self.currentVersion).isExistingInstall"
    }
    private var scannerKey: String {
        "UpdateNotice.v\(Self.currentVersion).showsScanner"
    }
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    static func isExistingInstall(originalPurchaseDate: Date) -> Bool {
        originalPurchaseDate < releaseDate
    }

    static func missedScannerNotice(originalPurchaseDate: Date, seenVersion: Int) -> Bool {
        seenVersion < scannerVersion && originalPurchaseDate < scannerReleaseDate
    }

    /// Whether this notice also shows the scanning page, decided with the audience.
    var showsScannerFeature: Bool {
        userDefaults.bool(forKey: scannerKey)
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

        let seenVersion = userDefaults.integer(forKey: defaultsKey)
        guard seenVersion < Self.currentVersion else {
            return false
        }
        if userDefaults.object(forKey: audienceKey) != nil {
            return userDefaults.bool(forKey: audienceKey)
        }

        let isExistingInstall = Self.isExistingInstall(originalPurchaseDate: originalPurchaseDate)
        userDefaults.set(
            Self.missedScannerNotice(originalPurchaseDate: originalPurchaseDate, seenVersion: seenVersion),
            forKey: scannerKey
        )
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
    /// Adds the scanning page for customers who never saw the scanning release's notice.
    var showsScannerFeature = false
    var openLibraryAction: (() -> Void)? = nil

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
        var isScannerFeature = false
        var isDrumFeature = false
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
    // generate-symbols.py lists them; textformat, checkmark.circle and the percussion page's drum,
    // shift and waveform are on it.
    private static var fixes: [Item] {
        let shared = [
            Item(
                systemImage: "checkmark.circle",
                title: "Editing crashes",
                detail: "Fixed crashes when editing tuplets, changing time signatures, deleting bars "
                    + "and undoing after opening a part."
            ),
            Item(
                systemImage: "checkmark.circle",
                title: "Selection when zoomed in",
                detail: "The selection stays on its note after an edit, and the page no longer shows notes "
                    + "doubled while it redraws."
            ),
            Item(
                systemImage: "checkmark.circle",
                title: "Score fixes",
                detail: "A hyphen in a lyric no longer brings up Review Score Fixes, and fixes you skipped "
                    + "aren't offered again."
            ),
            Item(
                systemImage: "checkmark.circle",
                title: "Renaming setlists",
                detail: "Setlists now keep their new name."
            ),
        ]
        #if os(Android)
        return shared + [
            Item(
                systemImage: "checkmark.circle",
                title: "Importing scores",
                detail: "Import works when another file manager is your default, as on Galaxy tablets, "
                    + "and tells you when a file can't be read."
            ),
            Item(
                systemImage: "checkmark.circle",
                title: "Scanning with the camera",
                detail: "If the document scanner doesn't open, Aria uses your camera app instead."
            ),
            Item(
                systemImage: "checkmark.circle",
                title: "Instruments and templates",
                detail: "Close and Done stay on screen when the keyboard is up."
            ),
            Item(
                systemImage: "checkmark.circle",
                title: "Library on tablets",
                detail: "Scan and Import have room again in landscape."
            ),
        ]
        #else
        return [
            Item(
                systemImage: "checkmark.circle",
                title: "Apple Pencil",
                detail: "Fixed a crash when turning on editing or annotations with Apple Pencil.",
                isPadOnly: true
            ),
        ] + shared
        #endif
    }

    private static var items: [Item] {
        [
            Item(
                systemImage: "textformat",
                title: "Fonts from other computers",
                detail: "Scores set in Arial, Times New Roman, Calibri and other common fonts keep their "
                    + "spacing and line breaks, even when your device doesn't have the font."
            ),
        ]
    }

    private var pages: [Page] {
        var pages = [
            Page(
                clip: nil,
                systemImage: "sparkles",
                title: "Percussion editing",
                message: "",
                isDrumFeature: true
            ),
        ]
        if showsScannerFeature {
            pages.append(Page(
                clip: nil,
                systemImage: "sparkles",
                title: "Scan sheet music",
                message: "",
                isScannerFeature: true
            ))
        }
        pages.append(Page(
            clip: nil,
            systemImage: "checkmark.circle",
            title: "Also in this update",
            message: "",
            items: Self.items,
            fixes: Self.fixes
        ))
        return pages
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
        if page.isDrumFeature {
            GeometryReader { geometry in
                ScrollView {
                    DrumPadUpdateFeature(contentWidth: max(1, geometry.size.width - 48))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 20)
                }
            }
        } else if page.isScannerFeature {
            GeometryReader { geometry in
                ScrollView {
                    ScannerUpdateFeature(contentWidth: max(1, geometry.size.width - 48),
                                         openLibraryAction: openLibraryAction)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 20)
                }
            }
        } else if page.items.isEmpty {
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
                                    .font(.system(size: 17, weight: .semibold))
                                    .monospacedDigit()
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

/// The featured opening page of the existing versioned What's New notice.
/// Artwork is the owner's selected Ain't Misbehavin' sheet and its actual Aria scan.
struct ScannerUpdateFeature: View {
    var original: Image = Image("ScanUpdateOriginal")
    var result: Image = Image("ScanUpdateResult")
    var contentWidth: CGFloat = 342
    var openLibraryAction: (() -> Void)? = nil
    private let blue = Color(red: 0.0, green: 0.478, blue: 1.0)

    var body: some View {
        VStack(spacing: 8) {
            Text("SCANNING · BETA")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(blue)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(blue.opacity(0.08), in: Capsule())

            VStack(spacing: 12) {
                Text("Scan your\nsheet music.")
                    .font(.system(size: 36, weight: .bold))
                    .tracking(-1.1)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("Turn a PDF or photo into a score you can play, transpose and edit.")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            illustration
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("A printed Ain’t Misbehavin’ page becomes an editable score in Aria")

            Divider()

            HStack(alignment: .top, spacing: 8) {
                benefit("Multi-page PDFs", symbol: "doc.text")
                benefit("Chords & lyrics", textSymbol: "♫")
                benefit("On-device\nscanning", symbol: "cpu")
            }
            .padding(.vertical, 3)

            Divider()

            Group {
                if let openLibraryAction {
                    Button(action: openLibraryAction) { libraryRow }
                        .buttonStyle(.plain)
                        .accessibilityHint("Returns to your library, where you can choose Scan")
                        .accessibilityIdentifier("updateNoticeOpenLibrary")
                } else {
                    libraryRow
                }
            }
            .padding(.horizontal, 16)

            Text("Scanning is in beta.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var illustration: some View {
        let width = min(contentWidth, 480)
        let paperWidth = width * 0.39
        let tabletWidth = width * 0.47
        let tabletHeight = (tabletWidth - 10) * 4 / 3 + 10
        let height = tabletHeight + 24
        return VStack(spacing: 10) {
            ZStack {
                original.resizable()
                    .scaledToFit()
                    .frame(width: paperWidth, height: paperWidth * 1724 / 1324)
                    .background(Color.white)
                    .overlay {
                        ScanUpdateCorners().stroke(blue, lineWidth: 2).padding(-4)
                    }
                    .shadow(color: .black.opacity(0.14), radius: 14, x: 0, y: 10)
                    .rotationEffect(.degrees(-5))
                    .position(x: width * 0.205, y: height / 2)

                Text("→")
                    .font(.system(size: width * 0.08, weight: .medium))
                    .foregroundStyle(blue)
                    .position(x: width * 0.46, y: height / 2)

                result.resizable()
                    .scaledToFit()
                    .frame(width: tabletWidth - 10, height: tabletHeight - 10)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(5)
                    .background(Color(white: 0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                    .overlay {
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.20), radius: 12, x: 0, y: 10)
                    .frame(width: tabletWidth, height: tabletHeight)
                    .position(x: width * 0.755, y: height / 2)
            }
            .frame(width: width, height: height)

        }
        .frame(maxWidth: .infinity)
    }

    private var libraryRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.system(size: 19))
                .accessibilityHidden(true)
            Text("Find Scan in your library.")
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .accessibilityHidden(true)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color.gray.opacity(0.07), in: RoundedRectangle(cornerRadius: 15))
        .contentShape(RoundedRectangle(cornerRadius: 15))
    }

    private func benefit(_ title: String, symbol: String? = nil, textSymbol: String? = nil) -> some View {
        VStack(spacing: 8) {
            Group {
                if let textSymbol {
                    Text(textSymbol)
                } else if let symbol {
                    Image(systemName: symbol)
                }
            }
            .font(.system(size: 22, weight: .medium))
            .foregroundStyle(blue)
            .frame(height: 26)
            .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 28, alignment: .top)
        }
        .frame(maxWidth: .infinity)
    }
}

/// The percussion editing page, led by a drum kit: the same pads the editor shows, drawn by the editor's own views.
struct DrumPadUpdateFeature: View {
    var contentWidth: CGFloat = 342
    private let blue = Color(red: 0.0, green: 0.478, blue: 1.0)

    private static func pad(_ pitch: Int, _ name: String, _ notehead: ScoreDrumPad.Notehead,
                            line: Int, voice: Int = 0, stemUp: Bool = true) -> ScoreDrumPad {
        ScoreDrumPad(pitch: pitch, name: name, shortcut: "", notehead: notehead, line: line,
                     voice: voice, stemUp: stemUp, panelRow: 0, panelColumn: 0)
    }

    /// A standard kit's essential drums, cymbals over drums as on the staff.
    private static let rows: [[ScoreDrumPad]] = [
        [
            pad(42, "Closed Hi-Hat", .cross, line: -1),
            pad(46, "Open Hi-Hat", .circleCross, line: -1),
            pad(49, "Crash", .cross, line: -2),
            pad(51, "Ride", .cross, line: 0),
        ],
        [
            pad(36, "Bass Drum", .normal, line: 7, voice: 1, stemUp: false),
            pad(38, "Snare", .normal, line: 3),
            pad(50, "High Tom", .normal, line: 1),
            pad(43, "Floor Tom", .normal, line: 5),
        ],
    ]

    var body: some View {
        VStack(spacing: 8) {
            Text("NEW · PERCUSSION EDITING")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(blue)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(blue.opacity(0.08), in: Capsule())

            VStack(spacing: 12) {
                Text("Tap in your\npercussion.")
                    .font(.system(size: 36, weight: .bold))
                    .tracking(-1.1)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("On a percussion staff, the keyboard becomes pads for that instrument, from snare "
                    + "and marching drums to concert percussion. Each one lands on its own line, in its own voice.")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                illustration
                Text("Drum kits open with the essentials first.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 10)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Drum kit pads: hi-hats, crash and ride over bass drum, snare and toms")

            Divider()

            HStack(alignment: .top, spacing: 8) {
                benefit("Drum kits\nand more", symbol: "drum")
                benefit("Add to beat", symbol: "shift")
                benefit("Sounds as\nyou tap", symbol: "waveform")
            }
            .padding(.vertical, 3)

            Divider()

            Text("Edit a percussion part and tap a beat to start.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var illustration: some View {
        let width = min(contentWidth, 480)
        let spacing: CGFloat = 6
        let padWidth = (width - 20 - spacing * 3) / 4
        let padHeight: CGFloat = 50
        return VStack(spacing: spacing) {
            ForEach(Self.rows.indices, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(Self.rows[row]) { pad in
                        ScoreReaderDrumPadKey(
                            pad: pad,
                            isActive: pad.pitch == 38,
                            isTall: false,
                            showsShortcut: false,
                            glyphHeight: padHeight - 10,
                            addsToBeat: false,
                            action: { _ in },
                            addAction: { _ in }
                        )
                        .frame(width: padWidth, height: padHeight)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .allowsHitTesting(false)
        .frame(maxWidth: .infinity)
    }

    private func benefit(_ title: String, symbol: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(blue)
                .frame(height: 26)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 28, alignment: .top)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Scan brackets around the printed sheet, drawn natively on both platforms.
struct ScanUpdateCorners: Shape {
    func path(in rect: CGRect) -> Path {
        let length: CGFloat = 10
        return Path { path in
            path.move(to: CGPoint(x: 0, y: length))
            path.addLine(to: .zero)
            path.addLine(to: CGPoint(x: length, y: 0))
            path.move(to: CGPoint(x: rect.width - length, y: 0))
            path.addLine(to: CGPoint(x: rect.width, y: 0))
            path.addLine(to: CGPoint(x: rect.width, y: length))
            path.move(to: CGPoint(x: rect.width, y: rect.height - length))
            path.addLine(to: CGPoint(x: rect.width, y: rect.height))
            path.addLine(to: CGPoint(x: rect.width - length, y: rect.height))
            path.move(to: CGPoint(x: length, y: rect.height))
            path.addLine(to: CGPoint(x: 0, y: rect.height))
            path.addLine(to: CGPoint(x: 0, y: rect.height - length))
        }
    }
}

/// A silent clip that loops without controls.
