//
//  SetlistShareExporter.swift
//  MuseReaderiOS
//
//

import Foundation
#if os(Android)
import UIKit
#else
import PDFKit
import UIKit
#endif

/// Turns a setlist into files the system share sheet can hand to another app.
///
/// Scores are exported one at a time: every format except an already-packaged
/// `.mscz` needs a live render session, and the render core only tolerates one
/// open score at a time. Keeping each session scoped to a single iteration also
/// keeps a long setlist from holding every native score in memory at once.
@MainActor
enum SetlistShareExporter {
    static func prepareShareItems(
        setlistName: String,
        scores: [ReaderRecentDocument],
        format: ScoreReaderExportFormat,
        combinesPDFPages: Bool,
        model: MuseReaderAppModel,
        progress: (Int) -> Void
    ) async throws -> SetlistSharePreparation {
        guard !scores.isEmpty else {
            throw SetlistShareError.emptySetlist
        }
        guard ScoreReaderExportFormat.setlistShareFormats.contains(format) else {
            throw SetlistShareError.unsupportedFormat(format.title)
        }

        let exportDirectory = try makeExportDirectory(for: setlistName)
        var shareURLs: [URL] = []
        var combinedPDFDocuments: [(title: String, data: Data)] = []
        var failures: [SetlistShareFailure] = []
        var usedBaseNames: Set<String> = []

        for (index, score) in scores.enumerated() {
            try Task.checkCancellation()
            progress(index)

            do {
                let baseName = uniqueFileBaseName(for: score, usedBaseNames: &usedBaseNames)
                switch format {
                case .pdf:
                    let pdfData = try await pdfData(for: score, model: model)
                    if combinesPDFPages {
                        combinedPDFDocuments.append((title: score.primaryTitle, data: pdfData))
                    } else {
                        shareURLs.append(
                            try write(pdfData, to: exportDirectory, baseName: baseName, format: format)
                        )
                    }
                case .museScore:
                    shareURLs.append(
                        try await writeMuseScoreCopy(
                            for: score,
                            baseName: baseName,
                            in: exportDirectory,
                            model: model
                        )
                    )
                case .musicXML:
                    let musicXMLData = try await musicXMLData(for: score, model: model)
                    shareURLs.append(
                        try write(musicXMLData, to: exportDirectory, baseName: baseName, format: format)
                    )
                case .midi, .audio, .images, .video:
                    throw SetlistShareError.unsupportedFormat(format.title)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failures.append(
                    SetlistShareFailure(
                        scoreTitle: score.primaryTitle,
                        message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    )
                )
            }
        }

        if !combinedPDFDocuments.isEmpty {
            shareURLs = [
                try writeCombinedPDF(combinedPDFDocuments, to: exportDirectory, setlistName: setlistName)
            ]
        }

        progress(scores.count)

        guard !shareURLs.isEmpty else {
            throw SetlistShareError.noSharableScores(failures.first?.message)
        }

        return SetlistSharePreparation(urls: shareURLs, failures: failures)
    }

    /// Opens a score for export without disturbing Recently Opened. Scores that
    /// still need import normalization fall back to the regular library open;
    /// legacy bookmark-only scores are skipped so sharing never kicks off a
    /// re-import or the unlock flow.
    private static func openSession(
        for score: ReaderRecentDocument,
        model: MuseReaderAppModel
    ) async throws -> ScoreSession {
        if let preloadedSession = try await model.preloadReaderSession(for: score) {
            return preloadedSession
        }

        guard score.libraryRelativePath != nil else {
            throw SetlistShareError.unavailableScore(score.primaryTitle)
        }

        return try await model.loadReaderSession(for: score)
    }

    private static func pdfData(
        for score: ReaderRecentDocument,
        model: MuseReaderAppModel
    ) async throws -> Data {
        let session = try await openSession(for: score, model: model)
        if let liveRenderSession = session.liveRenderSession {
            return try await liveRenderSession.pdfData()
        }

        return try pdfData(fromPreviewPages: session.previewPages, scoreTitle: score.primaryTitle)
    }

    private static func pdfData(fromPreviewPages pages: [ScorePage], scoreTitle: String) throws -> Data {
        #if os(Android)
        // Scores always open with a live session on Android, which writes the PDF.
        throw SetlistShareError.unavailableScore(scoreTitle)
        #else
        let pageImages = pages.compactMap { $0.rasterizedImage() }
        guard let firstPageImage = pageImages.first else {
            throw SetlistShareError.unavailableScore(scoreTitle)
        }

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: firstPageImage.size))
        return renderer.pdfData { context in
            for pageImage in pageImages {
                let pageBounds = CGRect(origin: .zero, size: pageImage.size)
                context.beginPage(withBounds: pageBounds, pageInfo: [:])
                pageImage.draw(in: pageBounds)
            }
        }
        #endif
    }

    private static func musicXMLData(
        for score: ReaderRecentDocument,
        model: MuseReaderAppModel
    ) async throws -> Data {
        let session = try await openSession(for: score, model: model)
        guard let liveRenderSession = session.liveRenderSession else {
            throw ScoreReaderExportError.unsupportedFormat("MusicXML")
        }

        return try await liveRenderSession.musicXMLData()
    }

    private static func writeMuseScoreCopy(
        for score: ReaderRecentDocument,
        baseName: String,
        in directory: URL,
        model: MuseReaderAppModel
    ) async throws -> URL {
        let exportURL = try exportURL(in: directory, baseName: baseName, format: .museScore)

        // Library scores are already packaged, so copying the file avoids paying
        // for a render session per score on a long setlist.
        if score.format == .mscz, let sourceURL = model.managedDocumentURL(for: score) {
            try FileManager.default.copyItem(at: sourceURL, to: exportURL)
            return exportURL
        }

        let session = try await openSession(for: score, model: model)
        guard let liveRenderSession = session.liveRenderSession else {
            throw ScoreReaderExportError.unsupportedFormat(".mscz")
        }

        try await liveRenderSession.save(to: exportURL)
        return exportURL
    }

    private static func writeCombinedPDF(
        _ documents: [(title: String, data: Data)],
        to directory: URL,
        setlistName: String
    ) throws -> URL {
        #if os(Android)
        // Android has no PDFKit; AndroidPDFMerger joins the engine's PDFs the same way.
        let combinedData: Data
        do {
            combinedData = try AndroidPDFMerger.merge(documents.map { AndroidPDFMerger.Source(title: $0.title, data: $0.data) })
        } catch {
            throw SetlistShareError.pdfMergeFailed
        }
        #else
        // The source documents stay alive until the merged data is generated:
        // a PDFPage keeps a reference back to the document it came from.
        let sourceDocuments = try documents.map { source -> (title: String, document: PDFDocument) in
            guard let document = PDFDocument(data: source.data) else {
                throw SetlistShareError.pdfMergeFailed
            }
            return (title: source.title, document: document)
        }

        let combinedDocument = PDFDocument()
        // One bookmark per score, so a PDF reader's sidebar can jump straight
        // to the start of each piece instead of scrolling the whole setlist.
        let outlineRoot = PDFOutline()
        combinedDocument.outlineRoot = outlineRoot
        var insertionIndex = 0
        for source in sourceDocuments {
            let firstPageIndex = insertionIndex
            for pageIndex in 0..<source.document.pageCount {
                guard let page = source.document.page(at: pageIndex) else {
                    continue
                }
                combinedDocument.insert(page, at: insertionIndex)
                insertionIndex += 1
            }

            guard insertionIndex > firstPageIndex, let firstPage = combinedDocument.page(at: firstPageIndex) else {
                continue
            }
            let title = source.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let bookmark = PDFOutline()
            bookmark.label = title.isEmpty ? "Aria Score" : title
            let pageBounds = firstPage.bounds(for: .mediaBox)
            bookmark.destination = PDFDestination(page: firstPage, at: CGPoint(x: pageBounds.minX, y: pageBounds.maxY))
            outlineRoot.insertChild(bookmark, at: outlineRoot.numberOfChildren)
        }

        guard insertionIndex > 0, let combinedData = combinedDocument.dataRepresentation() else {
            throw SetlistShareError.pdfMergeFailed
        }
        #endif

        return try write(
            combinedData,
            to: directory,
            baseName: sanitizedName(setlistName, fallback: "Aria Setlist"),
            format: .pdf
        )
    }

    private static func write(
        _ data: Data,
        to directory: URL,
        baseName: String,
        format: ScoreReaderExportFormat
    ) throws -> URL {
        let exportURL = try exportURL(in: directory, baseName: baseName, format: format)
        try data.write(to: exportURL, options: .atomic)
        return exportURL
    }

    private static func exportURL(
        in directory: URL,
        baseName: String,
        format: ScoreReaderExportFormat
    ) throws -> URL {
        let exportURL = directory
            .appendingPathComponent("\(baseName).\(format.setlistFileExtension)", isDirectory: false)
        if FileManager.default.fileExists(atPath: exportURL.path) {
            try FileManager.default.removeItem(at: exportURL)
        }
        return exportURL
    }

    /// Each share starts from a clean directory so files from an earlier run
    /// never ride along in the share sheet.
    private static func makeExportDirectory(for setlistName: String) throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AriaExports", isDirectory: true)
            .appendingPathComponent("Setlists", isDirectory: true)
            .appendingPathComponent(sanitizedName(setlistName, fallback: "Aria Setlist"), isDirectory: true)

        if FileManager.default.fileExists(atPath: directoryURL.path) {
            try FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return directoryURL
    }

    /// Prefer the score's title verbatim. If a setlist contains two scores with
    /// the same title, add a trailing suffix so neither export is overwritten.
    private static func uniqueFileBaseName(
        for score: ReaderRecentDocument,
        usedBaseNames: inout Set<String>
    ) -> String {
        let title = sanitizedName(score.primaryTitle, fallback: "Aria Score")
        var candidate = title
        var duplicateNumber = 2

        while !usedBaseNames.insert(candidate.lowercased()).inserted {
            candidate = "\(title) (\(duplicateNumber))"
            duplicateNumber += 1
        }

        return candidate
    }

    private static func sanitizedName(_ name: String, fallback: String) -> String {
        let sanitized = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\n", with: " ")
        return sanitized.trimmedToNil ?? fallback
    }
}
