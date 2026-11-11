import SwiftUI
#if !os(Android)
import UIKit
#endif

struct ScoreReaderTempoRampSheet: View {
    let writtenLoopDuration: TimeInterval
    let initialStartSpeed: Double
    let startAction: (_ start: Double, _ target: Double, _ step: Double, _ repeatsPerStep: Int) -> Void

    @Environment(\.dismiss) var dismiss
    @State var startSpeed: Double = 0.7
    @State var targetSpeed: Double = 1.0
    @State var step: Double = 0.05
    @State var repeatsPerStep = 1
    @State var didLoadInitialValue = false

    private static let speedRange: ClosedRange<Double> = 0.25...1.5
    private static let stepRange: ClosedRange<Double> = 0.01...0.25

    var body: some View {
        presentation.onAppear {
            guard !didLoadInitialValue else { return }
            didLoadInitialValue = true
            startSpeed = min(max((initialStartSpeed * 20).rounded() / 20, Self.speedRange.lowerBound), Self.speedRange.upperBound)
            if abs(initialStartSpeed - 1) < 0.001 { startSpeed = 0.7 }
        }
    }

    @ViewBuilder
    private var presentation: some View {
        #if os(Android)
        ScrollView { controls }
            .ariaSkipPresentationDetents([.height(470), .large])
        #else
        ScrollView { controls }
            .presentationDetents([.height(470), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color(uiColor: .systemBackground))
        #endif
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Tempo Ramp")
                    .font(.title3.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(Color.primary.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            VStack(spacing: 0) {
                settingRow("Starting tempo") {
                    percentStepper(value: $startSpeed, range: Self.speedRange, increment: 0.05,
                                   accessibilityName: "starting speed")
                }
                Divider()
                settingRow("Target tempo") {
                    percentStepper(value: $targetSpeed, range: Self.speedRange, increment: 0.05,
                                   accessibilityName: "target speed")
                }
                Divider()
                settingRow("Tempo step") { increaseStepper }
                Divider()
                settingRow("Increase after") { repeatStepper }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))

            if let ramp {
                rampSummary(ramp)
            } else {
                Text("Set a target above the starting tempo.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                startAction(startSpeed, targetSpeed, step, repeatsPerStep)
                dismiss()
            } label: {
                Text("Start Ramp")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(targetSpeed > startSpeed ? Color.blue : Color.gray, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(targetSpeed <= startSpeed)

            if ramp != nil {
                Text("Playback keeps looping at \(Self.percent(targetSpeed)) until you stop.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .frame(maxWidth: 500)
        .frame(maxWidth: .infinity)
    }

    private var ramp: ScoreTempoRamp? {
        guard targetSpeed > startSpeed + 0.001 else { return nil }
        return ScoreTempoRamp(baseSpeed: initialStartSpeed, startSpeed: startSpeed, targetSpeed: targetSpeed,
                              step: step, repeatsPerStep: repeatsPerStep)
    }

    private func rampSummary(_ ramp: ScoreTempoRamp) -> some View {
        let levels = (ramp.totalLoops - 1) / ramp.repeatsPerStep + 1
        let target = "Reaches \(Self.percent(ramp.targetSpeed)) on loop \(ramp.totalLoops)"
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) {
                summaryItem("repeat", title: "\(levels) tempo levels")
                Spacer(minLength: 0)
                summaryItem("clock", title: target, detail: timeEstimate(for: ramp))
            }
            VStack(alignment: .leading, spacing: 8) {
                summaryItem("repeat", title: "\(levels) tempo levels")
                summaryItem("clock", title: target, detail: timeEstimate(for: ramp))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    private func summaryItem(_ symbol: String, title: String, detail: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.subheadline)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                if let detail {
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func timeEstimate(for ramp: ScoreTempoRamp) -> String? {
        let estimate = ramp.timeToTarget(writtenLoopDuration: writtenLoopDuration)
        guard estimate > 0, estimate.isFinite else { return nil }
        let (minutes, seconds) = Int(estimate.rounded(.up)).quotientAndRemainder(dividingBy: 60)
        let time = minutes == 0 ? "\(seconds) sec" : seconds == 0 ? "\(minutes) min" : "\(minutes) min \(seconds) sec"
        return "In about \(time)"
    }

    private var increaseStepper: some View {
        percentStepper(value: $step, range: Self.stepRange, increment: 0.01,
                       accessibilityName: "tempo step", isStep: true)
    }

    private var repeatStepper: some View {
        stepper(value: repeatsPerStep == 1 ? "1 loop" : "\(repeatsPerStep) loops",
                accessibilityName: "loops per increase",
                decrease: { repeatsPerStep = max(1, repeatsPerStep - 1) },
                increase: { repeatsPerStep += 1 })
    }

    private func settingRow<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.body.weight(.medium))
            Spacer(minLength: 0)
            control()
        }
        .padding(.vertical, 3)
    }

    private func percentStepper(value: Binding<Double>, range: ClosedRange<Double>, increment: Double,
                                accessibilityName: String, isStep: Bool = false) -> some View {
        let label = isStep ? "+\(Int((value.wrappedValue * 100).rounded())) pts" : Self.percent(value.wrappedValue)
        return stepper(value: label,
                accessibilityName: accessibilityName,
                decrease: {
                    value.wrappedValue = max(range.lowerBound, ((value.wrappedValue - increment) * 100).rounded() / 100)
                }, increase: {
                    value.wrappedValue = min(range.upperBound, ((value.wrappedValue + increment) * 100).rounded() / 100)
                })
    }

    private func stepper(value: String, accessibilityName: String,
                         decrease: @escaping () -> Void, increase: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            stepButton("minus", label: "Lower \(accessibilityName)", action: decrease)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 66)
            stepButton("plus", label: "Raise \(accessibilityName)", action: increase)
        }
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 44, height: 44)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    static func percent(_ speed: Double) -> String {
        "\(Int((speed * 100).rounded()))%"
    }
}
