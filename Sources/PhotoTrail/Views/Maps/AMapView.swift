import Coords
import GpxTrackLog
import ImageData
import SwiftUI
import UDF

struct AMapPhoto: Codable, Equatable, Identifiable {
    let id: ImageData.ID
    let point: MapCoordinate
    let editable: Bool
}

struct AMapSnapshot: Codable, Equatable {
    let revision: Int
    let point: MapCoordinate?
    let editable: Bool
    let photos: [AMapPhoto]
    var allowDoubleClick = true
    var allowDragPin = true
    var selectedPhotoIDs: [ImageData.ID] = []
}

struct AMapView: View {
    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) private var store
    @Environment(LocationWorkspace.self) private var workspace
    let startupCoordinate: MapCoordinate?
    let onMapTap: () -> Void
    @AppStorage(SettingsView.trackWidthKey) private var trackWidth = 0.0
    @AppStorage(SettingsView.trackColorKey) private var trackColor = Color.red
    @AppStorage(SettingsPreferences.showAllPhotoLocationsKey) private var showAllPhotoLocations = true
    @AppStorage(SettingsPreferences.doubleClickKey) private var allowDoubleClick = true
    @AppStorage(SettingsPreferences.dragPinKey) private var allowDragPin = true
    private var mapStyles = AMapStylePreferences()
    @State private var photos: [AMapPhoto] = []
    @GestureState private var photoDrag: PhotoDrag?
    @State private var pendingPhotoDrag: PendingPhotoDrag?

    private struct PhotoDrag: Equatable {
        let id: ImageData.ID
        let translation: CGSize
    }

    private struct PendingPhotoDrag {
        let drag: PhotoDrag
        let original: MapCoordinate
    }

    private var strokeColor: String {
        let color = NSColor(trackColor).usingColorSpace(.sRGB) ?? .black
        return String(format: "#%02X%02X%02X", Int(color.redComponent * 255),
                      Int(color.greenComponent * 255), Int(color.blueComponent * 255))
    }

    private var snapshot: AMapSnapshot {
        let metadata = store[store.mostSelected].metadata
        let point = metadata.canDisplayAsWGS84 ? metadata.location.map {
            MapCoordinate(latitude: $0.latitude, longitude: $0.longitude)
        } : nil
        return AMapSnapshot(revision: store.mapRevision, point: point,
                            editable: !store.saveInProgress && !store.selection.isEmpty
                            && store.selection.allSatisfy { store[$0].updatable }, photos: photos,
                            allowDoubleClick: allowDoubleClick, allowDragPin: allowDragPin,
                            selectedPhotoIDs: store.selection.sorted())
    }

    var body: some View {
        Group {
            if let credentials = workspace.credentials {
                ZStack(alignment: .topLeading) {
                    AMapWebView(snapshot: snapshot, credentials: credentials,
                                startupCoordinate: startupCoordinate,
                                deviceCoordinate: workspace.deviceCoordinate,
                                deviceFocusID: workspace.deviceFocusID,
                                trackRevision: workspace.tracks.revision,
                                fitRevision: workspace.tracks.fitRevision,
                                mapStyle: mapStyles.selection.wrappedValue,
                                trackColor: strokeColor, trackWidth: trackWidth,
                                onMapTap: onMapTap,
                                onPick: { id, coordinate in
                        let coords = Coords(latitude: coordinate.latitude,
                                            longitude: coordinate.longitude)
                        if let id {
                            store.send(.locationForImageChanged(id, coords),
                                       description: L10n.text("拖动高德照片位置"))
                        } else {
                            store.send(.confirmedWGS84Location(coords),
                                       description: L10n.text("高德地图定位"))
                        }
                    }, workspace: workspace)
                    ForEach(workspace.amapPhotoPositions) { position in
                        if let id = displayID(for: position) {
                            let image = store[id]
                            PhotoThumbnailMapPin(image: image,
                                                 selected: store.selection.contains(id),
                                                 clusterCount: position.ids.count)
                                .position(x: position.x, y: position.y - 29)
                                .offset(photoDrag?.id == id ? photoDrag?.translation ?? .zero
                                    : pendingPhotoDrag?.drag.id == id
                                        ? pendingPhotoDrag?.drag.translation ?? .zero : .zero)
                                .onTapGesture {
                                    onMapTap()
                                    selectPosition(position)
                                }
                                .gesture(DragGesture(minimumDistance: 3,
                                                     coordinateSpace: .named("amapOverlay"))
                                    .updating($photoDrag) { value, state, _ in
                                        guard workspace.ready, allowDragPin, store.selection.contains(id),
                                              image.updatable, !store.saveInProgress else { return }
                                        state = PhotoDrag(id: id, translation: value.translation)
                                    }
                                    .onEnded { value in
                                        guard workspace.ready, allowDragPin, store.selection.contains(id),
                                              image.updatable, !store.saveInProgress,
                                              let original = image.metadata.location else { return }
                                        pendingPhotoDrag = PendingPhotoDrag(
                                            drag: PhotoDrag(id: id, translation: value.translation),
                                            original: MapCoordinate(latitude: original.latitude,
                                                                    longitude: original.longitude))
                                        workspace.moveAMapPhoto?(
                                            id,
                                            CGPoint(x: position.x + value.translation.width,
                                                    y: position.y + value.translation.height))
                                    }, including: workspace.ready && allowDragPin && store.selection.contains(id)
                                        && image.updatable && !store.saveInProgress ? .all : .none)
                        }
                    }
                    ForEach(workspace.amapPhotoEdges) { edge in
                        Button { workspace.focusPhoto?(edge.id) } label: {
                            PhotoEdgeIndicator(image: store[edge.id],
                                               direction: .radians(edge.angle))
                        }
                        .buttonStyle(.plain)
                        .position(x: edge.x, y: edge.y)
                    }
                }
                .coordinateSpace(name: "amapOverlay")
                .background {
                    MapScrollWheelMonitor { steps, point in workspace.zoomAMap?(steps, point) }
                }
                .id(workspace.session)
            } else {
                ZStack {
                    Color(nsColor: .controlBackgroundColor)
                    VStack(spacing: 16) {
                        Image(systemName: "map").font(.system(size: 44)).foregroundStyle(.secondary)
                        Text(L10n.text("设置高德地图后开始定位")).font(.title2.bold())
                        Text(L10n.text("填写你的高德 Key 和安全密钥，即可搜索地点、查看地图。\n也可以在左侧地图设置中切换到苹果地图。"))
                            .multilineTextAlignment(.center).foregroundStyle(.secondary)
                        Button(L10n.text("设置高德地图…")) { workspace.settingsPresented = true }
                            .buttonStyle(.borderedProminent)
                    }.padding(32)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)

            }
        }
        .onDisappear {
            workspace.ready = false
            pendingPhotoDrag = nil
        }
        .onChange(of: store.mapRevision) {
            guard let pending = pendingPhotoDrag else { return }
            let location = store[pending.drag.id].metadata.location
            if location?.latitude != pending.original.latitude
                || location?.longitude != pending.original.longitude { pendingPhotoDrag = nil }
        }
        .onChange(of: workspace.status) {
            if workspace.status.hasPrefix(L10n.text("位置已设置"))
                || workspace.status.contains(L10n.text("未修改")) || workspace.status.contains(L10n.text("重新拖动"))
                || workspace.status.contains(L10n.text("请先选择可编辑")) {
                pendingPhotoDrag = nil
            }
        }
        .onChange(of: workspace.ready) {
            if !workspace.ready { pendingPhotoDrag = nil }
        }
        .task(id: "\(store.mapRevision):\(showAllPhotoLocations)") {
            photos = SettingsPreferences.displayedPhotos(store.visibleImages, selection: store.selection,
                                                           showAll: showAllPhotoLocations).compactMap { image -> AMapPhoto? in
                guard image.metadata.canDisplayAsWGS84,
                      let location = image.metadata.location else { return nil }
                return AMapPhoto(id: image.id,
                                 point: MapCoordinate(latitude: location.latitude,
                                                      longitude: location.longitude),
                                 editable: image.updatable && !store.saveInProgress)
            }
        }
    }
}

private extension AMapView {
    func displayID(for position: AMapPhotoPosition) -> ImageData.ID? {
        position.ids.first(where: store.selection.contains) ?? position.ids.first
    }

    func selectPosition(_ position: AMapPhotoPosition) {
        guard !position.ids.isEmpty else { return }
        let current = store.mostSelected.flatMap { position.ids.firstIndex(of: $0) }
        let next = position.ids[(current.map { ($0 + 1) % position.ids.count }) ?? 0]
        store.send(.selectionChanged([next]), undoable: false)
    }
}

extension AMapView {
    // Only a display payload: GPX timestamps, elevations and WGS84 source stay untouched.
    static func trackSegments(_ logs: [GpxTrackLog]) throws -> [[MapCoordinate]] {
        try logs.flatMap(\.tracks).flatMap(\.segments).compactMap { segment in
            let points = segment.points.map { MapCoordinate(latitude: $0.lat, longitude: $0.lon) }
            guard points.allSatisfy(\.isValid) else { throw CocoaError(.validationMissingMandatoryProperty) }
            return points.count >= 2 ? points : nil
        }
    }
}
