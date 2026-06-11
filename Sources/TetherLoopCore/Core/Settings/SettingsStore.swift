import Foundation

public protocol SettingsStore {
    func load() -> TetherLoopSettings
    func save(_ settings: TetherLoopSettings) throws
}

public final class InMemorySettingsStore: SettingsStore {
    private var settings: TetherLoopSettings

    public init(_ settings: TetherLoopSettings = TetherLoopSettings()) {
        self.settings = settings
    }

    public func load() -> TetherLoopSettings {
        settings
    }

    public func save(_ settings: TetherLoopSettings) throws {
        self.settings = settings
    }
}
