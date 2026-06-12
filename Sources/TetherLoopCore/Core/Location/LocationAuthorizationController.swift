import CoreLocation
import Foundation

public protocol LocationAuthorizing {
    var isAuthorized: Bool { get }
    func requestAuthorization()
}

public final class SystemLocationAuthorization: NSObject, LocationAuthorizing {
    private let manager = CLLocationManager()

    public override init() { super.init() }

    public var isAuthorized: Bool {
        switch manager.authorizationStatus {
        case .authorized, .authorizedAlways: true
        default: false
        }
    }

    public func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }
}

public final class RecordingLocationAuthorization: LocationAuthorizing {
    public var isAuthorized: Bool
    public private(set) var requestCount = 0

    public init(isAuthorized: Bool = false) {
        self.isAuthorized = isAuthorized
    }

    public func requestAuthorization() {
        requestCount += 1
    }
}
