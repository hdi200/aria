import Foundation

enum ScoreLegacyRepairBackup {
    nonisolated static func createUntouchedCopy(of sourceURL: URL, fileManager: FileManager = .default) throws -> URL {
        guard sourceURL.isFileURL,
              fileManager.fileExists(atPath: sourceURL.path),
              let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        else {
            throw ScoreDocumentServiceError.bridgeFailure("The original score file could not be found for backup.")
        }

        let backupsRoot = documentsURL.appendingPathComponent("Aria Backups", isDirectory: true)
        let backupFolder = backupsRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: backupFolder, withIntermediateDirectories: true)

        // Managed loose MSCX scores keep images and other package entries beside
        // their score file. Preserve that whole container, not just the XML.
        let scoresRoot = try ManagedScoreLibraryPaths.itemsRootURL(fileManager: fileManager)
        let containerURL = sourceURL.deletingLastPathComponent()
        let isManagedMSCXContainer = sourceURL.pathExtension.lowercased() == "mscx"
            && containerURL.deletingLastPathComponent().standardizedFileURL == scoresRoot.standardizedFileURL

        let destinationURL: URL
        if isManagedMSCXContainer {
            let copiedContainer = backupFolder.appendingPathComponent(containerURL.lastPathComponent, isDirectory: true)
            try fileManager.copyItem(at: containerURL, to: copiedContainer)
            destinationURL = copiedContainer.appendingPathComponent(sourceURL.lastPathComponent)
        } else {
            destinationURL = backupFolder.appendingPathComponent(sourceURL.lastPathComponent)
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }

        let copiedSize = (try fileManager.attributesOfItem(atPath: destinationURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard fileManager.fileExists(atPath: destinationURL.path), copiedSize > 0
        else {
            throw ScoreDocumentServiceError.bridgeFailure("Aria could not verify the untouched backup copy.")
        }
        return destinationURL
    }
}
