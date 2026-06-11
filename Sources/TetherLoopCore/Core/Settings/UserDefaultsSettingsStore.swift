import Foundation

public final class UserDefaultsSettingsStore: SettingsStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "tetherloop.settings") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> TetherLoopSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(TetherLoopSettings.self, from: data) else {
            return TetherLoopSettings()
        }
        return settings
    }

    public func save(_ settings: TetherLoopSettings) throws {
        let data = try JSONEncoder().encode(settings)
        defaults.set(data, forKey: key)
    }
}
