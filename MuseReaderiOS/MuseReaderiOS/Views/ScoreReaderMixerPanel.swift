import SwiftUI

struct ScoreReaderMixerPanel: View {
    @ObservedObject var readerState: ScoreReaderState
    let selectedPartID: String
    let close: () -> Void
    @State private var expandedParts: Set<String> = []

    private var parts: [ScorePart] {
        readerState.scoreParts.filter {
            $0.isVisible && (selectedPartID == "full-score" || $0.id == selectedPartID)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Mixer").font(.title2.bold())
                Spacer()
                Button("Reset mix") { readerState.updateMixer(ScoreMixerSettings()) }
                    .font(.subheadline)
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Close mixer")
            }
            .padding(.horizontal)
            .padding(.top, 8)
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Master volume").font(.headline)
                        HStack {
                            Image(systemName: "speaker.wave.2.fill").foregroundStyle(.secondary)
                            Slider(value: Binding(
                                get: { Double(readerState.mixerSettings.masterVolume) },
                                set: { value in
                                    var mix = readerState.mixerSettings
                                    mix.masterVolume = Float(value)
                                    readerState.updateMixer(mix)
                                }
                            ), in: 0...1)
                            .accessibilityLabel("Master volume")
                            volumeLabel(readerState.mixerSettings.masterVolume)
                        }
                    }
                    .padding()
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))

                    ForEach(parts) { part in
                        instrumentRow(part)
                    }
                    if parts.isEmpty {
                        Text("No playable instruments in this part.")
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                }
                .padding()
            }
        }
        .background(.regularMaterial)
    }

    private func instrumentRow(_ part: ScorePart) -> some View {
        let settings = readerState.mixerSettings.settings(for: part.id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(part.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                mixButton("Mute", selected: settings.muted, part: part) { $0.muted.toggle() }
                mixButton("Solo", selected: settings.solo, part: part) { $0.solo.toggle() }
            }
            HStack {
                Slider(value: Binding(
                    get: { Double(readerState.mixerSettings.settings(for: part.id).volume) },
                    set: { value in updatePart(part.id) { $0.volume = Float(value) } }
                ), in: 0...1)
                .accessibilityLabel("\(part.name) volume")
                volumeLabel(settings.volume)
            }
            DisclosureGroup(isExpanded: Binding(
                get: { expandedParts.contains(part.id) },
                set: { expanded in
                    if expanded { expandedParts.insert(part.id) } else { expandedParts.remove(part.id) }
                }
            )) {
                HStack {
                    Text("L")
                    Slider(value: Binding(
                        get: { Double(readerState.mixerSettings.settings(for: part.id).pan) },
                        set: { value in updatePart(part.id) { $0.pan = Float(value) } }
                    ), in: -1...1)
                    .accessibilityLabel("\(part.name) pan")
                    .accessibilityValue(panLabel(settings.pan))
                    Text("R")
                    Button("Center") { updatePart(part.id) { $0.pan = 0 } }
                }
                .font(.caption)
                .padding(.top, 8)
            } label: {
                Text("Pan · \(panLabel(settings.pan))").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
    }

    private func mixButton(_ title: String, selected: Bool, part: ScorePart,
                           change: @escaping (inout ScoreMixerPartSettings) -> Void) -> some View {
        Button { updatePart(part.id, change: change) } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(selected ? Color.accentColor : Color.secondary.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) \(part.name)")
        .accessibilityValue(selected ? "On" : "Off")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func updatePart(_ id: String, change: (inout ScoreMixerPartSettings) -> Void) {
        var mix = readerState.mixerSettings
        var part = mix.settings(for: id)
        change(&part)
        mix.parts[id] = part
        readerState.updateMixer(mix)
    }

    private func volumeLabel(_ value: Float) -> some View {
        Text("\(Int(value * 100))%")
            .font(.caption.monospacedDigit())
            .frame(width: 38, alignment: .trailing)
            .accessibilityHidden(true)
    }

    private func panLabel(_ value: Float) -> String {
        abs(value) < 0.01 ? "Center" : "\(Int(abs(value) * 100))% \(value < 0 ? "left" : "right")"
    }
}
