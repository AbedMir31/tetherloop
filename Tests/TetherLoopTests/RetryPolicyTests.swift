import XCTest
@testable import TetherLoopCore

final class RetryPolicyTests: XCTestCase {
    func testDefaultBackoffIsBounded() {
        let policy = RetryPolicy()

        XCTAssertEqual(policy.delay(forAttempt: 0), 0)
        XCTAssertEqual(policy.delay(forAttempt: 1), 15)
        XCTAssertEqual(policy.delay(forAttempt: 2), 30)
        XCTAssertEqual(policy.delay(forAttempt: 3), 60)
        XCTAssertEqual(policy.delay(forAttempt: 4), 120)
        XCTAssertNil(policy.delay(forAttempt: 99))
    }
}
