import Coords
import GpxTrackLog
import MapKit
import SwiftUI
import UDF

struct MapView: View {
    @Environment(Store<GeoTagState, GeoTagEvent>.self) var store

    @AppStorage(Self.initialMapLatitudeKey) var initialMapLatitude = 37.7244
    @AppStorage(Self.initialMapLongitudeKey) var initialMapLongitude = -122.4381
    @AppStorage(Self.initialMapDistanceKey) var initialMapDistance = 50_000.0
    @AppStorage(Self.savedMapStyleKey) var savedMapStyle = MapStyleName.standard.rawValue
    @AppStorage(Self.showOtherPinsKey) var showOtherPins = false
    @AppStorage(SettingsView.trackWidthKey) var trackWidth = 0.0
    @AppStorage(SettingsView.trackColorKey) var trackColor = Color.black

    var mapFocus: FocusState<MapWithSearchView.MapFocus?>.Binding
    @Binding var searchInfo: MapWithSearchView.SearchInfo

    @Environment(LocationWorkspace.self) private var workspace
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var cameraDistance: Double = 0
    @State private var mapRect: MKMapRect?
    @State private var camera: MapCamera?
    @State private var mapStyleName: MapStyleName = .standard
    @AppStorage("GeoTagCNSatellite") private var satellite = false
    @State private var mainPin: Coords?
    @State private var otherPins: [OtherPin] = []
    @State private var tracks: [MapTrack] = []

    var body: some View {
        MapReader { mapProxy in
            Map(position: $cameraPosition) {
                if let point = workspace.previewCoordinate {
                    Annotation("位置预览", coordinate: Coords(latitude: point.latitude, longitude: point.longitude),
                               anchor: .bottom) { PhotoMapPin(preview: true) }
                        .annotationTitles(.hidden)
                }
                if let mainPin {
                    Annotation("main pin",
                               coordinate: mainPin,
                               anchor: .bottom) {
                        PhotoMapPin()
                    }
                    .annotationTitles(.hidden)
                }
                if showOtherPins {
                    ForEach(otherPins) { pin in
                        Annotation("other pin",
                                   coordinate: pin.location,
                                   anchor: .bottom ) {
                            PhotoMapPin(preview: true)
                        }
                        .annotationTitles(.hidden)
                    }
                }
                ForEach(tracks) { track in
                    MapPolyline(coordinates: track.coords)
                        .stroke(trackColor, lineWidth: trackWidth)
                }
            }
            .mapStyle(satellite ? .imagery : mapStyleName.mapStyle())
            .mapControls {
                MapScaleView()
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                workspace.appleHeading = context.camera.heading
                camera = context.camera
                if let distance = camera?.distance {
                    cameraDistance = distance
                }
                mapRect = context.rect
            }
            .contextMenu {
                MapContextMenu(camera: camera,
                               mapStyleName: $mapStyleName)
            }
            .simultaneousGesture(SpatialTapGesture().onEnded { position in
                mapFocus.wrappedValue = nil  // get rid of any search views
                if let id = store.mostSelected {
                    if let loc = mapProxy.convert(position.location, from: .local) {
                        store.send(.locationChanged(loc),
                                   description: "map click") {
                            // remember the current selection
                            let selected = store.selection
                            Task {
                                let address =
                                await ReverseLocationFinder.reverseGeocode(store: store,
                                                                           id: id)
                                if let address {
                                    store.send(.addressChanged(selected, address),
                                               undoable: false)
                                }
                            }
                        }
                    }
                }
            })
            .onChange(of: workspace.previewID) {
                if let point = workspace.previewCoordinate {
                    setCameraPosition(to: Coords(latitude: point.latitude, longitude: point.longitude))
                }
            }
            .onChange(of: satellite) {
                if !satellite { mapStyleName = .standard }
            }
            .onChange(of: mapStyleName) {
                savedMapStyle = mapStyleName.rawValue
            }
            .onChange(of: searchInfo.recenterLocation) {
                if let location = searchInfo.recenterLocation {
                    setCameraPosition(to: location)
                    searchInfo.recenterLocation = nil
                }
            }
            .onChange(of: mainPin) { recenter(on: mainPin) }
            .onAppear {
                workspace.appleNavigation = { command in
                    guard let current = camera else { return }
                    let distance: Double
                    switch command {
                    case "zoomIn": distance = max(100, current.distance / 2)
                    case "zoomOut": distance = min(40_000_000, current.distance * 2)
                    default: distance = current.distance
                    }
                    cameraPosition = .camera(.init(centerCoordinate: current.centerCoordinate,
                        distance: distance, heading: command == "north" ? 0 : current.heading, pitch: current.pitch))
                }
                let center = CLLocationCoordinate2D(
                    latitude: initialMapLatitude,
                    longitude: initialMapLongitude)
                cameraDistance = initialMapDistance
                setCameraPosition(to: center)
                mapStyleName = .init(rawValue: savedMapStyle) ?? .standard
            }
            .onDisappear { workspace.appleNavigation = nil }
            .task(id: store.version) {
                mainPin = store.currentLocation
                otherPins = store.selection.compactMap {
                    OtherPin(store[$0].metadata.location)
                }
                .filter { $0.location != mainPin }
            }
            .task(id: store.gpxTracks) {
                if store.gpxTracks.isEmpty {
                    tracks = []
                } else {
                    tracks = mapTracks()
                    cameraPosition = .automatic
                }
            }
        }
    }
}

// Map positioning helper functions

extension MapView {

    // Set the camera position
    func setCameraPosition(to coords: Coords) {
        cameraPosition = .camera(.init(centerCoordinate: coords,
                                       distance: cameraDistance))
    }

    // recenter map if the given coords are not in view
    func recenter(on coords: Coords?) {
        if let coords, let rect = mapRect {
            if !rect.contains(MKMapPoint(coords)) {
                setCameraPosition(to: coords)
            }
        }
    }
}

// Map pin support for "other" pins

extension MapView {

    // An identifiable container to hold locations of other pins
    struct OtherPin: Identifiable {
        let id = UUID()
        let location: Coords

        init?(_ location: Coords?) {
            guard let location else { return nil }
            self.location = location
        }
    }
}

// Map track support

extension MapView {

    // An identifial container to hold map tracks
    struct MapTrack: Identifiable {
        let id = UUID()
        let coords: [Coords]

        init(_ coords: [Coords]) {
            self.coords = coords
        }
    }

    // Convert the array of gpxTrackLogs into an array of MapTracks
    // where each non empty segment of a gpxTrackLog track is a MapTrack.

    func mapTracks() -> [MapTrack] {
        var mapTracks: [MapTrack] = []

        for trackLog in store.gpxTracks {
            for track in trackLog.tracks {
                for segment in track.segments {
                    let coords = segment.points.map {
                        Coords(latitude: $0.lat, longitude: $0.lon)
                    }
                    if !coords.isEmpty {
                        mapTracks.append(MapTrack(coords))
                    }
                }
            }
        }

        return mapTracks
    }
}

// Map View related default keys

extension MapView {
    static let initialMapLatitudeKey = "InitialMapLatitude"
    static let initialMapLongitudeKey = "InitialMapLongitude"
    static let initialMapDistanceKey = "InitialMapDistance"
    static let savedMapStyleKey = "SavedMapStyle"
    static let showOtherPinsKey = "ShowOtherPins"
}

// reset map related defaults for testing

extension MapView {
    static func resetMapDefaults() {
        @AppStorage(Self.initialMapLatitudeKey) var initialMapLatitude = 37.7244
        @AppStorage(Self.initialMapLongitudeKey) var initialMapLongitude = -122.4381
        @AppStorage(Self.initialMapDistanceKey) var initialMapDistance = 50_000.0
        @AppStorage(Self.savedMapStyleKey) var savedMapStyle = MapStyleName.standard.rawValue
        @AppStorage(Self.showOtherPinsKey) var showOtherPins = false

        initialMapLatitude = 37.7244
        initialMapLongitude = -122.4381
        initialMapDistance = 50_000.0
        savedMapStyle = MapStyleName.standard.rawValue
        showOtherPins = false
    }
}

#Preview {
    Text("Use MapWithSearchView to preview this sub-view")
        .padding()
}
