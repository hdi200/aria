import SwiftUI

enum ScoreAutoSystemBreaksMode: String, CaseIterable, Identifiable {
    case measuresPerSystem
    case lockCurrentLayout
    case removeExisting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .measuresPerSystem: return "Measures per system"
        case .lockCurrentLayout: return "Lock current layout"
        case .removeExisting: return "Remove auto breaks"
        }
    }
}

struct ScoreAutoSystemBreaksRequest {
    let mode: ScoreAutoSystemBreaksMode
    let measuresPerSystem: Int
}

struct ScoreReaderAutoSystemBreaksSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var mode: ScoreAutoSystemBreaksMode = .measuresPerSystem
    @State private var measuresText = "4"

    let isBusy: Bool
    let commitAction: (ScoreAutoSystemBreaksRequest) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Auto Breaks") {
                    Picker("Mode", selection: $mode) {
                        ForEach(ScoreAutoSystemBreaksMode.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }

                    if mode == .measuresPerSystem {
                        TextField("Measures per system", text: $measuresText)
                            .keyboardType(.numberPad)

                        Stepper(value: measuresBinding, in: 1...32) {
                            Text("\(validatedMeasures ?? 4) measures per system")
                        }
                    }
                }
            }
            .navigationTitle("Auto Breaks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(actionTitle) {
                        guard let request else {
                            return
                        }
                        commitAction(request)
                        dismiss()
                    }
                    .disabled(isBusy || request == nil)
                }
            }
        }
        .presentationDetents([.height(300)])
    }

    private var actionTitle: String {
        switch mode {
        case .measuresPerSystem, .lockCurrentLayout: return "Apply"
        case .removeExisting: return "Remove"
        }
    }

    private var request: ScoreAutoSystemBreaksRequest? {
        switch mode {
        case .measuresPerSystem:
            guard let validatedMeasures else {
                return nil
            }
            return ScoreAutoSystemBreaksRequest(mode: mode, measuresPerSystem: validatedMeasures)
        case .lockCurrentLayout, .removeExisting:
            return ScoreAutoSystemBreaksRequest(mode: mode, measuresPerSystem: 0)
        }
    }

    private var validatedMeasures: Int? {
        guard let count = Int(measuresText.trimmingCharacters(in: .whitespacesAndNewlines)), (1...32).contains(count) else {
            return nil
        }
        return count
    }

    private var measuresBinding: Binding<Int> {
        Binding(
            get: { validatedMeasures ?? 4 },
            set: { measuresText = "\($0)" }
        )
    }
}

struct ScoreReaderAddMeasuresSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var countText = "4"

    let isBusy: Bool
    let commitAction: (Int) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Measures") {
                    TextField("Count", text: $countText)
                        .keyboardType(.numberPad)

                    Stepper(value: countBinding, in: 1...64) {
                        Text("\(validatedCount ?? 4) measures")
                    }
                }
            }
            .navigationTitle("Add Measures")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let validatedCount {
                            commitAction(validatedCount)
                        }
                    }
                    .disabled(isBusy || validatedCount == nil)
                }
            }
        }
    }

    private var validatedCount: Int? {
        guard let count = Int(countText.trimmingCharacters(in: .whitespacesAndNewlines)), (1...64).contains(count) else {
            return nil
        }

        return count
    }

    private var countBinding: Binding<Int> {
        Binding(
            get: { validatedCount ?? 4 },
            set: { countText = "\($0)" }
        )
    }
}

struct ScoreReaderTempoEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tokens: [TempoToken] = [.noteValue(.quarter), .equals, .number("112")]

    let isBusy: Bool
    let commitAction: (TempoValue) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                HStack(spacing: 8) {
                    ForEach(tokens) { token in
                        Text(token.displayText)
                            .font(tokenFont(for: token))
                            .frame(minWidth: 34, minHeight: 38)
                            .padding(.horizontal, 8)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

                TempoKeyboard(
                    tokens: $tokens,
                    doneEnabled: parsedValue != nil && !isBusy,
                    doneAction: {
                        guard let parsedValue else { return }
                        commitAction(parsedValue)
                        dismiss()
                    }
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .navigationTitle("Tempo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(430)])
    }

    private var parsedValue: TempoValue? {
        guard
            case .noteValue(let beatUnit)? = tokens.first(where: {
                if case .noteValue = $0 { return true }
                return false
            }),
            tokens.contains(.equals),
            let numberToken = tokens.first(where: {
                if case .number = $0 { return true }
                return false
            }),
            case .number(let numberString) = numberToken,
            let bpm = Int(numberString),
            (20...300).contains(bpm)
        else {
            return nil
        }

        return TempoValue(beatUnit: beatUnit, bpm: bpm)
    }

    private func tokenFont(for token: TempoToken) -> Font {
        switch token {
        case .noteValue: return .system(size: 28, weight: .medium)
        case .equals, .number: return .system(size: 24, weight: .semibold)
        }
    }
}

private struct TempoKeyboard: View {
    @Binding var tokens: [TempoToken]
    let doneEnabled: Bool
    let doneAction: () -> Void

    var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                ForEach(TempoBeatUnit.allCases) { beatUnit in
                    key(beatUnit.symbol) { replaceNoteValue(beatUnit) }
                }
            }
            GridRow {
                ForEach(["1", "2", "3"], id: \.self) { digit in key(digit) { appendDigit(digit) } }
            }
            GridRow {
                ForEach(["4", "5", "6"], id: \.self) { digit in key(digit) { appendDigit(digit) } }
            }
            GridRow {
                ForEach(["7", "8", "9"], id: \.self) { digit in key(digit) { appendDigit(digit) } }
            }
            GridRow {
                key("=") { insertEquals() }
                key("0") { appendDigit("0") }
                key("⌫") { backspace() }
                key("Done", isEnabled: doneEnabled, action: doneAction)
            }
        }
    }

    private func key(_ title: String, isEnabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: title == "Done" ? 15 : 22, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(isEnabled ? Color(.secondarySystemBackground) : Color(.systemGray5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }

    private func replaceNoteValue(_ beatUnit: TempoBeatUnit) {
        tokens.removeAll {
            if case .noteValue = $0 { return true }
            return false
        }
        tokens.insert(.noteValue(beatUnit), at: 0)
    }

    private func insertEquals() {
        tokens.removeAll { $0 == .equals }
        let index = tokens.firstIndex {
            if case .noteValue = $0 { return true }
            return false
        }.map { $0 + 1 } ?? 0
        tokens.insert(.equals, at: min(index, tokens.count))
    }

    private func appendDigit(_ digit: String) {
        if let index = tokens.firstIndex(where: {
            if case .number = $0 { return true }
            return false
        }), case .number(let value) = tokens[index] {
            tokens[index] = .number((value + digit).prefix(3).description)
        } else {
            tokens.append(.number(digit))
        }
    }

    private func backspace() {
        guard let index = tokens.lastIndex(where: {
            if case .number = $0 { return true }
            return false
        }), case .number(let value) = tokens[index] else {
            _ = tokens.popLast()
            return
        }

        let trimmed = String(value.dropLast())
        if trimmed.isEmpty {
            tokens.remove(at: index)
        } else {
            tokens[index] = .number(trimmed)
        }
    }
}

struct ScoreReaderTimeSignatureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selected = ScoreTimeSignatureValue(numerator: 4, denominator: 4)
    @State private var customNumerator = 4
    @State private var customDenominator = 4

    let isBusy: Bool
    let commitAction: (ScoreTimeSignatureValue, ScoreSignatureApplyScope) -> Void

    private let presets = [
        ScoreTimeSignatureValue(numerator: 4, denominator: 4),
        ScoreTimeSignatureValue(numerator: 3, denominator: 4),
        ScoreTimeSignatureValue(numerator: 2, denominator: 4),
        ScoreTimeSignatureValue(numerator: 6, denominator: 8),
        ScoreTimeSignatureValue(numerator: 2, denominator: 2, style: .cutTime),
        ScoreTimeSignatureValue(numerator: 5, denominator: 4),
        ScoreTimeSignatureValue(numerator: 7, denominator: 8),
        ScoreTimeSignatureValue(numerator: 12, denominator: 8)
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                ZStack {
                    Text("Change Time Signature")
                        .font(.system(size: 20, weight: .bold))
                        .frame(maxWidth: .infinity)

                    HStack {
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close")
                    }
                }

                HStack(spacing: 0) {
                    Text("Current:  4/4")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)

                    Rectangle()
                        .fill(Color(.separator))
                        .frame(width: 1, height: 34)

                    Text("New:  \(selected.title)")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .frame(height: 64)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(.separator), lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 14) {
                    Text("Common")
                        .font(.system(size: 16, weight: .bold))

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: 4), spacing: 18) {
                        ForEach(presets) { preset in
                            pickerButton(preset.title, isSelected: selected == preset) {
                                selected = preset
                                customNumerator = preset.numerator
                                customDenominator = preset.denominator
                            }
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 14) {
                    Text("Custom")
                        .font(.system(size: 16, weight: .bold))

                    HStack(alignment: .top, spacing: 22) {
                        timeStepper(value: $customNumerator, range: 1...32, caption: "Beats per measure")

                        Text("/")
                            .font(.system(size: 24, weight: .semibold))
                            .padding(.top, 23)

                        timeStepper(value: $customDenominator, range: 1...32, caption: "Note value")
                    }
                    .onChange(of: customNumerator) { _, _ in applyCustomSelection() }
                    .onChange(of: customDenominator) { _, _ in applyCustomSelection() }

                    Text(totalDescription)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 24)

            HStack {
                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 136, height: 52)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color(.separator), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    commitAction(selected, .fromSelectedMeasure)
                    dismiss()
                } label: {
                    Text("Change")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 136, height: 52)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .opacity(isBusy ? 0.55 : 1)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 22)
        }
        .presentationDetents([.height(620), .large])
    }

    private func pickerButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(isSelected ? Color.blue.opacity(0.12) : Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSelected ? Color.blue : Color(.separator), lineWidth: isSelected ? 1.4 : 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func timeStepper(value: Binding<Int>, range: ClosedRange<Int>, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 18) {
                Text("\(value.wrappedValue)")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 64)

                VStack(spacing: 2) {
                    Button {
                        value.wrappedValue = min(value.wrappedValue + 1, range.upperBound)
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 42, height: 28)
                    }
                    .buttonStyle(.plain)

                    Button {
                        value.wrappedValue = max(value.wrappedValue - 1, range.lowerBound)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 42, height: 28)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 150, height: 60)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(.separator), lineWidth: 1)
            )

            Text(caption)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var totalDescription: String {
        "Total: \(customNumerator) \(noteValueName(for: customDenominator)) beats"
    }

    private func applyCustomSelection() {
        selected = ScoreTimeSignatureValue(numerator: customNumerator, denominator: customDenominator)
    }

    private func noteValueName(for denominator: Int) -> String {
        switch denominator {
        case 1: return "whole-note"
        case 2: return "half-note"
        case 4: return "quarter-note"
        case 8: return "eighth-note"
        case 16: return "sixteenth-note"
        case 32: return "thirty-second-note"
        default: return "1/\(denominator)-note"
        }
    }
}

struct ScoreReaderKeySignatureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selected: ScoreKeySignatureValue
    @State private var showingMinor = false

    let currentKeyValue: Int
    let isBusy: Bool
    let commitAction: (ScoreKeySignatureValue, ScoreSignatureApplyScope) -> Void

    init(
        currentKeyValue: Int,
        isBusy: Bool,
        commitAction: @escaping (ScoreKeySignatureValue, ScoreSignatureApplyScope) -> Void
    ) {
        let normalizedKey = min(max(currentKeyValue, -7), 7)
        self.currentKeyValue = normalizedKey
        self.isBusy = isBusy
        self.commitAction = commitAction
        _selected = State(initialValue: ScoreReaderKeySignatureSheet.majorKey(for: normalizedKey))
    }

    private let sharpKeys = [
        ScoreKeySignatureValue(title: "C", keyValue: 0, isMinor: false),
        ScoreKeySignatureValue(title: "G", keyValue: 1, isMinor: false),
        ScoreKeySignatureValue(title: "D", keyValue: 2, isMinor: false),
        ScoreKeySignatureValue(title: "A", keyValue: 3, isMinor: false),
        ScoreKeySignatureValue(title: "E", keyValue: 4, isMinor: false),
        ScoreKeySignatureValue(title: "B", keyValue: 5, isMinor: false),
        ScoreKeySignatureValue(title: "F#", keyValue: 6, isMinor: false),
        ScoreKeySignatureValue(title: "C#", keyValue: 7, isMinor: false)
    ]

    private let flatKeys = [
        ScoreKeySignatureValue(title: "F", keyValue: -1, isMinor: false),
        ScoreKeySignatureValue(title: "Bb", keyValue: -2, isMinor: false),
        ScoreKeySignatureValue(title: "Eb", keyValue: -3, isMinor: false),
        ScoreKeySignatureValue(title: "Ab", keyValue: -4, isMinor: false),
        ScoreKeySignatureValue(title: "Db", keyValue: -5, isMinor: false),
        ScoreKeySignatureValue(title: "Gb", keyValue: -6, isMinor: false),
        ScoreKeySignatureValue(title: "Cb", keyValue: -7, isMinor: false)
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                ZStack {
                    Text("Change Key Signature")
                        .font(.system(size: 20, weight: .bold))
                        .frame(maxWidth: .infinity)

                    HStack {
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close")
                    }
                }

                ScoreReaderKeySignaturePreviewCard(
                    keyValue: selected.keyValue,
                    keyTitle: keyPairTitle(for: selected.keyValue)
                )

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 18) {
                        Text("Key")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 76, alignment: .leading)

                        Picker("Key Mode", selection: $showingMinor) {
                            Text("Major").tag(false)
                            Text("Minor").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 240)
                    }

                    keyGrid(sharpKeys)
                    keyGrid(flatKeys)

                    Text("Preview updates as you select a key.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 28)

            Divider()

            HStack {
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 164, height: 56)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    commitAction(selected, .fromSelectedMeasure)
                    dismiss()
                } label: {
                    Text("Change")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 180, height: 56)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .opacity(isBusy ? 0.55 : 1)
            }
            .padding(24)
        }
        .presentationDetents([.height(560), .large])
    }

    private func keyGrid(_ keys: [ScoreKeySignatureValue]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 48, maximum: 56), spacing: 16)], spacing: 12) {
            ForEach(keys.map { ScoreKeySignatureValue(title: showingMinor ? minorTitle(for: $0.title) : $0.title, keyValue: $0.keyValue, isMinor: showingMinor) }) { key in
                pickerButton(key.title, isSelected: selected == key) {
                    selected = key
                }
            }
        }
    }

    private func pickerButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isSelected ? .white : .primary)
                .minimumScaleFactor(0.74)
                .lineLimit(1)
                .frame(width: 48, height: 48)
                .background(isSelected ? Color.blue : Color(.systemBackground), in: Circle())
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.blue : Color(.separator), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func minorTitle(for major: String) -> String {
        switch major {
        case "C": return "A"
        case "G": return "E"
        case "D": return "B"
        case "A": return "F#"
        case "E": return "C#"
        case "B": return "G#"
        case "F#": return "D#"
        case "C#": return "A#"
        case "F": return "D"
        case "Bb": return "G"
        case "Eb": return "C"
        case "Ab": return "F"
        case "Db": return "Bb"
        case "Gb": return "Eb"
        case "Cb": return "Ab"
        default: return "\(major) minor"
        }
    }

    private func keyPairTitle(for keyValue: Int) -> String {
        switch keyValue {
        case -7: return "Cb major / Ab minor"
        case -6: return "Gb major / Eb minor"
        case -5: return "Db major / Bb minor"
        case -4: return "Ab major / F minor"
        case -3: return "Eb major / C minor"
        case -2: return "Bb major / G minor"
        case -1: return "F major / D minor"
        case 0: return "C major / A minor"
        case 1: return "G major / E minor"
        case 2: return "D major / B minor"
        case 3: return "A major / F# minor"
        case 4: return "E major / C# minor"
        case 5: return "B major / G# minor"
        case 6: return "F# major / D# minor"
        case 7: return "C# major / A# minor"
        default: return "C major / A minor"
        }
    }

    private static func majorKey(for keyValue: Int) -> ScoreKeySignatureValue {
        switch keyValue {
        case -7: return ScoreKeySignatureValue(title: "Cb", keyValue: -7, isMinor: false)
        case -6: return ScoreKeySignatureValue(title: "Gb", keyValue: -6, isMinor: false)
        case -5: return ScoreKeySignatureValue(title: "Db", keyValue: -5, isMinor: false)
        case -4: return ScoreKeySignatureValue(title: "Ab", keyValue: -4, isMinor: false)
        case -3: return ScoreKeySignatureValue(title: "Eb", keyValue: -3, isMinor: false)
        case -2: return ScoreKeySignatureValue(title: "Bb", keyValue: -2, isMinor: false)
        case -1: return ScoreKeySignatureValue(title: "F", keyValue: -1, isMinor: false)
        case 1: return ScoreKeySignatureValue(title: "G", keyValue: 1, isMinor: false)
        case 2: return ScoreKeySignatureValue(title: "D", keyValue: 2, isMinor: false)
        case 3: return ScoreKeySignatureValue(title: "A", keyValue: 3, isMinor: false)
        case 4: return ScoreKeySignatureValue(title: "E", keyValue: 4, isMinor: false)
        case 5: return ScoreKeySignatureValue(title: "B", keyValue: 5, isMinor: false)
        case 6: return ScoreKeySignatureValue(title: "F#", keyValue: 6, isMinor: false)
        case 7: return ScoreKeySignatureValue(title: "C#", keyValue: 7, isMinor: false)
        default: return ScoreKeySignatureValue(title: "C", keyValue: 0, isMinor: false)
        }
    }
}

private struct ScoreReaderKeySignaturePreviewCard: View {
    let keyValue: Int
    let keyTitle: String

    var body: some View {
        HStack(spacing: 28) {
            ZStack(alignment: .leading) {
                StaffLines()
                    .stroke(Color.secondary.opacity(0.7), lineWidth: 1)
                    .frame(height: 74)

                Text("𝄞")
                    .font(.system(size: 80, weight: .regular))
                    .offset(x: 2, y: -1)

                ForEach(Array(accidentals.enumerated()), id: \.offset) { index, accidental in
                    Text(accidental.symbol)
                        .font(.system(size: 24, weight: .regular))
                        .offset(x: CGFloat(36 + (index * 12)), y: accidental.yOffset)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 92)

            VStack(alignment: .leading, spacing: 12) {
                Text(accidentalCountTitle)
                    .font(.system(size: 15, weight: .semibold))
                Text(keyTitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 190, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(.separator), lineWidth: 1)
        )
    }

    private var accidentalCountTitle: String {
        let count = abs(keyValue)
        guard count > 0 else {
            return "No sharps or flats"
        }
        return "\(count) \(keyValue > 0 ? "sharp" : "flat")\(count == 1 ? "" : "s")"
    }

    private var accidentals: [KeySignatureAccidental] {
        guard keyValue != 0 else {
            return []
        }

        let symbol = keyValue > 0 ? "♯" : "♭"
        let yOffsets: [CGFloat] = keyValue > 0
            ? [-23, -4, -28, -11, 12, -16, 8]
            : [-1, -17, 6, -12, 12, -6, 18]
        return (0..<abs(keyValue)).map { KeySignatureAccidental(symbol: symbol, yOffset: yOffsets[$0]) }
    }

    private struct KeySignatureAccidental: Identifiable {
        let id = UUID()
        let symbol: String
        let yOffset: CGFloat
    }

    private struct StaffLines: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            let spacing = rect.height / 6
            let startY = spacing
            for index in 0..<5 {
                let y = startY + (CGFloat(index) * spacing)
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: rect.width, y: y))
            }
            return path
        }
    }
}

struct ScoreReaderSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var metadata: ScoreEditableMetadata

    let isBusy: Bool
    let commitAction: (ScoreEditableMetadata) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Score") {
                    TextField("Title", text: $metadata.title)
                    TextField("Composer", text: $metadata.composer)
                    TextField("Subtitle", text: $metadata.subtitle)
                    TextField("Lyricist", text: $metadata.lyricist)
                    TextField("Arranger", text: $metadata.arranger)
                }

                Section("Initial Setup") {
                    Label("Instruments and part setup use the current score structure.", systemImage: "music.note.list")
                    Label("Initial key, time, and tempo are available from More.", systemImage: "slider.horizontal.3")
                }
            }
            .navigationTitle("Score Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        commitAction(metadata)
                        dismiss()
                    }
                    .disabled(isBusy)
                }
            }
        }
    }
}

struct ScoreReaderStaffSpacingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var staffSpacing = 6.5

    let isBusy: Bool
    let commitAction: (Double) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Staff Spacing") {
                    Slider(value: $staffSpacing, in: 3...16, step: 0.5)
                    HStack {
                        Text("Distance")
                        Spacer()
                        Text(staffSpacing.formatted(.number.precision(.fractionLength(1))))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Staff Spacing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        commitAction(staffSpacing)
                        dismiss()
                    }
                    .disabled(isBusy)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct ScoreReaderPageSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pageSize = "A4"
    @State private var margins = 15.0
    @State private var staffSize = 1.75
    @State private var systemSpacing = 8.5
    @State private var partLayout = "Score default"

    private let pageSizes = ["A4", "Letter", "Legal"]
    private let partLayouts = ["Score default", "Compact parts", "Roomy parts"]

    let isBusy: Bool
    let commitAction: (ScorePageSettingsValue) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Page") {
                    Picker("Page size", selection: $pageSize) {
                        ForEach(pageSizes, id: \.self) { size in
                            Text(size).tag(size)
                        }
                    }
                    Stepper("Margins \(margins.formatted(.number.precision(.fractionLength(0)))) mm", value: $margins, in: 5...35, step: 1)
                }

                Section("Notation") {
                    Stepper("Staff size \(staffSize.formatted(.number.precision(.fractionLength(2)))) mm", value: $staffSize, in: 1.2...2.4, step: 0.05)
                    Stepper("System spacing \(systemSpacing.formatted(.number.precision(.fractionLength(1))))", value: $systemSpacing, in: 4...24, step: 0.5)
                }

                Section("Parts") {
                    Picker("Part layout", selection: $partLayout) {
                        ForEach(partLayouts, id: \.self) { layout in
                            Text(layout).tag(layout)
                        }
                    }
                }
            }
            .navigationTitle("Page Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        commitAction(settingsValue)
                        dismiss()
                    }
                    .disabled(isBusy)
                }
            }
        }
    }

    private var settingsValue: ScorePageSettingsValue {
        let dimensions: (Double, Double)
        switch pageSize {
        case "Letter":
            dimensions = (215.9, 279.4)
        case "Legal":
            dimensions = (215.9, 355.6)
        default:
            dimensions = (210, 297)
        }

        return ScorePageSettingsValue(
            pageWidthMillimeters: dimensions.0,
            pageHeightMillimeters: dimensions.1,
            marginMillimeters: margins,
            staffSizeMillimeters: staffSize,
            systemSpacingSpatium: systemSpacing
        )
    }
}
