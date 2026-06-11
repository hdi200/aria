//
//  ReaderRecentDocument.swift
//  MuseReaderiOS
//
//  Created on 4/13/26.
//

import Foundation

struct ReaderRecentDocument: Identifiable, Codable, Equatable, Sendable {
    let fileReference: String
    let bookmarkData: Data?
    let libraryRelativePath: String?
    let displayName: String
    let title: String?
    let subtitle: String?
    let composer: String?
    let format: ScoreFileFormat
    let previewImageData: Data?
    let importedAt: Date
    let lastOpened: Date
    let fileSize: Int64?
    let modificationDate: Date?
    let rootFilePath: String
    let museScoreVersion: String?

    private enum CodingKeys: String, CodingKey {
        case fileReference
        case bookmarkData
        case libraryRelativePath
        case displayName
        case title
        case subtitle
        case composer
        case format
        case previewImageData
        case importedAt
        case lastOpened
        case fileSize
        case modificationDate
        case rootFilePath
        case museScoreVersion
    }

    var id: String {
        fileReference
    }

    var primaryTitle: String {
        title?.trimmedToNil ?? displayName
    }

    var secondaryLine: String? {
        composer?.trimmedToNil ?? subtitle?.trimmedToNil
    }

    var isStoredInLibrary: Bool {
        libraryRelativePath != nil
    }

    var setlistKey: String {
        libraryRelativePath ?? fileReference
    }

    func matchesCachedFileIdentity(of document: ScoreDocument) -> Bool {
        guard fileReference == document.fileReference || libraryRelativePath != nil else {
            return false
        }

        if let modificationDate, let documentModificationDate = document.modificationDate {
            return modificationDate == documentModificationDate
        }

        if let fileSize, let documentFileSize = document.fileSize {
            return fileSize == documentFileSize
        }

        return modificationDate == nil && document.modificationDate == nil && fileSize == nil && document.fileSize == nil
    }

    private init(fileReference: String,
                 bookmarkData: Data?,
                 libraryRelativePath: String?,
                 displayName: String,
                 title: String?,
                 subtitle: String?,
                 composer: String?,
                 format: ScoreFileFormat,
                 previewImageData: Data?,
                 importedAt: Date,
                 lastOpened: Date,
                 fileSize: Int64?,
                 modificationDate: Date?,
                 rootFilePath: String,
                 museScoreVersion: String?)
    {
        self.fileReference = fileReference
        self.bookmarkData = bookmarkData
        self.libraryRelativePath = libraryRelativePath
        self.displayName = displayName
        self.title = title
        self.subtitle = subtitle
        self.composer = composer
        self.format = format
        self.previewImageData = previewImageData
        self.importedAt = importedAt
        self.lastOpened = lastOpened
        self.fileSize = fileSize
        self.modificationDate = modificationDate
        self.rootFilePath = rootFilePath
        self.museScoreVersion = museScoreVersion
    }

    /// Returns a copy with a different cached preview image, preserving all other
    /// metadata. Used to overlay freshly rendered thumbnails onto a refreshed
    /// library list without rebuilding from a `ScoreDocument`.
    func replacingPreviewImageData(_ data: Data?) -> ReaderRecentDocument {
        ReaderRecentDocument(
            fileReference: fileReference,
            bookmarkData: bookmarkData,
            libraryRelativePath: libraryRelativePath,
            displayName: displayName,
            title: title,
            subtitle: subtitle,
            composer: composer,
            format: format,
            previewImageData: data,
            importedAt: importedAt,
            lastOpened: lastOpened,
            fileSize: fileSize,
            modificationDate: modificationDate,
            rootFilePath: rootFilePath,
            museScoreVersion: museScoreVersion
        )
    }

    init(document: ScoreDocument,
         bookmarkData: Data? = nil,
         libraryRelativePath: String? = nil,
         previewImageData: Data? = nil,
         importedAt: Date = .now,
         lastOpened: Date = .now)
    {
        fileReference = document.fileReference
        self.bookmarkData = bookmarkData
        self.libraryRelativePath = libraryRelativePath
        displayName = document.displayName
        title = document.title
        subtitle = document.subtitle
        composer = document.composer
        format = document.format
        self.previewImageData = previewImageData ?? document.previewImageData
        self.importedAt = importedAt
        self.lastOpened = lastOpened
        fileSize = document.fileSize
        modificationDate = document.modificationDate
        rootFilePath = document.rootFilePath
        museScoreVersion = document.museScoreVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fileReference = try container.decode(String.self, forKey: .fileReference)
        bookmarkData = try container.decodeIfPresent(Data.self, forKey: .bookmarkData)
        libraryRelativePath = try container.decodeIfPresent(String.self, forKey: .libraryRelativePath)
        displayName = try container.decode(String.self, forKey: .displayName)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        composer = try container.decodeIfPresent(String.self, forKey: .composer)
        format = try container.decode(ScoreFileFormat.self, forKey: .format)
        previewImageData = try container.decodeIfPresent(Data.self, forKey: .previewImageData)
        lastOpened = try container.decode(Date.self, forKey: .lastOpened)
        importedAt = try container.decodeIfPresent(Date.self, forKey: .importedAt) ?? lastOpened
        fileSize = try container.decodeIfPresent(Int64.self, forKey: .fileSize)
        modificationDate = try container.decodeIfPresent(Date.self, forKey: .modificationDate)
        rootFilePath = try container.decode(String.self, forKey: .rootFilePath)
        museScoreVersion = try container.decodeIfPresent(String.self, forKey: .museScoreVersion)
    }
}
