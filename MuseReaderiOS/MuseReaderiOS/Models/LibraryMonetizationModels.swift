//
//  LibraryMonetizationModels.swift
//  MuseReaderiOS
//

import Foundation

struct LibraryScoreAllowance: Equatable, Sendable {
    let status: LibraryAccessStatus
    let usedScoreCount: Int
    let reservedScoreCount: Int
    let freeLimit: Int

    var remainingSlots: Int {
        guard !status.hasUnlimitedScores else {
            return Int.max
        }
        return max(0, freeLimit - usedScoreCount - reservedScoreCount)
    }

    func canReserve(_ count: Int) -> Bool {
        count <= 0 || status.hasUnlimitedScores || remainingSlots >= count
    }
}

enum LibraryPaywallContext: Equatable, Sendable {
    case createScore
    case importScore(count: Int)
    case settings

    var title: String {
        switch self {
        case .createScore, .importScore:
            return "You’ve Reached Your Free Library Limit"
        case .settings:
            return "Aria Pro"
        }
    }
}

enum ScoreImportDisposition: Equatable, Sendable {
    case new
    case replace(relativePath: String, existingFileReference: String?)

    var usesNewSlot: Bool {
        if case .new = self {
            return true
        }
        return false
    }

    var isReplacement: Bool {
        !usesNewSlot
    }
}

struct ScoreImportCandidate: Identifiable, Equatable, Sendable {
    let id: UUID
    let url: URL
    let destinationFileName: String
    let disposition: ScoreImportDisposition

    init(
        id: UUID = UUID(),
        url: URL,
        destinationFileName: String,
        disposition: ScoreImportDisposition
    ) {
        self.id = id
        self.url = url
        self.destinationFileName = destinationFileName
        self.disposition = disposition
    }

    var destinationKey: String {
        destinationFileName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

struct ScoreImportReview: Identifiable, Equatable, Sendable {
    let id = UUID()
    let candidates: [ScoreImportCandidate]
    let availableNewSlots: Int
    let hasUnlimitedScores: Bool

    var newCandidateCount: Int {
        candidates.filter(\.disposition.usesNewSlot).count
    }

    var replacementCount: Int {
        candidates.filter(\.disposition.isReplacement).count
    }

    var hasDuplicateDestinations: Bool {
        Dictionary(grouping: candidates, by: \.destinationKey).values.contains { $0.count > 1 }
    }

    var exceedsFreeCapacity: Bool {
        !hasUnlimitedScores && uniqueNewDestinationCount > availableNewSlots
    }

    private var uniqueNewDestinationCount: Int {
        Set(candidates.filter(\.disposition.usesNewSlot).map(\.destinationKey)).count
    }
}

enum LibraryAccessSheet: Identifiable, Equatable, Sendable {
    case paywall(LibraryPaywallContext)
    case importReview(ScoreImportReview)
    case earlySupporter

    var id: String {
        switch self {
        case .paywall:
            return "paywall"
        case .importReview(let review):
            return "import-review-\(review.id.uuidString)"
        case .earlySupporter:
            return "early-supporter"
        }
    }
}
