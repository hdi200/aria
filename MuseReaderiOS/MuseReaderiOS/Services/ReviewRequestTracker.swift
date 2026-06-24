//
//  ReviewRequestTracker.swift
//  MuseReaderiOS
//
//

import Foundation

@MainActor
final class ReviewRequestTracker {
    private enum Constants {
        static let sessionCountKey = "Aria.reviewRequest.sessionCount"
        static let lastRecordedSessionIDKey = "Aria.reviewRequest.lastRecordedSessionID"
        static let firstInstalledVersionKey = "Aria.reviewRequest.firstInstalledVersion"
        static let lastSeenVersionKey = "Aria.reviewRequest.lastSeenVersion"
        static let versionFirstSeenDateKey = "Aria.reviewRequest.versionFirstSeenDate"
        static let requestedVersionsKey = "Aria.reviewRequest.requestedVersions"
        static let lastAttemptDateKey = "Aria.reviewRequest.lastAttemptDate"
        static let lastFrictionDateKey = "Aria.reviewRequest.lastFrictionDate"

        static let minimumSessionsBeforeFirstRequest = 3
        static let updateGraceInterval: TimeInterval = 3 * 24 * 60 * 60
        static let attemptCooldownInterval: TimeInterval = 60 * 24 * 60 * 60
        static let frictionCooldownInterval: TimeInterval = 24 * 60 * 60
        static let longLivedVersionInterval: TimeInterval = 180 * 24 * 60 * 60
    }

    private let userDefaults: UserDefaults
    private let appVersion: String
    private let processSessionID: String

    init(userDefaults: UserDefaults = .standard, appVersion: String = ReviewRequestTracker.currentAppVersion()) {
        self.userDefaults = userDefaults
        self.appVersion = appVersion
        self.processSessionID = "\(appVersion)-\(ProcessInfo.processInfo.globallyUniqueString)"
        prepareVersionStateIfNeeded(now: Date())
    }

    func recordActiveSession() {
        let sessionID = currentSessionID()
        guard userDefaults.string(forKey: Constants.lastRecordedSessionIDKey) != sessionID else {
            return
        }

        userDefaults.set(sessionID, forKey: Constants.lastRecordedSessionIDKey)
        userDefaults.set(userDefaults.integer(forKey: Constants.sessionCountKey) + 1, forKey: Constants.sessionCountKey)
        prepareVersionStateIfNeeded(now: Date())
    }

    func recordFrictionEvent() {
        userDefaults.set(Date(), forKey: Constants.lastFrictionDateKey)
    }

    func shouldRequestReviewAfterSuccessfulScoreOpen() -> Bool {
        let now = Date()
        prepareVersionStateIfNeeded(now: now)

        guard userDefaults.integer(forKey: Constants.sessionCountKey) >= Constants.minimumSessionsBeforeFirstRequest else {
            return false
        }

        if !isFirstInstalledVersion,
           !hasMetUpdateGraceInterval(now: now) {
            return false
        }

        if let lastAttemptDate = date(forKey: Constants.lastAttemptDateKey),
           now.timeIntervalSince(lastAttemptDate) < Constants.attemptCooldownInterval {
            return false
        }

        if let lastFrictionDate = date(forKey: Constants.lastFrictionDateKey),
           now.timeIntervalSince(lastFrictionDate) < Constants.frictionCooldownInterval {
            return false
        }

        if requestedVersions().contains(appVersion), !isLongLivedCurrentVersion(now: now) {
            return false
        }

        recordReviewAttempt(now: now)
        return true
    }

    private func prepareVersionStateIfNeeded(now: Date) {
        if userDefaults.string(forKey: Constants.firstInstalledVersionKey) == nil {
            userDefaults.set(appVersion, forKey: Constants.firstInstalledVersionKey)
        }

        guard userDefaults.string(forKey: Constants.lastSeenVersionKey) != appVersion else {
            if date(forKey: Constants.versionFirstSeenDateKey) == nil {
                userDefaults.set(now, forKey: Constants.versionFirstSeenDateKey)
            }
            return
        }

        userDefaults.set(appVersion, forKey: Constants.lastSeenVersionKey)
        userDefaults.set(now, forKey: Constants.versionFirstSeenDateKey)
    }

    private func recordReviewAttempt(now: Date) {
        userDefaults.set(now, forKey: Constants.lastAttemptDateKey)

        var versions = requestedVersions()
        if !versions.contains(appVersion) {
            versions.append(appVersion)
        }
        userDefaults.set(versions, forKey: Constants.requestedVersionsKey)
    }

    private func requestedVersions() -> [String] {
        userDefaults.stringArray(forKey: Constants.requestedVersionsKey) ?? []
    }

    private func isLongLivedCurrentVersion(now: Date) -> Bool {
        guard let firstSeenDate = date(forKey: Constants.versionFirstSeenDateKey) else {
            return false
        }

        return now.timeIntervalSince(firstSeenDate) >= Constants.longLivedVersionInterval
    }

    private var isFirstInstalledVersion: Bool {
        userDefaults.string(forKey: Constants.firstInstalledVersionKey) == appVersion
    }

    private func hasMetUpdateGraceInterval(now: Date) -> Bool {
        date(forKey: Constants.versionFirstSeenDateKey).map { now.timeIntervalSince($0) >= Constants.updateGraceInterval } ?? false
    }

    private func date(forKey key: String) -> Date? {
        userDefaults.object(forKey: key) as? Date
    }

    private func currentSessionID() -> String {
        processSessionID
    }

    private nonisolated static func currentAppVersion() -> String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return [shortVersion, buildVersion]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .nilIfEmpty ?? "unknown"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
