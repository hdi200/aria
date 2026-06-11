//
//  LibrarySetlistFolder.swift
//  MuseReaderiOS
//
//  Created by Codex on 5/25/26.
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

