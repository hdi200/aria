import Accelerate
import Foundation

struct StemSoftwareMix {
    let interleavedFloat32Samples: Data
    let normalizedLevels: [String: Float]
}

enum StemSoftwareMixerError: Error {
    case invalidBuffer
    case mismatchedBuffers
}

/// Combines synchronized stereo stems before they reach AVAudioEngine. Keeping one
/// playback node avoids the first-render skew that can occur when several player
/// nodes become audible together.
struct StemSoftwareMixer {
    static func mix(
        partSamples: [String: Data],
        settings: ScoreMixerSettings,
        metronomeEnabled: Bool
    ) throws -> StemSoftwareMix {
        guard let reference = partSamples.values.first,
              !reference.isEmpty,
              reference.count.isMultiple(of: MemoryLayout<Float>.size * 2) else {
            throw StemSoftwareMixerError.invalidBuffer
        }

        guard partSamples.values.allSatisfy({ $0.count == reference.count }) else {
            throw StemSoftwareMixerError.mismatchedBuffers
        }

        let frameCount = reference.count / MemoryLayout<Float>.size / 2
        var left = [Float](repeating: 0, count: frameCount)
        var right = [Float](repeating: 0, count: frameCount)
        let levels = try left.withUnsafeMutableBufferPointer { left in
            try right.withUnsafeMutableBufferPointer { right in
                try mix(
                    partSamples: partSamples,
                    frameCount: frameCount,
                    settings: settings,
                    metronomeEnabled: metronomeEnabled,
                    left: left.baseAddress!,
                    right: right.baseAddress!
                )
            }
        }

        var interleaved = [Float](repeating: 0, count: frameCount * 2)
        for frame in 0..<frameCount {
            interleaved[frame * 2] = left[frame]
            interleaved[frame * 2 + 1] = right[frame]
        }
        let samples = interleaved.withUnsafeBufferPointer { buffer in
            Data(bytes: buffer.baseAddress!, count: buffer.count * MemoryLayout<Float>.size)
        }
        return StemSoftwareMix(interleavedFloat32Samples: samples, normalizedLevels: levels)
    }

    /// Mixes the first `frameCount` frames of interleaved stereo stems straight into
    /// planar output channels, which must hold `frameCount` zeroed samples.
    /// When `reverbSend` (interleaved, zeroed) is given, every part except the
    /// metronome is also added to it post-fader at `reverbSendLevel`, as desktop
    /// MuseScore feeds its reverb aux channel. Returns post-fader part levels.
    static func mix(
        partSamples: [String: Data],
        frameCount: Int,
        settings: ScoreMixerSettings,
        metronomeEnabled: Bool,
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>,
        reverbSend: UnsafeMutablePointer<Float>? = nil,
        reverbSendLevel: Float = 0
    ) throws -> [String: Float] {
        let expectedByteCount = frameCount * 2 * MemoryLayout<Float>.size
        let partIDs = Set(partSamples.keys.filter { $0 != "metronome" })
        var normalizedLevels: [String: Float] = [:]

        for id in partSamples.keys.sorted() {
            guard let data = partSamples[id], data.count >= expectedByteCount else {
                throw StemSoftwareMixerError.mismatchedBuffers
            }

            let gain: Float
            let pan: Float
            if id == "metronome" {
                gain = metronomeEnabled ? 1 : 0
                pan = 0
            } else {
                gain = settings.gain(for: id, activePartIDs: partIDs)
                pan = min(max(settings.settings(for: id).pan, -1), 1)
            }
            guard gain > 0, frameCount > 0 else { continue }

            // Match the stereo balance behavior of AVAudioMixing: centre preserves
            // both channels and either edge attenuates only the opposite channel.
            var leftGain = gain * (pan > 0 ? 1 - pan : 1)
            var rightGain = gain * (pan < 0 ? 1 + pan : 1)
            var leftPeak: Float = 0
            var rightPeak: Float = 0

            data.withUnsafeBytes { rawBuffer in
                let source = rawBuffer.bindMemory(to: Float.self).baseAddress!
                let count = vDSP_Length(frameCount)
                vDSP_vsma(source, 2, &leftGain, left, 1, left, 1, count)
                vDSP_vsma(source + 1, 2, &rightGain, right, 1, right, 1, count)
                vDSP_maxmgv(source, 2, &leftPeak, count)
                vDSP_maxmgv(source + 1, 2, &rightPeak, count)
                if let reverbSend, id != "metronome", reverbSendLevel > 0 {
                    var leftSendGain = leftGain * reverbSendLevel
                    var rightSendGain = rightGain * reverbSendLevel
                    vDSP_vsma(source, 2, &leftSendGain, reverbSend, 2, reverbSend, 2, count)
                    vDSP_vsma(source + 1, 2, &rightSendGain, reverbSend + 1, 2, reverbSend + 1, 2, count)
                }
            }

            let peak = max(leftPeak * leftGain, rightPeak * rightGain)
            if id != "metronome", let level = normalizedMeterLevel(forPeak: peak) {
                normalizedLevels[id] = level
            }
        }
        return normalizedLevels
    }

    private static func normalizedMeterLevel(forPeak peak: Float) -> Float? {
        guard peak > 0.000_01 else { return nil }
        let decibels = 20 * log10(peak)
        return min(max((decibels + 60) / 60, 0), 1)
    }
}
