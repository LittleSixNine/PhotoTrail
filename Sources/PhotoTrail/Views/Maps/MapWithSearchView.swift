import Coords
import CoreLocation
import SwiftUI
import UDF

public struct MapWithSearchView: View {
    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) var store

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
    @State private var searchExpanded = false
    @State private var locator = DeviceLocation()
    @State private var startupLocator = DeviceLocation()
    @State private var startupCoordinate: MapCoordinate?
    @State private var startupRequestID: UUID?
    @Environment(\.openURL) private var openURL
    @AppStorage("PhotoTrailSatellite") private var satellite = false
    @AppStorage("PhotoTrailMapProvider") private var mapProvider = "amap"
    @AppStorage(SettingsPreferences.mapStartupViewKey) private var mapStartupView = SettingsPreferences.MapStartupView.device.rawValue

    private var hasMap: Bool { mapProvider != "amap" || workspace.credentials != nil }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                if mapProvider == "amap" {
                    AMapView(startupCoordinate: startupCoordinate,
                             onMapTap: { searchExpanded = false })
                        .id(mapStartupView)
                } else {
                    MapView(startupCoordinate: startupCoordinate,
                            mapFocus: $mapFocus, searchInfo: $searchInfo,
                            onMapTap: { searchExpanded = false })
                        .id(mapStartupView)
                }
                if hasMap {
                SearchView(mapFocus: $mapFocus, searchInfo: $searchInfo,
                           expanded: $searchExpanded,
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
                                  locating: locator.pending, locate: {
                startupRequestID = nil
                startupCoordinate = nil
                locator.request()
            }) { command in
                startupRequestID = nil
                startupCoordinate = nil
                if mapProvider == "amap" { workspace.amapNavigation?(command) }
                else { workspace.appleNavigation?(command) }
            }.padding(16)
            }
        }
        .onChange(of: locator.point) {
            if let point = locator.point, point.isValid {
                workspace.deviceCoordinate = point
                workspace.deviceFocusID = UUID()
            }
        }
        .onChange(of: startupLocator.point) {
            if startupRequestID != nil, let point = startupLocator.point, point.isValid {
                startupRequestID = nil
                workspace.deviceCoordinate = point
                startupCoordinate = point
            }
        }
        .onChange(of: startupLocator.error) {
            if startupLocator.error != nil { startupRequestID = nil }
        }
        .onChange(of: workspace.query) {
            if !workspace.query.isEmpty {
                startupRequestID = nil
                startupCoordinate = nil
            }
        }
        .onChange(of: workspace.previewID) {
            startupRequestID = nil
            startupCoordinate = nil
        }
        .onChange(of: mapStartupView) {
            startupRequestID = nil
            startupCoordinate = nil
        }
        .task(id: "\(mapProvider):\(mapStartupView):\(hasMap)") {
            startupRequestID = nil
            startupCoordinate = nil
            guard hasMap, mapStartupView == SettingsPreferences.MapStartupView.device.rawValue,
                  workspace.query.isEmpty, workspace.previewCoordinate == nil,
                  ProcessInfo.processInfo.environment["PHOTOTRAIL_OFFLINE_TESTS"] != "1" else { return }
            let requestID = UUID()
            startupRequestID = requestID
            startupLocator = DeviceLocation()
            startupLocator.request()
            try? await Task.sleep(for: .seconds(8))
            if startupRequestID == requestID {
                startupRequestID = nil
                startupCoordinate = nil
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
            startupRequestID = nil
            startupCoordinate = nil
            if mapProvider == "amap", UserDefaults.standard.bool(forKey: SetupGuideView.completedKey) {
                Task { await workspace.loadCredentials() }
            }
            workspace.ready = false
            workspace.status = ""
            workspace.query = ""
            workspace.previewCoordinate = nil
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
