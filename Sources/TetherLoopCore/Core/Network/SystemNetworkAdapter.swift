import Foundation

public final class SystemNetworkAdapter: NetworkAdapter {
    private let client: NetworkSetupClient
    private let coreWLAN: CoreWLANClient
    private var cachedDevice: String?

    public init(client: NetworkSetupClient = NetworkSetupClient(), coreWLAN: CoreWLANClient = CoreWLANClient()) {
        self.client = client
        self.coreWLAN = coreWLAN
    }

    public func currentNetwork() async throws -> WiFiNetworkState {
        let state = coreWLAN.currentNetwork()
        if case .associated(ssid: nil) = state {
            // Older macOS can still answer via networksetup; try before giving up on the SSID.
            if let legacy = try? await client.currentSSID(device: wifiDevice()) {
                return .associated(ssid: legacy)
            }
        }
        return state
    }

    public func preferredSSIDs() async throws -> [String] {
        try await client.preferredSSIDs(device: wifiDevice())
    }

    public func join(ssid: String) async throws {
        try await client.join(ssid: ssid, device: wifiDevice())
    }

    private func wifiDevice() async throws -> String {
        if let cachedDevice {
            return cachedDevice
        }
        let device = try await client.wifiDevice()
        cachedDevice = device
        return device
    }
}
