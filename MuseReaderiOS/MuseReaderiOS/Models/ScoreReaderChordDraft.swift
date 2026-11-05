//
//  ScoreReaderChordDraft.swift
//  MuseReaderiOS
//
//  The chord keyboard's keys and what each does to the chord being typed. The keyboard is
//  drawn by ScoreReaderChordKeyboardView (UIKit, iOS) and AndroidTextInputFields.swift.
//

import Foundation

/// Button-based chord composition. Preserve imported spellings until the user changes
/// that component; MuseScore still parses and engraves the resulting chord symbol.
struct ScoreReaderChordBuilderDraft {
    private(set) var text: String
    private(set) var editsBass = false

    init(text: String = "") { self.text = text }

    private var root: String { prefix(in: text, pattern: "^[A-G](?:bb|##|b|#|♭|♯)?") }
    private var suffix: String { String(text.dropFirst(root.count)) }
    private var quality: String { prefix(in: suffix, pattern: "^(?:maj|Maj|MAJ|min|dim|aug|sus|ø|°|Δ|M|m|\\+|-)") }
    private var bass: String { text.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? "" }

    var hasChord: Bool { !root.isEmpty }
    var isComplete: Bool {
        let chord = text.split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
        return hasChord && !text.hasSuffix("/") && !chord.hasSuffix("add") && !chord.hasSuffix("no")
    }
    var selectedRoot: String { String((editsBass ? bass : root).prefix(1)) }
    /// No written quality is a major chord, except before 7, 9, 11 or 13, where it is
    /// dominant (C7) and no quality key is lit.
    var selectedQuality: String {
        switch quality {
        case "": return ["7", "9", "11", "13"].contains(selectedExtension) ? "" : "maj"
        case "maj", "Maj", "MAJ", "Δ", "M": return "maj"
        case "min", "m", "-": return "min"
        case "aug", "+": return "aug"
        default: return quality
        }
    }
    var selectedExtension: String { prefix(in: String(suffix.dropFirst(quality.count)), pattern: "^[0-9]+") }

    func hasAccidental(_ accidental: String) -> Bool {
        (editsBass ? bass : root).dropFirst().replacingOccurrences(of: "♭", with: "b")
            .replacingOccurrences(of: "♯", with: "#") == accidental
    }

    mutating func chooseRoot(_ note: String) {
        guard ScoreReaderChordDraft.naturalNotes.contains(note) else { return }
        if editsBass, let slash = text.lastIndex(of: "/") {
            let accidental = prefix(in: bass, pattern: "^[A-G](?:bb|##|b|#|♭|♯)?").dropFirst()
            text = String(text[...slash]) + note + accidental
        } else if root.isEmpty {
            text = note
        } else {
            text = note + root.dropFirst() + suffix
        }
    }

    /// Tapping the lit quality again clears it, which is how Cmaj7 or Cm7 becomes C7.
    /// "maj" on a plain triad is already implied, so it isn't written out.
    mutating func chooseQuality(_ token: String) {
        guard hasChord else { return }
        editsBass = false
        if selectedQuality == token {
            text = root + suffix.dropFirst(quality.count)
            return
        }
        text = root + token + suffix.dropFirst(quality.count)
    }

    mutating func chooseExtension(_ degree: String) {
        guard hasChord else { return }
        let pieces = text.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        var chord = String(pieces[0])
        // add/no await a degree; otherwise replace or toggle the principal extension.
        if chord.hasSuffix("add") || chord.hasSuffix("no") {
            chord += degree
        } else {
            let currentDegree = selectedExtension
            let newDegree = degree == currentDegree ? "" : degree
            let tail = chord.dropFirst(root.count + quality.count + currentDegree.count)
            if newDegree.isEmpty, quality.isEmpty, tail.hasPrefix("b5") || tail.hasPrefix("#5") {
                // Keep an altered fifth distinct from a root accidental: C7b5 becomes C(b5).
                chord = root + "(" + tail.prefix(2) + ")" + tail.dropFirst(2)
            } else {
                chord = root + quality + newDegree + tail
            }
        }
        text = chord + (pieces.count == 2 ? "/" + pieces[1] : "")
        editsBass = false
    }

    func hasModifier(_ token: String) -> Bool {
        let chord = text.split(separator: "/").first
        return chord?.hasSuffix(token) == true || chord?.hasSuffix("(" + token + ")") == true
    }

    mutating func pressModifier(_ token: String) {
        guard hasChord else { return }
        if token == "/" {
            if !text.contains("/") { text += "/" }
            editsBass.toggle()
        } else if token == "b" || token == "#" {
            let note = editsBass ? bass : root
            guard !note.isEmpty else { return }
            let replacement = String(note.prefix(1)) + (hasAccidental(token) ? "" : token)
            if editsBass, let slash = text.lastIndex(of: "/") {
                text = String(text[...slash]) + replacement
            } else {
                text = replacement + suffix
            }
        } else {
            // Alterations belong before a slash bass.
            let pieces = text.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
            var chord = String(pieces[0])
            if chord.hasSuffix("(" + token + ")") {
                chord.removeLast(token.count + 2)
            } else if chord.hasSuffix(token) {
                chord.removeLast(token.count)
            } else if chord == root, token == "b5" || token == "#5" {
                chord += "(" + token + ")"
            } else {
                chord += token
            }
            text = chord + (pieces.count == 2 ? "/" + pieces[1] : "")
            editsBass = false
        }
    }

    mutating func clearSlashBass() {
        guard let slash = text.firstIndex(of: "/") else { return }
        text.removeSubrange(slash...)
        editsBass = false
    }

    mutating func backspace() {
        guard !text.isEmpty else { return }
        text.removeLast()
        editsBass = text.hasSuffix("/")
    }

    private func prefix(in value: String, pattern: String) -> String {
        guard let range = value.range(of: pattern, options: .regularExpression) else { return "" }
        return String(value[range])
    }
}

struct ScoreReaderChordDraft {
    static let naturalNotes = ["C", "D", "E", "F", "G", "A", "B"]
    static let rootRowKeys = ["C", "D", "E", "F", "G", "A", "B", "♭", "#"]
    static let qualities = ["maj", "min", "°", "ø", "+", "sus"]
    static let extensions = ["2", "3", "4", "5", "6", "7", "8", "9", "11", "13"]
    static let modifiers = ["add", "no", "♭5", "#5", "/", "⌫"]
    static let insertKey = "insert/next"
    static let doneKey = "done"

    /// What the keyboard does after a key, besides changing the text.
    enum Effect {
        case none
        /// Insert the chord and move to the next beat (the field's space action), then
        /// start a new chord.
        case advance
        /// Insert any chord typed and close the keyboard.
        case done
    }

    private(set) var text: String

    init(text: String = "") {
        self.text = text
    }

    /// `advancesOnInsert`: the field has a space action; without one, insert/next ends the
    /// chord with a space.
    mutating func press(_ key: String, advancesOnInsert: Bool) -> Effect {
        switch key {
        case Self.insertKey:
            guard !advancesOnInsert else { return .advance }
            let chord = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !chord.isEmpty {
                text = chord + " "
            }
        case Self.doneKey:
            return .done
        case "⌫":
            if !text.isEmpty {
                text.removeLast()
            }
        case "♭":
            text += "b"
        case "♭5":
            text += "b5"
        default:
            text += key
        }
        return .none
    }

    /// A long press on a natural root types its sharp.
    mutating func pressAndHold(root natural: String) {
        guard Self.naturalNotes.contains(natural) else { return }
        text += "\(natural)#"
    }

    mutating func clear() {
        text = ""
    }

    var hasChord: Bool {
        text.trimmedToNil != nil
    }

    var insertTitle: String {
        hasChord ? Self.insertKey : "next"
    }

    /// The root the chord ends with is shown selected.
    func highlights(root note: String) -> Bool {
        text.hasSuffix(note)
    }
}
