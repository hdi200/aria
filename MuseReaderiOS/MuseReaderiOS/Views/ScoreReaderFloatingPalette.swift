import SwiftUI

struct ScoreReaderFloatingToolPalette: View {
    @State private var preferFlats = false

    let selectedToolCategory: ScoreReaderToolCategory
    let editingState: ScoreEditingState
    let pendingPitchClass: Int?
    let pendingAccidentalKind: ScoreAccidentalKind?
    let isBusy: Bool
    let applyDurationAction: (ScoreNoteDuration) -> Void
    let toggleDotAction: () -> Void
    let toggleRestAction: () -> Void
    let toggleTieAction: () -> Void
    let addTupletAction: (Int) -> Void
    let deleteSelectionAction: () -> Void
    let addTextAction: (String) -> Void
    let openChordEntryAction: () -> Void
    let openLyricsEntryAction: () -> Void
    let addRepeatJumpAction: (String) -> Void
    let addExpressionAction: (String) -> Void
    let setPitchClassAction: (Int, Bool) -> Void
    let prepareAccidentalAction: (ScoreAccidentalKind) -> Void
    let openTempoEditorAction: () -> Void

    var body: some View {
        VStack(spacing: 5) {
            switch selectedToolCategory {
            case .select:
                EmptyView()
            case .notes:
                noteTools
            case .chord:
                EmptyView()
            case .lyrics:
                EmptyView()
            case .repeats:
                repeatJumpTools
            case .text:
                textTools
            case .expression:
                expressionTools
            case .layout, .more:
                EmptyView()
            }
        }
        .frame(width: selectedToolCategory == .notes ? 52 : 92)
        .fixedSize(horizontal: true, vertical: true)
        .padding(.horizontal, 7)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 14, y: 6)
    }

    @ViewBuilder
    private var noteTools: some View {
        ForEach(ScoreNoteDuration.allCases) { duration in
            ScoreReaderPaletteButton(
                duration: duration,
                isSelected: selectedDuration == duration,
                isEnabled: canUseRhythmTools,
                action: { applyDurationAction(duration) }
            )
        }

        ScoreReaderPaletteSeparator()

        ScoreReaderTupletMenuButton(
            isEnabled: canUseRhythmTools,
            action: addTupletAction
        )

        ScoreReaderPaletteSeparator()

        ScoreReaderPaletteButton(
            textSymbol: "\u{1D15F}.",
            title: "Dot",
            usesMusicFont: true,
            isSelected: selectedIsDotted,
            isEnabled: canUseRhythmTools,
            action: toggleDotAction
        )

        ScoreReaderPaletteSeparator()

        ScoreReaderPaletteButton(
            textSymbol: "\u{1D13D}",
            title: "Rest",
            usesMusicFont: true,
            glyphBaselineOffset: 7,
            isSelected: selectedIsRest,
            isEnabled: canUseRhythmTools,
            action: toggleRestAction
        )

        ScoreReaderPaletteSeparator()

        ScoreReaderPaletteButton(textSymbol: "♭", title: "Flat", isSelected: selectedAccidental == .flat, isEnabled: canEditPitch, action: {
            preferFlats = true
            if editingState.noteInputEnabled {
                prepareAccidentalAction(.flat)
            } else if let pitchClass = editingState.selection?.pitchClass(for: .flat) {
                setPitchClassAction(pitchClass, true)
            } else if let pitchClass = preparedPitchClass(for: .flat) {
                setPitchClassAction(pitchClass, true)
            }
        })

        ScoreReaderPaletteButton(textSymbol: "♯", title: "Sharp", isSelected: selectedAccidental == .sharp, isEnabled: canEditPitch, action: {
            preferFlats = false
            if editingState.noteInputEnabled {
                prepareAccidentalAction(.sharp)
            } else if let pitchClass = editingState.selection?.pitchClass(for: .sharp) {
                setPitchClassAction(pitchClass, false)
            } else if let pitchClass = preparedPitchClass(for: .sharp) {
                setPitchClassAction(pitchClass, false)
            }
        })

        ScoreReaderPaletteButton(textSymbol: "♮", title: "Natural", isSelected: selectedAccidental == .natural, isEnabled: canEditPitch, action: {
            if editingState.noteInputEnabled {
                prepareAccidentalAction(.natural)
            } else if let pitchClass = editingState.selection?.pitchClass(for: .natural) {
                setPitchClassAction(pitchClass, false)
            } else if let pitchClass = preparedPitchClass(for: .natural) {
                setPitchClassAction(pitchClass, false)
            }
        })

        ScoreReaderPaletteSeparator()

        ScoreReaderPaletteButton(
            textSymbol: "⌒",
            title: "Tie",
            isSelected: editingState.selection?.isTiedForward == true,
            isEnabled: editingState.selection?.kind == .note && !isBusy,
            action: toggleTieAction
        )
    }

    @ViewBuilder
    private var repeatJumpTools: some View {
        ScoreReaderPaletteButton(textSymbol: "1.", title: "First ending", isSelected: false, isEnabled: hasSelection, action: { addRepeatJumpAction("First ending") })
        ScoreReaderPaletteButton(textSymbol: "2.", title: "Second ending", isSelected: false, isEnabled: hasSelection, action: { addRepeatJumpAction("Second ending") })
        ScoreReaderPaletteSeparator()
        ScoreReaderPaletteButton(textSymbol: "||:", title: "Start repeat", isSelected: false, isEnabled: hasSelection, action: { addRepeatJumpAction("Start repeat") })
        ScoreReaderPaletteButton(textSymbol: ":||", title: "End repeat", isSelected: false, isEnabled: hasSelection, action: { addRepeatJumpAction("End repeat") })
        ScoreReaderPaletteSeparator()
        ScoreReaderPaletteButton(textSymbol: "D.S.", title: "D.S. al Coda", isSelected: false, isEnabled: hasSelection, action: { addRepeatJumpAction("D.S. al Coda") })
        ScoreReaderPaletteButton(textSymbol: "D.S.", title: "D.S. al Fine", isSelected: false, isEnabled: hasSelection, action: { addRepeatJumpAction("D.S. al Fine") })
        ScoreReaderPaletteButton(textSymbol: "D.C.", title: "D.C. al Coda", isSelected: false, isEnabled: hasSelection, action: { addRepeatJumpAction("D.C. al Coda") })
        ScoreReaderPaletteButton(textSymbol: "D.C.", title: "D.C. al Fine", isSelected: false, isEnabled: hasSelection, action: { addRepeatJumpAction("D.C. al Fine") })
        ScoreReaderPaletteSeparator()
        ScoreReaderPaletteButton(textSymbol: "\u{E048}", title: "Coda", usesMusicFont: true, isSelected: false, isEnabled: hasSelection, action: { addRepeatJumpAction("Coda") })
        ScoreReaderPaletteButton(textSymbol: "\u{E047}", title: "Segno", usesMusicFont: true, isSelected: false, isEnabled: hasSelection, action: { addRepeatJumpAction("Segno") })
    }

    @ViewBuilder
    private var textTools: some View {
        ScoreReaderPaletteButton(systemImage: "text.alignleft", title: "Staff Text", isSelected: false, isEnabled: hasSelection, action: { addTextAction("Staff Text") })
        ScoreReaderPaletteButton(systemImage: "text.badge.plus", title: "System Text", isSelected: false, isEnabled: hasSelection, action: { addTextAction("System Text") })
        ScoreReaderPaletteButton(textSymbol: "A", title: "Rehearsal Mark", isSelected: false, isEnabled: hasSelection, action: { addTextAction("Rehearsal Mark") })
        ScoreReaderPaletteButton(textSymbol: "C7", title: "Chord Text", isSelected: false, isEnabled: hasSelection, action: openChordEntryAction)
        ScoreReaderPaletteButton(textSymbol: "Ly", title: "Lyrics", isSelected: false, isEnabled: hasSelection, action: openLyricsEntryAction)
        ScoreReaderPaletteButton(systemImage: "metronome", title: "Tempo", isSelected: false, isEnabled: !isBusy, action: openTempoEditorAction)
    }

    @ViewBuilder
    private var expressionTools: some View {
        ForEach(ScoreReaderDynamicTools.primary) { dynamic in
            ScoreReaderPaletteButton(textSymbol: dynamic.token, title: dynamic.title, isSelected: false, isEnabled: hasSelection, action: { addExpressionAction(dynamic.token) })
        }
        Menu {
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
        .opacity(hasSelection ? 1 : 0.42)
        ForEach(ScoreReaderLineTools.primary) { line in
            ScoreReaderPaletteButton(textSymbol: line.symbol, title: line.title, isSelected: false, isEnabled: hasSelection, action: { addExpressionAction(line.token) })
        }
        ScoreReaderLinesMenuButton(isEnabled: hasSelection, addExpressionAction: addExpressionAction)
        ScoreReaderArticulationMenuButton(
            isEnabled: hasNoteSelection,
            supportsBowingArticulations: editingState.selection?.supportsBowingArticulations == true,
            addExpressionAction: addExpressionAction
        )
    }

    private var hasSelection: Bool {
        editingState.selection != nil && !isBusy
    }

    private var hasNoteSelection: Bool {
        guard let selection = editingState.selection else {
            return false
        }

        return (selection.kind == .note || selection.kind == .measure) && !isBusy
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
}

struct ScoreReaderPaletteButton: View {
    var duration: ScoreNoteDuration? = nil
    var textSymbol: String? = nil
    var systemImage: String? = nil
    var stackedChordIcon = false
    var title: String? = nil
    var usesMusicFont = false
    var glyphBaselineOffset: CGFloat? = nil
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: title == nil ? 0 : 2) {
                Group {
                    if let duration {
                        Text(duration.bravuraTextGlyph)
                            .font(MusicNotationFont.font(size: 25))
                            .frame(width: 24, height: 26)
                    } else if stackedChordIcon {
                        Image("ScoreReaderStackedChord")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 27, height: 27)
                    } else if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 19, weight: .semibold))
                    } else if let textSymbol {
                        Text(textSymbol)
                            .font(usesMusicFont ? MusicNotationFont.font(size: musicFontSize) : .system(size: textFontSize, weight: .medium))
                            .baselineOffset(glyphBaselineOffset ?? (usesMusicFont ? 2 : 0))
                    }
                }
                .frame(height: title == nil ? 28 : 22)

                if let title {
                    Text(title)
                        .font(.system(size: 9, weight: .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity)
                }
            }
            .foregroundStyle(isSelected ? .white : Color.black.opacity(0.82))
            .frame(width: title == nil ? 38 : 68, height: title == nil ? 32 : 48)
            .background(
                isSelected ? Color(red: 0.12, green: 0.45, blue: 0.95) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
    }

    private var musicFontSize: CGFloat {
        guard usesMusicFont, let textSymbol, textSymbol.count > 1 else {
            return 25
        }

        return 21
    }

    private var textFontSize: CGFloat {
        guard let textSymbol, textSymbol.count > 1 else {
            return 21
        }

        return 16
    }
}

struct ScoreReaderPaletteSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color.black.opacity(0.14))
            .frame(width: 36, height: 0.5)
            .padding(.vertical, 3)
    }
}

struct ScoreReaderPaletteLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.black.opacity(0.54))
            .frame(width: 78, height: 20)
    }
}
