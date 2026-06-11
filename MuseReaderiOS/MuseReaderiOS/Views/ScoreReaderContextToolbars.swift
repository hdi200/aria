import SwiftUI

struct ScoreReaderDynamicTool: Identifiable {
    let token: String
    let title: String

    var id: String { token }
}

enum ScoreReaderDynamicTools {
    static let primary: [ScoreReaderDynamicTool] = [
        ScoreReaderDynamicTool(token: "f", title: "Forte"),
        ScoreReaderDynamicTool(token: "mf", title: "Mezzo Forte"),
        ScoreReaderDynamicTool(token: "p", title: "Piano"),
        ScoreReaderDynamicTool(token: "mp", title: "Mezzo Piano")
    ]

    static let additional: [ScoreReaderDynamicTool] = [
        ScoreReaderDynamicTool(token: "ppp", title: "Pianississimo"),
        ScoreReaderDynamicTool(token: "pp", title: "Pianissimo"),
        ScoreReaderDynamicTool(token: "ff", title: "Fortissimo"),
        ScoreReaderDynamicTool(token: "fff", title: "Fortississimo"),
        ScoreReaderDynamicTool(token: "fp", title: "Forte Piano"),
        ScoreReaderDynamicTool(token: "pf", title: "Piano Forte"),
        ScoreReaderDynamicTool(token: "sf", title: "Sforzando"),
        ScoreReaderDynamicTool(token: "sfz", title: "Sforzato"),
        ScoreReaderDynamicTool(token: "sff", title: "Sforzando Fortissimo"),
        ScoreReaderDynamicTool(token: "sffz", title: "Sforzando Fortissimo Z"),
        ScoreReaderDynamicTool(token: "sfp", title: "Sforzando Piano"),
        ScoreReaderDynamicTool(token: "rfz", title: "Rinforzando"),
        ScoreReaderDynamicTool(token: "rf", title: "Rinforzando Forte"),
        ScoreReaderDynamicTool(token: "fz", title: "Forzando")
    ]

    static let all = primary + additional
}

struct ScoreReaderArticulationTool: Identifiable {
    let token: String
    let title: String
    let symbol: String

    var id: String { token }
}

enum ScoreReaderArticulationTools {
    private static let common: [ScoreReaderArticulationTool] = [
        ScoreReaderArticulationTool(token: "Accent", title: "Accent", symbol: ">"),
        ScoreReaderArticulationTool(token: "Marcato", title: "Marcato", symbol: "^"),
        ScoreReaderArticulationTool(token: "Tenuto", title: "Tenuto", symbol: "-"),
        ScoreReaderArticulationTool(token: "Staccato", title: "Staccato", symbol: ".")
    ]

    private static let bowing: [ScoreReaderArticulationTool] = [
        ScoreReaderArticulationTool(token: "String Up", title: "String Up", symbol: "∨"),
        ScoreReaderArticulationTool(token: "String Down", title: "String Down", symbol: "П")
    ]

    static func tools(supportsBowingArticulations: Bool) -> [ScoreReaderArticulationTool] {
        supportsBowingArticulations ? common + bowing : common
    }
}

struct ScoreReaderArticulationMenuButton: View {
    let isEnabled: Bool
    var supportsBowingArticulations = false
    let addExpressionAction: (String) -> Void

    var body: some View {
        Menu {
            ForEach(ScoreReaderArticulationTools.tools(supportsBowingArticulations: supportsBowingArticulations)) { articulation in
                Button {
                    addExpressionAction(articulation.token)
                } label: {
                    Text("\(articulation.symbol)  \(articulation.title)")
                }
            }
        } label: {
            VStack(spacing: 2) {
                Text(">")
                    .font(.system(size: 21, weight: .medium))
                    .frame(height: 22)
                Text("Articulations")
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.66)
                    .frame(maxWidth: .infinity)
            }
            .foregroundStyle(Color.black.opacity(0.82))
            .frame(width: 68, height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
    }
}

struct ScoreReaderLineTool: Identifiable {
    let token: String
    let title: String
    let symbol: String

    var id: String { token }
}

enum ScoreReaderLineTools {
    static let primary: [ScoreReaderLineTool] = [
        ScoreReaderLineTool(token: "Slur", title: "Slur", symbol: "⌒"),
        ScoreReaderLineTool(token: "Crescendo", title: "Crescendo", symbol: "<"),
        ScoreReaderLineTool(token: "Decrescendo", title: "Decrescendo", symbol: ">")
    ]

    static let all: [ScoreReaderLineTool] = [
        ScoreReaderLineTool(token: "Pedal", title: "Pedal", symbol: "Ped."),
        ScoreReaderLineTool(token: "8va", title: "8va", symbol: "8va"),
        ScoreReaderLineTool(token: "8vb", title: "8vb", symbol: "8vb")
    ]
}

struct ScoreReaderLinesMenuButton: View {
    let isEnabled: Bool
    let addExpressionAction: (String) -> Void

    var body: some View {
        Menu {
            ForEach(ScoreReaderLineTools.all) { line in
                Button {
                    addExpressionAction(line.token)
                } label: {
                    Text("\(line.symbol)  \(line.title)")
                }
            }
        } label: {
            VStack(spacing: 2) {
                Text("8va")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(height: 22)
                Text("Lines")
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity)
            }
            .foregroundStyle(Color.black.opacity(0.82))
            .frame(width: 68, height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
    }
}

struct ScoreReaderKeyboardContextToolbar: View {
    let editingState: ScoreEditingState
    let pendingPitchClass: Int?
    let pendingAccidentalKind: ScoreAccidentalKind?
    let isBusy: Bool
    var isCompact = false
    let applyDurationAction: (ScoreNoteDuration) -> Void
    let toggleDotAction: () -> Void
    let toggleRestAction: () -> Void
    let toggleTieAction: () -> Void
    let addTupletAction: (Int) -> Void
    let stackedChordInputEnabled: Bool
    let toggleStackedChordInputAction: () -> Void
    let setPitchClassAction: (Int, Bool) -> Void
    let prepareAccidentalAction: (ScoreAccidentalKind) -> Void
    @Binding var preferFlats: Bool

    var body: some View {
        if isCompact {
            compactBody
        } else {
            regularBody
        }
    }

    private var regularBody: some View {
        HStack(spacing: 0) {
            ScoreReaderPaletteButton(
                stackedChordIcon: true,
                isSelected: stackedChordInputEnabled,
                isEnabled: canUseStackedChordInput,
                action: toggleStackedChordInputAction
            )
            .frame(maxWidth: .infinity)

            ScoreReaderContextDivider()

            ForEach(ScoreNoteDuration.allCases) { duration in
                ScoreReaderPaletteButton(
                    duration: duration,
                    isSelected: selectedDuration == duration,
                    isEnabled: canUseRhythmTools,
                    action: { applyDurationAction(duration) }
                )
                .frame(maxWidth: .infinity)

                if duration != ScoreNoteDuration.allCases.last {
                    ScoreReaderContextDivider()
                }
            }

            ScoreReaderContextDivider()

            ScoreReaderTupletMenuButton(
                isEnabled: canUseRhythmTools,
                action: addTupletAction
            )
            .frame(maxWidth: .infinity)

            ScoreReaderContextDivider()

            ScoreReaderPaletteButton(
                textSymbol: "\u{1D15F}.",
                title: "Dot",
                usesMusicFont: true,
                isSelected: selectedIsDotted,
                isEnabled: canUseRhythmTools,
                action: toggleDotAction
            )
            .frame(maxWidth: .infinity)

            ScoreReaderContextDivider()

            ScoreReaderPaletteButton(
                textSymbol: "\u{1D13D}",
                title: "Rest",
                usesMusicFont: true,
                glyphBaselineOffset: 7,
                isSelected: selectedIsRest,
                isEnabled: canUseRhythmTools,
                action: toggleRestAction
            )
            .frame(maxWidth: .infinity)

            ScoreReaderContextDivider()

            ScoreReaderPaletteButton(
                textSymbol: "⌒",
                title: "Tie",
                isSelected: editingState.selection?.isTiedForward == true,
                isEnabled: editingState.selection?.kind == .note && !isBusy,
                action: toggleTieAction
            )
            .frame(maxWidth: .infinity)

            ScoreReaderContextDivider()

            accidentalButton(.flat)
            ScoreReaderContextDivider()
            accidentalButton(.natural)
            ScoreReaderContextDivider()
            accidentalButton(.sharp)
        }
        .frame(maxWidth: 900, minHeight: 58)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.black.opacity(0.09), lineWidth: 0.7)
        }
    }

    private var compactBody: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ScoreReaderCompactPaletteButton(
                    stackedChordIcon: true,
                    isSelected: stackedChordInputEnabled,
                    isEnabled: canUseStackedChordInput,
                    action: toggleStackedChordInputAction
                )
                ScoreReaderContextDivider()
                    .frame(height: 38)

                ForEach(ScoreNoteDuration.allCases) { duration in
                    ScoreReaderCompactPaletteButton(
                        duration: duration,
                        isSelected: selectedDuration == duration,
                        isEnabled: canUseRhythmTools,
                        action: { applyDurationAction(duration) }
                    )

                    ScoreReaderContextDivider()
                        .frame(height: 38)
                }

                ScoreReaderCompactTupletMenuButton(
                    isEnabled: canUseRhythmTools,
                    action: addTupletAction
                )
                ScoreReaderContextDivider()
                    .frame(height: 38)

                ScoreReaderCompactPaletteButton(
                    textSymbol: "·",
                    isSelected: selectedIsDotted,
                    isEnabled: canUseRhythmTools,
                    action: toggleDotAction
                )
                ScoreReaderContextDivider()
                    .frame(height: 38)

                ScoreReaderCompactPaletteButton(
                    textSymbol: "\u{1D13D}",
                    usesMusicFont: true,
                    isSelected: selectedIsRest,
                    isEnabled: canUseRhythmTools,
                    action: toggleRestAction
                )
                ScoreReaderContextDivider()
                    .frame(height: 38)

                ScoreReaderCompactPaletteButton(
                    textSymbol: "⌒",
                    isSelected: editingState.selection?.isTiedForward == true,
                    isEnabled: editingState.selection?.kind == .note && !isBusy,
                    action: toggleTieAction
                )
                ScoreReaderContextDivider()
                    .frame(height: 38)

                compactAccidentalButton(.flat)
                ScoreReaderContextDivider()
                    .frame(height: 38)
                compactAccidentalButton(.natural)
                ScoreReaderContextDivider()
                    .frame(height: 38)
                compactAccidentalButton(.sharp)
            }
            .frame(minHeight: 52)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
    }

    private func accidentalButton(_ accidentalKind: ScoreAccidentalKind) -> some View {
        ScoreReaderPaletteButton(
            textSymbol: symbol(for: accidentalKind),
            title: title(for: accidentalKind),
            isSelected: selectedAccidental == accidentalKind,
            isEnabled: canEditPitch,
            action: { applyAccidental(accidentalKind) }
        )
        .frame(maxWidth: .infinity)
    }

    private func compactAccidentalButton(_ accidentalKind: ScoreAccidentalKind) -> some View {
        ScoreReaderCompactPaletteButton(
            textSymbol: symbol(for: accidentalKind),
            isSelected: selectedAccidental == accidentalKind,
            isEnabled: canEditPitch,
            action: { applyAccidental(accidentalKind) }
        )
    }

    private var canEditPitch: Bool {
        (
            editingState.selection?.canChangePitch == true
            || editingState.noteInputEnabled
            || editingState.selection?.kind == .rest
            || editingState.selection?.kind == .measure
        ) && !isBusy
    }

    private var canUseRhythmTools: Bool {
        (editingState.noteInputEnabled || editingState.selection != nil) && !isBusy
    }

    private var canUseStackedChordInput: Bool {
        (
            editingState.noteInputEnabled
            || editingState.selection?.kind == .note
            || editingState.selection?.kind == .rest
            || editingState.selection?.kind == .measure
        ) && !editingState.noteInputInsertsRests && !isBusy
    }

    private var selectedDuration: ScoreNoteDuration {
        editingState.noteInputEnabled ? editingState.duration : (editingState.selection?.duration ?? editingState.duration)
    }

    private var selectedIsRest: Bool {
        editingState.noteInputEnabled ? editingState.noteInputInsertsRests : editingState.selection?.kind == .rest
    }

    private var selectedIsDotted: Bool {
        editingState.noteInputEnabled ? editingState.noteInputIsDotted : editingState.selection?.isDotted == true
    }

    private var selectedAccidental: ScoreAccidentalKind? {
        editingState.noteInputEnabled ? pendingAccidentalKind : editingState.selection?.accidentalKind
    }

    private func applyAccidental(_ accidentalKind: ScoreAccidentalKind) {
        switch accidentalKind {
        case .flat:
            preferFlats = true
        case .sharp, .natural:
            preferFlats = false
        }

        if editingState.noteInputEnabled {
            prepareAccidentalAction(accidentalKind)
        } else if let pitchClass = editingState.selection?.pitchClass(for: accidentalKind) {
            setPitchClassAction(pitchClass, preferFlats)
        } else if let pitchClass = preparedPitchClass(for: accidentalKind) {
            setPitchClassAction(pitchClass, preferFlats)
        }
    }

    private func preparedPitchClass(for accidentalKind: ScoreAccidentalKind) -> Int? {
        guard let pendingPitchClass else {
            return nil
        }

        let naturalPitchClasses = [0, 2, 4, 5, 7, 9, 11]
        var bestStep = 0
        var bestDistance = Int.max
        for (step, naturalPitchClass) in naturalPitchClasses.enumerated() {
            let upwardDistance = (pendingPitchClass - naturalPitchClass + 12) % 12
            let distance = min(upwardDistance, 12 - upwardDistance)
            if distance < bestDistance {
                bestDistance = distance
                bestStep = step
            }
        }

        let accidentalOffset: Int
        switch accidentalKind {
        case .natural:
            accidentalOffset = 0
        case .sharp:
            accidentalOffset = 1
        case .flat:
            accidentalOffset = -1
        }

        return (naturalPitchClasses[bestStep] + accidentalOffset + 12) % 12
    }

    private func symbol(for accidentalKind: ScoreAccidentalKind) -> String {
        switch accidentalKind {
        case .flat:
            return "♭"
        case .natural:
            return "♮"
        case .sharp:
            return "♯"
        }
    }

    private func title(for accidentalKind: ScoreAccidentalKind) -> String {
        switch accidentalKind {
        case .flat:
            return "Flat"
        case .natural:
            return "Natural"
        case .sharp:
            return "Sharp"
        }
    }
}

struct ScoreReaderContextDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.black.opacity(0.08))
            .frame(width: 1, height: 38)
            .padding(.horizontal, 2)
    }
}

struct ScoreReaderTupletMenuButton: View {
    let isEnabled: Bool
    let action: (Int) -> Void

    var body: some View {
        Menu {
            ForEach(ScoreReaderTupletPreset.allCases) { preset in
                Button(preset.title) {
                    action(preset.count)
                }
            }
        } label: {
            VStack(spacing: 2) {
                Text("3")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(height: 22)

                Text("Tuplet")
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .frame(maxWidth: .infinity)
            }
            .foregroundStyle(Color.black.opacity(0.82))
            .frame(width: 68, height: 48)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
        .accessibilityLabel("Tuplet")
    }
}

struct ScoreReaderCompactPaletteButton: View {
    var duration: ScoreNoteDuration? = nil
    var textSymbol: String? = nil
    var stackedChordIcon = false
    var usesMusicFont = false
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let duration {
                    Text(duration.bravuraTextGlyph)
                        .font(MusicNotationFont.font(size: 23))
                } else if stackedChordIcon {
                    Image("ScoreReaderStackedChord")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 25, height: 25)
                } else if let textSymbol {
                    Text(textSymbol)
                        .font(usesMusicFont ? MusicNotationFont.font(size: 23) : .system(size: 22, weight: .semibold))
                }
            }
            .foregroundStyle(isSelected ? Color(red: 0.0, green: 0.48, blue: 1.0) : Color.black.opacity(0.82))
            .frame(width: 46, height: 46)
            .background(
                isSelected ? Color(red: 0.86, green: 0.93, blue: 1.0) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
    }
}

struct ScoreReaderCompactTupletMenuButton: View {
    let isEnabled: Bool
    let action: (Int) -> Void

    var body: some View {
        Menu {
            ForEach(ScoreReaderTupletPreset.allCases) { preset in
                Button(preset.title) {
                    action(preset.count)
                }
            }
        } label: {
            VStack(spacing: 0) {
                Text("3")
                    .font(.system(size: 18, weight: .semibold))
                    .italic()
                    .frame(height: 18)
                HStack(spacing: 0) {
                    Rectangle().frame(width: 1, height: 5)
                    Rectangle().frame(height: 1)
                    Rectangle().frame(width: 1, height: 5)
                }
                .frame(width: 24, height: 7)
            }
            .foregroundStyle(Color.black.opacity(0.82))
            .frame(width: 46, height: 46)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
        .accessibilityLabel("Tuplet")
    }
}

private enum ScoreReaderTupletPreset: Int, CaseIterable, Identifiable {
    case duplet = 2
    case triplet = 3
    case quadruplet = 4
    case quintuplet = 5
    case sextuplet = 6
    case septuplet = 7
    case octuplet = 8
    case nonuplet = 9

    var id: Int { rawValue }
    var count: Int { rawValue }

    var title: String {
        switch self {
        case .duplet: return "Duplet"
        case .triplet: return "Triplet"
        case .quadruplet: return "Quadruplet"
        case .quintuplet: return "Quintuplet"
        case .sextuplet: return "Sextuplet"
        case .septuplet: return "Septuplet"
        case .octuplet: return "Octuplet"
        case .nonuplet: return "Nonuplet"
        }
    }
}

struct ScoreReaderRepeatContextToolbar: View {
    let isEnabled: Bool
    let addRepeatJumpAction: (String) -> Void

    var body: some View {
        ScoreReaderHorizontalContextToolbar {
            ScoreReaderPaletteButton(textSymbol: "1.", title: "First ending", isSelected: false, isEnabled: isEnabled, action: { addRepeatJumpAction("First ending") })
            ScoreReaderContextDivider()
            ScoreReaderPaletteButton(textSymbol: "2.", title: "Second ending", isSelected: false, isEnabled: isEnabled, action: { addRepeatJumpAction("Second ending") })
            ScoreReaderContextDivider()
            ScoreReaderPaletteButton(textSymbol: "||:", title: "Start repeat", isSelected: false, isEnabled: isEnabled, action: { addRepeatJumpAction("Start repeat") })
            ScoreReaderContextDivider()
            ScoreReaderPaletteButton(textSymbol: ":||", title: "End repeat", isSelected: false, isEnabled: isEnabled, action: { addRepeatJumpAction("End repeat") })
            ScoreReaderContextDivider()
            ScoreReaderPaletteButton(textSymbol: "D.S.", title: "D.S. al Coda", isSelected: false, isEnabled: isEnabled, action: { addRepeatJumpAction("D.S. al Coda") })
            ScoreReaderContextDivider()
            ScoreReaderPaletteButton(textSymbol: "D.S.", title: "D.S. al Fine", isSelected: false, isEnabled: isEnabled, action: { addRepeatJumpAction("D.S. al Fine") })
            ScoreReaderContextDivider()
            ScoreReaderPaletteButton(textSymbol: "D.C.", title: "D.C. al Coda", isSelected: false, isEnabled: isEnabled, action: { addRepeatJumpAction("D.C. al Coda") })
            ScoreReaderContextDivider()
            ScoreReaderPaletteButton(textSymbol: "D.C.", title: "D.C. al Fine", isSelected: false, isEnabled: isEnabled, action: { addRepeatJumpAction("D.C. al Fine") })
            ScoreReaderContextDivider()
            ScoreReaderPaletteButton(textSymbol: "\u{E048}", title: "Coda", usesMusicFont: true, isSelected: false, isEnabled: isEnabled, action: { addRepeatJumpAction("Coda") })
            ScoreReaderContextDivider()
            ScoreReaderPaletteButton(textSymbol: "\u{E047}", title: "Segno", usesMusicFont: true, isSelected: false, isEnabled: isEnabled, action: { addRepeatJumpAction("Segno") })
        }
    }
}

struct ScoreReaderTextContextToolbar: View {
    let isEnabled: Bool
    let addTextAction: (String) -> Void
    let openChordEntryAction: () -> Void
    let openLyricsEntryAction: () -> Void
    let openTempoEditorAction: () -> Void

    var body: some View {
        ScoreReaderHorizontalContextToolbar {
            ScoreReaderPaletteButton(systemImage: "text.alignleft", title: "Staff Text", isSelected: false, isEnabled: isEnabled, action: { addTextAction("Staff Text") })
            ScoreReaderContextDivider()
            ScoreReaderPaletteButton(systemImage: "text.badge.plus", title: "System Text", isSelected: false, isEnabled: isEnabled, action: { addTextAction("System Text") })
            ScoreReaderContextDivider()
            ScoreReaderPaletteButton(textSymbol: "A", title: "Rehearsal Mark", isSelected: false, isEnabled: isEnabled, action: { addTextAction("Rehearsal Mark") })
            ScoreReaderContextDivider()
            ScoreReaderPaletteButton(textSymbol: "C7", title: "Chord Text", isSelected: false, isEnabled: isEnabled, action: openChordEntryAction)
            ScoreReaderContextDivider()
            ScoreReaderPaletteButton(textSymbol: "Ly", title: "Lyrics", isSelected: false, isEnabled: isEnabled, action: openLyricsEntryAction)
            ScoreReaderContextDivider()
            ScoreReaderPaletteButton(systemImage: "metronome", title: "Tempo", isSelected: false, isEnabled: isEnabled, action: openTempoEditorAction)
        }
    }
}

struct ScoreReaderExpressionContextToolbar: View {
    let hasSelection: Bool
    let hasNoteSelection: Bool
    let supportsBowingArticulations: Bool
    let addExpressionAction: (String) -> Void

    var body: some View {
        ScoreReaderHorizontalContextToolbar {
            ForEach(Array(ScoreReaderDynamicTools.primary.enumerated()), id: \.element.id) { index, dynamic in
                if index > 0 {
                    ScoreReaderContextDivider()
                }
                ScoreReaderPaletteButton(textSymbol: dynamic.token, title: dynamic.title, isSelected: false, isEnabled: hasSelection, action: { addExpressionAction(dynamic.token) })
            }
            ScoreReaderContextDivider()
            Menu {
                Button("Laissez vibrer") {
                    addExpressionAction("LaissezVib")
                }

                ForEach(ScoreReaderDynamicTools.additional) { dynamic in
                    Button(dynamic.title) {
                        addExpressionAction(dynamic.token)
                    }
                }
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 19, weight: .semibold))
                        .frame(height: 22)
                    Text("More")
                        .font(.system(size: 9, weight: .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity)
                }
                .foregroundStyle(Color.black.opacity(0.82))
                .frame(width: 68, height: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!hasSelection)
            ScoreReaderContextDivider()
            ForEach(ScoreReaderLineTools.primary) { line in
                ScoreReaderPaletteButton(textSymbol: line.symbol, title: line.title, isSelected: false, isEnabled: hasSelection, action: { addExpressionAction(line.token) })
                ScoreReaderContextDivider()
            }
            ScoreReaderLinesMenuButton(isEnabled: hasSelection, addExpressionAction: addExpressionAction)
            ScoreReaderContextDivider()
            ScoreReaderArticulationMenuButton(
                isEnabled: hasNoteSelection,
                supportsBowingArticulations: supportsBowingArticulations,
                addExpressionAction: addExpressionAction
            )
        }
    }
}

struct ScoreReaderLayoutContextToolbar: View {
    let isEnabled: Bool
    let canOpenAutoBreaks: Bool
    let createMultiMeasureRests: Bool
    let hideEmptyStaves: Bool
    let addLayoutBreakAction: (String) -> Void
    let removeLayoutBreakAction: () -> Void
    let updateLayoutOptionsAction: (ScoreLayoutOptionsValue) -> Void
    let openAutoBreaksAction: () -> Void
    let openStaffSpacingAction: () -> Void
    let openPageSettingsAction: () -> Void

    var body: some View {
        ScoreReaderHorizontalContextToolbar {
            ScoreReaderPaletteButton(textSymbol: "----", title: "System Break", isSelected: false, isEnabled: isEnabled, action: { addLayoutBreakAction("System Break") })
            ScoreReaderContextDivider()
            ScoreReaderPaletteButton(systemImage: "line.3.horizontal", title: "Page Break", isSelected: false, isEnabled: isEnabled, action: { addLayoutBreakAction("Page Break") })
            ScoreReaderContextDivider()
            ScoreReaderPaletteButton(systemImage: "link", title: "Keep Bars Together", isSelected: false, isEnabled: isEnabled, action: { addLayoutBreakAction("Keep Bars Together") })
            ScoreReaderContextDivider()
            ScoreReaderPaletteButton(systemImage: "lock.rectangle.stack", title: "Auto Breaks", isSelected: false, isEnabled: canOpenAutoBreaks, action: openAutoBreaksAction)
            ScoreReaderContextDivider()
            ScoreReaderPaletteButton(textSymbol: "M", title: "Multi Rest", isSelected: createMultiMeasureRests, isEnabled: canOpenAutoBreaks, action: {
                updateLayoutOptionsAction(ScoreLayoutOptionsValue(
                    createMultiMeasureRests: !createMultiMeasureRests,
                    hideEmptyStaves: hideEmptyStaves
                ))
            })
            ScoreReaderContextDivider()
            ScoreReaderPaletteButton(systemImage: "eye.slash", title: "Hide Empty", isSelected: hideEmptyStaves, isEnabled: canOpenAutoBreaks, action: {
                updateLayoutOptionsAction(ScoreLayoutOptionsValue(
                    createMultiMeasureRests: createMultiMeasureRests,
                    hideEmptyStaves: !hideEmptyStaves
                ))
            })
            ScoreReaderContextDivider()
            ScoreReaderPaletteButton(systemImage: "arrow.up.and.down", title: "Staff Spacing", isSelected: false, isEnabled: isEnabled, action: openStaffSpacingAction)
            ScoreReaderContextDivider()
            ScoreReaderPaletteButton(systemImage: "doc", title: "Page Settings", isSelected: false, isEnabled: isEnabled, action: openPageSettingsAction)
            ScoreReaderContextDivider()
            ScoreReaderPaletteButton(textSymbol: "--x--", title: "Remove Break", isSelected: false, isEnabled: isEnabled, action: removeLayoutBreakAction)
                .foregroundStyle(Color.red)
        }
    }
}

struct ScoreReaderMoreContextToolbar: View {
    let isEnabled: Bool
    let canFillWithSlashes: Bool
    let canReplaceWithRhythmicSlashes: Bool
    let openAddInstrumentAction: () -> Void
    let removeSelectedInstrumentAction: () -> Void
    let openClefEditorAction: () -> Void
    let openScoreSetupAction: () -> Void
    let openTempoEditorAction: () -> Void
    let openTimeSignatureAction: () -> Void
    let openKeySignatureAction: () -> Void
    let openPickupMeasureAction: () -> Void
    let fillSelectionWithSlashesAction: () -> Void
    let replaceSelectionWithRhythmicSlashesAction: () -> Void
    let concertPitchEnabled: Bool
    let showsConcertPitchControl: Bool
    let toggleConcertPitchAction: () -> Void

    var body: some View {
        ScoreReaderHorizontalContextToolbar {
            ScoreReaderPaletteButton(systemImage: "music.note.list", title: "Add/Remove Instrument", isSelected: false, isEnabled: isEnabled, action: openAddInstrumentAction)
            ScoreReaderContextDivider()
            ScoreReaderPaletteButton(textSymbol: "𝄞", title: "Change Clef", isSelected: false, isEnabled: isEnabled, action: openClefEditorAction)
            ScoreReaderContextDivider()
            ScoreReaderPaletteButton(systemImage: "slider.horizontal.3", title: "Score Setup", isSelected: false, isEnabled: isEnabled, action: openScoreSetupAction)
            ScoreReaderContextDivider()
            ScoreReaderPaletteButton(systemImage: "metronome", title: "Tempo", isSelected: false, isEnabled: isEnabled, action: openTempoEditorAction)
            ScoreReaderContextDivider()
            ScoreReaderPaletteButton(textSymbol: "4⁄4", title: "Time Signature", isSelected: false, isEnabled: isEnabled, action: openTimeSignatureAction)
            ScoreReaderContextDivider()
            ScoreReaderPaletteButton(textSymbol: "♯♭", title: "Key Signature", isSelected: false, isEnabled: isEnabled, action: openKeySignatureAction)
            ScoreReaderContextDivider()
            ScoreReaderPaletteButton(systemImage: "forward.end", title: "Create Pickup", isSelected: false, isEnabled: isEnabled, action: openPickupMeasureAction)
            ScoreReaderContextDivider()
            ScoreReaderPaletteButton(textSymbol: "////", title: "Fill with Slashes", isSelected: false, isEnabled: canFillWithSlashes, action: fillSelectionWithSlashesAction)
            ScoreReaderContextDivider()
            ScoreReaderPaletteButton(textSymbol: "/ /", title: "Rhythmic Notation", isSelected: false, isEnabled: canReplaceWithRhythmicSlashes, action: replaceSelectionWithRhythmicSlashesAction)
            if showsConcertPitchControl {
                ScoreReaderContextDivider()
                ScoreReaderPaletteButton(systemImage: "music.quarternote.3", title: "Concert Pitch", isSelected: concertPitchEnabled, isEnabled: isEnabled, action: toggleConcertPitchAction)
            }
        }
    }
}

struct ScoreReaderHorizontalContextToolbar<Content: View>: View {
    @Environment(\.scoreReaderCompactPanelEmbedded) private var isEmbeddedInCompactPanel
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, isEmbeddedInCompactPanel ? 4 : 10)
            .padding(.vertical, isEmbeddedInCompactPanel ? 4 : 7)
            .frame(minHeight: isEmbeddedInCompactPanel ? 44 : 44)
        }
        .frame(maxWidth: .infinity, minHeight: isEmbeddedInCompactPanel ? 52 : 58)
        .modifier(ScoreReaderHorizontalToolbarChromeModifier(isEmbedded: isEmbeddedInCompactPanel))
    }
}

private struct ScoreReaderHorizontalToolbarChromeModifier: ViewModifier {
    let isEmbedded: Bool

    func body(content: Content) -> some View {
        if isEmbedded {
            content
        } else {
            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

            content
                .background(Color.white.opacity(0.66), in: shape)
                .overlay {
                    shape
                        .stroke(Color.black.opacity(0.06), lineWidth: 0.7)
                        .allowsHitTesting(false)
                }
                .shadow(color: Color.black.opacity(0.06), radius: 9, y: 2)
        }
    }
}
