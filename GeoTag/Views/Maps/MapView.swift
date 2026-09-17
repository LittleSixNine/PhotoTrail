import Coords
import GpxTrackLog
import ImageData
import MapKit
import SwiftUI
import UDF

struct MapView: View {
    @Environment(Store<GeoTagState, GeoTagEvent>.self) var store

    let startupCoordinate: MapCoordinate?
    @AppStorage(Self.initialMapLatitudeKey) var initialMapLatitude = 37.7244
    @AppStorage(Self.initialMapLongitudeKey) var initialMapLongitude = -122.4381
    @AppStorage(Self.initialMapDistanceKey) var initialMapDistance = 50_000.0
    @AppStorage(Self.lastMapLatitudeKey) private var lastMapLatitude = Double.nan
    @AppStorage(Self.lastMapLongitudeKey) private var lastMapLongitude = Double.nan
    @AppStorage(Self.lastMapDistanceKey) private var lastMapDistance = Double.nan
    @AppStorage(Self.savedMapStyleKey) var savedMapStyle = MapStyleName.standard.rawValue
    @AppStorage(SettingsView.trackWidthKey) var trackWidth = 0.0
    @AppStorage(SettingsView.trackColorKey) var trackColor = Color.red
    @AppStorage(SettingsPreferences.showAllPhotoLocationsKey) private var showAllPhotoLocations = true
    @AppStorage(SettingsPreferences.mapStartupViewKey) private var mapStartupView = SettingsPreferences.MapStartupView.device.rawValue
    @AppStorage(SettingsPreferences.doubleClickKey) private var allowDoubleClick = true
    @AppStorage(SettingsPreferences.dragPinKey) private var allowDragPin = true

    var mapFocus: FocusState<MapWithSearchView.MapFocus?>.Binding
    @Binding var searchInfo: MapWithSearchView.SearchInfo
    let onMapTap: () -> Void

    @Environment(LocationWorkspace.self) private var workspace
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var cameraDistance: Double = 0
    @State private var mapRect: MKMapRect?
    @State private var camera: MapCamera?
    @State private var mapStyleName: MapStyleName = .standard
    @AppStorage("PhotoTrailSatellite") private var satellite = false
    @State private var allPhotoPins: [PhotoPin] = []
    @State private var photoPins: [PhotoPinGroup] = []
    @State private var edgePhotos: [EdgePhoto] = []
    @State private var mapSize = CGSize.zero
    @State private var tracks: [MapTrack] = []
    @State private var fittedTrackRevision = -1
    @State private var startupCancelled = false
    @State private var activeMarker: LocationMarkerPin.Kind?
    @State private var compactDeviceMarker = false
    @GestureState private var photoDrag: PhotoDrag?

    private struct PhotoDrag: Equatable {
        let id: ImageData.ID
        let translation: CGSize
    }

    var body: some View {
        MapReader { mapProxy in
            Map(position: $cameraPosition) {
                if let point = workspace.deviceCoordinate {
                    Annotation("当前位置", coordinate: Coords(latitude: point.latitude, longitude: point.longitude),
                               anchor: .bottom) {
                        locationMarker(.device, point: point, name: "当前位置")
                    }
                    .annotationTitles(.hidden)
                }
                if let point = workspace.previewCoordinate {
                    Annotation(workspace.previewName, coordinate: Coords(latitude: point.latitude, longitude: point.longitude),
                               anchor: .bottom) {
                        locationMarker(.search, point: point, name: workspace.previewName)
                    }
                    .annotationTitles(.hidden)
                }
                ForEach(photoPins) { group in
                    let pin = displayPin(for: group)
                    Annotation(pin.image.name, coordinate: group.location, anchor: .bottom) {
                        PhotoThumbnailMapPin(image: pin.image, selected: pin.selected,
                                             clusterCount: group.pins.count)
                            .offset(photoDrag?.id == pin.id ? photoDrag?.translation ?? .zero : .zero)
                            .onTapGesture {
                                onMapTap()
                                selectPin(group)
                            }
                            .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .named("photoMap"))
                                .updating($photoDrag) { value, state, _ in
                                    guard allowDragPin, pin.selected, pin.editable else { return }
                                    state = PhotoDrag(id: pin.id, translation: value.translation)
                                }
                                .onEnded { value in
                                    guard allowDragPin, pin.selected, pin.editable,
                                          let anchor = mapProxy.convert(group.location,
                                                                        to: .named("photoMap")),
                                          let location = mapProxy.convert(
                                            CGPoint(x: anchor.x + value.translation.width,
                                                    y: anchor.y + value.translation.height),
                                                                          from: .named("photoMap")) else { return }
                                    store.send(.locationForImageChanged(pin.id, location),
                                               description: "拖动照片位置")
                                }, including: allowDragPin && pin.selected && pin.editable ? .all : .none)
                    }
                }
                ForEach(tracks) { track in
                    MapPolyline(coordinates: track.coords)
                        .stroke(trackColor.opacity(workspace.tracks.selected == nil || workspace.tracks.selected == track.fileID ? 1 : 0.4),
                                style: StrokeStyle(lineWidth: trackWidth > 0 ? trackWidth : 3,
                                                              lineCap: .round, lineJoin: .round, dash: [10, 5]))
                }
            }
            .mapStyle(satellite ? .imagery : mapStyleName.mapStyle())
            .coordinateSpace(name: "photoMap")
            .mapControls {
                MapScaleView()
            }
            .background {
                MapScrollWheelMonitor { steps, point in
                    zoomByWheel(steps, at: point, proxy: mapProxy)
                }
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                workspace.appleHeading = context.camera.heading
                camera = context.camera
                if let distance = camera?.distance {
                    cameraDistance = distance
                }
                let center = context.camera.centerCoordinate
                if MapCoordinate(latitude: center.latitude, longitude: center.longitude).isValid,
                   context.camera.distance.isFinite, context.camera.distance > 0 {
                    lastMapLatitude = center.latitude
                    lastMapLongitude = center.longitude
                    lastMapDistance = context.camera.distance
                }
                mapRect = context.rect
                compactDeviceMarker = context.rect.width
                    * MKMetersPerMapPointAtLatitude(context.camera.centerCoordinate.latitude) > 5_000
                photoPins = Self.groupedPhotoPins(allPhotoPins, in: context.rect)
                updateEdgePhotos(mapProxy, size: mapSize)
            }
            .contextMenu {
                MapContextMenu(camera: camera,
                               mapStyleName: $mapStyleName)
            }
            .simultaneousGesture(TapGesture().onEnded { onMapTap() })
            .gesture(SpatialTapGesture(count: 2).onEnded { position in
                startupCancelled = true
                mapFocus.wrappedValue = nil  // get rid of any search views
                if allowDoubleClick, !store.saveInProgress, let id = store.mostSelected {
                    if let loc = mapProxy.convert(position.location, from: .local) {
                        store.send(.confirmedWGS84Location(loc),
                                   description: "双击地图设置所选照片位置") {
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
                    startupCancelled = true
                    setCameraPosition(to: Coords(latitude: point.latitude, longitude: point.longitude))
                }
            }
            .onChange(of: workspace.deviceFocusID) {
                if let point = workspace.deviceCoordinate {
                    startupCancelled = true
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
                    startupCancelled = true
                    setCameraPosition(to: location)
                    searchInfo.recenterLocation = nil
                }
            }
            .onChange(of: startupCoordinate) {
                if !startupCancelled, !cameraPosition.positionedByUser,
                   mapStartupView == SettingsPreferences.MapStartupView.device.rawValue,
                   let startupCoordinate, startupCoordinate.isValid {
                    setCameraPosition(to: Coords(latitude: startupCoordinate.latitude,
                                                 longitude: startupCoordinate.longitude))
                }
            }
            .onAppear {
                workspace.focusPhoto = { id in
                    let metadata = store[id].metadata
                    if metadata.canDisplayAsWGS84, let location = metadata.location {
                        startupCancelled = true
                        setCameraPosition(to: location)
                    }
                }
                workspace.appleNavigation = { command in
                    guard let current = camera else { return }
                    startupCancelled = true
                    let distance: Double
                    switch command {
                    case "zoomIn": distance = max(100, current.distance / 2)
                    case "zoomOut": distance = min(40_000_000, current.distance * 2)
                    default: distance = current.distance
                    }
                    cameraPosition = .camera(.init(centerCoordinate: current.centerCoordinate,
                        distance: distance, heading: command == "north" ? 0 : current.heading, pitch: current.pitch))
                }
                let last = MapCoordinate(latitude: lastMapLatitude, longitude: lastMapLongitude)
                let hasLast = last.isValid && lastMapDistance.isFinite && lastMapDistance > 0
                let center = startupCoordinate.flatMap { point -> Coords? in
                    guard mapStartupView == SettingsPreferences.MapStartupView.device.rawValue,
                          point.isValid else { return nil }
                    return Coords(latitude: point.latitude, longitude: point.longitude)
                } ?? (hasLast ? Coords(latitude: last.latitude, longitude: last.longitude)
                              : Coords(latitude: initialMapLatitude, longitude: initialMapLongitude))
                cameraDistance = hasLast ? lastMapDistance : initialMapDistance
                startupCancelled = false
                setCameraPosition(to: center)
                mapStyleName = .init(rawValue: savedMapStyle) ?? .standard
            }
            .onDisappear {
                workspace.appleNavigation = nil
                workspace.focusPhoto = nil
            }
            .task(id: "\(store.mapRevision):\(showAllPhotoLocations)") {
                let pins = SettingsPreferences.displayedPhotos(store.visibleImages, selection: store.selection,
                                                           showAll: showAllPhotoLocations).compactMap { image -> PhotoPin? in
                    guard image.metadata.canDisplayAsWGS84,
                          let location = image.metadata.location else { return nil }
                    return PhotoPin(image: image, location: location,
                                    selected: store.selection.contains(image.id),
                                    editable: image.updatable && !store.saveInProgress)
                }
                allPhotoPins = pins
                photoPins = Self.groupedPhotoPins(pins, in: mapRect)
                updateEdgePhotos(mapProxy, size: mapSize)
            }
            .task(id: workspace.tracks.revision) {
                tracks = mapTracks()
                if fittedTrackRevision != workspace.tracks.fitRevision,
                   let selected = workspace.tracks.selected {
                    let points = tracks.filter { $0.fileID == selected }.flatMap(\.coords)
                    if !points.isEmpty {
                        startupCancelled = true
                        var rect = MKMapRect.null
                        for point in points {
                            let position = MKMapPoint(point)
                            rect = rect.union(MKMapRect(x: position.x, y: position.y, width: 1, height: 1))
                        }
                        cameraPosition = .rect(rect.insetBy(dx: -max(rect.width * 0.15, 100),
                                                           dy: -max(rect.height * 0.15, 100)))
                        fittedTrackRevision = workspace.tracks.fitRevision
                    }
                }
            }
            .overlay {
                GeometryReader { geometry in
                    ZStack {
                        Color.clear.allowsHitTesting(false)
                        ForEach(edgePhotos) { marker in
                            Button {
                                startupCancelled = true
                                setCameraPosition(to: marker.location)
                            } label: {
                                PhotoEdgeIndicator(image: marker.image,
                                                   direction: Self.edgeDirection(for: marker.point,
                                                                                 in: mapSize))
                            }
                            .buttonStyle(.plain)
                            .position(marker.point)
                            .help("在地图中显示 \(marker.image.name)")
                        }
                    }
                    .task(id: geometry.size) {
                        mapSize = geometry.size
                        updateEdgePhotos(mapProxy, size: geometry.size)
                    }
                }
            }
        }
    }
}

// Map positioning helper functions

extension MapView {

    func locationMarker(_ kind: LocationMarkerPin.Kind, point: MapCoordinate,
                        name: String) -> some View {
        Button { onMapTap(); activeMarker = kind } label: {
            LocationMarkerPin(kind: kind, compact: kind == .device && compactDeviceMarker)
        }
        .buttonStyle(.plain)
        .popover(isPresented: Binding(get: { activeMarker == kind },
                                      set: { if !$0 { activeMarker = nil } }), arrowEdge: .top) {
            LocationMarkerCallout(name: name, coordinate: point,
                canApply: !store.saveInProgress && !store.selection.isEmpty
                    && store.selection.allSatisfy { store[$0].updatable },
                apply: {
                    activeMarker = nil
                    store.send(.confirmedWGS84Location(Coords(latitude: point.latitude,
                                                               longitude: point.longitude)),
                               description: "写入地图定位到所选照片")
                }, favorite: {
                    activeMarker = nil
                    workspace.favoriteDraft = SavedLocation(name: name, note: "", coordinate: point)
                })
        }
    }

    // Set the camera position
    func setCameraPosition(to coords: Coords) {
        cameraPosition = .camera(.init(centerCoordinate: coords,
                                       distance: cameraDistance))
    }

    func zoomByWheel(_ steps: Double, at point: CGPoint, proxy: MapProxy) {
        guard steps != 0, let anchor = proxy.convert(point, from: .local) else { return }
        startupCancelled = true
        let oldDistance = cameraDistance
        let nextDistance = Self.wheelZoomDistance(oldDistance, steps: steps)
        let center = camera?.centerCoordinate ?? CLLocationCoordinate2D(
            latitude: initialMapLatitude, longitude: initialMapLongitude)
        let nextCenter = Self.wheelZoomCenter(MKMapPoint(center), anchor: MKMapPoint(anchor),
                                              ratio: nextDistance / oldDistance).coordinate
        cameraDistance = nextDistance
        let nextCamera = MapCamera(centerCoordinate: nextCenter, distance: nextDistance,
                                   heading: camera?.heading ?? 0, pitch: camera?.pitch ?? 0)
        camera = nextCamera
        cameraPosition = .camera(nextCamera)
    }

    static func wheelZoomDistance(_ distance: Double, steps: Double) -> Double {
        min(40_000_000, max(100, distance * pow(0.82, steps)))
    }

    static func wheelZoomCenter(_ center: MKMapPoint, anchor: MKMapPoint, ratio: Double) -> MKMapPoint {
        MKMapPoint(x: anchor.x + (center.x - anchor.x) * ratio,
                   y: anchor.y + (center.y - anchor.y) * ratio)
    }

    // recenter map if the given coords are not in view
    func recenter(on coords: Coords?) {
        if let coords, let rect = mapRect {
            if !rect.contains(MKMapPoint(coords)) {
                setCameraPosition(to: coords)
            }
        }
    }

    func updateEdgePhotos(_ proxy: MapProxy, size: CGSize) {
        guard size.width > 80, size.height > 80 else { edgePhotos = []; return }
        let inset: CGFloat = 36
        edgePhotos = allPhotoPins.filter { store.selection.contains($0.id) }.compactMap { pin in
            let id = pin.id
            let image = store[id]
            guard image.metadata.canDisplayAsWGS84, let location = image.metadata.location,
                  let point = proxy.convert(location, to: .local),
                  point.x < inset || point.x > size.width - inset
                    || point.y < inset || point.y > size.height - inset else { return nil }
            return EdgePhoto(image: image, location: location,
                             point: Self.edgePoint(for: point, in: size, inset: inset))
        }
    }

    static func edgePoint(for point: CGPoint, in size: CGSize, inset: CGFloat) -> CGPoint {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let delta = CGVector(dx: point.x - center.x, dy: point.y - center.y)
        let horizontal = abs(delta.dx) > 0 ? (size.width / 2 - inset) / abs(delta.dx) : .infinity
        let vertical = abs(delta.dy) > 0 ? (size.height / 2 - inset) / abs(delta.dy) : .infinity
        let scale = min(horizontal, vertical)
        return CGPoint(x: center.x + delta.dx * scale, y: center.y + delta.dy * scale)
    }

    static func edgeDirection(for point: CGPoint, in size: CGSize) -> Angle {
        .radians(atan2(point.y - size.height / 2, point.x - size.width / 2))
    }
}

// Photo pins use the image ID so selection and drag completion cannot target a
// different photo after the store refreshes.

extension MapView {
    private static let maximumVisiblePhotoGroups = 600

    struct CoordinateKey: Hashable {
        let latitude: Double
        let longitude: Double
    }

    struct PhotoPin: Identifiable {
        let id: ImageData.ID
        let image: ImageData
        let location: Coords
        let selected: Bool
        let editable: Bool

        init(image: ImageData, location: Coords, selected: Bool, editable: Bool) {
            id = image.id
            self.image = image
            self.location = location
            self.selected = selected
            self.editable = editable
        }
    }

    struct PhotoPinGroup: Identifiable {
        let pins: [PhotoPin]
        let location: Coords
        var id: ImageData.ID { pins[0].id }
    }

    struct EdgePhoto: Identifiable {
        let image: ImageData
        let location: Coords
        let point: CGPoint
        var id: ImageData.ID { image.id }
    }

    private struct PhotoCell: Hashable {
        let column: Int
        let row: Int
    }

    static func groupedPhotoPins(_ pins: [PhotoPin], in visibleRect: MKMapRect? = nil) -> [PhotoPinGroup] {
        guard pins.count > maximumVisiblePhotoGroups else { return exactPhotoGroups(pins) }

        var rect = visibleRect ?? .null
        if rect.isNull {
            for pin in pins {
                let point = MKMapPoint(pin.location)
                rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
            }
        }
        let paddedRect = rect.insetBy(dx: -max(rect.width * 0.1, 1),
                                      dy: -max(rect.height * 0.1, 1))
        let visible = pins.filter { paddedRect.contains(MKMapPoint($0.location)) }
        guard visible.count > maximumVisiblePhotoGroups else { return exactPhotoGroups(visible) }

        let cellWidth = max(rect.width / 30, 1)
        let cellHeight = max(rect.height / 20, 1)
        return Dictionary(grouping: visible) { pin in
            let point = MKMapPoint(pin.location)
            return PhotoCell(column: Int((point.x - rect.minX) / cellWidth),
                             row: Int((point.y - rect.minY) / cellHeight))
        }.values.compactMap { members in
            guard !members.isEmpty else { return nil }
            let points = members.map { MKMapPoint($0.location) }
            let center = MKMapPoint(x: points.map(\.x).reduce(0, +) / Double(points.count),
                                    y: points.map(\.y).reduce(0, +) / Double(points.count)).coordinate
            return PhotoPinGroup(pins: members.sorted { $0.id < $1.id },
                                 location: Coords(latitude: center.latitude, longitude: center.longitude))
        }.sorted { $0.id < $1.id }
    }

    private static func exactPhotoGroups(_ pins: [PhotoPin]) -> [PhotoPinGroup] {
        Dictionary(grouping: pins) {
            CoordinateKey(latitude: $0.location.latitude, longitude: $0.location.longitude)
        }.values.compactMap { members in
            guard let first = members.first else { return nil }
            return PhotoPinGroup(pins: members.sorted { $0.id < $1.id }, location: first.location)
        }.sorted { $0.id < $1.id }
    }

    func displayPin(for group: PhotoPinGroup) -> PhotoPin {
        group.pins.first(where: { store.selection.contains($0.id) }) ?? group.pins[0]
    }

    func selectPin(_ group: PhotoPinGroup) {
        let current = store.mostSelected.flatMap { id in group.pins.firstIndex { $0.id == id } }
        let next = group.pins[(current.map { ($0 + 1) % group.pins.count }) ?? 0]
        store.send(.selectionChanged([next.id]), undoable: false)
    }
}

// Map track support

extension MapView {

    // An identifial container to hold map tracks
    struct MapTrack: Identifiable {
        let id = UUID()
        let coords: [Coords]
        let fileID: String
    }

    // Convert the array of gpxTrackLogs into an array of MapTracks
    // where each non empty segment of a gpxTrackLog track is a MapTrack.

    func mapTracks() -> [MapTrack] {
        workspace.tracks.displays(amap: false).flatMap { display in
            display.segments.map { segment in
                MapTrack(coords: segment.map { Coords(latitude: $0.latitude, longitude: $0.longitude) }, fileID: display.id)
            }
        }
    }
}

// Map View related default keys

extension MapView {
    static let initialMapLatitudeKey = "InitialMapLatitude"
    static let initialMapLongitudeKey = "InitialMapLongitude"
    static let initialMapDistanceKey = "InitialMapDistance"
    static let lastMapLatitudeKey = "PhotoTrailAppleLastMapLatitude"
    static let lastMapLongitudeKey = "PhotoTrailAppleLastMapLongitude"
    static let lastMapDistanceKey = "PhotoTrailAppleLastMapDistance"
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
