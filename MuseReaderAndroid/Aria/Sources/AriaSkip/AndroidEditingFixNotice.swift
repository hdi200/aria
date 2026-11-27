import SwiftUI
import StoreKit

/// A one-time library message for Android phones that had the edit-mode offset fixed on
/// November 26, 2026 (IOS_CHANGES.md #144): the selection drew above the selected note and
/// taps landed below the finger.
///
/// The bug hit a phone when an edit-mode A4 page, as wide as the screen, came out shorter
/// than ScoreReaderPageCanvas's old 560-point page-height floor: narrower than about 396 dp
/// (most Samsung and OnePlus phones at their default display size). Installs from the
/// November 27 release on never had it, so they aren't told.
struct AndroidEditingFixNoticeStore {
    static let seenKey = "AndroidEditingFixNotice.seen"
    /// Decided once, so a later Display size change or split screen doesn't flip it.
    /// Set it to true (and `seenKey` to false) to force the message on a test install.
    static let audienceKey = "AndroidEditingFixNotice.isAffected"

    /// The old floor and A4's shape, from ScoreReaderPageCanvas.preferredPageHeight.
    static let oldMinimumPageHeight: CGFloat = 560
    static let a4HeightPerWidth: CGFloat = 842.0 / 595.0

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    /// `narrowSide` is the screen's shorter side in dp: its portrait width, where the edit
    /// page is as wide as the screen. Tablets are well over the limit.
    static func wasAffected(installDate: Date, narrowSide: CGFloat) -> Bool {
        installDate < UpdateNoticeStore.releaseDate
            && narrowSide > 0
            && narrowSide * a4HeightPerWidth < oldMinimumPageHeight
    }

    func shouldPresent() async -> Bool {
        guard !userDefaults.bool(forKey: Self.seenKey) else {
            return false
        }
        if userDefaults.object(forKey: Self.audienceKey) != nil {
            return userDefaults.bool(forKey: Self.audienceKey)
        }
        // Android's stand-in reports the first install time on this device.
        guard case .verified(let transaction) = try? await AppTransaction.shared else {
            return false
        }
        let screen = UIScreen.main.bounds.size
        let affected = Self.wasAffected(installDate: transaction.originalPurchaseDate,
                                        narrowSide: min(screen.width, screen.height))
        userDefaults.set(affected, forKey: Self.audienceKey)
        return affected
    }

    func markSeen() {
        userDefaults.set(true, forKey: Self.seenKey)
    }
}

/// Shows the message once when the library appears, after any launch sheet has closed.
struct AndroidEditingFixNotice: ViewModifier {
    var model: MuseReaderAppModel
    @State var isPresented = false
    @State var isChecking = false

    static let title = "Editing weirdness on your phone has been fixed"
    static let message = """
        On some Android phones, yours included, editing was a bit janky: tapping a note \
        could pick the one below it, and the blue highlight sat above the note instead of \
        on it. It came down to how Aria sized the page for your screen. That's fixed now, \
        so taps and highlights land right where you touch.

        Sorry about that, and thanks for using Aria.
        """

    func body(content: Content) -> some View {
        content
            .task {
                // Let the library and any launch sheet settle first.
                try? await Task.sleep(for: .milliseconds(800))
                await presentIfNeeded()
            }
            .onChangeCompatible(of: model.libraryAccessSheet?.id) { _ in
                Task { await presentIfNeeded() }
            }
            .alert(Self.title, isPresented: $isPresented) {
                Button("Done", role: .cancel) {}
            } message: {
                Text(Self.message)
            }
    }

    @MainActor
    private func presentIfNeeded() async {
        guard !isPresented, !isChecking, isLibraryIdle else {
            return
        }
        isChecking = true
        defer { isChecking = false }
        let store = AndroidEditingFixNoticeStore()
        guard await store.shouldPresent(), isLibraryIdle else {
            return
        }
        // Marked when shown: Back can close an Android dialog without running its button.
        store.markSeen()
        isPresented = true
    }

    private var isLibraryIdle: Bool {
        model.libraryAccessSheet == nil
            && !model.isReaderPresented
            && !model.isCreateScorePresented
            && !model.isImportingPresented
    }
}
