//
//  NewScoreDraft.swift
//  MuseReaderiOS
//
//  Created by Codex on 5/7/26.
//

import Foundation

struct NewScoreDraft: Sendable, Equatable {
    var title: String
    var subtitle: String
    var composer: String
    var template: NewScoreTemplate
    var keySignature: NewScoreKeySignature
    var timeSignature: NewScoreTimeSignature
    var tempo: Int
    var measureCount: Int
    var hasPickupMeasure: Bool
    var pickupNumerator: Int
    var pickupDenominator: Int
    var templateChoice: NewScoreTemplateChoice
    var selectedInstruments: [NewScoreInstrument]

    init(template: NewScoreTemplate = .piano) {
        self.title = template.defaultTitle
        self.subtitle = ""
        self.composer = "Your Name"
        self.template = template
        self.keySignature = .cMajor
        self.timeSignature = .fourFour
        self.tempo = 120
        self.measureCount = 32
        self.hasPickupMeasure = false
        self.pickupNumerator = 1
        self.pickupDenominator = 4
        self.templateChoice = template.choice
        self.selectedInstruments = template == .blankScore ? [] : template.choice.instruments
    }

    var metadata: ScoreEditableMetadata {
        ScoreEditableMetadata(
            title: title,
            subtitle: subtitle,
            composer: composer,
            lyricist: "",
            arranger: ""
        )
    }
}

enum NewScoreTemplate: String, CaseIterable, Identifiable, Sendable, Equatable {
    case blank
    case piano
    case leadSheet
    case stringQuartet
    case choir
    case blankScore
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blank: return "Treble Clef"
        case .piano: return "Piano"
        case .leadSheet: return "Lead Sheet"
        case .stringQuartet: return "String Quartet"
        case .choir: return "Choir"
        case .blankScore: return "Blank"
        case .custom: return "More"
        }
    }

    var defaultTitle: String {
        switch self {
        case .blank: return "New Treble Clef Score"
        case .piano: return "New Piano Score"
        case .leadSheet: return "New Lead Sheet"
        case .stringQuartet: return "New String Quartet"
        case .choir: return "New Choir Score"
        case .blankScore: return "New Blank Score"
        case .custom: return "New Score"
        }
    }

    var choice: NewScoreTemplateChoice {
        switch self {
        case .blank:
            return .quick(title: title, resourceDirectoryName: resourceDirectoryName, templateFileName: templateFileName, instruments: instruments)
        case .piano:
            return .quick(title: title, resourceDirectoryName: resourceDirectoryName, templateFileName: templateFileName, instruments: instruments)
        case .leadSheet:
            return .quick(title: title, resourceDirectoryName: resourceDirectoryName, templateFileName: templateFileName, instruments: instruments)
        case .stringQuartet:
            return .quick(title: title, resourceDirectoryName: resourceDirectoryName, templateFileName: templateFileName, instruments: instruments)
        case .choir:
            return .quick(title: title, resourceDirectoryName: resourceDirectoryName, templateFileName: templateFileName, instruments: instruments)
        case .blankScore:
            return .quick(title: title, resourceDirectoryName: resourceDirectoryName, templateFileName: templateFileName, instruments: instruments)
        case .custom:
            return NewScoreTemplateChoice.allTemplates[0].templates[0]
        }
    }

    var resourceDirectoryName: String {
        switch self {
        case .blank, .blankScore, .custom: return "Blank"
        case .piano: return "Piano"
        case .leadSheet: return "LeadSheet"
        case .stringQuartet: return "StringQuartet"
        case .choir: return "Choir"
        }
    }

    var templateFileName: String {
        switch self {
        case .blank, .blankScore, .custom: return "01-Treble_Clef.mscx"
        case .piano: return "04-Piano.mscx"
        case .leadSheet: return "01-Jazz_Lead_Sheet.mscx"
        case .stringQuartet: return "01-String_Quartet.mscx"
        case .choir: return "01-SATB.mscx"
        }
    }

    var bundleDirectoryURL: URL? {
        let bundleCandidates = [
            Bundle.main.url(forResource: "ScoreTemplates", withExtension: "bundle"),
            Bundle.main.url(forResource: "ScoreTemplates", withExtension: "bundle", subdirectory: "Resources")
        ]

        for bundleURL in bundleCandidates.compactMap({ $0 }) {
            let templateURL = bundleURL.appendingPathComponent(resourceDirectoryName, isDirectory: true)
            if FileManager.default.fileExists(atPath: templateURL.path) {
                return templateURL
            }
        }

        return nil
    }

    var instruments: [NewScoreInstrument] {
        switch self {
        case .blank, .custom:
            return [NewScoreInstrument(instanceID: "blank-treble-staff", instrumentID: "piano", name: "Treble Staff", category: .keyboards, clef: .treble)]
        case .blankScore:
            return []
        case .piano:
            return [
                NewScoreInstrument(instanceID: "piano", instrumentID: "piano", name: "Piano", category: .keyboards, clef: .treble)
            ]
        case .leadSheet:
            return [NewScoreInstrument(instanceID: "lead-sheet", instrumentID: "piano", name: "Lead Sheet", category: .keyboards, clef: .treble)]
        case .stringQuartet:
            return [
                NewScoreInstrument(instanceID: "violin-1", instrumentID: "violin", name: "Violin I", category: .bowedStrings, clef: .treble, playbackName: "Violin"),
                NewScoreInstrument(instanceID: "violin-2", instrumentID: "violin", name: "Violin II", category: .bowedStrings, clef: .treble, playbackName: "Violin"),
                NewScoreInstrument(instanceID: "viola", instrumentID: "viola", name: "Viola", category: .bowedStrings, clef: .alto),
                NewScoreInstrument(instanceID: "violoncello", instrumentID: "violoncello", name: "Cello", category: .bowedStrings, clef: .bass, playbackName: "Violoncello")
            ]
        case .choir:
            return [
                NewScoreInstrument(instanceID: "soprano", instrumentID: "soprano", name: "Soprano", category: .vocals, clef: .treble),
                NewScoreInstrument(instanceID: "alto", instrumentID: "alto", name: "Alto", category: .vocals, clef: .treble),
                NewScoreInstrument(instanceID: "tenor", instrumentID: "tenor", name: "Tenor", category: .vocals, clef: .treble),
                NewScoreInstrument(instanceID: "bass", instrumentID: "bass", name: "Bass", category: .vocals, clef: .bass)
            ]
        }
    }
}

struct NewScoreTemplateCategory: Identifiable, Sendable, Equatable {
    var id: String { title }
    let title: String
    let templates: [NewScoreTemplateChoice]
}

struct NewScoreTemplateChoice: Identifiable, Sendable, Equatable {
    var id: String { resourceDirectoryName + "/" + templateFileName }
    let title: String
    let categoryTitle: String
    let resourceDirectoryName: String
    let templateFileName: String
    let fallbackInstruments: [NewScoreInstrument]
    let replacesTemplateInstruments: Bool

    var instruments: [NewScoreInstrument] {
        parsedTemplateInstruments() ?? fallbackInstruments
    }

    static func quick(title: String,
                      resourceDirectoryName: String,
                      templateFileName: String,
                      instruments: [NewScoreInstrument]) -> NewScoreTemplateChoice
    {
        NewScoreTemplateChoice(
            title: title,
            categoryTitle: "Quick Start",
            resourceDirectoryName: resourceDirectoryName,
            templateFileName: templateFileName,
            fallbackInstruments: instruments,
            replacesTemplateInstruments: true
        )
    }

    var bundleDirectoryURL: URL? {
        let bundleCandidates = [
            Bundle.main.url(forResource: "ScoreTemplates", withExtension: "bundle"),
            Bundle.main.url(forResource: "ScoreTemplates", withExtension: "bundle", subdirectory: "Resources")
        ]

        for bundleURL in bundleCandidates.compactMap({ $0 }) {
            let templateURL = bundleURL.appendingPathComponent(resourceDirectoryName, isDirectory: true)
            if FileManager.default.fileExists(atPath: templateURL.path) {
                return templateURL
            }
        }

        return nil
    }

    private func parsedTemplateInstruments() -> [NewScoreInstrument]? {
        guard let templateURL = bundleDirectoryURL?.appendingPathComponent(templateFileName, isDirectory: false),
              let xml = try? String(contentsOf: templateURL, encoding: .utf8) else {
            return nil
        }

        let partPattern = #"<Part\b[^>]*>(.*?)</Part>"#
        guard let partRegex = try? NSRegularExpression(pattern: partPattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }

        let nsRange = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        let matches = partRegex.matches(in: xml, range: nsRange)
        let instruments = matches.compactMap { match -> NewScoreInstrument? in
            guard let partRange = Range(match.range(at: 1), in: xml) else {
                return nil
            }
            let part = String(xml[partRange])
            let instrumentID = capture(#"<Instrument\b[^>]*id="([^"]+)""#, in: part) ?? "piano"
            let name = cleaned(capture(#"<longName>(.*?)</longName>"#, in: part))
                ?? cleaned(capture(#"<trackName>(.*?)</trackName>"#, in: part))
                ?? instrumentID
            return NewScoreInstrumentCatalog.instrument(fromTemplateID: instrumentID, name: name)
        }

        return instruments.isEmpty ? nil : instruments
    }

    private func capture(_ pattern: String, in source: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..<source.endIndex, in: source)),
              let range = Range(match.range(at: 1), in: source) else {
            return nil
        }
        return String(source[range])
    }

    private func cleaned(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let cleaned = value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned.isEmpty ? nil : cleaned
    }

    static let allTemplates: [NewScoreTemplateCategory] = [
        category("General", "01-General", [
            ("Treble Clef", "01-Treble_Clef", "01-Treble_Clef.mscx"),
            ("Bass Clef", "02-Bass_Clef", "02-Bass_Clef.mscx"),
            ("Grand Staff", "03-Grand_Staff", "03-Grand_Staff.mscx")
        ]),
        category("Choral", "02-Choral", [
            ("SATB", "01-SATB", "01-SATB.mscx"),
            ("SATB + Organ", "02-SATB_+_Organ", "02-SATB_+_Organ.mscx"),
            ("SATB + Piano", "03-SATB_+_Piano", "03-SATB_+_Piano.mscx"),
            ("SATB Closed Score", "04-SATB_Closed_Score", "04-SATB_Closed_Score.mscx"),
            ("SATB Closed Score + Organ", "05-SATB_Closed_Score_+_Organ", "05-SATB_Closed_Score_+_Organ.mscx"),
            ("SATB Closed Score + Piano", "06-SATB_Closed_Score_+_Piano", "06-SATB_Closed_Score_+_Piano.mscx"),
            ("Voice + Piano", "07-Voice_+_Piano", "07-Voice_+_Piano.mscx"),
            ("Barbershop Quartet (Men)", "08-Barbershop_Quartet_(Men)", "08-Barbershop_Quartet_(Men).mscx"),
            ("Barbershop Quartet (Women)", "09-Barbershop_Quartet_(Women)", "09-Barbershop_Quartet_(Women).mscx"),
            ("Liturgical Unmetrical", "10-Liturgical_Unmetrical", "10-Liturgical_Unmetrical.mscx"),
            ("Liturgical Unmetrical + Organ", "11-Liturgical_Unmetrical_+_Organ", "11-Liturgical_Unmetrical_+_Organ.mscx")
        ]),
        category("Chamber Music", "03-Chamber_Music", [
            ("String Quartet", "01-String_Quartet", "01-String_Quartet.mscx"),
            ("Wind Quartet", "02-Wind_Quartet", "02-Wind_Quartet.mscx"),
            ("Wind Quintet", "03-Wind_Quintet", "03-Wind_Quintet.mscx"),
            ("Saxophone Quartet", "04-Saxophone_Quartet", "04-Saxophone_Quartet.mscx"),
            ("Brass Quartet", "05-Brass_Quartet", "05-Brass_Quartet.mscx"),
            ("Brass Quintet", "06-Brass_Quintet", "06-Brass_Quintet.mscx")
        ]),
        category("Solo", "04-Solo", [
            ("Guitar", "01-Guitar", "01-Guitar.mscx"),
            ("Guitar + Tablature", "02-Guitar_+_Tablature", "02-Guitar_+_Tablature.mscx"),
            ("Guitar Tablature", "03-Guitar_Tablature", "03-Guitar_Tablature.mscx"),
            ("Piano", "04-Piano", "04-Piano.mscx")
        ]),
        category("Jazz", "05-Jazz", [
            ("Jazz Lead Sheet", "01-Jazz_Lead_Sheet", "01-Jazz_Lead_Sheet.mscx"),
            ("Big Band", "02-Big_Band", "02-Big_Band.mscx"),
            ("Jazz Combo", "03-Jazz_Combo", "03-Jazz_Combo.mscx")
        ]),
        category("Popular", "06-Popular", [
            ("Rock Band", "01-Rock_Band", "01-Rock_Band.mscx"),
            ("Bluegrass Band", "02-Bluegrass_Band", "02-Bluegrass_Band.mscx")
        ]),
        category("Band and Percussion", "07-Band_and_Percussion", [
            ("Concert Band", "01-Concert_Band", "01-Concert_Band.mscx"),
            ("Small Concert Band", "02-Small_Concert_Band", "02-Small_Concert_Band.mscx"),
            ("Brass Band", "03-Brass_Band", "03-Brass_Band.mscx"),
            ("Marching Band", "04-Marching_Band", "04-Marching_Band.mscx"),
            ("Small Marching Band", "05-Small_Marching_Band", "05-Small_Marching_Band.mscx"),
            ("Battery Percussion", "06-Battery_Percussion", "06-Battery_Percussion.mscx"),
            ("Large Pit Percussion", "07-Large_Pit_Percussion", "07-Large_Pit_Percussion.mscx"),
            ("Small Pit Percussion", "08-Small_Pit_Percussion", "08-Small_Pit_Percussion.mscx"),
            ("European Concert Band", "09-European_Concert_Band", "09-European_Concert_Band.mscx")
        ]),
        category("Orchestral", "08-Orchestral", [
            ("Classical Orchestra", "01-Classical_Orchestra", "01-Classical_Orchestra.mscx"),
            ("Symphony Orchestra", "02-Symphony_Orchestra", "02-Symphony_Orchestra.mscx"),
            ("String Orchestra", "03-String_Orchestra", "03-String_Orchestra.mscx")
        ])
    ]

    private static func category(_ title: String,
                                 _ directory: String,
                                 _ entries: [(String, String, String)]) -> NewScoreTemplateCategory
    {
        NewScoreTemplateCategory(
            title: title,
            templates: entries.map { entry in
                NewScoreTemplateChoice(
                    title: entry.0,
                    categoryTitle: title,
                    resourceDirectoryName: "\(directory)/\(entry.1)",
                    templateFileName: entry.2,
                    fallbackInstruments: [],
                    replacesTemplateInstruments: false
                )
            }
        )
    }
}

struct NewScoreInstrument: Identifiable, Sendable, Equatable {
    var id: String { instanceID }
    let instanceID: String
    let instrumentID: String
    let name: String
    let category: NewScoreInstrumentCategory
    let clef: ScorePartClef
    let transposition: String
    let playbackName: String
    let genres: Set<NewScoreInstrumentGenre>

    init(instanceID: String? = nil,
         instrumentID: String = "piano",
         name: String,
         category: NewScoreInstrumentCategory = .keyboards,
         clef: ScorePartClef,
         transposition: String = "Concert pitch",
         playbackName: String? = nil,
         genres: Set<NewScoreInstrumentGenre> = [.common])
    {
        self.instanceID = instanceID ?? UUID().uuidString
        self.instrumentID = instrumentID
        self.name = name
        self.category = category
        self.clef = clef
        self.transposition = transposition
        self.playbackName = playbackName ?? name
        self.genres = genres
    }
}

enum NewScoreInstrumentGenre: String, CaseIterable, Identifiable, Sendable, Equatable, Hashable {
    case common = "Common"
    case all = "All instruments"
    case popular = "Pop/Rock"
    case jazz = "Jazz"
    case choral = "Choral"
    case orchestra = "Orchestra"
    case concertBand = "Concert Band"
    case marchingBand = "Marching Band"
    case electronic = "Electronic Music"
    case world = "World Music"
    case earlyMusic = "Early Music"
    case classroom = "Classroom"

    var id: String { rawValue }
}

enum NewScoreInstrumentCategory: String, CaseIterable, Identifiable, Sendable, Equatable, Hashable {
    case all = "All Instruments"
    case woodwinds = "Woodwinds"
    case freeReed = "Free Reed"
    case brass = "Brass"
    case pitchedPercussion = "Pitched Percussion"
    case unpitchedPercussion = "Unpitched Percussion"
    case marchingPercussion = "Marching Percussion"
    case bodyPercussion = "Body Percussion"
    case vocals = "Vocals"
    case keyboards = "Keyboards"
    case electronic = "Electronic"
    case pluckedStrings = "Plucked Strings"
    case bowedStrings = "Bowed Strings"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .woodwinds: return "pencil"
        case .freeReed: return "accordion"
        case .brass: return "music.quarternote.3"
        case .pitchedPercussion: return "pianokeys"
        case .unpitchedPercussion: return "circle.grid.cross"
        case .marchingPercussion: return "drum"
        case .bodyPercussion: return "hands.clap"
        case .vocals: return "person.wave.2"
        case .keyboards: return "pianokeys"
        case .electronic: return "waveform"
        case .pluckedStrings: return "guitars"
        case .bowedStrings: return "music.note"
        }
    }
}

extension NewScoreInstrument {
    var detailText: String {
        "\(category.rawValue) · \(clef.instrumentLabel) · \(transposition)"
    }
}

extension ScorePartClef {
    var instrumentLabel: String {
        switch self {
        case .treble:
            return "Treble clef"
        case .alto:
            return "Alto clef"
        case .bass:
            return "Bass clef"
        }
    }
}

struct NewScoreKeySignature: Identifiable, Sendable, Equatable {
    let rawValue: String
    let keyValue: Int
    let isMinor: Bool

    var id: String { "\(keyValue)-\(isMinor)-\(rawValue)" }

    static let cMajor = NewScoreKeySignature(rawValue: "C major", keyValue: 0, isMinor: false)
    static let gMajor = NewScoreKeySignature(rawValue: "G major", keyValue: 1, isMinor: false)
    static let dMajor = NewScoreKeySignature(rawValue: "D major", keyValue: 2, isMinor: false)
    static let aMajor = NewScoreKeySignature(rawValue: "A major", keyValue: 3, isMinor: false)
    static let eMajor = NewScoreKeySignature(rawValue: "E major", keyValue: 4, isMinor: false)
    static let bMajor = NewScoreKeySignature(rawValue: "B major", keyValue: 5, isMinor: false)
    static let fSharpMajor = NewScoreKeySignature(rawValue: "F# major", keyValue: 6, isMinor: false)
    static let cSharpMajor = NewScoreKeySignature(rawValue: "C# major", keyValue: 7, isMinor: false)
    static let fMajor = NewScoreKeySignature(rawValue: "F major", keyValue: -1, isMinor: false)
    static let bFlatMajor = NewScoreKeySignature(rawValue: "B-flat major", keyValue: -2, isMinor: false)
    static let eFlatMajor = NewScoreKeySignature(rawValue: "E-flat major", keyValue: -3, isMinor: false)
    static let aFlatMajor = NewScoreKeySignature(rawValue: "A-flat major", keyValue: -4, isMinor: false)
    static let dFlatMajor = NewScoreKeySignature(rawValue: "D-flat major", keyValue: -5, isMinor: false)
    static let gFlatMajor = NewScoreKeySignature(rawValue: "G-flat major", keyValue: -6, isMinor: false)
    static let cFlatMajor = NewScoreKeySignature(rawValue: "C-flat major", keyValue: -7, isMinor: false)

    static let aMinor = NewScoreKeySignature(rawValue: "A minor", keyValue: 0, isMinor: true)
    static let eMinor = NewScoreKeySignature(rawValue: "E minor", keyValue: 1, isMinor: true)
    static let bMinor = NewScoreKeySignature(rawValue: "B minor", keyValue: 2, isMinor: true)
    static let fSharpMinor = NewScoreKeySignature(rawValue: "F# minor", keyValue: 3, isMinor: true)
    static let cSharpMinor = NewScoreKeySignature(rawValue: "C# minor", keyValue: 4, isMinor: true)
    static let gSharpMinor = NewScoreKeySignature(rawValue: "G# minor", keyValue: 5, isMinor: true)
    static let dSharpMinor = NewScoreKeySignature(rawValue: "D# minor", keyValue: 6, isMinor: true)
    static let aSharpMinor = NewScoreKeySignature(rawValue: "A# minor", keyValue: 7, isMinor: true)
    static let dMinor = NewScoreKeySignature(rawValue: "D minor", keyValue: -1, isMinor: true)
    static let gMinor = NewScoreKeySignature(rawValue: "G minor", keyValue: -2, isMinor: true)
    static let cMinor = NewScoreKeySignature(rawValue: "C minor", keyValue: -3, isMinor: true)
    static let fMinor = NewScoreKeySignature(rawValue: "F minor", keyValue: -4, isMinor: true)
    static let bFlatMinor = NewScoreKeySignature(rawValue: "B-flat minor", keyValue: -5, isMinor: true)
    static let eFlatMinor = NewScoreKeySignature(rawValue: "E-flat minor", keyValue: -6, isMinor: true)
    static let aFlatMinor = NewScoreKeySignature(rawValue: "A-flat minor", keyValue: -7, isMinor: true)

    static let allCases: [NewScoreKeySignature] = [
        .cMajor, .gMajor, .dMajor, .aMajor, .eMajor, .bMajor, .fSharpMajor, .cSharpMajor,
        .fMajor, .bFlatMajor, .eFlatMajor, .aFlatMajor, .dFlatMajor, .gFlatMajor, .cFlatMajor,
        .aMinor, .eMinor, .bMinor, .fSharpMinor, .cSharpMinor, .gSharpMinor, .dSharpMinor, .aSharpMinor,
        .dMinor, .gMinor, .cMinor, .fMinor, .bFlatMinor, .eFlatMinor, .aFlatMinor
    ]

    static func from(_ value: ScoreKeySignatureValue) -> NewScoreKeySignature {
        allCases.first { $0.keyValue == value.keyValue && $0.isMinor == value.isMinor }
            ?? NewScoreKeySignature(rawValue: "\(value.title) \(value.isMinor ? "minor" : "major")", keyValue: value.keyValue, isMinor: value.isMinor)
    }
}

struct NewScoreTimeSignature: Identifiable, Sendable, Equatable {
    let rawValue: String
    let numerator: Int
    let denominator: Int
    let style: ScoreTimeSignatureStyle

    var id: String { "\(numerator)/\(denominator)" }

    var scoreValue: ScoreTimeSignatureValue {
        ScoreTimeSignatureValue(numerator: numerator, denominator: denominator, style: style)
    }

    init(rawValue: String, numerator: Int, denominator: Int, style: ScoreTimeSignatureStyle = .normal) {
        self.rawValue = rawValue
        self.numerator = numerator
        self.denominator = denominator
        self.style = style
    }

    static let fourFour = NewScoreTimeSignature(rawValue: "4/4", numerator: 4, denominator: 4)
    static let threeFour = NewScoreTimeSignature(rawValue: "3/4", numerator: 3, denominator: 4)
    static let twoFour = NewScoreTimeSignature(rawValue: "2/4", numerator: 2, denominator: 4)
    static let sixEight = NewScoreTimeSignature(rawValue: "6/8", numerator: 6, denominator: 8)
    static let cutTime = NewScoreTimeSignature(rawValue: "2/2", numerator: 2, denominator: 2, style: .cutTime)
    static let fiveFour = NewScoreTimeSignature(rawValue: "5/4", numerator: 5, denominator: 4)
    static let sevenEight = NewScoreTimeSignature(rawValue: "7/8", numerator: 7, denominator: 8)
    static let twelveEight = NewScoreTimeSignature(rawValue: "12/8", numerator: 12, denominator: 8)

    static let allCases: [NewScoreTimeSignature] = [
        .fourFour, .threeFour, .twoFour, .sixEight, .cutTime, .fiveFour, .sevenEight, .twelveEight
    ]

    static func from(_ value: ScoreTimeSignatureValue) -> NewScoreTimeSignature {
        allCases.first { $0.numerator == value.numerator && $0.denominator == value.denominator && $0.style == value.style }
            ?? NewScoreTimeSignature(rawValue: value.title, numerator: value.numerator, denominator: value.denominator, style: value.style)
    }
}
