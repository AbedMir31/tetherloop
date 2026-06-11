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
            diagnosticsStore: InMemoryDiagnosticLogStore(),
            notificationDispatcher: RecordingNotificationDispatcher()
        )

        model.setHotspotSSID("New")

        XCTAssertEqual(model.settings.hotspotSSID, "New")
        XCTAssertFalse(model.settings.isSetupVerified)
    }
}
