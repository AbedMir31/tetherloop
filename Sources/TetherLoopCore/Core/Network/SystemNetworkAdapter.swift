import Foundation

public final class SystemNetworkAdapter: NetworkAdapter {
    private let client: NetworkSetupClient
    private var cachedDevice: String?

    public init(client: NetworkSetupClient = NetworkSetupClient()) {
        self.client = client
    }

    public func currentSSID() async throws -> String? {
        try await client.currentSSID(device: wifiDevice())
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
