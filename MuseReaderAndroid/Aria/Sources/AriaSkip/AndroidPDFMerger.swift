// Joins the engine's score PDFs into one, with a bookmark per score: what PDFKit does for
// the iOS setlist share (SetlistShareExporter.writeCombinedPDF). Android has no API that
// merges PDFs without rasterizing them.
//
// It handles PDFs with a classic xref table, which is what the engine writes (Qt's PDF
// writer): each page is copied with everything it references, objects are renumbered,
// and a new page tree, outline and catalog are written.

import Foundation

enum AndroidPDFMergeError: Error {
    case unreadable(String)
}

enum AndroidPDFMerger {
    struct Source {
        let title: String
        let data: Data
    }

    static func merge(_ sources: [Source]) throws -> Data {
        var writer = Writer()
        let pagesNumber = writer.reserve()
        let outlinesNumber = writer.reserve()
        var bookmarks: [(title: String, page: Int, top: Double)] = []
        var allPages: [Int] = []

        for source in sources {
            let document = try Document(source.data)
            let pages = try document.pageObjectNumbers()
            guard !pages.isEmpty else { continue }

            // Everything the pages use, without following /Parent back into the old tree.
            var renumbered: [Int: Int] = [:]
            var pending = pages
            var order: [Int] = []
            while let number = pending.popLast() {
                guard renumbered[number] == nil, document.objects[number] != nil else { continue }
                renumbered[number] = writer.reserve()
                order.append(number)
                for reference in document.references(in: number) where renumbered[reference] == nil {
                    pending.append(reference)
                }
            }
            for number in order {
                let isPage = pages.contains(number)
                writer.set(renumbered[number]!, document.rewritten(number, renumbering: renumbered,
                                                                   parent: isPage ? pagesNumber : nil))
            }
            let firstPage = renumbered[pages[0]]!
            bookmarks.append((source.title, firstPage, document.pageTop(pages[0])))
            allPages += pages.map { renumbered[$0]! }
        }

        guard !allPages.isEmpty else {
            throw AndroidPDFMergeError.unreadable("no pages")
        }

        let kids = allPages.map { "\($0) 0 R" }.joined(separator: " ")
        writer.set(pagesNumber, ascii("<< /Type /Pages /Kids [\(kids)] /Count \(allPages.count) >>"))

        let bookmarkNumbers = bookmarks.map { _ in writer.reserve() }
        for (index, bookmark) in bookmarks.enumerated() {
            var dictionary = "<< /Title \(textString(bookmark.title)) /Parent \(outlinesNumber) 0 R"
            dictionary += " /Dest [\(bookmark.page) 0 R /XYZ 0 \(bookmark.top) null]"
            if index > 0 { dictionary += " /Prev \(bookmarkNumbers[index - 1]) 0 R" }
            if index + 1 < bookmarks.count { dictionary += " /Next \(bookmarkNumbers[index + 1]) 0 R" }
            dictionary += " >>"
            writer.set(bookmarkNumbers[index], ascii(dictionary))
        }
        if let first = bookmarkNumbers.first, let last = bookmarkNumbers.last {
            writer.set(outlinesNumber, ascii("<< /Type /Outlines /First \(first) 0 R /Last \(last) 0 R /Count \(bookmarkNumbers.count) >>"))
        } else {
            writer.set(outlinesNumber, ascii("<< /Type /Outlines /Count 0 >>"))
        }

        let catalogNumber = writer.reserve()
        writer.set(catalogNumber, ascii("<< /Type /Catalog /Pages \(pagesNumber) 0 R /Outlines \(outlinesNumber) 0 R >>"))
        return writer.data(root: catalogNumber)
    }

    /// A PDF text string: UTF-16BE with a byte-order mark, as hex.
    private static func textString(_ text: String) -> String {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var hex = "FEFF"
        for unit in (title.isEmpty ? "Aria Score" : title).utf16 {
            hex += String(format: "%04X", unit)
        }
        return "<\(hex)>"
    }

    private static func ascii(_ text: String) -> [UInt8] {
        Array(text.utf8)
    }

    // MARK: - Reading

    private struct Document {
        let bytes: [UInt8]
        /// Object number to its "N G obj ... endobj" bytes.
        var objects: [Int: ArraySlice<UInt8>] = [:]
        let rootNumber: Int

        init(_ data: Data) throws {
            bytes = [UInt8](data)
            guard let startxref = Self.lastRange(of: Array("startxref".utf8), in: bytes) else {
                throw AndroidPDFMergeError.unreadable("no startxref")
            }
            var cursor = startxref.upperBound
            guard let xrefOffset = Self.readInteger(bytes, &cursor), xrefOffset < bytes.count,
                  Self.matches(Array("xref".utf8), in: bytes, at: xrefOffset) else {
                throw AndroidPDFMergeError.unreadable("no classic xref table")
            }

            // Subsections of "first count" followed by "offset generation n|f" entries.
            var offsets: [(number: Int, offset: Int)] = []
            cursor = xrefOffset + 4
            while true {
                let save = cursor
                guard let first = Self.readInteger(bytes, &cursor), let count = Self.readInteger(bytes, &cursor) else {
                    cursor = save
                    break
                }
                for index in 0..<count {
                    guard let offset = Self.readInteger(bytes, &cursor), Self.readInteger(bytes, &cursor) != nil,
                          let flag = Self.readWord(bytes, &cursor) else {
                        throw AndroidPDFMergeError.unreadable("bad xref entry")
                    }
                    if flag == "n" {
                        offsets.append((first + index, offset))
                    }
                }
            }
            guard let trailer = Self.range(of: Array("trailer".utf8), in: bytes, from: cursor) else {
                throw AndroidPDFMergeError.unreadable("no trailer")
            }
            let trailerText = Self.latin1(bytes[trailer.upperBound..<startxref.lowerBound])
            guard let root = Self.reference(named: "Root", in: trailerText) else {
                throw AndroidPDFMergeError.unreadable("no root")
            }
            rootNumber = root

            let sorted = offsets.sorted { $0.offset < $1.offset }
            for (index, entry) in sorted.enumerated() {
                let end = index + 1 < sorted.count ? sorted[index + 1].offset : xrefOffset
                guard entry.offset < end, end <= bytes.count else { continue }
                objects[entry.number] = bytes[entry.offset..<end]
            }
        }

        /// The object's text before any stream data (where references can be).
        func dictionaryText(_ number: Int) -> String {
            guard let object = objects[number] else { return "" }
            return Self.latin1(object[..<streamStart(object)])
        }

        func pageObjectNumbers() throws -> [Int] {
            guard let pagesRoot = Self.reference(named: "Pages", in: dictionaryText(rootNumber)) else {
                throw AndroidPDFMergeError.unreadable("no page tree")
            }
            var pages: [Int] = []
            func walk(_ number: Int, depth: Int) {
                guard depth < 32 else { return }
                let text = dictionaryText(number)
                if text.contains("/Type /Pages") || text.contains("/Type/Pages") {
                    for kid in Self.kids(in: text) {
                        walk(kid, depth: depth + 1)
                    }
                } else if text.contains("/Type /Page") || text.contains("/Type/Page") {
                    pages.append(number)
                }
            }
            walk(pagesRoot, depth: 0)
            return pages
        }

        func references(in number: Int) -> [Int] {
            let text = Self.removingParent(dictionaryText(number))
            return Self.referenceNumbers(in: text)
        }

        /// The page's height (its MediaBox top), for the bookmark destination.
        func pageTop(_ number: Int) -> Double {
            let text = dictionaryText(number)
            guard let range = text.range(of: "/MediaBox") else { return 842 }
            let numbers = text[range.upperBound...].split(whereSeparator: { " [\n\r".contains($0) })
                .prefix(4).compactMap { Double($0.trimmingCharacters(in: CharacterSet(charactersIn: "]"))) }
            return numbers.count == 4 ? numbers[3] : 842
        }

        /// The object with its number and references renumbered, and a page's parent
        /// pointed at the new page tree.
        func rewritten(_ number: Int, renumbering: [Int: Int], parent: Int?) -> [UInt8] {
            guard let object = objects[number] else { return [] }
            let split = streamStart(object)
            var text = Self.latin1(object[..<split])
            // Header "N G obj" first, then the references. The old page tree isn't copied,
            // so a page's /Parent becomes null and then points at the new tree.
            if let header = text.range(of: #"^\s*\d+\s+\d+\s+obj"#, options: .regularExpression) {
                text.replaceSubrange(header, with: "\(renumbering[number]!) 0 obj")
            }
            text = Self.renumberingReferences(in: text, renumbering: renumbering)
            if let parent {
                text = text.replacingOccurrences(of: "/Parent null", with: "/Parent \(parent) 0 R")
            }
            return Array(text.data(using: .isoLatin1) ?? Data(text.utf8)) + Array(object[split...])
        }

        /// Where the stream data begins ("stream" after the dictionary), or the end.
        private func streamStart(_ object: ArraySlice<UInt8>) -> Int {
            let keyword = Array("stream".utf8)
            var index = object.startIndex
            while index + keyword.count <= object.endIndex {
                if object[index] == keyword[0], Array(object[index..<index + keyword.count]) == keyword,
                   index == object.startIndex || object[index - 1] != UInt8(ascii: "d") {
                    return index
                }
                index += 1
            }
            return object.endIndex
        }

        // MARK: Parsing helpers

        static func reference(named key: String, in text: String) -> Int? {
            guard let range = text.range(of: "/\(key)\\s+(\\d+)\\s+\\d+\\s+R", options: .regularExpression) else { return nil }
            return referenceNumbers(in: String(text[range])).first
        }

        static func kids(in text: String) -> [Int] {
            guard let start = text.range(of: "/Kids"), let open = text[start.upperBound...].firstIndex(of: "["),
                  let close = text[open...].firstIndex(of: "]") else { return [] }
            return referenceNumbers(in: String(text[open...close]))
        }

        static func referenceNumbers(in text: String) -> [Int] {
            guard let regex = try? NSRegularExpression(pattern: #"(\d+)\s+(\d+)\s+R\b"#) else { return [] }
            let range = NSRange(text.startIndex..., in: text)
            return regex.matches(in: text, range: range).compactMap { match in
                Range(match.range(at: 1), in: text).flatMap { Int(text[$0]) }
            }
        }

        static func renumberingReferences(in text: String, renumbering: [Int: Int]) -> String {
            guard let regex = try? NSRegularExpression(pattern: #"(\d+)\s+(\d+)\s+R\b"#) else { return text }
            var result = ""
            var last = text.startIndex
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let whole = Range(match.range, in: text), let numberRange = Range(match.range(at: 1), in: text),
                      let old = Int(text[numberRange]) else { continue }
                result += text[last..<whole.lowerBound]
                result += renumbering[old].map { "\($0) 0 R" } ?? "null"
                last = whole.upperBound
            }
            result += text[last...]
            return result
        }

        static func removingParent(_ text: String) -> String {
            text.replacingOccurrences(of: #"/Parent\s+\d+\s+\d+\s+R"#, with: "", options: .regularExpression)
        }

        /// PDF syntax is bytes; Latin-1 keeps every byte as one character.
        static func latin1(_ bytes: ArraySlice<UInt8>) -> String {
            String(bytes: bytes, encoding: .isoLatin1) ?? ""
        }

        static func readInteger(_ bytes: [UInt8], _ cursor: inout Int) -> Int? {
            skipWhitespace(bytes, &cursor)
            var value = 0
            var digits = 0
            while cursor < bytes.count, bytes[cursor] >= 48, bytes[cursor] <= 57 {
                value = value * 10 + Int(bytes[cursor] - 48)
                cursor += 1
                digits += 1
            }
            return digits > 0 ? value : nil
        }

        static func readWord(_ bytes: [UInt8], _ cursor: inout Int) -> String? {
            skipWhitespace(bytes, &cursor)
            let start = cursor
            while cursor < bytes.count, !isWhitespace(bytes[cursor]) { cursor += 1 }
            return cursor > start ? String(decoding: bytes[start..<cursor], as: UTF8.self) : nil
        }

        static func skipWhitespace(_ bytes: [UInt8], _ cursor: inout Int) {
            while cursor < bytes.count, isWhitespace(bytes[cursor]) { cursor += 1 }
        }

        static func isWhitespace(_ byte: UInt8) -> Bool {
            byte == 32 || byte == 10 || byte == 13 || byte == 9 || byte == 12 || byte == 0
        }

        static func matches(_ pattern: [UInt8], in bytes: [UInt8], at index: Int) -> Bool {
            index + pattern.count <= bytes.count && Array(bytes[index..<index + pattern.count]) == pattern
        }

        static func range(of pattern: [UInt8], in bytes: [UInt8], from start: Int) -> Range<Int>? {
            var index = start
            while index + pattern.count <= bytes.count {
                if matches(pattern, in: bytes, at: index) { return index..<index + pattern.count }
                index += 1
            }
            return nil
        }

        static func lastRange(of pattern: [UInt8], in bytes: [UInt8]) -> Range<Int>? {
            var index = bytes.count - pattern.count
            while index >= 0 {
                if matches(pattern, in: bytes, at: index) { return index..<index + pattern.count }
                index -= 1
            }
            return nil
        }
    }

    // MARK: - Writing

    private struct Writer {
        private var bodies: [Int: [UInt8]] = [:]
        private var nextNumber = 1

        mutating func reserve() -> Int {
            defer { nextNumber += 1 }
            return nextNumber
        }

        /// `body` is either a whole "N 0 obj ... endobj" (copied objects) or a dictionary.
        mutating func set(_ number: Int, _ body: [UInt8]) {
            bodies[number] = body
        }

        func data(root: Int) -> Data {
            var output = Array("%PDF-1.4\n%\u{E2}\u{E3}\u{CF}\u{D3}\n".utf8)
            var offsets: [Int] = Array(repeating: 0, count: nextNumber)
            for number in 1..<nextNumber {
                guard var body = bodies[number] else { continue }
                offsets[number] = output.count
                let text = String(decoding: body.prefix(24), as: UTF8.self)
                if !text.contains(" obj") {
                    body = Array("\(number) 0 obj\n".utf8) + body + Array("\nendobj\n".utf8)
                } else if body.last != 10 {
                    body.append(10)
                }
                output += body
            }
            let xrefOffset = output.count
            var xref = "xref\n0 \(nextNumber)\n0000000000 65535 f \n"
            for number in 1..<nextNumber {
                xref += offsets[number] > 0
                    ? String(format: "%010d 00000 n \n", offsets[number])
                    : "0000000000 65535 f \n"
            }
            xref += "trailer\n<< /Size \(nextNumber) /Root \(root) 0 R >>\nstartxref\n\(xrefOffset)\n%%EOF\n"
            output += Array(xref.utf8)
            return Data(output)
        }
    }
}
