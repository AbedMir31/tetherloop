import Foundation

public struct TetherLoopSettings: Codable, Equatable, Sendable {
    public var trustedSSIDs: Set<String>
    public var hotspotSSID: String?
    public var isSetupVerified: Bool
    public var isProtectionEnabled: Bool
    public var isSleepPreventionEnabled: Bool
    public var isGlobalFailoverEnabled: Bool
    public var launchAtLogin: Bool

    public init(
        trustedSSIDs: Set<String> = [],
        hotspotSSID: String? = nil,
        isSetupVerified: Bool = false,
        isProtectionEnabled: Bool = false,
        isSleepPreventionEnabled: Bool = false,
        isGlobalFailoverEnabled: Bool = false,
        launchAtLogin: Bool = false
    ) {
        self.trustedSSIDs = trustedSSIDs
        self.hotspotSSID = hotspotSSID
        self.isSetupVerified = isSetupVerified
        self.isProtectionEnabled = isProtectionEnabled
        self.isSleepPreventionEnabled = isSleepPreventionEnabled
        self.isGlobalFailoverEnabled = isGlobalFailoverEnabled
        self.launchAtLogin = launchAtLogin
    }

    public var isConfigured: Bool {
        !trustedSSIDs.isEmpty && hotspotSSID?.isEmpty == false
    }
}
