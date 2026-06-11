import XCTest
@testable import TetherLoopCore

final class PowerAssertionTests: XCTestCase {
    func testRecordingPowerControllerTracksRequests() throws {
        let controller = RecordingPowerAssertionController()

        try controller.enable(reason: "protect")
        try controller.disable()

        XCTAssertEqual(controller.enableReasons, ["protect"])
        XCTAssertEqual(controller.disableCount, 1)
    }
}
