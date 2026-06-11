import Foundation

public enum ProtectionEvent: Equatable {
    case settingsChanged
    case userProtectNow
    case userPause
    case userTryNow
    case userReturnToWiFi
    case trustedWiFiConnected(String)
    case trustedWiFiDisconnected(String)
    case untrustedWiFiDisconnected
    case trustedWiFiJoinFailed(String, String)
    case hotspotJoinSucceeded(String)
    case hotspotJoinFailed(String)
    case retryTimerFired
}

public enum ProtectionIntent: Equatable {
    case startSleepPrevention
    case stopSleepPrevention
    case scheduleRetry(TimeInterval)
    case record(DiagnosticEvent.Kind, String)
    case none
}

public struct ProtectionTransitionResult: Equatable {
    public let status: ProtectionStatus
    public let intents: [ProtectionIntent]
}

public struct ProtectionStateMachine: Equatable {
    private var settings: TetherLoopSettings
    private let retryPolicy: RetryPolicy
    private var retryAttempt = 0

    public private(set) var status: ProtectionStatus

    public init(settings: TetherLoopSettings, retryPolicy: RetryPolicy = RetryPolicy()) {
        self.settings = settings
        self.retryPolicy = retryPolicy
        self.status = Self.initialStatus(for: settings)
    }

    public mutating func update(settings: TetherLoopSettings) {
        self.settings = settings
        if status == .unconfigured || status == .monitoring || status == .protected || status == .paused {
            status = Self.initialStatus(for: settings)
        }
    }

    public mutating func handle(_ event: ProtectionEvent) -> ProtectionTransitionResult {
        var intents: [ProtectionIntent] = []

        switch event {
        case .settingsChanged:
            status = Self.initialStatus(for: settings)

        case .userProtectNow:
            guard canProtect else {
                status = .unconfigured
                intents.append(.record(.setupRequired, "Protection requires verified setup"))
                break
            }
            status = .protected
            retryAttempt = 0
            if settings.isSleepPreventionEnabled {
                intents.append(.startSleepPrevention)
            }
            intents.append(.record(.protectionEnabled, "Manual protection enabled"))

        case .userPause:
            status = .paused
            intents.append(.stopSleepPrevention)
            intents.append(.record(.protectionPaused, "Protection paused"))

        case .trustedWiFiConnected(let ssid):
            guard status != .paused else { break }
            if canProtect {
                status = settings.isProtectionEnabled ? .protected : .monitoring
                retryAttempt = 0
                intents.append(.record(.trustedNetworkAvailable, "Connected to trusted Wi-Fi: \(ssid)"))
            }

        case .trustedWiFiDisconnected(let ssid):
            guard canProtect, status != .paused else { break }
            status = .switching
            retryAttempt = 0
            intents.append(.record(.trustedNetworkLost, "Trusted Wi-Fi disconnected: \(ssid)"))

        case .untrustedWiFiDisconnected:
            guard canProtect, settings.isGlobalFailoverEnabled, status != .paused else { break }
            status = .switching
            retryAttempt = 0
            intents.append(.record(.trustedNetworkLost, "Wi-Fi disconnected in global mode"))

        case .trustedWiFiJoinFailed(let ssid, let message):
            status = canProtect ? .failed : .unconfigured
            intents.append(.record(.networkError, "Return to Wi-Fi failed for \(ssid): \(message)"))

        case .hotspotJoinSucceeded(let ssid):
            status = .onHotspot
            retryAttempt = 0
            intents.append(.record(.hotspotJoinSucceeded, "Joined hotspot: \(ssid)"))

        case .hotspotJoinFailed(let message):
            guard canProtect else {
                status = .unconfigured
                intents.append(.record(.hotspotJoinFailed, "Hotspot join failed: \(message)"))
                break
            }
            status = .failed
            let delay = retryPolicy.delay(forAttempt: retryAttempt)
            retryAttempt += 1
            intents.append(.record(.hotspotJoinFailed, "Hotspot join failed: \(message)"))
            if let delay {
                intents.append(.record(.retryScheduled, "Retry scheduled in \(Int(delay)) seconds"))
                intents.append(.scheduleRetry(delay))
            }

        case .retryTimerFired, .userTryNow:
            guard canProtect else {
                status = .unconfigured
                break
            }
            status = .switching
            intents.append(.record(.hotspotJoinStarted, "Retrying hotspot join"))

        case .userReturnToWiFi:
            if canProtect {
                status = settings.isProtectionEnabled ? .protected : .monitoring
            } else {
                status = .unconfigured
            }
            intents.append(.record(.manualAction, "Return to Wi-Fi requested"))
        }

        return ProtectionTransitionResult(status: status, intents: intents.isEmpty ? [.none] : intents)
    }

    private var canProtect: Bool {
        settings.isConfigured && settings.isSetupVerified
    }

    private static func initialStatus(for settings: TetherLoopSettings) -> ProtectionStatus {
        guard settings.isConfigured, settings.isSetupVerified else {
            return .unconfigured
        }
        return settings.isProtectionEnabled ? .protected : .monitoring
    }
}
