import Coords
import GpxTrackLog
import SwiftUI
import UDF
import UniformTypeIdentifiers

struct TrackSidebar: View {
    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) private var store
    @Environment(LocationWorkspace.self) private var workspace
    @AppStorage("PhotoTrailMapProvider") private var provider = "amap"
    @AppStorage(SettingsView.extendedTimeKey) private var extendedTime = 120.0
    @State private var historyExpanded = false
    @State private var tracksExpanded: Bool?
    @State private var matchingOptionsExpanded = false
    @State private var showsPrivacy = false
    @State private var importing = false
    @State private var importNotice: String?
    @State private var matching = false
    @State private var exportDocument: PhotoGPXDocument?
    @State private var exportFilename = ""
    @State private var exporting = false
    private var library: TrackLibrary { workspace.tracks }
    private var amap: Bool { provider == "amap" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DisclosureGroup(isExpanded: expansion) {
                VStack(alignment: .leading, spacing: 12) {
                    if library.activeRecords.isEmpty {
                        Text(L10n.text("导入 GPX、KML、KMZ，或从历史记录加入轨迹。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(library.activeRecords) { record in trackRow(record) }
                    if !store.gpxTracks.isEmpty {
                        Text(L10n.text("匹配范围：含时间轨迹（%1$@ 条）", store.gpxTracks.filter(\.hasRecordedTimes).count))
                            .font(.caption).foregroundStyle(.secondary)
                        matchingControls
                    }
                    Divider()
                    historySection
                }.padding(.top, 10)
            } label: {
                HStack(spacing: 8) {
                    Label(L10n.text("轨迹"), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.headline)
                    Spacer(minLength: 0)
                    Button(L10n.text("导入…")) { importing = true }
                        .buttonStyle(.borderless)
                        .help(L10n.text("导入轨迹")).disabled(store.saveInProgress)
                    Menu {
                        Button(L10n.text("刷新全部可见轨迹")) {
                            for record in library.activeRecords where library.visible.contains(record.id) {
                                refresh(record.id)
                            }
                        }.disabled(library.visible.isEmpty || store.saveInProgress)
                        Button(L10n.text("隐藏全部轨迹")) {
                            for id in library.visible { library.setVisible(id, false, amap: amap) }
                        }.disabled(library.visible.isEmpty)
                        Divider()
                        Button(L10n.text("轨迹与隐私说明")) { showsPrivacy = true }
                    } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).fixedSize().help(L10n.text("轨迹操作"))
                }
            }
            if !expansion.wrappedValue {
                Text(L10n.text("按拍摄时间，批量补齐照片定位。"))
                    .font(.caption).foregroundStyle(.secondary)
                if matching { ProgressView(L10n.text("正在匹配轨迹…")).controlSize(.small) }
                if library.states.values.contains(where: { if case .failed = $0 { return true }; return false }) {
                    Button(L10n.text("轨迹转换失败，展开查看。")) { tracksExpanded = true }
                        .buttonStyle(.borderless).foregroundStyle(.orange)
                }
            }
            if let importNotice {
                Text(importNotice).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !store.gpxBadFileNames.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L10n.text("以下轨迹未能导入")).fontWeight(.medium)
                        Spacer()
                        Button(L10n.text("关闭")) { store.send(.gpxLoadViewClosed, undoable: false) }
                            .buttonStyle(.borderless)
                    }
                    ForEach(store.gpxBadFileNames, id: \.self) { path in
                        Text(URL(fileURLWithPath: path).lastPathComponent).lineLimit(2)
                    }
                    Text(L10n.text("文件无法读取或没有有效轨迹，请检查后重新导入。"))
                }.font(.caption).foregroundStyle(.orange)
            }
            if let error = library.storageError { Text(error).font(.caption).foregroundStyle(.orange) }
        }
        .onChange(of: library.activeIDs) { previous, current in
            if !Set(current).subtracting(previous).isEmpty { tracksExpanded = true }
        }
        .popover(isPresented: $showsPrivacy) {
            Text(amap ? L10n.text("高德仅接收轨迹坐标用于转换；照片和轨迹文件不上传，缓存仅存本机。")
                      : L10n.text("轨迹使用原始坐标，无需转换；缓存仅存本机。"))
                .font(.callout).padding(16).frame(width: 280)
        }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: UTType.photoTrailTracks,
                      allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            importNotice = urls.contains { library.record($0.standardizedFileURL.path) != nil }
                ? L10n.text("已导入的文件会更新原条目，不会重复添加。") : nil
            store.send(.openFiles(urls), undoable: false) {
                if let unique = store.uniqueURLs {
                    OpenHelper.open(store, urls: unique, description: L10n.text("导入轨迹"), spinnerEnabled: nil)
                    store.send(.clearUniqueURLs, undoable: false)
                }
            }
        }
        .fileExporter(isPresented: $exporting, document: exportDocument,
                      contentType: PhotoGPXDocument.contentType,
                      defaultFilename: exportFilename) { result in
            if case .failure(let error) = result { importNotice = L10n.text("导出失败：%1$@", error.localizedDescription) }
            exportDocument = nil
        }
    }

}

private extension TrackSidebar {
    var expansion: Binding<Bool> {
        Binding(get: { tracksExpanded ?? !library.activeIDs.isEmpty }, set: { tracksExpanded = $0 })
    }

    var historySection: some View {
        DisclosureGroup(isExpanded: $historyExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                if library.records.isEmpty {
                    Text(L10n.text("导入过的轨迹会保存在这里。")).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(library.records.reversed()) { record in
                    HStack(spacing: 8) {
                        TrackThumbnail(segments: record.segments)
                            .frame(width: 36, height: 38).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(record.name).font(.callout.weight(.medium)).lineLimit(2).truncationMode(.middle)
                            Text(record.timeRange).font(.caption2).foregroundStyle(.secondary)
                            Text(record.cacheIsCurrent ? L10n.text("已缓存") : amap ? L10n.text("加入后转换") : L10n.text("原始轨迹"))
                                .font(.caption2).foregroundStyle(record.cacheIsCurrent ? Color.green : .secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Button(library.activeIDs.contains(record.id) ? L10n.text("已加入") : L10n.text("加入")) {
                            if let log = library.addHistory(record.id, amap: amap) {
                                store.send(.restoreTracks([log]), undoable: false)
                            }
                        }
                        .disabled(library.activeIDs.contains(record.id) || store.saveInProgress)
                        .accessibilityLabel(L10n.text("加入历史轨迹 %1$@", record.name))
                    }
                }
            }.padding(.top, 8)
        } label: {
            HStack {
                Label(L10n.text("轨迹历史"), systemImage: "clock")
                Spacer()
                Text("\(library.records.count)").foregroundStyle(.secondary)
            }
            .font(.subheadline)
        }
    }

    private var matchingControls: some View {
        let selection = MapPhotoSelectionSummary(images: store.imageData, selectedIDs: store.selection)
        let blocked = store.selection.isEmpty || !store.gpxTracks.contains(where: \.hasRecordedTimes) || store.saveInProgress || matching
        return VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("匹配所选照片：%1$@ 张", store.selection.count)).font(.callout.weight(.medium))
            Button(L10n.text("按轨迹时段选择照片")) { selectPhotosInTrackTime() }
                .buttonStyle(.borderless)
                .disabled(!store.gpxTracks.contains(where: \.hasRecordedTimes) || store.saveInProgress || matching)
                .help(L10n.text("选中拍摄时间落在任一已导入轨迹记录段内的照片"))
            Button { applyTrackLocations(overwrite: false) } label: {
                Text(L10n.text("补齐缺失定位")).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(blocked || selection.missing == 0 || selection.readOnly == selection.total)
            Text(L10n.text("仅为没有定位的照片匹配位置，不覆盖已有定位。"))
                .font(.caption).foregroundStyle(.secondary)
            Text(L10n.text("匹配后暂存，可撤销。"))
                .font(.caption).foregroundStyle(.secondary)
            if store.saveInProgress {
                Text(L10n.text("正在保存")).font(.caption).foregroundStyle(.secondary)
            } else if selection.total == 0 {
                Text(L10n.text("选择照片后再匹配定位。")).font(.caption).foregroundStyle(.secondary)
            } else if selection.readOnly > 0 {
                Text(L10n.text("%1$@ 张照片无法编辑，将跳过。", selection.readOnly))
                    .font(.caption).foregroundStyle(.secondary)
            } else if selection.missing == 0 {
                Text(L10n.text("所选照片均已有定位，可在更多匹配选项中重新匹配。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup(L10n.text("更多匹配选项"), isExpanded: $matchingOptionsExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    Button(L10n.text("覆盖所有定位")) { applyTrackLocations(overwrite: true) }
                        .buttonStyle(.bordered)
                        .disabled(blocked || selection.readOnly == selection.total)
                    Text(L10n.text("重新匹配所选照片，成功匹配的位置会替换现有定位，写入前可撤销。"))
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
            }
            if matching { ProgressView(L10n.text("正在匹配轨迹…")).controlSize(.small) }
        }
    }

    private func trackRow(_ record: TrackRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Button { library.select(record.id, amap: amap) } label: {
                    HStack(alignment: .top, spacing: 8) {
                        TrackThumbnail(segments: record.segments)
                            .frame(width: 48, height: 46)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(record.name).font(.callout.weight(.medium))
                                    .lineLimit(2).truncationMode(.middle)
                                if record.generatedFromPhotos {
                                    Label(L10n.text("照片生成"), systemImage: "photo.on.rectangle")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.blue)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.10), in: Capsule())
                                }
                            }
                            Text(record.timeRange).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .help(L10n.text("轨迹记录时间，按本机时区显示"))
                            Text(record.log.hasRecordedTimes ? L10n.text("含时间，可匹配照片")
                                 : L10n.text("仅供查看：缺少轨迹点时间"))
                                .font(.caption).foregroundStyle(record.log.hasRecordedTimes ? Color.secondary : .orange)
                            Text(summary(record)).font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel(L10n.text("查看 %1$@ 的轨迹范围", record.name))
                    .accessibilityValue("\(record.timeRange)，\(summary(record))")
                    .accessibilityAddTraits(library.selected == record.id ? .isSelected : [])
                VStack(spacing: 8) {
                    Button { library.setVisible(record.id, !library.visible.contains(record.id), amap: amap) } label: {
                        Image(systemName: library.visible.contains(record.id) ? "eye" : "eye.slash")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.text("仅控制地图显示，不改变匹配范围。"))
                    .accessibilityLabel(L10n.text("显示 %1$@", record.name))
                    .accessibilityValue(library.visible.contains(record.id) ? L10n.text("已显示") : L10n.text("已隐藏"))
                    Menu { trackActions(record) } label: { Image(systemName: "ellipsis").frame(width: 24, height: 20) }
                        .menuStyle(.borderlessButton).fixedSize().help(L10n.text("轨迹操作"))
                }
            }
            if record.sourceUnavailable {
                Text(L10n.text("原文件不可用，仍可查看已有缓存；请重新导入以匹配照片。"))
                    .font(.caption).foregroundStyle(.orange)
            }
            if let state = library.states[record.id] {
                switch state {
                case .loading(let completed, let total):
                    HStack(spacing: 8) {
                        ProgressView(value: Double(completed), total: Double(max(total, 1))) {
                            Text(library.nextRequestID == record.id
                                 ? L10n.text("%1$@中 · %2$@ / %3$@ 点", record.converted == nil ? L10n.text("转换") : L10n.text("刷新"), completed, total)
                                 : L10n.text("等待转换"))
                                .font(.caption)
                        }
                        Button(L10n.text("取消")) { library.cancel(record.id) }.buttonStyle(.borderless)
                    }
                    Text(library.nextRequestID != record.id ? L10n.text("前一条完成后自动开始。")
                         : workspace.ready ? L10n.text("正在按顺序处理轨迹。") : L10n.text("等待高德地图就绪…"))
                        .font(.caption2).foregroundStyle(.secondary)
                case .failed(let reason):
                    HStack(alignment: .top) {
                        Text(record.converted == nil ? L10n.text("转换失败：%1$@", reason) : L10n.text("刷新失败，保留原轨迹。%1$@", reason))
                            .font(.caption).foregroundStyle(.orange)
                        Spacer(minLength: 4)
                        Button(L10n.text("重试")) { refresh(record.id) }.buttonStyle(.borderless)
                    }
                }
            }
        }
        .padding(8)
        .background(library.selected == record.id ? Color.accentColor.opacity(0.10) : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .contextMenu { trackActions(record) }
    }

    @ViewBuilder
    private func trackActions(_ record: TrackRecord) -> some View {
        Button(L10n.text("重新读取并刷新这条轨迹")) { refresh(record.id) }
            .disabled(library.requests[record.id] != nil || store.saveInProgress)
        if record.generatedFromPhotos {
            Button(L10n.text("导出 GPX…"), systemImage: "square.and.arrow.up") {
                do {
                    exportDocument = PhotoGPXDocument(data: try Data(contentsOf: record.log.sourceURL))
                    exportFilename = record.name
                    exporting = true
                } catch { importNotice = L10n.text("无法读取缓存轨迹：%1$@", error.localizedDescription) }
            }.disabled(record.sourceUnavailable)
        }
        Button(L10n.text("清除这条轨迹的转换缓存")) { library.clearCache(record.id) }
            .disabled(record.converted == nil)
        Button(L10n.text("从操作区移除")) {
            library.remove(record.id)
            store.send(.removeTrack(record.log.sourceURL), description: L10n.text("移除轨迹"))
        }.disabled(store.saveInProgress)
    }

}

private extension TrackSidebar {
    func summary(_ record: TrackRecord) -> String {
        let state = amap ? (record.converted == nil ? L10n.text("待转换") : record.cacheIsCurrent ? L10n.text("已缓存") : L10n.text("待更新 · 使用旧缓存")) : L10n.text("原始轨迹")
        return L10n.text("%1$@ 点 · %2$@", record.points.count, state)
    }

    private func refresh(_ id: String) {
        if let log = library.refresh(id, amap: amap) {
            store.send(.restoreTracks([log]), undoable: false)
        }
    }

    private func selectPhotosInTrackTime() {
        let ids = LocationHelper.photoIDs(in: store.visibleImages, timeZone: store.timeZone,
                                          tracks: store.gpxTracks)
        store.send(.selectionChanged(ids), undoable: false)
        importNotice = L10n.text("已按全部导入轨迹的记录时段选中 %1$@ 张照片。", ids.count)
    }

    private func applyTrackLocations(overwrite: Bool) {
        let selection = store.selection
        matching = true
        let task = LocationHelper.locationFromTrack(store, extendedTime: extendedTime,
                                                    overwriteExisting: overwrite)
        Task {
            _ = await task.result
            defer { matching = false }
            guard store.selection == selection else {
                store.send(.locationFromTrack([]), undoable: false)
                importNotice = L10n.text("照片选择已变化，请重新操作。")
                return
            }
            let editableIDs = Set(store.imageData.lazy.filter { $0.updatable }.map(\.id))
            let matched = store.trackMatches.filter {
                $0.status == .matched && $0.coords != nil && editableIDs.contains($0.id)
            }
            guard !matched.isEmpty else {
                store.send(.locationFromTrack([]), undoable: false)
                importNotice = L10n.text("没有可安全匹配的照片；照片定位未修改。")
                return
            }
            store.send(.locationFromTrack(matched), undoable: false)
            store.send(.applyTrackMatches, description: overwrite ? L10n.text("按轨迹重设定位") : L10n.text("按轨迹补齐定位"))
            importNotice = L10n.text("已修改 %1$@ 张照片，另有 %2$@ 张跳过；请写入所有元数据。",
                                    matched.count, selection.count - matched.count)
        }
    }
}

struct TrackThumbnail: View {
    let segments: [[MapCoordinate]]

    // A local, aspect-preserving projection. Never request map tiles or join segment breaks.
    static func normalized(_ segments: [[MapCoordinate]]) -> [[CGPoint]] {
        let points = segments.flatMap { $0 }.filter(\.isValid)
        guard let first = points.first else { return [] }
        let meanLatitude = points.map(\.latitude).reduce(0, +) / Double(points.count)
        let scale = max(0.01, cos(meanLatitude * .pi / 180))
        let projected = segments.map { segment in segment.filter(\.isValid).map { point in
            let longitude = (point.longitude - first.longitude + 540).truncatingRemainder(dividingBy: 360) - 180
            return CGPoint(x: longitude * scale, y: -point.latitude)
        } }
        let all = projected.flatMap { $0 }
        guard let minX = all.map(\.x).min(), let maxX = all.map(\.x).max(),
              let minY = all.map(\.y).min(), let maxY = all.map(\.y).max() else { return [] }
        let extent = max(maxX - minX, maxY - minY, 0.000001)
        return projected.map { $0.map { CGPoint(x: ($0.x - (minX + maxX) / 2) / extent + 0.5,
                                                 y: ($0.y - (minY + maxY) / 2) / extent + 0.5) } }
    }

    var body: some View {
        let paths = Self.normalized(segments)
        Canvas { context, size in
            let inset: CGFloat = 4
            let edge = min(size.width, size.height) - inset * 2
            for segment in paths {
                var path = Path()
                for (index, point) in segment.enumerated() {
                    let fitted = CGPoint(x: (size.width - edge) / 2 + point.x * edge,
                                         y: (size.height - edge) / 2 + point.y * edge)
                    if index == 0 { path.move(to: fitted) } else { path.addLine(to: fitted) }
                }
                context.stroke(path, with: .color(.red), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 2]))
            }
        }.background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 4))
    }
}
