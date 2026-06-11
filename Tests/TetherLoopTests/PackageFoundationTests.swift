import XCTest
@testable import TetherLoopCore

@MainActor
final class PackageFoundationTests: XCTestCase {
    func testPreviewModelStartsVerifiedAndProtected() {
        let model = AppModel.preview()
        XCTAssertTrue(model.settings.isSetupVerified)
        XCTAssertEqual(model.settings.hotspotSSID, "Abed's iPhone")
        XCTAssertTrue(model.settings.isProtectionEnabled)
    }
}
