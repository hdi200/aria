//
//  NativeNotePreviewController.swift
//  MuseReaderiOS
//
//  Created by Codex on 5/13/26.
//

import AVFoundation
import AudioToolbox
import Foundation

@MainActor
final class NativeNotePreviewController {
    private let noteDurationSeconds: TimeInterval = 0.55
    private let velocity: UInt8 = 96
    private var engine: AVAudioEngine?
    private var sampler: AVAudioUnitSampler?
    private var loadedSoundBankURL: URL?
    private var loadedProgram: UInt8?
    private var activeStopTasks: [UInt8: Task<Void, Never>] = [:]

    func play(midiPitches: [Int]?, fallbackMIDIPitch: Int?, playbackBank: Int?, playbackProgram: Int?, playbackSetupData: String?) {
        let requestedPitches = midiPitches?.isEmpty == false ? midiPitches ?? [] : fallbackMIDIPitch.map { [$0] } ?? []
        let validPitches = requestedPitches.filter { (0...127).contains($0) }
        guard !validPitches.isEmpty else {
            return
        }

        do {
            let program = UInt8(clamping: playbackProgram ?? 0)
            try prepareIfNeeded(program: program)

            for midiPitch in validPitches {
                let note = UInt8(midiPitch)
                activeStopTasks[note]?.cancel()
                sampler?.startNote(note, withVelocity: velocity, onChannel: 0)
                activeStopTasks[note] = Task { @MainActor [weak self] in
                    let durationSeconds = self?.noteDurationSeconds ?? 0.55
                    try? await Task.sleep(for: .milliseconds(Int(durationSeconds * 1000)))
                    self?.sampler?.stopNote(note, onChannel: 0)
                    self?.activeStopTasks[note] = nil
                }
            }

            print("MuseReader note preview: notes=\(validPitches) bank=\(playbackBank ?? 0) program=\(program) setup=\(playbackSetupData ?? "")")
        } catch {
            print("MuseReader note preview failed: \(error.localizedDescription)")
        }
    }

    func stopAll() {
        for note in activeStopTasks.keys {
            sampler?.stopNote(note, onChannel: 0)
        }
        activeStopTasks.values.forEach { $0.cancel() }
        activeStopTasks.removeAll()
        engine?.stop()
        engine = nil
        sampler = nil
        loadedSoundBankURL = nil
        loadedProgram = nil
    }

    private func prepareIfNeeded(program: UInt8) throws {
        if engine != nil, sampler != nil, loadedProgram == program {
            return
        }

        guard let soundBankURL = Bundle.main.url(forResource: "MuseScore_General", withExtension: "sf2")
            ?? Bundle.main.url(forResource: "MuseScore_General", withExtension: "sf3")
            ?? Bundle.main.url(forResource: "MS Basic", withExtension: "sf3")
        else {
            throw NativePlaybackController.PlaybackError.soundBankUnavailable(
                "Add `MuseScore_General.sf2`, `MuseScore_General.sf3`, or `MS Basic.sf3` to the app bundle resources."
            )
        }

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try audioSession.setActive(true)

        let engine: AVAudioEngine
        let sampler: AVAudioUnitSampler
        if let existingEngine = self.engine, let existingSampler = self.sampler {
            engine = existingEngine
            sampler = existingSampler
        } else {
            engine = AVAudioEngine()
            sampler = AVAudioUnitSampler()
            engine.attach(sampler)
            engine.connect(sampler, to: engine.mainMixerNode, format: nil)
        }

        try sampler.loadSoundBankInstrument(
            at: soundBankURL,
            program: program,
            bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
            bankLSB: UInt8(kAUSampler_DefaultBankLSB)
        )

        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }

        self.engine = engine
        self.sampler = sampler
        self.loadedSoundBankURL = soundBankURL
        self.loadedProgram = program
        print("MuseReader note preview ready: soundbank=\(soundBankURL.lastPathComponent) program=\(program)")
    }
}
