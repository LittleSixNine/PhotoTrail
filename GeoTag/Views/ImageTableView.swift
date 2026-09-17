import Coords
import ImageData
import SwiftUI
import UDF

struct ImageTableView: View {
    @Environment(Store<GeoTagState, GeoTagEvent>.self) var store
    @AppStorage(Self.hideInvalidImagesKey) var hideInvalidImages = false
    @AppStorage(Coords.coordFormatKey) private var coordFormat: CoordFormat = .deg
    @State private var filter: PhotoListFilter = .all
    @State private var selection: Set<ImageData.ID> = []
    @State private var sortOrder = [KeyPathComparator(\ImageData.name)]
    @FocusState private var searchFocused: Bool
    @Binding var inspectorPresented: Bool
    var openDetail: () -> Void = {}

    private var searchableImages: [ImageData] {
        store.visibleImages.filter {
            (!hideInvalidImages || $0.updatable) && (store.searchText.isEmpty || $0.name.fuzzy(store.searchText))
        }
    }

    private var filteredImages: [ImageData] { searchableImages.filter { filter.includes($0) } }

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
        Table(of: ImageData.self, selection: $selection, sortOrder: $sortOrder) {
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
            }.width(min: 140, ideal: 220, max: 1000)
            TableColumn("拍摄时间", value: \.metadata.timestamp) { image in
                Text(image.metadata.timestamp.isEmpty ? "—" : image.metadata.timestamp).monospacedDigit()
            }.width(min: 155, ideal: 170, max: 500)
            TableColumn("纬度", sortUsing: KeyPathComparator(\ImageData.metadata.location?.latitude)) { image in
                Text(image.metadata.location.map { coordToString(for: $0.latitude, ref: Coords.latRef, format: coordFormat) } ?? "—").monospacedDigit()
            }.width(min: 90, ideal: 110, max: 400)
            TableColumn("经度", sortUsing: KeyPathComparator(\ImageData.metadata.location?.longitude)) { image in
                Text(image.metadata.location.map { coordToString(for: $0.longitude, ref: Coords.lonRef, format: coordFormat) } ?? "—").monospacedDigit()
            }.width(min: 95, ideal: 115, max: 400)
        } rows: {
            ForEach(filteredImages) { TableRow($0) }
        }
        .background(IndependentTableColumns())
        .contextMenu(forSelectionType: ImageData.ID.self) { ids in
            ContextMenuView(context: ids.first, inspectorPresented: $inspectorPresented)
        } primaryAction: { ids in
            guard let id = ids.first else { return }
            store.send(.selectionChanged(ids), undoable: false)
            store.send(.mostSelectedChanged(id), undoable: false)
            openDetail()
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
