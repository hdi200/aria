import Foundation
import Testing
@testable import MuseReaderiOS

struct ScoreMixerSettingsTests {
    @Test func multipleSolosAndMutePrecedence() {
        var mix = ScoreMixerSettings()
        mix.parts["piano"] = ScoreMixerPartSettings(volume: 0.4, solo: true)
        mix.parts["bass"] = ScoreMixerPartSettings(volume: 0.7, solo: true)
        let active: Set<String> = ["piano", "bass", "drums"]
        #expect(mix.gain(for: "piano", activePartIDs: active) == 0.4)
        #expect(mix.gain(for: "bass", activePartIDs: active) == 0.7)
        #expect(mix.gain(for: "drums", activePartIDs: active) == 0)
        mix.parts["piano"]?.muted = true
        #expect(mix.gain(for: "piano", activePartIDs: active) == 0)
    }

    @Test func soloInAnotherExcerptDoesNotSilenceCurrentPart() {
        var mix = ScoreMixerSettings()
        mix.parts["piano"] = ScoreMixerPartSettings(solo: true)
        #expect(mix.gain(for: "bass", activePartIDs: ["bass"]) == 1)
        #expect(mix.gain(for: "bass", activePartIDs: ["bass", "piano"]) == 0)
    }

    @Test func savedMixUsesStablePartAndScoreIDs() throws {
        let suite = "AriaMixerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ScoreMixerSettingsStore(defaults: defaults)
        var mix = ScoreMixerSettings(masterVolume: 0.6)
        mix.parts["part-42"] = ScoreMixerPartSettings(volume: 0.35, pan: -0.5, muted: true, solo: true)
        store.save(mix, scoreID: "score-a")
        #expect(store.load(scoreID: "score-a") == mix)
        #expect(store.load(scoreID: "score-b") == ScoreMixerSettings())
        #expect(store.load(scoreID: "score-a").settings(for: "new-part") == ScoreMixerPartSettings())
        store.save(ScoreMixerSettings(), scoreID: "score-a")
        #expect(store.load(scoreID: "score-a") == ScoreMixerSettings())
    }

    @Test func malformedSavedMixFallsBackToDefaults() throws {
        let suite = "AriaMixerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("invalid".utf8), forKey: "ScoreMixerSettings.score")
        #expect(ScoreMixerSettingsStore(defaults: defaults).load(scoreID: "score") == ScoreMixerSettings())
    }
}
