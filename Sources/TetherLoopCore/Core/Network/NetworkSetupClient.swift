import Foundation

@MainActor
public protocol CommandRunning {
    func run(_ executable: String, arguments: [String]) async throws -> String
}

public final class ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(_ executable: String, arguments: [String]) async throws -> String {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            try process.run()
            process.waitUntilExit()

            let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            guard process.terminationStatus == 0 else {
                throw NetworkAdapterError.commandFailed(error.isEmpty ? output : error)
            }
            return output
        }.value
    }
}

public final class NetworkSetupClient {
    private let runner: CommandRunning
    private let executable: String

    @MainActor
    public init(runner: CommandRunning = ProcessCommandRunner(), executable: String = "/usr/sbin/networksetup") {
        self.runner = runner
        self.executable = executable
    }

    @MainActor
    public func hardwarePortOutput() async throws -> String {
        try await runner.run(executable, arguments: ["-listallhardwareports"])
    }

    @MainActor
    public func wifiDevice() async throws -> String {
        let output = try await hardwarePortOutput()
        guard let device = Self.parseWiFiDevice(from: output) else {
            throw NetworkAdapterError.noWiFiDevice
        }
        return device
    }

    @MainActor
    public func currentSSID(device: String) async throws -> String? {
        let output = try await runner.run(executable, arguments: ["-getairportnetwork", device])
        return Self.parseCurrentSSID(from: output)
    }

    @MainActor
    public func preferredSSIDs(device: String) async throws -> [String] {
        let output = try await runner.run(executable, arguments: ["-listpreferredwirelessnetworks", device])
        return Self.parsePreferredSSIDs(from: output)
    }

    @MainActor
    public func join(ssid: String, device: String) async throws {
        let output = try await runner.run(executable, arguments: ["-setairportnetwork", device, ssid])
        if let failure = Self.parseJoinFailure(from: output) {
            throw NetworkAdapterError.commandFailed(failure)
        }
    }

    public static func parseWiFiDevice(from output: String) -> String? {
        let lines = output.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() where line.trimmingCharacters(in: .whitespaces) == "Hardware Port: Wi-Fi" {
            guard index + 1 < lines.count else { continue }
            let next = lines[index + 1].trimmingCharacters(in: .whitespaces)
            if next.hasPrefix("Device:") {
                return next.replacingOccurrences(of: "Device:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    public static func parseCurrentSSID(from output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.localizedCaseInsensitiveContains("not associated") {
            return nil
        }
        guard let range = trimmed.range(of: "Current Wi-Fi Network:") else {
            return nil
        }
        let ssid = trimmed[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return ssid.isEmpty ? nil : ssid
    }

    public static func parseJoinFailure(from output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let failureMarkers = ["failed to join", "could not find network", "error:"]
        let lowered = trimmed.lowercased()
        for marker in failureMarkers where lowered.contains(marker) {
            return trimmed
        }
        return nil
    }

    public static func parsePreferredSSIDs(from output: String) -> [String] {
        output
            .components(separatedBy: .newlines)
            .dropFirst()
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

public final class RecordingCommandRunner: CommandRunning {
    public var outputs: [String: String]
    public private(set) var invocations: [(String, [String])] = []

    public init(outputs: [String: String] = [:]) {
        self.outputs = outputs
    }

    public func run(_ executable: String, arguments: [String]) async throws -> String {
        invocations.append((executable, arguments))
        let key = arguments.joined(separator: " ")
        return outputs[key] ?? ""
    }
}
