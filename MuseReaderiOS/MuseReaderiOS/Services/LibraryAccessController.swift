//
//  LibraryAccessController.swift
//  MuseReaderiOS
//

import Observation
import Foundation
import StoreKit

extension LibraryAccessPolicy {
    static func allowsGrandfathering(in environment: AppStore.Environment) -> Bool {
        // StoreKit reports a synthetic originalAppVersion of 1.0 in Xcode and
        // sandbox/TestFlight. Only production carries the customer's real
        // acquisition build, so only production can safely grandfather users.
        environment == .production
    }
}

@MainActor
@Observable
final class LibraryAccessController {
    static let unlimitedScoresProductID = "com.hdi200.ariascore.unlimitedscores"

    private enum CacheKeys {
        static let verifiedUnlimitedReason = "Aria.LibraryAccess.VerifiedUnlimitedReason"
        static let verifiedFree = "Aria.LibraryAccess.VerifiedFree"
    }

    private(set) var status: LibraryAccessStatus
    private(set) var product: Product?
    private(set) var isLoadingProduct = false
    private(set) var isPerformingPurchase = false

    private let userDefaults: UserDefaults
    private let simulationOverride: LibraryAccessSimulationOverride?
    private let originalAppVersionSimulation: LibraryOriginalAppVersionSimulation?
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    private var hasStarted = false

    init(
        userDefaults: UserDefaults = .standard,
        simulationOverride explicitSimulationOverride: LibraryAccessSimulationOverride? = nil,
        originalAppVersionSimulation explicitOriginalAppVersionSimulation: LibraryOriginalAppVersionSimulation? = nil
    ) {
        self.userDefaults = userDefaults
        // Xcode Run uses Debug, so these launch arguments can exercise access
        // states on development devices. Archive/App Store builds omit this path.
        #if DEBUG
        let originalAppVersionSimulation = explicitOriginalAppVersionSimulation
            ?? LibraryOriginalAppVersionSimulation.fromLaunchArguments(ProcessInfo.processInfo.arguments)
        let simulationOverride = explicitSimulationOverride
            ?? (originalAppVersionSimulation == nil
                ? LibraryAccessSimulationOverride.fromLaunchArguments(ProcessInfo.processInfo.arguments)
                : nil)
        #else
        let simulationOverride: LibraryAccessSimulationOverride? = nil
        let originalAppVersionSimulation: LibraryOriginalAppVersionSimulation? = nil
        #endif
        self.simulationOverride = simulationOverride
        self.originalAppVersionSimulation = originalAppVersionSimulation

        if let simulationOverride {
            status = simulationOverride.initialStatus
            print("Aria development access override: \(simulationOverride.rawValue)")
        } else if let rawReason = userDefaults.string(forKey: CacheKeys.verifiedUnlimitedReason),
                  let reason = UnlimitedScoresReason(rawValue: rawReason)
        {
            // Preserve a previously verified entitlement immediately, including
            // while the device is offline and StoreKit is still resolving.
            status = .unlimited(reason)
        } else if userDefaults.bool(forKey: CacheKeys.verifiedFree) {
            // A customer Apple previously classified as new and unpaid remains
            // Free while offline instead of becoming temporarily unrestricted.
            status = .free
        } else {
            // Unknown access remains unrestricted until StoreKit proves that
            // this is a new customer without an unlimited entitlement.
            status = .rolloutDisabled
        }

        if let originalAppVersionSimulation {
            print(
                "Aria development production original app version override: "
                    + originalAppVersionSimulation.originalAppVersion
            )
        }
    }

    var displayPrice: String? {
        product?.displayPrice
    }

    var isUsingDevelopmentOverride: Bool {
        simulationOverride != nil || originalAppVersionSimulation != nil
    }

    func start() async {
        guard !hasStarted else {
            return
        }
        hasStarted = true

        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled else {
                    return
                }
                if case .verified(let transaction) = result,
                   transaction.productID == Self.unlimitedScoresProductID
                {
                    await transaction.finish()
                }
                await self?.refreshEntitlements()
            }
        }

        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        if let simulationOverride, simulationOverride != .free {
            status = simulationOverride.initialStatus
            if product == nil {
                await loadProduct()
            }
            return
        }

        if case .rolloutDisabled = status,
           let rawReason = userDefaults.string(forKey: CacheKeys.verifiedUnlimitedReason),
           let reason = UnlimitedScoresReason(rawValue: rawReason)
        {
            status = .unlimited(reason)
        } else if case .rolloutDisabled = status,
                  userDefaults.bool(forKey: CacheKeys.verifiedFree)
        {
            status = .free
        } else if case .rolloutDisabled = status {
            status = .checking
        }

        var purchaseReason: UnlimitedScoresReason?
        var hasUnverifiedUnlimitedTransaction = false
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                guard transaction.productID == Self.unlimitedScoresProductID,
                      transaction.revocationDate == nil
                else {
                    continue
                }
                purchaseReason = transaction.ownershipType == .familyShared ? .familyShared : .purchased
            case .unverified(let transaction, _):
                if transaction.productID == Self.unlimitedScoresProductID {
                    hasUnverifiedUnlimitedTransaction = true
                }
            }
        }

        var originalAppVersion: String?
        var originalPurchaseDate: Date?
        var appTransactionResolved = false
        var allowsGrandfathering = false
        if let originalAppVersionSimulation {
            originalAppVersion = originalAppVersionSimulation.originalAppVersion
            appTransactionResolved = true
            allowsGrandfathering = true
        } else if simulationOverride == .free {
            originalAppVersion = "2"
            appTransactionResolved = true
        } else {
            do {
                let result = try await AppTransaction.shared
                if case .verified(let appTransaction) = result {
                    originalAppVersion = appTransaction.originalAppVersion
                    originalPurchaseDate = appTransaction.originalPurchaseDate
                    appTransactionResolved = true
                    allowsGrandfathering = LibraryAccessPolicy.allowsGrandfathering(
                        in: appTransaction.environment
                    )
                }
            } catch {
                print("Aria StoreKit app transaction unavailable: \(error.localizedDescription)")
            }
        }

        if hasUnverifiedUnlimitedTransaction, purchaseReason == nil {
            // An unverified IAP may belong to a paying customer whose receipt
            // cannot currently be checked. Do not preserve a cached Free limit
            // in that ambiguous state.
            if !status.hasUnlimitedScores {
                status = .rolloutDisabled
            }
            return
        }

        if purchaseReason != nil || appTransactionResolved {
            applyVerifiedStatus(
                LibraryAccessPolicy.resolveStatus(
                    originalAppVersion: originalAppVersion,
                    originalPurchaseDate: originalPurchaseDate,
                    purchaseReason: purchaseReason,
                    allowsGrandfathering: allowsGrandfathering
                )
            )
        } else if case .checking = status {
            // AppTransaction can be unavailable when the device is offline or
            // signed out. Unknown customers fail open, while a previously
            // verified Free or unlimited classification remains unchanged.
            status = .rolloutDisabled
        }

        // Product metadata is only needed to display or make a purchase. It
        // must not gate entitlement and grandfathering checks when offline.
        if product == nil {
            await loadProduct()
        }
    }

    func purchaseUnlimitedScores() async -> LibraryPurchaseResult {
        isPerformingPurchase = true
        defer { isPerformingPurchase = false }

        if product == nil {
            await loadProduct()
        }

        guard let product else {
            return .failed("Aria Pro is temporarily unavailable. Please try again.")
        }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    return .failed("Aria could not verify this purchase.")
                }
                await transaction.finish()
                await refreshEntitlements()
                return status.hasUnlimitedScores ? .purchased : .failed("The purchase completed, but access could not be verified yet.")
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .failed("The App Store returned an unknown purchase result.")
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func restorePurchases() async -> LibraryPurchaseResult {
        isPerformingPurchase = true
        defer { isPerformingPurchase = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            return status.hasUnlimitedScores
                ? .restored
                : .failed("No Aria Pro purchase was found for this Apple ID.")
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func loadProduct() async {
        isLoadingProduct = true
        defer { isLoadingProduct = false }

        do {
            product = try await Product.products(for: [Self.unlimitedScoresProductID]).first
        } catch {
            product = nil
            print("Aria StoreKit product load failed: \(error.localizedDescription)")
        }
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
}
