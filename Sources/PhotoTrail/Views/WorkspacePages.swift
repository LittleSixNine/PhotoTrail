import AppKit
import Coords
import ImageData
import SwiftUI
import UDF
import UniformTypeIdentifiers

extension ImageData {
    var hasPendingChanges: Bool { updatable && metadata != original }
    var hasPendingLocationChanges: Bool { updatable && metadata.location != original?.location }
    var importedWithLocation: Bool {
        metadata.location != nil && (original?.location != nil || !updatable)
    }
}

enum PhotoListFilter: String, CaseIterable {
    case all = "全部", unlocated = "无定位", located = "有定位", pending = "待保存"

    func includes(_ image: ImageData) -> Bool {
        switch self {
        case .all: true
        case .unlocated: image.metadata.location == nil
        case .located: image.metadata.location != nil
        case .pending: image.hasPendingChanges
        }
    }
}

private enum FilmstripPopover { case filter, sort }

enum PhotoStripSort: String, CaseIterable {
    case importOrder = "导入顺序"
    case filename = "文件名"
    case capturedAt = "拍摄时间"
}

@MainActor private func importPhotoTrack(_ url: URL, store: Store<PhotoTrailState, PhotoTrailEvent>,
                              workspace: LocationWorkspace) {
    workspace.tracks.markPhotoGenerated(url)
    store.send(.openFiles([url]), undoable: false) {
        if let urls = store.uniqueURLs {
            OpenHelper.open(store, urls: urls, description: "导入照片轨迹", spinnerEnabled: nil)
            store.send(.clearUniqueURLs, undoable: false)
        }
    }
}

private struct HorizontalFilmstripWheelMonitor: NSViewRepresentable {
    func makeNSView(context: Context) -> MonitorView { MonitorView() }
    func updateNSView(_ view: MonitorView, context: Context) {}
    static func dismantleNSView(_ view: MonitorView, coordinator: Void) { view.stop() }

    final class MonitorView: NSView {
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window, event.window === window,
                      bounds.contains(convert(event.locationInWindow, from: nil)),
                      abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX),
                      let scroll = horizontalScroll(in: window.contentView, at: event.locationInWindow)
                else { return event }
                let clip = scroll.contentView
                let maximum = max(0, (scroll.documentView?.bounds.width ?? 0) - clip.bounds.width)
                let distance = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 32)
                clip.scroll(to: CGPoint(x: min(maximum, max(0, clip.bounds.minX - distance)), y: clip.bounds.minY))
                scroll.reflectScrolledClipView(clip)
                return nil
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func horizontalScroll(in view: NSView?, at point: NSPoint) -> NSScrollView? {
            guard let view, view.bounds.contains(view.convert(point, from: nil)) else { return nil }
            for child in view.subviews.reversed() {
                if let found = horizontalScroll(in: child, at: point) { return found }
            }
            guard let scroll = view as? NSScrollView,
                  (scroll.documentView?.bounds.width ?? 0) > scroll.contentView.bounds.width else { return nil }
            return scroll
        }
    }
}

struct PhotoSaveStatus: View {
    let image: ImageData
    var body: some View {
        Image(systemName: image.hasPendingChanges ? "square.and.arrow.down" : "checkmark.circle.fill")
            .font(.system(size: 18))
            .foregroundStyle(image.hasPendingChanges ? Color.orange : Color.green)
            .help(image.hasPendingChanges ? "有修改，待保存" : "已保存")
            .accessibilityLabel(image.hasPendingChanges ? "待保存" : "已保存")
    }
}

struct PhotoThumbnail: View {
    let image: ImageData
    var showsPairedBadge = false
    var fill = false
    var maxDimension = 1024.0
    @State private var thumbnail: Image?
    @Environment(\.displayScale) private var scale

    var body: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)
            if let thumbnail {
                if fill { thumbnail.resizable().scaledToFill() }
                else { thumbnail.resizable().scaledToFit() }
            } else {
                Image(systemName: "photo").foregroundStyle(.tertiary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .clipped()
        .overlay(alignment: .bottomTrailing) {
            if showsPairedBadge {
                Text("JPG + RAW")
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 3))
                    .padding(3)
                    .accessibilityLabel("JPG 和 RAW 双文件")
            }
        }
        .task(id: "\(image.id)-\(Int(maxDimension))") {
            let loaded = await PhotoThumbnailCache.shared.image(
                for: image, scale: scale, maxDimension: maxDimension)
            guard !Task.isCancelled else { return }
            thumbnail = loaded
        }
    }
}

@MainActor
private final class PhotoThumbnailCache {
    static let shared = PhotoThumbnailCache()
    private struct Key: Hashable { let id: ImageData.ID; let size: Int }
    private var images: [Key: Image] = [:]
    private var order: [Key] = []
    private let limit = 384

    func image(for image: ImageData, scale: CGFloat, maxDimension: Double) async -> Image {
        if let thumbnail = image.thumbnail { return thumbnail }
        let key = Key(id: image.id, size: Int(maxDimension))
        if let cached = images[key] { return cached }
        let loaded = await image.makeThumbnail(scale: scale, maxDimension: maxDimension)
        images[key] = loaded
        order.append(key)
        if order.count > limit, let oldest = order.first {
            order.removeFirst()
            images.removeValue(forKey: oldest)
        }
        return loaded
    }
}

struct WorkspaceSaveButton: View {
    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) private var store
    @State private var showCompletedRing = false
    var fillsWidth = false
    var body: some View {
        Button {
            SaveHelper.requestSave(store)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "square.and.arrow.down")
                    .frame(width: fillsWidth ? 16 : nil)
                Text(store.saveInProgress
                     ? "保存中 \(store.saveCompleted)/\(store.saveTotal)"
                     : "保存所有修改")
                    .monospacedDigit()
                    .frame(minWidth: fillsWidth ? nil : 110, alignment: .leading)
            }
            .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
        }
        .buttonStyle(WorkspaceToolbarButtonStyle(prominent: !fillsWidth, outlined: fillsWidth))
        .disabled(store.saveInProgress || !store.unsavedChanges)
        .overlay {
            if store.saveInProgress || showCompletedRing {
                ZStack {
                    Capsule().stroke(Color.blue.opacity(0.25), lineWidth: 2)
                    Capsule()
                        .trim(from: 0, to: store.saveTotal == 0 ? 0
                              : CGFloat(store.saveCompleted) / CGFloat(store.saveTotal))
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .animation(.linear(duration: 0.35), value: store.saveCompleted)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .onChange(of: store.saveInProgress) { _, saving in
            if saving {
                showCompletedRing = false
            } else if !store.unsavedChanges && store.saveTotal > 0
                        && store.saveCompleted == store.saveTotal {
                showCompletedRing = true
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    showCompletedRing = false
                }
            }
        }
        .help("保存全部待保存修改")
    }
}

struct TrackMatchSummary: View {
    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) private var store

    var body: some View {
        if !store.trackMatches.isEmpty {
            let matched = store.trackMatches.filter { $0.status == .matched }.count
            let review = store.trackMatches.filter { $0.status == .ambiguous }.count
            let skipped = store.trackMatches.count - matched - review
            VStack(alignment: .leading, spacing: 6) {
                Text("匹配预览：可应用 \(matched) · 需检查 \(review) · 跳过 \(skipped)")
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("查看逐张结果") {
                    ForEach(store.trackMatches.prefix(10)) { result in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store[result.id].name).font(.caption.weight(.medium)).lineLimit(1)
                            Text(detail(result)).font(.caption2).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }.padding(.vertical, 2)
                    }
                    if store.trackMatches.count > 10 {
                        Text("另有 \(store.trackMatches.count - 10) 张")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }.font(.caption)
                Button("应用 \(matched) 个可靠匹配") {
                    store.send(.applyTrackMatches, description: "应用轨迹匹配")
                }.disabled(matched == 0 || store.saveInProgress)
            }
        }
    }

    private func detail(_ result: LocationHelper.LocationById) -> String {
        let status: String
        switch result.status {
        case .matched: status = result.method == .recorded ? "精确记录点" : "线性插值"
        case .ambiguous: status = "需检查"
        case .unmatched: status = "未匹配"
        case .missingTime: status = "缺少时间"
        case .alreadyLocated: status = "已有定位"
        }
        let source = result.sourceURL.map { " · \($0.lastPathComponent)" } ?? ""
        return "\(status)\(source) · \(result.reason)"
    }
}

struct PhotoActionSidebar: View {
    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) private var store
    @Environment(LocationWorkspace.self) private var workspace
    @AppStorage(SettingsView.extendedTimeKey) private var extendedTime = 120.0
    @State private var timePresented = false
    @State private var photoGPXPresented = false
    @State private var overwriteExisting = false
    @State private var trackOptionsPresented = false
    @State private var gpxError: String?
    @State private var choosingCopyDestination = false
    @State private var copyExportInProgress = false
    @State private var copyExportNotice: String?

    private var editable: Bool {
        !store.selection.isEmpty && !store.saveInProgress && store.selection.allSatisfy { store[$0].updatable }
    }

    var body: some View {
        VStack(spacing: 0) {
        ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            Text("批量操作").font(.title3.bold())
            Text("已选择 \(store.selection.count) 张照片").font(.subheadline).foregroundStyle(.secondary)
            Menu {
                if workspace.favorites.isEmpty { Text("暂无收藏，请在详情页添加") }
                ForEach(workspace.favorites) { favorite in
                    Button(favorite.name) {
                        store.send(.confirmedWGS84Location(Coords(latitude: favorite.coordinate.latitude,
                                                                 longitude: favorite.coordinate.longitude)),
                                   description: "应用收藏地点")
                    }
                }
            } label: { actionLabel("应用收藏", "star") }
            .disabled(!editable)
            DisclosureGroup("轨迹匹配", isExpanded: $trackOptionsPresented) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("匹配范围：全部已导入轨迹（\(store.gpxTracks.count) 条）")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("相机时区：\(store.timeZone.identifier)")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("轨迹端点容差：\(Int(extendedTime)) 秒，可在设置中调整")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("覆盖已有定位", isOn: $overwriteExisting).font(.caption)
                    Button("预览所选照片的匹配结果") {
                        LocationHelper.locationFromTrack(store, extendedTime: extendedTime,
                                                         overwriteExisting: overwriteExisting)
                    }.disabled(!editable || store.gpxTracks.isEmpty)
                    TrackMatchSummary()
                }.padding(.top, 8)
            }
            Button { timePresented = true } label: { actionLabel("调整拍摄时间", "clock") }
                .disabled(!editable)
            Button {
                photoGPXPresented = true
            } label: { actionLabel("生成照片 GPX", "point.topleft.down.to.point.bottomright.curvepath") }
            .disabled(!hasGPXPoints)
            Button { choosingCopyDestination = true } label: {
                actionLabel("导出定位副本", "square.and.arrow.up.on.square")
            }.disabled(!hasCopyCandidates || copyExportInProgress)
            if copyExportInProgress { ProgressView("正在写入并回读验证…").controlSize(.small) }
            if let copyExportNotice {
                Text(copyExportNotice).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button { store.send(.deleteRequest, description: "清除定位") } label: {
                actionLabel("清除定位", "mappin.slash")
            }.disabled(!editable || store.selection.allSatisfy { store[$0].metadata.location == nil })
        }
        .padding(12)
        }.background(SubtleScrollbars())
        VStack(spacing: 10) {
            Divider()
            WorkspaceSaveButton(fillsWidth: true)
            Button { store.undo() } label: { actionLabel("撤销", "arrow.uturn.backward") }
                .disabled(!store.canUndo || store.saveInProgress || store.textfieldActive)
        }
        .padding(12)
        }
        .buttonStyle(WorkspaceToolbarButtonStyle(outlined: true)).controlSize(.large)
        .frame(width: 200).frame(maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { trackOptionsPresented = !store.trackMatches.isEmpty }
        .onChange(of: store.trackMatches) {
            if !store.trackMatches.isEmpty { trackOptionsPresented = true }
        }
        .sheet(isPresented: $photoGPXPresented) {
            PhotoGPXOptionsView(timeZone: store.timeZone) { minutes in
                let images = store.imageData.filter { store.selection.contains($0.id) }
                createPhotoTrack(images, minutes: minutes)
            }
        }
        .sheet(isPresented: $timePresented) {
            VStack(alignment: .leading, spacing: 16) {
                Text("调整拍摄时间").font(.title2)
                Text("多选时，将相同的时间差应用到全部选中照片。").font(.callout)
                DateTimeSectionView(image: store[store.mostSelected])
                HStack { Spacer(); Button("完成") { timePresented = false } }
            }.padding(24).frame(width: 460)
                .onDisappear { store.send(.textfieldFocusChanged(false), undoable: false) }
        }
        .alert("生成照片 GPX 失败", isPresented: Binding(get: { gpxError != nil }, set: {
            if !$0 { gpxError = nil }
        })) { Button("好") { gpxError = nil } } message: { Text(gpxError ?? "") }
        .fileImporter(isPresented: $choosingCopyDestination,
                      allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let destination = urls.first else { return }
            let images = store.imageData.filter { store.selection.contains($0.id) }
            copyExportInProgress = true
            copyExportNotice = nil
            Task {
                let scoped = destination.startAccessingSecurityScopedResource()
                defer { if scoped { destination.stopAccessingSecurityScopedResource() } }
                do {
                    let report = try await PhotoCopyExporter.export(
                        images: images, destination: destination, timeZone: store.timeZone)
                    copyExportNotice = "导出完成：成功 \(report.written)，跳过 \(report.skipped)，失败 \(report.failed)。报告保存在输出目录。"
                } catch {
                    copyExportNotice = "导出失败：\(error.localizedDescription)"
                }
                copyExportInProgress = false
            }
        }
    }

    private func createPhotoTrack(_ images: [ImageData], minutes: Double) {
        do {
            let url = try PhotoGPXDocument(images: images, timeZone: store.timeZone, segmentGap: minutes * 60)
                .saveToCache(timeZone: store.timeZone)
            importPhotoTrack(url, store: store, workspace: workspace)
        } catch { gpxError = error.localizedDescription }
    }

    private var hasGPXPoints: Bool {
        store.selection.contains { id in
            let metadata = store[id].metadata
            return metadata.location != nil && metadata.canDisplayAsWGS84
                && metadata.parsedDate(timeZone: store.timeZone) != nil
        }
    }

    private var hasCopyCandidates: Bool {
        store.selection.contains { id in
            let image = store[id]
            guard image.metadata.location != nil, image.metadata.canDisplayAsWGS84 else { return false }
            switch image.metadata.source {
            case .image, .xmp: return true
            case .photos, .copy: return false
            }
        }
    }

    private func actionLabel(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).frame(width: 16)
            Text(title)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 5)
    }
}

struct PhotoDetailPage: View {
    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) private var store
    @Environment(LocationWorkspace.self) private var workspace

    @AppStorage("PhotoTrailDetailWidthRatio") private var leftRatio = 0.26
    @AppStorage("PhotoTrailFilmstripHeightRatio") private var stripRatio = 0.13
    @AppStorage("PhotoTrailFilmstripSort") private var stripSort = PhotoStripSort.capturedAt.rawValue
    @AppStorage("PhotoTrailFilmstripAscending") private var stripAscending = true
    @SceneStorage("PhotoTrailFilmstripFilter") private var stripFilter: PhotoListFilter = .all
    @State private var filmstripPopover: FilmstripPopover?
    @AppStorage(SettingsView.extendedTimeKey) private var extendedTime = 120.0
    @State private var dragStart: Double?
    @State private var confirmClearLocations = false
    @State private var gpxError: String?
    @State private var photoGPXPresented = false
    @State private var selectionAnchor: ImageData.ID?
    @State private var choosingCopyDestination = false
    @State private var copyExportNotice: String?
    @State private var copyExportInProgress = false

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ScrollView {
                      VStack(spacing: 0) {
                        GeometryReader { geometry in
                            ImageView().frame(width: geometry.size.width, height: geometry.size.height)
                        }.aspectRatio(1.5, contentMode: .fit)
                        if let id = store.mostSelected {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(store[id].name).font(.headline).lineLimit(1).truncationMode(.middle)
                                Text(store[id].metadata.timestamp).font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14).padding(.bottom, 12)
                        }
                        Divider()
                        LocationPanel()
                      }
                    }.background(SubtleScrollbars()).frame(width: max(260, min(geometry.size.width * leftRatio, geometry.size.width - 420)))
                        .background(Color(nsColor: .windowBackgroundColor))
                    Divider().frame(width: 6).contentShape(Rectangle())
                        .onHover { if $0 { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                        .gesture(DragGesture().onChanged { value in
                            if dragStart == nil { dragStart = leftRatio }
                            leftRatio = min(0.5, max(0.18, (dragStart ?? leftRatio)
                                + value.translation.width / geometry.size.width))
                        }.onEnded { _ in dragStart = nil })
                    MapWithSearchView().frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                }.frame(width: geometry.size.width,
                        height: max(340, geometry.size.height - max(132, geometry.size.height * stripRatio) - 6))
                Divider().frame(height: 6).contentShape(Rectangle())
                    .onHover { if $0 { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
                    .gesture(DragGesture().onChanged { value in
                        if dragStart == nil { dragStart = stripRatio }
                        stripRatio = min(0.3, max(0.10, (dragStart ?? stripRatio)
                            - value.translation.height / geometry.size.height))
                    }.onEnded { _ in dragStart = nil })
                GeometryReader { geometry in
                    ScrollViewReader { proxy in
                        HStack(spacing: -42) {
                            ScrollView(.horizontal) {
                                LazyHStack(spacing: 12) {
                                    ForEach(sortedImages) { image in
                                    Button {
                                        select(image.id)
                                    } label: {
                                        VStack(spacing: 5) {
                                            PhotoThumbnail(image: image, showsPairedBadge: image.isPairedJPEG)
                                                .frame(width: max(90, (geometry.size.height - 48) * 1.5),
                                                       height: max(60, geometry.size.height - 48))
                                                .overlay {
                                                    if image.hasPendingLocationChanges
                                                        || store.locationSavedPhotoIDs.contains(image.id) {
                                                        PhotoSaveStatus(image: image)
                                                            .padding(9)
                                                            .background(.regularMaterial, in: Circle())
                                                            .allowsHitTesting(false)
                                                    }
                                                }
                                                .overlay(RoundedRectangle(cornerRadius: 5)
                                                    .stroke(store.selection.contains(image.id)
                                                            ? Color.accentColor : .clear,
                                                            lineWidth: 3))
                                                .overlay(alignment: .top) {
                                                    if image.importedWithLocation {
                                                        Circle().fill(Color.secondary)
                                                            .frame(width: 8, height: 8)
                                                            .overlay(Circle().stroke(.white, lineWidth: 1.5))
                                                            .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                                                            .offset(y: -5)
                                                            .help("导入时已包含定位信息")
                                                    }
                                                }
                                            Text(image.name).font(.caption).lineLimit(1)
                                                .truncationMode(.middle)
                                                .frame(width: max(90, (geometry.size.height - 48) * 1.5))
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu { photoMenu(image) }
                                    .id(image.id)
                                    }
                                }.padding(14).padding(.trailing, 42)
                            }.background(HorizontalFilmstripWheelMonitor())
                                .background(SubtleScrollbars())
                            VStack(spacing: 0) {
                                Spacer(minLength: 0)
                                filmstripFilterMenu
                                Spacer(minLength: 0)
                                filmstripSortMenu
                                Spacer(minLength: 0)
                                Button {
                                    if let id = currentVisiblePhotoID { proxy.scrollTo(id, anchor: .center) }
                                } label: {
                                    filmstripControl("回到当前", icon: "scope", menu: false)
                                }
                                .buttonStyle(.plain)
                                .disabled(currentVisiblePhotoID == nil)
                                .help(store.mostSelected == nil ? "请先选择照片"
                                      : currentVisiblePhotoID == nil ? "当前照片不在筛选结果中"
                                      : "将当前照片滚动到照片条中央")
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 2).padding(.vertical, 6)
                            .frame(width: 124)
                            .background(alignment: .trailing) {
                                // Button leading edge is 2 points inside the control area.
                                // The 80-point fade extends 40 points on either side of it.
                                HStack(spacing: 0) {
                                    LinearGradient(
                                        colors: [Color(nsColor: .windowBackgroundColor).opacity(0),
                                                 Color(nsColor: .windowBackgroundColor)],
                                        startPoint: .leading, endPoint: .trailing
                                    ).frame(width: 80)
                                    Color(nsColor: .windowBackgroundColor).frame(width: 82)
                                }
                                .frame(width: 162)
                                .allowsHitTesting(false)
                            }
                        }
                        .frame(height: geometry.size.height).background(Color(nsColor: .windowBackgroundColor))
                    }
                }.frame(height: max(132, geometry.size.height * stripRatio))
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }
        .sheet(isPresented: $photoGPXPresented) {
            PhotoGPXOptionsView(timeZone: store.timeZone) { minutes in
                prepareGPX(minutes: minutes)
            }
        }
        .confirmationDialog("清除所选照片定位？", isPresented: $confirmClearLocations) {
            Button("清除 \(store.selection.count) 张照片的定位", role: .destructive) {
                store.send(.deleteRequest, description: "清除所选照片定位")
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("照片将进入待保存状态；保存前仍可撤销。")
        }
        .alert("生成照片 GPX 失败", isPresented: Binding(get: { gpxError != nil }, set: {
            if !$0 { gpxError = nil }
        })) { Button("好") { gpxError = nil } } message: { Text(gpxError ?? "") }
        .fileImporter(isPresented: $choosingCopyDestination,
                      allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let destination = urls.first else { return }
            let images = selectedImages
            copyExportInProgress = true
            Task {
                let scoped = destination.startAccessingSecurityScopedResource()
                defer { if scoped { destination.stopAccessingSecurityScopedResource() } }
                do {
                    let report = try await PhotoCopyExporter.export(
                        images: images, destination: destination, timeZone: store.timeZone)
                    copyExportNotice = "导出完成：成功 \(report.written)，跳过 \(report.skipped)，失败 \(report.failed)。"
                } catch { copyExportNotice = "导出失败：\(error.localizedDescription)" }
                copyExportInProgress = false
            }
        }
        .alert("导出定位副本", isPresented: Binding(get: { copyExportNotice != nil }, set: {
            if !$0 { copyExportNotice = nil }
        })) { Button("好") { copyExportNotice = nil } } message: { Text(copyExportNotice ?? "") }
    }
}

private extension PhotoDetailPage {
    var selectedImages: [ImageData] {
        store.imageData.filter { store.selection.contains($0.id) }
    }

    var sortedImages: [ImageData] {
        let images = store.visibleImages.filter { stripFilter.includes($0) }
        let mode = PhotoStripSort(rawValue: stripSort) ?? .capturedAt
        if mode == .capturedAt {
            let dated = images.map { ($0, $0.metadata.parsedDate(timeZone: store.timeZone)) }
            return dated.sorted { left, right in
                let ordered: Bool
                switch (left.1, right.1) {
                case let (lhs?, rhs?): ordered = lhs == rhs ? left.0.id < right.0.id : lhs < rhs
                case (_?, nil): ordered = true
                case (nil, _?): ordered = false
                case (nil, nil): ordered = left.0.id < right.0.id
                }
                return stripAscending ? ordered : !ordered && left.0.id != right.0.id
            }.map(\.0)
        }
        return images.sorted { left, right in
            let ordered: Bool
            switch mode {
            case .importOrder:
                ordered = left.id < right.id
            case .filename:
                let comparison = left.name.localizedStandardCompare(right.name)
                ordered = comparison == .orderedSame ? left.id < right.id : comparison == .orderedAscending
            case .capturedAt: ordered = false
            }
            return stripAscending ? ordered : !ordered && left.id != right.id
        }
    }

    var currentVisiblePhotoID: ImageData.ID? {
        guard let id = store.mostSelected,
              store.visibleImages.contains(where: { $0.id == id && stripFilter.includes($0) }) else { return nil }
        return id
    }

    func popoverPresented(_ kind: FilmstripPopover) -> Binding<Bool> {
        Binding(get: { filmstripPopover == kind }, set: { showing in
            if showing { filmstripPopover = kind }
            else if filmstripPopover == kind { filmstripPopover = nil }
        })
    }

    var filmstripFilterMenu: some View {
        Button { filmstripPopover = filmstripPopover == .filter ? nil : .filter } label: {
            filmstripControl(stripFilter.rawValue, icon: "line.3.horizontal.decrease", menu: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("筛选：\(stripFilter.rawValue)")
        .help("筛选照片：\(stripFilter.rawValue)")
        .popover(isPresented: popoverPresented(.filter), attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("筛选照片").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
                ForEach(PhotoListFilter.allCases, id: \.self) { option in
                    filmstripOption(option.rawValue, selected: stripFilter == option) {
                        stripFilter = option
                        filmstripPopover = nil
                    }
                }
            }
            .padding(8).frame(width: 160)
            .onExitCommand { filmstripPopover = nil }
        }
    }

    var filmstripSortMenu: some View {
        Button { filmstripPopover = filmstripPopover == .sort ? nil : .sort } label: {
            filmstripControl((PhotoStripSort(rawValue: stripSort) ?? .capturedAt).rawValue,
                             icon: "arrow.up.arrow.down", menu: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("排序：\((PhotoStripSort(rawValue: stripSort) ?? .capturedAt).rawValue)")
        .help(stripAscending ? "排序：当前按升序排列" : "排序：当前按降序排列")
        .popover(isPresented: popoverPresented(.sort), attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("排序规则").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
                ForEach(PhotoStripSort.allCases, id: \.rawValue) { option in
                    filmstripOption(option.rawValue, selected: stripSort == option.rawValue) {
                        stripSort = option.rawValue
                    }
                }
                Divider().padding(.vertical, 5)
                Text("排列方向").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
                filmstripOption("升序", selected: stripAscending) { stripAscending = true }
                filmstripOption("降序", selected: !stripAscending) { stripAscending = false }
            }
            .padding(8).frame(width: 160)
            .onExitCommand { filmstripPopover = nil }
        }
    }

    func filmstripOption(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark").frame(width: 14).opacity(selected ? 1 : 0)
                Text(title)
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? Color.blue : Color.secondary)
            .padding(.horizontal, 8).frame(height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    func filmstripControl(_ title: String, icon: String, menu: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).frame(width: 10).foregroundStyle(.secondary)
            Text(title).lineLimit(1).fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
            if menu {
                Image(systemName: "chevron.up").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10).frame(width: 120, height: 32)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.9),
                    in: RoundedRectangle(cornerRadius: 7))
        .contentShape(RoundedRectangle(cornerRadius: 7))
    }

    func select(_ id: ImageData.ID) {
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.shift) {
            let images = sortedImages
            let anchor = selectionAnchor ?? store.mostSelected ?? id
            guard let start = images.firstIndex(where: { $0.id == anchor }),
                  let end = images.firstIndex(where: { $0.id == id }) else { return }
            let range = Set(images[min(start, end)...max(start, end)].map(\.id))
            let selection = modifiers.contains(.command) ? store.selection.union(range) : range
            store.send(.selectionChangedTo(selection, id), undoable: false)
            selectionAnchor = anchor
        } else if modifiers.contains(.command) {
            var selection = store.selection
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
            store.send(.selectionChangedTo(selection, selection.contains(id) ? id : nil), undoable: false)
            selectionAnchor = id
        } else {
            store.send(.selectionChanged([id]), undoable: false)
            selectionAnchor = id
        }
    }

    @ViewBuilder func photoMenu(_ source: ImageData) -> some View {
        Button("在地图中显示", systemImage: "map") { workspace.focusPhoto?(source.id) }
            .disabled(source.metadata.location == nil)
        Divider()
        Button("复制定位信息", systemImage: "document.on.document") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(source.stringRepresentation, forType: .string)
        }.disabled(source.metadata.location == nil)
        Button("粘贴定位到所选照片", systemImage: "document.on.clipboard") { pasteLocation() }
            .disabled(!editableSelection || pastedLocation == nil)
        Button("将此照片的位置应用到所选的 \(store.selection.count) 张照片",
               systemImage: "arrow.trianglehead.branch") { applyLocation(from: source) }
            .disabled(!editableSelection || source.metadata.location == nil)
        Divider()
        Button("使用 GPX 为所选照片匹配位置", systemImage: "point.3.connected.trianglepath.dotted") {
            LocationHelper.locationFromTrack(store, extendedTime: extendedTime)
        }.disabled(!editableSelection || store.gpxTracks.isEmpty)
        Button("从所选照片新建 GPX 轨迹", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
            photoGPXPresented = true
        }.disabled(!hasGPXPoints)
        Button("导出所选照片的定位副本", systemImage: "square.and.arrow.up.on.square") {
            choosingCopyDestination = true
        }.disabled(!hasCopyCandidates || copyExportInProgress)
        Divider()
        Button("清除所选照片定位…", systemImage: "mappin.slash", role: .destructive) {
            confirmClearLocations = true
        }.disabled(!editableSelection || selectedImages.allSatisfy { $0.metadata.location == nil })
        Button("在访达中显示", systemImage: "folder") { showInFinder() }
            .disabled(!hasLocalFiles)
    }

    var editableSelection: Bool {
        !store.selection.isEmpty && !store.saveInProgress
            && store.selection.allSatisfy { store[$0].updatable }
    }

    var pastedLocation: (Coords, Double?)? {
        NSPasteboard.general.string(forType: .string).flatMap(ImageData.decodeStringRep)
    }

    func pasteLocation() {
        guard let (coordinate, elevation) = pastedLocation else { return }
        apply(coordinate, elevation: elevation, description: "粘贴定位到所选照片")
    }

    func applyLocation(from source: ImageData) {
        guard let coordinate = source.metadata.location else { return }
        apply(coordinate, elevation: source.metadata.elevation, description: "应用照片定位到所选照片")
    }

    func apply(_ coordinate: Coords, elevation: Double?, description: String) {
        let selected = store.selection
        guard let id = selected.first else { return }
        store.send(.locationFromPhoto(coordinate, elevation), description: description) {
            Task {
                if let address = await ReverseLocationFinder.reverseGeocode(store: store, id: id) {
                    store.send(.addressChanged(selected, address), undoable: false)
                }
            }
        }
    }

    var hasGPXPoints: Bool {
        selectedImages.contains { image in
            image.metadata.location != nil && image.metadata.canDisplayAsWGS84
                && image.metadata.parsedDate(timeZone: store.timeZone) != nil
        }
    }

    func prepareGPX(minutes: Double) {
        do {
            let url = try PhotoGPXDocument(images: selectedImages, timeZone: store.timeZone, segmentGap: minutes * 60)
                .saveToCache(timeZone: store.timeZone)
            importPhotoTrack(url, store: store, workspace: workspace)
        } catch { gpxError = error.localizedDescription }
    }

    var hasCopyCandidates: Bool {
        selectedImages.contains { image in
            guard image.metadata.location != nil, image.metadata.canDisplayAsWGS84 else { return false }
            if case .image = image.metadata.source { return true }
            if case .xmp = image.metadata.source { return true }
            return false
        }
    }

    var hasLocalFiles: Bool {
        selectedImages.contains { image in
            if case .image = image.metadata.source { return true }
            if case .xmp = image.metadata.source { return true }
            return false
        }
    }

    func showInFinder() {
        let urls = selectedImages.compactMap { image -> URL? in
            switch image.metadata.source {
            case .image(let url), .xmp(let url): url
            case .photos, .copy: nil
            }
        }
        if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }
}

struct WorkspacePageSwitch: View {
    @Binding var selection: Bool
    var firstTitle = "照片列表"
    var secondTitle = "地图定位"
    var firstIcon = "list.bullet"
    var secondIcon = "photo"
    var optionWidth: CGFloat = 124
    var usesGlass = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if usesGlass {
            track.glassEffect(.clear.interactive(), in: Capsule())
        } else {
            track.background(.quaternary.opacity(0.5), in: Capsule())
        }
    }

    private var track: some View {
        HStack(spacing: 0) {
            option(firstTitle, icon: firstIcon, value: false)
            option(secondTitle, icon: secondIcon, value: true)
        }
        .background(alignment: .leading) {
            Capsule().fill(Color.blue).frame(width: optionWidth, height: 30)
                .offset(x: selection ? optionWidth : 0)
        }
        .padding(3)
        .fixedSize()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: selection)
    }

    private func option(_ title: String, icon: String, value: Bool) -> some View {
        Button { selection = value } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(selection == value ? Color.white : Color.primary)
            .frame(width: optionWidth, height: 30)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selection == value ? .isSelected : [])
    }
}

private struct PhotoGPXOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    let timeZone: TimeZone
    let create: (Double) -> Void
    @State private var minutes = ""

    private var validMinutes: Double? {
        guard let value = Double(minutes.trimmingCharacters(in: .whitespacesAndNewlines)),
              value.isFinite, value > 0, value <= 1_000_000 else { return nil }
        return value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("从照片新建 GPX 轨迹").font(.title2)
            Text("当前批次相机时区：\(timeZone.identifier)")
                .foregroundStyle(.secondary)
            Picker("断段间隔", selection: $minutes) {
                ForEach(["5", "15", "30", "60"], id: \.self) { value in
                    Text("\(value) 分钟").tag(value)
                }
                if !["5", "15", "30", "60"].contains(minutes) {
                    Text("自定义").tag(minutes)
                }
            }
            TextField("自定义分钟数", text: $minutes)
            Text("仅大于此间隔时开始新轨迹段。").font(.footnote).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("创建轨迹") {
                    if let value = validMinutes { create(value); dismiss() }
                }.disabled(validMinutes == nil)
            }
        }
        .padding(24).frame(width: 380)
        .onAppear {
            let value = SettingsPreferences.photoGPXGap / 60
            minutes = value.rounded() == value ? String(Int(value)) : String(value)
        }
    }
}
