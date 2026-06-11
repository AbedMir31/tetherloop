import Foundation
import UserNotifications

public protocol NotificationDispatching {
    func notify(title: String, body: String)
}

public final class RecordingNotificationDispatcher: NotificationDispatching {
    public private(set) var notifications: [(title: String, body: String)] = []

    public init() {}

    public func notify(title: String, body: String) {
        notifications.append((title, body))
    }
}

public final class UserNotificationDispatcher: NotificationDispatching {
    public init() {}

    public func notify(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }
}
