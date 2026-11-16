//
//  ScoreScanService.swift
//  MuseReaderiOS
//
//  Reads printed sheet music (a camera scan, a photo or a PDF) into MusicXML with ScoreScanner's
//  ScannerCore package, entirely on this device: the notes with copisteria, the chord names with
//  ScannerCore's chord finder and chord reader, and the title, composer, tempo, rehearsal marks,
//  navigation and other staff text with its text reader (all ONNX Runtime). Nothing is sent to
//  Apple's model or any server. Printed D.S./D.C., To Coda and Fine reach the score as playback jumps
//  when their segno and coda were found. On Android the app draws the pages (AriaScanPages.kt) and
//  ScannerCore reads them the same way; there is no camera scan there yet.
//

import Foundation
#if !os(Android)
import ImageIO
import UIKit
#endif
import UniformTypeIdentifiers
#if canImport(ScannerCore)
import ScannerCore
#endif

/// A page image or a PDF handed to the reader.
struct ScoreScanInput: Sendable {
    enum Kind: Sendable {
        case image
        case pdf
        /// Android: a PDF or picture in `file`, drawn page by page by the app (AriaScanPages.kt).
        case pageFile
    }

    let kind: Kind
    let data: Data
    /// The file a `pageFile` input draws its pages from.
    var file: URL? = nil
    /// The name used when the reader finds no printed title: the file's name, or nil for a camera
    /// scan or a photo.
    let sourceName: String?
    /// Pages to read, shown while reading: 1 for an image, the PDF's page count otherwise.
    var pageCount: Int = 1
}

/// A finished reading.
struct ScoreScanResult: Sendable {
    let musicXML: Data
    let title: String?
    let chordCount: Int
    let pageCount: Int
    /// False when only the notes were read.
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
    /// Whether Scan is offered: on every iOS version Aria supports, since ScannerCore 0.1.2 reads
    /// notes and chords on the device.
    static var isSupported: Bool {
        #if canImport(ScannerCore)
        return true
        #else
        return false
        #endif
    }

    /// Whether this build carries ScannerCore's on-device chord reader. Without it, only the notes
    /// are read.
    static var chordReadingAvailable: Bool {
        #if os(Android)
        // The models ship inside the app (AndroidScanPages), not in ScannerCore's bundle.
        return true
        #elseif canImport(ScannerCore)
        return ScoreReader.localChordReadingAvailable()
        #else
        return false
        #endif
    }

    /// Reads `input`. `notesOnly` skips chord names. One reading at a time; cancel by cancelling the
    /// calling task.
    static func read(
        _ input: ScoreScanInput,
        notesOnly: Bool,
        progress: @escaping @Sendable (String) -> Void
    ) async throws -> ScoreScanResult {
        #if canImport(ScannerCore)
        let readsText = !notesOnly
        // Chords and text on this device, so Apple's model is never asked (`usesAppleModel` is false).
        let options = ScoreReadOptions(
            readChordNames: readsText, readStaffText: readsText, chordReader: .onDevice, textReader: .onDevice)
        let reading: ScoreReading
        switch input.kind {
        case .image:
            reading = try await ScoreReader.read(image: input.data, title: "", options: options, progress: progress)
        case .pdf:
            #if os(Android)
            throw ScoreScanError.unsupportedFile
            #else
            reading = try await ScoreReader.read(pdf: input.data, title: "", options: options, progress: progress)
            #endif
        case .pageFile:
            #if os(Android)
            guard let file = input.file else {
                throw ScoreScanError.unsupportedFile
            }
            reading = try await ScoreReader.read(
                pageCount: input.pageCount, title: "", models: modelsDirectory(), options: options,
                progress: progress
            ) { index in
                try AndroidScanPages.page(index, of: file)
            }
            #else
            throw ScoreScanError.unsupportedFile
            #endif
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

    /// Where the reader's models are: in ScannerCore's bundle, or on Android copied out of the app
    /// (AndroidScanPages).
    nonisolated private static func modelsDirectory() throws -> URL {
        #if os(Android)
        return try AndroidScanPages.modelsDirectory()
        #elseif canImport(ScannerCore)
        return Scanner.bundledModels
        #else
        throw ScoreScanError.readerUnavailable
        #endif
    }

    // MARK: - Sources

    #if os(Android)
    /// A PDF or image file from the document picker (already copied into Aria's cache).
    nonisolated static func input(fromFileAt url: URL) throws -> ScoreScanInput {
        let name = url.deletingPathExtension().lastPathComponent
        let file = try AndroidScanPages.keep(url)
        let pages = AndroidScanPages.pageCount(of: file)
        guard pages > 0 else {
            try? FileManager.default.removeItem(at: file)
            throw ScoreScanError.unsupportedFile
        }
        return ScoreScanInput(kind: .pageFile, data: Data(), file: file, sourceName: name, pageCount: pages)
    }

    /// A photo from the picker.
    nonisolated static func input(fromPhotoData data: Data) throws -> ScoreScanInput {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("AriaScanPhoto-\(UUID().uuidString)")
        try data.write(to: file, options: .atomic)
        guard AndroidScanPages.pageCount(of: file) == 1 else {
            try? FileManager.default.removeItem(at: file)
            throw ScoreScanError.invalidImage
        }
        return ScoreScanInput(kind: .pageFile, data: Data(), file: file, sourceName: nil, pageCount: 1)
    }
    #else
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
            return ScoreScanInput(kind: .pdf, data: data, sourceName: name, pageCount: pdfPageCount(data))
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
        return ScoreScanInput(kind: .pdf, data: pdf(from: pages), sourceName: nil, pageCount: pages.count)
    }

    nonisolated private static func pdfPageCount(_ data: Data) -> Int {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider)
        else {
            return 1
        }
        return max(1, document.numberOfPages)
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

    #endif

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
