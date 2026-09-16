import Coords
import GpxTrackLog
import SwiftUI
import UDF
import UniformTypeIdentifiers

struct TrackSidebar: View {
    @Environment(Store<GeoTagState, GeoTagEvent>.self) private var store
    @Environment(LocationWorkspace.self) private var workspace
    @AppStorage("PhotoTrailMapProvider") private var provider = "amap"
    @AppStorage(SettingsView.extendedTimeKey) private var extendedTime = 120.0
    @State private var importing = false
    @State private var importNotice: String?
    @State private var matching = false
    @State private var exportDocument: PhotoGPXDocument?
    @State private var exportFilename = ""
    @State private var exporting = false
    private var library: TrackLibrary { workspace.tracks }
    private var amap: Bool { provider == "amap" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("GPX 轨迹").font(.headline)
                    Text("\(library.records.count) 个文件").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                Button { importing = true } label: { Label("导入", systemImage: "plus") }
                    .help("导入 GPX 轨迹")
                    .disabled(store.saveInProgress)
                Menu {
                    Button("刷新全部可见轨迹") {
                        for id in library.visible { refresh(id) }
                    }.disabled(library.visible.isEmpty)
                    Button("隐藏全部轨迹") {
                        for id in library.visible { library.setVisible(id, false, amap: amap) }
                    }.disabled(library.visible.isEmpty)
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).fixedSize().help("轨迹操作")
            }
            if library.records.isEmpty {
                Text("导入 GPX 后，可查看轨迹和匹配照片位置。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let importNotice { Text(importNotice).font(.caption).foregroundStyle(.secondary) }
            ForEach(library.records) { record in
                trackRow(record)
            }
            if !library.records.isEmpty {
                Button("选中轨迹时段的照片") { selectPhotosInTrackTime() }
                    .disabled(store.gpxTracks.isEmpty || store.saveInProgress || matching)
                    .help("选中拍摄时间落在任一已导入轨迹记录段内的照片")
                Text("已选 \(store.selection.count) 张照片 · 仅可靠匹配会修改")
                    .font(.caption).foregroundStyle(.secondary)
                Button("补齐所选照片的定位") { applyTrackLocations(overwrite: false) }
                    .disabled(store.selection.isEmpty || store.gpxTracks.isEmpty
                        || store.saveInProgress || matching
                        || store.selection.allSatisfy { store[$0].metadata.location != nil })
                    .help("只处理没有定位的所选照片")
                Button("按轨迹重设所选照片定位") { applyTrackLocations(overwrite: true) }
                    .disabled(store.selection.isEmpty || store.gpxTracks.isEmpty
                        || store.saveInProgress || matching)
                    .help("包括已有定位的所选照片；保存前可以撤销")
                if matching { ProgressView("正在匹配轨迹…").controlSize(.small) }
            }
            if let error = library.storageError {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
            if !library.records.isEmpty {
                Text("点轨迹看范围，勾选控制显示。")
                    .font(.caption).foregroundStyle(.secondary)
                Text(amap ? "高德仅接收轨迹坐标用于转换；照片和 GPX 文件不上传，缓存仅存本机。"
                          : "轨迹缓存仅存本机。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: provider) {
            for id in library.requests.keys { library.cancel(id) }
        }
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
                    .disabled(library.requests[record.id] != nil)
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
                            Text("\(record.converted == nil ? "转换" : "刷新")中 · \(completed) / \(total) 点")
                                .font(.caption)
                        }
                        Button("取消") { library.cancel(record.id) }.buttonStyle(.borderless)
                    }
                    Text(workspace.ready ? "高德每批最多 40 点，需间隔处理。" : "等待高德地图就绪…")
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
            Button("从列表移除") {
                library.remove(record.id)
                store.send(.removeTrack(record.log.sourceURL), description: "移除轨迹")
            }
        }
    }

    private func summary(_ record: TrackRecord) -> String {
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
