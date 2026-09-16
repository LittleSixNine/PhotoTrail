import Coords
import CoreLocation
import SwiftUI
import UDF

public struct MapWithSearchView: View {
    @Environment(Store<GeoTagState, GeoTagEvent>.self) var store

    enum MapFocus: Hashable {
        case map, search, searchList
    }

    // data shared between MapView, SearchBarView, and SearchView
    struct SearchInfo {
        var picked: Bool = false
        var searchText = ""
        var selection: Place?
        var searchResponse: [Place] = []
        var recenterLocation: Coords?
    }

    @Environment(LocationWorkspace.self) private var workspace
    @FocusState var mapFocus: MapFocus?
    @State var searchInfo = SearchInfo()
    @State private var locator = DeviceLocation()
    @Environment(\.openURL) private var openURL
    @AppStorage("PhotoTrailSatellite") private var satellite = false
    @AppStorage("PhotoTrailMapProvider") private var mapProvider = "amap"

    private var hasMap: Bool { mapProvider != "amap" || workspace.credentials != nil }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                if mapProvider == "amap" {
                    AMapView()
                } else {
                    MapView(mapFocus: $mapFocus, searchInfo: $searchInfo)
                }
                if hasMap {
                SearchView(mapFocus: $mapFocus, searchInfo: $searchInfo,
                           expandedWidth: min(360, max(180, geometry.size.width - 130)))
                    .padding(.leading, 16)
                    .padding(.bottom, 52)
                }
            }.frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
        }
        .overlay(alignment: .topLeading) {
            if hasMap {
            WorkspacePageSwitch(selection: $satellite, firstTitle: "标准", secondTitle: "卫星",
                                firstIcon: "map", secondIcon: "globe", optionWidth: 76, usesGlass: true)
                .padding(16)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if hasMap {
            MapNavigationControls(heading: mapProvider == "amap" ? workspace.amapHeading : workspace.appleHeading,
                                  locating: locator.pending, locate: { locator.request() }) { command in
                if mapProvider == "amap" { workspace.amapNavigation?(command) }
                else { workspace.appleNavigation?(command) }
            }.padding(16)
            }
        }
        .onChange(of: locator.point) {
            if let point = locator.point {
                workspace.preview(point)
            }
        }
        .alert("本机定位", isPresented: Binding(get: { locator.error != nil }, set: {
            if !$0 { locator.error = nil }
        })) {
            Button("苹果定位说明") {
                openURL(URL(string: "https://support.apple.com/zh-cn/guide/mac-help/mh35873/mac")!)
                locator.error = nil
            }
            Button("好", role: .cancel) { locator.error = nil }
        } message: { Text(locator.error ?? "") }
        .onChange(of: satellite) { workspace.setSatellite?(satellite) }
        .onChange(of: workspace.ready) {
            if workspace.ready { workspace.setSatellite?(satellite) }
        }
        .onChange(of: mapProvider) {
            if mapProvider == "amap", UserDefaults.standard.bool(forKey: SetupGuideView.completedKey) {
                Task { await workspace.loadCredentials() }
            }
            workspace.ready = false
            workspace.status = ""
            workspace.query = ""
            workspace.selectedResult = nil
            workspace.results = []
            mapFocus = nil
            searchInfo = SearchInfo()
            store.send(.textfieldFocusChanged(false), undoable: false)
            store.send(.findInMap(false), undoable: false)
        }
    }
}

#Preview(traits: .store) {
    MapWithSearchView()
}
