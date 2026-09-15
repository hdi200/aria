import SwiftUI
import UIKit

struct ScoreReaderMixerPanel: View {
    @ObservedObject var readerState: ScoreReaderState
    @ObservedObject private var mixerLevelMonitor: ScoreMixerLevelMonitor
    let selectedPartID: String
    let close: () -> Void

    init(readerState: ScoreReaderState, selectedPartID: String, close: @escaping () -> Void) {
        self.readerState = readerState
        self._mixerLevelMonitor = ObservedObject(wrappedValue: readerState.mixerLevelMonitor)
        self.selectedPartID = selectedPartID
        self.close = close
    }

    private var parts: [ScorePart] {
        readerState.scoreParts.filter {
            $0.isVisible && (selectedPartID == "full-score" || $0.id == selectedPartID)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if UIDevice.current.userInterfaceIdiom == .phone {
                phoneMixer
            } else {
                tabletMixer
            }
        }
        .background(.regularMaterial)
        .onAppear {
            readerState.setMixerMeteringEnabled(true)
        }
        .onDisappear {
            readerState.setMixerMeteringEnabled(false)
        }
    }

    @ViewBuilder
    private var header: some View {
        if UIDevice.current.userInterfaceIdiom == .phone {
            phoneHeader
        } else {
            tabletHeader
        }
    }

    private var phoneHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.blue)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text("Mixer")
                    .font(.system(size: 17, weight: .bold))
                Text("\(parts.count) \(parts.count == 1 ? "instrument" : "instruments")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            phoneHeaderActions
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Divider().opacity(0.7) }
    }

    private var phoneHeaderActions: some View {
        HStack(spacing: 8) {
            Button {
                readerState.updateMixer(ScoreMixerSettings())
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.blue)

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.blue)
                    .frame(width: 32, height: 32)
                    .background(Color.blue.opacity(0.10), in: Circle())
                    .overlay(Circle().strokeBorder(Color.blue.opacity(0.12), lineWidth: 1))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close mixer")
        }
    }

    private var tabletHeader: some View {
        VStack(spacing: 8) {
            Capsule()
                .fill(.secondary.opacity(0.35))
                .frame(width: 42, height: 5)

            HStack(spacing: 14) {
                Image(systemName: "waveform")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.blue)
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Mixer")
                        .font(.title2.bold())
                    Text("\(parts.count) \(parts.count == 1 ? "instrument" : "instruments") · \(readerState.session.document.primaryTitle)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 16)

                Button {
                    readerState.updateMixer(ScoreMixerSettings())
                } label: {
                    Label("Reset mix", systemImage: "arrow.counterclockwise")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.blue)

                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.blue)
                        .frame(width: 34, height: 34)
                        .background(Color.blue.opacity(0.10), in: Circle())
                        .overlay(Circle().strokeBorder(Color.blue.opacity(0.12), lineWidth: 1))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close mixer")
            }
            .padding(.horizontal, 24)
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var tabletMixer: some View {
        GeometryReader { proxy in
            if parts.isEmpty {
                emptyMixer
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let visibleChannelCount = min(parts.count + 1, 6)
                let availableWidth = max(proxy.size.width - 32, 1)
                let channelWidth = min(176, max(138, availableWidth / CGFloat(visibleChannelCount)))

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 10) {
                        mixerMasterChannel(width: channelWidth)

                        // A single rule separates Master from the part channels;
                        // the cards themselves separate the parts from each other.
                        Divider()
                            .frame(height: 300)
                            .padding(.horizontal, 4)

                        ForEach(Array(parts.enumerated()), id: \.element.id) { index, part in
                            mixerPartChannel(part, color: channelColor(index), width: channelWidth)
                        }
                    }
                    .frame(minWidth: proxy.size.width, maxHeight: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    private func mixerMasterChannel(width: CGFloat, compact: Bool = false) -> some View {
        mixerChannelStrip(
            name: "Master",
            color: .blue,
            volume: Binding(
                get: { readerState.mixerSettings.masterVolume },
                set: { value in
                    var mix = readerState.mixerSettings
                    mix.masterVolume = value
                    readerState.updateMixer(mix)
                }
            ),
            pan: Binding(
                get: { readerState.mixerSettings.masterPan },
                set: { value in
                    var mix = readerState.mixerSettings
                    mix.masterPan = value
                    readerState.updateMixer(mix)
                }
            ),
            muted: Binding(
                get: { readerState.mixerSettings.masterMuted },
                set: { value in
                    var mix = readerState.mixerSettings
                    mix.masterMuted = value
                    readerState.updateMixer(mix)
                }
            ),
            solo: nil,
            level: mixerLevelMonitor.levels[NativePlaybackController.masterMeterID] ?? 0,
            width: width,
            compact: compact
        )
    }

    private func mixerPartChannel(
        _ part: ScorePart,
        color: Color,
        width: CGFloat,
        compact: Bool = false
    ) -> some View {
        mixerChannelStrip(
            name: part.name,
            color: color,
            volume: Binding(
                get: { readerState.mixerSettings.settings(for: part.id).volume },
                set: { value in updatePart(part.id) { $0.volume = value } }
            ),
            pan: Binding(
                get: { readerState.mixerSettings.settings(for: part.id).pan },
                set: { value in updatePart(part.id) { $0.pan = value } }
            ),
            muted: Binding(
                get: { readerState.mixerSettings.settings(for: part.id).muted },
                set: { value in updatePart(part.id) { $0.muted = value } }
            ),
            solo: Binding(
                get: { readerState.mixerSettings.settings(for: part.id).solo },
                set: { value in updatePart(part.id) { $0.solo = value } }
            ),
            level: mixerLevelMonitor.levels[part.id] ?? 0,
            width: width,
            compact: compact
        )
    }

    private func mixerChannelStrip(
        name: String,
        color: Color,
        volume: Binding<Float>,
        pan: Binding<Float>,
        muted: Binding<Bool>?,
        solo: Binding<Bool>?,
        level: Float,
        width: CGFloat,
        compact: Bool = false
    ) -> some View {
        let cardCornerRadius: CGFloat = compact ? 13 : 16

        return VStack(spacing: compact ? 4 : 8) {
            HStack(spacing: compact ? 6 : 9) {
                Circle()
                    .fill(color)
                    .frame(width: compact ? 10 : 13, height: compact ? 10 : 13)
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }

            HStack(spacing: compact ? 5 : 8) {
                if let muted {
                    mixerButton(
                        "M",
                        accessibilityName: "Mute \(name)",
                        color: .red,
                        selected: muted,
                        compact: compact
                    )
                }
                if let solo {
                    mixerButton(
                        "S",
                        accessibilityName: "Solo \(name)",
                        color: .blue,
                        selected: solo,
                        compact: compact
                    )
                } else {
                    // Keeps Master's fader aligned with the part channels beside it.
                    Color.clear
                        .frame(
                            width: compact ? 34 : 46,
                            height: compact ? 32 : 36
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack(alignment: .center, spacing: compact ? 8 : 12) {
                VerticalMixerFader(
                    value: volume,
                    color: color,
                    accessibilityName: "\(name) volume",
                    compact: compact
                )
                StereoLevelMeter(level: level)
            }
            .frame(height: compact ? 92 : 138)

            Text(decibelLabel(volume.wrappedValue))
                .font(compact ? .caption.monospacedDigit() : .subheadline.monospacedDigit())
                .contentTransition(.numericText())

            VStack(spacing: 1) {
                Slider(value: pan, in: -1...1)
                    .tint(.secondary)
                    .accessibilityLabel("\(name) pan")
                    .accessibilityValue(panLabel(pan.wrappedValue))

                HStack {
                    Text("L")
                    Spacer()
                    Button { pan.wrappedValue = 0 } label: {
                        Capsule()
                            .fill(.secondary.opacity(0.45))
                            .frame(width: 7, height: 2)
                            .frame(width: 30, height: 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Center \(name) pan")
                    Spacer()
                    Text("R")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, compact ? 8 : 14)
        .padding(.vertical, compact ? 7 : 12)
        .frame(width: width)
        .background(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(BackgroundStyle.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }

    private func mixerButton(
        _ title: String,
        accessibilityName: String,
        color: Color,
        selected: Binding<Bool>,
        compact: Bool
    ) -> some View {
        Button { selected.wrappedValue.toggle() } label: {
            Text(title)
                .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: compact ? 28 : 32)
                .foregroundStyle(selected.wrappedValue ? Color.white : Color.primary)
                .background(
                    selected.wrappedValue ? color : Color.secondary.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
        }
        .frame(
            width: compact ? 34 : 46,
            height: compact ? 32 : 36
        )
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(selected.wrappedValue ? "On" : "Off")
        .accessibilityAddTraits(selected.wrappedValue ? .isSelected : [])
    }

    private func channelColor(_ index: Int) -> Color {
        let colors: [Color] = [.teal, .orange, .pink, .purple, .yellow, .indigo, .green, .cyan]
        return colors[index % colors.count]
    }

    private func decibelLabel(_ value: Float) -> String {
        guard value > 0.0001 else { return "−∞ dB" }
        return String(format: "%.1f dB", 20 * log10(value))
    }

    private var phoneMixer: some View {
        GeometryReader { proxy in
            let channelWidth = min(108, max(98, proxy.size.width * 0.27))

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 7) {
                    mixerMasterChannel(width: channelWidth, compact: true)
                        .id(NativePlaybackController.masterMeterID)

                    if !parts.isEmpty {
                        Divider()
                            .frame(height: 220)
                    }

                    ForEach(Array(parts.enumerated()), id: \.element.id) { index, part in
                        mixerPartChannel(
                            part,
                            color: channelColor(index),
                            width: channelWidth,
                            compact: true
                        )
                            .id(part.id)
                    }

                    if parts.isEmpty {
                        emptyMixer
                            .frame(width: proxy.size.width - channelWidth)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var emptyMixer: some View {
        Text("No playable instruments in this part.")
            .foregroundStyle(.secondary)
            .padding()
    }

    private func updatePart(_ id: String, change: (inout ScoreMixerPartSettings) -> Void) {
        var mix = readerState.mixerSettings
        var part = mix.settings(for: id)
        change(&part)
        mix.parts[id] = part
        readerState.updateMixer(mix)
    }

    private func panLabel(_ value: Float) -> String {
        abs(value) < 0.01 ? "Center" : "\(Int(abs(value) * 100))% \(value < 0 ? "left" : "right")"
    }

}

private struct VerticalMixerFader: View {
    @Binding var value: Float
    let color: Color
    let accessibilityName: String
    let compact: Bool

    var body: some View {
        GeometryReader { proxy in
            let thumbDiameter: CGFloat = compact ? 22 : 28
            let travel = max(proxy.size.height - thumbDiameter, 1)
            let boundedValue = min(max(CGFloat(value), 0), 1)
            let thumbY = thumbDiameter / 2 + (1 - boundedValue) * travel

            ZStack {
                Capsule()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 4)

                Capsule()
                    .fill(color)
                    .frame(width: 4, height: max(proxy.size.height - thumbY, 0))
                    .position(
                        x: proxy.size.width / 2,
                        y: thumbY + max(proxy.size.height - thumbY, 0) / 2
                    )

                Circle()
                    .fill(.background)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .shadow(color: .black.opacity(0.16), radius: 4, y: 2)
                    .overlay(Circle().stroke(.quaternary, lineWidth: 0.5))
                    .position(x: proxy.size.width / 2, y: thumbY)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let adjustedY = gesture.location.y - thumbDiameter / 2
                        value = Float(min(max(1 - adjustedY / travel, 0), 1))
                    }
            )
        }
        .frame(width: compact ? 34 : 44)
        .accessibilityElement()
        .accessibilityLabel(accessibilityName)
        .accessibilityValue("\(Int(value * 100)) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                value = min(value + 0.05, 1)
            case .decrement:
                value = max(value - 0.05, 0)
            @unknown default:
                break
            }
        }
    }
}

private struct StereoLevelMeter: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let level: Float

    var body: some View {
        GeometryReader { proxy in
            let boundedLevel = min(max(CGFloat(level), 0), 1)
            let activeHeight = proxy.size.height * boundedLevel

            HStack(spacing: 3) {
                meterBar(activeHeight: activeHeight)
                meterBar(activeHeight: activeHeight * 0.94)
            }
            .animation(reduceMotion ? nil : .linear(duration: 0.05), value: level)
        }
        .frame(width: 11)
        .accessibilityHidden(true)
    }

    private func meterBar(activeHeight: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            Capsule()
                .fill(Color.secondary.opacity(0.16))
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [.green, .mint, .yellow],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(height: activeHeight)
        }
        .frame(width: 4)
    }
}
