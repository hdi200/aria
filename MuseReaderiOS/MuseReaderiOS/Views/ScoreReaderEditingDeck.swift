//
//  ScoreReaderEditingDeck.swift
//  MuseReaderiOS
//

import SwiftUI

struct ScoreReaderEditorRail: View {
    let editingState: ScoreEditingState
    let isBusy: Bool
    let selectModeAction: () -> Void
    let noteInputModeAction: () -> Void
    let applyDurationAction: (ScoreNoteDuration) -> Void
    let toggleRestAction: () -> Void
    let deleteSelectionAction: () -> Void
    let undoAction: () -> Void
    let redoAction: () -> Void
    let saveAction: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ScoreReaderEditorRailButton(
                systemImage: "cursorarrow",
                isEnabled: !isBusy,
                isActive: !editingState.noteInputEnabled,
                accessibilityLabel: "Selection mode",
                action: selectModeAction
            )

            ScoreReaderEditorRailButton(
                systemImage: "pencil.tip.crop.circle.badge.plus",
                isEnabled: !isBusy,
                isActive: editingState.noteInputEnabled,
                accessibilityLabel: "Note input mode",
                action: noteInputModeAction
            )

            ScoreReaderEditorRailDivider()

            ForEach(ScoreNoteDuration.allCases) { duration in
                ScoreReaderDurationRailButton(
                    duration: duration,
                    isSelected: editingState.duration == duration,
                    isEnabled: !isBusy,
                    action: { applyDurationAction(duration) }
                )
            }

            ScoreReaderEditorRailDivider()

            ScoreReaderEditorRailButton(
                systemImage: editingState.noteInputInsertsRests ? "pause.rectangle.fill" : "music.note",
                isEnabled: !isBusy,
                isActive: editingState.noteInputInsertsRests,
                accessibilityLabel: editingState.noteInputInsertsRests ? "Rest mode enabled" : "Note mode enabled",
                action: toggleRestAction
            )

            ScoreReaderEditorRailButton(
                systemImage: "trash",
                isEnabled: editingState.canDeleteSelection && !isBusy,
                accessibilityLabel: "Delete selection",
                action: deleteSelectionAction
            )

            ScoreReaderEditorRailDivider()

            ScoreReaderEditorRailButton(
                systemImage: "arrow.uturn.backward",
                isEnabled: editingState.canUndo && !isBusy,
                accessibilityLabel: "Undo",
                action: undoAction
            )

            ScoreReaderEditorRailButton(
                systemImage: "arrow.uturn.forward",
                isEnabled: editingState.canRedo && !isBusy,
                accessibilityLabel: "Redo",
                action: redoAction
            )

            ScoreReaderEditorRailDivider()

            ScoreReaderEditorRailButton(
                systemImage: "square.and.arrow.down",
                isEnabled: !isBusy,
                accessibilityLabel: "Save score",
                action: saveAction
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.16), radius: 24, y: 12)
    }
}

struct ScoreReaderEditingDeck: View {
    @State private var preferFlats = false

    let editingState: ScoreEditingState
    let pendingPitchClass: Int?
    let isBusy: Bool
    let errorText: String?
    let setPitchClassAction: (Int, Bool) -> Void
    let semitoneShiftAction: (Int) -> Void
    let octaveShiftAction: (Int) -> Void

    var body: some View {
        VStack(spacing: 12) {
            if let errorText = errorText?.trimmedToNil {
                Text(errorText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.84))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.28), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(deckTitle)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(Color.black.opacity(0.86))

                        Text(deckSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(Color.black.opacity(0.58))
                            .lineLimit(2)
                    }

                    Spacer(minLength: 12)

                    if let selection = editingState.selection, let badgeText = selection.pitchDisplay(preferFlats: preferFlats) {
                        ScoreReaderEditorStatusBadge(
                            title: badgeText,
                            subtitle: selection.kind.displayName
                        )
                    } else if editingState.noteInputEnabled {
                        ScoreReaderEditorStatusBadge(
                            title: pitchLabel(for: pendingPitchClass),
                            subtitle: editingState.noteInputInsertsRests ? "Rest entry" : "Next note"
                        )
                    } else {
                        ScoreReaderEditorStatusBadge(
                            title: keyboardEnabled ? "Keyboard Ready" : "Pitch Locked",
                            subtitle: keyboardEnabled ? "Selected note active" : "Select a pitched note"
                        )
                    }
                }

                HStack(alignment: .top, spacing: 14) {
                    ScoreReaderEditorControlGroup(title: "Spelling") {
                        HStack(spacing: 8) {
                            ScoreReaderEditorPillToggle(
                                title: "♯",
                                isSelected: !preferFlats,
                                isEnabled: !isBusy,
                                action: { preferFlats = false }
                            )

                            ScoreReaderEditorPillToggle(
                                title: "♭",
                                isSelected: preferFlats,
                                isEnabled: !isBusy,
                                action: { preferFlats = true }
                            )
                        }
                    }

                    ScoreReaderEditorControlGroup(title: "Shift") {
                        HStack(spacing: 10) {
                            ScoreReaderEditorRoundButton(
                                systemImage: "arrow.down",
                                isEnabled: pitchEditEnabled && !isBusy,
                                accessibilityLabel: "Lower pitch by semitone",
                                action: { semitoneShiftAction(-1) }
                            )

                            ScoreReaderEditorRoundButton(
                                systemImage: "arrow.up",
                                isEnabled: pitchEditEnabled && !isBusy,
                                accessibilityLabel: "Raise pitch by semitone",
                                action: { semitoneShiftAction(1) }
                            )

                            ScoreReaderEditorRoundButton(
                                systemImage: "chevron.down.2",
                                isEnabled: pitchEditEnabled && !isBusy,
                                accessibilityLabel: "Lower pitch by octave",
                                action: { octaveShiftAction(-1) }
                            )

                            ScoreReaderEditorRoundButton(
                                systemImage: "chevron.up.2",
                                isEnabled: pitchEditEnabled && !isBusy,
                                accessibilityLabel: "Raise pitch by octave",
                                action: { octaveShiftAction(1) }
                            )
                        }
                    }
                }

                ScoreReaderPitchKeyboard(
                    useFlats: preferFlats,
                    activePitchClass: activePitchClass,
                    isEnabled: keyboardEnabled && !isBusy,
                    action: { pitchClass in
                        setPitchClassAction(pitchClass, preferFlats)
                    }
                )
                .frame(maxWidth: 760, minHeight: 96, maxHeight: 96)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: 980, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(Color.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.16), radius: 24, y: 12)
        }
    }

    private var deckTitle: String {
        if editingState.noteInputEnabled {
            return "Continuous Note Input"
        }

        if editingState.selection?.canChangePitch == true {
            return "Pitch Keyboard"
        }

        return editingState.noteInputEnabled ? "Note Input Active" : "Pitch Keyboard"
    }

    private var deckSubtitle: String {
        if editingState.noteInputEnabled {
            return "Tap the staff once to place the cursor, then keep entering notes from the keyboard."
        }

        if editingState.selection?.canChangePitch == true {
            return "Retune the selected note from the keyboard, or nudge it by semitone and octave."
        }

        return "Select a pitched note to activate the bottom keyboard."
    }

    private var keyboardEnabled: Bool {
        editingState.noteInputEnabled
        || editingState.selection?.canChangePitch == true
        || editingState.selection?.kind == .rest
        || editingState.selection?.kind == .measure
    }

    private var pitchEditEnabled: Bool {
        editingState.selection?.canChangePitch == true
        || editingState.selection?.kind == .measure
    }

    private var activePitchClass: Int? {
        editingState.noteInputEnabled ? pendingPitchClass : editingState.selection?.pitchClass
    }

    private func pitchLabel(for pitchClass: Int?) -> String {
        guard let pitchClass else {
            return "Choose Pitch"
        }

        return ScoreReaderPitchKeyboard.label(for: pitchClass, useFlats: preferFlats)
    }
}

struct ScoreReaderEditorControlGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.black.opacity(0.42))
                .tracking(0.8)

            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(red: 0.96, green: 0.97, blue: 0.99), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct ScoreReaderEditorStatusBadge: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(red: 0.29, green: 0.31, blue: 0.83))

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(Color.black.opacity(0.5))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(red: 0.92, green: 0.94, blue: 1.0), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct ScoreReaderEditorPillToggle: View {
    let title: String
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(isSelected ? .white : Color.black.opacity(0.72))
                .frame(width: 46, height: 42)
                .background(
                    isSelected
                        ? Color(red: 0.33, green: 0.34, blue: 0.87)
                        : Color.white,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.48)
        .disabled(!isEnabled)
    }
}

struct ScoreReaderDurationRailButton: View {
    let duration: ScoreNoteDuration
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(duration.shortLabel)
                .font(.caption.weight(.bold))
                .foregroundStyle(isSelected ? .white : Color.black.opacity(0.70))
                .frame(width: 52, height: 34)
                .background(
                    isSelected
                        ? Color(red: 0.33, green: 0.34, blue: 0.87)
                        : Color(red: 0.96, green: 0.97, blue: 0.99),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.48)
        .disabled(!isEnabled)
    }
}

struct ScoreReaderEditorRailDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.black.opacity(0.10))
            .frame(width: 34, height: 1)
    }
}

struct ScoreReaderEditorRailButton: View {
    let systemImage: String
    let isEnabled: Bool
    var isActive = false
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isActive ? .white : Color.black.opacity(0.68))
                .frame(width: 46, height: 46)
                .background(
                    isActive
                        ? Color(red: 0.33, green: 0.34, blue: 0.87)
                        : Color(red: 0.96, green: 0.97, blue: 0.99),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct ScoreReaderEditorRoundButton: View {
    let systemImage: String
    let isEnabled: Bool
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.black.opacity(0.76))
                .frame(width: 42, height: 42)
                .background(Color.white, in: Circle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.40)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct ScoreReaderPitchKeyboard: View {
    let useFlats: Bool
    let activePitchClass: Int?
    let isEnabled: Bool
    let action: (Int) -> Void

    private let naturalPitchClasses = [0, 2, 4, 5, 7, 9, 11]
    private let sharpPitchClasses = [(pitchClass: 1, slot: 0), (pitchClass: 3, slot: 1), (pitchClass: 6, slot: 3), (pitchClass: 8, slot: 4), (pitchClass: 10, slot: 5)]

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let naturalWidth = totalWidth / 7
            let blackWidth = naturalWidth * 0.62

            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(naturalPitchClasses, id: \.self) { pitchClass in
                        Button(action: { action(pitchClass) }) {
                            VStack {
                                Spacer()
                                Text(Self.label(for: pitchClass, useFlats: useFlats))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(activePitchClass == pitchClass ? Color(red: 0.24, green: 0.27, blue: 0.80) : Color.black.opacity(0.58))
                                    .padding(.bottom, 10)
                            }
                            .frame(width: naturalWidth, height: 96)
                            .background(
                                activePitchClass == pitchClass
                                    ? Color(red: 0.90, green: 0.92, blue: 1.0)
                                    : Color.white,
                                in: RoundedRectangle(cornerRadius: 0, style: .continuous)
                            )
                            .overlay(alignment: .trailing) {
                                Rectangle()
                                    .fill(Color.black.opacity(0.08))
                                    .frame(width: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!isEnabled)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                ForEach(sharpPitchClasses, id: \.pitchClass) { item in
                    Button(action: { action(item.pitchClass) }) {
                        VStack {
                            Text(Self.label(for: item.pitchClass, useFlats: useFlats))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white.opacity(0.92))
                                .padding(.top, 10)
                            Spacer()
                        }
                        .frame(width: blackWidth, height: 60)
                        .background(
                            activePitchClass == item.pitchClass
                                ? Color(red: 0.25, green: 0.28, blue: 0.73)
                                : Color(red: 0.16, green: 0.18, blue: 0.22),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!isEnabled)
                    .offset(x: naturalWidth * CGFloat(item.slot + 1) - (blackWidth / 2))
                }
            }
            .opacity(isEnabled ? 1 : 0.48)
        }
    }

    static func label(for pitchClass: Int, useFlats: Bool) -> String {
        switch pitchClass {
        case 0: return "C"
        case 1: return useFlats ? "D♭" : "C♯"
        case 2: return "D"
        case 3: return useFlats ? "E♭" : "D♯"
        case 4: return "E"
        case 5: return "F"
        case 6: return useFlats ? "G♭" : "F♯"
        case 7: return "G"
        case 8: return useFlats ? "A♭" : "G♯"
        case 9: return "A"
        case 10: return useFlats ? "B♭" : "A♯"
        case 11: return "B"
        default: return ""
        }
    }
}

extension ScoreSelectedElementKind {
    var displayName: String {
        switch self {
        case .note:
            return "Note"
        case .rest:
            return "Rest"
        case .bar:
            return "Bar"
        case .measure:
            return "Measure"
        case .timeSignature:
            return "Time Signature"
        case .keySignature:
            return "Key Signature"
        case .tempo:
            return "Tempo"
        case .layoutBreak:
            return "Layout Break"
        case .dynamic:
            return "Dynamic"
        case .marker:
            return "Marker"
        case .text:
            return "Text"
        case .chordText:
            return "Chord Text"
        case .expressionSpanner:
            return "Expression"
        case .tie:
            return "Tie"
        case .other:
            return "Selection"
        }
    }
}

extension ScoreSelectedElement {
    var textEditorID: String {
        "\(pageIndex)-\(kind)-\(normalizedRect.x)-\(normalizedRect.y)-\(textContent ?? "")"
    }

    func pitchDisplay(preferFlats: Bool) -> String? {
        guard let pitchClass, let octave else {
            return nil
        }

        let label: String
        switch pitchClass {
        case 0: label = "C"
        case 1: label = preferFlats ? "D♭" : "C♯"
        case 2: label = "D"
        case 3: label = preferFlats ? "E♭" : "D♯"
        case 4: label = "E"
        case 5: label = "F"
        case 6: label = preferFlats ? "G♭" : "F♯"
        case 7: label = "G"
        case 8: label = preferFlats ? "A♭" : "G♯"
        case 9: label = "A"
        case 10: label = preferFlats ? "B♭" : "A♯"
        case 11: label = "B"
        default: return nil
        }

        return "\(label)\(octave)"
    }
}
