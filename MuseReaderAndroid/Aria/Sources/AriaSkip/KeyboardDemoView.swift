import SwiftUI

/// Hosts the iOS app's note-entry keyboard (linked unchanged from the iOS sources).
struct KeyboardDemoView: View {
    @State var lastKey: PianoKeyboardKey?
    @State var useFlats = false
    @State var transposeLog: [String] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text(lastKey.map { "Tapped \(noteName($0.midiPitch)) (MIDI \($0.midiPitch))" } ?? "Tap a key")
                    .font(.headline)

                Toggle("Use flats", isOn: $useFlats)
                    .padding(.horizontal)

                ScoreReaderWidePitchKeyboard(
                    useFlats: useFlats,
                    activePitchClass: lastKey?.pitchClass,
                    activeMIDIPitch: lastKey?.midiPitch,
                    followsActiveMIDIPitch: false,
                    isEnabled: true,
                    action: { key in lastKey = key }
                )
                .frame(height: 92)
                .frame(maxWidth: .infinity)

                ScoreReaderPitchStrip(
                    isEnabled: lastKey != nil,
                    semitoneShiftAction: { shift in transposeLog.append("Semitone \(shift > 0 ? "+" : "")\(shift)") },
                    octaveShiftAction: { shift in transposeLog.append("Octave \(shift > 0 ? "+" : "")\(shift)") }
                )
                // The size iOS gives it next to the keyboard (ScoreReaderNoteEntrySurface).
                .frame(width: 74, height: 122)

                Text(transposeLog.suffix(3).joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle("Note entry keyboard")
        }
    }

    func noteName(_ midiPitch: Int) -> String {
        let sharps = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        let flats = ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B"]
        let names = useFlats ? flats : sharps
        return "\(names[midiPitch % 12])\(midiPitch / 12 - 1)"
    }
}
