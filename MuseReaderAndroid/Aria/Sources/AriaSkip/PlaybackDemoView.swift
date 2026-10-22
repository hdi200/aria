import SwiftUI

/// Plays the bundled Amazing Grace through the shared iOS session service and
/// NativePlaybackController (AVFoundation stand-in, AAudio output).
struct PlaybackDemoView: View {
    @State var status = "Opening…"
    @State var position = ""
    @State var controller: NativePlaybackController?
    @State var session: ScoreSession?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(status).font(.footnote).foregroundStyle(.secondary)
                Text(position).font(.title2)
                HStack(spacing: 24) {
                    Button("Play") { play() }
                    Button("Pause") { try? controller?.pause() }
                    Button("Stop") { try? controller?.stop() }
                    Button("Note") { NotePreview.shared.play(midiPitches: [67], fallbackMIDIPitch: nil, playbackBank: 0, playbackProgram: 0, playbackSetupData: nil) }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationTitle("Playback")
        }
        .task { await open() }
        .task {
            while !Task.isCancelled {
                if let state = controller?.state() {
                    position = String(format: "%.1f / %.1f s · %@", state.positionSeconds, state.durationSeconds, "\(state.status)")
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    private func open() async {
        do {
            let score = try BundledScore.copy(named: "Amazing_grace", extension: "mscz")
            let session = try await MuseScoreSessionService().openSession(at: score)
            self.session = session
            guard let live = session.liveRenderSession else {
                status = "No live session"
                return
            }
            let regions = try await live.playbackMeasureRegions()
            let duration = regions.map(\.endTimeSeconds).max() ?? 0
            let started = Date()
            let controller = NativePlaybackController()
            try await controller.prepare(liveRenderSession: live, durationSeconds: duration, metronomeEnabled: false)
            self.controller = controller
            status = String(format: "Ready in %.1f s (%d pages)", Date().timeIntervalSince(started), session.pageCount)
        } catch {
            status = "Failed: \(error.localizedDescription)"
        }
    }

    private func play() {
        do {
            try controller?.play()
        } catch {
            status = "Play failed: \(error.localizedDescription)"
        }
    }
}

@MainActor
enum NotePreview {
    static let shared = NativeNotePreviewController()
}

enum BundledScore {
    /// The engine reads real files, and bundle resources on Android live inside the APK.
    static func copy(named name: String, extension ext: String) throws -> URL {
        guard let resource = Bundle.module.url(forResource: name, withExtension: ext) else {
            throw ScoreEngineError.unavailable("\(name).\(ext) is missing from the app bundle.")
        }
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).\(ext)")
        try? FileManager.default.removeItem(at: destination)
        try Data(contentsOf: resource).write(to: destination)
        return destination
    }
}
