import Testing
@testable import Aria

@MainActor
struct TempoValueTests {
    @Test func parsesNativeTempoAndDescriptionSeparately() {
        let value = TempoValue(markingText: "Allegro, movement 2. \u{ECA5} = 112")
        #expect(value == TempoValue(beatUnit: .quarter, bpm: 112, text: "Allegro, movement 2."))
    }

    @Test func preservesBeatUnitAndDotWhenReopening() {
        #expect(TempoValue(markingText: "Andante \u{ECA5} \u{ECB7} = 72")
                == TempoValue(beatUnit: .dottedQuarter, bpm: 72, text: "Andante"))
        #expect(TempoValue(markingText: "Largo \u{ECA3} = 60")
                == TempoValue(beatUnit: .half, bpm: 60, text: "Largo"))
        #expect(TempoValue(markingText: "\u{ECA7} = 120")
                == TempoValue(beatUnit: .eighth, bpm: 120))
    }

    @Test func supportsImportedUnicodeAndRejectsMissingTempo() {
        #expect(TempoValue(markingText: "Allegro ♩ = 112")
                == TempoValue(beatUnit: .quarter, bpm: 112, text: "Allegro"))
        #expect(TempoValue(markingText: "Allegro 112") == nil)
        #expect(TempoValue(markingText: "♩ = 0") == nil)
    }

    @Test func readsImportedParenthesesApproximationsAndRanges() {
        #expect(TempoValue(markingText: "Allegro (\u{ECA5} = 120)")
                == TempoValue(beatUnit: .quarter, bpm: 120, text: "Allegro"))
        #expect(TempoValue(markingText: "(♩ = c. 96)") == TempoValue(beatUnit: .quarter, bpm: 96))
        #expect(TempoValue(markingText: "Moderato ♩ = 112–120")
                == TempoValue(beatUnit: .quarter, bpm: 112, text: "Moderato"))
    }

    @Test func editingKeepsTheWordsOfATextOnlyMarking() {
        #expect(TempoValue(editing: "Allegro") == TempoValue(beatUnit: .quarter, bpm: 112, text: "Allegro"))
        // An equation it can't read isn't kept as a description, which would double it.
        #expect(TempoValue(editing: "♩ = 400") == TempoValue(beatUnit: .quarter, bpm: 112))
    }
}
