import Foundation
import IOKit.pwr_mgt

public final class SystemPowerAssertionController: PowerAssertionControlling {
    private var assertionID: IOPMAssertionID = 0
    private var isEnabled = false

    public init() {}

    public func enable(reason: String) throws {
        guard !isEnabled else { return }
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoIdleSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        guard result == kIOReturnSuccess else {
            throw PowerAssertionError.creationFailed(result)
        }
        assertionID = id
        isEnabled = true
    }

    public func disable() throws {
        guard isEnabled else { return }
        let result = IOPMAssertionRelease(assertionID)
        guard result == kIOReturnSuccess else {
            throw PowerAssertionError.releaseFailed(result)
        }
        assertionID = 0
        isEnabled = false
    }
}

public enum PowerAssertionError: Error, LocalizedError, Equatable {
    case creationFailed(IOReturn)
    case releaseFailed(IOReturn)

    public var errorDescription: String? {
        switch self {
        case .creationFailed(let code): "Could not create power assertion: \(code)"
        case .releaseFailed(let code): "Could not release power assertion: \(code)"
        }
    }
}
