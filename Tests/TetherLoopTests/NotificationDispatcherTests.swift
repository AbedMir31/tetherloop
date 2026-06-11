import XCTest
@testable import TetherLoopCore

final class NotificationDispatcherTests: XCTestCase {
    func testRecordingDispatcherCapturesNotifications() {
        let dispatcher = RecordingNotificationDispatcher()

        dispatcher.notify(title: "Switched", body: "Phone")

        XCTAssertEqual(dispatcher.notifications.first?.title, "Switched")
        XCTAssertEqual(dispatcher.notifications.first?.body, "Phone")
    }
}
