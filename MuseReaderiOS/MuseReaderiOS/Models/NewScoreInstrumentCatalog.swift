//
//  NewScoreInstrumentCatalog.swift
//  MuseReaderiOS
//
//  Created by Codex on 5/22/26.
//

import Foundation

enum NewScoreInstrumentCatalog {
    static let importantInstruments: [NewScoreInstrument] = [
        instrument("flute", "Flute", .woodwinds, .treble, genres: [.common, .popular, .jazz, .orchestra, .concertBand, .marchingBand]),
        instrument("piccolo", "Piccolo", .woodwinds, .treble, transposition: "Octave transposition", genres: [.common, .jazz, .orchestra, .concertBand, .marchingBand]),
        instrument("alto-flute", "Alto Flute", .woodwinds, .treble, transposition: "G transposition", genres: [.jazz, .orchestra, .concertBand]),
        instrument("oboe", "Oboe", .woodwinds, .treble, genres: [.common, .orchestra, .concertBand]),
        instrument("english-horn", "English Horn", .woodwinds, .treble, transposition: "F transposition", genres: [.orchestra, .concertBand]),
        instrument("bassoon", "Bassoon", .woodwinds, .bass, genres: [.common, .orchestra, .concertBand]),
        instrument("contrabassoon", "Contrabassoon", .woodwinds, .bass, transposition: "Octave transposition", genres: [.orchestra, .concertBand]),
        instrument("bb-clarinet", "Clarinet in Bb", .woodwinds, .treble, transposition: "Bb transposition", playbackName: "Clarinet", genres: [.common, .jazz, .orchestra, .concertBand, .marchingBand]),
        instrument("a-clarinet", "Clarinet in A", .woodwinds, .treble, transposition: "A transposition", playbackName: "Clarinet", genres: [.orchestra]),
        instrument("eb-clarinet", "Clarinet in Eb", .woodwinds, .treble, transposition: "Eb transposition", playbackName: "Clarinet", genres: [.jazz, .orchestra, .concertBand]),
        instrument("bb-bass-clarinet", "Bass Clarinet in Bb", .woodwinds, .treble, transposition: "Bb transposition", playbackName: "Bass Clarinet", genres: [.common, .jazz, .orchestra, .concertBand, .marchingBand]),
        instrument("alto-saxophone", "Alto Saxophone", .woodwinds, .treble, transposition: "Eb transposition", playbackName: "Saxophone", genres: [.common, .popular, .jazz, .orchestra, .concertBand, .marchingBand]),
        instrument("tenor-saxophone", "Tenor Saxophone", .woodwinds, .treble, transposition: "Bb transposition", playbackName: "Saxophone", genres: [.common, .popular, .jazz, .orchestra, .concertBand, .marchingBand]),
        instrument("baritone-saxophone", "Baritone Saxophone", .woodwinds, .treble, transposition: "Eb transposition", playbackName: "Saxophone", genres: [.common, .jazz, .orchestra, .concertBand, .marchingBand]),
        instrument("soprano-saxophone", "Soprano Saxophone", .woodwinds, .treble, transposition: "Bb transposition", playbackName: "Saxophone", genres: [.common, .jazz, .orchestra, .concertBand, .marchingBand]),

        instrument("accordion", "Accordion", .freeReed, .treble, genres: [.common, .jazz]),
        instrument("bandoneon", "Bandoneon", .freeReed, .treble, genres: [.world]),
        instrument("harmonica", "Harmonica", .freeReed, .treble, genres: [.common, .popular, .jazz]),

        instrument("bb-trumpet", "Trumpet in Bb", .brass, .treble, transposition: "Bb transposition", playbackName: "Trumpet", genres: [.common, .popular, .jazz, .orchestra, .concertBand, .marchingBand]),
        instrument("c-trumpet", "Trumpet in C", .brass, .treble, playbackName: "Trumpet", genres: [.orchestra]),
        instrument("horn", "Horn in F", .brass, .treble, transposition: "F transposition", playbackName: "Horn", genres: [.common, .orchestra, .concertBand, .marchingBand]),
        instrument("trombone", "Trombone", .brass, .bass, genres: [.common, .popular, .jazz, .orchestra, .concertBand, .marchingBand]),
        instrument("bass-trombone", "Bass Trombone", .brass, .bass, genres: [.jazz, .orchestra, .concertBand, .marchingBand]),
        instrument("euphonium", "Euphonium", .brass, .bass, genres: [.concertBand, .marchingBand]),
        instrument("euphonium-treble", "Euphonium in Bb", .brass, .treble, transposition: "Bb transposition", playbackName: "Euphonium", genres: [.concertBand, .marchingBand]),
        instrument("tuba", "Tuba", .brass, .bass, genres: [.common, .jazz, .orchestra, .concertBand, .marchingBand]),
        instrument("bb-tuba", "Contrabass Tuba in Bb", .brass, .bass, transposition: "Bb transposition", playbackName: "Tuba", genres: [.orchestra]),
        instrument("bb-cornet", "Cornet in Bb", .brass, .treble, transposition: "Bb transposition", playbackName: "Cornet", genres: [.common, .jazz, .concertBand]),
        instrument("flugelhorn", "Flugelhorn", .brass, .treble, transposition: "Bb transposition", genres: [.jazz, .concertBand, .marchingBand]),

        instrument("timpani", "Timpani", .pitchedPercussion, .bass, genres: [.common, .orchestra, .concertBand, .marchingBand]),
        instrument("glockenspiel", "Glockenspiel", .pitchedPercussion, .treble, transposition: "Octave transposition", genres: [.common, .jazz, .orchestra, .concertBand, .marchingBand, .classroom]),
        instrument("xylophone", "Xylophone", .pitchedPercussion, .treble, transposition: "Octave transposition", genres: [.common, .jazz, .orchestra, .concertBand, .marchingBand, .classroom]),
        instrument("vibraphone", "Vibraphone", .pitchedPercussion, .treble, genres: [.common, .jazz, .orchestra, .concertBand, .marchingBand]),
        instrument("marimba", "Marimba", .pitchedPercussion, .treble, genres: [.common, .jazz, .orchestra, .concertBand, .marchingBand]),
        instrument("tubular-bells", "Chimes", .pitchedPercussion, .treble, genres: [.common, .orchestra, .concertBand]),
        instrument("crotales", "Crotales", .pitchedPercussion, .treble, transposition: "Octave transposition", genres: [.orchestra, .concertBand, .marchingBand]),

        instrument("drumset", "Drum Kit", .unpitchedPercussion, .treble, playbackName: "Drum Kit", genres: [.common, .popular, .orchestra, .concertBand, .marchingBand]),
        instrument("snare-drum", "Snare Drum", .unpitchedPercussion, .treble, genres: [.common, .choral, .orchestra, .concertBand, .marchingBand]),
        instrument("bass-drum", "Bass Drum", .unpitchedPercussion, .bass, genres: [.common, .orchestra, .concertBand, .marchingBand]),
        instrument("cymbal", "Cymbals", .unpitchedPercussion, .treble, genres: [.common, .orchestra, .concertBand, .marchingBand, .classroom]),
        instrument("bongos", "Bongos", .unpitchedPercussion, .treble, genres: [.popular, .jazz, .orchestra, .concertBand, .marchingBand, .classroom]),
        instrument("congas", "Congas", .unpitchedPercussion, .treble, genres: [.popular, .jazz, .orchestra, .concertBand, .marchingBand]),

        instrument("snare-drum", "Marching Snare Drum", .marchingPercussion, .treble, playbackName: "Snare Drum", genres: [.common, .choral, .orchestra, .concertBand, .marchingBand]),
        instrument("bass-drum", "Marching Bass Drum", .marchingPercussion, .bass, playbackName: "Bass Drum", genres: [.common, .orchestra, .concertBand, .marchingBand]),
        instrument("tom-toms", "Tenor Drums", .marchingPercussion, .treble, playbackName: "Toms", genres: [.orchestra, .concertBand, .marchingBand]),

        instrument("hand-clap", "Hand Clap", .bodyPercussion, .treble, genres: [.common, .popular, .choral, .classroom]),
        instrument("finger-snap", "Finger Snap", .bodyPercussion, .treble, genres: [.common, .popular, .choral, .classroom]),
        instrument("stamp", "Stamp", .bodyPercussion, .bass, genres: [.common, .popular, .choral, .classroom]),

        instrument("voice", "Voice", .vocals, .treble, genres: [.common, .jazz, .choral]),
        instrument("soprano", "Soprano", .vocals, .treble, genres: [.common, .jazz, .choral, .orchestra]),
        instrument("mezzo-soprano", "Mezzo-soprano", .vocals, .treble, genres: [.common, .choral, .orchestra]),
        instrument("alto", "Alto", .vocals, .treble, genres: [.common, .jazz, .choral, .orchestra]),
        instrument("tenor", "Tenor", .vocals, .treble, genres: [.common, .jazz, .choral, .orchestra]),
        instrument("baritone", "Baritone", .vocals, .bass, genres: [.common, .jazz, .choral, .orchestra]),
        instrument("bass", "Bass", .vocals, .bass, genres: [.common, .jazz, .choral, .orchestra]),

        instrument("piano", "Piano", .keyboards, .treble, genres: [.common, .popular, .jazz, .choral, .orchestra, .classroom]),
        instrument("grand-piano", "Grand Piano", .keyboards, .treble, genres: [.orchestra, .concertBand]),
        instrument("electric-piano", "Electric Piano", .keyboards, .treble, genres: [.popular, .jazz]),
        instrument("harpsichord", "Harpsichord", .keyboards, .treble, genres: [.common, .orchestra, .earlyMusic]),
        instrument("celesta", "Celesta", .keyboards, .treble, transposition: "Octave transposition", genres: [.orchestra]),
        instrument("organ", "Organ", .keyboards, .treble, genres: [.common, .popular, .jazz, .orchestra]),

        instrument("poly-synth", "Synthesizer", .electronic, .treble, genres: [.popular, .marchingBand, .electronic]),
        instrument("bass-synthesizer", "Bass Synthesizer", .electronic, .bass, genres: [.popular, .marchingBand, .electronic]),

        instrument("guitar-nylon", "Classical Guitar", .pluckedStrings, .treble, transposition: "Octave transposition", playbackName: "Guitar", genres: [.common, .popular]),
        instrument("guitar-steel", "Acoustic Guitar", .pluckedStrings, .treble, transposition: "Octave transposition", playbackName: "Guitar", genres: [.common, .popular, .jazz, .classroom]),
        instrument("electric-guitar", "Electric Guitar", .pluckedStrings, .treble, transposition: "Octave transposition", genres: [.common, .popular, .jazz, .marchingBand]),
        instrument("bass-guitar", "Bass Guitar", .pluckedStrings, .bass, transposition: "Octave transposition", genres: [.common, .popular, .jazz, .marchingBand]),
        instrument("acoustic-bass", "Acoustic Bass", .pluckedStrings, .bass, transposition: "Octave transposition", genres: [.common, .jazz]),
        instrument("electric-bass", "Electric Bass", .pluckedStrings, .bass, transposition: "Octave transposition", genres: [.common, .popular, .jazz]),
        instrument("mandolin", "Mandolin", .pluckedStrings, .treble, genres: [.popular]),
        instrument("banjo", "Banjo", .pluckedStrings, .treble, genres: [.common, .popular, .jazz]),
        instrument("ukulele", "Ukulele", .pluckedStrings, .treble, transposition: "Octave transposition", genres: [.common, .popular, .classroom]),
        instrument("harp", "Harp", .pluckedStrings, .treble, genres: [.common, .orchestra]),

        instrument("violin", "Violin", .bowedStrings, .treble, genres: [.common, .popular, .jazz, .orchestra]),
        instrument("viola", "Viola", .bowedStrings, .alto, genres: [.common, .jazz, .orchestra]),
        instrument("violoncello", "Cello", .bowedStrings, .bass, playbackName: "Violoncello", genres: [.common, .popular, .jazz, .orchestra]),
        instrument("contrabass", "Contrabass", .bowedStrings, .bass, transposition: "Octave transposition", genres: [.common, .jazz, .orchestra, .concertBand]),
    ]

    static func instruments(for genre: NewScoreInstrumentGenre,
                            category: NewScoreInstrumentCategory,
                            matching query: String) -> [NewScoreInstrument]
    {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return importantInstruments.filter { instrument in
            let matchesGenre = genre == .all || instrument.genres.contains(genre)
            let matchesCategory = category == .all || instrument.category == category
            let matchesQuery = trimmedQuery.isEmpty
                || instrument.name.lowercased().contains(trimmedQuery)
                || instrument.instrumentID.lowercased().contains(trimmedQuery)
                || instrument.category.rawValue.lowercased().contains(trimmedQuery)
                || instrument.genres.contains { $0.rawValue.lowercased().contains(trimmedQuery) }
            return matchesGenre && matchesCategory && matchesQuery
        }
    }

    static func instrument(fromTemplateID instrumentID: String, name: String) -> NewScoreInstrument {
        let catalogID = canonicalInstrumentID(for: instrumentID)
        if let catalogInstrument = importantInstruments.first(where: { $0.instrumentID == catalogID }) {
            return NewScoreInstrument(
                instanceID: "\(instrumentID)-\(name)",
                instrumentID: catalogID,
                name: name,
                category: catalogInstrument.category,
                clef: catalogInstrument.clef,
                transposition: catalogInstrument.transposition,
                playbackName: catalogInstrument.playbackName,
                genres: catalogInstrument.genres
            )
        }

        return NewScoreInstrument(
            instanceID: "\(instrumentID)-\(name)",
            instrumentID: catalogID,
            name: name,
            category: fallbackCategory(for: catalogID, name: name),
            clef: fallbackClef(for: catalogID, name: name)
        )
    }

    private static func canonicalInstrumentID(for instrumentID: String) -> String {
        switch instrumentID {
        case "double-bass":
            return "contrabass"
        case "bass-clarinet":
            return "bb-bass-clarinet"
        case "drum-kit", "drum-kit-4", "drum-kit-5", "percussion":
            return "drumset"
        default:
            return instrumentID
        }
    }

    private static func fallbackCategory(for instrumentID: String, name: String) -> NewScoreInstrumentCategory {
        let lowerName = name.lowercased()
        if instrumentID.contains("drum") || instrumentID.contains("percussion") || lowerName.contains("percussion") {
            return .unpitchedPercussion
        }
        if lowerName.contains("voice") || lowerName.contains("soprano") || lowerName.contains("alto") || lowerName.contains("tenor") || lowerName.contains("bass") {
            return .vocals
        }
        if lowerName.contains("guitar") || lowerName.contains("bass") {
            return .pluckedStrings
        }
        return .keyboards
    }

    private static func fallbackClef(for instrumentID: String, name: String) -> ScorePartClef {
        let lowerName = name.lowercased()
        if lowerName.contains("bass") || lowerName.contains("tuba") || lowerName.contains("trombone") || lowerName.contains("cello") {
            return .bass
        }
        if lowerName.contains("viola") {
            return .alto
        }
        return .treble
    }

    private static func instrument(_ instrumentID: String,
                                   _ name: String,
                                   _ category: NewScoreInstrumentCategory,
                                   _ clef: ScorePartClef,
                                   transposition: String = "Concert pitch",
                                   playbackName: String? = nil,
                                   genres: Set<NewScoreInstrumentGenre>) -> NewScoreInstrument
    {
        NewScoreInstrument(
            instanceID: instrumentID,
            instrumentID: instrumentID,
            name: name,
            category: category,
            clef: clef,
            transposition: transposition,
            playbackName: playbackName,
            genres: genres
        )
    }
}
