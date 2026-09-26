import Coords
import CoreLocation
import Observation

@MainActor @Observable
final class DeviceLocation: NSObject, @preconcurrency CLLocationManagerDelegate {
    var point: MapCoordinate?
    var error: String?
    private let manager = CLLocationManager()
    private(set) var pending = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request() {
        point = nil
        error = nil
        pending = true
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        default:
            pending = false
            error = L10n.text("无法获取本机位置，请在系统设置的定位服务中允许 PhotoTrail 使用定位。")
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if pending, manager.authorizationStatus != .notDetermined { request() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard pending, let location = locations.last, location.horizontalAccuracy >= 0 else { return }
        pending = false
        point = MapCoordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard pending else { return }
        pending = false
        self.error = Self.explanation(for: error)
    }

    static func explanation(for error: Error) -> String {
        switch (error as? CLError)?.code {
        case .denied:
            return L10n.text("定位权限不可用。请在系统设置 → 隐私与安全性 → 定位服务中，开启定位服务并允许 PhotoTrail 使用定位。")
        case .network:
            return L10n.text("定位服务遇到网络错误。请检查网络连接后重试。Mac 还需要开启 Wi‑Fi 来辅助定位，即使正在通过网线联网。")
        default:
            return L10n.text("系统暂时无法确定本机位置。Mac 会利用附近的 Wi‑Fi 信息定位；即使通过网线联网，也请确认 Wi‑Fi 已开启，然后重试。")
        }
    }
}
