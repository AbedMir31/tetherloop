import XCTest
@testable import TetherLoopCore

final class NetworkSetupClientTests: XCTestCase {
    func testParsesWiFiDevice() {
        let output = """
        Hardware Port: Wi-Fi
        Device: en0
        Ethernet Address: aa:bb:cc
        """

        XCTAssertEqual(NetworkSetupClient.parseWiFiDevice(from: output), "en0")
    }

    func testParsesCurrentSSID() {
        XCTAssertEqual(
            NetworkSetupClient.parseCurrentSSID(from: "Current Wi-Fi Network: Home Wi-Fi\n"),
            "Home Wi-Fi"
        )
    }

    func testParsesDisconnectedCurrentSSID() {
        XCTAssertNil(NetworkSetupClient.parseCurrentSSID(from: "You are not associated with an AirPort network.\n"))
    }

    func testParsesPreferredNetworksWithoutHeader() {
        let output = """
        Preferred networks on en0:
            Home
            Office
        """

        XCTAssertEqual(NetworkSetupClient.parsePreferredSSIDs(from: output), ["Home", "Office"])
    }

    @MainActor
    func testJoinCommandDoesNotIncludePassword() async throws {
        let runner = RecordingCommandRunner(outputs: ["-setairportnetwork en0 Phone": ""])
        let client = NetworkSetupClient(runner: runner)

        try await client.join(ssid: "Phone", device: "en0")

        XCTAssertEqual(runner.invocations.last?.1, ["-setairportnetwork", "en0", "Phone"])
    }
}
