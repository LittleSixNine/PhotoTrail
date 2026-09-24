import Coords
import ImageData
import SwiftUI
import UDF

struct ImageTableView: View {
    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) var store
    @AppStorage(Self.hideInvalidImagesKey) var hideInvalidImages = false
    @AppStorage(Coords.coordFormatKey) private var coordFormat: CoordFormat = .deg
    @Environment(LocationWorkspace.self) private var workspace
    @SceneStorage("PhotoTrailListFilter") private var filter: PhotoListFilter = .all
    @SceneStorage("PhotoTrailListUnmatchedOnly") private var unmatchedOnly = false
    @State private var pendingRemoval: Set<ImageData.ID> = []
    @State private var pendingClear: Set<ImageData.ID> = []
    @State private var selection: Set<ImageData.ID> = []
    @State private var sortOrder = [KeyPathComparator(\ImageData.name)]
    @FocusState private var searchFocused: Bool
    @Binding var inspectorPresented: Bool
    @Binding var batchActionsPresented: Bool
    var openDetail: () -> Void = {}

    private var searchableImages: [ImageData] {
        store.visibleImages.filter {
            (!hideInvalidImages || $0.updatable) && (store.searchText.isEmpty || $0.name.fuzzy(store.searchText))
        }
    }

    private var resultsByID: [ImageData.ID: LocationHelper.LocationById] {
        Dictionary(uniqueKeysWithValues: workspace.listMatchResults.map { ($0.id, $0) })
    }
    private var filteredImages: [ImageData] {
        let results = resultsByID
        return searchableImages.filter { image in
            filter.includes(image) && (!unmatchedOnly || results[image.id].map {
                $0.status == .unmatched || $0.status == .ambiguous || $0.status == .missingTime
            } == true)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索文件名", text: Binding(get: { store.searchText }, set: {
                    store.send(.searchTextChanged($0), undoable: false)
                }))
                .textFieldStyle(.plain).focused($searchFocused).frame(minWidth: 120, maxWidth: 260)
                Spacer(minLength: 0)
                Menu {
                    Button("导入顺序") { sortOrder = [KeyPathComparator(\ImageData.id)] }
                    Button("拍摄时间") { sortOrder = [KeyPathComparator(\ImageData.metadata.timestamp)] }
                    Button("文件名") { sortOrder = [KeyPathComparator(\ImageData.name)] }
                } label: { Label("排序", systemImage: "arrow.up.arrow.down") }
                    .fixedSize()
                Picker("筛选照片", selection: $filter) {
                    ForEach(PhotoListFilter.allCases, id: \.self) { option in
                        Text("\(option.rawValue) \(searchableImages.filter { option.includes($0) }.count)").tag(option)
                    }
                }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 440)
            }.padding(.leading, 14).padding(.vertical, 14)
            Divider()
            HStack {
                if !workspace.listMatchResults.isEmpty {
                    Toggle("仅看上次匹配未成功的照片", isOn: $unmatchedOnly).toggleStyle(.checkbox)
                    Button("清除匹配记录") { workspace.listMatchResults = []; unmatchedOnly = false }
                }
                Spacer()
                Text("已选择 \(store.selection.count) 张（当前显示 \(store.selection.intersection(Set(filteredImages.map(\.id))).count) 张）")
                    .foregroundStyle(.secondary)
                Button(batchActionsPresented ? "收起批量操作" : "批量操作") { batchActionsPresented.toggle() }
                    .disabled(store.selection.isEmpty && !batchActionsPresented)
            }.font(.callout).padding(10)
            photoTable
            Divider()
            HStack(spacing: 18) {
                Label("待保存", systemImage: "square.and.arrow.down").foregroundStyle(.orange)
                Label("无待保存修改", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Text("显示 \(filteredImages.count) / 共 \(store.visibleImages.count) 张照片").foregroundStyle(.secondary)
                Spacer()
            }.font(.caption).padding(12)
        }
        .onChange(of: selection) {
            if selection != store.selection { store.send(.selectionChanged(selection), undoable: false) }
        }
        .onChange(of: store.selection) { selection = store.selection }
        .onChange(of: filter) { retainVisibleSelection() }
        .onChange(of: store.searchText) { retainVisibleSelection() }
        .onChange(of: sortOrder) { store.send(.sortOrderChanged(sortOrder), undoable: false) }
        .onChange(of: searchFocused) { store.send(.textfieldFocusChanged(searchFocused), undoable: false) }
        .onChange(of: store.searchActive) { searchFocused = store.searchActive }
        .onAppear { selection = store.selection; sortOrder = store.sortOrder }
        .onDisappear { store.send(.textfieldFocusChanged(false), undoable: false) }
    }

    private func retainVisibleSelection() {
        let visible = Set(filteredImages.map(\.id))
        store.send(.selectionChanged(store.selection.intersection(visible)), undoable: false)
    }

    private var photoTable: some View {
        let results = resultsByID
        return Table(of: ImageData.self, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("状态") { image in
                PhotoSaveStatus(image: image).frame(maxWidth: .infinity, alignment: .center)
            }.width(min: 40, ideal: 48, max: 160)
            TableColumn("预览") { image in
                PhotoThumbnail(image: image, showsPairedBadge: image.isPairedJPEG)
                    .frame(width: 60, height: 46).padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .center)
            }.width(min: 68, ideal: 76, max: 220)
            TableColumn("文件名", value: \.name) { image in
                Text(image.name).lineLimit(1).truncationMode(.middle).help(image.fullPath)
                    .foregroundStyle(image.updatable ? .primary : .secondary)
                    .contextMenu {
                        ContextMenuView(targets: [image.id], inspectorPresented: $inspectorPresented,
                                        openDetail: openDetail,
                                        showBatchActions: { batchActionsPresented = true },
                                        remove: { pendingRemoval = [image.id] },
                                        clearLocations: { pendingClear = [image.id] })
                    }
            }.width(min: 140, ideal: 220, max: 1000)
            TableColumn("拍摄时间", value: \.metadata.timestamp) { image in
                Text(image.metadata.timestamp.isEmpty ? "—" : image.metadata.timestamp).monospacedDigit()
                    .foregroundStyle(image.updatable && image.metadata.dateTimeCreated != image.original?.dateTimeCreated
                                     ? Color.orange : Color.primary)
            }.width(min: 155, ideal: 170, max: 500)
            TableColumn("定位") { image in
                VStack(alignment: .leading, spacing: 3) {
                    if let location = image.metadata.location {
                        Text("纬 \(coordToString(for: location.latitude, ref: Coords.latRef, format: coordFormat))")
                        Text("经 \(coordToString(for: location.longitude, ref: Coords.lonRef, format: coordFormat))")
                    } else { Text("无定位") }
                }.monospacedDigit().font(.caption)
                    .foregroundStyle(image.hasPendingLocationChanges ? Color.orange
                                     : image.metadata.location == nil ? Color.secondary : Color.primary)
            }.width(min: 130, ideal: 160, max: 400)
            TableColumn("上次轨迹匹配") { image in
                if let result = results[image.id] {
                    Text(result.listStatus).help(result.reason)
                        .foregroundStyle(result.status == .matched ? Color.green : Color.secondary)
                } else { Text("—").foregroundStyle(.secondary) }
            }.width(min: 100, ideal: 130, max: 350)
        } rows: {
            ForEach(filteredImages) { TableRow($0) }
        }
        .background(IndependentTableColumns())
        .background(SubtleScrollbars())
        .contextMenu(forSelectionType: ImageData.ID.self) { ids in
            ContextMenuView(targets: ids, inspectorPresented: $inspectorPresented,
                            openDetail: openDetail, showBatchActions: { batchActionsPresented = true },
                            remove: { pendingRemoval = ids }, clearLocations: { pendingClear = ids })
        } primaryAction: { ids in
            guard let id = ids.first else { return }
            store.send(.selectionChanged(ids), undoable: false)
            store.send(.mostSelectedChanged(id), undoable: false)
            openDetail()
        }
        .alert("从列表移除照片？", isPresented: Binding(get: { !pendingRemoval.isEmpty }, set: {
            if !$0 { pendingRemoval = [] }
        })) {
            Button("取消", role: .cancel) { pendingRemoval = [] }
            Button("从列表移除", role: .destructive) {
                store.send(.removeImages(pendingRemoval), description: "从列表移除照片")
                pendingRemoval = []
            }
        } message: {
            Text("不会删除或修改磁盘原文件。选中照片及其配对 RAW 会一起移出列表；未保存的修改将从当前列表移除，可撤销恢复。")
        }
        .alert("清除照片定位？", isPresented: Binding(get: { !pendingClear.isEmpty }, set: {
            if !$0 { pendingClear = [] }
        })) {
            Button("取消", role: .cancel) { pendingClear = [] }
            Button("清除定位", role: .destructive) {
                store.send(.selectionChanged(pendingClear), undoable: false)
                store.send(.deleteRequest, description: "清除照片定位")
                pendingClear = []
            }
        } message: {
            Text("保留照片和列表项目，清除这些照片的坐标及相关地点信息。配对 RAW 同步修改，点击保存后才写入原文件；可撤销。")
        }
        .overlay {
            if store.imageData.isEmpty {
                ContentUnavailableView("导入照片，开始定位", systemImage: "photo.on.rectangle",
                                       description: Text("点击右上角导入照片，或将照片拖入窗口。"))
            } else if filteredImages.isEmpty {
                ContentUnavailableView.search(text: store.searchText)
            }
        }
    }
}

extension ImageTableView {
    static let imageTableConfigKey = "ImageTableConfig"
    static let hideInvalidImagesKey = "HideInvalidImages"
}
