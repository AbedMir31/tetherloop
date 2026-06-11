import Foundation

public struct RetryPolicy: Equatable, Sendable {
    public let delays: [TimeInterval]

    public init(delays: [TimeInterval] = [0, 15, 30, 60, 120, 120, 120, 120, 120]) {
        self.delays = delays
    }

    public func delay(forAttempt attempt: Int) -> TimeInterval? {
        guard attempt >= 0, attempt < delays.count else { return nil }
        return delays[attempt]
    }
}
