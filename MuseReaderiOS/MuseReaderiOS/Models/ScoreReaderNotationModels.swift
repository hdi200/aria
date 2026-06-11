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
}

struct TempoValue: Equatable {
    var beatUnit: TempoBeatUnit
    var bpm: Int
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
        case .noteValue(let value): return value.symbol
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
    var numerator: Int
    var denominator: Int
    var style: ScoreTimeSignatureStyle = .normal

    var id: String { "\(numerator)/\(denominator)-\(style.rawValue)" }

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
    var systemSpacingSpatium: Double

    static let a4 = ScorePageSettingsValue(
        pageWidthMillimeters: 210,
        pageHeightMillimeters: 297,
        marginMillimeters: 15,
        staffSizeMillimeters: 1.75,
        systemSpacingSpatium: 8.5
    )
}

struct ScoreLayoutOptionsValue: Equatable {
    var createMultiMeasureRests: Bool
    var hideEmptyStaves: Bool
}
