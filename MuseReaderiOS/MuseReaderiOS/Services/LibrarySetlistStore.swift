//
//  LibrarySetlistStore.swift
//  MuseReaderiOS
//
//  Created by Codex on 5/25/26.
//

import Foundation

@MainActor
final class LibrarySetlistStore {
    private enum Constants {
        static let fileName = "setlists.json"
    }

    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func load() -> [LibrarySetlistFolder] {
        guard
            let storageURL = try? storageURL(),
            fileManager.fileExists(atPath: storageURL.path),
            let data = try? Data(contentsOf: storageURL),
            let folders = try? decoder.decode([LibrarySetlistFolder].self, from: data)
        else {
            return []
        }

        return folders
    }

    func save(_ folders: [LibrarySetlistFolder]) {
        guard
            let data = try? encoder.encode(folders),
            let storageURL = try? storageURL()
        else {
            return
        }

        do {
            try fileManager.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            try data.write(to: storageURL, options: .atomic)
        } catch {
            return
        }
    }

    private func storageURL() throws -> URL {
        try ManagedScoreLibraryPaths.privateRootURL(fileManager: fileManager)
            .appendingPathComponent(Constants.fileName, isDirectory: false)
    }
}

