import Foundation

public enum WiFiNetworkState: Equatable, Sendable {
    case disconnected
    case associated(ssid: String?)   // ssid nil = associated but unreadable (no Location permission)
}

@MainActor
public protocol NetworkAdapter {
    func currentNetwork() async throws -> WiFiNetworkState
    func preferredSSIDs() async throws -> [String]
    func join(ssid: String) async throws
}

public extension NetworkAdapter {
    func currentSSID() async throws -> String? {
        if case .associated(let ssid) = try await currentNetwork() { return ssid }
        return nil
    }
}

public enum NetworkAdapterError: Error, LocalizedError, Equatable {
    case noWiFiDevice
    case commandFailed(String)
    case malformedOutput(String)

    public var errorDescription: String? {
        switch self {
        case .noWiFiDevice:
            "No Wi-Fi device was found."
        case .commandFailed(let message):
            message
        case .malformedOutput(let output):
            "Could not parse network output: \(output)"
        }
    }
}

public final class FakeNetworkAdapter: NetworkAdapter {
    public var current: String?
    public var preferred: [String]
    public var joinError: Error?
    public var joinResults: [Result<Void, Error>] = []
    public private(set) var joinAttempts: [String] = []
    public private(set) var joinedSSIDs: [String] = []
    public var associatedWithoutSSID = false

    public init(currentSSID: String? = nil, preferredSSIDs: [String] = []) {
        self.current = currentSSID
        self.preferred = preferredSSIDs
    }

    public func currentNetwork() async throws -> WiFiNetworkState {
        if let current { return .associated(ssid: current) }
        return associatedWithoutSSID ? .associated(ssid: nil) : .disconnected
    }

    public func currentSSID() async throws -> String? {
        current
    }

    public func preferredSSIDs() async throws -> [String] {
        preferred
    }

    public func join(ssid: String) async throws {
        joinAttempts.append(ssid)

        if !joinResults.isEmpty {
            let result = joinResults.removeFirst()
            switch result {
            case .success:
                joinedSSIDs.append(ssid)
                current = ssid
                return
            case .failure(let error):
                throw error
            }
        }

        if let joinError {
            throw joinError
        }
        joinedSSIDs.append(ssid)
        current = ssid
    }
}
