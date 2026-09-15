import CoreLocation
import Testing
@testable import GeoTag

@MainActor
struct DeviceLocationTests {
    @Test func explainsPermissionAndNetworkSeparately() {
        let denied = DeviceLocation.explanation(for: CLError(.denied))
        let network = DeviceLocation.explanation(for: CLError(.network))
        let unavailable = DeviceLocation.explanation(for: CLError(.locationUnknown))
        #expect(denied.contains("定位权限"))
        #expect(network.contains("网络错误"))
        #expect(unavailable.contains("暂时无法确定"))
        #expect(unavailable.contains("请确认 Wi‑Fi 已开启"))
    }
}
