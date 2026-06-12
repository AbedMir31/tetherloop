import CoreWLAN
import Foundation

public final class CoreWLANClient {
    public init() {}

    public func currentNetwork() -> WiFiNetworkState {
        guard let interface = CWWiFiClient.shared().interface() else {
            return .disconnected
        }
        if let ssid = interface.ssid(), !ssid.isEmpty {
            return .associated(ssid: ssid)
        }
        if interface.wlanChannel() != nil {
            return .associated(ssid: nil)
        }
        return .disconnected
    }
}
