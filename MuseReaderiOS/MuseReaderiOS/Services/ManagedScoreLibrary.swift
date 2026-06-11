//
//  ManagedScoreLibrary.swift
//  MuseReaderiOS
//
//  Created on 4/14/26.
//

import Foundation

struct ManagedLibraryDocument: Sendable {
    let canonicalURL: URL
    let relativeMainFilePath: String
}

enum ManagedScoreLibraryError: LocalizedError {
    case invalidLocation
    case unsupportedFormat(String)
    case missingDocument
    case couldNotCreateStorage
    case missingTemplate(String)

    var errorDescription: String? {
        switch self {
        case .invalidLocation:
            return "Aria could not access that file location."
        case .unsupportedFormat(let pathExtension):
            return "Aria cannot import .\(pathExtension) into its score library yet."
        case .missingDocument:
            return "Aria could not find that score in its score library."
        case .couldNotCreateStorage:
            return "Aria could not create its internal score library."
        case .missingTemplate(let name):
            return "Aria could not find the \(name) score template."
        }
    }
}

enum ManagedScoreLibraryPaths {
    static let privateRootDirectoryName = "MuseReaderLibrary"
    static let previousNestedVisibleRootDirectoryName = "Aria"
    static let itemsDirectoryName = "Scores"
    static let indexFileName = "library-index.json"

    static func privateRootURL(fileManager: FileManager = .default) throws -> URL {
        guard let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw ManagedScoreLibraryError.couldNotCreateStorage
        }

        return applicationSupportURL.appendingPathComponent(privateRootDirectoryName, isDirectory: true)
    }

    static func visibleRootURL(fileManager: FileManager = .default) throws -> URL {
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw ManagedScoreLibraryError.couldNotCreateStorage
        }

        return documentsURL
    }

    static func itemsRootURL(fileManager: FileManager = .default) throws -> URL {
        try visibleRootURL(fileManager: fileManager).appendingPathComponent(itemsDirectoryName, isDirectory: true)
    }

    static func indexURL(fileManager: FileManager = .default) throws -> URL {
        try privateRootURL(fileManager: fileManager).appendingPathComponent(indexFileName, isDirectory: false)
    }

    static func legacyItemsRootURL(fileManager: FileManager = .default) throws -> URL {
        try privateRootURL(fileManager: fileManager).appendingPathComponent(itemsDirectoryName, isDirectory: true)
    }

    static func previousNestedVisibleItemsRootURL(fileManager: FileManager = .default) throws -> URL {
        try visibleRootURL(fileManager: fileManager)
            .appendingPathComponent(previousNestedVisibleRootDirectoryName, isDirectory: true)
            .appendingPathComponent(itemsDirectoryName, isDirectory: true)
    }
}

struct ManagedScoreLibrary {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func prepareStorageIfNeeded() throws {
        let privateRootURL = try ManagedScoreLibraryPaths.privateRootURL(fileManager: fileManager)
        let itemsRootURL = try ManagedScoreLibraryPaths.itemsRootURL(fileManager: fileManager)

        print("Aria library prepare storage: private=\(privateRootURL.path) scores=\(itemsRootURL.path)")
        try fileManager.createDirectory(at: privateRootURL, withIntermediateDirectories: true, attributes: nil)
        try fileManager.createDirectory(at: itemsRootURL, withIntermediateDirectories: true, attributes: nil)
    }

    func importDocument(from sourceURL: URL) throws -> ManagedLibraryDocument {
        guard sourceURL.isFileURL else {
            throw ManagedScoreLibraryError.invalidLocation
        }

        print("Aria library import begin: source=\(sourceURL.path) ext=\(sourceURL.pathExtension)")
        try prepareStorageIfNeeded()

        let fileExtension = sourceURL.pathExtension.lowercased()
        let scoresRootURL = try ManagedScoreLibraryPaths.itemsRootURL(fileManager: fileManager)
        print("Aria library import scores root: \(scoresRootURL.path)")

        let canonicalURL: URL
        switch fileExtension {
        case ScoreFileFormat.mscz.rawValue, ScoreFileFormat.mxl.rawValue, ScoreFileFormat.musicxml.rawValue, "xml":
            let destinationURL = uniqueDestinationURL(
                for: sourceURL.lastPathComponent,
                in: scoresRootURL,
                isDirectory: false
            )
            print("Aria library import copy file: source=\(sourceURL.path) destination=\(destinationURL.path)")
            try coordinatedRead(from: sourceURL) { coordinatedURL in
                print("Aria library import coordinated file URL: \(coordinatedURL.path)")
                try fileManager.copyItem(at: coordinatedURL, to: destinationURL)
            }
            canonicalURL = destinationURL
        case ScoreFileFormat.mscx.rawValue:
            let containerURL = sourceURL.deletingLastPathComponent()
            let destinationFolderName = containerURL.lastPathComponent.trimmedToNil ?? sourceURL.deletingPathExtension().lastPathComponent
            let itemRootURL = uniqueDestinationURL(
                for: destinationFolderName,
                in: scoresRootURL,
                isDirectory: true
            )
            print("Aria library import copy mscx container: sourceFile=\(sourceURL.path) container=\(containerURL.path) destinationFolder=\(itemRootURL.path)")
            do {
                try coordinatedRead(from: containerURL) { coordinatedURL in
                    print("Aria library import coordinated mscx container URL: \(coordinatedURL.path)")
                    try fileManager.copyItem(at: coordinatedURL, to: itemRootURL)
                }
            } catch {
                print("Aria library import mscx container copy failed, falling back to selected file only: error=\(error)")
                try fileManager.createDirectory(at: itemRootURL, withIntermediateDirectories: true, attributes: nil)
                let destinationURL = itemRootURL.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: false)
                try coordinatedRead(from: sourceURL) { coordinatedURL in
                    print("Aria library import coordinated mscx file URL: \(coordinatedURL.path) destination=\(destinationURL.path)")
                    try fileManager.copyItem(at: coordinatedURL, to: destinationURL)
                }
            }
            canonicalURL = itemRootURL.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: false)
        default:
            throw ManagedScoreLibraryError.unsupportedFormat(fileExtension.isEmpty ? "unknown" : fileExtension)
        }

        print("Aria library import canonical candidate: \(canonicalURL.path)")
        guard fileManager.fileExists(atPath: canonicalURL.path) else {
            print("Aria library import missing canonical file: \(canonicalURL.path)")
            throw ManagedScoreLibraryError.missingDocument
        }

        let relativePath = try relativePath(for: canonicalURL).requiredLibraryPath()
        print("Aria library import complete: canonical=\(canonicalURL.path) relative=\(relativePath)")
        return ManagedLibraryDocument(
            canonicalURL: canonicalURL,
            relativeMainFilePath: relativePath
        )
    }

    func createDocument(fromTemplate template: NewScoreTemplateChoice) throws -> ManagedLibraryDocument {
        try prepareStorageIfNeeded()

        guard let templateRootURL = template.bundleDirectoryURL else {
            throw ManagedScoreLibraryError.missingTemplate(template.title)
        }

        let scoresRootURL = try ManagedScoreLibraryPaths.itemsRootURL(fileManager: fileManager)
        let itemRootURL = uniqueDestinationURL(
            for: template.title,
            in: scoresRootURL,
            isDirectory: true
        )
        try fileManager.copyItem(at: templateRootURL, to: itemRootURL)

        let canonicalURL = itemRootURL.appendingPathComponent(template.templateFileName, isDirectory: false)
        guard fileManager.fileExists(atPath: canonicalURL.path) else {
            throw ManagedScoreLibraryError.missingTemplate(template.title)
        }

        return ManagedLibraryDocument(
            canonicalURL: canonicalURL,
            relativeMainFilePath: try relativePath(for: canonicalURL).requiredLibraryPath()
        )
    }

    func packagedDocumentDestination(preferredName: String) throws -> ManagedLibraryDocument {
        try prepareStorageIfNeeded()

        let scoresRootURL = try ManagedScoreLibraryPaths.itemsRootURL(fileManager: fileManager)
        let preferredFileName = preferredName.trimmedToNil.map { "\($0).\(ScoreFileFormat.mscz.rawValue)" }
            ?? "Score.\(ScoreFileFormat.mscz.rawValue)"
        let canonicalURL = uniqueDestinationURL(
            for: preferredFileName,
            in: scoresRootURL,
            isDirectory: false
        )

        return ManagedLibraryDocument(
            canonicalURL: canonicalURL,
            relativeMainFilePath: try relativePath(for: canonicalURL).requiredLibraryPath()
        )
    }

    func url(forRelativePath storedRelativePath: String) throws -> URL {
        try prepareStorageIfNeeded()

        let rootURL = try ManagedScoreLibraryPaths.visibleRootURL(fileManager: fileManager)
        let resolvedURL = URL(fileURLWithPath: storedRelativePath, relativeTo: rootURL).standardizedFileURL

        guard try relativePath(for: resolvedURL) != nil else {
            throw ManagedScoreLibraryError.invalidLocation
        }

        return resolvedURL
    }

    func relativePath(for url: URL) throws -> String? {
        let rootURL = try ManagedScoreLibraryPaths.visibleRootURL(fileManager: fileManager).standardizedFileURL
        let standardizedURL = url.standardizedFileURL
        let rootPath = rootURL.path
        let documentPath = standardizedURL.path

        guard documentPath == rootPath || documentPath.hasPrefix(rootPath + "/") else {
            return nil
        }

        if documentPath == rootPath {
            return ""
        }

        return String(documentPath.dropFirst(rootPath.count + 1))
    }

    func removeDocument(atRelativePath relativePath: String) throws {
        let documentURL = try url(forRelativePath: relativePath)
        let itemRootURL = containerURLForRemoval(of: documentURL)

        guard fileManager.fileExists(atPath: itemRootURL.path) else {
            throw ManagedScoreLibraryError.missingDocument
        }

        try fileManager.removeItem(at: itemRootURL)
    }

    func visibleScoreDocuments() throws -> [ManagedLibraryDocument] {
        try prepareStorageIfNeeded()

        let scoresRootURL = try ManagedScoreLibraryPaths.itemsRootURL(fileManager: fileManager)
        guard let enumerator = fileManager.enumerator(
            at: scoresRootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var scoreURLs: [URL] = []
        var mscxContainerURLs: Set<URL> = []
        for case let fileURL as URL in enumerator {
            let fileExtension = fileURL.pathExtension.lowercased()
            guard Self.supportedScoreExtensions.contains(fileExtension) else {
                continue
            }

            guard try relativePath(for: fileURL) != nil else {
                continue
            }

            scoreURLs.append(fileURL)
            if fileExtension == ScoreFileFormat.mscx.rawValue {
                mscxContainerURLs.insert(fileURL.deletingLastPathComponent().standardizedFileURL)
            }
        }

        let documents = try scoreURLs
            .filter { scoreURL in
                let fileExtension = scoreURL.pathExtension.lowercased()
                guard fileExtension != ScoreFileFormat.mscx.rawValue else {
                    return true
                }
                return !isResourceInsideMSCXContainer(
                    scoreURL,
                    scoresRootURL: scoresRootURL,
                    mscxContainerURLs: mscxContainerURLs
                )
            }
            .map { scoreURL in
                ManagedLibraryDocument(
                    canonicalURL: scoreURL,
                    relativeMainFilePath: try relativePath(for: scoreURL).requiredLibraryPath()
                )
            }

        return documents.sorted {
            $0.canonicalURL.lastPathComponent.localizedStandardCompare($1.canonicalURL.lastPathComponent) == .orderedAscending
        }
    }

    func migrateLegacyLibraryIfNeeded() throws {
        try prepareStorageIfNeeded()

        try migratePreviousNestedVisibleLibraryIfNeeded()

        let legacyRootURL = try ManagedScoreLibraryPaths.legacyItemsRootURL(fileManager: fileManager)
        guard fileManager.fileExists(atPath: legacyRootURL.path) else {
            return
        }

        let existingVisibleDocuments = try visibleScoreDocuments()
        guard existingVisibleDocuments.isEmpty else {
            return
        }

        guard let legacyChildren = try? fileManager.contentsOfDirectory(
            at: legacyRootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let scoresRootURL = try ManagedScoreLibraryPaths.itemsRootURL(fileManager: fileManager)
        for legacyItemURL in legacyChildren {
            let scoreURLs = scoreDocumentURLs(inLegacyItem: legacyItemURL)
            for scoreURL in scoreURLs {
                if scoreURL.pathExtension.lowercased() == ScoreFileFormat.mscx.rawValue {
                    let destinationFolderURL = uniqueDestinationURL(
                        for: legacyItemURL.lastPathComponent,
                        in: scoresRootURL,
                        isDirectory: true
                    )
                    try? fileManager.copyItem(at: legacyItemURL, to: destinationFolderURL)
                    break
                } else {
                    let destinationURL = uniqueDestinationURL(
                        for: scoreURL.lastPathComponent,
                        in: scoresRootURL,
                        isDirectory: false
                    )
                    try? fileManager.copyItem(at: scoreURL, to: destinationURL)
                }
            }
        }
    }

    private func migratePreviousNestedVisibleLibraryIfNeeded() throws {
        let previousScoresRootURL = try ManagedScoreLibraryPaths.previousNestedVisibleItemsRootURL(fileManager: fileManager)
        guard fileManager.fileExists(atPath: previousScoresRootURL.path) else {
            return
        }

        let currentScoresRootURL = try ManagedScoreLibraryPaths.itemsRootURL(fileManager: fileManager)
        let existingVisibleDocuments = try visibleScoreDocuments()
        guard existingVisibleDocuments.isEmpty else {
            return
        }

        guard let previousChildren = try? fileManager.contentsOfDirectory(
            at: previousScoresRootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for childURL in previousChildren {
            let isDirectory = (try? childURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? childURL.hasDirectoryPath
            let destinationURL = uniqueDestinationURL(
                for: childURL.lastPathComponent,
                in: currentScoresRootURL,
                isDirectory: isDirectory
            )
            try? fileManager.moveItem(at: childURL, to: destinationURL)
        }
    }

    private func coordinatedRead(from sourceURL: URL, perform action: (URL) throws -> Void) throws {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var capturedError: Error?

        coordinator.coordinate(readingItemAt: sourceURL, options: [], error: &coordinationError) { coordinatedURL in
            do {
                try action(coordinatedURL)
            } catch {
                capturedError = error
            }
        }

        if let coordinationError {
            throw coordinationError
        }

        if let capturedError {
            throw capturedError
        }
    }

    private static let supportedScoreExtensions: Set<String> = [
        ScoreFileFormat.mscz.rawValue,
        ScoreFileFormat.mscx.rawValue,
        ScoreFileFormat.mxl.rawValue,
        ScoreFileFormat.musicxml.rawValue,
        "xml"
    ]

    private func uniqueDestinationURL(for preferredName: String, in directoryURL: URL, isDirectory: Bool) -> URL {
        let sanitizedName = sanitizedFileName(preferredName)
        let baseName = (sanitizedName as NSString).deletingPathExtension.trimmedToNil ?? "Score"
        let pathExtension = (sanitizedName as NSString).pathExtension

        var candidateName = sanitizedName
        var candidateURL = directoryURL.appendingPathComponent(candidateName, isDirectory: isDirectory)
        var duplicateIndex = 2
        while fileManager.fileExists(atPath: candidateURL.path) {
            if pathExtension.isEmpty {
                candidateName = "\(baseName) \(duplicateIndex)"
            } else {
                candidateName = "\(baseName) \(duplicateIndex).\(pathExtension)"
            }
            candidateURL = directoryURL.appendingPathComponent(candidateName, isDirectory: isDirectory)
            duplicateIndex += 1
        }

        return candidateURL
    }

    private func sanitizedFileName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:")
            .union(.newlines)
            .union(.controlCharacters)
        let sanitized = name
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "Score" : sanitized
    }

    private func containerURLForRemoval(of documentURL: URL) -> URL {
        if documentURL.pathExtension.lowercased() == ScoreFileFormat.mscx.rawValue {
            return documentURL.deletingLastPathComponent()
        }

        return documentURL
    }

    private func scoreDocumentURLs(inLegacyItem legacyItemURL: URL) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: legacyItemURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { item -> URL? in
            guard let url = item as? URL else {
                return nil
            }
            return Self.supportedScoreExtensions.contains(url.pathExtension.lowercased()) ? url : nil
        }
    }

    private func isResourceInsideMSCXContainer(_ url: URL,
                                               scoresRootURL: URL,
                                               mscxContainerURLs: Set<URL>) -> Bool
    {
        let rootURL = scoresRootURL.standardizedFileURL
        var candidateURL = url.deletingLastPathComponent().standardizedFileURL

        while candidateURL.path != rootURL.path {
            if mscxContainerURLs.contains(candidateURL) {
                return true
            }

            let parentURL = candidateURL.deletingLastPathComponent().standardizedFileURL
            guard parentURL.path != candidateURL.path else {
                return false
            }
            candidateURL = parentURL
        }

        return false
    }
}

private extension Optional where Wrapped == String {
    func requiredLibraryPath() throws -> String {
        guard let self, !self.isEmpty else {
            throw ManagedScoreLibraryError.invalidLocation
        }

        return self
    }
}
