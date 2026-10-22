// Keep SoundFont extraction, FluidSynth setup and note-preview output off the UI.
#if os(Android)
import AVFoundation
import AudioToolbox
import Dispatch
import Foundation
import SwiftJNI

actor AndroidNotePreviewWorker {
    private nonisolated let executor = AndroidPreviewSerialExecutor()
    nonisolated var unownedExecutor: UnownedSerialExecutor { executor.asUnownedSerialExecutor() }
    private var engine: AVAudioEngine?
    private var sampler: AVAudioUnitSampler?
    private var loadedProgram: UInt8?
    private var stops: [UInt8: Task<Void, Never>] = [:]
    private var generation = 0

    func prewarm(program: Int) {
        do { try prepare(program: UInt8(clamping: program)) }
        catch { print("MuseReader note preview prewarm failed: \(error.localizedDescription)") }
    }

    func play(pitches: [Int], bank: Int?, program: Int?, setup: String?) {
        stopNotes()
        let pitches = pitches.filter { (0...127).contains($0) }
        guard !pitches.isEmpty else { return }
        do {
            let program = UInt8(clamping: program ?? 0)
            try prepare(program: program)
            if let engine, !engine.isRunning { try engine.start() }
            let currentGeneration = generation
            for pitch in pitches {
                let note = UInt8(pitch)
                sampler?.startNote(note, withVelocity: 96, onChannel: 0)
                stops[note] = Task { [weak self] in
                    do { try await Task.sleep(for: .milliseconds(550)) }
                    catch { return }
                    await self?.stop(note, generation: currentGeneration)
                }
            }
            print("MuseReader note preview: notes=\(pitches) bank=\(bank ?? 0) program=\(program) setup=\(setup ?? "")")
        } catch { print("MuseReader note preview failed: \(error.localizedDescription)") }
    }

    func stopAll() {
        stopNotes()
        engine?.stop()
        engine = nil
        sampler = nil
        loadedProgram = nil
    }

    private func stop(_ note: UInt8, generation expected: Int) {
        guard generation == expected else { return }
        sampler?.stopNote(note, onChannel: 0)
        stops[note] = nil
    }

    private func stopNotes() {
        generation &+= 1
        for note in stops.keys { sampler?.stopNote(note, onChannel: 0) }
        stops.values.forEach { $0.cancel() }
        stops.removeAll()
    }

    private func prepare(program: UInt8) throws {
        guard loadedProgram != program || engine == nil else { return }
        #if ARIA_EDIT_AUDIT
        let started = Date()
        #endif
        guard let url = AppResources.url(forResource: "MuseScore_General", withExtension: "sf2") else {
            throw NSError(domain: "AriaNotePreview", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "MuseScore_General.sf2 is unavailable."])
        }
        let outputEngine = engine ?? AVAudioEngine()
        let instrument = sampler ?? AVAudioUnitSampler()
        if engine == nil {
            outputEngine.attach(instrument)
            outputEngine.connect(instrument, to: outputEngine.mainMixerNode, format: nil)
        }
        try instrument.loadSoundBankInstrument(at: url, program: program,
            bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB), bankLSB: UInt8(kAUSampler_DefaultBankLSB))
        // A prepared preview must not take over the score playback latency clock.
        try outputEngine.prewarmSamplers()
        engine = outputEngine
        sampler = instrument
        loadedProgram = program
        print("MuseReader note preview ready: soundbank=\(url.lastPathComponent) program=\(program)")
        #if ARIA_EDIT_AUDIT
        if let process = try? JClass(name: "android/os/Process", systemClass: true),
           let tidMethod = process.getStaticMethodID(name: "myTid", sig: "()I"),
           let pidMethod = process.getStaticMethodID(name: "myPid", sig: "()I") {
            do {
                // Keep the generic return type non-optional: JNI returns primitive
                // int, whereas Optional<Int32> expects a boxed java.lang.Integer.
                let tid: Int32 = try process.callStatic(method: tidMethod, options: [], args: [])
                let pid: Int32 = try process.callStatic(method: pidMethod, options: [], args: [])
                print("ARIA_PREVIEW_PREPARE tid=\(tid) main=\(tid == pid) seconds=\(Date().timeIntervalSince(started)) program=\(program)")
            } catch { print("ARIA_PREVIEW_THREAD_PROBE_UNAVAILABLE") }
        }
        #endif
    }
}

private nonisolated final class AndroidPreviewSerialExecutor: SerialExecutor, @unchecked Sendable {
    private let queue = DispatchQueue(label: "aria.note.preview", qos: .userInitiated)
    func enqueue(_ job: consuming ExecutorJob) {
        let pending = UnownedJob(job)
        queue.async {
            jniContext {
                JNI.jni.withEnv { precondition($0.PushLocalFrame($1, 32) == 0) }
                defer { JNI.jni.withEnv { _ = $0.PopLocalFrame($1, nil) } }
                pending.runSynchronously(on: self.asUnownedSerialExecutor())
            }
        }
    }
}
#endif
