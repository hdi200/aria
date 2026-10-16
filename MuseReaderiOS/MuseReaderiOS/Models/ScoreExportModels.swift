//
//  ScoreExportModels.swift
//  MuseReaderiOS
//
//  Export formats, requests and errors, kept apart from the export panel and
//  exporters (UIKit, AVFoundation, PDFKit).
//

import Foundation
import SwiftUI

enum ScoreReaderExportFormat: String, CaseIterable, Identifiable {
    case museScore
    case pdf
    case musicXML
    case midi
    case audio
    case images
    case video

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .museScore:
            return ".mscz"
        case .pdf:
            return "PDF"
        case .musicXML:
            return "MusicXML"
        case .midi:
            return "MIDI"
        case .audio:
            return "Audio"
        case .images:
            return "Images"
        case .video:
            return "Video"
        }
    }

    var subtitle: String {
        switch self {
        case .museScore:
            return "Native MuseScore file"
        case .pdf:
            return "Best for sharing & printing"
        case .musicXML:
            return ".musicxml or .xml"
        case .midi:
            return ".mid for playback / DAW"
        case .audio:
            return ".wav"
        case .images:
            return "PNG pages"
        case .video:
            return "Scrolling score or piano"
        }
    }

    var systemImage: String {
        switch self {
        case .museScore:
            return "doc.badge.gearshape"
        case .pdf:
            return "doc.richtext"
        case .musicXML:
            return "doc.text"
        case .midi:
            return "music.note"
        case .audio:
            return "waveform"
        case .images:
            return "photo.on.rectangle"
        case .video:
            return "play.rectangle"
        }
    }

    var tint: Color {
        switch self {
        case .museScore:
            return Color.gray
        case .pdf:
            return Color.red
        case .musicXML:
            return Color.gray
        case .midi:
            return Color.purple
        case .audio:
            return Color.green
        case .images:
            return Color.blue
        case .video:
            return Color.orange
        }
    }

    var isAvailable: Bool {
        switch self {
        case .museScore, .pdf, .musicXML, .midi, .audio, .images, .video:
            return true
        }
    }

    var exportsDisplayedView: Bool {
        switch self {
        case .pdf, .images, .video:
            return true
        case .museScore, .musicXML, .midi, .audio:
            return false
        }
    }
}

struct ScoreReaderExportDraft {
    var includesFullScore = true
    var includesParts = false
    var format: ScoreReaderExportFormat = .pdf
    var selectedPartIDs: Set<String> = []
    var fileName = ""
    var exportPartsInConcertPitch = false
    var exportPartsInOriginalKey = false
    var videoStyle: ScoreVideoStyle = .scrolling
    /// 9:16 for Reels and TikTok, for every layout (Pages uses its portrait style).
    var videoVertical = false
    var videoBackgroundImageData: Data? = nil
    var videoBackgroundImageName: String? = nil
    /// The built-in photo in use (`ScoreVideoBackgroundPhoto.id`), or nil for
    /// the person's own.
    var videoBackgroundPhotoID: String? = nil
    /// The person's own photo, kept while a built-in one is chosen.
    var videoCustomBackgroundData: Data? = nil

    var hasExportContent: Bool {
        includesFullScore || includesParts
    }
}

struct ScoreReaderSharedExportItems: Identifiable {
    let urls: [URL]

    var id: String {
        urls.map(\.absoluteString).joined(separator: "|")
    }
}

enum ScoreReaderExportError: LocalizedError {
    case unsupportedFormat(String)
    case noContentSelected
    case noPages
    case noAudio
    case imageEncodingFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format):
            return "\(format) export is not available in the current render bridge."
        case .noContentSelected:
            return "Choose at least one export target."
        case .noPages:
            return "There are no rendered pages to export."
        case .noAudio:
            return "There is no playback audio to export."
        case .imageEncodingFailed:
            return "Aria could not encode one of the score pages."
        }
    }
}

enum ScoreReaderExportTarget {
    case fullScore(pageCount: Int)
    case part(ScorePart, pageCount: Int)

    var pageCount: Int {
        switch self {
        case .fullScore(let pageCount), .part(_, let pageCount):
            return pageCount
        }
    }
}

struct ScoreVideoBackgroundPhoto: Identifiable, Sendable {
    /// The file name in Resources/VideoBackgrounds, without ".jpg".
    let id: String
    let name: String

    static let all: [ScoreVideoBackgroundPhoto] = [
        ScoreVideoBackgroundPhoto(id: "mount-fuji", name: "Mount Fuji"),
        ScoreVideoBackgroundPhoto(id: "grand-canyon", name: "Grand Canyon"),
        ScoreVideoBackgroundPhoto(id: "moonlit-fjord", name: "Moonlit fjord"),
        ScoreVideoBackgroundPhoto(id: "spruce-forest", name: "Spruce forest"),
        ScoreVideoBackgroundPhoto(id: "misty-mountains", name: "Misty mountains"),
        ScoreVideoBackgroundPhoto(id: "northern-lights", name: "Northern lights"),
        ScoreVideoBackgroundPhoto(id: "mountain-sunset", name: "Mountain sunset"),
        ScoreVideoBackgroundPhoto(id: "snowy-peaks", name: "Snowy peaks"),
        ScoreVideoBackgroundPhoto(id: "pink-bay", name: "Pink bay"),
        ScoreVideoBackgroundPhoto(id: "beach-sunset", name: "Beach sunset"),
        ScoreVideoBackgroundPhoto(id: "forest-river", name: "Forest river"),
        ScoreVideoBackgroundPhoto(id: "beech-ferns", name: "Beech and ferns"),
        ScoreVideoBackgroundPhoto(id: "blue-sky", name: "Blue sky")
    ]

    var url: URL? {
        AppResources.url(forResource: id, withExtension: "jpg")
            ?? AppResources.url(forResource: id, withExtension: "jpg", subdirectory: "VideoBackgrounds")
    }
}

extension ScoreReaderExportFormat {
    /// The formats a whole setlist can be shared as. MIDI, audio, and page
    /// images stay with single-score export, where the reader can still offer
    /// the part and page choices those formats depend on.
    static let setlistShareFormats: [ScoreReaderExportFormat] = [.pdf, .museScore, .musicXML]

    var setlistFileExtension: String {
        switch self {
        case .pdf:
            return "pdf"
        case .museScore:
            return "mscz"
        case .musicXML:
            return "musicxml"
        case .midi:
            return "mid"
        case .audio:
            return "wav"
        case .images:
            return "png"
        case .video:
            return "mp4"
        }
    }
}

struct SetlistShareFailure: Identifiable {
    let id = UUID()
    let scoreTitle: String
    let message: String
}

struct SetlistSharePreparation {
    let urls: [URL]
    let failures: [SetlistShareFailure]
}

enum SetlistShareError: LocalizedError {
    case emptySetlist
    case unsupportedFormat(String)
    case unavailableScore(String)
    case pdfMergeFailed
    case noSharableScores(String?)

    var errorDescription: String? {
        switch self {
        case .emptySetlist:
            return "Add scores to this setlist before sharing it."
        case .unsupportedFormat(let format):
            return "\(format) is not available for setlist sharing."
        case .unavailableScore(let scoreTitle):
            return "Aria could not open “\(scoreTitle)”. Open it once in the reader and try again."
        case .pdfMergeFailed:
            return "Aria could not combine these scores into one PDF."
        case .noSharableScores(let reason):
            let summary = "Aria could not prepare any of the scores in this setlist."
            guard let reason else {
                return summary
            }
            return "\(summary) \(reason)"
        }
    }
}
