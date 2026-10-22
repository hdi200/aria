// Android's MIDIInputController: the same API as the iOS one
// (Services/MIDIInputController.swift, CoreMIDI), with Android MIDI (AriaMidi.kt).

// Not limited to Android: the Skip project's own iOS build (a build step only; the iOS
// app is MuseReaderiOS/Aria.xcodeproj) compiles it in place of the held-back iOS file.
import Foundation
import SkipFuse

final class MIDIInputController {
    var noteOnHandler: ((Int) -> Void)?
    var noteOffHandler: ((Int) -> Void)?

    private var pollTask: Task<Void, Never>?

    func start() {
        guard pollTask == nil else {
            return
        }
        guard (try? Self.midi()?.start() as Bool?) == true else {
            return
        }
        // Kotlin queues the notes; collect them often enough to feel immediate.
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.deliverNotes()
                try? await Task.sleep(for: .milliseconds(8))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        try? Self.midi()?.stop() as Void?
    }

    deinit {
        pollTask?.cancel()
    }

    private func deliverNotes() {
        guard let events = try? Self.midi()?.takeNotes() as String?, !events.isEmpty else {
            return
        }
        for event in events.split(separator: ",") {
            guard let pitch = Int(event.dropLast()) else { continue }
            if event.hasSuffix("+") {
                noteOnHandler?(pitch)
            } else {
                noteOffHandler?(pitch)
            }
        }
    }

    private static func midi() -> AnyDynamicObject? {
        try? AnyDynamicObject(className: "aria.skip.AriaMidi")
    }
}
