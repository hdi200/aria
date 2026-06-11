//
//  MSCXMusicXMLConverterTests.swift
//  MuseReaderiOSTests
//
//  Created by Codex on 5/20/26.
//

import Foundation
import Testing
@testable import MuseReaderiOS

struct MSCXMusicXMLConverterTests {
    @Test
    func passesThroughMusicXMLUnchanged() {
        let xml = """
        <?xml version="1.0"?>
        <score-partwise version="4.0"><part-list/></score-partwise>
        """

        #expect(MSCXMusicXMLConverter().convertToMusicXML(xml) == xml)
    }

    @Test
    func convertsFixtureMatrixToMusicXML() throws {
        for fixture in [
            "single-staff-notes-rests",
            "two-voices-one-staff",
            "piano-grand-staff",
            "gaps-dots-accidentals",
            "source-measure-numbers",
            "ties-slurs"
        ] {
            let musicXML = try convertedFixture(named: fixture)

            #expect(musicXML.contains("<score-partwise version=\"4.0\">"), "Expected \(fixture) to become MusicXML")
            #expect(musicXML.contains("<part-list>"), "Expected \(fixture) to include a part-list")
            #expect(musicXML.contains("<measure number="), "Expected \(fixture) to include measures")
            #expect(musicXML.contains("<duration>"), "Expected \(fixture) to include timed notes or rests")
        }
    }

    @Test
    func emitsSingleStaffNotesRestsAndAttributes() throws {
        let musicXML = try convertedFixture(named: "single-staff-notes-rests")

        #expect(musicXML.contains("<work-title>Fixture Title</work-title>"))
        #expect(musicXML.contains("<creator type=\"composer\">Fixture Composer</creator>"))
        #expect(musicXML.contains("<part-name>Violin</part-name>"))
        #expect(musicXML.contains("<divisions>480</divisions>"))
        #expect(musicXML.contains("<beats>3</beats>"))
        #expect(musicXML.contains("<beat-type>4</beat-type>"))
        #expect(musicXML.contains("<fifths>2</fifths>"))
        #expect(musicXML.contains("<sign>G</sign>"))
        #expect(musicXML.contains("<line>2</line>"))
        #expect(musicXML.contains("<step>C</step>"))
        #expect(musicXML.contains("<octave>4</octave>"))
        #expect(musicXML.contains("<rest/>"))
        #expect(musicXML.contains("<type>quarter</type>"))
    }

    @Test
    func preservesVoiceNumbersAndLeadingGaps() throws {
        let musicXML = try convertedFixture(named: "two-voices-one-staff")

        #expect(musicXML.contains("<voice>1</voice>"))
        #expect(musicXML.contains("<voice>2</voice>"))
        #expect(musicXML.contains("<forward>"))
        #expect(musicXML.contains("<duration>480</duration>"))
    }

    @Test
    func emitsGrandStaffAsOneMusicXMLPartWithStaffNumbers() throws {
        let musicXML = try convertedFixture(named: "piano-grand-staff")

        #expect(musicXML.contains("<part-name>Piano</part-name>"))
        #expect(musicXML.contains("<staves>2</staves>"))
        #expect(musicXML.contains("<clef number=\"1\">"))
        #expect(musicXML.contains("<clef number=\"2\">"))
        #expect(musicXML.contains("<sign>F</sign>"))
        #expect(musicXML.contains("<staff>1</staff>"))
        #expect(musicXML.contains("<staff>2</staff>"))
        #expect(musicXML.contains("<backup>"))
    }

    @Test
    func emitsDotsAccidentalsAndForwardFill() throws {
        let musicXML = try convertedFixture(named: "gaps-dots-accidentals")

        #expect(musicXML.contains("<duration>720</duration>"))
        #expect(musicXML.contains("<dot/>"))
        #expect(musicXML.contains("<alter>1</alter>"))
        #expect(musicXML.contains("<accidental>sharp</accidental>"))
        #expect(musicXML.contains("<forward>"))
    }

    @Test
    func preservesSourceMeasureNumbers() throws {
        let musicXML = try convertedFixture(named: "source-measure-numbers")

        #expect(musicXML.contains("<measure number=\"A\">"))
        #expect(musicXML.contains("<measure number=\"B\">"))
    }

    @Test
    func emitsTieAndSlurNotation() throws {
        let musicXML = try convertedFixture(named: "ties-slurs")

        #expect(musicXML.contains("<tied type=\"start\"/>"))
        #expect(musicXML.contains("<slur type=\"start\"/>"))
        #expect(musicXML.contains("<notations>"))
    }

    private func convertedFixture(named name: String) throws -> String {
        let url = fixtureDirectory.appendingPathComponent("\(name).mscx")
        let xml = try String(contentsOf: url, encoding: .utf8)
        return MSCXMusicXMLConverter().convertToMusicXML(xml)
    }

    private var fixtureDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("ConverterFixtures")
    }
}
