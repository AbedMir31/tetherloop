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
            notificationDispatcher: RecordingNotificationDispatcher()
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
            notificationDispatcher: RecordingNotificationDispatcher()
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
            notificationDispatcher: RecordingNotificationDispatcher()
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
            notificationDispatcher: RecordingNotificationDispatcher()
        )

        await model.runSetupVerificationTest()

        XCTAssertFalse(model.settings.isSetupVerified)
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
            notificationDispatcher: RecordingNotificationDispatcher()
        )

        model.setLaunchAtLogin(true)

        XCTAssertEqual(login.requestedValues, [true])
        XCTAssertTrue(store.load().launchAtLogin)
    }
}
