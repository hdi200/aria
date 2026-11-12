import SwiftUI
import UniformTypeIdentifiers

struct ScoreReaderAutoSystemBreaksSheet: View {
    @Environment(\.dismiss) var dismiss
    @State var mode: ScoreAutoSystemBreaksMode = .measuresPerSystem
    @State var measuresText = "4"

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
                        commitAndDismiss(request)
                    }
                    .disabled(isBusy || request == nil)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(role: .destructive) {
                commitAndDismiss(removeExistingRequest)
            } label: {
                Text("Remove Existing Breaks")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.bordered)
            .disabled(isBusy)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .background(.regularMaterial)
        }
        .presentationDetents([.height(380)])
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

    private var removeExistingRequest: ScoreAutoSystemBreaksRequest {
        ScoreAutoSystemBreaksRequest(mode: .removeExisting, measuresPerSystem: 0)
    }

    private func commitAndDismiss(_ request: ScoreAutoSystemBreaksRequest) {
        commitAction(request)
        dismiss()
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
    @Environment(\.dismiss) var dismiss
    @State var countText = "4"

    let isBusy: Bool
    let commitAction: (Int) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                Text("How many measures should be added?")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)

                counterCard

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .background(Color(.systemGroupedBackground))
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

    private var counterCard: some View {
        HStack(spacing: 18) {
            adjustmentButton(systemImage: "minus", isEnabled: currentCount > 1) {
                adjustCount(by: -1)
            }

            countDisplay

            adjustmentButton(systemImage: "plus", isEnabled: currentCount < 64) {
                adjustCount(by: 1)
            }
        }
        .padding(18)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var countDisplay: some View {
        VStack(spacing: 2) {
            TextField("4", text: $countText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .frame(width: 88)

            Text("measures")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func adjustmentButton(systemImage: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 54, height: 54)
                .background(Color(.secondarySystemBackground), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.38)
    }

    private var validatedCount: Int? {
        guard let count = Int(countText.trimmingCharacters(in: .whitespacesAndNewlines)), (1...64).contains(count) else {
            return nil
        }

        return count
    }

    private var currentCount: Int {
        validatedCount ?? 4
    }

    private func adjustCount(by delta: Int) {
        countText = "\(min(max(currentCount + delta, 1), 64))"
    }
}

struct ScoreReaderTempoEditorSheet: View {
    @Environment(\.dismiss) var dismiss
    @State var beatUnit: TempoBeatUnit
    @State var bpmText: String
    @State var tempoText: String
    @State var hasStartedNumberEntry = false
    @FocusState var textIsFocused: Bool

    let isBusy: Bool
    let commitAction: (TempoValue) -> Void

    init(initialValue: TempoValue = TempoValue(beatUnit: .quarter, bpm: 112),
         isBusy: Bool,
         commitAction: @escaping (TempoValue) -> Void) {
        _beatUnit = State(initialValue: initialValue.beatUnit)
        _bpmText = State(initialValue: String(initialValue.bpm))
        _tempoText = State(initialValue: initialValue.text)
        self.isBusy = isBusy
        self.commitAction = commitAction
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    preview
                    textEntry
                    beatUnitPicker
                    if !textIsFocused {
                        numberPad
                    }
                }
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .padding(24)
            }
            .background(.regularMaterial)
            .navigationTitle("Tempo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        guard let value else { return }
                        textIsFocused = false
                        commitAction(value)
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(value == nil || isBusy)
                }
            }
        }
        #if os(Android)
        // Skip Fuse's custom ViewModifier defaults to EmptyModifier; apply the
        // presentation preference directly so the card actually resizes.
        .presentationDetents([.height(textIsFocused ? 360 : 640)])
        #else
        .modifier(ScoreReaderTempoSheetSizing(isEnteringText: textIsFocused))
        #endif
    }

    private var value: TempoValue? {
        guard let bpm = Int(bpmText), (20...300).contains(bpm) else { return nil }
        return TempoValue(beatUnit: beatUnit, bpm: bpm, text: tempoText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var preview: some View {
        HStack(spacing: 22) {
            TempoBeatUnitGlyph(beatUnit: beatUnit, size: 38)
                .frame(width: 82, height: 68)
                .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
            Text("=")
                .font(.system(size: 34, weight: .semibold))
            Text(bpmText.isEmpty ? "—" : bpmText)
                .font(.system(size: 38, weight: .bold))
                .monospacedDigit()
                .frame(width: 116, height: 68)
                .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel("Tempo BPM")
                .accessibilityValue(bpmText)
        }
        .foregroundStyle(Color.black.opacity(0.9))
        .padding(.vertical, 2)
        .onTapGesture { textIsFocused = false }
    }

    private var textEntry: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("e.g. Allegro", text: $tempoText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20))
                    .focused($textIsFocused)
                    .submitLabel(.done)
                    .onSubmit { textIsFocused = false }
                    .accessibilityLabel("Tempo text")
                if !tempoText.isEmpty {
                    Button { tempoText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.secondary)
                            .frame(width: 32, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear tempo text")
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.08), lineWidth: 1)
            }
            Text("Tempo text (optional)")
                .font(.system(size: 13))
                .foregroundStyle(Color.secondary)
                .padding(.horizontal, 2)
        }
    }

    private var beatUnitPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Beat unit")
                    .font(.system(size: 17, weight: .semibold))
                Spacer(minLength: 8)
                Text("The note value that gets the beat.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.trailing)
            }
            HStack(spacing: 10) {
                ForEach(TempoBeatUnit.allCases) { unit in
                    Button {
                        beatUnit = unit
                        textIsFocused = false
                    } label: {
                        TempoBeatUnitGlyph(beatUnit: unit, size: 31)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .foregroundStyle(beatUnit == unit ? Color.blue : Color.black.opacity(0.9))
                            .background(beatUnit == unit ? Color.blue.opacity(0.12) : Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 14))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(beatUnit == unit ? Color.blue : Color.clear, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(unit == .dottedQuarter ? "Dotted quarter note" : unit.rawValue.capitalized + " note")
                    .accessibilityValue(beatUnit == unit ? "Selected" : "")
                }
            }
        }
    }

    private var numberPad: some View {
        VStack(spacing: 8) {
            ForEach(0..<3) { row in
                HStack(spacing: 10) {
                    ForEach(1..<4) { column in
                        let digit = String(row * 3 + column)
                        numberKey(digit) { appendDigit(digit) }
                    }
                }
            }
            HStack(spacing: 10) {
                numberKey("=") {
                    textIsFocused = false
                    hasStartedNumberEntry = false
                }
                numberKey("0") { appendDigit("0") }
                Button {
                    textIsFocused = false
                    hasStartedNumberEntry = true
                    bpmText = String(bpmText.dropLast())
                } label: {
                    Image(systemName: "delete.left")
                        .font(.system(size: 24, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Erase tempo digit")
            }
            if hasStartedNumberEntry && value == nil {
                Text("Enter a tempo from 20 to 300 BPM.")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
        }
        .foregroundStyle(Color.black.opacity(0.9))
    }

    private func numberKey(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 26, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func appendDigit(_ digit: String) {
        textIsFocused = false
        bpmText = hasStartedNumberEntry ? String((bpmText + digit).prefix(3)) : digit
        hasStartedNumberEntry = true
    }
}

/// Keep the tempo editor a card when the text keyboard appears. A large detent
/// makes iPad extend the sheet down to the keyboard, leaving an empty column.
#if !os(Android)
private struct ScoreReaderTempoSheetSizing: ViewModifier {
    let isEnteringText: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), !AriaWindowLayout.shared.usesPhoneLayout {
            content.presentationSizing(ScoreReaderTempoCardSizing(isEnteringText: isEnteringText))
        } else {
            content.presentationDetents([.height(isEnteringText ? 360 : 640)])
        }
    }
}

@available(iOS 18.0, *)
private struct ScoreReaderTempoCardSizing: PresentationSizing {
    let isEnteringText: Bool

    func proposedSize(for root: PresentationSizingRoot, context: PresentationSizingContext) -> ProposedViewSize {
        ProposedViewSize(width: 600, height: isEnteringText ? 360 : 640)
    }
}
#endif

struct ScoreReaderTimeSignatureSheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @State var selected: ScoreTimeSignatureValue
    @State var customNumerator: Int
    @State var customDenominator: Int

    let currentValue: ScoreTimeSignatureValue
    let isBusy: Bool
    let commitAction: (ScoreTimeSignatureValue, ScoreSignatureApplyScope) -> Void

    init(currentValue: ScoreTimeSignatureValue = ScoreTimeSignatureValue(numerator: 4, denominator: 4),
         isBusy: Bool,
         commitAction: @escaping (ScoreTimeSignatureValue, ScoreSignatureApplyScope) -> Void) {
        self.currentValue = currentValue
        self.isBusy = isBusy
        self.commitAction = commitAction
        _selected = State(initialValue: currentValue)
        _customNumerator = State(initialValue: currentValue.numerator)
        _customDenominator = State(initialValue: currentValue.denominator)
    }

    private let presets = [
        ScoreTimeSignatureValue(numerator: 4, denominator: 4),
        ScoreTimeSignatureValue(numerator: 4, denominator: 4, style: .commonTime),
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
            ScrollView {
                VStack(alignment: .leading, spacing: contentSpacing) {
                    ZStack {
                        Text("Change Time Signature")
                            .font(.system(size: isPhoneLandscape ? 18 : 20, weight: .bold))
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
                        Text("Current:  \(currentValue.title)")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)

                        Rectangle()
                            .fill(Color(.separator))
                            .frame(width: 1, height: 34)

                        Text("New:  \(selected.title)")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .frame(height: isPhoneLandscape ? 46 : 64)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color(.separator), lineWidth: 1)
                    )

                    if isPhoneLandscape {
                        HStack(alignment: .top, spacing: 22) {
                            commonSignatureSection

                            Rectangle()
                                .fill(Color(.separator))
                                .frame(width: 1)

                            customSignatureSection(showDescription: false)
                        }
                    } else {
                        commonSignatureSection

                        Divider()

                        customSignatureSection(showDescription: true)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, isPhoneLandscape ? 10 : 20)
                .padding(.bottom, isPhoneLandscape ? 12 : 24)
            }

            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: isPhoneLandscape ? 46 : 52)
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
                        .frame(maxWidth: .infinity, minHeight: isPhoneLandscape ? 46 : 52)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canCommit)
                .opacity(canCommit ? 1 : 0.55)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, isPhoneLandscape ? 12 : 22)
        }
        .presentationDetents(timeSignatureDetents)
        .presentationCompactPopoverWhenAvailable(isPhoneLandscape)
    }

    private var customControlsRow: some View {
        HStack(alignment: .top, spacing: isPhoneLandscape ? 14 : 14) {
            customControlGroup(title: "Beats per measure") {
                stepperSegment(value: $customNumerator, range: 1...32)
            }

            if isPhoneLandscape {
                Text("/")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.primary)
                    .padding(.top, 28)
            }

            customControlGroup(title: "Note value") {
                denominatorSegment(value: $customDenominator)
            }
        }
    }

    private func customControlGroup<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: isPhoneLandscape ? 6 : 8) {
            if isPhoneLandscape {
                content()
                customControlLabel(title)
            } else {
                customControlLabel(title)
                content()
            }
        }
    }

    private var commonSignatureSection: some View {
        VStack(alignment: .leading, spacing: isPhoneLandscape ? 10 : 14) {
            Text("Common")
                .font(.system(size: 16, weight: .bold))

            AriaGrid(columns: commonGridColumns, spacing: isPhoneLandscape ? 10 : 12, items: presets) { preset in
                pickerButton(preset.title, isSelected: selected == preset) {
                    selected = preset
                    customNumerator = preset.numerator
                    customDenominator = preset.denominator
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func customSignatureSection(showDescription: Bool) -> some View {
        VStack(alignment: .leading, spacing: isPhoneLandscape ? 10 : 14) {
            Text("Custom")
                .font(.system(size: 16, weight: .bold))

            customControlsRow
                .onChangeCompatible(of: customNumerator) { _ in applyCustomSelection() }
                .onChangeCompatible(of: customDenominator) { _ in applyCustomSelection() }
                .padding(.bottom, showDescription ? 6 : 0)

            if showDescription {
                Text(totalDescription)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var commonGridColumns: [GridItem] {
        if isPhoneLandscape {
            return Array(repeating: GridItem(.flexible(), spacing: 9), count: 3)
        }
        return [GridItem(.adaptive(minimum: 112), spacing: 12)]
    }

    private var isPhone: Bool {
        horizontalSizeClass == .compact || verticalSizeClass == .compact
    }

    private var isPhoneLandscape: Bool {
        horizontalSizeClass == .compact && verticalSizeClass == .compact
    }

    private var contentSpacing: CGFloat {
        isPhoneLandscape ? 10 : 22
    }

    private var timeSignatureDetents: Set<PresentationDetent> {
        if isPhoneLandscape {
            return [.height(360)]
        }
        return isPhone ? [.large] : [.height(620), .large]
    }

    /// Like desktop, the same time signature can be added again (a restatement, or 4/4 after
    /// common time): `currentValue` doesn't carry the common/cut style, and the engine ignores
    /// an identical time signature already on that bar.
    private var canCommit: Bool {
        !isBusy
    }

    private func pickerButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity, minHeight: isPhoneLandscape ? 40 : 54)
                .background(isSelected ? Color.blue.opacity(0.12) : Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSelected ? Color.blue : Color(.separator), lineWidth: isSelected ? 1.4 : 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func customControlLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.secondary)
    }

    private func stepperSegment(value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 0) {
            Button {
                value.wrappedValue = max(value.wrappedValue - 1, range.lowerBound)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: isPhoneLandscape ? 34 : 38, height: controlHeight)
            }
            .buttonStyle(.plain)

            segmentDivider

            Text("\(value.wrappedValue)")
                .font(.system(size: isPhoneLandscape ? 20 : 22, weight: .semibold))
                .frame(width: isPhoneLandscape ? 44 : 48, height: controlHeight)

            segmentDivider

            Button {
                value.wrappedValue = min(value.wrappedValue + 1, range.upperBound)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: isPhoneLandscape ? 34 : 38, height: controlHeight)
            }
            .buttonStyle(.plain)
        }
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(.separator), lineWidth: 1)
        )
    }

    private func denominatorSegment(value: Binding<Int>) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(ScoreTimeSignatureValue.allowedDenominators.enumerated()), id: \.element) { index, denominator in
                Button {
                    value.wrappedValue = denominator
                } label: {
                    Text("\(denominator)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(value.wrappedValue == denominator ? Color.blue : Color.primary)
                        .frame(width: isPhoneLandscape ? 32 : 35, height: controlHeight)
                        .background(value.wrappedValue == denominator ? Color.blue.opacity(0.12) : Color.clear)
                }
                .buttonStyle(.plain)

                if index < ScoreTimeSignatureValue.allowedDenominators.count - 1 {
                    segmentDivider
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(.separator), lineWidth: 1)
        )
    }

    private var segmentDivider: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(width: 1, height: controlHeight)
    }

    private var controlHeight: CGFloat {
        isPhoneLandscape ? 44 : 52
    }

    private var totalDescription: String {
        "Total: \(customNumerator) \(noteValueName(for: customDenominator)) beats"
    }

    private func applyCustomSelection() {
        // Picking Common or Cut Time moves the pickers to its numbers; keep its symbol.
        guard customNumerator != selected.numerator || customDenominator != selected.denominator else {
            return
        }
        selected = ScoreTimeSignatureValue(numerator: customNumerator, denominator: customDenominator)
    }

    private func noteValueName(for denominator: Int) -> String {
        switch denominator {
        case 1: return "whole-note"
        case 2: return "half-note"
        case 4: return "quarter-note"
        case 8: return "eighth-note"
        case 16: return "sixteenth-note"
        default: return "1/\(denominator)-note"
        }
    }
}

struct ScoreReaderKeySignatureSheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @State var selected: ScoreKeySignatureValue
    @State var showingMinor = false

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
            ScrollView {
                VStack(alignment: .leading, spacing: isPhoneLandscape ? 10 : 22) {
                    currentNewKeyCard

                    if isPhoneLandscape {
                        HStack(alignment: .top, spacing: 18) {
                            VStack(alignment: .leading, spacing: 10) {
                                ScoreReaderKeySignaturePreviewCard(
                                    keyValue: selected.keyValue,
                                    keyTitle: selectedDisplayTitle,
                                    isCompactLandscape: true
                                )

                                keyTypeControl
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)

                            Rectangle()
                                .fill(Color(.separator))
                                .frame(width: 1)

                            keyChoiceSection()
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    } else {
                        ScoreReaderKeySignaturePreviewCard(
                            keyValue: selected.keyValue,
                            keyTitle: selectedDisplayTitle,
                            isCompactLandscape: false
                        )

                        keyChoiceSection(includeKeyType: true)
                    }
                }
                .padding(.horizontal, isPhoneLandscape ? 20 : 24)
                .padding(.top, isPhoneLandscape ? 10 : 14)
                .padding(.bottom, isPhoneLandscape ? 12 : 28)
            }

            Divider()

            HStack(spacing: 24) {
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: isPhoneLandscape ? 46 : 56)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
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
                        .frame(maxWidth: .infinity, minHeight: isPhoneLandscape ? 46 : 56)
                        .background(canCommit ? Color.blue : Color(.systemGray5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canCommit)
                .opacity(canCommit ? 1 : 0.78)
            }
            .padding(isPhoneLandscape ? 16 : 24)
        }
        .presentationDetents(keySignatureDetents)
        .presentationCompactPopoverWhenAvailable(isPhoneLandscape)
    }

    private var currentNewKeyCard: some View {
        HStack(spacing: 0) {
            keySummaryColumn(title: "Current", value: currentDisplayTitle)

            Rectangle()
                .fill(Color(.separator))
                .frame(width: 1, height: 48)

            keySummaryColumn(title: "New", value: selectedDisplayTitle)
        }
        .padding(.vertical, isPhoneLandscape ? 10 : 18)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator), lineWidth: 1)
        )
    }

    private func keySummaryColumn(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: isPhoneLandscape ? 13 : 14, weight: .medium))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: isPhoneLandscape ? 18 : 21, weight: .bold))
        }
        .frame(maxWidth: .infinity)
    }

    private var keyTypeControl: some View {
        HStack(spacing: isPhoneLandscape ? 12 : 18) {
            Text("Key type")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: isPhoneLandscape ? 76 : 94, alignment: .leading)

            Picker("Key Mode", selection: $showingMinor) {
                Text("Major").tag(false)
                Text("Minor").tag(true)
            }
            .pickerStyle(.segmented)
            .onChangeCompatible(of: showingMinor) { _ in syncSelectedKeyMode() }
        }
    }

    private func keyChoiceSection(includeKeyType: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: isPhoneLandscape ? 10 : 16) {
            if includeKeyType {
                keyTypeControl
            }

            VStack(alignment: .leading, spacing: isPhoneLandscape ? 6 : 10) {
                Text("Sharps")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                keyGrid(sharpKeys)
            }

            Divider()

            VStack(alignment: .leading, spacing: isPhoneLandscape ? 6 : 10) {
                Text("Flats")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                keyGrid(flatKeys)
            }
        }
    }

    private var isPhone: Bool {
        horizontalSizeClass == .compact || verticalSizeClass == .compact
    }

    private var isPhoneLandscape: Bool {
        horizontalSizeClass == .compact && verticalSizeClass == .compact
    }

    private var keySignatureDetents: Set<PresentationDetent> {
        if isPhoneLandscape {
            return [.height(380)]
        }
        return isPhone ? [.large] : [.height(560), .large]
    }

    private var canCommit: Bool {
        !isBusy && selected.keyValue != currentKeyValue
    }

    private var currentDisplayTitle: String {
        "\(Self.majorKey(for: currentKeyValue).title) major"
    }

    private var selectedDisplayTitle: String {
        "\(selected.title) \(selected.isMinor ? "minor" : "major")"
    }

    private func keyGrid(_ keys: [ScoreKeySignatureValue]) -> some View {
        AriaGrid(columns: [GridItem(.adaptive(minimum: isPhoneLandscape ? 38 : 48, maximum: isPhoneLandscape ? 42 : 56), spacing: isPhoneLandscape ? 9 : 16)], spacing: isPhoneLandscape ? 8 : 12, items: keys.map { keyValueSelection(for: $0.keyValue, minor: showingMinor) }) { key in
            pickerButton(key.title, isSelected: selected == key) {
                selected = key
            }
        }
    }

    private func pickerButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: isPhoneLandscape ? 14 : 16, weight: .semibold))
                .foregroundStyle(isSelected ? Color.blue : Color.primary)
                .minimumScaleFactor(0.74)
                .lineLimit(1)
                .frame(width: isPhoneLandscape ? 38 : 48, height: isPhoneLandscape ? 38 : 48)
                .background(isSelected ? Color.blue.opacity(0.12) : Color(.systemBackground), in: Circle())
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.blue : Color(.separator), lineWidth: 1)
                )
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: isPhoneLandscape ? 16 : 20, height: isPhoneLandscape ? 16 : 20)
                            .background(Color.blue, in: Circle())
                            .offset(x: 4, y: -4)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func syncSelectedKeyMode() {
        selected = keyValueSelection(for: selected.keyValue, minor: showingMinor)
    }

    private func keyValueSelection(for keyValue: Int, minor: Bool) -> ScoreKeySignatureValue {
        let major = Self.majorKey(for: keyValue)
        return ScoreKeySignatureValue(
            title: minor ? minorTitle(for: major.title) : major.title,
            keyValue: keyValue,
            isMinor: minor
        )
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

struct ScoreReaderKeySignaturePreviewCard: View {
    let keyValue: Int
    let keyTitle: String
    let isCompactLandscape: Bool

    var body: some View {
        HStack(spacing: isCompactLandscape ? 16 : 24) {
            ZStack(alignment: .leading) {
                StaffLines()
                    .stroke(Color.secondary.opacity(0.7), lineWidth: 1)
                    .frame(height: isCompactLandscape ? 60 : 76)

                Text("𝄞")
                    .font(.system(size: clefFontSize, weight: .regular))
                    .offset(x: 2, y: clefYOffset)

                ForEach(Array(accidentals.enumerated()), id: \.offset) { index, accidental in
                    Text(accidental.symbol)
                        .font(.system(size: isCompactLandscape ? 22 : 25, weight: .regular))
                        .offset(
                            x: CGFloat((isCompactLandscape ? accidentalStartCompact : accidentalStart) + (index * (isCompactLandscape ? 12 : 14))),
                            y: accidental.yOffset * (isCompactLandscape ? 0.82 : 1) + accidentalYShift
                        )
                }
            }
            .frame(maxWidth: .infinity, minHeight: isCompactLandscape ? 78 : 92)

            Text(keyTitle)
                .font(.system(size: isCompactLandscape ? 17 : 20, weight: .bold))
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .frame(width: isCompactLandscape ? 132 : 150, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: isCompactLandscape ? 88 : 112)
        .padding(.horizontal, 20)
        .padding(.vertical, isCompactLandscape ? 12 : 16)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator), lineWidth: 1)
        )
    }

    #if os(Android)
    // Android draws 𝄞 from its fallback music font at about 2.7 staff heights, so at
    // Apple's size it overran the staff and covered the first sharp or flat.
    private var clefFontSize: CGFloat { isCompactLandscape ? 40 : 50 }
    private var clefYOffset: CGFloat { isCompactLandscape ? 3 : 4 }
    private let accidentalStart = 46
    private let accidentalStartCompact = 40
    // Android's flat sits low: raise it half a staff space so its loop centres on the line.
    private var accidentalYShift: CGFloat { keyValue < 0 ? (isCompactLandscape ? -5 : -6) : 0 }
    #else
    private var clefFontSize: CGFloat { isCompactLandscape ? 66 : 82 }
    private let clefYOffset: CGFloat = -1
    private let accidentalStart = 42
    private let accidentalStartCompact = 36
    private let accidentalYShift: CGFloat = 0
    #endif

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

    struct KeySignatureAccidental: Identifiable {
        let id = UUID()
        let symbol: String
        let yOffset: CGFloat
    }

    struct StaffLines: Shape {
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
    @Environment(\.dismiss) var dismiss
    @State var metadata: ScoreEditableMetadata
    @State var isSaving = false
    @State var saveErrorMessage: String?

    let isBusy: Bool
    /// Reads the score's current metadata when the sheet appears. On Android the sheet's
    /// @State could keep an earlier, empty value instead of the one passed in.
    var loadAction: (() async -> ScoreEditableMetadata)? = nil
    let commitAction: (ScoreEditableMetadata) async throws -> Void

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
                // Plain rows, as iOS draws Form fields; Android otherwise boxes each one.
                .textFieldStyle(.plain)

                if let saveErrorMessage {
                    Section {
                        Text(saveErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section("Initial Setup") {
                    Label("Instruments and part setup use the current score structure.", systemImage: "music.note.list")
                    Label("Initial key, time, and tempo are available from More.", systemImage: "slider.horizontal.3")
                }
            }
            .navigationTitle("Score Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save", action: save)
                        .disabled(isBusy || isSaving)
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .task {
            guard let loadAction else { return }
            let shown = metadata
            let current = await loadAction()
            // Keep anything typed while it loaded.
            if metadata == shown {
                metadata = current
            }
        }
    }

    private func save() {
        isSaving = true
        saveErrorMessage = nil
        let metadataToSave = metadata

        Task { @MainActor in
            do {
                try await commitAction(metadataToSave)
                dismiss()
            } catch {
                saveErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isSaving = false
        }
    }
}

struct ScoreReaderPageSettingsSheet: View {
    @Environment(\.dismiss) var dismiss
    @State var pageSize: String
    @State var margins: Double
    @State var staffSize: Double
    @State var staffSpacing: Double
    @State var systemSpacing: Double

    private static let presetPageSizes = ["A4", "Letter", "Legal"]
    /// The score's own page size when it isn't a preset (A3, B4, a desktop custom size, ...),
    /// offered as "Current" so applying other settings doesn't turn the page into A4.
    private let currentPageSize: (width: Double, height: Double)?
    private let currentPageSizeName: String?

    private var pageSizes: [String] {
        Self.presetPageSizes + (currentPageSizeName.map { [$0] } ?? [])
    }

    let isBusy: Bool
    let commitAction: (ScorePageSettingsValue) -> Void

    init(
        initialValue: ScorePageSettingsValue = .a4,
        isBusy: Bool,
        commitAction: @escaping (ScorePageSettingsValue) -> Void
    ) {
        if let presetName = Self.presetPageSizeName(for: initialValue) {
            currentPageSize = nil
            currentPageSizeName = nil
            _pageSize = State(initialValue: presetName)
        } else {
            let width = initialValue.pageWidthMillimeters
            let height = initialValue.pageHeightMillimeters
            let name = "Current (\(width.formatted(.number.precision(.fractionLength(0)))) × \(height.formatted(.number.precision(.fractionLength(0)))) mm)"
            currentPageSize = (width, height)
            currentPageSizeName = name
            _pageSize = State(initialValue: name)
        }
        _margins = State(initialValue: initialValue.marginMillimeters)
        _staffSize = State(initialValue: initialValue.staffSizeMillimeters)
        _staffSpacing = State(initialValue: initialValue.staffSpacingSpatium)
        _systemSpacing = State(initialValue: initialValue.systemSpacingSpatium)
        self.isBusy = isBusy
        self.commitAction = commitAction
    }

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
                    Stepper("Staff spacing \(staffSpacing.formatted(.number.precision(.fractionLength(1))))", value: $staffSpacing, in: 3...16, step: 0.5)
                    Stepper("System spacing \(systemSpacing.formatted(.number.precision(.fractionLength(1))))", value: $systemSpacing, in: 4...24, step: 0.5)
                }
            }
            .navigationTitle("Page Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .bottomBar) {
                    Button("Reset to Defaults") {
                        applySettingsValue(.a4)
                    }
                    .disabled(isBusy)
                }
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

    private static func presetPageSizeName(for value: ScorePageSettingsValue) -> String? {
        let width = value.pageWidthMillimeters
        let height = value.pageHeightMillimeters
        if abs(width - 215.9) < 0.75 && abs(height - 279.4) < 0.75 {
            return "Letter"
        }
        if abs(width - 215.9) < 0.75 && abs(height - 355.6) < 0.75 {
            return "Legal"
        }
        if abs(width - 210) < 0.75 && abs(height - 297) < 0.75 {
            return "A4"
        }
        return nil
    }

    private func applySettingsValue(_ value: ScorePageSettingsValue) {
        pageSize = Self.presetPageSizeName(for: value) ?? "A4"
        margins = value.marginMillimeters
        staffSize = value.staffSizeMillimeters
        staffSpacing = value.staffSpacingSpatium
        systemSpacing = value.systemSpacingSpatium
    }

    private var settingsValue: ScorePageSettingsValue {
        let dimensions: (Double, Double)
        switch pageSize {
        case "Letter":
            dimensions = (215.9, 279.4)
        case "Legal":
            dimensions = (215.9, 355.6)
        default:
            if let currentPageSize, pageSize == currentPageSizeName {
                dimensions = (currentPageSize.width, currentPageSize.height)
            } else {
                dimensions = (210, 297)
            }
        }

        return ScorePageSettingsValue(
            pageWidthMillimeters: dimensions.0,
            pageHeightMillimeters: dimensions.1,
            marginMillimeters: margins,
            staffSizeMillimeters: staffSize,
            staffSpacingSpatium: staffSpacing,
            systemSpacingSpatium: systemSpacing
        )
    }
}

struct ScoreReaderInstrumentLayoutSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var parts: [ScorePart]
    let isBusy: Bool
    let setVisibilityAction: (Int, Bool) -> Void
    let moveAction: (Int, Int) -> Void
    @State var draggedPartID: String?
    @State var draggedOriginalIndex: Int?

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let metrics = layoutMetrics(for: geometry.size.width)
                ScrollView {
                    VStack(spacing: 0) {
                        instrumentLayoutHeader(metrics: metrics)
                        Divider()

                        ForEach(Array(parts.enumerated()), id: \.element.id) { index, part in
                            instrumentLayoutRow(part: part, index: index, metrics: metrics)
                                .onReorderDrag {
                                    draggedPartID = part.id
                                    draggedOriginalIndex = index
                                    return NSItemProvider(object: part.id as NSString)
                                }
                                .onDrop(
                                    of: [UTType.plainText],
                                    delegate: ScorePartLayoutDropDelegate(
                                        part: part,
                                        parts: $parts,
                                        draggedPartID: $draggedPartID,
                                        draggedOriginalIndex: $draggedOriginalIndex,
                                        didDrop: isBusy ? nil : moveAction
                                    )
                                )

                            if part.id != parts.last?.id {
                                Divider()
                                    .padding(.leading, metrics.rowHorizontalPadding + metrics.dragHandleWidth + metrics.columnSpacing)
                            }
                        }
                    }
                    .frame(width: metrics.cardWidth)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    }
                    .padding(.top, metrics.topPadding)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
                }
                .background(Color(.systemGroupedBackground).ignoresSafeArea())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .navigationTitle("Instrument Layout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func instrumentLayoutHeader(metrics: InstrumentLayoutMetrics) -> some View {
        HStack(spacing: metrics.columnSpacing) {
            Color.clear
                .frame(width: metrics.dragHandleWidth)

            Text("Instrument")
                .font(metrics.headerFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text("Visibility")
                .font(metrics.headerFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: metrics.visibilityColumnWidth, alignment: .center)
        }
        .padding(.horizontal, metrics.rowHorizontalPadding)
        .padding(.vertical, metrics.headerVerticalPadding)
    }

    private func instrumentLayoutRow(part: ScorePart, index: Int, metrics: InstrumentLayoutMetrics) -> some View {
        HStack(spacing: metrics.columnSpacing) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: metrics.dragHandleFontSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: metrics.dragHandleWidth, height: 44)
                .contentShape(Rectangle())

            Text(part.name)
                .font(metrics.nameFont)
                .foregroundStyle(.primary)
                .lineLimit(metrics.nameLineLimit)
                .minimumScaleFactor(0.86)

            Spacer(minLength: 8)

            Toggle("", isOn: visibilityBinding(for: index))
                .labelsHidden()
                .disabled(isBusy)
                .frame(width: metrics.visibilityColumnWidth, alignment: .center)
        }
        .frame(minHeight: metrics.rowHeight)
        .padding(.horizontal, metrics.rowHorizontalPadding)
        .contentShape(Rectangle())
    }

    private func layoutMetrics(for width: CGFloat) -> InstrumentLayoutMetrics {
        let compact = width < 520
        let outerPadding: CGFloat = compact ? 14 : 28
        let maxCardWidth: CGFloat = compact ? width - (outerPadding * 2) : 680
        return InstrumentLayoutMetrics(
            cardWidth: max(min(width - (outerPadding * 2), maxCardWidth), 0),
            topPadding: compact ? 14 : 22,
            rowHorizontalPadding: compact ? 14 : 20,
            headerVerticalPadding: compact ? 12 : 14,
            dragHandleWidth: compact ? 24 : 30,
            dragHandleFontSize: compact ? 13 : 14,
            columnSpacing: compact ? 10 : 12,
            visibilityColumnWidth: compact ? 96 : 132,
            rowHeight: compact ? 66 : 74,
            cornerRadius: compact ? 18 : 22,
            headerFont: .system(size: compact ? 12 : 13, weight: .semibold),
            nameFont: .system(size: compact ? 17 : 20, weight: .semibold),
            nameLineLimit: compact ? 2 : 1
        )
    }

    private func visibilityBinding(for index: Int) -> Binding<Bool> {
        Binding(
            get: {
                guard parts.indices.contains(index) else {
                    return true
                }
                return parts[index].isVisible
            },
            set: { visible in
                guard parts.indices.contains(index) else {
                    return
                }
                parts[index].isVisible = visible
                setVisibilityAction(index, visible)
            }
        )
    }
}

struct InstrumentLayoutMetrics {
    let cardWidth: CGFloat
    let topPadding: CGFloat
    let rowHorizontalPadding: CGFloat
    let headerVerticalPadding: CGFloat
    let dragHandleWidth: CGFloat
    let dragHandleFontSize: CGFloat
    let columnSpacing: CGFloat
    let visibilityColumnWidth: CGFloat
    let rowHeight: CGFloat
    let cornerRadius: CGFloat
    let headerFont: Font
    let nameFont: Font
    let nameLineLimit: Int
}

struct ScorePartLayoutDropDelegate: DropDelegate {
    let part: ScorePart
    @Binding var parts: [ScorePart]
    @Binding var draggedPartID: String?
    @Binding var draggedOriginalIndex: Int?
    let didDrop: ((Int, Int) -> Void)?

    func dropEntered(info: DropInfo) {
        guard
            let draggedPartID,
            draggedPartID != part.id,
            let sourceIndex = parts.firstIndex(where: { $0.id == draggedPartID }),
            let destinationIndex = parts.firstIndex(where: { $0.id == part.id })
        else {
            return
        }

        let proposedDestination = destinationIndex > sourceIndex ? destinationIndex + 1 : destinationIndex
        withAnimation(.snappy(duration: 0.16)) {
            parts.move(fromOffsets: IndexSet(integer: sourceIndex), toOffset: proposedDestination)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        if
            let draggedPartID,
            let originalIndex = draggedOriginalIndex,
            let finalIndex = parts.firstIndex(where: { $0.id == draggedPartID })
        {
            let destination = finalIndex > originalIndex ? finalIndex + 1 : finalIndex
            didDrop?(originalIndex, destination)
        }
        draggedPartID = nil
        draggedOriginalIndex = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

/// A tempo beat unit in Bravura Text. A dotted quarter's dot sits 0.08 em after the note,
/// as an entered dotted quarter looks; the font has no space that narrow.
struct TempoBeatUnitGlyph: View {
    let beatUnit: TempoBeatUnit
    let size: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: beatUnit.isDotted ? size * 0.08 : 0) {
            Text(beatUnit.bravuraTextNote)
            if beatUnit.isDotted {
                Text("\u{ECB7}")
            }
        }
        .font(MusicNotationFont.font(size: size))
    }
}
