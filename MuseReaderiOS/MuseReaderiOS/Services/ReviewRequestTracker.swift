//
//  ReviewRequestTracker.swift
//  MuseReaderiOS
//
//

import Foundation

@MainActor
final class ReviewRequestTracker {
    private enum Constants {
        static let openCountKey = "Aria.reviewRequest.openCount"
        static let didRequestReviewKey = "Aria.reviewRequest.didRequestReview"
        static let reviewOpenThreshold = 3
    }

    private let userDefaults: UserDefaults
    private var didRecordOpenThisProcess = false

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func shouldRequestReviewAfterAppOpen() -> Bool {
        guard !didRecordOpenThisProcess else {
            return false
        }

        didRecordOpenThisProcess = true

        guard !userDefaults.bool(forKey: Constants.didRequestReviewKey) else {
            return false
        }

        let openCount = userDefaults.integer(forKey: Constants.openCountKey) + 1
        userDefaults.set(openCount, forKey: Constants.openCountKey)

        guard openCount >= Constants.reviewOpenThreshold else {
            return false
        }

        userDefaults.set(true, forKey: Constants.didRequestReviewKey)
        return true
    }
}
