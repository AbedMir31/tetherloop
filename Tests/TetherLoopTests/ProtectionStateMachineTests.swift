import XCTest
@testable import TetherLoopCore

final class ProtectionStateMachineTests: XCTestCase {
    func testUnverifiedSetupCannotProtect() {
        var machine = ProtectionStateMachine(settings: TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: "Phone",
            isSetupVerified: false,
            isProtectionEnabled: true
        ))

        let result = machine.handle(.userProtectNow)

        XCTAssertEqual(result.status, .unconfigured)
        XCTAssertTrue(result.intents.contains(.record(.setupRequired, "Protection requires verified setup")))
    }

    func testTrustedDisconnectSwitchesWhenProtectionIsVerified() {
        var machine = ProtectionStateMachine(settings: verifiedSettings())

        let result = machine.handle(.trustedWiFiDisconnected("Home"))

        XCTAssertEqual(result.status, .switching)
        XCTAssertTrue(result.intents.contains(.record(.trustedNetworkLost, "Trusted Wi-Fi disconnected: Home")))
    }

    func testPauseSuppressesTrustedDisconnect() {
        var machine = ProtectionStateMachine(settings: verifiedSettings())
        _ = machine.handle(.userPause)

        let result = machine.handle(.trustedWiFiDisconnected("Home"))

        XCTAssertEqual(result.status, .paused)
    }

    func testHotspotFailureSchedulesRetry() {
        var machine = ProtectionStateMachine(settings: verifiedSettings(), retryPolicy: RetryPolicy(delays: [0, 15]))

        let result = machine.handle(.hotspotJoinFailed("not found"))

        XCTAssertEqual(result.status, .failed)
        XCTAssertTrue(result.intents.contains(.record(.retryScheduled, "Retry scheduled in 0 seconds")))
        XCTAssertTrue(result.intents.contains(.scheduleRetry(0)))
    }

    func testHotspotSuccessMovesOnHotspot() {
        var machine = ProtectionStateMachine(settings: verifiedSettings())

        let result = machine.handle(.hotspotJoinSucceeded("Phone"))

        XCTAssertEqual(result.status, .onHotspot)
    }

    private func verifiedSettings() -> TetherLoopSettings {
        TetherLoopSettings(
            trustedSSIDs: ["Home"],
            hotspotSSID: "Phone",
            isSetupVerified: true,
            isProtectionEnabled: true,
            isSleepPreventionEnabled: true
        )
    }
}
