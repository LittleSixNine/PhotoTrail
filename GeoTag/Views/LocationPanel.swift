import Coords
import SwiftUI
import UDF

struct PhotoWithLocationPanel: View {
    @State private var expanded = true
    var body: some View {
        HStack(spacing: 0) {
            ImageView().frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            if expanded {
                LocationPanel().frame(width: 290)
            }
            Button {
                expanded.toggle()
            } label: {
                Image(systemName: expanded ? "sidebar.right" : "sidebar.left")
            }
            .buttonStyle(.borderless)
            .help(expanded ? "收起位置面板" : "展开位置面板")
            .padding(6)
        }
    }
}

struct LocationPanel: View {
    @Environment(Store<GeoTagState, GeoTagEvent>.self) private var store
    @Environment(LocationWorkspace.self) private var workspace
    @AppStorage("GeoTagCNMapProvider") private var provider = "apple"
    @FocusState private var textFocused: Bool

    private var editable: Bool {
        !store.saveInProgress && !store.selection.isEmpty && store.selection.allSatisfy { store[$0].updatable }
    }

    var body: some View {
        @Bindable var workspace = workspace
        let content = VStack(alignment: .leading, spacing: 12) {
                Picker("地图", selection: $provider) {
                    Text("苹果").tag("apple")
                    Text("高德").tag("amap")
                }
                .pickerStyle(.segmented)
                if provider == "amap" { searchSection }
                statusSection
                Divider()
                favoritesSection
                if provider == "amap" {
                    Divider()
                    HStack {
                        Button("高德设置…") { workspace.settingsPresented = true }
                        Button("重新加载") { workspace.reload() }.disabled(workspace.credentials == nil)
                    }
                }
            }
            .padding(12)
        return ScrollView { content }
        .sheet(isPresented: $workspace.settingsPresented) {
            AMapSettingsView { credentials in
                workspace.credentials = credentials
                workspace.reload()
            }
            .onAppear { store.send(.textfieldFocusChanged(true), undoable: false) }
            .onDisappear { store.send(.textfieldFocusChanged(false), undoable: false) }
        }
        .sheet(item: $workspace.favoriteDraft) { favorite in
            FavoriteEditor(favorite: favorite)
        }
        .onChange(of: textFocused) {
            store.send(.textfieldFocusChanged(textFocused), undoable: false)
        }
        .onChange(of: store.mapSearchActive) {
            if provider == "amap" && store.mapSearchActive { textFocused = true }
        }
        .task(id: workspace.query) {
            workspace.invalidateSelection?()
            let query = workspace.query.trimmingCharacters(in: .whitespacesAndNewlines)
            workspace.results = []
            workspace.selectedResult = nil
            workspace.searching = false
            guard provider == "amap", workspace.ready, !query.isEmpty else { return }
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            workspace.search?(query)
        }
        .onChange(of: provider) {
            workspace.status = provider == "amap" ? "高德地图加载中…" : "在地图点选位置，或应用收藏地点。"
            workspace.query = ""
            workspace.selectedResult = nil
            textFocused = false
        }
    }

    private var searchSection: some View {
        @Bindable var workspace = workspace
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("搜索地点，例如东方明珠", text: $workspace.query)
                    .textFieldStyle(.roundedBorder)
                    .focused($textFocused)
                    .onSubmit { workspace.search?(workspace.query.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    .disabled(!workspace.ready)
                if !workspace.query.isEmpty {
                    Button { workspace.query = "" } label: { Image(systemName: "xmark.circle") }
                        .buttonStyle(.borderless).help("清空搜索")
                }
            }
            if workspace.searching { ProgressView("搜索中…").controlSize(.small) }
            ForEach(workspace.results) { result in
                Button {
                    workspace.selectedResult = result
                    workspace.previewSearch?(result)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.name).fontWeight(.medium)
                        Text(result.address).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(workspace.selectedResult?.id == result.id ? Color.accentColor.opacity(0.12) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
            }
            if let result = workspace.selectedResult {
                HStack {
                    Button("应用到 \(store.selection.count) 张") {
                        workspace.chooseSearch?(result, "apply")
                    }.disabled(!editable || !workspace.ready)
                    Button("收藏此地点") { workspace.chooseSearch?(result, "favorite") }
                        .disabled(!workspace.ready)
                }
            }
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("当前位置").font(.headline)
            Text("已选择 \(store.selection.count) 张照片").font(.caption)
            Text(workspace.status).font(.caption).textSelection(.enabled)
            if store.unsavedChanges { Label("有未保存的修改", systemImage: "pencil.circle").font(.caption) }
            DisclosureGroup("定位详情") {
                VStack(alignment: .leading, spacing: 4) {
                    let metadata = store[store.mostSelected].metadata
                    if let point = metadata.location {
                        Text("纬度：\(point.latitude, specifier: "%.6f")")
                        Text("经度：\(point.longitude, specifier: "%.6f")")
                        Text(metadata.gpsMapDatum?.isEmpty != false
                             ? "原照片未声明坐标系，暂按 WGS84 显示；浏览不会修改照片。"
                             : "坐标基准：\(metadata.gpsMapDatum ?? "")")
                    } else { Text("这张照片暂无可显示的位置。") }
                    Text("高德地图显示主选照片；点选会设置全部选中照片的位置，保存后写入 WGS84。")
                }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
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
