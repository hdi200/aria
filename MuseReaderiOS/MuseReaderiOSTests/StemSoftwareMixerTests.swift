import Foundation
import Testing
@testable import MuseReaderiOS

struct StemSoftwareMixerTests {
    @Test func appliesPartVolumeAndStereoPanBeforeSumming() throws {
        var settings = ScoreMixerSettings()
        settings.parts["piano"] = ScoreMixerPartSettings(volume: 0.5, pan: 1)
        settings.parts["bass"] = ScoreMixerPartSettings(muted: true)

        let result = try StemSoftwareMixer.mix(
            partSamples: [
                "piano": samples([1, 2, -1, -2]),
                "bass": samples([10, 10, 10, 10]),
                "metronome": samples([4, 4, 4, 4])
            ],
            settings: settings,
            metronomeEnabled: false
        )

        #expect(decoded(result.interleavedFloat32Samples) == [0, 1, 0, -1])
        #expect(result.normalizedLevels["piano"] == 1)
        #expect(result.normalizedLevels["bass"] == nil)
        #expect(result.normalizedLevels["metronome"] == nil)
    }

    @Test func soloAndMetronomeAreAppliedIndependently() throws {
        var settings = ScoreMixerSettings()
        settings.parts["violin"] = ScoreMixerPartSettings(solo: true)

        let result = try StemSoftwareMixer.mix(
            partSamples: [
                "violin": samples([1, 1]),
                "cello": samples([3, 3]),
                "metronome": samples([2, 2])
            ],
            settings: settings,
            metronomeEnabled: true
        )

        #expect(decoded(result.interleavedFloat32Samples) == [3, 3])
        #expect(result.normalizedLevels["violin"] == 1)
        #expect(result.normalizedLevels["cello"] == nil)
    }

    @Test func reverbSendIsPostFaderAndSkipsTheMetronome() throws {
        var settings = ScoreMixerSettings()
        settings.parts["flute"] = ScoreMixerPartSettings(volume: 0.5, pan: 1)
        let partSamples = [
            "flute": samples([2, 4]),
            "metronome": samples([8, 8])
        ]
        var left: [Float] = [0]
        var right: [Float] = [0]
        var send: [Float] = [0, 0]

        _ = try StemSoftwareMixer.mix(
            partSamples: partSamples,
            frameCount: 1,
            settings: settings,
            metronomeEnabled: true,
            left: &left,
            right: &right,
            reverbSend: &send,
            reverbSendLevel: 0.5
        )

        #expect(left == [8])
        #expect(right == [10])
        #expect(send == [0, 1])
    }

    @Test func rejectsDifferentStemLengths() {
        #expect(throws: StemSoftwareMixerError.self) {
            try StemSoftwareMixer.mix(
                partSamples: ["a": samples([1, 1]), "b": samples([1, 1, 1, 1])],
                settings: ScoreMixerSettings(),
                metronomeEnabled: false
            )
        }
    }

    private func samples(_ values: [Float]) -> Data {
        values.withUnsafeBufferPointer { buffer in
            Data(bytes: buffer.baseAddress!, count: buffer.count * MemoryLayout<Float>.size)
        }
    }

    private func decoded(_ data: Data) -> [Float] {
        data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}
