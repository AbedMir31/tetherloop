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

    func testParseJoinFailureDetectsFailedToJoin() {
        XCTAssertEqual(
            NetworkSetupClient.parseJoinFailure(from: "Failed to join network MyPhone."),
            "Failed to join network MyPhone."
        )
    }

    func testParseJoinFailureDetectsCouldNotFind() {
        XCTAssertEqual(
            NetworkSetupClient.parseJoinFailure(from: "Could not find network MyPhone."),
            "Could not find network MyPhone."
        )
    }

    func testParseJoinFailureDetectsErrorCode() {
        XCTAssertEqual(
            NetworkSetupClient.parseJoinFailure(from: "Error: -3905 (Operation could not be completed)"),
            "Error: -3905 (Operation could not be completed)"
        )
    }

    func testParseJoinFailureAcceptsEmptyOutput() {
        XCTAssertNil(NetworkSetupClient.parseJoinFailure(from: ""))
        XCTAssertNil(NetworkSetupClient.parseJoinFailure(from: "\n"))
    }

    @MainActor
    func testJoinThrowsOnFailureOutputWithZeroExit() async {
        let runner = RecordingCommandRunner(outputs: ["-setairportnetwork en0 Phone": "Failed to join network Phone."])
        let client = NetworkSetupClient(runner: runner)

        do {
            try await client.join(ssid: "Phone", device: "en0")
            XCTFail("Expected join to throw on failure output")
        } catch let error as NetworkAdapterError {
            guard case .commandFailed = error else {
                XCTFail("Expected commandFailed, got \(error)")
                return
            }
        } catch {
            XCTFail("Expected NetworkAdapterError.commandFailed, got \(error)")
        }
    }
}
