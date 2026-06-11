//
//  ScoreReaderPickupEditor.swift
//  MuseReaderiOS
//

import SwiftUI

/// Reusable pickup-measure sheet. Visual layout matches `ScoreReaderTimeSignatureSheet`
/// and `ScoreReaderKeySignatureSheet` in ScoreReaderMoreEditors.swift.
struct ScoreReaderPickupEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let context: ScorePickupEditorContext
    let isBusy: Bool
    let applyAction: (_ numerator: Int, _ denominator: Int) -> Void
    let removeAction: () -> Void
    let cancelAction: (() -> Void)?

    @State private var count: Int
    @State private var denominator: Int

    init(
        context: ScorePickupEditorContext,
        isBusy: Bool,
        applyAction: @escaping (_ numerator: Int, _ denominator: Int) -> Void,
        removeAction: @escaping () -> Void,
        cancelAction: (() -> Void)? = nil
    ) {
        self.context = context
        self.isBusy = isBusy
        self.applyAction = applyAction
        self.removeAction = removeAction
        self.cancelAction = cancelAction

        let initial = Self.initialSelection(for: context)
        _count = State(initialValue: initial.count)
        _denominator = State(initialValue: initial.denominator)
    }

    private var presets: [PickupLengthPreset] {
        Self.presets(nominalNumerator: context.nominalNumerator, nominalDenominator: context.nominalDenominator)
    }

    private var sheetTitle: String {
        "Pickup Measure"
    }

    private var currentLabel: String {
        if context.isExistingPickup, context.currentNumerator > 0, context.currentDenominator > 0 {
            return "\(context.currentNumerator)/\(context.currentDenominator)"
        }
        return "\(context.nominalNumerator)/\(context.nominalDenominator)"
    }

    private var newLabel: String {
        "\(count)/\(denominator)"
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                header

                HStack(spacing: 0) {
                    Text("Current:  \(currentLabel)")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)

                    Rectangle()
                        .fill(Color(.separator))
                        .frame(width: 1, height: 34)

                    Text("New:  \(newLabel)")
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
                            pickerButton(preset.title, isSelected: count == preset.numerator && denominator == preset.denominator) {
                                count = preset.numerator
                                denominator = preset.denominator
                            }
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 14) {
                    Text("Custom")
                        .font(.system(size: 16, weight: .bold))

                    HStack(alignment: .top, spacing: 22) {
                        pickupStepper(value: $count, range: 1...max(1, maxCount(for: denominator)), caption: "Beats in pickup")

                        Text("/")
                            .font(.system(size: 24, weight: .semibold))
                            .padding(.top, 23)

                        pickupDenominatorStepper
                    }

                    if !isValid {
                        Text("Pickup must be shorter than one full \(context.nominalNumerator)/\(context.nominalDenominator) measure.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.orange)
                    } else {
                        Text(lengthDescription)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                if context.isExistingPickup {
                    Button(role: .destructive) {
                        removeAction()
                        dismiss()
                    } label: {
                        Text("Remove Pickup Measure")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)
                    .opacity(isBusy ? 0.55 : 1)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 24)

            HStack {
                Spacer()

                Button {
                    cancelAction?()
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
                    applyAction(count, denominator)
                    dismiss()
                } label: {
                    Text(context.isExistingPickup ? "Change" : "Add")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 136, height: 52)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isBusy || !isValid)
                .opacity(isBusy || !isValid ? 0.55 : 1)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 22)
        }
        .presentationDetents([.height(context.isExistingPickup ? 640 : 580), .large])
    }

    private var header: some View {
        ZStack {
            Text(sheetTitle)
                .font(.system(size: 20, weight: .bold))
                .frame(maxWidth: .infinity)

            HStack {
                Spacer()
                Button {
                    cancelAction?()
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
    }

    private var pickupDenominatorStepper: some View {
        pickupStepper(
            value: Binding(
                get: { denominator },
                set: { newValue in
                    denominator = newValue
                    count = min(count, maxCount(for: newValue))
                }
            ),
            range: 1...32,
            caption: "Note value"
        )
    }

    private var lengthDescription: String {
        "Pickup length: \(count) \(noteValueName(for: denominator)) beat\(count == 1 ? "" : "s")"
    }

    private var isValid: Bool {
        count > 0 && count * context.nominalDenominator < denominator * context.nominalNumerator
    }

    private func maxCount(for denominator: Int) -> Int {
        let limit = (denominator * context.nominalNumerator + context.nominalDenominator - 1) / context.nominalDenominator
        return max(1, limit - 1)
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

    private func pickupStepper(value: Binding<Int>, range: ClosedRange<Int>, caption: String) -> some View {
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

    private static func initialSelection(for context: ScorePickupEditorContext) -> (count: Int, denominator: Int) {
        if context.isExistingPickup, context.currentNumerator > 0, context.currentDenominator > 0 {
            return (max(1, context.currentNumerator), context.currentDenominator)
        }
        if let first = presets(nominalNumerator: context.nominalNumerator, nominalDenominator: context.nominalDenominator).first {
            return (first.numerator, first.denominator)
        }
        return (1, min(context.nominalDenominator, 4))
    }

    private static func presets(nominalNumerator: Int, nominalDenominator: Int) -> [PickupLengthPreset] {
        let candidates: [(Int, Int)] = [
            (1, 4),
            (1, 8),
            (2, 4),
            (3, 4),
            (3, 8),
            (1, 16)
        ]

        var seen = Set<String>()
        var output: [PickupLengthPreset] = []
        for (numerator, denominator) in candidates {
            guard numerator > 0, denominator > 0 else { continue }
            guard numerator * nominalDenominator < denominator * nominalNumerator else { continue }
            let key = "\(numerator)/\(denominator)"
            guard seen.insert(key).inserted else { continue }
            output.append(PickupLengthPreset(numerator: numerator, denominator: denominator))
        }
        return output
    }
}

private struct PickupLengthPreset: Identifiable, Equatable {
    let numerator: Int
    let denominator: Int

    var id: String { "\(numerator)/\(denominator)" }
    var title: String { "\(numerator)/\(denominator)" }
}
