//
//  ScoreReaderChordDraft.swift
//  MuseReaderiOS
//
//  The chord keyboard's keys and what each does to the chord being typed. The keyboard is
//  drawn by ScoreReaderChordKeyboardView (UIKit, iOS) and AndroidTextInputFields.swift.
//

import Foundation

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
