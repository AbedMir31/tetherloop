import AppKit
import Foundation

public struct ProcessSnapshot: Equatable, Sendable {
    public let name: String
    public let bundleIdentifier: String?

    public init(name: String, bundleIdentifier: String? = nil) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
    }
}

public protocol ProcessSnapshotProviding {
    func runningProcesses() -> [ProcessSnapshot]
}

public final class WorkspaceProcessSnapshotProvider: ProcessSnapshotProviding {
    public init() {}

    public func runningProcesses() -> [ProcessSnapshot] {
        NSWorkspace.shared.runningApplications.map {
            ProcessSnapshot(
                name: $0.localizedName ?? $0.bundleIdentifier ?? "Unknown",
                bundleIdentifier: $0.bundleIdentifier
            )
        }
    }
}

public final class StaticProcessSnapshotProvider: ProcessSnapshotProviding {
    private let snapshots: [ProcessSnapshot]

    public init(_ snapshots: [ProcessSnapshot]) {
        self.snapshots = snapshots
    }

    public func runningProcesses() -> [ProcessSnapshot] {
        snapshots
    }
}
