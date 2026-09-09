import Foundation

struct ScoreMixerPartSettings: Codable, Equatable {
    var volume: Float = 1
    var pan: Float = 0
    var muted = false
    var solo = false
}

struct ScoreMixerSettings: Codable, Equatable {
    var masterVolume: Float = 1
    var parts: [String: ScoreMixerPartSettings] = [:]

    func settings(for partID: String) -> ScoreMixerPartSettings {
        parts[partID] ?? ScoreMixerPartSettings()
    }

    func gain(for partID: String, activePartIDs: Set<String>) -> Float {
        let part = settings(for: partID)
        let hasSolo = activePartIDs.contains { settings(for: $0).solo }
        return part.muted || (hasSolo && !part.solo) ? 0 : min(max(part.volume, 0), 1)
    }
}

struct ScoreMixerSettingsStore {
    var defaults: UserDefaults = .standard
    private let prefix = "ScoreMixerSettings."

    func load(scoreID: String) -> ScoreMixerSettings {
        guard let data = defaults.data(forKey: prefix + scoreID),
              let settings = try? JSONDecoder().decode(ScoreMixerSettings.self, from: data) else {
            return ScoreMixerSettings()
        }
        return settings
    }

    func save(_ settings: ScoreMixerSettings, scoreID: String) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: prefix + scoreID)
    }
}
