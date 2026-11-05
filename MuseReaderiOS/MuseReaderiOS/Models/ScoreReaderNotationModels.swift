import Foundation

enum TempoBeatUnit: String, CaseIterable, Identifiable {
    case quarter
    case eighth
    case half
    case dottedQuarter

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .quarter: return "♩"
        case .eighth: return "♪"
        case .half: return "𝅗𝅥"
        case .dottedQuarter: return "♩."
        }
    }

    var bravuraTextGlyph: String {
        switch self {
        case .quarter: return "\u{1D15F}"
        case .eighth: return "\u{1D160}"
        case .half: return "\u{1D15E}"
        case .dottedQuarter: return "\u{1D15F}\u{E1E7}"
        }
    }

    /// The note without its dot, for the tempo keypad (TempoBeatUnitGlyph), which draws
    /// metNoteQuarterUp and metAugmentationDot with their own spacing.
    var bravuraTextNote: String {
        self == .dottedQuarter ? "\u{ECA5}" : bravuraTextGlyph
    }

    var isDotted: Bool { self == .dottedQuarter }
}

struct TempoValue: Equatable {
    var beatUnit: TempoBeatUnit
    var bpm: Int
    var text: String = ""
}

extension TempoValue {
    /// MuseScore plainText uses SMuFL metronome glyphs. Also accept Unicode music
    /// characters from imported scores. Match the final equation, not punctuation
    /// or numbers in a description such as "Allegro, movement 2.". Imported markings may
    /// wrap the equation in parentheses, write "c." before the number, or give a range
    /// ("♩ = 112–120"); the range keeps its first number.
    init?(markingText: String) {
        let pattern = "(?s)^(.*?)\\s*\\(?\\s*([♩𝅘𝅥\\x{ECA5}♪𝅘𝅥𝅮\\x{ECA7}𝅗𝅥\\x{ECA3}])\\s*([.·\\x{ECB7}\\x{E1E7}]?)\\s*=\\s*"
            + "(?:(?:ca?|approx)\\.?\\s*)?([0-9]{1,3})(?:\\s*[-–—]\\s*[0-9]{1,3})?\\s*\\)?\\s*$"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: markingText, range: NSRange(markingText.startIndex..., in: markingText)),
              let prefixRange = Range(match.range(at: 1), in: markingText),
              let noteRange = Range(match.range(at: 2), in: markingText),
              let dotRange = Range(match.range(at: 3), in: markingText),
              let bpmRange = Range(match.range(at: 4), in: markingText),
              let bpm = Int(markingText[bpmRange]), (20...300).contains(bpm) else { return nil }
        let note = String(markingText[noteRange])
        let unit: TempoBeatUnit
        if ["𝅗𝅥", "\u{ECA3}"].contains(note) { unit = .half }
        else if ["♪", "𝅘𝅥𝅮", "\u{ECA7}"].contains(note) { unit = .eighth }
        else { unit = markingText[dotRange].isEmpty ? .quarter : .dottedQuarter }
        self.init(beatUnit: unit, bpm: bpm, text: markingText[prefixRange].trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// What the tempo editor opens with for an existing marking. A text-only marking
    /// ("Allegro") keeps its words as the description, so Done doesn't replace them with a
    /// bare equation. A marking with an equation that can't be read opens at the default.
    init(editing markingText: String) {
        if let parsed = TempoValue(markingText: markingText) {
            self = parsed
            return
        }
        let words = markingText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(beatUnit: .quarter, bpm: 112, text: words.contains("=") ? "" : words)
    }
}

enum TempoToken: Equatable, Identifiable {
    case noteValue(TempoBeatUnit)
    case equals
    case number(String)

    var id: String {
        switch self {
        case .noteValue(let value): return "note-\(value.rawValue)"
        case .equals: return "equals"
        case .number(let value): return "number-\(value)"
        }
    }

    var displayText: String {
        switch self {
        case .noteValue(let value): return value.bravuraTextGlyph
        case .equals: return "="
        case .number(let value): return value
        }
    }
}

enum ScoreTimeSignatureStyle: String, CaseIterable, Identifiable {
    case normal
    case commonTime
    case cutTime

    var id: String { rawValue }
}

struct ScoreTimeSignatureValue: Equatable, Identifiable {
    static let allowedDenominators = [1, 2, 4, 8, 16]

    var numerator: Int
    var denominator: Int
    var style: ScoreTimeSignatureStyle = .normal

    var id: String { "\(numerator)/\(denominator)-\(style.rawValue)" }

    var hasAllowedDenominator: Bool {
        Self.allowedDenominators.contains(denominator)
    }

    var title: String {
        switch style {
        case .normal: return "\(numerator)/\(denominator)"
        case .commonTime: return "Common Time"
        case .cutTime: return "Cut Time"
        }
    }
}

struct ScoreKeySignatureValue: Equatable, Identifiable {
    var title: String
    var keyValue: Int
    var isMinor: Bool

    var id: String { "\(title)-\(isMinor)-\(keyValue)" }
}

enum ScoreSignatureApplyScope: String, CaseIterable, Identifiable {
    case fromSelectedMeasure
    case fromStart

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fromSelectedMeasure: return "From Selected"
        case .fromStart: return "From Start"
        }
    }
}

struct ScorePageSettingsValue: Equatable {
    var pageWidthMillimeters: Double
    var pageHeightMillimeters: Double
    var marginMillimeters: Double
    var staffSizeMillimeters: Double
    var staffSpacingSpatium: Double
    var systemSpacingSpatium: Double

    static let a4 = ScorePageSettingsValue(
        pageWidthMillimeters: 210,
        pageHeightMillimeters: 297,
        marginMillimeters: 15,
        staffSizeMillimeters: 1.75,
        staffSpacingSpatium: 6.5,
        systemSpacingSpatium: 8.5
    )
}

struct ScoreLayoutOptionsValue: Equatable {
    var createMultiMeasureRests: Bool
    var hideEmptyStaves: Bool
}
