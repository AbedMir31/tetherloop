import Foundation

public protocol PowerAssertionControlling {
    func enable(reason: String) throws
    func disable() throws
}

public final class RecordingPowerAssertionController: PowerAssertionControlling {
    public private(set) var enableReasons: [String] = []
    public private(set) var disableCount = 0

    public init() {}

    public func enable(reason: String) throws {
        enableReasons.append(reason)
    }

    public func disable() throws {
        disableCount += 1
    }
}
