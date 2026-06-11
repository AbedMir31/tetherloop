import Foundation

public struct DiagnosticEvent: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case setupRequired
        case setupVerified
        case settingsChanged
        case protectionEnabled
        case protectionPaused
        case trustedNetworkAvailable
        case trustedNetworkLost
        case hotspotJoinStarted
        case hotspotJoinSucceeded
        case hotspotJoinFailed
        case retryScheduled
        case networkError
        case manualAction
        case notification
        case sleepPrevention
    }

    public let id: UUID
    public let date: Date
    public let kind: Kind
    public let message: String

    public init(id: UUID = UUID(), date: Date = Date(), kind: Kind, message: String) {
        self.id = id
        self.date = date
        self.kind = kind
        self.message = Self.redact(message)
    }

    public static func redact(_ message: String) -> String {
        var redacted = message
        let patterns = ["password=", "passphrase=", "pwd="]
        for pattern in patterns {
            if let range = redacted.range(of: pattern, options: .caseInsensitive) {
                redacted = String(redacted[..<range.upperBound]) + "[redacted]"
            }
        }
        return redacted
    }
}
