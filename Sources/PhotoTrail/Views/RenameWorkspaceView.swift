import AppKit
import ImageData
import SwiftUI
import UDF
import UniformTypeIdentifiers

struct RenameWorkspaceView: View {
    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) private var store
    @Bindable var workspace: RenameWorkspace
    @State private var selectedRule: UUID?
    @State private var ruleFrames: [UUID: CGRect] = [:]
    @State private var confirm = false
    @State private var showHistory = false
    @State private var showPresetSave = false
    @State private var showPresetManager = false
    @State private var presetQuery = ""
    @State private var renamingPresetID: UUID?
    @State private var renamingPresetName = ""
    @State private var showPresetRename = false
    @State private var showSettings = false
    @State private var showAdvanced = false
    @State private var confirmSaveFirst = false
    @State private var awaitingSave = false
    @State private var pendingRemoval = Set<ImageData.ID>()

    private var dirty: Bool { store.imageData.contains(where: \.hasPendingChanges) }
    private var canExecute: Bool {
        !workspace.busy && !workspace.executing && !store.saveInProgress &&
        workspace.plan != nil && workspace.actionable > 0 && !workspace.blocked && workspace.directoriesAuthorized
    }

    var body: some View {
        HSplitView {
            rulesSidebar.frame(minWidth: 320, idealWidth: 350, maxWidth: 420)
            preview.frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay {
            if workspace.busy && !workspace.executing {
                ZStack {
                    Color.black.opacity(0.06)
                    VStack(spacing: 14) {
                        Text(L10n.text("正在生成重命名预览…")).font(.headline)
                        if workspace.previewTotal > 0 && !workspace.previewCalculating {
                            ProgressView(value: Double(workspace.previewCompleted), total: Double(workspace.previewTotal))
                                .frame(width: 300)
                            Text(L10n.text("已处理 %1$@/%2$@", workspace.previewCompleted, workspace.previewTotal)).monospacedDigit()
                            RemainingTimeView(seconds: workspace.previewRemainingSeconds)
                        } else {
                            ProgressView().progressViewStyle(.linear).frame(width: 300)
                        }
                        Text(L10n.text(workspace.previewCalculating
                            ? "正在计算文件名并检查冲突…" : "正在读取照片信息并计算文件名，请稍候。"))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .padding(28)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
                }
                .allowsHitTesting(false)
                .accessibilityIdentifier("renamePreviewLoadingOverlay")
            }
        }
        .environment(workspace)
        .accessibilityIdentifier("renameWorkspace")
        .task {
            workspace.initializeScope(selection: store.selection)
            refresh()
        }
        .onChange(of: workspace.rules) { refresh() }
        .onChange(of: workspace.settings) { refresh() }
        .onChange(of: workspace.onlySelected) { refresh() }
        .onChange(of: workspace.authorizedDirectories) { refresh() }
        .onChange(of: workspace.counterRevision) { refresh() }
        .onChange(of: store.selection) {
            workspace.selectedRows = sharedSelectedRows
            if workspace.onlySelected { refresh() }
        }
        .onChange(of: workspace.rows.map(\.source)) { workspace.selectedRows = sharedSelectedRows }
        .onChange(of: workspace.selectedRows) {
            guard workspace.selectedRows != sharedSelectedRows else { return }
            store.send(.selectionChanged(sharedPhotoIDs(for: workspace.selectedRows)), undoable: false)
        }
        .onChange(of: store.imageData.map(\.metadataCreatorImageURL)) { if !workspace.executing { refresh() } }
        .onChange(of: store.saveInProgress) {
            if !store.saveInProgress && !workspace.executing {
                if awaitingSave {
                    awaitingSave = false
                    workspace.notice = dirty
                        ? L10n.text("仍有未保存修改，未执行重命名。请检查保存结果后重试。")
                        : L10n.text("全部修改已保存。请核对更新后的文件名预览，再执行重命名。")
                }
                refresh()
            }
        }
        .alert(L10n.text("先保存元数据，再重命名？"), isPresented: $confirmSaveFirst) {
            Button(L10n.text("取消"), role: .cancel) {}
            Button(L10n.text("保存全部修改并重新预览")) {
                awaitingSave = SaveHelper.requestSave(store)
            }
        } message: {
            Text(L10n.text("有 %1$@ 项未保存修改，包含元数据编辑和地图定位两个页面的修改，不限当前选中照片。保存后将重新生成改名预览，仍需你确认执行；保存失败或取消不会改名。", store.imageData.filter(\.hasPendingChanges).count))
        }
        .alert(L10n.text("确认重命名"), isPresented: $confirm) {
            Button(L10n.text("取消"), role: .cancel) {}
            Button(L10n.text("执行重命名")) {
                if dirty { confirmSaveFirst = true }
                else { workspace.execute(store: store) }
            }
        } message: {
            Text(L10n.text("将按预览重命名 %1$@ 个文件，包括列表中的配对文件。文件内容不改写；执行记录可用于恢复原名。", workspace.actionable))
        }
        .alert(L10n.text("保存重命名预设"), isPresented: $showPresetSave) {
            TextField(L10n.text("预设名称"), text: $workspace.presetName)
            Button(L10n.text("取消"), role: .cancel) {}
            Button(L10n.text("保存")) { workspace.savePreset() }
        }
        .alert(L10n.text("重命名预设"), isPresented: $showPresetRename) {
            TextField(L10n.text("预设名称"), text: $renamingPresetName)
            Button(L10n.text("取消"), role: .cancel) {}
            Button(L10n.text("保存")) {
                if let id = renamingPresetID { workspace.renamePreset(id, name: renamingPresetName) }
            }
        }
        .sheet(isPresented: $showHistory) { historySheet }
        .sheet(isPresented: $showSettings) { settingsSheet }
        .alert(L10n.text("从列表移除照片？"), isPresented: Binding(get: { !pendingRemoval.isEmpty }, set: {
            if !$0 { pendingRemoval = [] }
        })) {
            Button(L10n.text("取消"), role: .cancel) { pendingRemoval = [] }
            Button(L10n.text("从列表移除"), role: .destructive) {
                store.send(.removeImages(pendingRemoval), description: L10n.text("从列表移除照片"))
                pendingRemoval = []
            }
        } message: {
            Text(L10n.text("不会删除或修改磁盘原文件。选中照片及其配对 RAW 会一起移出列表；未保存的修改将从当前列表移除，可撤销恢复。"))
        }
    }

}

private extension RenameWorkspaceView {
    func refresh() {
        workspace.refresh(images: store.imageData, selection: store.selection, directoryScopes: store.scopedURLs)
    }

    var rulesSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.text("重命名规则")).font(.headline)
                Spacer()
            }.padding(14)
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.text("当前预设")).font(.caption).foregroundStyle(.secondary)
                    Text(workspace.currentPresetName).fontWeight(.medium).lineLimit(1).help(workspace.currentPresetName)
                    if workspace.presetModified {
                        Text(L10n.text("已修改 · 尚未保存")).font(.caption).foregroundStyle(.orange)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button(L10n.text("切换与管理…")) { showPresetManager = true }
                    .accessibilityIdentifier("renamePresetManager")
                    .popover(isPresented: $showPresetManager, arrowEdge: .trailing) { presetManager }
            }.padding(.horizontal, 14).padding(.bottom, 14)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.text("本次处理范围")).font(.headline)
                    Picker(L10n.text("照片范围"), selection: $workspace.onlySelected) {
                        Text(L10n.text("全部导入照片")).tag(false)
                        Text(L10n.text("选中照片及配对文件")).tag(true)
                    }
                    Text(L10n.text("照片：%1$@；关联文件一并列入右侧预览。", scopedPhotos.count))
                        .font(.caption).foregroundStyle(.secondary)
                    if scopedPhotos.contains(where: { $0.metadataCreatorImageURL == nil }) {
                        Text(L10n.text("其中 %1$@ 张不是本地文件，无法直接重命名。", scopedPhotos.filter { $0.metadataCreatorImageURL == nil }.count))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                    ForEach($workspace.rules) { $rule in
                        RenameRuleCard(rule: $rule, selectedRule: $selectedRule,
                                       index: workspace.rules.firstIndex(where: { $0.id == rule.id }) ?? 0,
                                       restingFrame: ruleFrames[rule.id] ?? .zero,
                                       reorder: { sourceID, point in
                                           guard !store.saveInProgress,
                                                 let target = ruleFrames.filter({ $0.key != sourceID && $0.value.minX <= point.x && point.x <= $0.value.maxX })
                                                    .min(by: { abs($0.value.midY - point.y) < abs($1.value.midY - point.y) }),
                                                 point.y >= (ruleFrames.values.map(\.minY).min() ?? 0),
                                                 point.y <= (ruleFrames.values.map(\.maxY).max() ?? 0) + 20 else { return }
                                           workspace.moveRule(sourceID, to: target.key); selectedRule = sourceID
                                       },
                                       remove: { workspace.rules.removeAll { $0.id == rule.id } },
                                       duplicate: {
                                           var copy = rule; copy.id = UUID()
                                           if let index = workspace.rules.firstIndex(where: { $0.id == rule.id }) {
                                               workspace.rules.insert(copy, at: index + 1)
                                           }
                                       })
                    }
                    Menu { actionMenu { action in
                        let rule = RenameRule(action: action.number)
                        workspace.rules.append(rule); selectedRule = rule.id
                    } } label: { Label(L10n.text("添加规则"), systemImage: "plus") }
                    .accessibilityIdentifier("renameAddRule")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Divider().padding(.vertical, 2)
                    Button { showSettings = true } label: {
                        Label(L10n.text("重命名设置…"), systemImage: "slider.horizontal.3")
                    }
                    .accessibilityIdentifier("renameSettings")
                    Button(L10n.text("执行记录与恢复…")) { showHistory = true }
                }.padding(14)
            }
            .coordinateSpace(name: "renameRules")
            .onPreferenceChange(RenameRuleFrames.self) { ruleFrames = $0 }
        }
        .disabled(workspace.executing || store.saveInProgress)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func setCommonPreset(_ name: String, rules: [RenameRule]) {
        workspace.activateCommonPreset(name: L10n.text(name), rules: rules)
        selectedRule = nil
        showPresetManager = false
    }

    private var presetManager: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("切换与管理预设")).font(.headline)
            TextField(L10n.text("搜索预设"), text: $presetQuery).textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.text("常用方案")).font(.caption).foregroundStyle(.secondary)
                    ForEach(["拍摄日期＋编号", "保留原名加前缀", "查找并替换"], id: \.self) { name in
                        if presetQuery.isEmpty || L10n.text(name).localizedStandardContains(presetQuery) {
                            Button {
                                let rules: [RenameRule] = name == "拍摄日期＋编号"
                                    ? [RenameRule(action: 40), RenameRule(action: 48, prefix: "_")]
                                    : [RenameRule(action: name == "保留原名加前缀" ? 1 : 11)]
                                setCommonPreset(name, rules: rules)
                            } label: {
                                presetChoice(L10n.text(name), selected: workspace.currentPresetID == nil && workspace.currentPresetName == L10n.text(name))
                            }.buttonStyle(.plain)
                        }
                    }
                    Divider()
                    Text(L10n.text("我的预设")).font(.caption).foregroundStyle(.secondary)
                    ForEach(workspace.presets.filter { presetQuery.isEmpty || $0.name.localizedStandardContains(presetQuery) }) { preset in
                        HStack(spacing: 10) {
                            Button {
                                workspace.activatePreset(preset); selectedRule = nil; showPresetManager = false
                            } label: { presetChoice(preset.name, selected: workspace.currentPresetID == preset.id) }
                            .buttonStyle(.plain)
                            Button {
                                renamingPresetID = preset.id; renamingPresetName = preset.name
                                showPresetManager = false; showPresetRename = true
                            } label: { Image(systemName: "pencil") }
                            .buttonStyle(.borderless).help(L10n.text("重命名预设"))
                            Button(role: .destructive) { workspace.deletePreset(preset.id) } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless).help(L10n.text("删除预设"))
                        }
                    }
                    if workspace.presets.isEmpty {
                        Text(L10n.text("保存当前规则后，预设会显示在这里。")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.frame(maxHeight: 280)
            Divider()
            HStack {
                Button(L10n.text("新建预设")) { setCommonPreset("自定义规则", rules: []) }
                Spacer()
                Button(L10n.text("保存当前修改")) {
                    if workspace.currentPresetID != nil { workspace.updateCurrentPreset() }
                    else { saveAsNewPreset() }
                }.disabled(workspace.currentPresetID != nil && !workspace.presetModified)
            }
            Button(L10n.text("另存为新预设…")) { saveAsNewPreset() }
            HStack {
                Button(L10n.text("导入预设…")) { showPresetManager = false; importPreset() }
                Spacer()
                Button(L10n.text("导出预设…")) { showPresetManager = false; exportPreset() }
            }
        }.padding(16).frame(width: 350)
        .accessibilityIdentifier("renamePresetPopover")
    }

    private func presetChoice(_ name: String, selected: Bool) -> some View {
        HStack {
            Text(name).lineLimit(1)
            Spacer()
            if selected { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
        }.padding(.vertical, 4).contentShape(Rectangle())
    }

    private func saveAsNewPreset() {
        workspace.presetName = workspace.currentPresetName
        showPresetManager = false; showPresetSave = true
    }

    private var preview: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.text("重命名预览")).font(.headline)
                    Text(L10n.text("文件：%1$@ · 将重命名：%2$@", workspace.rows.count, workspace.actionable))
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                Button(L10n.text("导入照片")) { store.send(.openCommand, undoable: false) }
                    .disabled(workspace.executing || store.saveInProgress)
                    .accessibilityIdentifier("renameAddFiles")
                if !workspace.rows.isEmpty && !workspace.directoriesAuthorized {
                    Button(L10n.text("授权文件目录…")) { authorizeDirectories(workspace.rows.map(\.source)) }
                        .disabled(workspace.executing || store.saveInProgress)
                }
                Button { refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .help(L10n.text("重新预览"))
                    .disabled(workspace.executing)
            }.padding(16)
            Divider()
            Table(workspace.rows, selection: $workspace.selectedRows) {
                TableColumn(L10n.text("预览")) { row in
                    if let image = store.imageData.first(where: { $0.metadataCreatorImageURL == row.source }) {
                        PhotoThumbnail(image: image, maxDimension: 100).frame(width: 38, height: 32)
                    } else {
                        Image(systemName: "doc").foregroundStyle(.secondary).frame(width: 38, height: 32)
                    }
                }.width(46)
                TableColumn(L10n.text("原文件名")) { row in Text(row.source.lastPathComponent).help(row.source.path) }
                    .width(min: 140, ideal: 170)
                if let index = workspace.rules.firstIndex(where: { $0.id == selectedRule }) {
                    TableColumn(L10n.text("第 %1$@ 条执行后", index + 1)) { row in
                        Text(row.steps.first(where: { $0.id == selectedRule })?.name ?? "—")
                            .foregroundStyle(.secondary)
                    }.width(min: 120, ideal: 140)
                }
                TableColumn(L10n.text("新文件名")) { row in
                    Text(row.target.lastPathComponent).foregroundStyle(row.changes ? Color.primary : Color.secondary)
                        .help(row.target.path)
                }.width(min: 160, ideal: 200)
                TableColumn(L10n.text("状态")) { row in
                    if let issue = row.issues.first(where: { $0 == .conflict || $0 == .invalidName }) ?? row.issues.first {
                        Label(RenameCopy.issue(issue), systemImage: row.issues.contains(.conflict) || row.issues.contains(.invalidName) ? "xmark.octagon" : "info.circle")
                            .foregroundStyle(row.issues.contains(.conflict) || row.issues.contains(.invalidName) ? Color.red : Color.secondary)
                    } else {
                        Label(L10n.text("将重命名"), systemImage: "checkmark.circle").foregroundStyle(.green)
                    }
                }.width(min: 100, ideal: 120)
            }
            .accessibilityIdentifier("renamePreviewTable")
            .contextMenu(forSelectionType: URL.self) { urls in
                let ids = sharedPhotoIDs(for: urls)
                if !ids.isEmpty {
                    Button(L10n.text("从列表移除照片")) { pendingRemoval = ids }
                        .disabled(workspace.executing || store.saveInProgress)
                }
            }
            .overlay {
                if workspace.rows.isEmpty && !workspace.busy {
                    ContentUnavailableView(L10n.text("暂无可重命名的文件"), systemImage: "character.cursor.ibeam",
                                           description: Text(L10n.text("导入本地照片或添加文件后设置规则，先核对预览，再执行改名。照片图库项目不支持文件改名。")))
                }
            }
            Divider()
            HStack {
                Text(L10n.text("确认最终文件名后执行重命名。"))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if selectedRule != nil {
                    Button(L10n.text("收起中间结果")) { selectedRule = nil }.font(.caption)
                }
            }.padding(.horizontal, 16).padding(.top, 8)
            VStack(alignment: .leading, spacing: 8) {
                if dirty {
                    HStack {
                        Label(L10n.text("元数据或定位修改尚未保存。"), systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(.orange)
                        Spacer()
                        Button(L10n.text("先保存…")) { confirmSaveFirst = true }
                            .disabled(store.saveInProgress || workspace.executing)
                    }
                }
                if !workspace.notice.isEmpty { Text(workspace.notice).font(.callout).textSelection(.enabled) }
                HStack {
                    Text(L10n.text("先预览，确认后执行")).font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    if !workspace.executing {
                        Button(L10n.text("执行重命名：%1$@ 个文件", workspace.actionable)) {
                            if dirty { confirmSaveFirst = true }
                            else { confirm = true }
                        }
                            .buttonStyle(.borderedProminent).disabled(!canExecute)
                            .accessibilityIdentifier("renamePerform")
                    }
                }
            }.padding(16)
        }
    }

    private var settingsSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("重命名设置")).font(.title2)
            ScrollView {
                Form {
                    Section {
                        Toggle(L10n.text("照片及关联文件一起改名"), isOn: $workspace.settings.pair)
                            .accessibilityIdentifier("renamePairFiles")
                        Text(L10n.text("同一文件夹内，同名的 JPG、RAW 和 XMP 等文件会一起改名，保留各自扩展名。"))
                            .font(.caption).foregroundStyle(.secondary)
                        if workspace.settings.pair {
                            TextField(L10n.text("照片文件扩展名"), text: $workspace.settings.sourceExtensions)
                            Text(L10n.text("按从左到右的顺序优先选取实际存在的照片，依据它计算新文件名，其他文件跟随改名。例如 jpg 在 arw 前面时，以 JPG 为准；将 arw 放在前面则优先以 RAW 为准。"))
                                .font(.caption).foregroundStyle(.secondary)
                            TextField(L10n.text("附属文件扩展名"), text: $workspace.settings.targetExtensions)
                            Text(L10n.text("这些附属文件跟随照片一起改名，排列顺序不影响优先级。"))
                                .font(.caption).foregroundStyle(.secondary)
                            Text(L10n.text("扩展名用逗号分隔，不加点。"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Section {
                        Picker(L10n.text("排序"), selection: $workspace.settings.sort) {
                            ForEach(RenameSettings.Sort.allCases, id: \.self) { Text(RenameLabels.sort($0)).tag($0) }
                        }
                        Toggle(L10n.text("降序"), isOn: $workspace.settings.descending)
                        Picker(L10n.text("文件名冲突"), selection: $workspace.settings.conflict) {
                            Text(L10n.text("阻止执行")).tag(RenameSettings.Conflict.stop)
                            Text(L10n.text("添加数字后缀")).tag(RenameSettings.Conflict.numbers)
                            Text(L10n.text("添加字母后缀")).tag(RenameSettings.Conflict.letters)
                        }
                        if workspace.settings.conflict != .stop {
                            Picker(L10n.text("后缀格式"), selection: Binding(
                                get: { workspace.settings.conflict == .letters
                                    ? workspace.settings.letterSuffixFormat ?? .plain
                                    : workspace.settings.numberSuffixFormat ?? .underscore },
                                set: { value in
                                    if workspace.settings.conflict == .letters { workspace.settings.letterSuffixFormat = value }
                                    else { workspace.settings.numberSuffixFormat = value }
                                })) {
                                ForEach(RenameSettings.SuffixFormat.allCases, id: \.self) { format in
                                    Text(format.format(workspace.settings.conflict == .letters ? "A"
                                        : RenameEngine.padded(1, width: workspace.settings.conflictDigits ?? 3))).tag(format)
                                }
                            }
                            if workspace.settings.conflict == .numbers {
                                Picker(L10n.text("数字位数"), selection: Binding(
                                    get: { workspace.settings.conflictDigits ?? 3 },
                                    set: { workspace.settings.conflictDigits = $0 })) {
                                    ForEach(2...5, id: \.self) { width in
                                        Text(RenameEngine.padded(1, width: width)).tag(width)
                                    }
                                }
                            }
                        }
                        Toggle(L10n.text("第一项保留无后缀名称"), isOn: $workspace.settings.keepFirst)
                    }
                    DisclosureGroup(L10n.text("高级设置"), isExpanded: $showAdvanced) {
                        Text(L10n.text("拍摄时间来源优先级（每行一个标签）")).font(.caption)
                        TextEditor(text: $workspace.settings.datePriority)
                            .font(.system(.caption, design: .monospaced)).frame(height: 150)
                            .border(Color.secondary.opacity(0.2))
                    }
                }.formStyle(.grouped)
            }
            HStack {
                Spacer()
                Button(L10n.text("完成")) { showSettings = false }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 580, height: 560)
        .accessibilityIdentifier("renameSettingsSheet")
    }

    private var historySheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("执行记录与恢复")).font(.title2)
            Text(L10n.text("恢复前核对文件身份、内容与原名占用；不会覆盖后来创建的文件。"))
                .foregroundStyle(.secondary)
            if workspace.historyLoading { ProgressView() }
            List(workspace.history) { journal in
                HStack {
                    VStack(alignment: .leading) {
                        Text(journal.created.formatted(date: .numeric, time: .standard))
                        Text(L10n.text("文件：%1$@ · %2$@", journal.entries.count, RenameLabels.journal(journal.state)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if journal.state != "restored" {
                        Button(L10n.text("恢复原名")) { workspace.restore(journal, store: store) }
                            .disabled(workspace.executing || workspace.historyLoading || store.saveInProgress || dirty)
                    }
                }
            }
            if !workspace.notice.isEmpty { Text(workspace.notice).font(.callout) }
            HStack { Spacer(); Button(L10n.text("完成")) { showHistory = false }.keyboardShortcut(.cancelAction) }
        }.padding(20).frame(width: 700, height: 450)
            .task { await workspace.loadHistory() }
            .overlay {
                if workspace.executing { RenameExecutionProgressView(workspace: workspace) }
            }
    }

    private var scopedPhotos: [ImageData] {
        store.imageData.filter { !workspace.onlySelected || store.selection.contains($0.id) }
    }

    private var sharedSelectedRows: Set<URL> {
        Set(store.imageData.filter { store.selection.contains($0.id) }
            .compactMap(\.metadataCreatorImageURL)).intersection(workspace.rows.map(\.source))
    }

    private func sharedPhotoIDs(for urls: Set<URL>) -> Set<ImageData.ID> {
        Set(store.imageData.filter { image in
            image.metadataCreatorImageURL.map(urls.contains) == true || image.metadataInspectionURL.map(urls.contains) == true
        }.map(\.id))
    }

    private func authorizeDirectories(_ files: [URL]) {
        let parents = Set(files.map { $0.deletingLastPathComponent().standardizedFileURL })
        for parent in parents.sorted(by: { $0.path < $1.path }) where !workspace.authorizedDirectories.contains(parent) {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true; panel.canChooseFiles = false
            panel.directoryURL = parent
            panel.message = L10n.text("请选择文件所在目录，以扫描配对文件、检查重名和安全改名。仅处理预览中的文件，不递归遍历。")
            panel.prompt = L10n.text("授权目录")
            if panel.runModal() == .OK, let url = panel.url { workspace.authorizeDirectory(url) }
        }
        refresh()
    }

    private func importPreset() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { workspace.importPreset(url) }
    }
    private func exportPreset() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "PhotoTrail.rename.json"
        if panel.runModal() == .OK, let url = panel.url { workspace.exportPreset(url) }
    }
}

@MainActor @ViewBuilder private func actionMenu(_ choose: @escaping @MainActor (RenameAction) -> Void) -> some View {
    let categories = RenameAction.all.reduce(into: [String]()) { if !$0.contains($1.categoryChinese) { $0.append($1.categoryChinese) } }
    ForEach(categories, id: \.self) { category in
        Menu(L10n.text(category)) {
            ForEach(RenameAction.all.filter { $0.categoryChinese == category }) { action in
                Button(L10n.text(action.titleChinese)) { choose(action) }
            }
        }
    }
}

private struct RenameRuleFrames: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct RenameRuleCard: View {
    @Binding var rule: RenameRule
    @Binding var selectedRule: UUID?
    let index: Int
    let restingFrame: CGRect
    let reorder: (UUID, CGPoint) -> Void
    let remove: () -> Void
    let duplicate: () -> Void
    @State private var expanded = true
    @FocusState private var editing: Bool
    @State private var dragOffset: CGSize = .zero
    @State private var dragOriginFrame: CGRect = .zero
    private var title: String {
        RenameAction.all.first(where: { $0.number == rule.action })
            .map { L10n.text($0.categoryChinese) + " · " + L10n.text($0.titleChinese) } ?? "R\(rule.action)"
    }

    private var cardContents: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Toggle("", isOn: $rule.enabled).labelsHidden().toggleStyle(.checkbox)
                    .accessibilityLabel(L10n.text("启用规则"))
                Button { expanded.toggle(); selectedRule = rule.id } label: {
                    HStack { Text("\(index + 1)").monospacedDigit().foregroundStyle(.secondary)
                        Text(title).fontWeight(.medium)
                        Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.caption) }
                }.buttonStyle(.plain).accessibilityIdentifier("renameRuleTitle")
                Spacer(minLength: 0)
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 15)).foregroundStyle(.secondary)
                    .frame(width: 28, height: 28).contentShape(Rectangle())
                    .help(L10n.text("拖动以调整规则顺序"))
                    .accessibilityLabel(L10n.text("拖动以调整规则顺序"))
                    .accessibilityIdentifier("renameRuleDragHandle")
                    .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .named("renameRules"))
                        .onChanged { value in
                            if dragOffset == .zero { dragOriginFrame = restingFrame }
                            dragOffset = value.translation; selectedRule = rule.id
                        }
                        .onEnded { value in
                            dragOffset = .zero
                            guard !dragOriginFrame.contains(value.location) else { return }
                            reorder(rule.id, value.location)
                        })
            }
            if expanded {
                Menu(L10n.text("更换动作")) { actionMenu { rule.action = $0.number; selectedRule = rule.id } }
                    .font(.caption)
                RenameRuleParameters(rule: $rule)
                    .disabled(!rule.enabled)
                if rule.action < 98 {
                    Picker(L10n.text("作用片段"), selection: $rule.part) {
                        ForEach(RenameRule.Part.allCases, id: \.self) { Text(RenameLabels.part($0)).tag($0) }
                    }
                }
            }
        }
        .padding(12)
        .background(selectedRule == rule.id || editing ? Color.blue.opacity(0.08) : Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 10))
    }

    var body: some View {
        cardContents
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(
            selectedRule == rule.id || editing ? Color.blue : Color.secondary.opacity(0.18),
            lineWidth: selectedRule == rule.id || editing ? 1.5 : 1))
        .focused($editing)
        .simultaneousGesture(TapGesture().onEnded { selectedRule = rule.id })
        .onChange(of: editing) { if editing { selectedRule = rule.id } }
        .onChange(of: rule) { selectedRule = rule.id }
        .contentShape(Rectangle())
        .contextMenu {
            Button(L10n.text("复制规则"), action: duplicate)
            Button(L10n.text("删除规则"), role: .destructive, action: remove)
        }
        .background(GeometryReader { geometry in
            Color.clear.preference(key: RenameRuleFrames.self, value: [rule.id: geometry.frame(in: .named("renameRules"))])
        })
        .offset(dragOffset)
        .zIndex(dragOffset == .zero ? 0 : 1)
        .shadow(color: .black.opacity(dragOffset == .zero ? 0 : 0.15), radius: 8)
    }
}

private struct RenameRuleParameters: View {
    @Environment(RenameWorkspace.self) private var workspace
    @State private var tagPicker = false
    @State private var lexicalExpanded = false
    @Binding var rule: RenameRule
    private var action: Int { rule.action }
    private var needsAnchor: Bool { [3,4,15,16,43,44,49,50,57,58,63,64,70,71,75,76,81,82,86,87,91,92].contains(action) }
    private var needsPosition: Bool { [5,14,26,27,45,51,59,65,69,77,83,88,93].contains(action) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if action <= 19 || [32,94,95,96,97].contains(action) || (66...77).contains(action) {
                if [32,94].contains(action) || (66...77).contains(action) {
                    Text(L10n.text(action == 94 ? "每行新名称，或旧名与新名的 TSV" : action == 32 ? "词汇大小写例外（每行一个）" : "标签模板，例如 <CameraModel>"))
                        .font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $rule.text).font(.system(.callout, design: .monospaced)).frame(height: 80)
                        .border(Color.secondary.opacity(0.2))
                    if (66...77).contains(action) {
                        Button(L10n.text("插入标签…")) { tagPicker = true }
                    }
                } else { TextField(L10n.text("文字或匹配表达式"), text: $rule.text) }
            }
            if [9,10,11,17,95,96].contains(action) { TextField(L10n.text("替换为"), text: $rule.replacement) }
            if needsAnchor { TextField(L10n.text("定位文字"), text: $rule.anchor) }
            if needsPosition { number(L10n.text("字符位置（从 0 开始）"), value: $rule.position) }
            if [24,25,26,27,38,39].contains(action) { number(L10n.text("字符数量或长度"), value: $rule.length) }
            if action == 27 { number(L10n.text("移动后的目标位置"), value: $rule.start) }
            if action <= 19 || [52,53,95,96,94].contains(action) {
                Toggle(L10n.text("区分大小写"), isOn: $rule.caseSensitive)
                if action <= 19 || action == 52 || action == 53 {
                    Picker(L10n.text("匹配次数"), selection: $rule.occurrence) {
                        ForEach(RenameRule.Occurrence.allCases, id: \.self) { Text(RenameLabels.occurrence($0)).tag($0) }
                    }
                    if rule.occurrence == .nth { number(L10n.text("第几次匹配"), value: $rule.matchNumber) }
                }
            }
            if (40...45).contains(action) { dateParameters }
            if (46...51).contains(action) || (54...65).contains(action) { sequenceParameters }
            if action == 52 {
                Picker(L10n.text("数字操作"), selection: $rule.numberOperation) {
                    ForEach(RenameRule.NumberOperation.allCases, id: \.self) { Text(RenameLabels.number($0)).tag($0) }
                }
                number(L10n.text("运算值"), value: $rule.numberValue)
                number(L10n.text("最小位数"), value: $rule.padding)
            }
            if (78...93).contains(action) {
                TextField(L10n.text("前缀"), text: $rule.prefix)
                TextField(L10n.text("后缀"), text: $rule.suffix)
                if (78...83).contains(action) || action >= 89 { TextField(L10n.text("分隔符"), text: $rule.text) }
                if action >= 89 {
                    number(L10n.text("祖先层级（父目录为 0）"), value: $rule.position)
                    number(L10n.text("目录层数"), value: $rule.length)
                }
            }
            if action == 32 {
                DisclosureGroup(L10n.text("词性大小写"), isExpanded: $lexicalExpanded) {
                    ForEach(rule.lexicalCases.keys.sorted(), id: \.self) { kind in
                        Picker(L10n.text(kind), selection: Binding(get: { rule.lexicalCases[kind] ?? .keep },
                                                                 set: { rule.lexicalCases[kind] = $0 })) {
                            Text(L10n.text("保持不变")).tag(RenameRule.CaseStyle.keep)
                            Text(L10n.text("转小写")).tag(RenameRule.CaseStyle.lower)
                            Text(L10n.text("转大写")).tag(RenameRule.CaseStyle.upper)
                            Text(L10n.text("转标题大小写")).tag(RenameRule.CaseStyle.title)
                        }
                    }
                }
            }
            if action == 96 { Toggle(L10n.text("要求整段匹配"), isOn: $rule.fullMatch) }
            if (40...45).contains(action) || (66...83).contains(action) || action == 94 || (89...93).contains(action) {
                Toggle(L10n.text("必需内容缺失时保留整个原名"), isOn: $rule.skipMissing)
            }
            if action == 98 { filterParameters }
            if action == 99 {
                Text(L10n.text("高级选项统一在下方任务选项中设置。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.textFieldStyle(.roundedBorder).controlSize(.regular)
        .sheet(isPresented: $tagPicker) { RenameTagPicker(rule: $rule, workspace: workspace) }
    }

    private func number(_ title: String, value: Binding<Int>) -> some View {
        HStack { Text(title).font(.callout); Spacer(); TextField(title, value: value, format: .number.grouping(.never)).frame(width: 72).multilineTextAlignment(.trailing) }
    }

    private var dateParameters: some View {
        VStack(alignment: .leading, spacing: 9) {
            Picker(L10n.text("日期来源"), selection: $rule.dateSource) {
                Text(L10n.text("拍摄时间")).tag(RenameRule.DateSource.shooting)
                Text(L10n.text("文件创建时间")).tag(RenameRule.DateSource.created)
                Text(L10n.text("文件修改时间")).tag(RenameRule.DateSource.modified)
                Text(L10n.text("当前时间")).tag(RenameRule.DateSource.now)
            }
            TextField(L10n.text("日期格式"), text: $rule.dateFormat)
            Menu(L10n.text("常用日期格式")) {
                ForEach(["yyyyMMdd_HHmmss", "yyyy-MM-dd_HH-mm-ss", "yyyy.MM.dd.HHmmss", "yyyyMMdd", "yyyyMMdd_HHmmss_SSS"], id: \.self) { format in
                    Button(format) { rule.dateFormat = format }
                }
            }.font(.caption)
            Picker(L10n.text("时间显示"), selection: $rule.timeZone) {
                Text(L10n.text("拍摄当地时间")).tag("source")
                Text(L10n.text("本机时区")).tag("local")
                Text("UTC").tag("UTC")
                if !["source","local","UTC"].contains(rule.timeZone) { Text(rule.timeZone).tag(rule.timeZone) }
            }
            TextField(L10n.text("时区标识或 source／local"), text: $rule.timeZone)
            number(L10n.text("夜间日界小时（0 为关闭）"), value: $rule.nightHour)
            Text(L10n.text("无时区的拍摄时间按记录的钟面时间使用，不推断拍摄地点时区。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var sequenceParameters: some View {
        VStack(spacing: 9) {
            if action <= 51 {
                Picker(L10n.text("编号来源"), selection: $rule.counter) {
                    Text(L10n.text("本批次起始值")).tag(0)
                    ForEach(1...10, id: \.self) { index in
                        Text(L10n.text("持续计数器 %1$@", index)).tag(index)
                    }
                }
                if rule.counter > 0 {
                    Text(L10n.text("当前计数：%1$@", RenameWorkspace.counters()[rule.counter] ?? 1))
                        .font(.caption).foregroundStyle(.secondary)
                    Button(L10n.text("将计数器设为起始值")) { workspace.resetCounter(rule) }
                }
            }
            if action >= 60 {
                TextField(L10n.text("起始字母"), text: $rule.alphabetStart)
                number(L10n.text("最少字母数（前补 A）"), value: $rule.alphabetWidth)
            } else { number(L10n.text("起始值"), value: $rule.start) }
            number(L10n.text("步长"), value: $rule.step)
            if action <= 51 { number(L10n.text("最小位数"), value: $rule.padding) }
            TextField(L10n.text("前缀"), text: $rule.prefix)
            TextField(L10n.text("后缀"), text: $rule.suffix)
            Toggle(L10n.text("每个目录独立编号"), isOn: $rule.perDirectory)
        }
    }

    private var filterParameters: some View {
        VStack(alignment: .leading, spacing: 9) {
            Picker(L10n.text("条件组合"), selection: $rule.filterAny) {
                Text(L10n.text("满足全部条件")).tag(false)
                Text(L10n.text("满足任一条件")).tag(true)
            }
            ForEach($rule.filters) { $condition in
                VStack(spacing: 6) {
                    Picker(L10n.text("字段"), selection: $condition.field) {
                        Text(L10n.text("文件名")).tag(RenameFilterCondition.Field.name)
                        Text(L10n.text("扩展名")).tag(RenameFilterCondition.Field.fileExtension)
                        Text(L10n.text("拍摄时间")).tag(RenameFilterCondition.Field.shootingDate)
                        Text(L10n.text("照片注释")).tag(RenameFilterCondition.Field.comment)
                    }
                    Picker(L10n.text("比较"), selection: $condition.comparison) {
                        ForEach(RenameFilterCondition.Comparison.allCases, id: \.self) { Text(RenameLabels.comparison($0)).tag($0) }
                    }
                    TextField(L10n.text("比较值"), text: $condition.value)
                    Button(L10n.text("移除条件")) { rule.filters.removeAll { $0.id == condition.id } }
                }.padding(8).background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
            }
            Button(L10n.text("添加条件")) { rule.filters.append(RenameFilterCondition()) }
            Toggle(L10n.text("区分大小写"), isOn: $rule.caseSensitive)
            Text(L10n.text("仅控制后续规则，遇到下一筛选规则重新确定范围。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

enum RenameLabels {
    static func part(_ part: RenameRule.Part) -> String {
        switch part {
        case .stem: L10n.text("文件名主体（不含扩展名）")
        case .entire: L10n.text("整个文件名与扩展名")
        case .dottedExtension: L10n.text("扩展名（含点）")
        case .extensionOnly: L10n.text("扩展名（不含点）")
        }
    }
    static func sort(_ sort: RenameSettings.Sort) -> String {
        switch sort {
        case .input: L10n.text("导入顺序")
        case .name: L10n.text("文件名")
        case .natural: L10n.text("文件名自然顺序")
        case .shooting: L10n.text("拍摄时间")
        case .created: L10n.text("文件创建时间")
        case .modified: L10n.text("文件修改时间")
        }
    }
    static func occurrence(_ value: RenameRule.Occurrence) -> String {
        switch value {
        case .all: L10n.text("全部匹配")
        case .first: L10n.text("第一个匹配")
        case .last: L10n.text("最后一个匹配")
        case .nth: L10n.text("第 N 个匹配")
        }
    }
    static func number(_ value: RenameRule.NumberOperation) -> String {
        switch value {
        case .add: L10n.text("加")
        case .subtract: L10n.text("减")
        case .multiply: L10n.text("乘")
        case .divide: L10n.text("除")
        case .set: L10n.text("设为")
        }
    }
    static func comparison(_ value: RenameFilterCondition.Comparison) -> String {
        switch value {
        case .contains: L10n.text("包含")
        case .notContains: L10n.text("不包含")
        case .equals: L10n.text("等于")
        case .notEquals: L10n.text("不等于")
        case .starts: L10n.text("开头是")
        case .ends: L10n.text("结尾是")
        case .before: L10n.text("早于或小于")
        case .after: L10n.text("晚于或大于")
        case .exists: L10n.text("有值")
        case .missing: L10n.text("无值")
        }
    }
    static func journal(_ value: String) -> String {
        switch value {
        case "completed": L10n.text("已完成")
        case "restored": L10n.text("已恢复")
        default: L10n.text("需要恢复")
        }
    }
}

private struct RenameTagPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var rule: RenameRule
    let workspace: RenameWorkspace
    @State private var query = ""
    private var input: RenameInput? {
        workspace.inputs.first(where: { workspace.selectedRows.contains($0.url) }) ?? workspace.inputs.first
    }
    private static let reference: [String] = {
        guard let url = Bundle.main.url(forResource: "RenameTags", withExtension: "json"),
              let data = try? Data(contentsOf: url), let tags = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return tags
    }()
    private var tokens: [String] {
        let actual = Set(workspace.inputs.flatMap { $0.tags.keys }.filter { !$0.hasPrefix("PhotoTrail:") })
        return Set(Self.reference).union(actual).sorted().filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("选择标签")).font(.title2)
            TextField(L10n.text("搜索标签"), text: $query).textFieldStyle(.roundedBorder)
            if let input { Text(input.name).font(.caption).foregroundStyle(.secondary) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(tokens, id: \.self) { token in
                        Button {
                            rule.text += "<" + token + ">"
                            dismiss()
                        } label: {
                            HStack(alignment: .firstTextBaseline) {
                                Text("<\(token)>").font(.system(.callout, design: .monospaced))
                                Spacer()
                                let value = input.flatMap { try? RenameEngine.template("<" + token + ">", input: $0, rule: rule, settings: workspace.settings) }
                                Text(value ?? L10n.text("无值")).foregroundStyle(.secondary).lineLimit(1)
                            }.padding(.vertical, 6).padding(.horizontal, 8).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Divider()
                    }
                }
            }
            Text(L10n.text("值来自当前预览文件；候选标签不保证每种文件都有值。"))
                .font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button(L10n.text("完成")) { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(20).frame(width: 700, height: 500)
    }
}
