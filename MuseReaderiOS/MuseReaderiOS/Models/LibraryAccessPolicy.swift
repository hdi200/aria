//
//  LibraryAccessPolicy.swift
//  MuseReaderiOS
//
//  Access states and the free-score policy, shared by the App Store
//  (LibraryAccessController) and Android store implementations.
//

import Foundation

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
