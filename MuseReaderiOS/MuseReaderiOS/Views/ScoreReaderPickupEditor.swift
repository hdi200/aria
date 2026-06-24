//
//  ScoreReaderPickupEditor.swift
//  MuseReaderiOS
//

import SwiftUI

/// Reusable pickup-measure sheet. Visual layout matches `ScoreReaderTimeSignatureSheet`
/// and `ScoreReaderKeySignatureSheet` in ScoreReaderMoreEditors.swift.
struct ScoreReaderPickupEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

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
            ScrollView {
                VStack(alignment: .leading, spacing: contentSpacing) {
                    header
                    summaryCard

                    if isPhoneLandscape {
                        HStack(alignment: .top, spacing: 22) {
                            commonPickupSection

                            Rectangle()
                                .fill(Color(.separator))
                                .frame(width: 1)

                            customPickupSection(showDescription: false, showRemoveAction: context.isExistingPickup)
                        }
                    } else {
                        commonPickupSection

                        Divider()

                        customPickupSection(showDescription: true, showRemoveAction: false)

                        if context.isExistingPickup {
                            removePickupButton
                        }
                    }
                }
                .padding(.horizontal, isPhoneLandscape ? 20 : 24)
                .padding(.top, isPhoneLandscape ? 10 : 20)
                .padding(.bottom, isPhoneLandscape ? 12 : 24)
            }

            HStack(spacing: 12) {
                Button {
                    cancelAction?()
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
                    applyAction(count, denominator)
                    dismiss()
                } label: {
                    Text(context.isExistingPickup ? "Change" : "Add")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: isPhoneLandscape ? 46 : 52)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isBusy || !isValid)
                .opacity(isBusy || !isValid ? 0.55 : 1)
            }
            .padding(.horizontal, isPhoneLandscape ? 20 : 24)
            .padding(.bottom, isPhoneLandscape ? 12 : 22)
        }
        .presentationDetents(pickupDetents)
        .presentationCompactPopoverWhenAvailable(isPhoneLandscape)
    }

    private var header: some View {
        ZStack {
            Text(sheetTitle)
                .font(.system(size: isPhoneLandscape ? 18 : 20, weight: .bold))
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

    private var summaryCard: some View {
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
        .frame(height: isPhoneLandscape ? 46 : 64)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(.separator), lineWidth: 1)
        )
    }

    private var customControlsRow: some View {
        HStack(alignment: .top, spacing: 14) {
            customControlGroup(title: "Beats in pickup") {
                pickupStepper(value: $count, range: 1...max(1, maxCount(for: denominator)))
            }

            if isPhoneLandscape {
                Text("/")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.primary)
                    .padding(.top, 28)
            }

            customControlGroup(title: "Note value") {
                pickupDenominatorPicker
            }
        }
    }

    private var commonPickupSection: some View {
        VStack(alignment: .leading, spacing: isPhoneLandscape ? 10 : 14) {
            Text("Common")
                .font(.system(size: 16, weight: .bold))

            LazyVGrid(columns: commonGridColumns, spacing: isPhoneLandscape ? 10 : 12) {
                ForEach(presets) { preset in
                    pickerButton(preset.title, isSelected: count == preset.numerator && denominator == preset.denominator) {
                        count = preset.numerator
                        denominator = preset.denominator
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func customPickupSection(showDescription: Bool, showRemoveAction: Bool) -> some View {
        VStack(alignment: .leading, spacing: isPhoneLandscape ? 10 : 14) {
            Text("Custom")
                .font(.system(size: 16, weight: .bold))

            customControlsRow
                .padding(.bottom, showDescription ? 6 : 0)

            if showDescription {
                validationMessage
            }

            if showRemoveAction {
                removePickupButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var validationMessage: some View {
        Group {
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
    }

    private var removePickupButton: some View {
        Button(role: .destructive) {
            removeAction()
            dismiss()
        } label: {
            Text("Remove Pickup Measure")
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: isPhoneLandscape ? 40 : 44)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy ? 0.55 : 1)
    }

    private func customControlGroup<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: isPhoneLandscape ? 6 : 8) {
            if usesIPhoneControlCaptions {
                content()
                customControlLabel(title)
            } else {
                customControlLabel(title)
                content()
            }
        }
    }

    private var usesIPhoneControlCaptions: Bool {
        horizontalSizeClass == .compact || verticalSizeClass == .compact
    }

    private var isPhoneLandscape: Bool {
        horizontalSizeClass == .compact && verticalSizeClass == .compact
    }

    private var isPhone: Bool {
        horizontalSizeClass == .compact || verticalSizeClass == .compact
    }

    private var contentSpacing: CGFloat {
        isPhoneLandscape ? 10 : 22
    }

    private var pickupDetents: Set<PresentationDetent> {
        if isPhoneLandscape {
            return [.height(context.isExistingPickup ? 390 : 360)]
        }
        return isPhone ? [.large] : [.height(context.isExistingPickup ? 640 : 580), .large]
    }

    private var commonGridColumns: [GridItem] {
        if isPhoneLandscape {
            return Array(repeating: GridItem(.flexible(), spacing: 9), count: 3)
        }
        return [GridItem(.adaptive(minimum: 112), spacing: 12)]
    }

    private func customControlLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.secondary)
    }

    private var pickupDenominatorPicker: some View {
        HStack(spacing: 0) {
            ForEach(Array(ScoreTimeSignatureValue.allowedDenominators.enumerated()), id: \.element) { index, value in
                Button {
                    denominator = value
                    count = min(count, maxCount(for: value))
                } label: {
                    Text("\(value)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(denominator == value ? Color.blue : Color.primary)
                        .frame(width: isPhoneLandscape ? 32 : 35, height: controlHeight)
                        .background(denominator == value ? Color.blue.opacity(0.12) : Color.clear)
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

    private func pickupStepper(value: Binding<Int>, range: ClosedRange<Int>) -> some View {
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

    private var segmentDivider: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(width: 1, height: controlHeight)
    }

    private var controlHeight: CGFloat {
        isPhoneLandscape ? 44 : 52
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
