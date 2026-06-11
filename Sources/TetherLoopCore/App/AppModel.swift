import AppKit
import Combine
import Foundation

@MainActor
public final class AppModel: ObservableObject {
    @Published public private(set) var settings: TetherLoopSettings
    @Published public private(set) var status: ProtectionStatus = .unconfigured
    @Published public private(set) var diagnostics: [DiagnosticEvent] = []
    @Published public private(set) var networkChoices: [String] = []
    @Published public private(set) var isRefreshingNetworks = false
    @Published public private(set) var networkChoicesError: String?
    private let settingsStore: SettingsStore
    private let networkAdapter: NetworkAdapter
    private let powerController: PowerAssertionControlling
    private let loginItemController: LoginItemControlling
    private let diagnosticsStore: DiagnosticLogStoring
    private let notificationDispatcher: NotificationDispatching
    private var stateMachine: ProtectionStateMachine
    private var previousSSID: String?
    private var monitorTask: Task<Void, Never>?

    public init(
        settingsStore: SettingsStore,
        networkAdapter: NetworkAdapter,
        powerController: PowerAssertionControlling,
        loginItemController: LoginItemControlling,
        diagnosticsStore: DiagnosticLogStoring,
        notificationDispatcher: NotificationDispatching
    ) {
        self.settingsStore = settingsStore
        self.networkAdapter = networkAdapter
        self.powerController = powerController
        self.loginItemController = loginItemController
        self.diagnosticsStore = diagnosticsStore
        self.notificationDispatcher = notificationDispatcher
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
            notificationDispatcher: UserNotificationDispatcher()
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
            notificationDispatcher: RecordingNotificationDispatcher()
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

        do {
            if let currentSSID = try await networkAdapter.currentSSID() {
                ssids.append(currentSSID)
            }
        } catch {
            if firstError == nil {
                firstError = error
            }
        }

        let choices = Self.sortedUniqueSSIDs(ssids)
        networkChoices = choices

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
        updateSettings { $0.isProtectionEnabled = enabled }
        handle(.settingsChanged)
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

    public func protectNow() {
        handle(.userProtectNow)
    }

    public func pauseProtection() {
        handle(.userPause)
    }

    public func tryHotspotNow() {
        handle(.userTryNow)
        Task { await joinHotspotIfPossible(reason: "Manual hotspot attempt") }
    }

    public func runSetupVerificationTest() async {
        await verifyHotspotSetup()
    }

    public func returnToWiFi() {
        handle(.userReturnToWiFi)
        record(.manualAction, "Return to Wi-Fi requested")
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
    }

    public func pollNetwork() async {
        do {
            let current = try await networkAdapter.currentSSID()
            defer { previousSSID = current }

            if let current, settings.trustedSSIDs.contains(current) {
                handle(.trustedWiFiConnected(current))
                return
            }

            if current == nil, let previousSSID, settings.trustedSSIDs.contains(previousSSID) {
                handle(.trustedWiFiDisconnected(previousSSID))
                await joinHotspotIfPossible(reason: "Trusted Wi-Fi disconnected")
            }
        } catch {
            record(.networkError, "Network poll failed: \(error.localizedDescription)")
        }
    }

    private func joinHotspotIfPossible(reason: String) async {
        guard let hotspot = settings.hotspotSSID, settings.isSetupVerified || reason.contains("Manual") else {
            record(.hotspotJoinFailed, "Hotspot is not verified")
            return
        }
        record(.hotspotJoinStarted, "\(reason): \(hotspot)")
        do {
            try await networkAdapter.join(ssid: hotspot)
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
            updateSettings { $0.isSetupVerified = true }
            handle(.settingsChanged)
            record(.setupVerified, "Setup verification completed")
            notificationDispatcher.notify(title: "TetherLoop setup verified", body: hotspot)

            if let originalSSID, originalSSID != hotspot {
                try? await networkAdapter.join(ssid: originalSSID)
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

    private func handle(_ event: ProtectionEvent) {
        let result = stateMachine.handle(event)
        status = result.status
        apply(intents: result.intents)
    }

    private func apply(intents: [ProtectionIntent]) {
        for intent in intents {
            switch intent {
            case .startSleepPrevention:
                try? powerController.enable(reason: "TetherLoop protection is active")
            case .stopSleepPrevention:
                try? powerController.disable()
            case .record(let kind, let message):
                record(kind, message)
            case .none:
                break
            }
        }
    }

    private func applySleepPreventionIfNeeded() {
        if settings.isSleepPreventionEnabled && settings.isProtectionEnabled {
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

    private static func sortedUniqueSSIDs(_ ssids: [String]) -> [String] {
        let cleaned = ssids
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(cleaned)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }
}
