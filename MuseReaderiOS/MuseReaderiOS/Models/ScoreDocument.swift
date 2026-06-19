//
//  ScoreDocument.swift
//  MuseReaderiOS
//
//

import Foundation
import UIKit

enum ScoreFileFormat: String, Codable, Sendable {
    case mscz
    case mscx
    case mxl
    case musicxml

    var displayName: String {
        switch self {
        case .mscz:
            return "MSCZ Package"
        case .mscx:
            return "MSCX Score"
        case .mxl:
            return "Compressed MusicXML"
        case .musicxml:
            return "MusicXML Score"
        }
    }
}

struct ScoreDocument: Identifiable, Sendable {
    let id: String
    let fileReference: String
    let url: URL
    let displayName: String
    let format: ScoreFileFormat
    let title: String?
    let subtitle: String?
    let composer: String?
    let lyricist: String?
    let arranger: String?
    let rootFilePath: String
    let museScoreVersion: String?
    let partCount: Int
    let parts: [ScorePart]
    let packageEntries: [String]
    let previewImageData: Data?
    let scoreExcerpt: String
    let fileSize: Int64?
    let modificationDate: Date?

    var primaryTitle: String {
        title?.trimmedToNil ?? displayName
    }

    var secondaryLine: String? {
        composer?.trimmedToNil ?? lyricist?.trimmedToNil ?? subtitle?.trimmedToNil
    }

    var previewImage: UIImage? {
        previewImageData.flatMap(UIImage.init(data:))
    }

    var hasThumbnail: Bool {
        previewImageData != nil
    }
}

struct ScorePart: Identifiable, Sendable, Equatable {
    let id: String
    let index: Int
    let name: String
    let clef: ScorePartClef
}

enum ScorePartClef: String, Sendable, Equatable {
    case treble
    case alto
    case bass

    nonisolated static func inferred(for partName: String) -> ScorePartClef {
        let lowercasedName = partName.lowercased()

        if lowercasedName.contains("viola") || lowercasedName.contains("alto") {
            return .alto
        }

        if lowercasedName.contains("cello")
            || lowercasedName.contains("bass")
            || lowercasedName.contains("tuba")
            || lowercasedName.contains("bassoon")
            || lowercasedName.contains("trombone")
        {
            return .bass
        }

        return .treble
    }

    var symbol: String {
        switch self {
        case .treble:
            return "𝄞"
        case .alto:
            return "𝄡"
        case .bass:
            return "𝄢"
        }
    }
}

extension ScoreDocument {
    func replacingParts(_ parts: [ScorePart]) -> ScoreDocument {
        ScoreDocument(
            id: id,
            fileReference: fileReference,
            url: url,
            displayName: displayName,
            format: format,
            title: title,
            subtitle: subtitle,
            composer: composer,
            lyricist: lyricist,
            arranger: arranger,
            rootFilePath: rootFilePath,
            museScoreVersion: museScoreVersion,
            partCount: parts.count,
            parts: parts,
            packageEntries: packageEntries,
            previewImageData: previewImageData,
            scoreExcerpt: scoreExcerpt,
            fileSize: fileSize,
            modificationDate: modificationDate
        )
    }
}

extension String {
    var trimmedToNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
