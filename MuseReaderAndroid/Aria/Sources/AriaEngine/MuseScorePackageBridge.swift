// Android's MuseScorePackageBridge: reads MSCZ/MSCX/MusicXML/MXL files the way the iOS
// bridge does (MuseReaderiOS/MuseReaderiOS/Bridge/MuseScorePackageBridge.mm), with the same
// zip reader (MSRZipArchive.cpp, compiled into libaria_engine.so) and error messages.

@_implementationOnly import AriaRenderCoreCxx
@_implementationOnly import CxxStdlib
import Foundation

// Android only: the iOS app has its own Objective-C++ bridge.

private let containerPath = "META-INF/container.xml"

private let preferredThumbnailPaths = [
    "Thumbnails/thumbnail.png",
    "Thumbnails/thumbnail.jpg",
    "Thumbnails/thumbnail.jpeg",
    "thumbnail.png",
    "thumbnail.jpg",
    "thumbnail.jpeg",
    "preview.png",
    "preview.jpg",
    "preview.jpeg",
]

private func stringFromUTF8Data(_ data: Data?) -> String? {
    guard let data else {
        return nil
    }
    return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
}

private func firstCaptureGroup(_ pattern: String, _ source: String) -> String? {
    guard let expression = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
        return nil
    }
    let fullRange = NSRange(source.startIndex..<source.endIndex, in: source)
    guard let match = expression.firstMatch(in: source, options: [], range: fullRange), match.numberOfRanges >= 2,
          let groupRange = Range(match.range(at: 1), in: source) else {
        return nil
    }
    return String(source[groupRange])
}

private func pathExtension(_ path: String) -> String {
    (path as NSString).pathExtension.lowercased()
}

private func isMusicXMLPathExtension(_ pathExtension: String) -> Bool {
    let lowercased = pathExtension.lowercased()
    return lowercased == "musicxml" || lowercased == "xml"
}

private func isMusicXMLDocument(_ xml: String) -> Bool {
    firstCaptureGroup("<\\s*(score-partwise|score-timewise)\\b", xml) != nil
}

private func rootScorePathFromContainer(_ containerXML: String, includeMusicXML: Bool) -> String? {
    guard let rootFilePath = firstCaptureGroup("full-path=\"([^\"]+)\"", containerXML) else {
        return nil
    }
    let fileExtension = pathExtension(rootFilePath)
    if fileExtension == "mscx" || (includeMusicXML && isMusicXMLPathExtension(fileExtension)) {
        return rootFilePath
    }
    return nil
}

private func rootScorePathFromEntries(_ entries: [String], includeMusicXML: Bool) -> String? {
    if let mscx = entries.first(where: { pathExtension($0) == "mscx" }) {
        return mscx
    }
    if includeMusicXML {
        return entries.first { $0 != containerPath && isMusicXMLPathExtension(pathExtension($0)) }
    }
    return nil
}

private func hasSupportedPreviewExtension(_ entryPath: String) -> Bool {
    ["png", "jpg", "jpeg"].contains(pathExtension(entryPath))
}

private func localizedCaseInsensitiveSorted(_ strings: [String]) -> [String] {
    strings.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
}

private func previewPathsFromEntries(_ entries: [String]) -> [String] {
    var previewPaths: [String] = []
    func add(_ path: String) {
        if !previewPaths.contains(path) {
            previewPaths.append(path)
        }
    }
    for preferredPath in preferredThumbnailPaths {
        for entry in entries where entry.caseInsensitiveCompare(preferredPath) == .orderedSame && hasSupportedPreviewExtension(entry) {
            add(entry)
        }
    }
    for entry in entries where entry.lowercased().hasPrefix("thumbnails/") && hasSupportedPreviewExtension(entry) {
        add(entry)
    }
    for entry in entries {
        let lowercasedName = (entry as NSString).lastPathComponent.lowercased()
        if hasSupportedPreviewExtension(entry) && (lowercasedName.contains("thumbnail") || lowercasedName.contains("preview")) {
            add(entry)
        }
    }
    return localizedCaseInsensitiveSorted(previewPaths)
}

private func thumbnailData(from previewAssets: [MSRPreviewAsset]) -> Data? {
    for preferredPath in preferredThumbnailPaths {
        if let asset = previewAssets.first(where: { $0.path.caseInsensitiveCompare(preferredPath) == .orderedSame }) {
            return asset.imageData
        }
    }
    return previewAssets.first?.imageData
}

open class MuseScorePackageBridge: NSObject, @unchecked Sendable {
    public override init() {}

    open func loadDocument(at url: URL) throws -> MSRDocumentPayload {
        let fileExtension = url.pathExtension.lowercased()

        if fileExtension == "mscx" || isMusicXMLPathExtension(fileExtension) {
            let scoreData = try Data(contentsOf: url, options: .mappedIfSafe)
            guard let scoreXML = stringFromUTF8Data(scoreData) else {
                throw bridgeError(.invalidScoreEncoding, "This MSCX file could not be decoded as text.")
            }
            let isMSCX = fileExtension == "mscx"
            if !isMSCX && !isMusicXMLDocument(scoreXML) {
                throw bridgeError(.unsupportedFormat, "This XML file is not a score-partwise or score-timewise MusicXML document.")
            }
            return MSRDocumentPayload(format: isMSCX ? .MSCX : .musicXML, rootFilePath: url.lastPathComponent,
                                      scoreXML: scoreXML, packageEntries: [], previewAssets: [], thumbnailData: nil)
        }

        let isMSCZ = fileExtension == "mscz"
        let isMXL = fileExtension == "mxl"
        guard isMSCZ || isMXL else {
            throw bridgeError(.unsupportedFormat, "Only MSCZ, MSCX, MusicXML, and MXL files are supported right now.")
        }

        let archiveData = try Data(contentsOf: url, options: .mappedIfSafe)
        var archive = msr.ZipArchive()
        var zipError = std.string()
        let opened = archiveData.withUnsafeBytes { raw in
            aria.zipOpen(&archive, raw.bindMemory(to: UInt8.self).baseAddress, raw.count, &zipError)
        }
        guard opened else {
            throw bridgeError(.invalidArchive, "The score package is invalid: \(makeString(zipError))")
        }

        func dataForEntry(_ entryPath: String) throws -> Data {
            var output = aria.Bytes()
            var message = std.string()
            guard aria.zipExtract(archive, std.string(entryPath), &output, &message) else {
                throw bridgeError(.invalidArchive, "Could not read archive entry \(entryPath): \(makeString(message))")
            }
            return makeData(output)
        }

        let entries = localizedCaseInsensitiveSorted(archive.entryNames().map { makeString($0) })
        let containerXML = stringFromUTF8Data(try? dataForEntry(containerPath))

        guard let rootScorePath = containerXML.flatMap({ rootScorePathFromContainer($0, includeMusicXML: isMXL) })
            ?? rootScorePathFromEntries(entries, includeMusicXML: isMXL) else {
            throw bridgeError(.missingScoreFile, isMXL
                ? "The MXL package does not contain a root MusicXML score."
                : "The MSCZ package does not contain a root MSCX score.")
        }

        let scoreData = try dataForEntry(rootScorePath)
        guard let scoreXML = stringFromUTF8Data(scoreData) else {
            throw bridgeError(.invalidScoreEncoding, "The root score file in this package could not be decoded as text.")
        }
        if isMXL && !isMusicXMLDocument(scoreXML) {
            throw bridgeError(.unsupportedFormat,
                              "The root file in this MXL package is not a score-partwise or score-timewise MusicXML document.")
        }

        let previewAssets = previewPathsFromEntries(entries).compactMap { path in
            (try? dataForEntry(path)).map { MSRPreviewAsset(path: path, imageData: $0) }
        }
        return MSRDocumentPayload(format: isMXL ? .MXL : .MSCZ, rootFilePath: rootScorePath, scoreXML: scoreXML,
                                  packageEntries: entries, previewAssets: previewAssets,
                                  thumbnailData: thumbnailData(from: previewAssets))
    }
}

