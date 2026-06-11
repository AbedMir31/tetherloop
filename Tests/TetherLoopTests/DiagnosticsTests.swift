import XCTest
@testable import TetherLoopCore

final class DiagnosticsTests: XCTestCase {
    func testRedactsPasswordLikeFields() {
        let event = DiagnosticEvent(kind: .networkError, message: "join failed password=secret")

        XCTAssertEqual(event.message, "join failed password=[redacted]")
    }

    func testLogStoreBoundsRetention() {
        let store = InMemoryDiagnosticLogStore(limit: 2)
        store.append(DiagnosticEvent(kind: .manualAction, message: "one"))
        store.append(DiagnosticEvent(kind: .manualAction, message: "two"))
        store.append(DiagnosticEvent(kind: .manualAction, message: "three"))

        XCTAssertEqual(store.loadEvents().map(\.message), ["two", "three"])
    }
}
