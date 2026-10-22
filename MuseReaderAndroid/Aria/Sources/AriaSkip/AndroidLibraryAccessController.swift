// Android's LibraryAccessController: the same API and access rules as the iOS one
// (Services/LibraryAccessController.swift), with Google Play Billing (AriaBilling.kt)
// in place of StoreKit. Early-supporter grandfathering is App Store history, so it
// doesn't apply here; Play has no family sharing for one-time products.

// Not limited to Android: the Skip project's own iOS build (a build step only; the iOS
// app is MuseReaderiOS/Aria.xcodeproj) compiles it in place of the held-back iOS file.
import Foundation
import Observation
import SkipFuse

@MainActor
@Observable
final class LibraryAccessController {
    static let unlimitedScoresProductID = "com.hdi200.ariascore.unlimitedscores"

    private enum CacheKeys {
        static let verifiedUnlimitedReason = "Aria.LibraryAccess.VerifiedUnlimitedReason"
        static let verifiedFree = "Aria.LibraryAccess.VerifiedFree"
    }

    private(set) var status: LibraryAccessStatus
    private(set) var displayPrice: String?
    private(set) var isLoadingProduct = false
    private(set) var isPerformingPurchase = false

    private let userDefaults: UserDefaults
    private var hasStarted = false
    @ObservationIgnored private var purchaseUpdates: Task<Void, Never>?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let rawReason = userDefaults.string(forKey: CacheKeys.verifiedUnlimitedReason),
           let reason = UnlimitedScoresReason(rawValue: rawReason)
        {
            status = .unlimited(reason)
        } else if userDefaults.bool(forKey: CacheKeys.verifiedFree) {
            status = .free
        } else {
            // As on iOS, unknown access stays unrestricted until the store answers.
            status = .rolloutDisabled
        }
    }

    var isUsingDevelopmentOverride: Bool {
        false
    }

    func start() async {
        guard !hasStarted else {
            return
        }
        hasStarted = true
        await refreshEntitlements()
        purchaseUpdates = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                let changed = await Task.detached {
                    (try? AnyDynamicObject(className: "aria.skip.AriaBilling").takePurchaseChange()) as Bool? ?? false
                }.value
                if changed { await self?.refreshEntitlements() }
            }
        }
    }

    deinit { purchaseUpdates?.cancel() }

    func refreshEntitlements() async {
        if case .rolloutDisabled = status {
            status = .checking
        }

        switch await Self.billing("ownership", Self.unlimitedScoresProductID) {
        case "purchased":
            applyVerifiedStatus(.unlimited(.purchased))
        case "none", "pending":
            applyVerifiedStatus(
                LibraryAccessPolicy.resolveStatus(
                    originalAppVersion: nil,
                    purchaseReason: nil,
                    allowsGrandfathering: false
                )
            )
        default:
            // Play unreachable (offline, no Play services): keep a verified state,
            // fail open otherwise, like iOS without an AppTransaction.
            if case .checking = status {
                status = .rolloutDisabled
            }
        }

        if displayPrice == nil {
            await loadProduct()
        }
    }

    func purchaseUnlimitedScores() async -> LibraryPurchaseResult {
        isPerformingPurchase = true
        defer { isPerformingPurchase = false }

        let outcome = await Self.billing("purchase", Self.unlimitedScoresProductID) ?? "failed:"
        switch outcome {
        case "purchased":
            await refreshEntitlements()
            return status.hasUnlimitedScores
                ? .purchased
                : .failed("The purchase completed, but access could not be verified yet.")
        case "pending":
            return .pending
        case "cancelled":
            return .cancelled
        default:
            let message = outcome.hasPrefix("failed:") ? String(outcome.dropFirst("failed:".count)) : outcome
            return .failed(message.isEmpty ? "Aria Pro is temporarily unavailable. Please try again." : message)
        }
    }

    func restorePurchases() async -> LibraryPurchaseResult {
        isPerformingPurchase = true
        defer { isPerformingPurchase = false }

        await refreshEntitlements()
        return status.hasUnlimitedScores
            ? .restored
            : .failed("No Aria Pro purchase was found for this Google account.")
    }

    private func loadProduct() async {
        isLoadingProduct = true
        defer { isLoadingProduct = false }
        displayPrice = await Self.billing("displayPrice", Self.unlimitedScoresProductID)
    }

    private func applyVerifiedStatus(_ verifiedStatus: LibraryAccessStatus) {
        status = verifiedStatus
        if let reason = verifiedStatus.unlimitedReason {
            userDefaults.set(reason.rawValue, forKey: CacheKeys.verifiedUnlimitedReason)
            userDefaults.removeObject(forKey: CacheKeys.verifiedFree)
        } else if verifiedStatus == .free {
            userDefaults.removeObject(forKey: CacheKeys.verifiedUnlimitedReason)
            userDefaults.set(true, forKey: CacheKeys.verifiedFree)
        } else {
            userDefaults.removeObject(forKey: CacheKeys.verifiedUnlimitedReason)
            userDefaults.removeObject(forKey: CacheKeys.verifiedFree)
        }
    }

    /// Calls a blocking AriaBilling function off the main thread.
    private nonisolated static func billing(_ function: String, _ productID: String) async -> String? {
        await Task.detached {
            do {
                let billing = try AnyDynamicObject(className: "aria.skip.AriaBilling")
                switch function {
                case "ownership":
                    return try billing.ownership(productID) as String?
                case "purchase":
                    return try billing.purchase(productID) as String?
                default:
                    return try billing.displayPrice(productID) as String?
                }
            } catch {
                print("Aria Play Billing \(function) failed: \(error)")
                return nil
            }
        }.value
    }
}
