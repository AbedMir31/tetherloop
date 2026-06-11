import Foundation

public enum ProtectionStatus: String, Codable, Equatable, CaseIterable {
    case unconfigured
    case monitoring
    case protected
    case paused
    case switching
    case onHotspot
    case failed

    public var displayName: String {
        switch self {
        case .unconfigured: "Setup Required"
        case .monitoring: "Monitoring"
        case .protected: "Protected"
        case .paused: "Paused"
        case .switching: "Switching"
        case .onHotspot: "On Hotspot"
        case .failed: "Failed"
        }
    }

    public var symbolName: String {
        switch self {
        case .unconfigured: "link.badge.plus"
        case .monitoring: "wifi"
        case .protected: "shield.checkered"
        case .paused: "pause.circle"
        case .switching: "arrow.triangle.2.circlepath"
        case .onHotspot: "antenna.radiowaves.left.and.right"
        case .failed: "exclamationmark.triangle"
        }
    }
}
