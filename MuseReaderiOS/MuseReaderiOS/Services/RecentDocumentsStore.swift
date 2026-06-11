//
//  RecentDocumentsStore.swift
//  MuseReaderiOS
//
//  Created by Codex on 4/13/26.
//

import Foundation

@MainActor
final class RecentDocumentsStore {
    private enum Constants {
        static let legacyStorageKey = "MuseReaderiOS.recentDocuments"
    }

    private let fileManager: FileManager
    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default, userDefaults: UserDefaults = .standard) {
        self.fileManager = fileManager
        self.userDefaults = userDefaults
    }

    func load() -> [ReaderRecentDocument] {
        if let documents = loadFromDisk() {
            return documents.sorted { $0.lastOpened > $1.lastOpened }
        }

        guard
            let data = userDefaults.data(forKey: Constants.legacyStorageKey),
            let documents = try? decoder.decode([ReaderRecentDocument].self, from: data)
        else {
            return []
        }

        let sortedDocuments = documents.sorted { $0.lastOpened > $1.lastOpened }
        save(sortedDocuments)
        userDefaults.removeObject(forKey: Constants.legacyStorageKey)
        return sortedDocuments
    }

    func save(_ documents: [ReaderRecentDocument]) {
        guard
            let data = try? encoder.encode(documents),
            let storageURL = try? ManagedScoreLibraryPaths.indexURL(fileManager: fileManager)
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

    func record(document: ScoreDocument,
                bookmarkData: Data? = nil,
                libraryRelativePath: String? = nil,
                previewImageData: Data? = nil,
                replacingFileReference: String? = nil,
                in existingDocuments: [ReaderRecentDocument]) -> [ReaderRecentDocument]
    {
        let existingDocument = existingDocuments.first(where: {
            $0.fileReference == document.fileReference
                || (libraryRelativePath != nil && $0.libraryRelativePath == libraryRelativePath)
        })
        let existingImportedAt = existingDocument?.importedAt ?? .now
        let resolvedPreviewImageData = previewImageData
            ?? existingDocument?.previewImageData
            ?? document.previewImageData

        let recent = ReaderRecentDocument(
            document: document,
            bookmarkData: bookmarkData,
            libraryRelativePath: libraryRelativePath,
            previewImageData: resolvedPreviewImageData,
            importedAt: existingImportedAt
        )
        var updated = existingDocuments.filter { existing in
            let matchesLibraryPath = libraryRelativePath != nil && existing.libraryRelativePath == libraryRelativePath
            return existing.fileReference != recent.fileReference
                && existing.fileReference != replacingFileReference
                && !matchesLibraryPath
        }
        updated.insert(recent, at: 0)

        save(updated)
        return updated
    }

    private func loadFromDisk() -> [ReaderRecentDocument]? {
        guard
            let storageURL = try? ManagedScoreLibraryPaths.indexURL(fileManager: fileManager),
            fileManager.fileExists(atPath: storageURL.path),
            let data = try? Data(contentsOf: storageURL),
            let documents = try? decoder.decode([ReaderRecentDocument].self, from: data)
        else {
            return nil
        }

        return documents
    }
}
