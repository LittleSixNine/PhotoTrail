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
        .onDisappear { workspace.ready = false }
    }
}
