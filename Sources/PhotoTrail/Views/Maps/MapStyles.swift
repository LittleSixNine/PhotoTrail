import MapKit
import SwiftUI

// map styles supported by this app

enum MapStyleName: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case imagery = "Imagery"
    case hybrid = "Hybrid"
    case standardTraffic = "Standard with traffic"
    case hybridTraffic = "Hybrid with traffic"

    var id: MapStyleName { self }

    func mapStyle() -> MapStyle {
        switch self {
        case .standard:
            return .standard(elevation: .realistic)
        case .imagery:
            return .imagery
        case .hybrid:
            return .hybrid
        case .standardTraffic:
            return .standard(showsTraffic: true)
        case .hybridTraffic:
            return .hybrid(showsTraffic: true)
        }
    }
}

// A picker view used to select a map style

struct MapStylePicker: View {
    @Binding var mapStyleName: MapStyleName

    var body: some View {
        Picker(selection: $mapStyleName) {
            ForEach(MapStyleName.allCases) { style in
                Text(LocalizedStringKey(style.rawValue)).tag(style)
            }
        } label: {
            Label("Map style…", systemImage: "map")
        }
        .pickerStyle(.menu)
    }
}

enum AMapStyleName: String, CaseIterable, Identifiable {
    case normal, dark, light, whitesmoke, fresh, grey, graffiti, macaron, blue, darkblue, wine

    static let preferenceKey = "PhotoTrailAMapStyle"
    static let lightPreferenceKey = "PhotoTrailAMapStyleLight"
    static let darkPreferenceKey = "PhotoTrailAMapStyleDark"

    static func migrateLegacyPreference(in defaults: UserDefaults) {
        guard defaults.object(forKey: lightPreferenceKey) == nil,
              let value = defaults.string(forKey: preferenceKey),
              let style = Self(rawValue: value) else { return }
        defaults.set(style.rawValue, forKey: lightPreferenceKey)
    }
    var id: Self { self }
    var title: String {
        switch self {
        case .normal: "标准"
        case .dark: "幻影黑"
        case .light: "月光银"
        case .whitesmoke: "远山黛"
        case .fresh: "草色青"
        case .grey: "雅士灰"
        case .graffiti: "涂鸦"
        case .macaron: "马卡龙"
        case .blue: "靛青蓝"
        case .darkblue: "极夜蓝"
        case .wine: "酱籽"
        }
    }
}

struct AMapStylePreferences: DynamicProperty {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AMapStyleName.lightPreferenceKey) private var light: AMapStyleName = .light
    @AppStorage(AMapStyleName.darkPreferenceKey) private var dark: AMapStyleName = .dark

    var selection: Binding<AMapStyleName> { colorScheme == .dark ? $dark : $light }
}

struct AMapStylePicker: View {
    private var styles = AMapStylePreferences()

    var body: some View {
        Picker("高德地图配色", selection: styles.selection) {
            ForEach(AMapStyleName.allCases) { style in
                Text(style.title).tag(style)
            }
        }
        .pickerStyle(.menu)
    }
}
