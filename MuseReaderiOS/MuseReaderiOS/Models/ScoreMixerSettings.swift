import Foundation

struct ScoreMixerPartSettings: Codable, Equatable {
    var volume: Float = 1
    var pan: Float = 0
    var muted = false
    var solo = false
}

struct ScoreMixerSettings: Codable, Equatable {
    var masterVolume: Float = 1
    var masterPan: Float = 0
    var masterMuted = false
    var parts: [String: ScoreMixerPartSettings] = [:]

    init(
        masterVolume: Float = 1,
        masterPan: Float = 0,
        masterMuted: Bool = false,
        parts: [String: ScoreMixerPartSettings] = [:]
    ) {
        self.masterVolume = masterVolume
        self.masterPan = masterPan
        self.masterMuted = masterMuted
        self.parts = parts
    }

    private enum CodingKeys: String, CodingKey {
        case masterVolume
        case masterPan
        case masterMuted
        case parts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        masterVolume = try container.decodeIfPresent(Float.self, forKey: .masterVolume) ?? 1
        masterPan = try container.decodeIfPresent(Float.self, forKey: .masterPan) ?? 0
        masterMuted = try container.decodeIfPresent(Bool.self, forKey: .masterMuted) ?? false
        parts = try container.decodeIfPresent([String: ScoreMixerPartSettings].self, forKey: .parts) ?? [:]
    }

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
