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
        let backupFolder = uniqueBackupFolder(
            in: backupsRoot,
            scoreName: sourceURL.deletingPathExtension().lastPathComponent,
            fileManager: fileManager
        )
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

    /// A folder people can recognize in the Files app, e.g. "Hikari – 2026-09-23 14.05.09".
    nonisolated private static func uniqueBackupFolder(in root: URL, scoreName: String, fileManager: FileManager) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let name = scoreName.isEmpty ? "Score" : scoreName
        let base = "\(name) – \(formatter.string(from: Date()))"

        var candidate = root.appendingPathComponent(base, isDirectory: true)
        var counter = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = root.appendingPathComponent("\(base) (\(counter))", isDirectory: true)
            counter += 1
        }
        return candidate
    }
}
