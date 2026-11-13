//
//  ScoreScanService.swift
//  MuseReaderiOS
//
//  Reads printed sheet music (a camera scan, a photo or a PDF) into MusicXML with ScoreScanner's
//  ScannerCore package: the notes on this device (copisteria, ONNX Runtime), and chord names, title,
//  composer, tempo, part names and staff text with Apple's model on Private Cloud Compute. The
//  on-device Apple model is never used (`allowOnDeviceFallback` stays off). iOS only: Android has no
//  reader yet (see MuseReaderAndroid/FEATURES_TODO.md).
//

#if !os(Android)
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers
#if canImport(ScannerCore)
import ScannerCore
#endif

/// A page image or a PDF handed to the reader.
struct ScoreScanInput: Sendable {
    enum Kind: Sendable {
        case image
        case pdf
    }

    let kind: Kind
    let data: Data
    /// The name used when the reader finds no printed title: the file's name, or nil for a camera
    /// scan or a photo.
    let sourceName: String?
}

/// A finished reading.
struct ScoreScanResult: Sendable {
    let musicXML: Data
    let title: String?
    let chordCount: Int
    let pageCount: Int
    /// False when only the notes were read (Private Cloud Compute unavailable).
    let readChordsAndText: Bool
}

enum ScoreScanError: LocalizedError {
    case readerUnavailable
    case invalidImage
    case unsupportedFile

    var errorDescription: String? {
        switch self {
        case .readerUnavailable:
            return "This build of Aria does not include the score reader."
        case .invalidImage:
            return "Aria could not read this image. Choose a JPEG, PNG or HEIC photo under 80 megapixels."
        case .unsupportedFile:
            return "Choose a PDF or an image of printed music."
        }
    }
}

enum ScoreScanService {
    /// Whether Scan is offered. ScannerCore 0.1.0 always reads the title and composer with Apple's
    /// model, even with chord and text reading off, so a reading needs iOS 27. Drop this gate once
    /// the package has a notes-only mode that skips the model.
    static var isSupported: Bool {
        #if canImport(ScannerCore)
        if #available(iOS 27.0, *) {
            return true
        }
        return false
        #else
        return false
        #endif
    }

    /// Whether Apple's model on Private Cloud Compute can read chords and text here (iOS 27 with
    /// Apple Intelligence). Without it, only the notes are read.
    static var cloudReadingAvailable: Bool {
        #if canImport(ScannerCore)
        return ScoreReader.cloudReadingAvailable
        #else
        return false
        #endif
    }

    /// Reads `input`. `notesOnly` skips chord names and staff text (the title and composer are then
    /// not read either). One reading at a time; cancel by cancelling the calling task.
    static func read(
        _ input: ScoreScanInput,
        notesOnly: Bool,
        progress: @escaping @Sendable (String) -> Void
    ) async throws -> ScoreScanResult {
        #if canImport(ScannerCore)
        let readsText = !notesOnly
        // Never set allowOnDeviceFallback: the on-device model is not accurate enough for scores.
        let options = ScoreReadOptions(readChordNames: readsText, readStaffText: readsText)
        let reading: ScoreReading
        switch input.kind {
        case .image:
            reading = try await ScoreReader.read(image: input.data, title: "", options: options, progress: progress)
        case .pdf:
            reading = try await ScoreReader.read(pdf: input.data, title: "", options: options, progress: progress)
        }
        return ScoreScanResult(
            musicXML: reading.score.xml,
            title: reading.title,
            chordCount: reading.chordCount,
            pageCount: reading.score.pageCount,
            readChordsAndText: readsText
        )
        #else
        throw ScoreScanError.readerUnavailable
        #endif
    }

    /// True when a reading stopped because Private Cloud Compute was unavailable or refused a
    /// request (for example rate limiting), so reading the notes alone can still work.
    static func isCloudFailure(_ error: Error) -> Bool {
        #if canImport(ScannerCore)
        return error is AppleModelRouteError
        #else
        return false
        #endif
    }

    // MARK: - Sources

    /// A PDF or image file from Files.
    nonisolated static func input(fromFileAt url: URL) throws -> ScoreScanInput {
        let startedScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if startedScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let data = try Data(contentsOf: url)
        let name = url.deletingPathExtension().lastPathComponent
        let type = UTType(filenameExtension: url.pathExtension.lowercased())
        if type?.conforms(to: .pdf) == true || data.starts(with: Data("%PDF".utf8)) {
            return ScoreScanInput(kind: .pdf, data: data, sourceName: name)
        }
        guard type?.conforms(to: .image) ?? true else {
            throw ScoreScanError.unsupportedFile
        }
        return ScoreScanInput(kind: .image, data: try normalizedImage(data), sourceName: name)
    }

    /// A photo from the library.
    nonisolated static func input(fromPhotoData data: Data) throws -> ScoreScanInput {
        ScoreScanInput(kind: .image, data: try normalizedImage(data), sourceName: nil)
    }

    /// Pages from the document camera: one page is read as an image, several as one PDF so the
    /// reader carries the meter from page to page.
    nonisolated static func input(fromCameraPages pages: [UIImage]) -> ScoreScanInput {
        if pages.count == 1 {
            return ScoreScanInput(kind: .image, data: png(from: pages[0]), sourceName: nil)
        }
        return ScoreScanInput(kind: .pdf, data: pdf(from: pages), sourceName: nil)
    }

    /// JPEG and PNG pass through untouched; other images (HEIC, TIFF) become an oriented PNG.
    nonisolated static func normalizedImage(_ data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 80_000_000 / height
        else {
            throw ScoreScanError.invalidImage
        }
        let type = CGImageSourceGetType(source) as String?
        if type == UTType.jpeg.identifier || type == UTType.png.identifier {
            return data
        }
        guard let image = UIImage(data: data) else {
            throw ScoreScanError.invalidImage
        }
        return png(from: image)
    }

    nonisolated private static func png(from image: UIImage) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: image.size, format: format).pngData { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    nonisolated private static func pdf(from images: [UIImage]) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: CGSize(width: 1, height: 1)))
        return renderer.pdfData { context in
            for image in images {
                let bounds = CGRect(origin: .zero, size: image.size)
                context.beginPage(withBounds: bounds, pageInfo: [:])
                UIColor.white.setFill()
                UIBezierPath(rect: bounds).fill()
                image.draw(in: bounds)
            }
        }
    }

    // MARK: - Import

    /// Writes the MusicXML to a temporary folder, named after the printed title, the source file,
    /// or "Scanned Score". The caller removes the folder after importing.
    static func writeTemporaryMusicXML(_ result: ScoreScanResult, input: ScoreScanInput) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("AriaScan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(fileName(for: result, input: input)).appendingPathExtension("musicxml")
        try result.musicXML.write(to: url, options: .atomic)
        return url
    }

    static func fileName(for result: ScoreScanResult, input: ScoreScanInput) -> String {
        let candidates = [result.title, input.sourceName, "Scanned Score"]
        for candidate in candidates {
            let cleaned = (candidate ?? "")
                .components(separatedBy: CharacterSet(charactersIn: "/:\\").union(.newlines).union(.controlCharacters))
                .joined(separator: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
            if !cleaned.isEmpty {
                return String(cleaned.prefix(80))
            }
        }
        return "Scanned Score"
    }
}
#endif
