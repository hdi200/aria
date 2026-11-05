import Testing
@testable import Aria

@MainActor
struct ScoreReaderChordBuilderTests {
    @Test func changesComponentsWithoutAppendingDuplicateRootsOrQualities() {
        var draft = ScoreReaderChordBuilderDraft(text: "Cmaj7")
        draft.chooseRoot("D")
        draft.chooseQuality("min")
        draft.chooseExtension("9")
        #expect(draft.text == "Dmin9")
        #expect(draft.selectedRoot == "D")
        #expect(draft.selectedQuality == "min")
        #expect(draft.selectedExtension == "9")
    }

    @Test func changesSlashBassAndKeepsAlterationsBeforeIt() {
        var draft = ScoreReaderChordBuilderDraft(text: "C7")
        draft.pressModifier("/")
        #expect(!draft.isComplete)
        draft.chooseRoot("G")
        draft.pressModifier("b")
        #expect(draft.text == "C7/Gb")
        draft.pressModifier("b5")
        #expect(draft.text == "C7b5/Gb")
        draft.pressModifier("add")
        #expect(!draft.isComplete)
        draft.chooseExtension("11")
        #expect(draft.text == "C7b5add11/Gb")
        #expect(draft.isComplete)
    }

    @Test func preservesPrefilledChordUntilAComponentIsChanged() {
        var draft = ScoreReaderChordBuilderDraft(text: "F#7(b9)/C#")
        #expect(draft.text == "F#7(b9)/C#")
        draft.chooseRoot("A")
        #expect(draft.text == "A#7(b9)/C#")
        draft.chooseQuality("maj")
        #expect(draft.text == "A#maj7(b9)/C#")
        draft.chooseExtension("13")
        #expect(draft.text == "A#maj13(b9)/C#")
        let previous = ScoreReaderChordBuilderDraft(text: "Ebmaj7/Bb")
        #expect(previous.text == "Ebmaj7/Bb")
        #expect(previous.selectedRoot == "E")
        #expect(previous.selectedQuality == "maj")
    }

    @Test func dominantChordsLightNoQualityAndTappingAQualityAgainClearsIt() {
        var draft = ScoreReaderChordBuilderDraft(text: "C7")
        #expect(draft.selectedQuality == "")
        draft.chooseQuality("maj")
        #expect(draft.text == "Cmaj7")
        draft.chooseQuality("maj")
        #expect(draft.text == "C7")
        draft.chooseQuality("min")
        draft.chooseQuality("min")
        #expect(draft.text == "C7")

        var triad = ScoreReaderChordBuilderDraft(text: "C")
        #expect(triad.selectedQuality == "maj")
        triad.chooseQuality("maj")
        #expect(triad.text == "C")
        #expect(ScoreReaderChordBuilderDraft(text: "C6").selectedQuality == "maj")
    }

    @Test func tappingTheSelectedExtensionClearsOnlyThatExtension() {
        var draft = ScoreReaderChordBuilderDraft(text: "Amin9/E")
        draft.chooseExtension("9")
        #expect(draft.text == "Amin/E")
        #expect(draft.selectedExtension.isEmpty)

        draft.chooseExtension("7")
        draft.pressModifier("add")
        draft.chooseExtension("7")
        #expect(draft.text == "Amin7add7/E")
        draft.chooseExtension("7")
        #expect(draft.text == "Aminadd7/E")
    }

    @Test func clearingAnExtensionKeepsAnAlteredFifthDistinctFromTheRoot() {
        var draft = ScoreReaderChordBuilderDraft(text: "C7b5/E")
        draft.chooseExtension("7")
        #expect(draft.text == "C(b5)/E")
        #expect(draft.hasModifier("b5"))
        #expect(!draft.hasAccidental("b"))
        draft.pressModifier("b5")
        #expect(draft.text == "C/E")
    }

    @Test func clearSlashBassKeepsTheChordAndCancelsAnUnfinishedBass() {
        var draft = ScoreReaderChordBuilderDraft(text: "C7/E")
        draft.clearSlashBass()
        #expect(draft.text == "C7")
        draft.pressModifier("/")
        #expect(!draft.isComplete)
        draft.clearSlashBass()
        #expect(draft.text == "C7")
        #expect(draft.isComplete)
        #expect(!draft.editsBass)
    }
}
