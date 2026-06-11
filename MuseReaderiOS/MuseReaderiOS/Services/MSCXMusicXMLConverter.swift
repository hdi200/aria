//
//  MSCXMusicXMLConverter.swift
//  MuseReaderiOS
//
//  Created on 5/20/26.
//

import Foundation

struct MSCXMusicXMLConverter: Sendable {
    private let divisions = 480

    nonisolated init() {}

    nonisolated func convertToMusicXML(_ xml: String) -> String {
        if xml.range(of: #"<\s*score-partwise\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return xml
        }

        guard
            xml.range(of: #"<\s*museScore\b"#, options: [.regularExpression, .caseInsensitive]) != nil,
            let scoreBody = captureFirst(pattern: #"<Score\b[^>]*>(.*?)</Score>"#, in: xml)
        else {
            return xml
        }

        let scoreWithoutParts = removingBlocks(named: "Part", from: scoreBody)
        let staffBlocks = captureStaffBlocks(in: scoreWithoutParts)
        guard !staffBlocks.isEmpty else {
            return xml
        }

        let parts = makeParts(from: scoreBody, staffBlocks: staffBlocks)
        let title = cleaned(captureFirst(pattern: #"<metaTag\b[^>]*name="workTitle"[^>]*>(.*?)</metaTag>"#, in: scoreBody))
            ?? "Untitled Score"
        let composer = cleaned(captureFirst(pattern: #"<metaTag\b[^>]*name="composer"[^>]*>(.*?)</metaTag>"#, in: scoreBody))

        var output: [String] = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<score-partwise version="4.0">"#,
            "  <work>",
            "    <work-title>\(escaped(title))</work-title>",
            "  </work>"
        ]

        if let composer {
            output.append("  <identification>")
            output.append("    <creator type=\"composer\">\(escaped(composer))</creator>")
            output.append("  </identification>")
        }

        output.append("  <part-list>")
        for part in parts {
            output.append("    <score-part id=\"\(part.id)\">")
            output.append("      <part-name>\(escaped(part.name))</part-name>")
            output.append("    </score-part>")
        }
        output.append("  </part-list>")

        for part in parts {
            output.append("  <part id=\"\(part.id)\">")
            let measureCount = part.staffIDs.compactMap { staffBlocks[$0]?.measures.count }.max() ?? 0
            for index in 0..<measureCount {
                let sourceNumber = part.staffIDs.compactMap { staffBlocks[$0]?.measures[safe: index]?.number }.first ?? "\(index + 1)"
                output.append("    <measure number=\"\(escaped(sourceNumber))\">")
                if let firstMeasure = part.staffIDs.compactMap({ staffBlocks[$0]?.measures[safe: index] }).first {
                    output.append(contentsOf: attributesXML(for: firstMeasure.body, staffCount: part.staffIDs.count, force: index == 0).map { "      \($0)" })
                }

                var staffIndex = 0
                for staffID in part.staffIDs {
                    staffIndex += 1
                    guard let measure = staffBlocks[staffID]?.measures[safe: index] else {
                        continue
                    }
                    output.append(contentsOf: measureXML(from: measure.body, staffNumber: part.staffIDs.count > 1 ? staffIndex : nil).map { "      \($0)" })
                    if staffIndex < part.staffIDs.count {
                        output.append("      <backup>")
                        output.append("        <duration>\(measureDurationTicks(in: measure.body))</duration>")
                        output.append("      </backup>")
                    }
                }
                output.append("    </measure>")
            }
            output.append("  </part>")
        }

        output.append("</score-partwise>")
        return output.joined(separator: "\n")
    }

    private func makeParts(from scoreBody: String, staffBlocks: [String: StaffBlock]) -> [MusicXMLPart] {
        let partBlocks = captureGroups(pattern: #"<Part\b[^>]*>(.*?)</Part>"#, in: scoreBody)
        var claimedStaffIDs = Set<String>()
        var parts: [MusicXMLPart] = []

        for (index, block) in partBlocks.enumerated() {
            let staffIDs = captureGroups(pattern: #"<Staff\b[^>]*id="([^"]+)"[^>]*/?>"#, in: block)
                .filter { staffBlocks[$0] != nil }
            guard !staffIDs.isEmpty else {
                continue
            }

            claimedStaffIDs.formUnion(staffIDs)
            let name = cleaned(captureFirst(pattern: #"<trackName>\s*(.*?)\s*</trackName>"#, in: block))
                ?? cleaned(captureFirst(pattern: #"<longName>\s*(.*?)\s*</longName>"#, in: block))
                ?? "Part \(index + 1)"
            parts.append(MusicXMLPart(id: "P\(parts.count + 1)", name: name, staffIDs: staffIDs))
        }

        for staffID in staffBlocks.keys.sorted(by: numericSort) where !claimedStaffIDs.contains(staffID) {
            parts.append(MusicXMLPart(id: "P\(parts.count + 1)", name: "Staff \(staffID)", staffIDs: [staffID]))
        }

        return parts
    }

    private func captureStaffBlocks(in scoreBody: String) -> [String: StaffBlock] {
        guard let regex = try? NSRegularExpression(pattern: #"<Staff\b([^>]*)>(.*?)</Staff>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return [:]
        }

        var blocks: [String: StaffBlock] = [:]
        for match in regex.matches(in: scoreBody, range: NSRange(scoreBody.startIndex..., in: scoreBody)) {
            guard
                let attrsRange = Range(match.range(at: 1), in: scoreBody),
                let bodyRange = Range(match.range(at: 2), in: scoreBody),
                let id = captureFirst(pattern: #"id="([^"]+)""#, in: String(scoreBody[attrsRange]))
            else {
                continue
            }

            let body = String(scoreBody[bodyRange])
            blocks[id] = StaffBlock(id: id, measures: captureMeasures(in: body))
        }

        return blocks
    }

    private func captureMeasures(in staffBody: String) -> [MSCXMeasure] {
        guard let regex = try? NSRegularExpression(pattern: #"<Measure\b([^>]*)>(.*?)</Measure>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        return regex.matches(in: staffBody, range: NSRange(staffBody.startIndex..., in: staffBody)).enumerated().compactMap { offset, match in
            guard
                let attrsRange = Range(match.range(at: 1), in: staffBody),
                let bodyRange = Range(match.range(at: 2), in: staffBody)
            else {
                return nil
            }

            let attrs = String(staffBody[attrsRange])
            let number = captureFirst(pattern: #"number="([^"]+)""#, in: attrs) ?? "\(offset + 1)"
            return MSCXMeasure(number: number, body: String(staffBody[bodyRange]))
        }
    }

    private func attributesXML(for measureBody: String, staffCount: Int, force: Bool) -> [String] {
        guard force
            || measureBody.range(of: "<TimeSig", options: .caseInsensitive) != nil
            || measureBody.range(of: "<KeySig", options: .caseInsensitive) != nil
            || measureBody.range(of: "<Clef", options: .caseInsensitive) != nil
        else {
            return []
        }

        let (beats, beatType) = timeSignature(in: measureBody)
        var lines = [
            "<attributes>",
            "  <divisions>\(divisions)</divisions>",
            "  <key>",
            "    <fifths>\(keyFifths(in: measureBody))</fifths>",
            "  </key>",
            "  <time>",
            "    <beats>\(beats)</beats>",
            "    <beat-type>\(beatType)</beat-type>",
            "  </time>"
        ]

        if staffCount > 1 {
            lines.append("  <staves>\(staffCount)</staves>")
        }

        for staff in 1...max(staffCount, 1) {
            let clef = clefSignAndLine(in: measureBody, fallbackStaffNumber: staff)
            lines.append("  <clef\(staffCount > 1 ? " number=\"\(staff)\"" : "")>")
            lines.append("    <sign>\(clef.sign)</sign>")
            lines.append("    <line>\(clef.line)</line>")
            lines.append("  </clef>")
        }

        lines.append("</attributes>")
        return lines
    }

    private func measureXML(from measureBody: String, staffNumber: Int?) -> [String] {
        var events = tokenBlocks(in: measureBody)
        if events.isEmpty {
            events = [MSCXToken(name: "Rest", body: "<durationType>measure</durationType>", offset: measureBody.startIndex)]
        }

        var lines: [String] = []
        var cursor = 0
        for token in events {
            let location = intElement("location", in: token.body) ?? intElement("tick", in: token.body)
            if let location, location > cursor {
                lines.append(contentsOf: forwardXML(duration: location - cursor))
                cursor = location
            }

            let duration = durationTicks(for: token)
            if token.name.caseInsensitiveCompare("Rest") == .orderedSame {
                lines.append(contentsOf: restXML(duration: duration, tokenBody: token.body, staffNumber: staffNumber))
            } else {
                lines.append(contentsOf: chordXML(duration: duration, tokenBody: token.body, staffNumber: staffNumber))
            }
            cursor += duration
        }

        let targetDuration = measureDurationTicks(in: measureBody)
        if cursor < targetDuration {
            lines.append(contentsOf: forwardXML(duration: targetDuration - cursor))
        }

        return lines
    }

    private func chordXML(duration: Int, tokenBody: String, staffNumber: Int?) -> [String] {
        let noteBlocks = captureGroups(pattern: #"<Note\b[^>]*>(.*?)</Note>"#, in: tokenBody)
        let notes = noteBlocks.isEmpty ? [tokenBody] : noteBlocks
        var lines: [String] = []

        for (index, noteBody) in notes.enumerated() {
            lines.append("<note>")
            if index > 0 {
                lines.append("  <chord/>")
            }
            let pitch = midiPitch(from: noteBody) ?? ("C", 0, 4)
            lines.append("  <pitch>")
            lines.append("    <step>\(pitch.step)</step>")
            if pitch.alter != 0 {
                lines.append("    <alter>\(pitch.alter)</alter>")
            }
            lines.append("    <octave>\(pitch.octave)</octave>")
            lines.append("  </pitch>")
            lines.append("  <duration>\(duration)</duration>")
            lines.append("  <voice>\(voice(in: tokenBody))</voice>")
            lines.append("  <type>\(musicXMLType(for: tokenBody))</type>")
            for _ in 0..<dotCount(in: tokenBody) {
                lines.append("  <dot/>")
            }
            if let accidental = accidental(in: noteBody) {
                lines.append("  <accidental>\(accidental)</accidental>")
            }
            if let staffNumber {
                lines.append("  <staff>\(staffNumber)</staff>")
            }
            lines.append(contentsOf: noteNotations(in: tokenBody).map { "  \($0)" })
            lines.append("</note>")
        }

        return lines
    }

    private func restXML(duration: Int, tokenBody: String, staffNumber: Int?) -> [String] {
        var lines = [
            "<note>",
            "  <rest/>",
            "  <duration>\(duration)</duration>",
            "  <voice>\(voice(in: tokenBody))</voice>",
            "  <type>\(musicXMLType(for: tokenBody))</type>"
        ]
        for _ in 0..<dotCount(in: tokenBody) {
            lines.append("  <dot/>")
        }
        if let staffNumber {
            lines.append("  <staff>\(staffNumber)</staff>")
        }
        lines.append("</note>")
        return lines
    }

    private func forwardXML(duration: Int) -> [String] {
        ["<forward>", "  <duration>\(duration)</duration>", "</forward>"]
    }

    private func tokenBlocks(in measureBody: String) -> [MSCXToken] {
        guard let regex = try? NSRegularExpression(pattern: #"<(Chord|Rest)\b[^>]*>(.*?)</\1>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        return regex.matches(in: measureBody, range: NSRange(measureBody.startIndex..., in: measureBody)).compactMap { match in
            guard
                let nameRange = Range(match.range(at: 1), in: measureBody),
                let bodyRange = Range(match.range(at: 2), in: measureBody)
            else {
                return nil
            }
            return MSCXToken(name: String(measureBody[nameRange]), body: String(measureBody[bodyRange]), offset: nameRange.lowerBound)
        }
    }

    private func durationTicks(for token: MSCXToken) -> Int {
        if token.body.range(of: #"<durationType>\s*measure\s*</durationType>"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return measureDurationTicks(in: token.body)
        }

        let base: Int
        switch cleaned(captureFirst(pattern: #"<durationType>\s*(.*?)\s*</durationType>"#, in: token.body))?.lowercased() {
        case "longa":
            base = divisions * 16
        case "breve":
            base = divisions * 8
        case "whole":
            base = divisions * 4
        case "half":
            base = divisions * 2
        case "eighth":
            base = divisions / 2
        case "16th", "sixteenth":
            base = divisions / 4
        case "32nd":
            base = divisions / 8
        default:
            base = divisions
        }

        var duration = base
        var dotValue = base / 2
        for _ in 0..<dotCount(in: token.body) {
            duration += dotValue
            dotValue /= 2
        }
        return duration
    }

    private func measureDurationTicks(in body: String) -> Int {
        let (beats, beatType) = timeSignature(in: body)
        return max(beats, 1) * divisions * 4 / max(beatType, 1)
    }

    private func timeSignature(in body: String) -> (Int, Int) {
        guard let timeSig = captureFirst(pattern: #"<TimeSig\b[^>]*>(.*?)</TimeSig>"#, in: body) else {
            return (4, 4)
        }

        if let sig = cleaned(captureFirst(pattern: #"<sigN>\s*(\d+)\s*</sigN>\s*<sigD>\s*(\d+)\s*</sigD>"#, in: timeSig)) {
            let parts = sig.split(separator: " ").compactMap { Int($0) }
            if parts.count == 2 {
                return (parts[0], parts[1])
            }
        }

        let beats = Int(cleaned(captureFirst(pattern: #"<sigN>\s*(\d+)\s*</sigN>"#, in: timeSig)) ?? "") ?? 4
        let beatType = Int(cleaned(captureFirst(pattern: #"<sigD>\s*(\d+)\s*</sigD>"#, in: timeSig)) ?? "") ?? 4
        return (beats, beatType)
    }

    private func keyFifths(in body: String) -> Int {
        Int(cleaned(captureFirst(pattern: #"<accidental>\s*(-?\d+)\s*</accidental>"#, in: body)) ?? "") ?? 0
    }

    private func clefSignAndLine(in body: String, fallbackStaffNumber: Int) -> (sign: String, line: Int) {
        let clefBlock = captureFirst(pattern: #"<Clef\b[^>]*>(.*?)</Clef>"#, in: body) ?? ""
        let type = cleaned(captureFirst(pattern: #"<concertClefType>\s*(.*?)\s*</concertClefType>"#, in: clefBlock))?.uppercased()
        if type?.contains("F") == true || (type == nil && fallbackStaffNumber == 2) {
            return ("F", 4)
        }
        if type?.contains("C") == true {
            return ("C", 3)
        }
        return ("G", 2)
    }

    private func musicXMLType(for body: String) -> String {
        switch cleaned(captureFirst(pattern: #"<durationType>\s*(.*?)\s*</durationType>"#, in: body))?.lowercased() {
        case "longa":
            return "long"
        case "breve":
            return "breve"
        case "whole", "measure":
            return "whole"
        case "half":
            return "half"
        case "eighth":
            return "eighth"
        case "16th", "sixteenth":
            return "16th"
        case "32nd":
            return "32nd"
        default:
            return "quarter"
        }
    }

    private func dotCount(in body: String) -> Int {
        Int(cleaned(captureFirst(pattern: #"<dots>\s*(\d+)\s*</dots>"#, in: body)) ?? "") ?? 0
    }

    private func voice(in body: String) -> Int {
        max(Int(cleaned(captureFirst(pattern: #"<voice>\s*(\d+)\s*</voice>"#, in: body)) ?? "") ?? 1, 1)
    }

    private func midiPitch(from noteBody: String) -> (step: String, alter: Int, octave: Int)? {
        guard let pitch = Int(cleaned(captureFirst(pattern: #"<pitch>\s*(-?\d+)\s*</pitch>"#, in: noteBody)) ?? "") else {
            return nil
        }

        let pitchClass = ((pitch % 12) + 12) % 12
        let octave = pitch / 12 - 1
        switch pitchClass {
        case 0: return ("C", 0, octave)
        case 1: return ("C", 1, octave)
        case 2: return ("D", 0, octave)
        case 3: return ("D", 1, octave)
        case 4: return ("E", 0, octave)
        case 5: return ("F", 0, octave)
        case 6: return ("F", 1, octave)
        case 7: return ("G", 0, octave)
        case 8: return ("G", 1, octave)
        case 9: return ("A", 0, octave)
        case 10: return ("A", 1, octave)
        default: return ("B", 0, octave)
        }
    }

    private func accidental(in noteBody: String) -> String? {
        guard let accidental = Int(cleaned(captureFirst(pattern: #"<Accidental\b[^>]*>.*?<subtype>\s*(-?\d+)\s*</subtype>.*?</Accidental>"#, in: noteBody)) ?? "") else {
            return nil
        }
        switch accidental {
        case -1:
            return "flat"
        case 0:
            return "natural"
        case 1:
            return "sharp"
        default:
            return nil
        }
    }

    private func noteNotations(in body: String) -> [String] {
        var notations: [String] = []
        for tieType in captureGroups(pattern: #"<Tie\b[^>]*type="([^"]+)"[^>]*/?>"#, in: body) {
            notations.append("<tied type=\"\(escaped(tieType))\"/>")
        }
        for slurType in captureGroups(pattern: #"<Slur\b[^>]*type="([^"]+)"[^>]*/?>"#, in: body) {
            notations.append("<slur type=\"\(escaped(slurType))\"/>")
        }
        guard !notations.isEmpty else {
            return []
        }
        return ["<notations>"] + notations.map { "  \($0)" } + ["</notations>"]
    }

    private func removingBlocks(named name: String, from source: String) -> String {
        source.replacingOccurrences(
            of: #"<\#(name)\b[^>]*>.*?</\#(name)>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    private func captureFirst(pattern: String, in source: String) -> String? {
        captureGroups(pattern: pattern, in: source).first
    }

    private func captureGroups(pattern: String, in source: String) -> [String] {
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

    private func intElement(_ name: String, in body: String) -> Int? {
        Int(cleaned(captureFirst(pattern: #"<\#(name)>\s*(-?\d+)\s*</\#(name)>"#, in: body)) ?? "")
    }

    private func cleaned(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let stripped = value
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? nil : stripped
    }

    private func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func numericSort(_ lhs: String, _ rhs: String) -> Bool {
        if let left = Int(lhs), let right = Int(rhs) {
            return left < right
        }
        return lhs < rhs
    }
}

private struct StaffBlock {
    let id: String
    let measures: [MSCXMeasure]
}

private struct MSCXMeasure {
    let number: String
    let body: String
}

private struct MusicXMLPart {
    let id: String
    let name: String
    let staffIDs: [String]
}

private struct MSCXToken {
    let name: String
    let body: String
    let offset: String.Index
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
