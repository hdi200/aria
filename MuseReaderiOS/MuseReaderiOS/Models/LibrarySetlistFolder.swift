//
//  LibrarySetlistFolder.swift
//  MuseReaderiOS
//
//

import Foundation

struct LibrarySetlistFolder: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var scoreKeys: [String]

    init(id: UUID = UUID(), name: String, scoreKeys: [String] = []) {
        self.id = id
        self.name = name
        self.scoreKeys = scoreKeys
    }
}

extension LibrarySetlistFolder {
    @discardableResult
    mutating func appendScoreKeyIfNeeded(_ scoreKey: String) -> Bool {
        guard !scoreKeys.contains(scoreKey) else {
            return false
        }
        scoreKeys.append(scoreKey)
        return true
    }

    /// Resolves the persisted keys without letting the recent-items order change
    /// the performance order of a setlist. Legacy aliases are intentionally
    /// accepted so existing setlists survive document normalization/replacement.
    func orderedScores(from libraryScores: [ReaderRecentDocument]) -> [ReaderRecentDocument] {
        var scoresByKey: [String: ReaderRecentDocument] = [:]
        for score in libraryScores {
            scoresByKey[score.setlistKey] = score
            scoresByKey[score.fileReference] = score
            if let libraryRelativePath = score.libraryRelativePath {
                scoresByKey[libraryRelativePath] = score
            }
        }

        var includedScoreIDs: Set<ReaderRecentDocument.ID> = []
        return scoreKeys.compactMap { key in
            guard let score = scoresByKey[key], includedScoreIDs.insert(score.id).inserted else {
                return nil
            }
            return score
        }
    }

    @discardableResult
    mutating func reorderScores(
        using orderedScoreIDs: [ReaderRecentDocument.ID],
        from libraryScores: [ReaderRecentDocument]
    ) -> Bool {
        let currentScores = orderedScores(from: libraryScores)
        guard orderedScoreIDs.count == currentScores.count,
              Set(orderedScoreIDs) == Set(currentScores.map(\.id))
        else {
            return false
        }

        let scoresByID = Dictionary(uniqueKeysWithValues: currentScores.map { ($0.id, $0) })
        scoreKeys = orderedScoreIDs.compactMap { scoresByID[$0]?.setlistKey }
        return true
    }
}
