import AppKit
import Combine
import Foundation

@MainActor
public final class AppModel: ObservableObject {
    @Published public private(set) var settings: TetherLoopSettings
    @Published public private(set) var status: ProtectionStatus = .unconfigured
    @Published public private(set) var diagnostics: [DiagnosticEvent] = []
    @Published public private(set) var networkChoices: [String] = []
    @Published public private(set) var currentSSID: String?
    @Published public private(set) var isRefreshingNetworks = false
    @Published public private(set) var networkChoicesError: String?
    @Published public private(set) var needsLocationPermission = false
    private let settingsStore: SettingsStore
    private let networkAdapter: NetworkAdapter
    private let powerController: PowerAssertionControlling
    private let loginItemController: LoginItemControlling
    private let diagnosticsStore: DiagnosticLogStoring
    private let notificationDispatcher: NotificationDispatching
    private let locationAuthorization: LocationAuthorizing
    private let joinConfirmationAttempts: Int
    private let joinConfirmationDelay: Duration
    private var stateMachine: ProtectionStateMachine
    private var previousSSID: String?
    private var lastTrustedSSID: String?
    private var monitorTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?

    public init(
        settingsStore: SettingsStore,
        networkAdapter: NetworkAdapter,
        powerController: PowerAssertionControlling,
        loginItemController: LoginItemControlling,
        diagnosticsStore: DiagnosticLogStoring,
        notificationDispatcher: NotificationDispatching,
        locationAuthorization: LocationAuthorizing,
        joinConfirmationAttempts: Int = 10,
        joinConfirmationDelay: Duration = .seconds(1)
    ) {
        self.settingsStore = settingsStore
        self.networkAdapter = networkAdapter
        self.powerController = powerController
        self.loginItemController = loginItemController
        self.diagnosticsStore = diagnosticsStore
        self.notificationDispatcher = notificationDispatcher
        self.locationAuthorization = locationAuthorization
        self.joinConfirmationAttempts = joinConfirmationAttempts
        self.joinConfirmationDelay = joinConfirmationDelay
        let loaded = settingsStore.load()
        self.settings = loaded
        self.stateMachine = ProtectionStateMachine(settings: loaded)
        self.status = stateMachine.status
        self.diagnostics = diagnosticsStore.loadEvents()
    }

    public static func live() -> AppModel {
        AppModel(
            settingsStore: UserDefaultsSettingsStore(),
            networkAdapter: SystemNetworkAdapter(),
            powerController: SystemPowerAssertionController(),
            loginItemController: SystemLoginItemController(),
            diagnosticsStore: FileDiagnosticLogStore(),
            notificationDispatcher: UserNotificationDispatcher(),
            locationAuthorization: SystemLocationAuthorization()
        )
    }

    public static func preview() -> AppModel {
        let settings = TetherLoopSettings(
            trustedSSIDs: ["Home Wi-Fi", "Office"],
            hotspotSSID: "Abed's iPhone",
            isSetupVerified: true,
            isProtectionEnabled: true,
            isSleepPreventionEnabled: true,
            isGlobalFailoverEnabled: false,
            launchAtLogin: false
        )
        let store = InMemorySettingsStore(settings)
        let logStore = InMemoryDiagnosticLogStore(events: [
            DiagnosticEvent(kind: .protectionEnabled, message: "Protection enabled"),
            DiagnosticEvent(kind: .trustedNetworkLost, message: "Home Wi-Fi disconnected"),
            DiagnosticEvent(kind: .hotspotJoinSucceeded, message: "Joined Abed's iPhone")
        ])
        return AppModel(
            settingsStore: store,
            networkAdapter: FakeNetworkAdapter(
                currentSSID: "Abed's iPhone",
                preferredSSIDs: ["Home Wi-Fi", "Office", "Abed's iPhone"]
            ),
            powerController: RecordingPowerAssertionController(),
            loginItemController: RecordingLoginItemController(),
            diagnosticsStore: logStore,
            notificationDispatcher: RecordingNotificationDispatcher(),
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: true)
        )
    }

    public var trustedSSIDs: [String] {
        settings.trustedSSIDs.sorted()
    }

    public var selectableSSIDs: [String] {
        let savedHotspot = [settings.hotspotSSID].compactMap { $0 }
        return Self.sortedUniqueSSIDs(networkChoices + trustedSSIDs + savedHotspot)
    }

    public var setupSummary: String {
        guard let hotspot = settings.hotspotSSID, !settings.trustedSSIDs.isEmpty else {
            return "Setup incomplete"
        }
        return settings.isSetupVerified
            ? "Verified for \(hotspot)"
            : "Test required for \(hotspot)"
    }

    public func addTrustedSSID(_ ssid: String) {
        let trimmed = ssid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateSettings { $0.trustedSSIDs.insert(trimmed) }
        record(.settingsChanged, "Added trusted Wi-Fi: \(trimmed)")
    }

    public func removeTrustedSSID(_ ssid: String) {
        updateSettings { $0.trustedSSIDs.remove(ssid) }
        record(.settingsChanged, "Removed trusted Wi-Fi: \(ssid)")
    }

    public func setHotspotSSID(_ ssid: String) {
        let trimmed = ssid.trimmingCharacters(in: .whitespacesAndNewlines)
        cancelRetry()
        updateSettings {
            $0.hotspotSSID = trimmed.isEmpty ? nil : trimmed
            $0.isSetupVerified = false
        }
        record(.settingsChanged, "Updated hotspot target")
    }

    public func refreshNetworkChoices() async {
        guard !isRefreshingNetworks else { return }
        isRefreshingNetworks = true
        defer { isRefreshingNetworks = false }

        var ssids: [String] = []
        var firstError: Error?

        do {
            ssids.append(contentsOf: try await networkAdapter.preferredSSIDs())
        } catch {
            firstError = error
        }

        var detectedCurrentSSID: String?

        do {
            let state = try await networkAdapter.currentNetwork()
            switch state {
            case .associated(let ssid?):
                detectedCurrentSSID = ssid
                ssids.append(ssid)
                needsLocationPermission = false
            case .associated(nil):
                needsLocationPermission = true
            case .disconnected:
                break
            }
        } catch {
            if firstError == nil {
                firstError = error
            }
        }

        currentSSID = detectedCurrentSSID
        let choices = Self.sortedUniqueSSIDs(ssids)
        networkChoices = choices
        defaultTrustedSSIDIfNeeded(detectedCurrentSSID)

        if choices.isEmpty, let firstError {
            let message = firstError.localizedDescription
            if networkChoicesError != message {
                record(.networkError, "Could not load remembered Wi-Fi networks: \(message)")
            }
            networkChoicesError = message
        } else {
            networkChoicesError = nil
        }
    }

    public func setProtectionEnabled(_ enabled: Bool) {
        if !enabled {
            cancelRetry()
        }
        updateSettings { $0.isProtectionEnabled = enabled }
        handle(.settingsChanged)
        applySleepPreventionIfNeeded()
        record(enabled ? .protectionEnabled : .protectionPaused, enabled ? "Protection enabled" : "Protection disabled")
    }

    public func setSleepPreventionEnabled(_ enabled: Bool) {
        updateSettings { $0.isSleepPreventionEnabled = enabled }
        applySleepPreventionIfNeeded()
    }

    public func setGlobalFailoverEnabled(_ enabled: Bool) {
        updateSettings { $0.isGlobalFailoverEnabled = enabled }
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginItemController.setEnabled(enabled)
            updateSettings { $0.launchAtLogin = enabled }
            record(.settingsChanged, enabled ? "Launch at login enabled" : "Launch at login disabled")
        } catch {
            record(.settingsChanged, "Launch at login update failed: \(error.localizedDescription)")
        }
    }

    public func requestLocationPermission() {
        locationAuthorization.requestAuthorization()
        record(.settingsChanged, "Requested Location access for Wi-Fi network detection")
    }

    public func protectNow() {
        handle(.userProtectNow)
    }

    public func pauseProtection() {
        cancelRetry()
        handle(.userPause)
    }

    public func tryHotspotNow() {
        handle(.userTryNow)
        Task { await joinHotspotIfPossible(reason: "Manual hotspot attempt") }
    }

    public func runSetupVerificationTest() async {
        await verifyHotspotSetup()
    }

    public func returnToWiFi() async {
        cancelRetry()
        handle(.userReturnToWiFi)
        guard let target = returnWiFiTarget() else {
            record(.networkError, "Return to Wi-Fi failed: no trusted Wi-Fi network is configured")
            return
        }

        record(.manualAction, "Return to Wi-Fi requested: \(target)")
        do {
            try await networkAdapter.join(ssid: target)
            guard await confirmJoin(to: target) else {
                let message = "Join command completed but \(target) never became the current network"
                handle(.trustedWiFiJoinFailed(target, message))
                notificationDispatcher.notify(title: "TetherLoop could not return to Wi-Fi", body: message)
                return
            }
            previousSSID = target
            lastTrustedSSID = target
            handle(.trustedWiFiConnected(target))
            record(.manualAction, "Returned to Wi-Fi: \(target)")
            notificationDispatcher.notify(title: "TetherLoop returned to Wi-Fi", body: target)
        } catch {
            handle(.trustedWiFiJoinFailed(target, error.localizedDescription))
            notificationDispatcher.notify(title: "TetherLoop could not return to Wi-Fi", body: error.localizedDescription)
        }
    }

    public func startMonitoring(intervalSeconds: UInt64 = 5) {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollNetwork()
                try? await Task.sleep(for: .seconds(intervalSeconds))
            }
        }
    }

    public func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
        cancelRetry()
    }

    public func pollNetwork() async {
        do {
            let state = try await networkAdapter.currentNetwork()
            let current: String?
            switch state {
            case .associated(let ssid?):
                needsLocationPermission = false
                current = ssid
            case .associated(nil):
                // Associated but SSID unreadable: do NOT treat as a disconnect.
                if !needsLocationPermission {
                    needsLocationPermission = true
                    record(.networkError, "Wi-Fi SSID is unreadable. Grant TetherLoop Location access in System Settings > Privacy & Security > Location Services so trusted-network detection can work.")
                }
                return
            case .disconnected:
                current = nil
            }
            defer { previousSSID = current }

            if let current, settings.trustedSSIDs.contains(current) {
                lastTrustedSSID = current
                handle(.trustedWiFiConnected(current))
                return
            }

            guard current == nil else { return }

            if let previousSSID, settings.trustedSSIDs.contains(previousSSID) {
                lastTrustedSSID = previousSSID
                let result = handle(.trustedWiFiDisconnected(previousSSID))
                if result.status == .switching {
                    await joinHotspotIfPossible(reason: "Trusted Wi-Fi disconnected")
                }
            } else if settings.isGlobalFailoverEnabled, previousSSID != nil {
                let result = handle(.untrustedWiFiDisconnected)
                if result.status == .switching {
                    await joinHotspotIfPossible(reason: "Wi-Fi disconnected in global mode")
                }
            }
        } catch {
            record(.networkError, "Network poll failed: \(error.localizedDescription)")
        }
    }

    private func confirmJoin(to target: String) async -> Bool {
        for attempt in 0..<joinConfirmationAttempts {
            if let state = try? await networkAdapter.currentNetwork() {
                switch state {
                case .associated(let ssid?) where ssid == target:
                    return true
                case .associated(nil):
                    // SSID unreadable (no Location permission): we cannot disprove
                    // the join; trust the command result rather than failing falsely.
                    return true
                default:
                    break
                }
            }
            if attempt < joinConfirmationAttempts - 1 {
                try? await Task.sleep(for: joinConfirmationDelay)
            }
        }
        return false
    }

    private func joinHotspotIfPossible(reason: String) async {
        guard let hotspot = settings.hotspotSSID, settings.isSetupVerified || reason.contains("Manual") else {
            record(.hotspotJoinFailed, "Hotspot is not verified")
            return
        }
        record(.hotspotJoinStarted, "\(reason): \(hotspot)")
        do {
            try await networkAdapter.join(ssid: hotspot)
            guard await confirmJoin(to: hotspot) else {
                handle(.hotspotJoinFailed("Join command completed but \(hotspot) never became the current network"))
                record(.hotspotJoinFailed, "Could not confirm join to \(hotspot)")
                notificationDispatcher.notify(title: "TetherLoop could not join hotspot", body: "\(hotspot) did not become the current network")
                return
            }
            cancelRetry()
            handle(.hotspotJoinSucceeded(hotspot))
            record(.hotspotJoinSucceeded, "Joined \(hotspot)")
            notificationDispatcher.notify(title: "TetherLoop switched to hotspot", body: hotspot)
        } catch {
            handle(.hotspotJoinFailed(error.localizedDescription))
            record(.hotspotJoinFailed, "Could not join \(hotspot): \(error.localizedDescription)")
            notificationDispatcher.notify(title: "TetherLoop could not join hotspot", body: error.localizedDescription)
        }
    }

    private func verifyHotspotSetup() async {
        guard let hotspot = settings.hotspotSSID else {
            record(.setupRequired, "Choose a hotspot before running setup verification")
            return
        }

        let originalSSID = try? await networkAdapter.currentSSID()
        record(.hotspotJoinStarted, "Testing hotspot target: \(hotspot)")

        do {
            try await networkAdapter.join(ssid: hotspot)
            guard await confirmJoin(to: hotspot) else {
                updateSettings { $0.isSetupVerified = false }
                record(.hotspotJoinFailed, "Setup verification failed: \(hotspot) never became the current network")
                notificationDispatcher.notify(title: "TetherLoop setup failed", body: "\(hotspot) did not become the current network")
                return
            }
            updateSettings { $0.isSetupVerified = true }
            handle(.settingsChanged)
            record(.setupVerified, "Setup verification completed")
            notificationDispatcher.notify(title: "TetherLoop setup verified", body: hotspot)

            if let originalSSID, originalSSID != hotspot {
                try? await networkAdapter.join(ssid: originalSSID)
                if settings.trustedSSIDs.contains(originalSSID) {
                    lastTrustedSSID = originalSSID
                }
                record(.manualAction, "Returned to Wi-Fi: \(originalSSID)")
            }
        } catch {
            updateSettings { $0.isSetupVerified = false }
            record(.hotspotJoinFailed, "Setup verification failed: \(error.localizedDescription)")
            notificationDispatcher.notify(title: "TetherLoop setup failed", body: error.localizedDescription)
        }
    }

    private func updateSettings(_ mutate: (inout TetherLoopSettings) -> Void) {
        var copy = settings
        mutate(&copy)
        settings = copy
        stateMachine.update(settings: copy)
        try? settingsStore.save(copy)
        status = stateMachine.status
    }

    @discardableResult
    private func handle(_ event: ProtectionEvent) -> ProtectionTransitionResult {
        let result = stateMachine.handle(event)
        status = result.status
        apply(intents: result.intents)
        return result
    }

    private func apply(intents: [ProtectionIntent]) {
        for intent in intents {
            switch intent {
            case .startSleepPrevention:
                try? powerController.enable(reason: "TetherLoop protection is active")
            case .stopSleepPrevention:
                try? powerController.disable()
            case .scheduleRetry(let delay):
                scheduleRetry(after: delay)
            case .record(let kind, let message):
                record(kind, message)
            case .none:
                break
            }
        }
    }

    private func applySleepPreventionIfNeeded() {
        if settings.isSleepPreventionEnabled && settings.isProtectionEnabled && status != .paused {
            try? powerController.enable(reason: "TetherLoop protection is active")
        } else {
            try? powerController.disable()
        }
    }

    private func record(_ kind: DiagnosticEvent.Kind, _ message: String) {
        let event = DiagnosticEvent(kind: kind, message: message)
        diagnosticsStore.append(event)
        diagnostics = diagnosticsStore.loadEvents()
    }

    private func returnWiFiTarget() -> String? {
        if let lastTrustedSSID, settings.trustedSSIDs.contains(lastTrustedSSID) {
            return lastTrustedSSID
        }
        return settings.trustedSSIDs.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }.first
    }

    private func scheduleRetry(after delay: TimeInterval) {
        cancelRetry()
        retryTask = Task { [weak self] in
            if delay > 0 {
                let nanoseconds = UInt64(delay * 1_000_000_000)
                do {
                    try await Task.sleep(nanoseconds: nanoseconds)
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }
            await self?.retryHotspotJoin()
        }
    }

    private func retryHotspotJoin() async {
        retryTask = nil
        handle(.retryTimerFired)
        await joinHotspotIfPossible(reason: "Retry hotspot attempt")
    }

    private func cancelRetry() {
        retryTask?.cancel()
        retryTask = nil
    }

    private func defaultTrustedSSIDIfNeeded(_ ssid: String?) {
        guard settings.trustedSSIDs.isEmpty,
              let ssid,
              ssid != settings.hotspotSSID else {
            return
        }

        updateSettings { $0.trustedSSIDs.insert(ssid) }
        record(.settingsChanged, "Defaulted trusted Wi-Fi to current network: \(ssid)")
    }

    private static func sortedUniqueSSIDs(_ ssids: [String]) -> [String] {
        let cleaned = ssids
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(cleaned)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }
}
