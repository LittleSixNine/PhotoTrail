import Coords
import ImageData
import MapKit
import SwiftUI
import UDF

struct LocationPanel: View {
    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) private var store
    @Environment(LocationWorkspace.self) private var workspace
    @AppStorage("PhotoTrailMapProvider") private var provider = "amap"
    @AppStorage(Coords.coordFormatKey) private var coordFormat: CoordFormat = .deg
    @AppStorage(SettingsPreferences.automaticRegionKey) private var automaticRegion = true
    @AppStorage(SettingsPreferences.writeRegionKey) private var fillsMissingRegions = true

    @State private var region = ""
    @State private var displayedRegionKey = ""
    @State private var manualLookup = 0
    @State private var manualLookupKey = ""
    @State private var showsRegionHelp = false
    @State private var showsAllFavorites = false

    private var regionKey: String {
        guard let point = store[store.mostSelected].metadata.location else { return "" }
        return "\(L10n.language.rawValue):\(provider):\(point.latitude):\(point.longitude)"
    }

    var body: some View {
        @Bindable var workspace = workspace
        let selection = MapPhotoSelectionSummary(images: store.imageData, selectedIDs: store.selection)
        let content = VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(L10n.text("照片定位")).font(.headline)
                    Spacer()
                    mapSettings
                }
                photoPreview
                Divider()
                statusSection(selection)
                Divider()
                favoritesSection(selection)
                Divider()
                TrackSidebar()
            }
            .font(.system(size: 14))
            .padding(16)
        return content
        .task(id: "\(regionKey):\(provider == "amap" && workspace.ready):\(automaticRegion):\(manualLookup)") {
            let key = regionKey
            displayedRegionKey = key
            region = ""
            let metadata = store[store.mostSelected].metadata
            guard let point = metadata.location, metadata.canDisplayAsWGS84 else { return }
            if let cached = workspace.regionCache[key] { region = cached.regionName; return }
            guard automaticRegion || (manualLookup > 0 && manualLookupKey == key) else { return }
            region = L10n.text("正在读取地区…")
            do {
                if automaticRegion { try await Task.sleep(for: .milliseconds(500)) }
                let place = try await workspace.address(at:
                    MapCoordinate(latitude: point.latitude, longitude: point.longitude), provider: provider)
                let name = place.regionName
                guard !Task.isCancelled, key == regionKey,
                      automaticRegion || (manualLookup > 0 && manualLookupKey == key) else { return }
                region = name.isEmpty ? L10n.text("暂无地区信息") : name
            } catch {
                guard !Task.isCancelled, key == regionKey,
                      automaticRegion || (manualLookup > 0 && manualLookupKey == key) else { return }
                region = L10n.text("地区暂不可用")
                if manualLookup > 0, manualLookupKey == key { OperationFailure.present(region, error: error) }
            }
        }
        .onChange(of: automaticRegion) { manualLookup = 0; manualLookupKey = "" }
        .onAppear { workspace.fillRegionsOnLocationChange = fillsMissingRegions }
        .onChange(of: fillsMissingRegions) { workspace.fillRegionsOnLocationChange = fillsMissingRegions }
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
            Menu(L10n.text("地图来源")) {
                providerOption("apple", title: L10n.text("苹果地图（WGS-84）"), subtitle: L10n.text("海外拍摄优先"))
                providerOption("amap", title: L10n.text("高德地图（GCJ-02）"), subtitle: L10n.text("中国大陆拍摄优先"))
            }
            AppAppearancePicker()
            if provider == "amap" { AMapStylePicker() }
            Divider()
            Button(L10n.text("高德 API 设置…")) { workspace.settingsPresented = true }
            Button(L10n.text("重新加载高德地图")) { workspace.reload() }
                .disabled(provider != "amap" || workspace.credentials == nil)
        } label: {
            Image(systemName: "gearshape").font(.system(size: 17)).frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(L10n.text("地图设置"))
        .accessibilityLabel(L10n.text("地图设置"))
    }

    private func providerOption(_ value: String, title: String, subtitle: String) -> some View {
        Toggle(isOn: Binding(get: { provider == value }, set: { selected in
            if selected { provider = value }
        })) {
            Text(title)
            Text(subtitle)
        }
    }

}

private extension LocationPanel {
    var photoPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            ImageView().aspectRatio(1.5, contentMode: .fit)
                .padding(.horizontal, -16)
            if let id = store.mostSelected {
                Text(store[id].name).font(.headline).lineLimit(1).truncationMode(.middle)
                    .help(store[id].name)
                Text(store[id].metadata.timestamp).font(.caption).foregroundStyle(.secondary)
                if store.selection.count > 1 {
                    Text(L10n.text("上方仅预览当前照片"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var regionTitle: String {
        if displayedRegionKey == regionKey && !region.isEmpty { return region }
        return automaticRegion ? L10n.text("正在读取地区…") : L10n.text("点击查询地区")
    }

    private func statusSection(_ selection: MapPhotoSelectionSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(selection.total > 1 ? L10n.text("所选照片的定位") : L10n.text("当前照片的位置"))
                    .font(.headline)
                Spacer(minLength: 4)
                Button { toggleCurrentFavorite() } label: {
                    Image(systemName: currentFavorite == nil ? "star" : "star.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(currentFavorite == nil ? Color.secondary : Color.yellow)
                        .frame(width: 28, height: 28)
                }
                    .buttonStyle(.plain)
                    .disabled(store.mostSelected == nil || store[store.mostSelected].metadata.location == nil)
                    .help(currentFavorite == nil ? L10n.text("收藏当前位置") : L10n.text("取消收藏当前位置"))
                    .accessibilityLabel(currentFavorite == nil ? L10n.text("收藏当前位置") : L10n.text("取消收藏当前位置"))
                    .accessibilityValue(currentFavorite == nil ? L10n.text("未收藏") : L10n.text("已收藏"))
                    .accessibilityIdentifier("favoriteCurrentLocation")
            }
            if selection.total == 0 {
                Text(L10n.text("选择照片以查看定位")).foregroundStyle(.secondary)
            } else {
                if selection.total > 1 {
                    Text(L10n.text("%1$@ 张缺少定位 · %2$@ 张已有定位 · %3$@ 张缺少城市信息",
                                   selection.missing, selection.located, selection.missingCity))
                        .font(.system(size: 15, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    if selection.unreadable > 0 {
                        Text(L10n.text("读取失败：%1$@ 张；请检查来源文件。", selection.unreadable))
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Text(L10n.text("当前预览"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                currentLocation
                if selection.pending > 0 {
                    Label(L10n.text("定位修改待写入：%1$@ 张", selection.pending), systemImage: "pencil.circle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            if !workspace.status.isEmpty,
               !workspace.status.hasPrefix(L10n.text("高德地图已就绪")),
               !workspace.status.hasPrefix(L10n.text("选择照片后")),
               !workspace.status.hasPrefix(L10n.text("在地图点选")) {
                Text(workspace.status).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.textSelection(.enabled)
    }

    private var regionControl: some View {
        HStack(spacing: 4) {
            Toggle(L10n.text("补齐地区"), isOn: Binding(
                get: { fillsMissingRegions },
                set: { fillsMissingRegions = $0; workspace.fillRegionsOnLocationChange = $0 }))
                .font(.system(size: 12))
                .toggleStyle(SidebarCheckboxToggleStyle())
                .disabled(store.saveInProgress || store.importProgress.isActive || store.renameInProgress)
                .accessibilityIdentifier("linkedRegionFilling")
            Button { showsRegionHelp.toggle() } label: {
                Image(systemName: "info.circle").font(.system(size: 12)).frame(width: 24, height: 28)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .accessibilityLabel(L10n.text("补齐地区说明"))
            .popover(isPresented: $showsRegionHelp, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("联动补齐地区")).font(.headline)
                    Text(L10n.text("开启后，应用或补齐定位时，根据新定位补齐省、市、区县等信息。"))
                    Text(L10n.text("仅补缺失项，保留已有文字。修改先暂存，保存照片时才写入。"))
                        .foregroundStyle(.secondary)
                }.font(.callout).padding(16).frame(width: 280)
            }
        }.fixedSize()
    }

    private var currentLocation: some View {
        VStack(alignment: .leading, spacing: 10) {
            let metadata = store[store.mostSelected].metadata
            if !metadata.readable {
                Text(L10n.text("元数据读取失败")).foregroundStyle(.orange)
            } else if let point = metadata.location {
                Label(regionTitle, systemImage: "mappin.and.ellipse")
                    .font(.system(size: 18, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if !automaticRegion {
                    Button(L10n.text("查询地区")) { manualLookupKey = regionKey; manualLookup += 1 }
                        .buttonStyle(.borderless)
                }
                HStack(alignment: .bottom, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        coordinateText(point, latitude: true)
                        coordinateText(point, latitude: false)
                    }
                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    regionControl
                }

            } else {
                Label(L10n.text("暂无定位"), systemImage: "mappin.slash")
                    .font(.system(size: 18, weight: .semibold)).foregroundStyle(.secondary)
                regionControl
            }
        }
    }

    private func coordinateText(_ point: Coords, latitude: Bool) -> some View {
        Text(L10n.text(latitude ? "纬度 %1$@" : "经度 %1$@",
            coordToString(for: latitude ? point.latitude : point.longitude,
                          ref: latitude ? Coords.latRef : Coords.lonRef, format: coordFormat)))
    }

    private func favoritesSection(_ selection: MapPhotoSelectionSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(L10n.text("收藏地点"), systemImage: "star").font(.headline)
                Spacer()
                Text("\(workspace.favorites.count)").foregroundStyle(.secondary)
            }
            if workspace.favorites.isEmpty {
                Text(L10n.text("收藏常用地点，方便下次直接应用。"))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                favoriteRows(Array(workspace.favorites.prefix(2)), selection: selection)
                if workspace.favorites.count > 2 {
                    Button { showsAllFavorites.toggle() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: showsAllFavorites ? "chevron.up" : "chevron.down")
                            if !showsAllFavorites {
                                Text(verbatim: "+\(workspace.favorites.count - 2)").monospacedDigit()
                            }
                        }
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showsAllFavorites ? L10n.text("收起其余收藏，仅显示前2处")
                        : L10n.text("展开其余收藏：%1$@ 处", workspace.favorites.count - 2))
                    .accessibilityValue(showsAllFavorites ? L10n.text("已展开") : L10n.text("已收起"))
                    .accessibilityIdentifier("expandFavoriteLocations")
                    if showsAllFavorites {
                        favoriteRows(Array(workspace.favorites.dropFirst(2)), selection: selection)
                    }
                }
                if store.saveInProgress {
                    Text(L10n.text("正在保存")).font(.caption).foregroundStyle(.secondary)
                } else if !selection.allEditable {
                    Text(selection.total == 0 ? L10n.text("选择照片以应用收藏")
                         : L10n.text("所选照片包含无法编辑的项目，应用收藏前请调整选择。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let error = workspace.favoriteError {
                Text(error).font(.caption).foregroundStyle(.orange)
                Button(L10n.text("重试读取")) { workspace.loadFavorites() }.buttonStyle(.borderless)
            }
        }
    }

    private func favoriteRows(_ favorites: [SavedLocation], selection: MapPhotoSelectionSummary) -> some View {
        VStack(spacing: 0) {
            ForEach(favorites) { favorite in
                favoriteRow(favorite, editable: selection.allEditable && !store.saveInProgress
                    && !store.importProgress.isActive && !store.renameInProgress)
                if favorite.id != favorites.last?.id { Divider() }
            }
        }
    }

    private func favoriteRow(_ favorite: SavedLocation, editable: Bool) -> some View {
        HStack(spacing: 8) {
            Button { workspace.preview(favorite.coordinate) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.and.ellipse").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(favorite.name).fontWeight(.medium)
                        if !favorite.note.isEmpty {
                            Text(favorite.note).font(.caption).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button(L10n.text("应用")) {
                store.send(.confirmedWGS84Location(Coords(latitude: favorite.coordinate.latitude,
                                                         longitude: favorite.coordinate.longitude)),
                           description: L10n.text("应用收藏地点"))
                LocationHelper.scheduleLinkedRegions(store, workspace: workspace, ids: store.selection)
                workspace.status = L10n.text("定位修改已暂存，请写入所有元数据。")
            }.buttonStyle(.borderless).disabled(!editable)
            Menu {
                Button(L10n.text("编辑名称和备注")) { workspace.favoriteDraft = favorite }
                Button(L10n.text("删除收藏"), role: .destructive) {
                    do { try workspace.deleteFavorite(favorite.id) } catch {
                        workspace.status = OperationFailure.message(L10n.text("删除收藏失败，原记录已保留。"), error: error)
                        OperationFailure.present(workspace.status)
                    }
                }
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help(L10n.text("管理收藏"))
        }.padding(.vertical, 8)
    }

    private var currentFavorite: SavedLocation? {
        let metadata = store[store.mostSelected].metadata
        guard let point = LocationHelper.favoriteCoordinate(metadata) else { return nil }
        return workspace.favorites.first {
            abs($0.coordinate.latitude - point.latitude) < 0.000001
                && abs($0.coordinate.longitude - point.longitude) < 0.000001
        }
    }

    private func toggleCurrentFavorite() {
        guard let favorite = currentFavorite else { favoritePhoto(); return }
        do { try workspace.deleteFavorite(favorite.id) } catch {
            workspace.status = OperationFailure.message(L10n.text("删除收藏失败，原记录已保留。"), error: error)
            OperationFailure.present(workspace.status)
        }
    }

    private func favoritePhoto() {
        let metadata = store[store.mostSelected].metadata
        guard metadata.location != nil else { return }
        guard let point = LocationHelper.favoriteCoordinate(metadata) else {
            workspace.status = L10n.text("原照片坐标系尚未确认，请在高德搜索或重新选点后收藏。")
            return
        }
        workspace.favoriteDraft = SavedLocation(name: "", note: "", coordinate: point)
    }
}

private struct FavoriteEditor: View {
    @Environment(LocationWorkspace.self) private var workspace
    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var favorite: SavedLocation
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("收藏地点")).font(.title2)
            TextField(L10n.text("名称，例如家"), text: $favorite.name)
            TextField(L10n.text("备注（可选）"), text: $favorite.note, axis: .vertical)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button(L10n.text("取消")) { dismiss() }
                Button(L10n.text("保存收藏")) {
                    favorite.name = favorite.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    do { try workspace.saveFavorite(favorite); dismiss() } catch {
                        self.error = OperationFailure.message(L10n.text("收藏保存失败，原记录已保留。"), error: error)
                        OperationFailure.present(self.error!)
                    }
                }.disabled(favorite.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .textFieldStyle(.roundedBorder).padding(24).frame(width: 360)
        .onAppear { store.send(.textfieldFocusChanged(true), undoable: false) }
        .onDisappear { store.send(.textfieldFocusChanged(false), undoable: false) }
    }
}

// Basic GPS is read before images enter the list; full ExifTool inspection is independent.
struct MapPhotoSelectionSummary {
    var total = 0
    var located = 0
    var missingCity = 0
    var missing = 0
    var unreadable = 0
    var readOnly = 0
    var pending = 0
    private var expected = 0
    var allEditable: Bool { total > 0 && total == expected && readOnly == 0 }

    init(images: [ImageData], selectedIDs: Set<ImageData.ID>) {
        expected = selectedIDs.count
        for image in images where selectedIDs.contains(image.id) {
            total += 1
            if !image.metadata.readable { unreadable += 1 } else if image.metadata.location == nil {
                missing += 1
            } else {
                located += 1
                if image.metadata.city?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false { missingCity += 1 }
            }
            if !image.updatable { readOnly += 1 }
            if image.hasPendingLocationChanges { pending += 1 }
        }
    }
}
