import Coords
import SwiftUI
import UDF

struct AMapSnapshot: Codable, Equatable {
    let revision: Int
    let point: MapCoordinate?
    let editable: Bool
}

struct AMapView: View {
    @Environment(Store<GeoTagState, GeoTagEvent>.self) private var store
    @Environment(LocationWorkspace.self) private var workspace

    private var snapshot: AMapSnapshot {
        let metadata = store[store.mostSelected].metadata
        let point = metadata.canDisplayAsWGS84 ? metadata.location.map {
            MapCoordinate(latitude: $0.latitude, longitude: $0.longitude)
        } : nil
        return AMapSnapshot(revision: store.version, point: point,
                            editable: !store.saveInProgress && !store.selection.isEmpty
                            && store.selection.allSatisfy { store[$0].updatable })
    }

    var body: some View {
        Group {
            if let credentials = workspace.credentials {
                AMapWebView(snapshot: snapshot, credentials: credentials,
                            onPick: { coordinate in
                    store.send(.confirmedWGS84Location(
                        Coords(latitude: coordinate.latitude, longitude: coordinate.longitude)),
                               description: "高德地图定位")
                }, workspace: workspace)
                .id(workspace.session)
            } else {
                ContentUnavailableView {
                    Label("配置高德地图", systemImage: "map")
                } description: {
                    Text("在照片右侧的“高德设置”中填写凭据。")
                } actions: {
                    Button("高德设置…") { workspace.settingsPresented = true }
                }
            }
        }
    }
}
