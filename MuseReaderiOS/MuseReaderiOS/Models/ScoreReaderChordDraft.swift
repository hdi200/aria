//
//  ScoreReaderChordDraft.swift
//  MuseReaderiOS
//
//  The chord keyboard's keys and what each does to the chord being typed. The keyboard is
//  drawn by ScoreReaderChordKeyboardView (UIKit, iOS) and AndroidTextInputFields.swift.
//

import Foundation

/// Chord Entry types like a keyboard: each key adds its text at the end and ⌫ erases from
/// the end. An existing chord symbol starts out as the text, spelled as it was saved, and
/// MuseScore parses and engraves whatever is entered.
struct ScoreReaderChordBuilderDraft {
    private(set) var text: String

    init(text: String = "") { self.text = text }

    /// Keys that type more than one character, erased with a single ⌫, plus the dim and aug
    /// spellings of imported chords.
    static let multiCharacterTokens = ["maj", "min", "sus", "add", "no", "11", "13", "b5", "#5", "dim", "aug"]

    var hasChord: Bool { text.range(of: "^[A-G]", options: .regularExpression) != nil }

    /// A chord still waiting for its bass, added or omitted degree, altered degree, or the
    /// number of a minor-major seventh.
    var isComplete: Bool {
        hasChord && !text.hasSuffix("/") && !text.hasSuffix("add") && !text.hasSuffix("no")
            && !text.hasSuffix("(maj") && !endsWithAlteration
    }

    /// maj straight after a minor or diminished quality is the major seventh of a
    /// minor-major (Cmin(maj7)) or diminished-major (C°(maj7)) chord.
    private var endsWithMinorOrDiminished: Bool {
        hasChord && text.range(of: "(min|m|-|°)$", options: .regularExpression) != nil
    }

    /// ♭ or # after a note letter is that note's accidental (Cb, C/Eb); anywhere else it
    /// alters the degree that follows (C7b9).
    private var endsWithAlteration: Bool {
        guard let accidentals = text.range(of: "[b#♭♯]+$", options: .regularExpression) else { return false }
        let beforeAccidentals = text[..<accidentals.lowerBound]
        guard let note = beforeAccidentals.last else { return false }
        return !"ABCDEFG".contains(note)
    }

    mutating func type(_ token: String) {
        if token == "maj", endsWithMinorOrDiminished {
            text += "(maj"
        } else if text.hasSuffix("(maj"), token.allSatisfy(\.isNumber) {
            text += token + ")"
        } else {
            text += token
        }
    }

    mutating func backspace() {
        guard !text.isEmpty else { return }
        if let closedMajor = text.range(of: "(?<=\\(maj)[0-9]+\\)$", options: .regularExpression) {
            // Cmin(maj7) → Cmin(maj, the way it was typed.
            text.removeSubrange(closedMajor)
        } else if text.hasSuffix("(maj") {
            text.removeLast("(maj".count)
        } else if let token = Self.multiCharacterTokens.first(where: { text.hasSuffix($0) }) {
            text.removeLast(token.count)
        } else {
            text.removeLast()
        }
    }

    mutating func clear() {
        text = ""
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
