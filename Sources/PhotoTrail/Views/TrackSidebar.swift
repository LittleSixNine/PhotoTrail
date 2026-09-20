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
            HStack {
                Text("GPX 轨迹").font(.headline)
                Spacer(minLength: 6)
                Button { importing = true } label: { Label("导入", systemImage: "plus") }
                    .help("导入 GPX 轨迹").disabled(store.saveInProgress)
                Menu {
                    Button("刷新全部可见轨迹") {
                        for record in library.activeRecords where library.visible.contains(record.id) {
                            refresh(record.id)
                        }
                    }.disabled(library.visible.isEmpty || store.saveInProgress)
                    Button("隐藏全部轨迹") {
                        for id in library.visible { library.setVisible(id, false, amap: amap) }
                    }.disabled(library.visible.isEmpty)
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).fixedSize().help("轨迹操作")
            }
            Divider()
            historySection
            Divider()
            Text("本次轨迹 · \(library.activeRecords.count)")
                .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            if library.activeRecords.isEmpty {
                Text("导入 GPX，或从历史记录加入轨迹。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let importNotice { Text(importNotice).font(.caption).foregroundStyle(.secondary) }
            if !store.gpxBadFileNames.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("以下 GPX 未能导入").fontWeight(.medium)
                        Spacer()
                        Button("关闭") { store.send(.gpxLoadViewClosed, undoable: false) }
                            .buttonStyle(.borderless)
                    }
                    ForEach(store.gpxBadFileNames, id: \.self) { path in
                        Text(URL(fileURLWithPath: path).lastPathComponent).lineLimit(2)
                    }
                    Text("文件无法读取或没有有效轨迹，请检查后重新导入。")
                }.font(.caption).foregroundStyle(.orange)
            }
            ForEach(library.activeRecords) { record in
                trackRow(record)
            }
            if !library.activeRecords.isEmpty {
                Divider()
                matchingControls
            }
            if let error = library.storageError {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
            Text(amap ? "高德仅接收轨迹坐标用于转换；照片和 GPX 文件不上传，缓存仅存本机。"
                      : "轨迹使用原始坐标，无需转换；缓存仅存本机。")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [UTType(filenameExtension: "gpx") ?? .xml],
                      allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            importNotice = urls.contains { library.record($0.standardizedFileURL.path) != nil }
                ? "已导入的文件会更新原条目，不会重复添加。" : nil
            store.send(.openFiles(urls), undoable: false) {
                if let unique = store.uniqueURLs {
                    OpenHelper.open(store, urls: unique, description: "导入 GPX", spinnerEnabled: nil)
                    store.send(.clearUniqueURLs, undoable: false)
                }
            }
        }
        .fileExporter(isPresented: $exporting, document: exportDocument,
                      contentType: PhotoGPXDocument.contentType,
                      defaultFilename: exportFilename) { result in
            if case .failure(let error) = result { importNotice = "导出失败：\(error.localizedDescription)" }
            exportDocument = nil
        }
    }

}

private extension TrackSidebar {
    var historySection: some View {
        DisclosureGroup(isExpanded: $historyExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                if library.records.isEmpty {
                    Text("导入过的轨迹会保存在这里。").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(library.records.reversed()) { record in
                    HStack(spacing: 8) {
                        TrackThumbnail(segments: record.segments)
                            .frame(width: 36, height: 38).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(record.name).font(.callout.weight(.medium)).lineLimit(2).truncationMode(.middle)
                            Text(record.timeRange).font(.caption2).foregroundStyle(.secondary)
                            Text(record.cacheIsCurrent ? "已缓存" : amap ? "加入后转换" : "原始轨迹")
                                .font(.caption2).foregroundStyle(record.cacheIsCurrent ? Color.green : .secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Button(library.activeIDs.contains(record.id) ? "已加入" : "加入") {
                            if let log = library.addHistory(record.id, amap: amap) {
                                store.send(.restoreTracks([log]), undoable: false)
                            }
                        }
                        .disabled(library.activeIDs.contains(record.id) || store.saveInProgress)
                        .accessibilityLabel("加入历史轨迹 \(record.name)")
                    }
                }
            }.padding(.top, 8)
        } label: {
            HStack {
                Label("历史记录", systemImage: "clock")
                Spacer()
                Text("\(library.records.count)").foregroundStyle(.secondary)
            }
            .font(.subheadline)
        }
    }

    private var matchingControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { selectPhotosInTrackTime() } label: {
                Text("选择轨迹时段内拍摄的照片").frame(maxWidth: .infinity)
            }
            .disabled(store.gpxTracks.isEmpty || store.saveInProgress || matching)
            .help("选中拍摄时间落在任一已导入轨迹记录段内的照片")
            Text("已选择 \(store.selection.count) 张照片")
                .font(.caption).foregroundStyle(.secondary)
            Text("为所选照片写入定位").font(.subheadline.weight(.medium)).padding(.top, 6)
            Button { applyTrackLocations(overwrite: false) } label: {
                Text("补齐缺失定位").frame(maxWidth: .infinity)
            }
            .disabled(store.selection.isEmpty || store.gpxTracks.isEmpty || store.saveInProgress || matching
                || store.selection.allSatisfy { store[$0].metadata.location != nil })
            Text("仅为没有定位的照片匹配位置，不覆盖已有定位。")
                .font(.caption).foregroundStyle(.secondary)
            Button { applyTrackLocations(overwrite: true) } label: {
                Text("覆盖所有定位").frame(maxWidth: .infinity)
            }
            .disabled(store.selection.isEmpty || store.gpxTracks.isEmpty || store.saveInProgress || matching)
            Text("使用轨迹位置替换已有定位；保存前可以撤销。")
                .font(.caption).foregroundStyle(.secondary)
            if matching { ProgressView("正在匹配轨迹…").controlSize(.small) }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private func trackRow(_ record: TrackRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Toggle("显示 \(record.name)", isOn: Binding(
                    get: { library.visible.contains(record.id) },
                    set: { library.setVisible(record.id, $0, amap: amap) }))
                    .labelsHidden().toggleStyle(.checkbox)
                    .help("显示或隐藏这条轨迹")
                    .padding(.top, 4)
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
                                    Label("照片生成", systemImage: "photo.on.rectangle")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.blue)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.10), in: Capsule())
                                }
                            }
                            Text(record.timeRange).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .help("GPX 记录时间，按本机时区显示")
                            Text(summary(record)).font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel("查看 \(record.name) 的轨迹范围")
                    .accessibilityValue("\(record.timeRange)，\(summary(record))")
                    .accessibilityAddTraits(library.selected == record.id ? .isSelected : [])
                Button { refresh(record.id) } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .disabled(library.requests[record.id] != nil || store.saveInProgress)
                    .help("重新读取并刷新这条轨迹")
                    .accessibilityLabel("刷新 \(record.name)")
                    .padding(.top, 4)
            }
            if record.sourceUnavailable {
                Text("原文件不可用，仍可查看已有缓存；请重新导入以匹配照片。")
                    .font(.caption).foregroundStyle(.orange)
            }
            if let state = library.states[record.id] {
                switch state {
                case .loading(let completed, let total):
                    HStack(spacing: 8) {
                        ProgressView(value: Double(completed), total: Double(max(total, 1))) {
                            Text(library.nextRequestID == record.id
                                 ? "\(record.converted == nil ? "转换" : "刷新")中 · \(completed) / \(total) 点"
                                 : "等待转换")
                                .font(.caption)
                        }
                        Button("取消") { library.cancel(record.id) }.buttonStyle(.borderless)
                    }
                    Text(library.nextRequestID != record.id ? "前一条完成后自动开始。"
                         : workspace.ready ? "正在按顺序处理轨迹。" : "等待高德地图就绪…")
                        .font(.caption2).foregroundStyle(.secondary)
                case .failed(let reason):
                    HStack(alignment: .top) {
                        Text(record.converted == nil ? "转换失败：\(reason)" : "刷新失败，保留原轨迹。\(reason)")
                            .font(.caption).foregroundStyle(.orange)
                        Spacer(minLength: 4)
                        Button("重试") { refresh(record.id) }.buttonStyle(.borderless)
                    }
                }
            }
        }
        .padding(8)
        .background(library.selected == record.id ? Color.accentColor.opacity(0.10) : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .contextMenu {
            if record.generatedFromPhotos {
                Button("导出 GPX…", systemImage: "square.and.arrow.up") {
                    do {
                        exportDocument = PhotoGPXDocument(data: try Data(contentsOf: record.log.sourceURL))
                        exportFilename = record.name
                        exporting = true
                    } catch { importNotice = "无法读取缓存轨迹：\(error.localizedDescription)" }
                }.disabled(record.sourceUnavailable)
                Divider()
            }
            Button("清除这条轨迹的转换缓存") { library.clearCache(record.id) }
                .disabled(record.converted == nil)
            Button("从操作区移除") {
                library.remove(record.id)
                store.send(.removeTrack(record.log.sourceURL), description: "移除轨迹")
            }.disabled(store.saveInProgress)
        }
    }

}

private extension TrackSidebar {
    func summary(_ record: TrackRecord) -> String {
        let state = amap ? (record.converted == nil ? "待转换" : record.cacheIsCurrent ? "已缓存" : "待更新 · 使用旧缓存") : "原始轨迹"
        return "\(record.points.count) 点 · \(state)"
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
        importNotice = "已按全部导入轨迹的记录时段选中 \(ids.count) 张照片。"
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
                importNotice = "照片选择已变化，请重新操作。"
                return
            }
            let matched = store.trackMatches.filter { $0.status == .matched && $0.coords != nil }
            guard !matched.isEmpty else {
                store.send(.locationFromTrack([]), undoable: false)
                importNotice = "没有可安全匹配的照片；照片定位未修改。"
                return
            }
            store.send(.applyTrackMatches, description: overwrite ? "按轨迹重设定位" : "按轨迹补齐定位")
            importNotice = "已修改 \(matched.count) 张照片，另有 \(selection.count - matched.count) 张跳过；请保存修改。"
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
