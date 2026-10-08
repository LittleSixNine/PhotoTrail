import Exiftool
import ImageData
import SwiftUI
import UDF

enum MetadataExposureDisplay {
    static func text(_ value: String) -> String? {
        let parts = value.split(separator: "/")
        let seconds: Double?
        if parts.count == 2, let numerator = Double(parts[0]), let denominator = Double(parts[1]), denominator > 0 {
            seconds = numerator / denominator
        } else { seconds = Double(value) }
        guard let seconds, seconds.isFinite, seconds > 0 else { return nil }
        if seconds >= 1 { return String(format: "%.6g s", seconds) }
        let reciprocal = 1 / seconds
        guard reciprocal.isFinite else { return nil }
        let common: [Double] = [1, 1.3, 1.6, 2, 2.5, 3.2, 4, 5, 6, 8, 10, 13, 15, 20, 25, 30,
                                40, 50, 60, 80, 100, 125, 160, 200, 250, 320, 400, 500, 640, 800,
                                1000, 1250, 1600, 2000, 2500, 3200, 4000, 5000, 6400, 8000]
        if let nearest = common.min(by: { abs($0 - reciprocal) < abs($1 - reciprocal) }),
           abs(1 / nearest - seconds) / seconds <= 0.03 {
            let approximate = abs(1 / nearest - seconds) / seconds > 0.000001
            return (approximate ? "≈ " : "") + String(format: "1/%.6g s", nearest)
        }
        return String(format: "1/%.6g s", reciprocal)
    }
}

enum MetadataInspectorDateDisplay {
    static func text(_ value: String, timeZone: TimeZone = .current) -> String? {
        var normalized = value.replacingOccurrences(of: "T", with: " ")
        if normalized.count >= 10 {
            normalized = normalized.prefix(10).replacingOccurrences(of: "-", with: ":") + normalized.dropFirst(10)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        if let parsed = try? MetadataDate(normalized) {
            formatter.timeZone = parsed.offset.isEmpty ? parsed.displayTimeZone : timeZone
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let seconds = timeZone.secondsFromGMT(for: parsed.date)
            let zone = parsed.offset.isEmpty ? L10n.text("时区未记录")
                : String(format: "UTC%@%02d:%02d", seconds < 0 ? "-" : "+", abs(seconds) / 3600, abs(seconds) % 3600 / 60)
            let detail = zone + (parsed.fraction.isEmpty ? "" : " · " + L10n.text("亚秒 %1$@ 秒", "0" + parsed.fraction))
            return formatter.string(from: parsed.date) + "\n" + detail
        }
        if let parsed = try? MetadataDate(normalized + " 00:00:00") {
            formatter.timeZone = parsed.displayTimeZone
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: parsed.date) + "\n" + L10n.text("仅日期")
        }
        if let parsed = try? MetadataDate("2000:01:01 " + normalized) {
            let zone = parsed.offset.isEmpty ? L10n.text("时区未记录")
                : "UTC" + (parsed.offset == "Z" ? "+00:00" : parsed.offset)
            return String(normalized.prefix(8)) + "\n" + L10n.text("仅时间") + " · " + zone
                + (parsed.fraction.isEmpty ? "" : " · " + L10n.text("亚秒 %1$@ 秒", "0" + parsed.fraction))
        }
        return nil
    }
}

final class MetadataInspectorReadCache: @unchecked Sendable {
    static let shared = MetadataInspectorReadCache()
    enum Kind: Hashable, Sendable { case editable, standard, additional }
    struct Key: Hashable, Sendable {
        let url: URL
        let imageURL: URL
        let kind: Kind
    }
    enum Value: Sendable {
        case editable(MetadataInspectionSnapshot, [LegacyCreatorTag: [String]])
        case display([String: String])
    }
    private struct Entry {
        let versions: [MetadataInspectionFileVersion]
        let value: Value
    }
    private let lock = NSLock()
    private var entries: [Key: Entry] = [:]
    private var order: [Key] = []
    // ponytail: cap by dataset count; add a byte budget if measured metadata memory warrants it.
    private let limit: Int

    init(limit: Int = 64) { self.limit = limit }

    func value(for key: Key, versions: [MetadataInspectionFileVersion]) -> Value? {
        lock.withLock {
            guard let entry = entries[key] else { return nil }
            guard entry.versions == versions else {
                entries[key] = nil
                order.removeAll { $0 == key }
                return nil
            }
            return entry.value
        }
    }

    func insert(_ value: Value, for key: Key, versions: [MetadataInspectionFileVersion]) {
        lock.withLock {
            entries[key] = Entry(versions: versions, value: value)
            order.removeAll { $0 == key }
            order.append(key)
            if order.count > limit { entries[order.removeFirst()] = nil }
        }
    }

    func invalidate(urls: Set<URL>) {
        lock.withLock {
            let removed = order.filter { urls.contains($0.url) || urls.contains($0.imageURL) }
            for key in removed { entries[key] = nil }
            order.removeAll { removed.contains($0) }
        }
    }
}

struct MetadataInspectionRequest: Sendable, Equatable {
    let id: ImageData.ID
    let url: URL?
    let creatorImageURL: URL?
    var versions: [MetadataInspectionFileVersion] {
        var versions = [MetadataInspectionFileVersion.read(url)]
        if creatorImageURL != url { versions.append(MetadataInspectionFileVersion.read(creatorImageURL)) }
        return versions
    }
}

private enum MetadataInspectionRead: Sendable {
    case values(MetadataInspectionSnapshot, [LegacyCreatorTag: [String]]?)
    case unsupported
    case failed
}

struct MetadataListInspectorView: View {
    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) private var store
    @Environment(MetadataLoadingQueue.self) private var metadataQueue
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectionProjection = PhotoListProjection()
    @State private var results: [ImageData.ID: MetadataInspectionRead] = [:]
    @State private var checkingVersions = false
    @State private var observedVersions: [MetadataInspectionFileVersion] = []
    @State private var loading = false
    @State private var loadID = UUID()
    @State private var revision = 0
    @State private var fieldQuery = ""
    @State private var showsEditingHelp = false
    @AppStorage("metadataCommonFieldsOnly") private var commonOnly = true

    @State private var workflowEditor: MetadataCreatorEditorSelection?
    @State private var selectedWorkflowPreset: MetadataPreset?
    @AppStorage("PhotoTrail.MetadataPresets") private var presetData = Data()
    @State private var advanced: [ImageData.ID: [String: String]] = [:]
    @State private var advancedLoading = false
    @State private var advancedFailed = false
    @State private var advancedReadKey: LoadKey?
    @State private var editableReadKey: LoadKey?
    @State private var creatorEditor: MetadataCreatorEditorSelection?
    @State private var selectedFields = Set<String>()
    @State private var batchEditor: MetadataBatchEditorSelection?
    @State private var pasteFailed = false

    private struct LoadKey: Hashable {
        let ids: [ImageData.ID]
        let urls: [URL?]
        let creatorImageURLs: [URL?]
        let revision: Int

        func hasSameSources(as other: Self?) -> Bool {
            guard let other else { return false }
            return ids == other.ids && urls == other.urls && creatorImageURLs == other.creatorImageURLs
        }
    }

    private var selected: [ImageData] {
        selectionProjection.selected(store.state)
    }

    private var loadKey: LoadKey {
        let images = selected
        return LoadKey(ids: images.map(\.id),
                urls: images.map(\.metadataInspectionURL),
                creatorImageURLs: images.map(\.metadataCreatorImageURL),
                revision: revision)
    }

    private var selectedVersions: [MetadataInspectionFileVersion] {
        selected.flatMap(\.metadataInspectionVersions)
    }


    private var completeValues: [[MetadataTag: MetadataTagValue]]? { completeValues(for: selected) }

    private func completeValues(for images: [ImageData]) -> [[MetadataTag: MetadataTagValue]]? {
        let values = images.compactMap { image -> [MetadataTag: MetadataTagValue]? in
            guard case .values(let snapshot, _) = results[image.id] else { return nil }
            var values = snapshot.values
            for (tag, change) in image.creatorDraft?.changes ?? [:] {
                switch change {
                case .set(let value): values[tag] = value
                case .remove: values[tag] = nil
                }
            }
            return values
        }
        return values.count == images.count ? values : nil
    }

    private var completeLegacyValues: [[LegacyCreatorTag: [String]]]? {
        let values = selected.compactMap { image -> [LegacyCreatorTag: [String]]? in
            guard case .values(_, let legacy?) = results[image.id] else { return nil }
            var values = legacy
            for (tag, source) in [(MetadataTag.exifArtist, LegacyCreatorTag.exifArtist), (.iptcByline, .iptcByline)] {
                switch image.creatorDraft?.changes[tag] {
                case .set(.text(let text)): values[source] = [text]
                case .set(.list(let names)): values[source] = names
                case .remove: values[source] = nil
                case nil: break
                }
            }
            return values
        }
        return values.count == selected.count ? values : nil
    }

    private var editableCreatorReadings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)]? {
        guard !store.saveInProgress, !loading, !selected.isEmpty else { return nil }
        var readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)] = []
        for image in selected {
            guard image.updatable, !image.hasLegacyChanges,
                  store.creatorSaveResults[image.id] != .resultUnknown,
                  case .values(let snapshot, _) = results[image.id] else { return nil }
            switch image.metadata.source {
            case .image(let url) where ["jpg", "jpeg"].contains(url.pathExtension.lowercased()):
                readings.append((image, snapshot))
            case .xmp:
                readings.append((image, snapshot))
            default: return nil
            }
        }
        return readings
    }

    private var editUnavailableReason: String {
        let pending = selected.filter(\.hasLegacyChanges).count
        if pending > 0 {
            return L10n.text("所选照片中有 %1$@ 张存在未保存的日期或定位修改，请先保存全部修改。", pending)
        }
        let unsupported = selected.filter { image in
            switch image.metadata.source {
            case .image(let url): !["jpg", "jpeg"].contains(url.pathExtension.lowercased())
            case .xmp: false
            default: true
            }
        }.count
        if unsupported > 0 {
            return L10n.text("所选照片中有 %1$@ 张不支持这些字段的编辑。请选择 JPEG 或已有 XMP 后重试。", unsupported)
        }
        return L10n.text("部分照片暂不可编辑，请检查读取或保存结果后重新读取元数据。")
    }

    private func label(for tag: MetadataTag) -> String { tag.displayName }

    private var sourceDescription: String {
        if selected.count == 1, let image = selected.first {
            switch image.metadata.source {
            case .image(let url):
                return L10n.text("图像文件：%1$@", url.lastPathComponent)
            case .xmp:
                return L10n.text("XMP 附属文件：%1$@",
                                 image.metadataInspectionURL?.lastPathComponent ?? image.name)
            case .photos:
                return L10n.text("照片图库项目暂不支持读取这些描述字段。")
            case .copy:
                return L10n.text("此条目没有可读取的本地文件。")
            }
        }
        let imageCount = selected.filter {
            if case .image = $0.metadata.source { return true }
            return false
        }.count
        let sidecarCount = selected.filter {
            if case .xmp = $0.metadata.source { return true }
            return false
        }.count
        return L10n.text("读取来源：图像 %1$@ 张，XMP %2$@ 张，非本地 %3$@ 张。",
                         imageCount, sidecarCount, selected.count - imageCount - sidecarCount)
    }

    private var readFailureCount: Int {
        selected.filter {
            guard let result = results[$0.id] else { return false }
            if case .failed = result { return true }
            return false
        }.count
    }

    private var legacyReadFailureCount: Int {
        selected.filter {
            guard case .values(_, let legacy) = results[$0.id] else { return false }
            return legacy == nil
        }.count
    }

    var body: some View {
        let images = selected
        let values = completeValues(for: images)
        return ScrollViewReader { proxy in
            VStack(spacing: 0) {
                inspectorHeader
                Divider()
                if images.isEmpty {
                    Text(L10n.text("Please select an image"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    inspectorTools(proxy: proxy)
                    Divider()
                    List(selection: $selectedFields) {
                        Group {
                            if loading && values == nil {
                                ProgressView()
                            } else if !loading && values == nil {
                                Text(L10n.text("部分照片无法读取描述元数据；暂不汇总字段。"))
                                    .foregroundStyle(.secondary)
                                if readFailureCount > 0 {
                                    Text(L10n.text("读取失败：%1$@ 张；请检查来源文件。", readFailureCount))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if advancedLoading && advanced.isEmpty { ProgressView() }
                            if advancedFailed {
                                Text(L10n.text("部分照片无法读取描述元数据；暂不汇总字段。"))
                            }
                            if values != nil || !advanced.isEmpty { advancedFields() }
                            if store.metadataSaveCancelled {
                                Text(L10n.text("已停止后续写入；尚未保存的草稿保留。"))
                                    .font(.caption).foregroundStyle(.orange)
                            }
                            if !store.saveInProgress, editableCreatorReadings == nil, values != nil {
                                Text(editUnavailableReason)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            creatorSaveSummary().selectionDisabled()
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    }
                    .listStyle(.inset)
                    .environment(\.defaultMinListRowHeight, 38)
                    .focusedValue(\.metadataFieldSelection, true)
                    .focusedValue(\.metadataFieldClipboard, fieldClipboardActions)
                    .onKeyPress(keys: ["c", "v"]) { press in
                        guard press.modifiers == .control else { return .ignored }
                        let action = press.key == "c" ? fieldClipboardActions.copy : fieldClipboardActions.paste
                        guard let action else { return .ignored }
                        action()
                        return .handled
                    }
                    .accessibilityIdentifier("metadataFieldsList")
                    if !selectedFields.isEmpty {
                        Divider()
                        metadataBatchFooter
                    }
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .onChange(of: selected.map(\.id)) { selectedFields = [] }
        .onChange(of: fieldQuery) { selectedFields = [] }
        .onChange(of: commonOnly) { selectedFields = [] }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            if scenePhase == .active { reloadIfFilesChanged() }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active { reloadIfFilesChanged() }
        }
        .onChange(of: store.saveInProgress) {
            if !store.saveInProgress { revision += 1 }
        }
        .alert(L10n.text("粘贴失败"), isPresented: $pasteFailed) {
            Button(L10n.text("好"), role: .cancel) {}
        } message: {
            Text(L10n.text("未修改任何字段。请检查剪贴板内容、目标字段格式，并确认来源文件没有变化。"))
        }
        .sheet(item: $batchEditor) { selection in
            MetadataWorkflowView(readings: selection.readings, initialTargets: selection.tags,
                                 excludedFieldCount: selection.excludedCount,
                                 initialBatchMode: selection.mode, initialBatchInput: selection.input)
        }
        .sheet(item: $workflowEditor) { selection in
            MetadataWorkflowView(readings: selection.readings, quickPreset: selectedWorkflowPreset)
        }
        .sheet(item: $creatorEditor) { selection in
            MetadataCreatorEditorView(readings: selection.readings, tag: selection.tag,
                                      initialMode: selection.mode, initialInput: selection.input)
        }
        .task(id: loadKey) {
            let currentKey = loadKey
            if !currentKey.hasSameSources(as: advancedReadKey) { advanced = [:] }
            advancedReadKey = currentKey
            guard !selected.isEmpty else { advancedLoading = false; advancedFailed = false; return }
            advancedLoading = true
            advancedFailed = false
            let requests = selected.map {
                MetadataInspectionRequest(id: $0.id, url: $0.metadataInspectionURL,
                                          creatorImageURL: $0.metadataCreatorImageURL)
            }
            let versions = selectedVersions
            // Cached selections render immediately; only cold selection changes are debounced.
            if !requests.allSatisfy({ metadataQueue.hasCached($0, kind: .additional) }) {
                try? await Task.sleep(for: .milliseconds(150))
            }
            guard !Task.isCancelled else { return }
            var values: [ImageData.ID: [String: String]] = [:]
            for request in requests {
                guard !Task.isCancelled else { return }
                if case .display(let tags) = await metadataQueue.read(request, kind: .additional) {
                    values[request.id] = tags
                }
            }
            guard !Task.isCancelled else { return }
            advancedLoading = false
            advancedFailed = values.count != requests.count || selectedVersions != versions
            if selectedVersions == versions {
                advanced = values
            }
        }
        .task(id: loadKey) {
            let requests = selected.map {
                MetadataInspectionRequest(id: $0.id, url: $0.metadataInspectionURL,
                                          creatorImageURL: $0.metadataCreatorImageURL)
            }
            let versions = selectedVersions
            observedVersions = versions
            let token = UUID()
            loadID = token
            let currentKey = loadKey
            if !currentKey.hasSameSources(as: editableReadKey) { results = [:] }
            editableReadKey = currentKey
            guard !requests.isEmpty else { loading = false; return }
            loading = true
            if !requests.allSatisfy({ metadataQueue.hasCached($0, kind: .editable) }) {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled else { return }

            var loaded: [ImageData.ID: MetadataInspectionRead] = [:]
            for request in requests {
                guard !Task.isCancelled else { return }
                if request.url == nil || request.creatorImageURL == nil { loaded[request.id] = .unsupported }
                else if case .editable(let snapshot, let legacy) = await metadataQueue.read(request, kind: .editable) {
                    loaded[request.id] = .values(snapshot, legacy)
                } else { loaded[request.id] = .failed }
            }
            guard !Task.isCancelled, loadID == token else { return }
            if selectedVersions != versions {
                revision += 1
                return
            }
            results = loaded
            loading = false
        }
    }

}

private extension MetadataListInspectorView {
    var savedMetadataPresets: [MetadataPreset] {
        ((try? JSONDecoder().decode([MetadataPreset].self, from: presetData)) ?? []).filter { $0.version == 1 }
    }

    var inspectorHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 12) {
                Text(L10n.text("元数据")).font(.headline)
                Spacer(minLength: 8)
                Menu {
                    if savedMetadataPresets.isEmpty {
                        Text(L10n.text("暂无预设"))
                    }
                    ForEach(savedMetadataPresets, id: \.name) { preset in
                        Button(preset.name) {
                            if let readings = editableCreatorReadings {
                                selectedWorkflowPreset = preset
                                workflowEditor = MetadataCreatorEditorSelection(readings: readings, tag: .creator)
                            }
                        }
                    }
                    Divider()
                    Button(L10n.text("编辑预设…")) {
                        if let readings = editableCreatorReadings {
                            selectedWorkflowPreset = nil
                            workflowEditor = MetadataCreatorEditorSelection(readings: readings, tag: .creator)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.fill").font(.system(size: 16))
                        Text(L10n.text("批量操作")).font(.system(size: 15, weight: .semibold))
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                    }.foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 9))
                        .opacity(editableCreatorReadings == nil ? 0.45 : 1)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .disabled(editableCreatorReadings == nil)
                .help(editableCreatorReadings == nil ? editUnavailableReason : L10n.text("批量操作"))
                .accessibilityIdentifier("metadataPresetButton")
            }
            if !selected.isEmpty {
                HStack(spacing: 8) {
                    Text(L10n.text("已选择 %1$@ 张照片", selected.count))
                    Text("·")
                    Text(loading || advancedLoading ? L10n.text("正在读取元数据…")
                         : readFailureCount > 0 || advancedFailed ? L10n.text("未能读取") : L10n.text("读取完成"))
                }.font(.caption).foregroundStyle(.secondary)
            }
            let pending = store.imageData.filter(\.hasPendingChanges).count
            if !selected.isEmpty || store.saveInProgress || pending > 0 {
                HStack(spacing: 8) {
                    if !selected.isEmpty {
                        Text(sourceDescription).lineLimit(1).truncationMode(.middle)
                            .textSelection(.enabled).help(sourceDescription)
                    }
                    Spacer(minLength: 0)
                    if store.saveInProgress {
                        Button(L10n.text("停止后续元数据写入")) {
                            store.send(.cancelMetadataSave, undoable: false)
                        }
                    } else {
                        if pending > 0 {
                            Text(L10n.text("全局待保存：%1$@ 项", pending)).foregroundStyle(.orange)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.orange.opacity(0.1), in: Capsule())
                        }
                    }
                }.font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.horizontal, 14).padding(.vertical, 12)
    }

    private var fieldScopePicker: some View {
        HStack(spacing: 2) {
            fieldScopeOption(L10n.text("常用字段"), common: true)
            fieldScopeOption(L10n.text("完整字段"), common: false)
        }
        .padding(3)
        .frame(minWidth: 208)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text("字段范围"))
        .accessibilityIdentifier("metadataFieldScope")
    }

    private func fieldScopeOption(_ title: String, common: Bool) -> some View {
        let selected = commonOnly == common
        return Button { commonOnly = common } label: {
            Text(title).font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .background(selected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 6))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(common ? "metadataCommonScope" : "metadataFullScope")
    }

    private var fieldSearch: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(L10n.text("搜索名称、标签或值"), text: $fieldQuery)
                .textFieldStyle(.plain)
                .accessibilityIdentifier("metadataFieldSearch")
            if !fieldQuery.isEmpty {
                Button { fieldQuery = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                    .accessibilityLabel(L10n.text("清除搜索"))
            }
        }
        .padding(.horizontal, 9).frame(height: 32)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
    }

    func inspectorTools(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    fieldScopePicker.fixedSize()
                    inspectorNavigation(proxy: proxy)
                }
                VStack(spacing: 8) {
                    fieldScopePicker
                    inspectorNavigation(proxy: proxy)
                }
            }
            fieldSearch
            if !fieldQuery.isEmpty {
                Text(L10n.text("搜索包含全部字段。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.horizontal, 14).padding(.vertical, 10)
    }

    func inspectorNavigation(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 10) {
            if !commonOnly || !fieldQuery.isEmpty {
                Menu(L10n.text("分组")) {
                    ForEach(MetadataDisplaySection.standard, id: \.name) { section in
                        Button(L10n.text(section.name)) { proxy.scrollTo(section.name, anchor: .top) }
                    }
                }.menuStyle(.borderedButton).help(L10n.text("跳转到分组"))
            }
            Spacer(minLength: 0)
            Button {
                metadataQueue.refresh(ids: Set(selected.map(\.id)))
                revision += 1
            } label: {
                Image(systemName: "arrow.clockwise").frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless).foregroundStyle(.secondary)
            .disabled(store.saveInProgress)
            .accessibilityLabel(L10n.text("重新读取元数据"))
            .help(L10n.text("重新读取元数据"))
            Button { showsEditingHelp.toggle() } label: {
                Image(systemName: "questionmark.circle").font(.system(size: 16))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless).foregroundStyle(.secondary)
            .accessibilityLabel(L10n.text("字段编辑帮助"))
            .help(L10n.text("字段编辑帮助"))
            .popover(isPresented: $showsEditingHelp) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.text("字段编辑帮助")).font(.headline)
                    Text(L10n.text("选择字段 → 编辑并预览 → 写入所有元数据"))
                    Text(L10n.text("单击选择，⌘ / Shift 多选；双击或点铅笔编辑。"))
                    Text(L10n.text("搜索包含全部字段。")).foregroundStyle(.secondary)
                }.font(.callout).padding(16).frame(width: 300)
            }
        }.controlSize(.regular)
    }

    var metadataBatchFooter: some View {
        HStack(spacing: 12) {
            Text(L10n.text("已选字段：%1$@", selectedFields.count))
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Menu(L10n.text("编辑所选字段")) { batchActions(selectedFields) }
                .menuStyle(.borderedButton)
                .disabled(batchTargets(selectedFields).isEmpty || editableCreatorReadings == nil)
                .accessibilityIdentifier("metadataBatchActions")
        }.controlSize(.regular).padding(.horizontal, 14).padding(.vertical, 10)
    }

    func batchTargets(_ identifiers: Set<String>) -> [MetadataTag] {
        MetadataTag.allCases.filter { tag in
            identifiers.contains(tag.rawValue) && (tag.supportsSidecar || selected.allSatisfy {
                if case .image = $0.metadata.source { true } else { false }
            })
        }
    }

    @ViewBuilder
    func batchActions(_ identifiers: Set<String>) -> some View {
        Button(L10n.text("复制其他字段的值…")) { openBatch(identifiers, mode: "copy") }
        Button(L10n.text("统一赋值…")) { openBatch(identifiers, mode: "set") }
        Button(L10n.text("粘贴到所选字段")) { pasteMetadataFields(identifiers) }
            .disabled(NSPasteboard.general.string(forType: .string)?.isEmpty != false)
        Button(L10n.text("清除所选字段…")) { openBatch(identifiers, mode: "clear") }
            .disabled(batchTargets(identifiers).contains(where: \.isFileTime))
    }

    func openBatch(_ identifiers: Set<String>, mode: String, input: String = "") {
        let tags = batchTargets(identifiers)
        guard !tags.isEmpty, let readings = editableCreatorReadings else { return }
        batchEditor = MetadataBatchEditorSelection(readings: readings, tags: tags,
                                                   excludedCount: identifiers.count - tags.count, mode: mode, input: input)
    }

    func field(_ label: String, tag: MetadataTag,
               values: [[MetadataTag: MetadataTagValue]], selected: [ImageData],
               readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)]?) -> some View {
        let label = tag.isDate ? MetadataFieldSourceLabel.label(label, tag: tag.rawValue) : label
        let summary = MetadataSelectionValue.summarize(values, tag: tag)
        let canEdit = readings != nil && (tag.supportsSidecar || !selected.contains {
            if case .xmp = $0.metadata.source { return true }; return false
        })
        let value = display(summary, tag: tag)
        let pending = selected.contains { $0.creatorDraft?.changes[tag] != nil }
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(pending ? Color.orange : Color.primary)
                Text(tag.rawValue).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
            }.frame(minWidth: 140, idealWidth: 190, maxWidth: 240, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                metadataValue(value, isDate: tag.isDate,
                              color: pending ? .orange : summary == .absent ? .secondary : .primary)
                if tag == .creator { creatorCompatibility(values: values) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if pending {
                Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(.orange)
                    .accessibilityLabel(L10n.text("待保存")).help(L10n.text("待保存"))
            }
            if canEdit {
                Button {
                    if let readings { creatorEditor = MetadataCreatorEditorSelection(readings: readings, tag: tag) }
                } label: {
                    Image(systemName: "pencil").font(.system(size: 12)).frame(width: 24, height: 26)
                }
                .buttonStyle(.borderless)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel(L10n.text("编辑元数据…") + " · " + label)
                .help(L10n.text("编辑元数据…"))
            } else {
                Image(systemName: "lock").font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(width: 24).accessibilityLabel(L10n.text("只读")).help(L10n.text("只读"))
            }
        }
        .frame(minHeight: 40)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowSeparator(.visible)
        .listRowSeparatorTint(Color(nsColor: .separatorColor))
        .contentShape(Rectangle())
        .tag(tag.rawValue)
        .onTapGesture(count: 2) {
            if canEdit, let readings { creatorEditor = MetadataCreatorEditorSelection(readings: readings, tag: tag) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label + " · " + tag.rawValue)
        .accessibilityValue(value)
        .accessibilityIdentifier("metadataField." + tag.rawValue)
        .contextMenu {
            Button(L10n.text("Copy")) {
                if let text = rawCopyValue(summary) { copyMetadataText(text) }
            }.disabled(rawCopyValue(summary) == nil)
            batchActions(selectedFields.contains(tag.rawValue) ? selectedFields : [tag.rawValue])
                .disabled(readings == nil)
            Divider()
            Group {
                Button(L10n.text("编辑元数据…")) {
                    if let readings { creatorEditor = MetadataCreatorEditorSelection(readings: readings, tag: tag) }
                }
                if !tag.isList || tag == .creator {
                    Button(L10n.text("仅补空值")) {
                        if let readings {
                            creatorEditor = MetadataCreatorEditorSelection(readings: readings, tag: tag, mode: .fillMissing)
                        }
                    }
                }
                if tag.isList && tag != .creator {
                    Button(L10n.text("追加关键词")) {
                        if let readings {
                            creatorEditor = MetadataCreatorEditorSelection(readings: readings, tag: tag, mode: .append, input: "")
                        }
                    }
                    Button(L10n.text("移除指定关键词")) {
                        if let readings {
                            creatorEditor = MetadataCreatorEditorSelection(readings: readings, tag: tag, mode: .removeKeywords, input: "")
                        }
                    }
                }
                if tag.isDate {
                    Button(L10n.text("时间偏移")) {
                        if let readings {
                            creatorEditor = MetadataCreatorEditorSelection(readings: readings, tag: tag, mode: .offset)
                        }
                    }
                }
                Button(L10n.text("清除字段")) {
                    if let readings {
                        creatorEditor = MetadataCreatorEditorSelection(readings: readings, tag: tag, mode: .remove)
                    }
                }.disabled(tag.isFileTime)
            }.disabled(!canEdit)
            Divider()
            Button(L10n.text("复制显示值")) { copyMetadataText(value) }
                .disabled(rawCopyValue(summary) == nil)
            Button(L10n.text("复制原值")) {
                if let text = rawCopyValue(summary) { copyMetadataText(text) }
            }.disabled(rawCopyValue(summary) == nil)
            Button(L10n.text("复制规范标签")) { copyMetadataText(tag.rawValue) }
        }
    }

    // ponytail: extras use tag-name grouping; promote fields to the fixed schema when exact grouping is needed.
    func advancedGroup(_ tag: String) -> String {
        let canonical = tag.split(separator: "/").last.map(String.init) ?? tag
        let name = canonical.split(separator: ":").last.map(String.init) ?? canonical
        if canonical.hasPrefix("File:") || canonical.hasPrefix("System:") { return "File" }
        if name.hasPrefix("GPS") { return "GPS Coordinates" }
        if name.contains("Date") || name.contains("Time") { return "Date and Time" }
        if name.contains("Lens") { return "Lens" }
        if ["Make", "Model", "SerialNumber", "CameraSerialNumber"].contains(name) { return "Camera" }
        if ["Artist", "Creator", "By-line", "By-lineTitle", "Contact"].contains(name) { return "General" }
        if ["City", "State", "Province-State", "Location", "Country", "CountryCode", "Sub-location",
            "Country-PrimaryLocationName", "Country-PrimaryLocationCode"].contains(name) { return "Location Address" }
        if name.contains("Resolution") || name.contains("Width") || name.contains("Height") || name == "Orientation" {
            return "Dimension And Resolution"
        }
        if ["ISO", "FNumber", "ApertureValue", "ShutterSpeedValue", "FocalLength", "FocalLengthIn35mmFormat",
            "ExposureCompensation", "Flash"].contains(name) { return "Camera Settings" }
        if ["ColorSpace", "MaxApertureValue", "ExposureMode", "ExposureProgram", "ExposureTime",
            "MeteringMode", "WhiteBalance", "Saturation", "Sharpness"].contains(name) { return "Advanced Settings" }
        return "Information"
    }

    func advancedLabel(_ tag: String) -> String {
        let name = tag.split(separator: ":").last.map(String.init) ?? tag
        let labels: [String: String] = [
            "FileName": "Metadata field: FileName",
            "FilePath": "Metadata field: FilePath",
            "MDItemUserTags": "Metadata field: MDItemUserTags",
            "Artist": "Metadata field: Artist",
            "By-line": "Metadata field: By-line",
            "By-lineTitle": "Metadata field: By-lineTitle",
            "Contact": "Metadata field: Contact",
            "ImageDescription": "Metadata field: ImageDescription",
            "Copyright": "Metadata field: Copyright",
            "Software": "Metadata field: Software",
            "UserComment": "Metadata field: UserComment",
            "Headline": "Metadata field: Headline",
            "Caption-Abstract": "Metadata field: Caption-Abstract",
            "ObjectName": "Metadata field: ObjectName",
            "Keywords": "Metadata field: Keywords",
            "Subject": "Metadata field: Subject",
            "Keyword": "Metadata field: Keyword",
            "FileCreateDate": "Metadata field: FileCreateDate",
            "FileModifyDate": "Metadata field: FileModifyDate",
            "DateTimeOriginal": "Metadata field: DateTimeOriginal",
            "CreateDate": "Metadata field: CreateDate",
            "ModifyDate": "Metadata field: ModifyDate",
            "DateCreated": "Metadata field: DateCreated",
            "TimeCreated": "Metadata field: TimeCreated",
            "Make": "Metadata field: Make",
            "Model": "Metadata field: Model",
            "SerialNumber": "Metadata field: SerialNumber",
            "ISO": "Metadata field: ISO",
            "FNumber": "Metadata field: FNumber",
            "ApertureValue": "Metadata field: ApertureValue",
            "ShutterSpeedValue": "Metadata field: ShutterSpeedValue",
            "FocalLength": "Metadata field: FocalLength",
            "FocalLengthIn35mmFormat": "Metadata field: FocalLengthIn35mmFormat",
            "ExposureCompensation": "Metadata field: ExposureCompensation",
            "Flash": "Metadata field: Flash",
            "ColorSpace": "Metadata field: ColorSpace",
            "MaxApertureValue": "Metadata field: MaxApertureValue",
            "ExposureMode": "Metadata field: ExposureMode",
            "ExposureProgram": "Metadata field: ExposureProgram",
            "ExposureTime": "Metadata field: ExposureTime",
            "MeteringMode": "Metadata field: MeteringMode",
            "WhiteBalance": "Metadata field: WhiteBalance",
            "Saturation": "Metadata field: Saturation",
            "Sharpness": "Metadata field: Sharpness",
            "LensMake": "Metadata field: LensMake",
            "Lens": "Metadata field: Lens",
            "LensModel": "Metadata field: LensModel",
            "LensSerialNumber": "Metadata field: LensSerialNumber",
            "LensInfo": "Metadata field: LensInfo",
            "Orientation": "Metadata field: Orientation",
            "ImageWidth": "Metadata field: ImageWidth",
            "ImageHeight": "Metadata field: ImageHeight",
            "ExifImageWidth": "Metadata field: ExifImageWidth",
            "ExifImageHeight": "Metadata field: ExifImageHeight",
            "XResolution": "Metadata field: XResolution",
            "YResolution": "Metadata field: YResolution",
            "GPSLatitude": "Metadata field: GPSLatitude",
            "GPSLatitudeRef": "Metadata field: GPSLatitudeRef",
            "GPSLongitude": "Metadata field: GPSLongitude",
            "GPSLongitudeRef": "Metadata field: GPSLongitudeRef",
            "GPSAltitude": "Metadata field: GPSAltitude",
            "GPSAltitudeRef": "Metadata field: GPSAltitudeRef",
            "GPSDateStamp": "Metadata field: GPSDateStamp",
            "GPSTimeStamp": "Metadata field: GPSTimeStamp",
            "City": "Metadata field: City",
            "Province-State": "Metadata field: Province-State",
            "Sub-location": "Metadata field: Sub-location",
            "Country-PrimaryLocationName": "Metadata field: Country-PrimaryLocationName",
            "Country-PrimaryLocationCode": "Metadata field: Country-PrimaryLocationCode"
        ]
        let label = labels[name].map { L10n.text($0) } ?? name
        return name.contains("Date") || name.contains("Time")
            ? MetadataFieldSourceLabel.label(label, tag: tag) : label
    }

    @ViewBuilder
    func advancedFields() -> some View {
        let selected = self.selected
        let completeValues = self.completeValues
        let readings = editableCreatorReadings
        let mappedTags = self.mappedTags
        let matchesQuery: (String, String) -> Bool = { tag, group in
            self.matchesQuery(tag, group: group, selected: selected, completeValues: completeValues)
        }
        let sections = MetadataDisplaySection.standard
        let referenceTags = sections.flatMap(\.tags)
        let commonKeys = Set(MetadataTag.allCases.map { $0.rawValue.replacingOccurrences(of: "-x-default", with: "") })
        let readOnlyExtras = !fieldQuery.isEmpty ? Set(advanced.values.flatMap { $0.keys }).filter { key in
            !commonKeys.contains(key) && !referenceTags.contains { tag in
                MetadataDisplaySection.value(for: tag, in: [key: "present"]) != nil
            } && matchesQuery(key, advancedGroup(key))
        }.sorted() : []
        ForEach(sections, id: \.name) { section in
            let tags = section.tags.filter { matchesQuery($0, section.name) }
            let extraTags = readOnlyExtras.filter { advancedGroup($0) == section.name }
            let editableTags = MetadataTag.allCases.filter { !mappedTags.contains($0)
                && advancedGroup($0.rawValue) == section.name && matchesQuery($0.rawValue, section.name) }
            if !tags.isEmpty || !editableTags.isEmpty || !extraTags.isEmpty {
                Section {
                    Group {
                        ForEach(tags, id: \.self) { tag in
                            let values = selected.map { MetadataDisplaySection.value(for: tag, in: advanced[$0.id] ?? [:]) }
                            if let editable = mappedTag(tag), let completeValues,
                               editable.supportsSidecar || !selected.contains(where: { if case .xmp = $0.metadata.source { true } else { false } }) {
                                field(advancedLabel(tag), tag: editable, values: completeValues, selected: selected, readings: readings)
                                if selected.contains(where: { MetadataDisplaySection.sourceKeys(for: tag, in: advanced[$0.id] ?? [:]).count > 1 }) {
                                    inspectionRow(tag, values: values, selected: selected)
                                }
                            } else { inspectionRow(tag, values: values, selected: selected) }
                        }
                        if let completeValues {
                            ForEach(editableTags, id: \.rawValue) { tag in
                                field(label(for: tag), tag: tag, values: completeValues, selected: selected, readings: readings)
                            }
                        }
                        ForEach(extraTags, id: \.self) { tag in
                            inspectionRow(tag, values: selected.map { advanced[$0.id]?[tag] }, selected: selected)
                        }
                    }
                } header: {
                    Text(L10n.text(section.name))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color(nsColor: .separatorColor).opacity(0.12))
                        .id(section.name).selectionDisabled()
                }
            }
        }
    }

    var mappedTags: Set<MetadataTag> { Set(MetadataDisplaySection.standard.flatMap(\.tags).compactMap(mappedTag)) }

    func mappedTag(_ tag: String) -> MetadataTag? {
        if tag == "EXIF:DateTimeOriginal" { return .captureDate }
        if tag == "EXIF:CreateDate" { return .exifCreateDate }
        if tag == "EXIF:ModifyDate" { return .exifModifyDate }
        if tag == "XMP:Subject" { return .subject }
        if tag == "File:FileCreateDate" { return .fileCreateDate }
        if tag == "File:FileModifyDate" { return .fileModifyDate }
        if tag == "XMP:CreateDate" { return .sidecarDate }
        if tag == "XMP:ModifyDate" { return .dateModified }
        if tag == "XMP:Lens" { return .lens }
        if tag == "XMP:FocalLength" { return .focalLength }
        return MetadataTag.allCases.first { writable in
            !writable.supportsSidecar && tag.split(separator: ":").last == writable.rawValue.split(separator: ":").last
                && (tag.hasPrefix("EXIF:") ? writable.rawValue.hasPrefix("IFD0:") || writable.rawValue.hasPrefix("ExifIFD:")
                    : tag.hasPrefix("IPTC:") && writable.rawValue.hasPrefix("IPTC:"))
        }
    }

    func matchesQuery(_ tag: String, group: String, selected: [ImageData],
                      completeValues: [[MetadataTag: MetadataTagValue]]?) -> Bool {
        let editable = mappedTag(tag) ?? MetadataTag(rawValue: tag)
        return MetadataFieldFilter.matches(query: fieldQuery, presentOnly: false, editedOnly: false,
            commonOnly: commonOnly, isCommon: MetadataFieldFilter.commonTags.contains(editable?.rawValue ?? tag),
            names: [tag, editable?.rawValue ?? "", L10n.text(group), advancedLabel(tag)],
            hasEdits: selected.contains { image in
                editable.map { image.creatorDraft?.changes[$0] != nil } ?? false
            }, values: {
                let isReferenceField = MetadataDisplaySection.standard.contains { $0.tags.contains(tag) }
                return selected.enumerated().map { index, image in
                    if let editable, let completeValues,
                       editable.supportsSidecar || { if case .image = image.metadata.source { true } else { false } }() {
                        switch completeValues[index][editable] {
                        case .text(let text): return text
                        case .list(let words): return words.joined(separator: "\n")
                        case nil: return nil
                        }
                    }
                    return MetadataDisplaySection.value(for: tag, in: advanced[image.id] ?? [:], exactSource: !isReferenceField)
                }
            })
    }

    func inspectionRow(_ tag: String, values: [String?], selected: [ImageData]) -> some View {
        let summary = MetadataDisplaySection.summarize(values)
        let name = tag.split(separator: ":").last.map(String.init) ?? tag
        let isDate = name.contains("Date") || name.contains("Time")
        let text: String
        switch summary {
        case .absent: text = L10n.text("未填写")
        case .uniform(let value):
            if isDate { text = MetadataInspectorDateDisplay.text(value) ?? value }
            else if ["ExposureTime", "ShutterSpeedValue"].contains(tag.split(separator: ":").last.map(String.init) ?? tag) {
                text = MetadataExposureDisplay.text(value) ?? value
            } else { text = value }
        case .mixed(let present, let total): text = L10n.text("多个值（%1$@/%2$@ 张有值）", present, total)
        }
        let available = selected.allSatisfy { advanced[$0.id] != nil }
        let visibleText = available ? text : (advancedFailed ? L10n.text("未能读取") : L10n.text("正在读取元数据…"))
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(advancedLabel(tag)).font(.system(size: 13, weight: .medium))
                Text(tag).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
            }.frame(minWidth: 140, idealWidth: 190, maxWidth: 240, alignment: .leading)
            metadataValue(visibleText, isDate: isDate, color: summary == .absent ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "lock").font(.system(size: 11)).foregroundStyle(.secondary)
                .frame(width: 24).accessibilityLabel(L10n.text("只读"))
        }
        .frame(minHeight: 40)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowSeparator(.visible)
        .listRowSeparatorTint(Color(nsColor: .separatorColor))
        .tag("display:" + tag)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(advancedLabel(tag) + " · " + tag)
        .accessibilityValue(visibleText)
        .help(L10n.text("此字段为结构或计算信息，尚未接入可靠写回；GPS 请在地图定位中编辑。"))
        .contextMenu {
            if selectedFields.contains("display:" + tag), !batchTargets(selectedFields).isEmpty {
                batchActions(selectedFields)
                Divider()
            }
            Button(L10n.text("复制显示值")) {
                if case .uniform = summary { copyMetadataText(text) }
            }.disabled({ if case .uniform = summary { false } else { true } }())
            Button(L10n.text("复制规范标签")) { copyMetadataText(tag) }
        }
    }

    @ViewBuilder
    func creatorSaveSummary() -> some View {
        let completed = selected.filter {
            store.creatorSaveResults[$0.id] == .saved || store.creatorSaveResults[$0.id] == .unchanged
        }.count
        let failed = selected.filter {
            guard let result = store.creatorSaveResults[$0.id] else { return false }
            return result != .saved && result != .unchanged
        }
        if completed > 0 || !failed.isEmpty {
            Text(L10n.text("元数据保存：成功 %1$@ 张，待处理 %2$@ 张。", completed, failed.count))
                .font(.caption).foregroundStyle(.secondary)
            ForEach(failed.prefix(20)) { image in
                VStack(alignment: .leading, spacing: 3) {
                    Text(image.name).font(.caption.weight(.medium))
                    if let result = store.creatorSaveResults[image.id] {
                        Text(creatorSaveMessage(result)).font(.caption).foregroundStyle(.orange)
                    }
                    if image.creatorDraft != nil {
                        Button(L10n.text("放弃该元数据草稿")) {
                            store.send(.creatorDraftRemoved(image.id), description: L10n.text("放弃该元数据草稿"))
                            revision += 1
                        }.disabled(store.saveInProgress)
                    }
                }
            }
            if failed.count > 20 {
                Text(L10n.text("另有 %1$@ 张待处理", failed.count - 20))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    func creatorSaveMessage(_ result: MetadataCreatorSaveResult) -> String {
        switch result {
        case .saved, .unchanged: ""
        case .staleSource: L10n.text("源文件已变化；请放弃草稿并重新读取。")
        case .preparationFailed: L10n.text("备份或写入准备失败；请检查备份目录。")
        case .failed: L10n.text("元数据写入失败；请检查文件权限。")
        case .resultUnknown: L10n.text("元数据写入结果未确认；请先检查磁盘文件，不能直接重试。")
        }
    }

    @ViewBuilder
    func creatorCompatibility(values: [[MetadataTag: MetadataTagValue]]) -> some View {
        if let legacy = completeLegacyValues {
            let conflicts = zip(values, legacy).filter {
                MetadataSelectionValue.creatorSourcesConflict(xmp: $0[.creator], legacy: $1)
            }.count
            if conflicts > 0 {
                Text(L10n.text("作者来源冲突：%1$@ 张。", conflicts))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } else if legacyReadFailureCount > 0 {
            Text(L10n.text("兼容作者来源读取失败：%1$@ 张。", legacyReadFailureCount))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var selectedFieldCopyText: String? {
        guard selectedFields.count == 1, let identifier = selectedFields.first else { return nil }
        if let tag = MetadataTag(rawValue: identifier), let values = completeValues {
            return rawCopyValue(MetadataSelectionValue.summarize(values, tag: tag))
        }
        guard identifier.hasPrefix("display:"), selected.allSatisfy({ advanced[$0.id] != nil }) else { return nil }
        let tag = String(identifier.dropFirst("display:".count))
        let reference = MetadataDisplaySection.standard.contains { $0.tags.contains(tag) }
        let values = selected.map { MetadataDisplaySection.value(for: tag, in: advanced[$0.id] ?? [:], exactSource: !reference) }
        if case .uniform(let text) = MetadataDisplaySection.summarize(values) { return text }
        return nil
    }

    private var fieldClipboardActions: MetadataFieldClipboardActions {
        MetadataFieldClipboardActions(
            copy: selectedFieldCopyText.map { text in { copyMetadataText(text) } },
            paste: editableCreatorReadings != nil && !batchTargets(selectedFields).isEmpty
                ? { pasteMetadataFields(selectedFields) } : nil)
    }

    private func pasteMetadataFields(_ identifiers: Set<String>) {
        guard let readings = editableCreatorReadings,
              let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        do {
            let operations = try MetadataFieldClipboard.operations(text: text, targets: batchTargets(identifiers))
            let plan = try MetadataWorkflowPreview.prepare(readings, operations: operations)
            guard plan.items.allSatisfy({ MetadataInspectionFileVersion.read($0.target) == $0.version }) else {
                throw MetadataCreatorPlanError.sourceChanged
            }
            store.send(.creatorDraftApplied(plan.items), description: L10n.text("粘贴到所选字段"))
        } catch { pasteFailed = true }
    }

    func copyMetadataText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func rawCopyValue(_ summary: MetadataSelectionValue) -> String? {
        switch summary {
        case .uniform(.text(let text)): text
        case .uniform(.list(let values)): values.joined(separator: "\n")
        default: nil
        }
    }

    @ViewBuilder
    private func metadataValue(_ value: String, isDate: Bool, color: Color) -> some View {
        if isDate, let newline = value.firstIndex(of: "\n") {
            VStack(alignment: .leading, spacing: 3) {
                Text(String(value[..<newline]))
                    .font(.system(size: 15, design: .monospaced)).monospacedDigit()
                    .foregroundStyle(color).lineLimit(1)
                Text(String(value[value.index(after: newline)...]))
                    .font(.system(size: 11, design: .monospaced)).monospacedDigit()
                    .foregroundStyle(.secondary).lineLimit(1)
            }.help(value)
        } else {
            Text(value).font(.system(size: 13, design: isDate ? .monospaced : .default)).monospacedDigit()
                .lineLimit(2).help(value).foregroundStyle(color)
        }
    }

    func display(_ summary: MetadataSelectionValue, tag: MetadataTag) -> String {
        if case .uniform(.text(let value)) = summary {
            if tag.isDate { return MetadataInspectorDateDisplay.text(value) ?? value }
            if [.exposureTime, .exifExposureTime, .exifShutter].contains(tag) {
                return MetadataExposureDisplay.text(value) ?? value
            }
            if let choices = tag.numericChoices, let number = Int(value), let choice = choices.first(where: { $0.0 == number }) { return choice.1 }
            if tag.numericUnit == "f/" { return "f / " + value }
            if !tag.numericUnit.isEmpty { return value + " " + tag.numericUnit }
        }
        return display(summary)
    }

    func display(_ summary: MetadataSelectionValue) -> String {
        switch summary {
        case .unselected: "—"
        case .absent: L10n.text("未填写")
        case .uniform(.text(let value)): value
        case .uniform(.list(let values)): values.joined(separator: ", ")
        case .mixed(let present, let total):
            L10n.text("多个值（%1$@/%2$@ 张有值）", present, total)
        }
    }
}

struct MetadataFieldClipboardActions {
    let copy: (() -> Void)?
    let paste: (() -> Void)?
}

private struct MetadataFieldClipboardKey: FocusedValueKey {
    typealias Value = MetadataFieldClipboardActions
}

private struct MetadataFieldSelectionKey: FocusedValueKey {
    typealias Value = Bool
}

extension FocusedValues {
    var metadataFieldClipboard: MetadataFieldClipboardActions? {
        get { self[MetadataFieldClipboardKey.self] }
        set { self[MetadataFieldClipboardKey.self] = newValue }
    }

    var metadataFieldSelection: Bool? {
        get { self[MetadataFieldSelectionKey.self] }
        set { self[MetadataFieldSelectionKey.self] = newValue }
    }
}

extension MetadataListInspectorView {
    private func reloadIfFilesChanged() {
        guard !store.saveInProgress, !checkingVersions else { return }
        let key = loadKey
        let requests = selected.map {
            MetadataInspectionRequest(id: $0.id, url: $0.metadataInspectionURL,
                                      creatorImageURL: $0.metadataCreatorImageURL)
        }
        checkingVersions = true
        Task { @MainActor in
            defer { checkingVersions = false }
            let versions = await Task.detached(priority: .utility) { requests.flatMap(\.versions) }.value
            guard !store.saveInProgress, key == loadKey, versions != observedVersions else { return }
            revision += 1
        }
    }

}
