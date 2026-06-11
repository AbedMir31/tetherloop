import Foundation
import ServiceManagement

public protocol LoginItemControlling {
    func setEnabled(_ enabled: Bool) throws
}

public final class SystemLoginItemController: LoginItemControlling {
    public init() {}

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

public final class RecordingLoginItemController: LoginItemControlling {
    public private(set) var requestedValues: [Bool] = []
    public var error: Error?

    public init() {}

    public func setEnabled(_ enabled: Bool) throws {
        if let error {
            throw error
        }
        requestedValues.append(enabled)
    }
}
