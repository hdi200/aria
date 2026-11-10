import Testing
@testable import Aria

@MainActor
struct ScoreReaderChordBuilderTests {
    private func typed(_ keys: [String], from text: String = "") -> ScoreReaderChordBuilderDraft {
        var draft = ScoreReaderChordBuilderDraft(text: text)
        for key in keys { draft.type(key) }
        return draft
    }

    @Test func keysTypeInOrder() {
        #expect(typed(["B", "b", "7", "b", "9"]).text == "Bb7b9")
        #expect(typed(["C", "7", "sus", "4"]).text == "C7sus4")
        #expect(typed(["C", "maj", "7"]).text == "Cmaj7")
        #expect(typed(["C", "6", "/", "9"]).text == "C6/9")
        #expect(typed(["F", "#", "maj", "7", "/", "C", "#"]).text == "F#maj7/C#")
    }

    @Test func majAfterMinorOrDiminishedSpellsTheMajorSeventh() {
        var draft = typed(["C", "min", "maj"])
        #expect(draft.text == "Cmin(maj")
        #expect(!draft.isComplete)
        draft.type("7")
        #expect(draft.text == "Cmin(maj7)")
        #expect(draft.isComplete)
        #expect(typed(["C", "°", "maj", "7"]).text == "C°(maj7)")

        draft.backspace()
        #expect(draft.text == "Cmin(maj")
        draft.backspace()
        #expect(draft.text == "Cmin")
        draft.backspace()
        #expect(draft.text == "C")
    }

    @Test func anExistingChordStartsAsTypedAndKeysAddToIt() {
        let draft = ScoreReaderChordBuilderDraft(text: "CmMaj7")
        #expect(draft.text == "CmMaj7")
        #expect(draft.isComplete)
        #expect(typed(["/", "G"], from: "Am7").text == "Am7/G")
    }

    @Test func backspaceErasesAKeyAtATime() {
        var draft = ScoreReaderChordBuilderDraft(text: "Bb7")
        draft.backspace()
        draft.backspace()
        #expect(draft.text == "B")
        draft.type("7")
        #expect(draft.text == "B7")

        var words = ScoreReaderChordBuilderDraft(text: "Cmaj13add")
        words.backspace()
        #expect(words.text == "Cmaj13")
        words.backspace()
        #expect(words.text == "Cmaj")
        words.backspace()
        #expect(words.text == "C")

        var imported = ScoreReaderChordBuilderDraft(text: "Cdim")
        imported.backspace()
        #expect(imported.text == "C")

        var slash = ScoreReaderChordBuilderDraft(text: "C7/E")
        slash.backspace()
        #expect(slash.text == "C7/")
        slash.backspace()
        #expect(slash.text == "C7")
    }

    @Test func unfinishedChordsAreNotComplete() {
        #expect(!typed(["C", "7", "/"]).isComplete)
        #expect(!typed(["C", "add"]).isComplete)
        #expect(!typed(["C", "7", "no"]).isComplete)
        #expect(!typed(["C", "7", "b"]).isComplete)
        #expect(!typed(["C", "7", "#"]).isComplete)
        #expect(!ScoreReaderChordBuilderDraft(text: "").isComplete)
        #expect(!ScoreReaderChordBuilderDraft(text: "maj7").hasChord)
    }

    @Test func noteAccidentalsAreComplete() {
        #expect(typed(["C", "b"]).isComplete)
        #expect(typed(["C", "#", "#"]).isComplete)
        #expect(typed(["C", "/", "E", "b"]).isComplete)
        #expect(ScoreReaderChordBuilderDraft(text: "B♭7/A♭").isComplete)
        #expect(typed(["C", "7", "b", "9"]).isComplete)
    }

    @Test func clearErasesEverything() {
        var draft = ScoreReaderChordBuilderDraft(text: "G7/B")
        draft.clear()
        #expect(draft.text.isEmpty)
        #expect(!draft.hasChord)
    }
}
