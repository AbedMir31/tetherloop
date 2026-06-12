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
        XCTAssertEqual(network.joinedSSIDs, ["Phone"])
        XCTAssertEqual(model.postVerificationReturn, .offered(originalSSID: "Home"))
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

    func testVerificationDoesNotAutoReturnToOriginalNetwork() async {
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

        await model.runSetupVerificationTest()

        XCTAssertEqual(network.current, "Phone")
        XCTAssertEqual(model.postVerificationReturn, .offered(originalSSID: "Home"))
    }

    func testAcceptingReturnOfferJoinsOriginalNetwork() async {
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

        await model.runSetupVerificationTest()
        await model.acceptPostVerificationReturn()

        XCTAssertEqual(network.joinedSSIDs.last, "Home")
        XCTAssertNil(model.postVerificationReturn)
    }

    func testFailedReturnOfferLogsErrorNotSuccess() async {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: "Phone",
            isSetupVerified: true,
            isProtectionEnabled: true
        ))
        let network = FakeNetworkAdapter(currentSSID: "Home")
        network.joinResults = [
            .success(()),
            .failure(NetworkAdapterError.commandFailed("boom"))
        ]
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
        let countBeforeAccept = model.diagnostics.count
        await model.acceptPostVerificationReturn()

        let afterOffer = model.diagnostics.dropFirst(countBeforeAccept)
        XCTAssertFalse(afterOffer.contains { $0.message.contains("Returned to Wi-Fi") })
        XCTAssertTrue(afterOffer.contains { $0.message.contains("Could not return") })
    }

    func testVerificationFromNoWiFiSetsStayedOnHotspot() async {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: "Phone",
            isSetupVerified: false
        ))
        let network = FakeNetworkAdapter(currentSSID: nil)
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

        XCTAssertEqual(model.postVerificationReturn, .stayedOnHotspot)
    }

    func testOnlyFirstRetryFailureNotifies() async throws {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: "Phone",
            isSetupVerified: true,
            isProtectionEnabled: true
        ))
        let network = FakeNetworkAdapter(currentSSID: "Home")
        network.joinError = NetworkAdapterError.commandFailed("down")
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

        let joinFailureNotifications = notifications.notifications.filter {
            $0.title == "TetherLoop could not join hotspot"
        }
        XCTAssertEqual(joinFailureNotifications.count, 1)
    }

    func testPauseCancelsPendingRetry() async throws {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: "Phone",
            isSetupVerified: true,
            isProtectionEnabled: true
        ))
        let network = FakeNetworkAdapter(currentSSID: "Home")
        network.joinError = NetworkAdapterError.commandFailed("always fails")
        let model = AppModel(
            settingsStore: store,
            networkAdapter: network,
            powerController: RecordingPowerAssertionController(),
            loginItemController: RecordingLoginItemController(),
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: RecordingNotificationDispatcher(),
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: true),
            retryPolicy: RetryPolicy(delays: [60])
        )

        await model.pollNetwork()
        network.current = nil
        await model.pollNetwork()   // first hotspot join fails, schedules retry 60s out

        XCTAssertEqual(network.joinAttempts, ["Phone"])

        model.pauseProtection()
        try await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(network.joinAttempts.count, 1)
        XCTAssertEqual(model.status, .paused)
    }

    func testSettingHotspotCancelsPendingRetry() async throws {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: "Phone",
            isSetupVerified: true,
            isProtectionEnabled: true
        ))
        let network = FakeNetworkAdapter(currentSSID: "Home")
        network.joinError = NetworkAdapterError.commandFailed("always fails")
        let model = AppModel(
            settingsStore: store,
            networkAdapter: network,
            powerController: RecordingPowerAssertionController(),
            loginItemController: RecordingLoginItemController(),
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: RecordingNotificationDispatcher(),
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: true),
            retryPolicy: RetryPolicy(delays: [60])
        )

        await model.pollNetwork()
        network.current = nil
        await model.pollNetwork()

        XCTAssertEqual(network.joinAttempts, ["Phone"])

        model.setHotspotSSID("Other")
        try await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(network.joinAttempts, ["Phone"])
    }

    func testStopMonitoringCancelsRetry() async throws {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: "Phone",
            isSetupVerified: true,
            isProtectionEnabled: true
        ))
        let network = FakeNetworkAdapter(currentSSID: "Home")
        network.joinError = NetworkAdapterError.commandFailed("always fails")
        let model = AppModel(
            settingsStore: store,
            networkAdapter: network,
            powerController: RecordingPowerAssertionController(),
            loginItemController: RecordingLoginItemController(),
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: RecordingNotificationDispatcher(),
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: true),
            retryPolicy: RetryPolicy(delays: [60])
        )

        await model.pollNetwork()
        network.current = nil
        await model.pollNetwork()

        XCTAssertEqual(network.joinAttempts, ["Phone"])

        model.stopMonitoring()
        try await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(network.joinAttempts.count, 1)
    }

    func testReturnToWiFiWithNoTrustedNetworksRecordsFailure() async {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: [],
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

        XCTAssertTrue(network.joinAttempts.isEmpty)
        XCTAssertTrue(model.diagnostics.contains { $0.message.contains("no trusted Wi-Fi") })
    }

    func testRefreshDefaultsTrustedSSIDOnlyWhenEmptyAndNotHotspot() async {
        // (a) empty trusted, current "Cafe", hotspot "Phone" -> trusted gains "Cafe".
        let storeA = InMemorySettingsStore(TetherLoopSettings(hotspotSSID: "Phone"))
        let modelA = AppModel(
            settingsStore: storeA,
            networkAdapter: FakeNetworkAdapter(currentSSID: "Cafe", preferredSSIDs: ["Cafe", "Phone"]),
            powerController: RecordingPowerAssertionController(),
            loginItemController: RecordingLoginItemController(),
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: RecordingNotificationDispatcher(),
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: true)
        )
        await modelA.refreshNetworkChoices()
        XCTAssertTrue(modelA.trustedSSIDs.contains("Cafe"))

        // (b) current equals hotspot "Phone" -> trusted stays empty.
        let storeB = InMemorySettingsStore(TetherLoopSettings(hotspotSSID: "Phone"))
        let modelB = AppModel(
            settingsStore: storeB,
            networkAdapter: FakeNetworkAdapter(currentSSID: "Phone", preferredSSIDs: ["Phone", "Home"]),
            powerController: RecordingPowerAssertionController(),
            loginItemController: RecordingLoginItemController(),
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: RecordingNotificationDispatcher(),
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: true)
        )
        await modelB.refreshNetworkChoices()
        XCTAssertTrue(modelB.trustedSSIDs.isEmpty)

        // (c) trusted already has "Home" -> current "Cafe" is NOT added.
        let storeC = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: "Phone"
        ))
        let modelC = AppModel(
            settingsStore: storeC,
            networkAdapter: FakeNetworkAdapter(currentSSID: "Cafe", preferredSSIDs: ["Cafe", "Phone"]),
            powerController: RecordingPowerAssertionController(),
            loginItemController: RecordingLoginItemController(),
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: RecordingNotificationDispatcher(),
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: true)
        )
        await modelC.refreshNetworkChoices()
        XCTAssertEqual(modelC.trustedSSIDs, ["Home"])
        XCTAssertFalse(modelC.trustedSSIDs.contains("Cafe"))
    }

    func testRetryExhaustionSendsFinalNotification() async throws {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: "Phone",
            isSetupVerified: true,
            isProtectionEnabled: true
        ))
        let network = FakeNetworkAdapter(currentSSID: "Home")
        network.joinError = NetworkAdapterError.commandFailed("down")
        let notifications = RecordingNotificationDispatcher()
        let model = AppModel(
            settingsStore: store,
            networkAdapter: network,
            powerController: RecordingPowerAssertionController(),
            loginItemController: RecordingLoginItemController(),
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: notifications,
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: true),
            retryPolicy: RetryPolicy(delays: [0]),
            joinConfirmationAttempts: 2,
            joinConfirmationDelay: .zero
        )

        await model.pollNetwork()
        network.current = nil
        await model.pollNetwork()
        try await Task.sleep(nanoseconds: 100_000_000)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(notifications.notifications.last?.title, "TetherLoop stopped retrying")
    }

    func testAutomaticJoinRequiresVerifiedSetup() async {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: "Phone",
            isSetupVerified: false,
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

        // Poll on "Home" to record previousSSID, then drop the network and poll again.
        await model.pollNetwork()
        network.current = nil
        await model.pollNetwork()

        // With unverified setup the state machine never enters .switching, so the
        // automatic failover path never reaches the hotspot join: no join is attempted.
        XCTAssertTrue(network.joinAttempts.isEmpty)
    }

    func testManualTryBypassesVerification() async throws {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: "Phone",
            isSetupVerified: false,
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
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: true),
            joinConfirmationAttempts: 2,
            joinConfirmationDelay: .zero
        )

        model.tryHotspotNow()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(network.joinAttempts, ["Phone"])
    }

    func testJoinWithoutHotspotRecordsConfigurationMessage() async throws {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: nil,
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
            locationAuthorization: RecordingLocationAuthorization(isAuthorized: true),
            joinConfirmationAttempts: 2,
            joinConfirmationDelay: .zero
        )

        model.tryHotspotNow()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(network.joinAttempts.isEmpty)
        XCTAssertTrue(model.diagnostics.contains { $0.message.contains("No hotspot target") })
    }

    func testPollNetworkPublishesCurrentSSID() async {
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
        XCTAssertEqual(model.currentSSID, "Home")
        XCTAssertTrue(model.isOnTrustedWiFi)
        XCTAssertFalse(model.isOnHotspot)

        // Second poll observes a disconnect. currentSSID is published from the
        // polled value (nil) inside pollNetwork, BEFORE the failover join runs;
        // the awaited join sets network.current = "Phone" but never republishes
        // currentSSID, so the published value remains nil. Deterministic.
        network.current = nil
        await model.pollNetwork()
        XCTAssertNil(model.currentSSID)
        XCTAssertFalse(model.isOnTrustedWiFi)
        XCTAssertFalse(model.isOnHotspot)
    }

    func testFailoverToHotspotUpdatesPlacementFlags() async {
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
        await model.pollNetwork()   // failover joins "Phone", sets network.current = "Phone"
        await model.pollNetwork()   // now observes "Phone" and publishes it

        XCTAssertEqual(model.currentSSID, "Phone")
        XCTAssertTrue(model.isOnHotspot)
        XCTAssertFalse(model.isOnTrustedWiFi)
    }

    func testUnreadableSSIDKeepsLastPublishedSSID() async {
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
        XCTAssertEqual(model.currentSSID, "Home")

        // Unreadable SSID: pollNetwork early-returns before publishing, so the
        // last known value must stand.
        network.current = nil
        network.associatedWithoutSSID = true
        await model.pollNetwork()

        XCTAssertEqual(model.currentSSID, "Home")
    }

    func testProtectionActiveTracksManualProtectAndPause() {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: "Phone",
            isSetupVerified: true,
            isProtectionEnabled: false
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

        XCTAssertEqual(model.status, .monitoring)
        XCTAssertFalse(model.isProtectionActive)

        model.protectNow()
        XCTAssertEqual(model.status, .protected)
        XCTAssertTrue(model.isProtectionActive)

        model.pauseProtection()
        XCTAssertEqual(model.status, .paused)
        XCTAssertFalse(model.isProtectionActive)
    }

    func testProtectionActiveTrueWhileOnHotspot() async {
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
        XCTAssertTrue(model.isProtectionActive)
    }
}
