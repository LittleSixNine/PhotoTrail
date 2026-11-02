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
    @Binding var editSession: MetadataBatchEditSession?
    @Binding var ruleSession: MetadataBatchEditSession?
    var visiblePhotoIDs: Set<ImageData.ID>?

    init(editSession: Binding<MetadataBatchEditSession?>, ruleSession: Binding<MetadataBatchEditSession?>,
         visiblePhotoIDs: Set<ImageData.ID>? = nil) {
        _editSession = editSession
        _ruleSession = ruleSession
        self.visiblePhotoIDs = visiblePhotoIDs
    }
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
    @AppStorage(MetadataFieldFilter.commonFieldsKey) private var commonFieldsData = Data()
    @State private var commonFieldTags = MetadataFieldFilter.commonTags(from: UserDefaults.standard.data(forKey: MetadataFieldFilter.commonFieldsKey) ?? Data())

    @AppStorage(SettingsPreferences.metadataTextSizeKey) private var textSize = 0
    @AppStorage(SettingsPreferences.metadataSpacingKey) private var rowSpacing = 0
    @AppStorage(SettingsPreferences.metadataTagNamesKey) private var showsTagNames = true
    private var fontDelta: CGFloat { CGFloat(max(-1, min(1, textSize))) * 2 }
    private var rowPadding: CGFloat { rowSpacing < 0 ? 2 : rowSpacing > 0 ? 10 : 6 }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingBatch = false
    @AppStorage("PhotoTrail.MetadataPresetShortcuts") private var presetShortcutData = Data()
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
    @State private var valueDistribution: MetadataCreatorEditorSelection?
    @State private var pasteFailed = false
    @State private var pasteSkipped: [String] = []
    @State private var fieldColumnWidth: CGFloat = 190

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
            guard !image.hasLegacyChanges,
                  store.creatorSaveResults[image.id] != .resultUnknown,
                  case .values(let snapshot, _) = results[image.id] else { return nil }
            readings.append((image, snapshot))
        }
        guard readings.contains(where: { $0.image.supportsMetadataEditing }) else { return nil }
        return readings
    }

    private var editUnavailableReason: String {
        let pending = selected.filter(\.hasLegacyChanges).count
        if pending > 0 {
            return L10n.text("所选照片中有 %1$@ 张存在未保存的日期或定位修改，请先保存全部修改。", pending)
        }
        let unsupported = selected.filter { !$0.supportsMetadataEditing }.count
        if unsupported > 0 {
            return L10n.text("所选照片中有 %1$@ 张不支持这些字段的编辑。请选择 JPEG、支持的 RAW 或已有 XMP 后重试。", unsupported)
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
        inspectorContent
            .allowsHitTesting(!showingBatch)
            .accessibilityHidden(showingBatch)
            .overlay {
                if showingBatch, let ruleSession {
                    MetadataBatchEditView(session: ruleSession, visiblePhotoIDs: visiblePhotoIDs, close: {
                        showingBatch = false
                        if ruleSession.application.applied || !ruleSession.hasInput { self.ruleSession = nil }
                    })
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12))
                    .shadow(color: .black.opacity(0.12), radius: 8, x: -3)
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                }
            }
            .clipped()
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: showingBatch)
            .onAppear { showingBatch = ruleSession != nil }
            .onChange(of: ruleSession?.id) { showingBatch = ruleSession != nil }
    }

}

private extension MetadataListInspectorView {
    var inspectorContent: some View {
        let images = selected
        let values = completeValues(for: images)
        return ScrollViewReader { proxy in
            VStack(spacing: 0) {
                inspectorHeader(readings: editableCreatorReadings)
                if let session = editSession, session.inline, session.hasInput,
                   session.photoIDs != Set(selected.map(\.id)) {
                    HStack {
                        Text(L10n.text("还有未应用的字段输入，请返回检查。"))
                        Button(L10n.text("继续编辑")) { store.send(.selectionChanged(session.photoIDs), undoable: false) }
                        Button(L10n.text("放弃输入并关闭")) { session.discardInput(); editSession = nil }
                    }.font(.caption).padding(10)
                }
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
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            fieldColumnWidth = min(240, max(140, (width - 68) * 0.4))
        }
        .onChange(of: selected.map(\.id)) { selectedFields = [] }
        .onChange(of: fieldQuery) { selectedFields = [] }
        .onChange(of: commonOnly) { selectedFields = [] }
        .onChange(of: commonFieldsData) {
            commonFieldTags = MetadataFieldFilter.commonTags(from: commonFieldsData)
            selectedFields = []
        }
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
        .alert(L10n.text("已跳过不支持的文件或字段"), isPresented: Binding(
            get: { !pasteSkipped.isEmpty }, set: { if !$0 { pasteSkipped = [] } })) {
            Button(L10n.text("好"), role: .cancel) {}
        } message: { Text(pasteSkipped.joined(separator: "\n")) }
        .sheet(item: $batchEditor) { selection in
            MetadataWorkflowView(readings: selection.readings, initialTargets: selection.tags,
                                 excludedFieldCount: selection.excludedCount,
                                 initialBatchMode: selection.mode, initialBatchInput: selection.input)
        }
        .sheet(item: $workflowEditor) { selection in
            MetadataWorkflowView(readings: selection.readings, quickPreset: selectedWorkflowPreset, initialTab: selection.input ?? "actions")
        }
        .popover(item: $valueDistribution) { selection in
            MetadataValueDistributionView(tag: selection.tag, readings: selection.readings, select: { ids in
                valueDistribution = nil
                store.send(.selectionChanged(ids), undoable: false)
            })
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

    func inspectorHeader(readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)]?) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 12) {
                Text(L10n.text("元数据")).font(.headline)
                Spacer(minLength: 8)
                Menu {
                    Button(L10n.text("高级操作…")) { openWorkflow(readings, tab: "actions") }
                    Button(L10n.text("管理预设…")) { openWorkflow(readings, tab: "presets") }
                    Button(L10n.text("比较与交换")) { openWorkflow(readings, tab: "exchange") }
                } label: { Image(systemName: "ellipsis.circle").font(.title3) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .disabled(readings == nil)
                .accessibilityLabel(L10n.text("更多元数据工具"))
                .accessibilityIdentifier("metadataMoreTools")
            }
            if !selected.isEmpty {
                HStack(spacing: 8) {
                    Text(L10n.text("已选择 %1$@ 张（当前显示 %2$@ 张）", selected.count, selected.filter { visiblePhotoIDs?.contains($0.id) ?? true }.count))
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
            batchEntryCards(readings: readings)
        }.padding(.horizontal, 14).padding(.vertical, 12)
    }

    private var shortcutNames: [String] {
        MetadataPresetShortcuts.names(in: savedMetadataPresets, data: presetShortcutData)
    }

    private func batchEntryCards(readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)]?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    if let readings { startBatch(readings) }
                } label: {
                    batchEntryLabel("复杂批量规则", subtitle: "组合多个修改项", icon: "slider.horizontal.3", featured: false)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("metadataBatchStart")
                Menu {
                    ForEach(savedMetadataPresets, id: \.name) { preset in
                        Button(preset.name) { openPreset(preset, readings: readings) }
                    }
                    if savedMetadataPresets.isEmpty { Text(L10n.text("暂无预设")) }
                    Divider()
                    Menu(L10n.text("选择常用预设")) {
                        ForEach(savedMetadataPresets, id: \.name) { preset in
                            Toggle(preset.name, isOn: Binding(get: { shortcutNames.contains(preset.name) }, set: { enabled in
                                presetShortcutData = MetadataPresetShortcuts.updating(preset.name, enabled: enabled,
                                    in: savedMetadataPresets, data: presetShortcutData)
                            }))
                        }
                    }.disabled(savedMetadataPresets.isEmpty)
                    Button(L10n.text("管理预设…")) { openWorkflow(readings, tab: "presets") }
                } label: {
                    batchEntryLabel("应用批量预设", subtitle: "快速调用已存预设", icon: "bolt.fill", featured: true)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden)
                .accessibilityIdentifier("metadataPresetButton")
            }
            .disabled(readings == nil)
            if !shortcutNames.isEmpty {
                HStack(spacing: 8) {
                    Text(L10n.text("常用预设")).font(.caption).foregroundStyle(.secondary)
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(shortcutNames, id: \.self) { name in
                                Button {
                                    if let preset = savedMetadataPresets.first(where: { $0.name == name }) {
                                        openPreset(preset, readings: readings)
                                    }
                                } label: {
                                    Label(name, systemImage: "bolt.fill").font(.caption)
                                        .lineLimit(1).padding(.horizontal, 9).padding(.vertical, 5)
                                        .background(Color.accentColor.opacity(0.08), in: Capsule())
                                }
                                .buttonStyle(.plain).foregroundStyle(Color.accentColor)
                                .help(name)
                                .accessibilityIdentifier("metadataPresetShortcut-" + name)
                            }
                        }
                    }.scrollIndicators(.hidden)
                }
                .disabled(readings == nil)
            }
        }.padding(.top, 5)
    }

    private func batchEntryLabel(_ title: String, subtitle: String, icon: String, featured: Bool) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 20, weight: .medium)).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.text(title)).font(.system(size: 14, weight: .semibold))
                Text(L10n.text(subtitle)).font(.system(size: 11)).foregroundStyle(.secondary)
            }.fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: featured ? "chevron.down" : "chevron.right").font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .foregroundStyle(Color.accentColor)
        .background(Color.accentColor.opacity(featured ? 0.12 : 0.025), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.accentColor.opacity(featured ? 0.28 : 0.5)))
        .contentShape(RoundedRectangle(cornerRadius: 9))
    }

    private func openPreset(_ preset: MetadataPreset,
                            readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)]?) {
        guard let readings else { return }
        Task { @MainActor in
            if let previous = editSession, previous.inline {
                guard await previous.finishInline(in: store) else { return }
            }
            let current = readings.compactMap { reading -> (image: ImageData, snapshot: MetadataInspectionSnapshot)? in
                guard let image = store.state.imageData.first(where: { $0.id == reading.image.id }) else { return nil }
                return (image, reading.snapshot)
            }
            guard current.count == readings.count else { return }
            selectedWorkflowPreset = preset
            workflowEditor = MetadataCreatorEditorSelection(readings: current, tag: .creator)
        }
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
                    Text(L10n.text("编辑 → 应用 → 保存照片"))
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
            Button(L10n.text("编辑所选字段")) {
                let tags = batchTargets(selectedFields)
                guard let readings = editableCreatorReadings else { return }
                startBatch(readings, tags: tags)
            }
            .disabled(batchTargets(selectedFields).isEmpty || editableCreatorReadings == nil)
            .accessibilityIdentifier("metadataEditSelected")
            Menu { batchActions(selectedFields) } label: {
                Image(systemName: "ellipsis.circle")
            }
                .accessibilityLabel(L10n.text("字段操作"))
                .menuStyle(.borderedButton)
                .disabled(batchTargets(selectedFields).isEmpty || editableCreatorReadings == nil)
                .accessibilityIdentifier("metadataBatchActions")
        }.controlSize(.regular).padding(.horizontal, 14).padding(.vertical, 10)
    }

    func batchTargets(_ identifiers: Set<String>) -> [MetadataTag] {
        MetadataTag.allCases.filter { tag in
            identifiers.contains(tag.rawValue) && selected.contains { $0.supportsMetadataEditing(tag) }
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

    func beginFieldEdit(_ readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)], tag: MetadataTag) {
        guard readings.count == 1 else { startBatch(readings, tags: [tag]); return }
        if let previous = editSession, previous.inline, previous.fields.first?.tag == tag,
           previous.photoIDs == Set(readings.map(\.image.id)), !previous.application.applied { return }
        Task { @MainActor in
            if let previous = editSession {
                guard previous.inline, await previous.finishInline(in: store) else { return }
            }
            // Use the current draft after the preceding field has finished applying.
            guard let current = store.state.imageData.first(where: { $0.id == readings[0].image.id }) else { return }
            editSession = MetadataBatchEditSession(readings: [(current, readings[0].snapshot)], tags: [tag], inline: true)
        }
    }

    func startBatch(_ readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)], tags: [MetadataTag]? = nil) {
        Task { @MainActor in
            if let previous = editSession, previous.inline {
                guard await previous.finishInline(in: store) else { return }
            }
            if let previous = ruleSession, previous.hasInput || previous.application.applied {
                showingBatch = true
                return
            }
            let current = readings.compactMap { reading -> (image: ImageData, snapshot: MetadataInspectionSnapshot)? in
                guard let image = store.state.imageData.first(where: { $0.id == reading.image.id }) else { return nil }
                return (image, reading.snapshot)
            }
            guard current.count == readings.count else { return }
            let tags = (tags ?? []).filter { tag in current.contains { $0.image.supportsMetadataEditing(tag) } }
            ruleSession = MetadataBatchEditSession(readings: current, tags: tags)
        }
    }

    func openWorkflow(_ readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)]?, tab: String) {
        guard let readings else { return }
        selectedWorkflowPreset = nil
        workflowEditor = MetadataCreatorEditorSelection(readings: readings, tag: .creator, input: tab)
    }

    func openBatch(_ identifiers: Set<String>, mode: String, input: String = "") {
        let tags = batchTargets(identifiers)
        guard !tags.isEmpty, let readings = editableCreatorReadings else { return }
        batchEditor = MetadataBatchEditorSelection(readings: readings, tags: tags,
                                                   excludedCount: identifiers.count - tags.count, mode: mode, input: input)
    }

    func fieldValue(_ tag: MetadataTag, summary: MetadataSelectionValue,
                    values: [[MetadataTag: MetadataTagValue]],
                    readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)]?) -> some View {
        let pending = selected.contains { $0.creatorDraft?.changes[tag] != nil }
        let canEdit = readings != nil && selected.contains { $0.supportsMetadataEditing(tag) }
        let value = display(summary, tag: tag)
        return VStack(alignment: .leading, spacing: 3) {
                if let session = editSession, session.inline, session.fields.first?.tag == tag,
                   session.photoIDs == Set(selected.map(\.id)) {
                    MetadataInlineFieldEditor(session: session) { if editSession?.id == session.id { editSession = nil } }
                } else if selected.count == 1 && canEdit, let readings {
                    Button { beginFieldEdit(readings, tag: tag) } label: {
                        metadataValue(value, isDate: tag.isDate || tag.isPartialDate,
                                      color: pending ? .orange : summary == .absent ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                } else if case .mixed = summary, let readings {
                    Button { valueDistribution = MetadataCreatorEditorSelection(readings: readings, tag: tag) } label: {
                        HStack(spacing: 5) {
                            metadataValue(value, isDate: tag.isDate || tag.isPartialDate, color: pending ? .orange : .primary)
                            Image(systemName: "chevron.down").font(.caption2)
                        }
                    }.buttonStyle(.plain).help(L10n.text("查看值分布"))
                } else {
                    metadataValue(value, isDate: tag.isDate || tag.isPartialDate,
                                  color: pending ? .orange : summary == .absent ? .secondary : .primary)
                }
                if tag == .creator { creatorCompatibility(values: values) }
            }.frame(maxWidth: .infinity, alignment: .leading)
    }

    func field(_ label: String, tag: MetadataTag,
               values: [[MetadataTag: MetadataTagValue]], selected: [ImageData],
               readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)]?) -> some View {
        let label = tag.isDate ? MetadataFieldSourceLabel.label(label, tag: tag.rawValue) : label
        let summary = MetadataSelectionValue.summarize(values, tag: tag)
        let canEdit = readings != nil && selected.contains { $0.supportsMetadataEditing(tag) }
        let value = display(summary, tag: tag)
        let pending = selected.contains { $0.creatorDraft?.changes[tag] != nil }
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.system(size: 13 + fontDelta, weight: .medium))
                    .foregroundStyle(pending ? Color.orange : Color.primary)
                Text(showsTagNames ? tag.rawValue : String(tag.rawValue.split(separator: ":").first ?? ""))
                    .font(.system(size: 10 + fontDelta)).foregroundStyle(.secondary).lineLimit(2)
            }.frame(width: fieldColumnWidth, alignment: .leading)
            fieldValue(tag, summary: summary, values: values, readings: readings)
            if pending {
                Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(.orange)
                    .accessibilityLabel(L10n.text("待保存")).help(L10n.text("待保存"))
            }
            if canEdit {
                Button {
                    if let readings { beginFieldEdit(readings, tag: tag) }
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
        .frame(minHeight: rowSpacing < 0 ? 30 : rowSpacing > 0 ? 48 : 40)
        .padding(.horizontal, 10).padding(.vertical, rowPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowSeparator(.visible)
        .listRowSeparatorTint(Color(nsColor: .separatorColor))
        .contentShape(Rectangle())
        .tag(tag.rawValue)
        .help(tag.rawValue)
        .onTapGesture(count: 2) {
            if canEdit, let readings { beginFieldEdit(readings, tag: tag) }
        }
        .onTapGesture {
            if selected.count == 1, canEdit, let readings { beginFieldEdit(readings, tag: tag) }
        }
        .accessibilityElement(children: editSession?.inline == true ? .contain : .combine)
        .accessibilityLabel(label + " · " + tag.rawValue)
        .accessibilityValue(value)
        .accessibilityIdentifier("metadataField." + tag.rawValue)
        .contextMenu {
            Button(L10n.text("查看值分布")) {
                if let readings { valueDistribution = MetadataCreatorEditorSelection(readings: readings, tag: tag) }
            }.disabled(readings == nil)
            Button(L10n.text("Copy")) {
                if let text = rawCopyValue(summary) { copyMetadataText(text) }
            }.disabled(rawCopyValue(summary) == nil)
            batchActions(selectedFields.contains(tag.rawValue) ? selectedFields : [tag.rawValue])
                .disabled(readings == nil)
            Divider()
            Group {
                Button(L10n.text("编辑元数据…")) {
                    if let readings { beginFieldEdit(readings, tag: tag) }
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
                            if let editable = MetadataFieldFilter.mappedTag(tag), let completeValues,
                               selected.contains(where: { $0.supportsMetadataEditing(editable) }) {
                                field(MetadataFieldFilter.displayName(tag), tag: editable, values: completeValues, selected: selected, readings: readings)
                                if selected.contains(where: { MetadataDisplaySection.sourceKeys(for: tag, in: advanced[$0.id] ?? [:]).count > 1 }) {
                                    let sources = Set(selected.flatMap {
                                        MetadataDisplaySection.sourceKeys(for: tag, in: advanced[$0.id] ?? [:])
                                    }).sorted()
                                    DisclosureGroup(L10n.text("查看完整字段与标签来源")) {
                                        ForEach(sources, id: \.self) { source in
                                            inspectionRow(source, values: selected.map { advanced[$0.id]?[source] }, selected: selected)
                                        }
                                    }.font(.caption).selectionDisabled()
                                }
                            } else {
                                inspectionRow(tag, values: selected.map { MetadataDisplaySection.value(for: tag, in: advanced[$0.id] ?? [:]) }, selected: selected)
                            }
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
                        .padding(.horizontal, 10).padding(.vertical, rowPadding)
                        .background(Color(nsColor: .separatorColor).opacity(0.12))
                        .id(section.name).selectionDisabled()
                }
            }
        }
    }

    var mappedTags: Set<MetadataTag> { Set(MetadataDisplaySection.standard.flatMap(\.tags).compactMap(MetadataFieldFilter.mappedTag)) }

    func matchesQuery(_ tag: String, group: String, selected: [ImageData],
                      completeValues: [[MetadataTag: MetadataTagValue]]?) -> Bool {
        let editable = MetadataFieldFilter.mappedTag(tag) ?? MetadataTag(rawValue: tag)
        return MetadataFieldFilter.matches(query: fieldQuery, presentOnly: false, editedOnly: false,
            commonOnly: commonOnly, isCommon: commonFieldTags.contains(editable?.rawValue ?? tag),
            names: [tag, editable?.rawValue ?? "", L10n.text(group), MetadataFieldFilter.displayName(tag)],
            hasEdits: selected.contains { image in
                editable.map { image.creatorDraft?.changes[$0] != nil } ?? false
            }, values: {
                let isReferenceField = MetadataDisplaySection.standard.contains { $0.tags.contains(tag) }
                return selected.enumerated().map { index, image in
                    if let editable, let completeValues,
                       image.supportsMetadataEditing(editable) {
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
                Text(MetadataFieldFilter.displayName(tag)).font(.system(size: 13 + fontDelta, weight: .medium))
                Text(showsTagNames ? tag : String(tag.split(separator: ":").first ?? ""))
                    .font(.system(size: 10 + fontDelta)).foregroundStyle(.secondary).lineLimit(2)
            }.frame(width: fieldColumnWidth, alignment: .leading)
            metadataValue(visibleText, isDate: isDate, color: summary == .absent ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "lock").font(.system(size: 11)).foregroundStyle(.secondary)
                .frame(width: 24).accessibilityLabel(L10n.text("只读"))
        }
        .frame(minHeight: rowSpacing < 0 ? 30 : rowSpacing > 0 ? 48 : 40)
        .padding(.horizontal, 10).padding(.vertical, rowPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowSeparator(.visible)
        .listRowSeparatorTint(Color(nsColor: .separatorColor))
        .tag("display:" + tag)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(MetadataFieldFilter.displayName(tag) + " · " + tag)
        .accessibilityValue(visibleText)
        .help(tag + " · " + L10n.text("此字段尚未开放可靠写回；GPS 请在地图定位中编辑。"))
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
        SaveHelper.creatorFailure(result)
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
            guard readings.allSatisfy({ MetadataInspectionFileVersion.read($0.snapshot.url) == $0.snapshot.version }) else {
                throw MetadataCreatorPlanError.sourceChanged
            }
            if !plan.items.isEmpty { store.send(.creatorDraftApplied(plan.items), description: L10n.text("粘贴到所选字段")) }
            pasteSkipped = plan.skipped.filter { plan.skipReasons[$0] == .unsupportedField }
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
                    .font(.system(size: 15 + fontDelta, design: .monospaced)).monospacedDigit()
                    .foregroundStyle(color).lineLimit(1)
                Text(String(value[value.index(after: newline)...]))
                    .font(.system(size: 11 + fontDelta, design: .monospaced)).monospacedDigit()
                    .foregroundStyle(.secondary).lineLimit(1)
            }.help(value)
        } else {
            Text(value).font(.system(size: 13 + fontDelta, design: isDate ? .monospaced : .default)).monospacedDigit()
                .lineLimit(2).help(value).foregroundStyle(color)
        }
    }

    func display(_ summary: MetadataSelectionValue, tag: MetadataTag) -> String {
        if case .uniform(.text(let value)) = summary {
            if tag.isDate || tag.isPartialDate { return MetadataInspectorDateDisplay.text(value) ?? value }
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
