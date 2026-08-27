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
    case checking
    case free
    case unlimited(UnlimitedScoresReason)

    var hasUnlimitedScores: Bool {
        if case .unlimited = self {
            return true
        }
        return false
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

struct LibraryAccessPolicy {
    static let freeScoreLimit = 2
    static let grandfatheredThroughBuild = "1"

    static func resolveStatus(
        originalAppVersion: String?,
        purchaseReason: UnlimitedScoresReason?
    ) -> LibraryAccessStatus {
        if let originalAppVersion,
           isVersion(originalAppVersion, atOrBefore: grandfatheredThroughBuild)
        {
            return .unlimited(.earlySupporter)
        }

        if let purchaseReason {
            return .unlimited(purchaseReason)
        }

        return .free
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
    }

    @Published private(set) var status: LibraryAccessStatus
    @Published private(set) var product: Product?
    @Published private(set) var isLoadingProduct = false
    @Published private(set) var isPerformingPurchase = false

    private let userDefaults: UserDefaults
    private let simulationOverride: LibraryAccessSimulationOverride?
    private var updatesTask: Task<Void, Never>?
    private var hasStarted = false

    init(
        userDefaults: UserDefaults = .standard,
        simulationOverride explicitSimulationOverride: LibraryAccessSimulationOverride? = nil
    ) {
        self.userDefaults = userDefaults
        // Xcode Run uses Debug, so these launch arguments can exercise access
        // states on development devices. Archive/App Store builds omit this path.
        #if DEBUG
        let simulationOverride = explicitSimulationOverride
            ?? LibraryAccessSimulationOverride.fromLaunchArguments(ProcessInfo.processInfo.arguments)
        #else
        let simulationOverride: LibraryAccessSimulationOverride? = nil
        #endif
        self.simulationOverride = simulationOverride

        if let simulationOverride {
            status = simulationOverride.initialStatus
            print("Aria development access override: \(simulationOverride.rawValue)")
        } else if let rawReason = userDefaults.string(forKey: CacheKeys.verifiedUnlimitedReason),
           let reason = UnlimitedScoresReason(rawValue: rawReason)
        {
            status = .unlimited(reason)
        } else {
            status = .checking
        }
    }

    var displayPrice: String? {
        product?.displayPrice
    }

    var isUsingDevelopmentOverride: Bool {
        simulationOverride != nil
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

        async let productLoad: Void = loadProduct()
        async let entitlementRefresh: Void = refreshEntitlements()
        _ = await (productLoad, entitlementRefresh)
    }

    func refreshEntitlements() async {
        if let simulationOverride, simulationOverride != .free {
            status = simulationOverride.initialStatus
            return
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
        var appTransactionResolved = false
        if simulationOverride == .free {
            originalAppVersion = "2"
            appTransactionResolved = true
        } else {
            do {
                let result = try await AppTransaction.shared
                if case .verified(let appTransaction) = result {
                    originalAppVersion = appTransaction.originalAppVersion
                    appTransactionResolved = true
                }
            } catch {
                print("Aria StoreKit app transaction unavailable: \(error.localizedDescription)")
            }
        }

        if hasUnverifiedUnlimitedTransaction, status.hasUnlimitedScores, purchaseReason == nil {
            return
        }

        if purchaseReason != nil || appTransactionResolved {
            applyVerifiedStatus(
                LibraryAccessPolicy.resolveStatus(
                    originalAppVersion: originalAppVersion,
                    purchaseReason: purchaseReason
                )
            )
        } else if !status.hasUnlimitedScores {
            status = .free
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
        } else {
            userDefaults.removeObject(forKey: CacheKeys.verifiedUnlimitedReason)
        }
    }
}
