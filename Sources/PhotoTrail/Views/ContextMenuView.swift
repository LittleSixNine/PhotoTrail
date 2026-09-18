import ImageData
import SwiftUI
import UDF

struct ContextMenuView: View {
    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) var store
    @AppStorage(SettingsView.extendedTimeKey) var extendedTime = 120.0
    let targets: Set<ImageData.ID>
    @Binding var inspectorPresented: Bool
    var openDetail: () -> Void
    var showBatchActions: () -> Void
    var remove: () -> Void
    var clearLocations: () -> Void

    private var images: [ImageData] { store.imageData.filter { targets.contains($0.id) } }
    private var editable: Bool {
        !images.isEmpty && !store.saveInProgress && images.allSatisfy(\.updatable)
    }
    private var source: ImageData? { images.count == 1 ? images.first : nil }
    private var localURLs: [URL] {
        images.compactMap {
            switch $0.metadata.source {
            case .image(let url), .xmp(let url): url
            case .photos, .copy: nil
            }
        }
    }

    var body: some View {
        Button("在地图定位页查看") { selectTargets(); openDetail() }
            .disabled(images.isEmpty)
        Button("查看与编辑照片信息…") { selectTargets(); inspectorPresented = true }
            .disabled(images.count != 1)
        Divider()
        Button("复制此照片的定位", systemImage: "document.on.document") {
            guard let source else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(source.stringRepresentation, forType: .string)
        }.disabled(source?.metadata.location == nil)
        Button("粘贴定位到这 \(images.count) 张照片", systemImage: "document.on.clipboard") {
            selectTargets()
            store.send(.pasteRequest, description: "粘贴定位") {
                guard let id = store.mostSelected else { return }
                let selected = store.selection
                Task {
                    if let address = await ReverseLocationFinder.reverseGeocode(store: store, id: id) {
                        store.send(.addressChanged(selected, address), undoable: false)
                    }
                }
            }
        }.disabled(!editable || NSPasteboard.general.string(forType: .string)
            .flatMap { ImageData.decodeStringRep(value: $0) } == nil)
        Button("预览这 \(images.count) 张照片的轨迹匹配") {
            selectTargets()
            showBatchActions()
            LocationHelper.locationFromTrack(store, extendedTime: extendedTime)
        }.disabled(!editable || store.gpxTracks.isEmpty)
        Divider()
        Button("在访达中显示原文件") {
            NSWorkspace.shared.activateFileViewerSelecting(localURLs)
        }.disabled(localURLs.isEmpty)
        Button("从列表移除这 \(images.count) 张照片…", systemImage: "minus.circle") { remove() }
            .disabled(store.saveInProgress || images.isEmpty)
        Button("清除这 \(images.count) 张照片的定位…", systemImage: "mappin.slash") { clearLocations() }
            .disabled(!editable || images.allSatisfy { $0.metadata.location == nil })
    }

    private func selectTargets() {
        store.send(.selectionChanged(targets), undoable: false)
    }
}
