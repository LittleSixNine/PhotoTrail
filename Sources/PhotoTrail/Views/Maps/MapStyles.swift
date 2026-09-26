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
                Text(L10n.text(style.rawValue)).tag(style)
            }
        } label: {
            Label(L10n.text("Map style…"), systemImage: "map")
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
        case .normal: L10n.text("标准")
        case .dark: L10n.text("幻影黑")
        case .light: L10n.text("月光银")
        case .whitesmoke: L10n.text("远山黛")
        case .fresh: L10n.text("草色青")
        case .grey: L10n.text("雅士灰")
        case .graffiti: L10n.text("涂鸦")
        case .macaron: L10n.text("马卡龙")
        case .blue: L10n.text("靛青蓝")
        case .darkblue: L10n.text("极夜蓝")
        case .wine: L10n.text("酱籽")
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
        Picker(L10n.text("高德地图配色"), selection: styles.selection) {
            ForEach(AMapStyleName.allCases) { style in
                Text(style.title).tag(style)
            }
        }
        .pickerStyle(.menu)
    }
}
