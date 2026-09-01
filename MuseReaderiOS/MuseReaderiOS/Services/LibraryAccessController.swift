//
//  LibraryAccessController.swift
//  MuseReaderiOS
//

import Combine
import Foundation
import StoreKit

enum UnlimitedScoresReason: String, Codable, Equatable, Sendable {
    case earlySupporter
    case purchased
    case familyShared

    var settingsTitle: String {
        switch self {
        case .earlySupporter:
            return "Early Supporter"
        case .purchased:
            return "Purchased"
        case .familyShared:
            return "Family Access"
        }
    }
}

enum LibraryAccessStatus: Equatable, Sendable {
    case rolloutDisabled
    case checking
    case free
    case unlimited(UnlimitedScoresReason)

    var hasUnlimitedScores: Bool {
        if case .rolloutDisabled = self {
            return true
        }
        if case .unlimited = self {
            return true
        }
        return false
    }

    var showsMonetizationUI: Bool {
        self != .rolloutDisabled
    }

    var unlimitedReason: UnlimitedScoresReason? {
        guard case .unlimited(let reason) = self else {
            return nil
        }
        return reason
    }
}

enum LibraryPurchaseResult: Equatable, Sendable {
    case purchased
    case restored
    case pending
    case cancelled
    case failed(String)

    var unlocked: Bool {
        self == .purchased || self == .restored
    }
}

enum LibraryAccessSimulationOverride: String, Equatable, Sendable {
    case free
    case earlySupporter
    case purchased
    case familyShared

    static func fromLaunchArguments(_ arguments: [String]) -> Self? {
        if let combined = arguments.first(where: { $0.hasPrefix("-AriaAccessOverride=") }),
           let value = combined.split(separator: "=", maxSplits: 1).last
        {
            return Self(rawValue: String(value))
        }

        guard let argumentIndex = arguments.firstIndex(of: "-AriaAccessOverride"),
              arguments.indices.contains(argumentIndex + 1)
        else {
            return nil
        }
        return Self(rawValue: arguments[argumentIndex + 1])
    }

    var initialStatus: LibraryAccessStatus {
        switch self {
        case .free:
            return .free
        case .earlySupporter:
            return .unlimited(.earlySupporter)
        case .purchased:
            return .unlimited(.purchased)
        case .familyShared:
            return .unlimited(.familyShared)
        }
    }
}

struct LibraryOriginalAppVersionSimulation: Equatable, Sendable {
    let originalAppVersion: String

    static func fromLaunchArguments(_ arguments: [String]) -> Self? {
        let rawValue: String?
        if let combined = arguments.first(where: { $0.hasPrefix("-AriaOriginalAppVersionOverride=") }),
           let value = combined.split(separator: "=", maxSplits: 1).last
        {
            rawValue = String(value)
        } else if let argumentIndex = arguments.firstIndex(of: "-AriaOriginalAppVersionOverride"),
                  arguments.indices.contains(argumentIndex + 1)
        {
            rawValue = arguments[argumentIndex + 1]
        } else {
            rawValue = nil
        }

        guard let rawValue, !rawValue.isEmpty else {
            return nil
        }
        return Self(originalAppVersion: rawValue)
    }
}

struct LibraryAccessPolicy {
    static let freeScoreLimit = 2
    static let grandfatheredThroughBuild = "1"
    // Aria Pro version 4.1 went live on August 29, 2026 at 19:02:37 UTC.
    // The App Store-signed original purchase date is a second, stable way to
    // recognize existing users when Apple's historical build number is not
    // what we expect.
    static let grandfatheredBeforePurchaseDate = Date(timeIntervalSince1970: 1_788_030_157)

    static func resolveStatus(
        originalAppVersion: String?,
        originalPurchaseDate: Date? = nil,
        purchaseReason: UnlimitedScoresReason?,
        allowsGrandfathering: Bool = true
    ) -> LibraryAccessStatus {
        let hasGrandfatheredVersion = originalAppVersion.map {
            isVersion($0, atOrBefore: grandfatheredThroughBuild)
        } ?? false
        let hasGrandfatheredPurchaseDate = originalPurchaseDate.map {
            $0 < grandfatheredBeforePurchaseDate
        } ?? false

        if allowsGrandfathering,
           hasGrandfatheredVersion || hasGrandfatheredPurchaseDate {
            return .unlimited(.earlySupporter)
        }

        if let purchaseReason {
            return .unlimited(purchaseReason)
        }

        return .free
    }

    static func allowsGrandfathering(in environment: AppStore.Environment) -> Bool {
        // StoreKit reports a synthetic originalAppVersion of 1.0 in Xcode and
        // sandbox/TestFlight. Only production carries the customer's real
        // acquisition build, so only production can safely grandfather users.
        environment == .production
    }

    static func isVersion(_ version: String, atOrBefore cutoff: String) -> Bool {
        compareVersion(version, cutoff) != .orderedDescending
    }

    static func compareVersion(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = numericComponents(of: lhs)
        let right = numericComponents(of: rhs)
        let componentCount = max(left.count, right.count)

        for index in 0..<componentCount {
            let leftValue = index < left.count ? left[index] : 0
            let rightValue = index < right.count ? right[index] : 0
            if leftValue < rightValue {
                return .orderedAscending
            }
            if leftValue > rightValue {
                return .orderedDescending
            }
        }

        return .orderedSame
    }

    private static func numericComponents(of version: String) -> [Int] {
        let components = version.split { !$0.isNumber }
            .compactMap { Int($0) }
        return components.isEmpty ? [Int.max] : components
    }
}

@MainActor
final class LibraryAccessController: ObservableObject {
    static let unlimitedScoresProductID = "com.hdi200.ariascore.unlimitedscores"

    private enum CacheKeys {
        static let verifiedUnlimitedReason = "Aria.LibraryAccess.VerifiedUnlimitedReason"
        static let verifiedFree = "Aria.LibraryAccess.VerifiedFree"
    }

    @Published private(set) var status: LibraryAccessStatus
    @Published private(set) var product: Product?
    @Published private(set) var isLoadingProduct = false
    @Published private(set) var isPerformingPurchase = false

    private let userDefaults: UserDefaults
    private let simulationOverride: LibraryAccessSimulationOverride?
    private let originalAppVersionSimulation: LibraryOriginalAppVersionSimulation?
    private var updatesTask: Task<Void, Never>?
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
