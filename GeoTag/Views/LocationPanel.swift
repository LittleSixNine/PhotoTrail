import Coords
import MapKit
import SwiftUI
import UDF

struct LocationPanel: View {
    @Environment(Store<GeoTagState, GeoTagEvent>.self) private var store
    @Environment(LocationWorkspace.self) private var workspace
    @AppStorage("GeoTagCNMapProvider") private var provider = "amap"

    @State private var region = ""
    @State private var displayedRegionKey = ""

    private var regionKey: String {
        guard let point = store[store.mostSelected].metadata.location else { return "" }
        return "\(provider):\(point.latitude):\(point.longitude)"
    }

    private var editable: Bool {
        !store.saveInProgress && !store.selection.isEmpty && store.selection.allSatisfy { store[$0].updatable }
    }

    var body: some View {
        @Bindable var workspace = workspace
        let content = VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("当前位置").font(.headline)
                    Spacer()
                    mapSettings
                }
                statusSection
                Divider()
                favoritesSection
                Divider()
                Text("轨迹同步").font(.headline)
                Text("轨迹同步功能稍后加入。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
        return ScrollView { content }
        .task(id: "\(regionKey):\(provider == "amap" && workspace.ready)") {
            let key = regionKey
            displayedRegionKey = key
            region = ""
            let metadata = store[store.mostSelected].metadata
            guard let point = metadata.location, metadata.canDisplayAsWGS84 else { return }
            if let cached = workspace.regionCache[key] { region = cached; return }
            region = "正在读取地区…"
            do {
                try await Task.sleep(for: .milliseconds(500))
                let name: String
                if provider == "amap" {
                    guard let lookup = workspace.lookupAMapRegion, workspace.ready else {
                        region = "地图就绪后读取地区"
                        return
                    }
                    name = try await lookup(MapCoordinate(latitude: point.latitude, longitude: point.longitude))
                } else {
                    guard let request = MKReverseGeocodingRequest(location:
                        CLLocation(latitude: point.latitude, longitude: point.longitude)) else { return }
                    request.preferredLocale = Locale(identifier: "zh_CN")
                    let items = try await request.mapItems
                    let place = items.first?.placemark
                    var parts: [String] = []
                    for value in [place?.administrativeArea, place?.locality, place?.subLocality]
                        .compactMap({ $0 }) where !parts.contains(value) { parts.append(value) }
                    name = parts.joined(separator: " · ")
                }
                guard !Task.isCancelled, key == regionKey else { return }
                region = name.isEmpty ? "暂无地区信息" : name
                if !name.isEmpty {
                    if workspace.regionCache.count >= 256 { workspace.regionCache.removeAll() }
                    workspace.regionCache[key] = name
                }
            } catch {
                guard !Task.isCancelled, key == regionKey else { return }
                region = "地区暂不可用"
            }
        }
        .sheet(isPresented: $workspace.settingsPresented) {
            AMapSettingsView(initialCredentials: workspace.credentials) { credentials in
                workspace.credentials = credentials
                workspace.reload()
            }
            .onAppear { store.send(.textfieldFocusChanged(true), undoable: false) }
            .onDisappear { store.send(.textfieldFocusChanged(false), undoable: false) }
        }
        .sheet(item: $workspace.favoriteDraft) { favorite in
            FavoriteEditor(favorite: favorite)
        }
    }

    private var mapSettings: some View {
        Menu {
            Picker("地图来源", selection: $provider) {
                Text("苹果地图（海外拍摄优先）").tag("apple")
                Text("高德地图（中国大陆拍摄优先）").tag("amap")
            }
            Divider()
            Button("高德 API 设置…") { workspace.settingsPresented = true }
            Button("重新加载高德地图") { workspace.reload() }
                .disabled(provider != "amap" || workspace.credentials == nil)
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "mappin.and.ellipse").font(.system(size: 19))
                Image(systemName: "gearshape.fill").font(.system(size: 10))
                    .background(Color(nsColor: .windowBackgroundColor), in: Circle())
                    .offset(x: 5, y: 3)
            }.frame(width: 28, height: 26)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("地图设置")
        .accessibilityLabel("地图设置")
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            let metadata = store[store.mostSelected].metadata
            if let point = metadata.location {
                Text("纬度：\(point.latitude, specifier: "%.6f")")
                Text("经度：\(point.longitude, specifier: "%.6f")")
                if displayedRegionKey == regionKey, !region.isEmpty {
                    Text(region).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("暂无定位").foregroundStyle(.secondary)
            }
            if !workspace.status.isEmpty,
               !workspace.status.hasPrefix("高德地图已就绪"),
               !workspace.status.hasPrefix("选择照片后"),
               !workspace.status.hasPrefix("在地图点选") {
                Text(workspace.status).font(.caption).foregroundStyle(.secondary)
            }
        }.textSelection(.enabled)
    }

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("收藏地点").font(.headline)
                Spacer()
                Button("收藏照片位置") { favoritePhoto() }
                    .disabled(store[store.mostSelected].metadata.location == nil)
            }
            if let error = workspace.favoriteError {
                Text(error).font(.caption).foregroundStyle(.red)
                Button("重试读取") { workspace.loadFavorites() }
            }
            if workspace.favorites.isEmpty { Text("收藏常用地点，方便下次直接应用。").font(.caption).foregroundStyle(.secondary) }
            ForEach(workspace.favorites) { favorite in
                HStack {
                    Button { workspace.preview(favorite.coordinate) } label: {
                        VStack(alignment: .leading) {
                            Text(favorite.name)
                            if !favorite.note.isEmpty { Text(favorite.note).font(.caption).foregroundStyle(.secondary) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain)
                    Button("应用") {
                        store.send(.confirmedWGS84Location(Coords(latitude: favorite.coordinate.latitude,
                                                                 longitude: favorite.coordinate.longitude)),
                                   description: "应用收藏地点")
                        workspace.status = "已应用收藏位置，请保存照片。"
                    }.disabled(!editable)
                    Menu {
                        Button("编辑名称和备注") { workspace.favoriteDraft = favorite }
                        Button("删除收藏", role: .destructive) {
                            do {
                                try workspace.deleteFavorite(favorite.id)
                            } catch {
                                workspace.status = "删除收藏失败，原记录已保留。"
                            }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).fixedSize().help("管理收藏")
                }
            }
        }
    }

    private func favoritePhoto() {
        let metadata = store[store.mostSelected].metadata
        guard let point = metadata.location else { return }
        guard metadata.gpsMapDatum?.isEmpty == false, metadata.canDisplayAsWGS84 else {
            workspace.status = "原照片坐标系尚未确认，请在高德搜索或重新选点后收藏。"
            return
        }
        workspace.favoriteDraft = SavedLocation(name: "", note: "",
            coordinate: MapCoordinate(latitude: point.latitude, longitude: point.longitude))
    }
}

private struct FavoriteEditor: View {
    @Environment(LocationWorkspace.self) private var workspace
    @Environment(Store<GeoTagState, GeoTagEvent>.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var favorite: SavedLocation
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("收藏地点").font(.title2)
            TextField("名称，例如家", text: $favorite.name)
            TextField("备注（可选）", text: $favorite.note, axis: .vertical)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存收藏") {
                    favorite.name = favorite.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    do { try workspace.saveFavorite(favorite); dismiss() } catch { self.error = "收藏保存失败，原记录已保留。" }
                }.disabled(favorite.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .textFieldStyle(.roundedBorder).padding(24).frame(width: 360)
        .onAppear { store.send(.textfieldFocusChanged(true), undoable: false) }
        .onDisappear { store.send(.textfieldFocusChanged(false), undoable: false) }
    }
}
