import Foundation

@MainActor
public protocol NetworkAdapter {
    func currentSSID() async throws -> String?
    func preferredSSIDs() async throws -> [String]
    func join(ssid: String) async throws
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

    public init(currentSSID: String? = nil, preferredSSIDs: [String] = []) {
        self.current = currentSSID
        self.preferred = preferredSSIDs
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
