import XCTest
@testable import TetherLoopCore

final class SettingsStoreTests: XCTestCase {
    func testDefaultsArePrivacySafeAndDisabled() {
        let settings = TetherLoopSettings()

        XCTAssertTrue(settings.trustedSSIDs.isEmpty)
        XCTAssertNil(settings.hotspotSSID)
        XCTAssertFalse(settings.isSetupVerified)
        XCTAssertFalse(settings.isProtectionEnabled)
        XCTAssertFalse(settings.isSleepPreventionEnabled)
        XCTAssertFalse(settings.launchAtLogin)
    }

    func testHotspotChangeInvalidatesVerification() {
        let store = InMemorySettingsStore(TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: "Old Phone",
            isSetupVerified: true
        ))
        var settings = store.load()
        settings.hotspotSSID = "New Phone"
        settings.isSetupVerified = false
        try? store.save(settings)

        XCTAssertEqual(store.load().hotspotSSID, "New Phone")
        XCTAssertFalse(store.load().isSetupVerified)
    }

    func testSettingsRoundTripThroughUserDefaults() throws {
        let defaults = UserDefaults(suiteName: "TetherLoopSettingsStoreTests")!
        defaults.removePersistentDomain(forName: "TetherLoopSettingsStoreTests")
        let store = UserDefaultsSettingsStore(defaults: defaults, key: "settings")

        let expected = TetherLoopSettings(
            trustedSSIDs: ["Home", "Office"],
            hotspotSSID: "iPhone",
            isSetupVerified: true,
            isProtectionEnabled: true,
            isSleepPreventionEnabled: true,
            isGlobalFailoverEnabled: false,
            launchAtLogin: true
        )
        try store.save(expected)

        XCTAssertEqual(store.load(), expected)
    }
}
