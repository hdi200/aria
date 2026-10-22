// Android stand-in for the StoreKit the shared views use: the review request, shown with
// Google Play's in-app review (AriaReview.kt). Purchases are in
// AndroidLibraryAccessController.swift (Play Billing).
@_exported import SwiftUI
import SkipFuse

public struct RequestReviewAction: Sendable {
    public init() {}

    @MainActor
    public func callAsFunction() {
        do {
            let review = try AnyDynamicObject(className: "aria.skip.AriaReview")
            try review.request() as Void
        } catch {
            print("Aria review request failed: \(error)")
        }
    }
}

extension EnvironmentValues {
    public var requestReview: RequestReviewAction {
        RequestReviewAction()
    }
}

// MARK: - App transaction

public enum VerificationResult<SignedType: Sendable>: Sendable {
    case verified(SignedType)
    case unverified(SignedType, Error)
}

/// The app's install record. Play has no signed purchase record for a free app, so this is
/// the first install time on this device.
public struct AppTransaction: Sendable {
    public let originalPurchaseDate: Date

    public static var shared: VerificationResult<AppTransaction> {
        get async throws {
            let device = try AnyDynamicObject(className: "aria.skip.AriaDevice")
            let millis: Int64 = try device.firstInstallTime() ?? 0
            return .verified(AppTransaction(originalPurchaseDate: Date(timeIntervalSince1970: Double(millis) / 1000)))
        }
    }
}
