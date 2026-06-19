//
//  ScoreDocumentService.swift
//  MuseReaderiOS
//
//

import Foundation

protocol ScoreDocumentService: Sendable {
    nonisolated func inspectDocument(at url: URL) throws -> ScoreDocument
}

struct ScoreDocumentInspection: Sendable {
    let document: ScoreDocument
    let embeddedPreviews: [ScorePackagePreviewAsset]
}

enum ScoreDocumentServiceError: LocalizedError {
    case invalidFormat(String)
    case bridgeFailure(String)

    var errorDescription: String? {
        switch self {
        case .invalidFormat(let pathExtension):
            return "The file extension \(pathExtension) is not supported yet."
        case .bridgeFailure(let message):
            return message
        }
    }
}

struct MuseScoreDocumentService: ScoreDocumentService {
    private let parser = ScoreMetadataParser()

    nonisolated init() {}

    nonisolated func inspectDocument(at url: URL) throws -> ScoreDocument {
        try inspectPackage(at: url).document
    }

    nonisolated func inspectPackage(at url: URL) throws -> ScoreDocumentInspection {
        let bridge = MuseScorePackageBridge()
        let payload = try bridge.loadDocument(at: url)

        let metadata = parser.parse(xml: payload.scoreXML)
        let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let fileReference = url.standardizedFileURL.path
        let format = scoreFileFormat(for: url)
        let embeddedPreviews = payload.previewAssets.map {
            ScorePackagePreviewAsset(path: $0.path, imageData: $0.imageData)
        }
        let document = ScoreDocument(
            id: fileReference,
            fileReference: fileReference,
            url: url,
            displayName: url.lastPathComponent,
            format: format,
            title: metadata.title,
            subtitle: metadata.subtitle,
            composer: metadata.composer,
            lyricist: metadata.lyricist,
            arranger: metadata.arranger,
            rootFilePath: payload.rootFilePath,
            museScoreVersion: metadata.museScoreVersion,
            partCount: metadata.partsCount,
            parts: metadata.parts,
            packageEntries: payload.packageEntries,
            previewImageData: embeddedPreviews.first?.imageData ?? payload.thumbnailData,
            scoreExcerpt: makeScoreExcerpt(from: payload.scoreXML),
            fileSize: resourceValues?.fileSize.map(Int64.init),
            modificationDate: resourceValues?.contentModificationDate
        )

        return ScoreDocumentInspection(
            document: document,
            embeddedPreviews: embeddedPreviews
        )
    }

    nonisolated private func makeScoreExcerpt(from xml: String) -> String {
        let excerpt = xml
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(10)
            .joined(separator: "\n")

        return excerpt.isEmpty ? "<empty score>" : excerpt
    }

    nonisolated private func scoreFileFormat(for url: URL) -> ScoreFileFormat {
        switch url.pathExtension.lowercased() {
        case "mscx":
            return .mscx
        case "mscz":
            return .mscz
        case "mxl":
            return .mxl
        case "musicxml", "xml":
            return .musicxml
        default:
            return .mscz
        }
    }
}

struct ParsedScoreMetadata {
    let title: String?
    let subtitle: String?
    let composer: String?
    let lyricist: String?
    let arranger: String?
    let partsCount: Int
    let parts: [ScorePart]
    let museScoreVersion: String?
}

struct ScoreMetadataParser {
    nonisolated func parse(xml: String) -> ParsedScoreMetadata {
        let masterScoreXML = masterScoreXML(in: xml)
        let styled = styledMetadata(in: masterScoreXML)

        let parts = parts(in: xml, masterScoreXML: masterScoreXML)

        return ParsedScoreMetadata(
            title: styled.title
                ?? metaTag(named: "workTitle", in: masterScoreXML)
                ?? metaTag(named: "workTitle", in: xml)
                ?? element(named: "work-title", in: xml)
                ?? element(named: "movement-title", in: xml),
            subtitle: styled.subtitle ?? metaTag(named: "subtitle", in: masterScoreXML) ?? metaTag(named: "subtitle", in: xml),
            composer: styled.composer ?? metaTag(named: "composer", in: masterScoreXML) ?? metaTag(named: "composer", in: xml) ?? musicXMLCreator(type: "composer", in: xml),
            lyricist: styled.lyricist ?? metaTag(named: "lyricist", in: masterScoreXML) ?? metaTag(named: "lyricist", in: xml) ?? musicXMLCreator(type: "lyricist", in: xml),
            arranger: metaTag(named: "arranger", in: masterScoreXML) ?? metaTag(named: "arranger", in: xml) ?? musicXMLCreator(type: "arranger", in: xml),
            partsCount: parts.count,
            parts: parts,
            museScoreVersion: captureFirstGroup(pattern: #"<museScore\b[^>]*version="([^"]+)""#, in: xml)
        )
    }

    nonisolated private func parts(in xml: String, masterScoreXML: String) -> [ScorePart] {
        let musicXMLParts = musicXMLParts(in: xml)
        if !musicXMLParts.isEmpty {
            return musicXMLParts
        }

        let blocks = captureGroups(pattern: #"<Part\b[^>]*>(.*?)</Part>"#, in: masterScoreXML)
        return blocks.enumerated().map { index, block in
            let name = cleaned(captureFirstGroup(pattern: #"<trackName>\s*(.*?)\s*</trackName>"#, in: block))
                ?? cleaned(captureFirstGroup(pattern: #"<longName>\s*(.*?)\s*</longName>"#, in: block))
                ?? cleaned(captureFirstGroup(pattern: #"<shortName>\s*(.*?)\s*</shortName>"#, in: block))
                ?? "Part \(index + 1)"

            return ScorePart(
                id: "part-\(index)",
                index: index,
                name: name,
                clef: ScorePartClef.inferred(for: name)
            )
        }
    }

    nonisolated private func musicXMLParts(in xml: String) -> [ScorePart] {
        guard xml.range(of: #"<\s*part-list\b"#, options: [.regularExpression, .caseInsensitive]) != nil else {
            return []
        }

        let blocks = captureGroups(pattern: #"<score-part\b[^>]*>(.*?)</score-part>"#, in: xml)
        return blocks.enumerated().map { index, block in
            let name = cleaned(captureFirstGroup(pattern: #"<part-name\b[^>]*>\s*(.*?)\s*</part-name>"#, in: block))
                ?? cleaned(captureFirstGroup(pattern: #"<part-abbreviation\b[^>]*>\s*(.*?)\s*</part-abbreviation>"#, in: block))
                ?? "Part \(index + 1)"

            return ScorePart(
                id: "part-\(index)",
                index: index,
                name: name,
                clef: ScorePartClef.inferred(for: name)
            )
        }
    }

    nonisolated private func metaTag(named tagName: String, in xml: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: tagName)
        let pattern = #"<metaTag\b[^>]*name=""# + escapedName + #""[^>]*>(.*?)</metaTag>"#
        return cleaned(captureFirstGroup(pattern: pattern, in: xml))
    }

    nonisolated private func element(named name: String, in xml: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = #"<"# + escapedName + #"\b[^>]*>\s*(.*?)\s*</"# + escapedName + #">"#
        return cleaned(captureFirstGroup(pattern: pattern, in: xml))
    }

    nonisolated private func musicXMLCreator(type: String, in xml: String) -> String? {
        let escapedType = NSRegularExpression.escapedPattern(for: type)
        let pattern = #"<creator\b[^>]*type=""# + escapedType + #""[^>]*>\s*(.*?)\s*</creator>"#
        return cleaned(captureFirstGroup(pattern: pattern, in: xml))
    }

    nonisolated private func styledMetadata(in xml: String) -> StyledMetadata {
        var metadata = StyledMetadata()
        let textBlocks = captureGroups(pattern: #"<Text\b[^>]*>(.*?)</Text>"#, in: xml)

        for block in textBlocks {
            guard
                let styleValue = textStyleValue(in: block),
                let payload = cleaned(
                    captureFirstGroup(pattern: #"<text>(.*?)</text>"#, in: block)
                    ?? captureFirstGroup(pattern: #"<html-data>(.*?)</html-data>"#, in: block)
                )
            else {
                continue
            }

            switch styleValue {
            case "title", "2":
                metadata.title = metadata.title ?? payload
            case "subtitle", "sub-title", "3":
                metadata.subtitle = metadata.subtitle ?? payload
            case "composer", "4":
                metadata.composer = metadata.composer ?? payload
            case "lyricist", "poet", "5":
                metadata.lyricist = metadata.lyricist ?? payload
            default:
                continue
            }
        }

        return metadata
    }

    nonisolated private func masterScoreXML(in xml: String) -> String {
        let scoreBlocks = captureGroups(pattern: #"<Score\b[^>]*>(.*?)</Score>"#, in: xml)
        guard !scoreBlocks.isEmpty else {
            return xml
        }

        return scoreBlocks.max { lhs, rhs in
            partCount(in: lhs) < partCount(in: rhs)
        } ?? scoreBlocks[0]
    }

    nonisolated private func partCount(in xml: String) -> Int {
        countMatches(pattern: #"<Part\b"#, in: xml)
    }

    nonisolated private func textStyleValue(in block: String) -> String? {
        cleaned(captureFirstGroup(pattern: #"<style>(.*?)</style>"#, in: block)
            ?? captureFirstGroup(pattern: #"<subStyle>(.*?)</subStyle>"#, in: block)
            ?? captureFirstGroup(pattern: #"<textStyle>(.*?)</textStyle>"#, in: block))?
            .lowercased()
    }

    nonisolated private func cleaned(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let decoded = decodeHTMLEntities(in: value)
        let withoutCDATA = decoded
            .replacingOccurrences(of: #"<!\[CDATA\[(.*?)\]\]>"#, with: "$1", options: .regularExpression)
        let stripped = withoutCDATA
            .replacingOccurrences(of: #"<br\s*/?>"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        let collapsed = stripped
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return collapsed.isEmpty ? nil : collapsed
    }

    nonisolated private func decodeHTMLEntities(in value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
    }

    nonisolated private func captureFirstGroup(pattern: String, in source: String) -> String? {
        guard
            let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
            let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
            match.numberOfRanges > 1,
            let range = Range(match.range(at: 1), in: source)
        else {
            return nil
        }

        return String(source[range])
    }

    nonisolated private func captureGroups(pattern: String, in source: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        return regex.matches(in: source, range: NSRange(source.startIndex..., in: source)).compactMap { match in
            guard match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: source) else {
                return nil
            }

            return String(source[range])
        }
    }

    nonisolated private func countMatches(pattern: String, in source: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return 0
        }

        return regex.numberOfMatches(in: source, range: NSRange(source.startIndex..., in: source))
    }
}

private struct StyledMetadata {
    var title: String?
    var subtitle: String?
    var composer: String?
    var lyricist: String?

    nonisolated init() {}
}
