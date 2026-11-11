import SwiftUI

/// Playback & Practice: opened by tapping the metronome button. Metronome, practice speed
/// (per score, relative to the written tempo) and count-in. Changes apply as they are made.
struct ScoreReaderPracticePanel: View {
    let metronomeEnabled: Bool
    let practiceSpeed: Double
    let countInEnabled: Bool
    let countInBars: Int
    let setMetronomeEnabledAction: (Bool) -> Void
    let setPracticeSpeedAction: (Double) -> Void
    let setCountInBarsAction: (Int) -> Void
    let resetAction: () -> Void

    @State var draftSpeed: Double?

    private static let presets: [Double] = [0.5, 0.7, 0.85, 1.0]

    private var shownSpeed: Double { draftSpeed ?? practiceSpeed }

    private var selectedCountIn: Int { countInEnabled ? countInBars : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Playback & Practice")
                .font(.system(size: 17, weight: .bold))
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()

            metronomeRow
                .padding(.horizontal, 18)
                .padding(.vertical, 14)

            Divider().padding(.horizontal, 18)

            speedSection
                .padding(.horizontal, 18)
                .padding(.vertical, 14)

            Divider().padding(.horizontal, 18)

            countInSection
                .padding(.horizontal, 18)
                .padding(.vertical, 14)

            Divider().padding(.horizontal, 18)

            HStack {
                Button(action: resetAction) {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Metronome off, written tempo, no count-in")
                Spacer(minLength: 8)
                Text("Changes apply automatically")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        #if os(Android)
        .frame(maxWidth: .infinity)
        #else
        .frame(width: 340)
        #endif
    }

    private var metronomeRow: some View {
        Toggle(isOn: Binding(get: { metronomeEnabled }, set: setMetronomeEnabledAction)) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Metronome")
                    .font(.system(size: 16, weight: .semibold))
                Text("Clicks during playback")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
    }

    private var speedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Practice speed")
                        .font(.system(size: 16, weight: .semibold))
                    Text("For this score · relative to written tempo")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Text(Self.percent(shownSpeed))
                    .font(.system(size: 26, weight: .bold))
                    .monospacedDigit()
                    .accessibilityHidden(true)
            }

            Slider(
                value: Binding(
                    get: { shownSpeed },
                    set: { draftSpeed = ($0 * 20).rounded() / 20 }
                ),
                in: ScoreReaderState.practiceSpeedRange,
                onEditingChanged: { editing in
                    if !editing, let draftSpeed {
                        setPracticeSpeedAction(draftSpeed)
                        self.draftSpeed = nil
                    }
                }
            )
            .accessibilityLabel("Practice speed")
            .accessibilityValue(Self.percent(shownSpeed))

            HStack {
                Text(Self.percent(ScoreReaderState.practiceSpeedRange.lowerBound))
                Spacer()
                Text(Self.percent(ScoreReaderState.practiceSpeedRange.upperBound))
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(Self.presets, id: \.self) { preset in
                    let isSelected = abs(shownSpeed - preset) < 0.001
                    Button {
                        draftSpeed = nil
                        setPracticeSpeedAction(preset)
                    } label: {
                        Text(Self.percent(preset))
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .foregroundStyle(isSelected ? Color.white : Color.blue)
                            .background(isSelected ? Color.blue : Color.blue.opacity(0.09),
                                        in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .accessibilitySelected(isSelected)
                }
            }
        }
    }

    private var countInSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Count-in")
                    .font(.system(size: 16, weight: .semibold))
                Text("Clicks before playback starts")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                ForEach([(0, "Off"), (1, "1 bar"), (2, "2 bars")], id: \.0) { option in
                    let isSelected = selectedCountIn == option.0
                    Button {
                        setCountInBarsAction(option.0)
                    } label: {
                        Text(option.1)
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                            .background(isSelected ? Color.blue : Color.black.opacity(0.05),
                                        in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .accessibilitySelected(isSelected)
                }
            }

            Text("Count-in follows the practice speed and time signature, and plays only at the start, not on loop repeats.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    static func percent(_ speed: Double) -> String {
        "\(Int((speed * 100).rounded()))%"
    }
}
