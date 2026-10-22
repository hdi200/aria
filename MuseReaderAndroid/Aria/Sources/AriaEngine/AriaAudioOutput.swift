// Swift over the engine's audio output (engine/aria_audio_output.cpp). The AVFoundation
// stand-in (Sources/AndroidShims/AVFoundation) builds AVAudioEngine on it.

@_implementationOnly import AriaRenderCoreCxx
@_implementationOnly import CxxStdlib
import Foundation


public final class AriaAudioOutput: @unchecked Sendable {
    private let output: UnsafeMutableRawPointer
    public let sampleRate: Double

    /// Opens and starts a stereo output with `playerCount` players; `sampleRate` nil: the
    /// device's rate.
    public init(sampleRate: Double?, playerCount: Int) throws {
        var errorMessage = std.string()
        guard let output = aria.audioOutputCreate(sampleRate ?? 0, Int32(playerCount), &errorMessage) else {
            throw NSError(domain: "Aria.AudioOutput", code: 1, userInfo: [
                NSLocalizedDescriptionKey: String(errorMessage).isEmpty ? "The audio output could not be opened." : String(errorMessage)
            ])
        }
        self.output = output
        self.sampleRate = aria.audioOutputSampleRate(output)
    }

    deinit {
        aria.audioOutputDestroy(output)
    }

    public static func hostTimeNanos() -> UInt64 {
        UInt64(max(aria.hostTimeNanos(), 0))
    }

    public func start() throws {
        var errorMessage = std.string()
        guard aria.audioOutputStart(output, &errorMessage) else {
            throw NSError(domain: "Aria.AudioOutput", code: 2, userInfo: [NSLocalizedDescriptionKey: String(errorMessage)])
        }
    }

    public func stop() {
        aria.audioOutputStop(output)
    }

    public var isRunning: Bool {
        aria.audioOutputIsRunning(output)
    }

    public func setMaster(volume: Float, pan: Float) {
        aria.audioOutputSetMaster(output, volume, pan)
    }

    public var latencySeconds: Double {
        aria.audioOutputLatencySeconds(output)
    }

    public var bufferSeconds: Double {
        aria.audioOutputBufferSeconds(output)
    }

    public func takePeak() -> Float {
        aria.audioOutputTakePeak(output)
    }

    /// `sampleTime` nil: after the previous buffer.
    public func schedule(player: Int, sampleTime: Int64?, left: UnsafePointer<Float>, right: UnsafePointer<Float>,
                         frameCount: Int, id: Int64) {
        aria.audioPlayerSchedule(output, Int32(player), sampleTime ?? -1, left, right, Int32(frameCount), id)
    }

    /// `hostTimeNanos` 0: now.
    public func play(player: Int, hostTimeNanos: UInt64) {
        aria.audioPlayerPlayAt(output, Int32(player), Int64(clamping: hostTimeNanos))
    }

    public func pause(player: Int) {
        aria.audioPlayerPause(output, Int32(player))
    }

    public func stop(player: Int) {
        aria.audioPlayerStop(output, Int32(player))
    }

    public func isPlaying(player: Int) -> Bool {
        aria.audioPlayerIsPlaying(output, Int32(player))
    }

    public func sampleTime(player: Int) -> Int64 {
        aria.audioPlayerSampleTime(output, Int32(player))
    }

    public func setVolume(player: Int, volume: Float) {
        aria.audioPlayerSetVolume(output, Int32(player), volume)
    }

    /// Loads the live instrument (FluidSynth), or only changes its program.
    public func loadSampler(soundFontPath: String, bank: Int, program: Int) throws {
        var errorMessage = std.string()
        guard aria.audioSamplerLoad(output, std.string(soundFontPath), Int32(bank), Int32(program), &errorMessage) else {
            throw NSError(domain: "Aria.AudioOutput", code: 3, userInfo: [NSLocalizedDescriptionKey: String(errorMessage)])
        }
    }

    public func samplerNoteOn(_ key: Int, velocity: Int) {
        aria.audioSamplerNoteOn(output, Int32(key), Int32(velocity))
    }

    public func samplerNoteOff(_ key: Int) {
        aria.audioSamplerNoteOff(output, Int32(key))
    }

    /// Ids of buffers rendered (or dropped by a stop) since the last call.
    public func takeFinished(player: Int) -> [Int64] {
        aria.audioPlayerTakeFinished(output, Int32(player)).map { Int64($0) }
    }
}

