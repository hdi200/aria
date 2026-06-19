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

