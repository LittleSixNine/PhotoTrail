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
    var selectedPhotoIDs: [ImageData.ID] = []
}

struct AMapView: View {
    @Environment(Store<GeoTagState, GeoTagEvent>.self) private var store
    @Environment(LocationWorkspace.self) private var workspace
    @AppStorage(SettingsView.trackWidthKey) private var trackWidth = 0.0
    @AppStorage(SettingsView.trackColorKey) private var trackColor = Color.red
    @State private var photos: [AMapPhoto] = []
    @GestureState private var photoDrag: PhotoDrag?

    private struct PhotoDrag: Equatable {
        let id: ImageData.ID
        let translation: CGSize
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
                            selectedPhotoIDs: store.selection.sorted())
    }

    var body: some View {
        Group {
            if let credentials = workspace.credentials {
                ZStack(alignment: .topLeading) {
                    AMapWebView(snapshot: snapshot, credentials: credentials,
                                trackRevision: workspace.tracks.revision,
                                fitRevision: workspace.tracks.fitRevision,
                                trackColor: strokeColor, trackWidth: trackWidth,
                                onPick: { id, coordinate in
                        let coords = Coords(latitude: coordinate.latitude,
                                            longitude: coordinate.longitude)
                        if let id {
                            store.send(.locationForImageChanged(id, coords),
                                       description: "拖动高德照片位置")
                        } else {
                            store.send(.confirmedWGS84Location(coords),
                                       description: "高德地图定位")
                        }
                    }, workspace: workspace)
                    ForEach(workspace.amapPhotoPositions) { position in
                        if let id = displayID(for: position) {
                            let image = store[id]
                            PhotoThumbnailMapPin(image: image,
                                                 selected: store.selection.contains(id),
                                                 clusterCount: position.ids.count)
                                .position(x: position.x, y: position.y - 29)
                                .offset(photoDrag?.id == id ? photoDrag?.translation ?? .zero : .zero)
                                .onTapGesture { selectPosition(position) }
                                .gesture(DragGesture(minimumDistance: 3,
                                                     coordinateSpace: .named("amapOverlay"))
                                    .updating($photoDrag) { value, state, _ in
                                        guard position.ids.count == 1, image.updatable,
                                              !store.saveInProgress else { return }
                                        state = PhotoDrag(id: id, translation: value.translation)
                                    }
                                    .onEnded { value in
                                        guard position.ids.count == 1, image.updatable,
                                              !store.saveInProgress else { return }
                                        workspace.moveAMapPhoto?(id, value.location)
                                    })
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
                        Text("设置高德地图后开始定位").font(.title2.bold())
                        Text("填写你的高德 Key 和安全密钥，即可搜索地点、查看地图。\n也可以在左侧地图设置中切换到苹果地图。")
                            .multilineTextAlignment(.center).foregroundStyle(.secondary)
                        Button("设置高德地图…") { workspace.settingsPresented = true }
                            .buttonStyle(.borderedProminent)
                    }.padding(32)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)

            }
        }
        .onDisappear {
            workspace.ready = false
        }
        .task(id: store.mapRevision) {
            photos = store.visibleImages.compactMap { image -> AMapPhoto? in
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
