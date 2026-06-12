import XCTest
@testable import TetherLoopCore

@MainActor
final class ViewModelTests: XCTestCase {
    func testAddingTrustedNetworkPersistsSettings() {
        let store = InMemorySettingsStore()
        let model = AppModel(
            settingsStore: store,
            networkAdapter: FakeNetworkAdapter(),
            powerController: RecordingPowerAssertionController(),
            loginItemController: RecordingLoginItemController(),
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: RecordingNotificationDispatcher(),
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: true)
        )

        model.addTrustedSSID("Home")

        XCTAssertEqual(store.load().trustedSSIDs, ["Home"])
        XCTAssertEqual(model.trustedSSIDs, ["Home"])
    }

    func testSettingHotspotInvalidatesVerification() {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: "Old",
            isSetupVerified: true
        ))
        let model = AppModel(
            settingsStore: store,
            networkAdapter: FakeNetworkAdapter(),
            powerController: RecordingPowerAssertionController(),
            loginItemController: RecordingLoginItemController(),
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: RecordingNotificationDispatcher(),
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: true)
        )

        model.setHotspotSSID("New")

        XCTAssertEqual(model.settings.hotspotSSID, "New")
        XCTAssertFalse(model.settings.isSetupVerified)
    }

    func testSetupVerificationMarksVerifiedOnlyAfterJoinSucceeds() async {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: "Phone",
            isSetupVerified: false
        ))
        let network = FakeNetworkAdapter(currentSSID: "Home")
        let model = AppModel(
            settingsStore: store,
            networkAdapter: network,
            powerController: RecordingPowerAssertionController(),
            loginItemController: RecordingLoginItemController(),
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: RecordingNotificationDispatcher(),
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: true)
        )

        await model.runSetupVerificationTest()

        XCTAssertTrue(model.settings.isSetupVerified)
        XCTAssertEqual(network.joinedSSIDs, ["Phone", "Home"])
    }

    func testSetupVerificationFailureStaysUnverified() async {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: "Phone",
            isSetupVerified: false
        ))
        let network = FakeNetworkAdapter(currentSSID: "Home")
        network.joinError = NetworkAdapterError.commandFailed("not found")
        let model = AppModel(
            settingsStore: store,
            networkAdapter: network,
            powerController: RecordingPowerAssertionController(),
            loginItemController: RecordingLoginItemController(),
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: RecordingNotificationDispatcher(),
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: true)
        )

        await model.runSetupVerificationTest()

        XCTAssertFalse(model.settings.isSetupVerified)
    }

    func testReturnToWiFiJoinsLastTrustedNetwork() async {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Home", "Office"],
            hotspotSSID: "Phone",
            isSetupVerified: true,
            isProtectionEnabled: true
        ))
        let network = FakeNetworkAdapter(currentSSID: "Office")
        let model = AppModel(
            settingsStore: store,
            networkAdapter: network,
            powerController: RecordingPowerAssertionController(),
            loginItemController: RecordingLoginItemController(),
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: RecordingNotificationDispatcher(),
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: true)
        )

        await model.pollNetwork()
        network.current = "Phone"
        await model.returnToWiFi()

        XCTAssertEqual(network.joinAttempts, ["Office"])
        XCTAssertEqual(network.current, "Office")
    }

    func testReturnToWiFiFallsBackToFirstTrustedNetwork() async {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Office", "Home"],
            hotspotSSID: "Phone",
            isSetupVerified: true,
            isProtectionEnabled: true
        ))
        let network = FakeNetworkAdapter(currentSSID: "Phone")
        let model = AppModel(
            settingsStore: store,
            networkAdapter: network,
            powerController: RecordingPowerAssertionController(),
            loginItemController: RecordingLoginItemController(),
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: RecordingNotificationDispatcher(),
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: true)
        )

        await model.returnToWiFi()

        XCTAssertEqual(network.joinAttempts, ["Home"])
        XCTAssertEqual(network.current, "Home")
    }

    func testReturnToWiFiFailureDoesNotScheduleHotspotRetry() async throws {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: "Phone",
            isSetupVerified: true,
            isProtectionEnabled: true
        ))
        let network = FakeNetworkAdapter(currentSSID: "Phone")
        network.joinResults = [
            .failure(NetworkAdapterError.commandFailed("join failed")),
            .success(())
        ]
        let model = AppModel(
            settingsStore: store,
            networkAdapter: network,
            powerController: RecordingPowerAssertionController(),
            loginItemController: RecordingLoginItemController(),
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: RecordingNotificationDispatcher(),
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: true)
        )

        await model.returnToWiFi()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(network.joinAttempts, ["Home"])
        XCTAssertEqual(network.current, "Phone")
        XCTAssertEqual(model.status, .failed)
    }

    func testTrustedDisconnectRetriesHotspotAfterFailure() async throws {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: "Phone",
            isSetupVerified: true,
            isProtectionEnabled: true
        ))
        let network = FakeNetworkAdapter(currentSSID: "Home")
        network.joinResults = [
            .failure(NetworkAdapterError.commandFailed("not found")),
            .success(())
        ]
        let model = AppModel(
            settingsStore: store,
            networkAdapter: network,
            powerController: RecordingPowerAssertionController(),
            loginItemController: RecordingLoginItemController(),
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: RecordingNotificationDispatcher(),
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: true)
        )

        await model.pollNetwork()
        network.current = nil
        await model.pollNetwork()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(network.joinAttempts, ["Phone", "Phone"])
        XCTAssertEqual(network.current, "Phone")
        XCTAssertEqual(model.status, .onHotspot)
    }

    func testDisablingProtectionCancelsScheduledRetry() async throws {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: "Phone",
            isSetupVerified: true,
            isProtectionEnabled: true
        ))
        let network = FakeNetworkAdapter(currentSSID: "Home")
        network.joinResults = [
            .failure(NetworkAdapterError.commandFailed("first failure")),
            .failure(NetworkAdapterError.commandFailed("second failure")),
            .success(())
        ]
        let model = AppModel(
            settingsStore: store,
            networkAdapter: network,
            powerController: RecordingPowerAssertionController(),
            loginItemController: RecordingLoginItemController(),
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: RecordingNotificationDispatcher(),
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: true)
        )

        await model.pollNetwork()
        network.current = nil
        await model.pollNetwork()
        try await Task.sleep(nanoseconds: 50_000_000)

        model.setProtectionEnabled(false)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(network.joinAttempts, ["Phone", "Phone"])
        XCTAssertNil(network.current)
    }

    func testGlobalFailoverJoinsHotspotAfterUntrustedDisconnectWhenEnabled() async {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: "Phone",
            isSetupVerified: true,
            isProtectionEnabled: true,
            isGlobalFailoverEnabled: true
        ))
        let network = FakeNetworkAdapter(currentSSID: "Cafe")
        let model = AppModel(
            settingsStore: store,
            networkAdapter: network,
            powerController: RecordingPowerAssertionController(),
            loginItemController: RecordingLoginItemController(),
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: RecordingNotificationDispatcher(),
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: true)
        )

        await model.pollNetwork()
        network.current = nil
        await model.pollNetwork()

        XCTAssertEqual(network.joinAttempts, ["Phone"])
        XCTAssertEqual(network.current, "Phone")
    }

    func testGlobalFailoverDoesNotResetRetryWhileAlreadyDisconnected() async throws {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: "Phone",
            isSetupVerified: true,
            isProtectionEnabled: true,
            isGlobalFailoverEnabled: true
        ))
        let network = FakeNetworkAdapter(currentSSID: "Cafe")
        network.joinResults = [
            .failure(NetworkAdapterError.commandFailed("first failure")),
            .failure(NetworkAdapterError.commandFailed("second failure")),
            .success(())
        ]
        let model = AppModel(
            settingsStore: store,
            networkAdapter: network,
            powerController: RecordingPowerAssertionController(),
            loginItemController: RecordingLoginItemController(),
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: RecordingNotificationDispatcher(),
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: true)
        )

        await model.pollNetwork()
        network.current = nil
        await model.pollNetwork()
        try await Task.sleep(nanoseconds: 50_000_000)

        await model.pollNetwork()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(network.joinAttempts, ["Phone", "Phone"])
        XCTAssertNil(network.current)
        XCTAssertEqual(model.status, .failed)
        model.setProtectionEnabled(false)
    }

    func testUntrustedDisconnectDoesNotJoinHotspotWhenGlobalFailoverIsDisabled() async {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: "Phone",
            isSetupVerified: true,
            isProtectionEnabled: true,
            isGlobalFailoverEnabled: false
        ))
        let network = FakeNetworkAdapter(currentSSID: "Cafe")
        let model = AppModel(
            settingsStore: store,
            networkAdapter: network,
            powerController: RecordingPowerAssertionController(),
            loginItemController: RecordingLoginItemController(),
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: RecordingNotificationDispatcher(),
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: true)
        )

        await model.pollNetwork()
        network.current = nil
        await model.pollNetwork()

        XCTAssertTrue(network.joinAttempts.isEmpty)
    }

    func testLaunchAtLoginCallsControllerBeforePersisting() {
        let store = InMemorySettingsStore()
        let login = RecordingLoginItemController()
        let model = AppModel(
            settingsStore: store,
            networkAdapter: FakeNetworkAdapter(),
            powerController: RecordingPowerAssertionController(),
            loginItemController: login,
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: RecordingNotificationDispatcher(),
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: true)
        )

        model.setLaunchAtLogin(true)

        XCTAssertEqual(login.requestedValues, [true])
        XCTAssertTrue(store.load().launchAtLogin)
    }

    func testPausedProtectionDoesNotJoinHotspotOnTrustedDisconnect() async {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: "Phone",
            isSetupVerified: true,
            isProtectionEnabled: true
        ))
        let network = FakeNetworkAdapter(currentSSID: "Home")
        let model = AppModel(
            settingsStore: store,
            networkAdapter: network,
            powerController: RecordingPowerAssertionController(),
            loginItemController: RecordingLoginItemController(),
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: RecordingNotificationDispatcher(),
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: true)
        )

        await model.pollNetwork()
        model.pauseProtection()
        network.current = nil
        await model.pollNetwork()

        XCTAssertTrue(network.joinAttempts.isEmpty)
        XCTAssertEqual(model.status, .paused)
    }

    func testDisabledProtectionDoesNotJoinHotspotOnTrustedDisconnect() async {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: "Phone",
            isSetupVerified: true,
            isProtectionEnabled: false
        ))
        let network = FakeNetworkAdapter(currentSSID: "Home")
        let model = AppModel(
            settingsStore: store,
            networkAdapter: network,
            powerController: RecordingPowerAssertionController(),
            loginItemController: RecordingLoginItemController(),
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: RecordingNotificationDispatcher(),
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: true)
        )

        await model.pollNetwork()
        network.current = nil
        await model.pollNetwork()

        XCTAssertTrue(network.joinAttempts.isEmpty)
        XCTAssertNotEqual(model.status, .switching)
        XCTAssertNotEqual(model.status, .onHotspot)
    }

    func testProtectNowArmsFailoverEvenWhenToggleIsOff() async {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: "Phone",
            isSetupVerified: true,
            isProtectionEnabled: false
        ))
        let network = FakeNetworkAdapter(currentSSID: "Home")
        let model = AppModel(
            settingsStore: store,
            networkAdapter: network,
            powerController: RecordingPowerAssertionController(),
            loginItemController: RecordingLoginItemController(),
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: RecordingNotificationDispatcher(),
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: true)
        )

        // Poll once to record previousSSID = "Home", then manually arm protection.
        await model.pollNetwork()
        model.protectNow()
        XCTAssertEqual(model.status, .protected)
        network.current = nil
        await model.pollNetwork()

        XCTAssertEqual(network.joinAttempts, ["Phone"])
    }

    func testPausedGlobalFailoverDoesNotJoinHotspot() async {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: "Phone",
            isSetupVerified: true,
            isProtectionEnabled: true,
            isGlobalFailoverEnabled: true
        ))
        let network = FakeNetworkAdapter(currentSSID: "Cafe")
        let model = AppModel(
            settingsStore: store,
            networkAdapter: network,
            powerController: RecordingPowerAssertionController(),
            loginItemController: RecordingLoginItemController(),
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: RecordingNotificationDispatcher(),
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: true)
        )

        await model.pollNetwork()
        model.pauseProtection()
        network.current = nil
        await model.pollNetwork()

        XCTAssertTrue(network.joinAttempts.isEmpty)
        XCTAssertEqual(model.status, .paused)
    }

    func testRefreshNetworkChoicesIncludesRememberedCurrentAndSavedNetworks() async {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: "Phone"
        ))
        let network = FakeNetworkAdapter(
            currentSSID: "Cafe",
            preferredSSIDs: ["Phone", "Home", "Phone", "  "]
        )
        let model = AppModel(
            settingsStore: store,
            networkAdapter: network,
            powerController: RecordingPowerAssertionController(),
            loginItemController: RecordingLoginItemController(),
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: RecordingNotificationDispatcher(),
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: true)
        )

        await model.refreshNetworkChoices()

        XCTAssertEqual(model.networkChoices, ["Cafe", "Home", "Phone"])
        XCTAssertEqual(model.selectableSSIDs, ["Cafe", "Home", "Phone"])
        XCTAssertNil(model.networkChoicesError)
    }

    func testRefreshNetworkChoicesDefaultsTrustedNetworkToCurrentWiFi() async {
        let store = InMemorySettingsStore(TetherLoopSettings(
            hotspotSSID: "Phone"
        ))
        let model = AppModel(
            settingsStore: store,
            networkAdapter: FakeNetworkAdapter(
                currentSSID: "Home",
                preferredSSIDs: ["Home", "Phone"]
            ),
            powerController: RecordingPowerAssertionController(),
            loginItemController: RecordingLoginItemController(),
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: RecordingNotificationDispatcher(),
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: true)
        )

        await model.refreshNetworkChoices()

        XCTAssertEqual(model.currentSSID, "Home")
        XCTAssertEqual(model.trustedSSIDs, ["Home"])
        XCTAssertEqual(store.load().trustedSSIDs, ["Home"])
    }

    func testAssociatedWithoutSSIDDoesNotTriggerFailover() async {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: "Phone",
            isSetupVerified: true,
            isProtectionEnabled: true
        ))
        let network = FakeNetworkAdapter(currentSSID: "Home")
        let model = AppModel(
            settingsStore: store,
            networkAdapter: network,
            powerController: RecordingPowerAssertionController(),
            loginItemController: RecordingLoginItemController(),
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: RecordingNotificationDispatcher(),
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: false)
        )

        await model.pollNetwork()
        network.current = nil
        network.associatedWithoutSSID = true
        await model.pollNetwork()

        XCTAssertTrue(network.joinAttempts.isEmpty)
        XCTAssertTrue(model.needsLocationPermission)
        XCTAssertEqual(model.status, .protected)
    }

    func testUnreadableSSIDThenRealDisconnectStillFailsOver() async {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: "Phone",
            isSetupVerified: true,
            isProtectionEnabled: true
        ))
        let network = FakeNetworkAdapter(currentSSID: "Home")
        let model = AppModel(
            settingsStore: store,
            networkAdapter: network,
            powerController: RecordingPowerAssertionController(),
            loginItemController: RecordingLoginItemController(),
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: RecordingNotificationDispatcher(),
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: false)
        )

        // Poll once on trusted SSID, then simulate unreadable state, then real disconnect.
        await model.pollNetwork()
        network.current = nil
        network.associatedWithoutSSID = true
        await model.pollNetwork()   // unreadable — no failover, previousSSID preserved
        network.associatedWithoutSSID = false
        await model.pollNetwork()   // real disconnect

        XCTAssertEqual(network.joinAttempts, ["Phone"])
    }

    func testReadableSSIDClearsLocationPermissionFlag() async {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: "Phone",
            isSetupVerified: true,
            isProtectionEnabled: true
        ))
        let network = FakeNetworkAdapter(currentSSID: nil)
        network.associatedWithoutSSID = true
        let model = AppModel(
            settingsStore: store,
            networkAdapter: network,
            powerController: RecordingPowerAssertionController(),
            loginItemController: RecordingLoginItemController(),
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: RecordingNotificationDispatcher(),
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: false)
        )

        await model.pollNetwork()
        XCTAssertTrue(model.needsLocationPermission)

        network.current = "Home"
        network.associatedWithoutSSID = false
        await model.pollNetwork()

        XCTAssertFalse(model.needsLocationPermission)
    }

    func testRequestLocationPermissionCallsController() {
        let store = InMemorySettingsStore()
        let recordingLocation = RecordingLocationAuthorization(isAuthorized: false)
        let model = AppModel(
            settingsStore: store,
            networkAdapter: FakeNetworkAdapter(),
            powerController: RecordingPowerAssertionController(),
            loginItemController: RecordingLoginItemController(),
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: RecordingNotificationDispatcher(),
            locationAuthorization: recordingLocation
        )

        model.requestLocationPermission()

        XCTAssertEqual(recordingLocation.requestCount, 1)
    }

    func testRefreshNetworkChoicesDoesNotDefaultHotspotAsTrustedNetwork() async {
        let store = InMemorySettingsStore(TetherLoopSettings(
            hotspotSSID: "Phone"
        ))
        let model = AppModel(
            settingsStore: store,
            networkAdapter: FakeNetworkAdapter(
                currentSSID: "Phone",
                preferredSSIDs: ["Phone", "Home"]
            ),
            powerController: RecordingPowerAssertionController(),
            loginItemController: RecordingLoginItemController(),
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: RecordingNotificationDispatcher(),
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: true)
        )

        await model.refreshNetworkChoices()

        XCTAssertEqual(model.currentSSID, "Phone")
        XCTAssertTrue(model.trustedSSIDs.isEmpty)
        XCTAssertTrue(store.load().trustedSSIDs.isEmpty)
    }

    func testPauseSurvivesUnrelatedSettingsChanges() {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: "Phone",
            isSetupVerified: true,
            isProtectionEnabled: true
        ))
        let model = AppModel(
            settingsStore: store,
            networkAdapter: FakeNetworkAdapter(),
            powerController: RecordingPowerAssertionController(),
            loginItemController: RecordingLoginItemController(),
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: RecordingNotificationDispatcher(),
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: true)
        )

        model.pauseProtection()
        XCTAssertEqual(model.status, .paused)

        model.setSleepPreventionEnabled(true)
        XCTAssertEqual(model.status, .paused)

        model.addTrustedSSID("Office")
        XCTAssertEqual(model.status, .paused)
    }

    func testPauseSurvivesNetworkChoicesRefresh() async {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: "Phone",
            isSetupVerified: true,
            isProtectionEnabled: true
        ))
        let network = FakeNetworkAdapter(currentSSID: "Home")
        let model = AppModel(
            settingsStore: store,
            networkAdapter: network,
            powerController: RecordingPowerAssertionController(),
            loginItemController: RecordingLoginItemController(),
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: RecordingNotificationDispatcher(),
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: true)
        )

        model.pauseProtection()
        XCTAssertEqual(model.status, .paused)

        await model.refreshNetworkChoices()

        XCTAssertEqual(model.status, .paused)
    }

    func testEnableProtectionToggleClearsPause() {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: "Phone",
            isSetupVerified: true,
            isProtectionEnabled: true
        ))
        let model = AppModel(
            settingsStore: store,
            networkAdapter: FakeNetworkAdapter(),
            powerController: RecordingPowerAssertionController(),
            loginItemController: RecordingLoginItemController(),
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: RecordingNotificationDispatcher(),
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: true)
        )

        model.pauseProtection()
        XCTAssertEqual(model.status, .paused)

        model.setProtectionEnabled(true)

        XCTAssertEqual(model.status, .protected)
    }

    func testEnablingProtectionStartsSleepAssertionWhenSleepPreventionIsOn() {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: "Phone",
            isSetupVerified: true,
            isProtectionEnabled: false,
            isSleepPreventionEnabled: true
        ))
        let power = RecordingPowerAssertionController()
        let model = AppModel(
            settingsStore: store,
            networkAdapter: FakeNetworkAdapter(),
            powerController: power,
            loginItemController: RecordingLoginItemController(),
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: RecordingNotificationDispatcher(),
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: true)
        )

        model.setProtectionEnabled(true)

        XCTAssertEqual(power.enableReasons.count, 1)
    }

    func testDisablingProtectionStopsSleepAssertion() {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: "Phone",
            isSetupVerified: true,
            isProtectionEnabled: true,
            isSleepPreventionEnabled: true
        ))
        let power = RecordingPowerAssertionController()
        let model = AppModel(
            settingsStore: store,
            networkAdapter: FakeNetworkAdapter(),
            powerController: power,
            loginItemController: RecordingLoginItemController(),
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: RecordingNotificationDispatcher(),
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: true)
        )

        model.protectNow()
        XCTAssertGreaterThanOrEqual(power.enableReasons.count, 1)

        model.setProtectionEnabled(false)

        XCTAssertGreaterThanOrEqual(power.disableCount, 1)
    }

    func testEnablingProtectionWithoutSleepPreventionDoesNotStartAssertion() {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: "Phone",
            isSetupVerified: true,
            isProtectionEnabled: false,
            isSleepPreventionEnabled: false
        ))
        let power = RecordingPowerAssertionController()
        let model = AppModel(
            settingsStore: store,
            networkAdapter: FakeNetworkAdapter(),
            powerController: power,
            loginItemController: RecordingLoginItemController(),
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: RecordingNotificationDispatcher(),
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: true)
        )

        model.setProtectionEnabled(true)

        XCTAssertTrue(power.enableReasons.isEmpty)
    }

    func testTogglingSleepPreventionWhilePausedDoesNotStartAssertion() {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: "Phone",
            isSetupVerified: true,
            isProtectionEnabled: true,
            isSleepPreventionEnabled: false
        ))
        let power = RecordingPowerAssertionController()
        let model = AppModel(
            settingsStore: store,
            networkAdapter: FakeNetworkAdapter(),
            powerController: power,
            loginItemController: RecordingLoginItemController(),
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: RecordingNotificationDispatcher(),
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: true)
        )

        model.pauseProtection()
        XCTAssertEqual(model.status, .paused)

        model.setSleepPreventionEnabled(true)

        XCTAssertTrue(power.enableReasons.isEmpty)
    }

    func testHotspotJoinIsNotSuccessUntilNetworkConfirms() async throws {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: "Phone",
            isSetupVerified: true,
            isProtectionEnabled: true
        ))
        let network = FakeNetworkAdapter(currentSSID: "Home")
        network.joinSetsCurrent = false
        let notifications = RecordingNotificationDispatcher()
        let model = AppModel(
            settingsStore: store,
            networkAdapter: network,
            powerController: RecordingPowerAssertionController(),
            loginItemController: RecordingLoginItemController(),
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: notifications,
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: true),
            joinConfirmationAttempts: 2,
            joinConfirmationDelay: .zero
        )

        await model.pollNetwork()
        network.current = nil
        await model.pollNetwork()
        try await Task.sleep(nanoseconds: 100_000_000)
        model.pauseProtection()

        XCTAssertEqual(model.status, .paused)
        XCTAssertFalse(notifications.notifications.contains { $0.title == "TetherLoop switched to hotspot" })
    }

    func testSetupVerificationFailsWhenJoinDoesNotConfirm() async {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: "Phone",
            isSetupVerified: false
        ))
        let network = FakeNetworkAdapter(currentSSID: "Home")
        network.joinSetsCurrent = false
        let model = AppModel(
            settingsStore: store,
            networkAdapter: network,
            powerController: RecordingPowerAssertionController(),
            loginItemController: RecordingLoginItemController(),
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: RecordingNotificationDispatcher(),
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: true),
            joinConfirmationAttempts: 2,
            joinConfirmationDelay: .zero
        )

        await model.runSetupVerificationTest()

        XCTAssertFalse(store.load().isSetupVerified)
    }

    func testConfirmedJoinStillSucceeds() async {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: "Phone",
            isSetupVerified: true,
            isProtectionEnabled: true
        ))
        let network = FakeNetworkAdapter(currentSSID: "Home")
        let model = AppModel(
            settingsStore: store,
            networkAdapter: network,
            powerController: RecordingPowerAssertionController(),
            loginItemController: RecordingLoginItemController(),
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: RecordingNotificationDispatcher(),
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: true),
            joinConfirmationAttempts: 2,
            joinConfirmationDelay: .zero
        )

        await model.pollNetwork()
        network.current = nil
        await model.pollNetwork()

        XCTAssertEqual(model.status, .onHotspot)
    }
}
