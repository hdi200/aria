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

        let partIDs = Set(partSamples.keys.filter { $0 != "metronome" })
        let sampleCount = reference.count / MemoryLayout<Float>.size
        let frameCount = sampleCount / 2
        var mixedSamples = [Float](repeating: 0, count: sampleCount)
        var normalizedLevels: [String: Float] = [:]

        for id in partSamples.keys.sorted() {
            guard let data = partSamples[id], data.count == reference.count else {
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
            guard gain > 0 else { continue }

            // Match the stereo balance behavior of AVAudioMixing: centre preserves
            // both channels and either edge attenuates only the opposite channel.
            let leftGain = gain * (pan > 0 ? 1 - pan : 1)
            let rightGain = gain * (pan < 0 ? 1 + pan : 1)
            var peak: Float = 0

            data.withUnsafeBytes { rawBuffer in
                let source = rawBuffer.bindMemory(to: Float.self)
                for frame in 0..<frameCount {
                    let left = source[frame * 2] * leftGain
                    let right = source[frame * 2 + 1] * rightGain
                    mixedSamples[frame * 2] += left
                    mixedSamples[frame * 2 + 1] += right
                    peak = max(peak, max(abs(left), abs(right)))
                }
            }

            if id != "metronome", let level = normalizedMeterLevel(forPeak: peak) {
                normalizedLevels[id] = level
            }
        }

        let samples = mixedSamples.withUnsafeBufferPointer { buffer in
            Data(bytes: buffer.baseAddress!, count: buffer.count * MemoryLayout<Float>.size)
        }
        return StemSoftwareMix(
            interleavedFloat32Samples: samples,
            normalizedLevels: normalizedLevels
        )
    }

    private static func normalizedMeterLevel(forPeak peak: Float) -> Float? {
        guard peak > 0.000_01 else { return nil }
        let decibels = 20 * log10(peak)
        return min(max((decibels + 60) / 60, 0), 1)
    }
}
