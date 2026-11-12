import SwiftUI
import UIKit

/// Playback & Practice: opened by tapping the metronome button. Metronome, practice speed
/// (per score, relative to the written tempo) and count-in. Changes apply as they are made.
struct ScoreReaderPracticePanel: View {
    let metronomeEnabled: Bool
    let practiceSpeed: Double
    let countInEnabled: Bool
    let countInBars: Int
    /// Written tempo at the bar playback starts from; the BPM shown is this × the speed.
    var writtenTempoBpm: Double = 0
    let setMetronomeEnabledAction: (Bool) -> Void
    let setPracticeSpeedAction: (Double) -> Void
    let setCountInBarsAction: (Int) -> Void
    let resetAction: () -> Void

    @State var draftSpeed: Double?
    /// Android: the option rows' measured width. Buttons that share a row by
    /// `maxWidth: .infinity` were briefly laid out at uneven widths each time the panel
    /// redrew; fixed widths from this avoid it.
    @State var optionRowWidth: CGFloat = 0

    /// A button's width in a row of `count`, or nil to share the row (iOS, or not measured yet).
    private func optionWidth(count: Int, spacing: CGFloat) -> CGFloat? {
        #if os(Android)
        guard optionRowWidth > 0 else { return nil }
        return ((optionRowWidth - spacing * CGFloat(count - 1)) / CGFloat(count)).rounded(.down)
        #else
        return nil
        #endif
    }

    private static let presets: [Double] = [0.5, 0.7, 0.85, 1.0]

    private var shownSpeed: Double { draftSpeed ?? practiceSpeed }

    private var selectedCountIn: Int { countInEnabled ? countInBars : 0 }

    private var usesCompactTypography: Bool {
        #if os(Android)
        false
        #else
        AriaWindowLayout.shared.usesPhoneLayout
        #endif
    }

    private var sectionFont: Font { .system(size: usesCompactTypography ? 15 : 16, weight: .semibold) }
    private var detailFont: Font { .system(size: usesCompactTypography ? 12 : 13) }
    private var optionFont: Font { .system(size: usesCompactTypography ? 13 : 14, weight: .semibold) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Playback & Practice")
                .font(.system(size: usesCompactTypography ? 16 : 17, weight: .bold))
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
                        .font(optionFont)
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
                    .font(sectionFont)
                Text("Clicks during playback")
                    .font(detailFont)
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
                        .font(sectionFont)
                    Text("For this score · relative to written tempo")
                        .font(detailFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(Self.percent(shownSpeed))
                        .font(.system(size: usesCompactTypography ? 22 : 26, weight: .bold))
                        .monospacedDigit()
                    if writtenTempoBpm > 0 {
                        Text(Self.bpm(writtenTempoBpm * shownSpeed))
                            .font(.system(size: usesCompactTypography ? 12 : 13, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityHidden(true)
            }

            Slider(
                value: Binding(
                    get: { shownSpeed },
                    set: { newValue in
                        // 5% steps, with 100% a little "sticky": it snaps there from
                        // nearby, with a tap of haptic feedback as it lands.
                        let snapped = abs(newValue - 1) < 0.04 ? 1 : (newValue * 20).rounded() / 20
                        if abs(snapped - 1) < 0.001, abs(shownSpeed - 1) >= 0.001 {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                        draftSpeed = snapped
                    }
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
            .accessibilityValue(writtenTempoBpm > 0
                ? "\(Self.percent(shownSpeed)), \(Self.bpm(writtenTempoBpm * shownSpeed))"
                : Self.percent(shownSpeed))

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
                    let width = optionWidth(count: Self.presets.count, spacing: 8)
                    Button {
                        draftSpeed = nil
                        setPracticeSpeedAction(preset)
                    } label: {
                        Text(Self.percent(preset))
                            .font(optionFont)
                            .lineLimit(1)
                            .frame(width: width)
                            .frame(maxWidth: width == nil ? .infinity : nil, minHeight: 36)
                            .foregroundStyle(isSelected ? Color.white : Color.blue)
                            .background(isSelected ? Color.blue : Color.blue.opacity(0.09),
                                        in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .accessibilitySelected(isSelected)
                }
            }
            #if os(Android)
            .frame(maxWidth: .infinity)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { optionRowWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, newWidth in
                            if abs(newWidth - optionRowWidth) > 1 { optionRowWidth = newWidth }
                        }
                }
            )
            #endif
        }
    }

    private var countInSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Count-in")
                    .font(sectionFont)
                Text("Clicks before playback starts")
                    .font(detailFont)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                ForEach([(0, "Off"), (1, "1 bar"), (2, "2 bars")], id: \.0) { option in
                    let isSelected = selectedCountIn == option.0
                    let width = optionWidth(count: 3, spacing: 6)
                    Button {
                        setCountInBarsAction(option.0)
                    } label: {
                        Text(option.1)
                            .font(optionFont)
                            .lineLimit(1)
                            .frame(width: width)
                            .frame(maxWidth: width == nil ? .infinity : nil, minHeight: 36)
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

    static func bpm(_ beatsPerMinute: Double) -> String {
        "\(Int(beatsPerMinute.rounded())) BPM"
    }
}
