import AppKit
import ImageData
import SwiftUI
import UDF
import UniformTypeIdentifiers

struct RenameWorkspaceView: View {
    @Environment(LocationWorkspace.self) private var locationWorkspace
    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var workspace: RenameWorkspace
    @State private var selectedRule: UUID?
    @AppStorage("PhotoTrailRenameTableColumns.v1") private var tableColumns = TableColumnCustomization<RenamePreview>()
    @State private var ruleFrames: [UUID: CGRect] = [:]
    @State private var confirm = false
    @State private var showFileFilter = false
    @State private var resultFilter = "all"
    @State private var viewingSort = "processing"
    @State private var showHistory = false
    @State private var showPresetSave = false
    @State private var showPresetManager = false
    @State private var presetQuery = ""
    @State private var renamingPresetID: UUID?
    @State private var renamingPresetName = ""
    @State private var renamingPresetExample = ""
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
        .onChange(of: workspace.fileFilter) { refresh() }
        .onChange(of: workspace.orderRevision) { refresh() }
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
                awaitingSave = SaveHelper.requestSave(store, workspace: locationWorkspace, forceAll: true)
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
        .alert(L10n.text("保存重命名方案"), isPresented: $showPresetSave) {
            TextField(L10n.text("方案名称"), text: $workspace.presetName)
            TextField(L10n.text("文件名示例"), text: $workspace.presetExample)
            Button(L10n.text("取消"), role: .cancel) {}
            Button(L10n.text("保存")) { workspace.savePreset() }
        }
        .alert(L10n.text("重命名方案"), isPresented: $showPresetRename) {
            TextField(L10n.text("方案名称"), text: $renamingPresetName)
            TextField(L10n.text("文件名示例"), text: $renamingPresetExample)
            Button(L10n.text("取消"), role: .cancel) {}
            Button(L10n.text("保存")) {
                if let id = renamingPresetID { workspace.renamePreset(id, name: renamingPresetName, example: renamingPresetExample) }
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
            presetCard.padding(.horizontal, 14).padding(.bottom, 14)
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
                                       collapseToken: workspace.currentPresetID == nil ? nil : workspace.presetActivationID,
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

    var presetCard: some View {
        let dark = colorScheme == .dark
        let background = dark
            ? [Color(red: 0.07, green: 0.12, blue: 0.25), Color(red: 0.20, green: 0.22, blue: 0.51)]
            : [Color(red: 0.93, green: 0.97, blue: 1), Color(red: 0.90, green: 0.87, blue: 1)]
        let title = dark
            ? [Color(red: 0.47, green: 0.82, blue: 1), Color(red: 0.76, green: 0.68, blue: 1)]
            : [Color(red: 0.04, green: 0.46, blue: 1), Color(red: 0.48, green: 0.24, blue: 0.96)]
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("当前方案"))
                        .font(.caption).foregroundStyle(dark ? Color.white.opacity(0.7) : Color.secondary)
                    if workspace.presetModified {
                        Text(L10n.text("已修改 · 尚未保存"))
                            .font(.caption).foregroundStyle(dark ? Color(red: 1, green: 0.78, blue: 0.43) : Color.orange)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button { showPresetManager = true } label: {
                    HStack(spacing: 6) {
                        Text(L10n.text("切换与管理…"))
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(dark ? Color.white : Color.blue)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Color.white.opacity(dark ? 0.15 : 0.65), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(dark ? 0.20 : 0.5)))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("renamePresetManager")
                .popover(isPresented: $showPresetManager, arrowEdge: .trailing) { presetManager }
            }
            .padding(.horizontal, 16).padding(.top, 14)
            if !workspace.presetExample.isEmpty {
                Text(L10n.text("示例：%1$@", workspace.presetExample))
                    .font(.callout).foregroundStyle(dark ? Color.white.opacity(0.88) : Color.primary)
                    .shadow(color: dark ? .black.opacity(0.45) : .white.opacity(0.9), radius: 2)
                    .lineLimit(1).truncationMode(.middle).help(workspace.presetExample)
                    .padding(.horizontal, 16)
            }
            Text(workspace.currentPresetName)
                .font(.system(size: 52, weight: .bold))
                .foregroundStyle(LinearGradient(colors: title, startPoint: .leading, endPoint: .trailing))
                .mask(LinearGradient(colors: [.white.opacity(dark ? 0.16 : 0.10),
                                              .white.opacity(dark ? 0.60 : 0.42)],
                                     startPoint: .top, endPoint: .bottom))
                .lineLimit(1).minimumScaleFactor(0.12).help(workspace.currentPresetName)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.bottom, 2)
        }
        .background(LinearGradient(colors: background, startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(
            dark ? Color.white.opacity(0.12) : Color.blue.opacity(0.16)))
        .accessibilityIdentifier("renamePresetCard")
    }

    private func setCommonPreset(_ name: String, rules: [RenameRule]) {
        workspace.activateCommonPreset(name: L10n.text(name), rules: rules)
        selectedRule = nil
        showPresetManager = false
    }

    private var presetManager: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("切换与管理方案")).font(.headline)
            TextField(L10n.text("搜索方案"), text: $presetQuery).textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(workspace.presets.filter { presetQuery.isEmpty || $0.name.localizedStandardContains(presetQuery) }) { preset in
                        HStack(spacing: 10) {
                            Button {
                                workspace.activatePreset(preset); selectedRule = nil; showPresetManager = false
                            } label: { presetChoice(preset.name, example: preset.example ?? "", selected: workspace.currentPresetID == preset.id) }
                            .buttonStyle(.plain)
                            Button {
                                renamingPresetID = preset.id; renamingPresetName = preset.name
                                renamingPresetExample = preset.example ?? ""
                                showPresetManager = false; showPresetRename = true
                            } label: { Image(systemName: "pencil") }
                            .buttonStyle(.borderless).help(L10n.text("重命名方案"))
                            Button(role: .destructive) { workspace.deletePreset(preset.id) } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless).help(L10n.text("删除方案"))
                        }
                    }
                    if workspace.presets.isEmpty {
                        Text(L10n.text("保存当前规则后，方案会显示在这里。")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.frame(maxHeight: 280)
            Divider()
            Button { setCommonPreset("自定义规则", rules: []) } label: {
                Text(L10n.text("新建方案")).frame(maxWidth: .infinity, minHeight: 30)
            }
            HStack {
                Button(L10n.text("保存当前修改")) {
                    if workspace.currentPresetID != nil { workspace.updateCurrentPreset() }
                    else { saveAsNewPreset() }
                }.disabled(workspace.currentPresetID != nil && !workspace.presetModified)
                Spacer()
                Button(L10n.text("另存为新方案…")) { saveAsNewPreset() }
            }
            HStack(spacing: 10) {
                Spacer()
                Button(L10n.text("导入方案…")) { showPresetManager = false; importPreset() }
                Button(L10n.text("导出方案…")) { showPresetManager = false; exportPreset() }
            }

        }.padding(16).frame(width: 420)
        .accessibilityIdentifier("renamePresetPopover")
    }

    private func presetChoice(_ name: String, example: String, selected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(name).fontWeight(.medium).lineLimit(1)
                if !example.isEmpty { Text(example).font(.caption).foregroundStyle(.secondary).lineLimit(1).help(example) }
            }
            Spacer()
            if selected { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
        }.padding(.vertical, 4).contentShape(Rectangle())
    }

    private func saveAsNewPreset() {
        workspace.presetName = workspace.currentPresetName
        showPresetManager = false; showPresetSave = true
    }

    private var selectedStepTitle: String {
        workspace.rules.firstIndex(where: { $0.id == selectedRule }).map { L10n.text("第 %1$@ 条执行后", $0 + 1) }
            ?? L10n.text("步骤结果")
    }

    private var visibleRows: [RenamePreview] {
        var rows = workspace.rows.filter { row in
            switch resultFilter {
            case "changes": return row.changes
            case "unchanged": return !row.changes
            case "conflict": return row.issues.contains(.conflict)
            case "error": return row.issues.contains(.invalidName) || row.issues.contains(.metadataFailure)
            case "skipped": return row.issues.contains(.excluded) || row.issues.contains(.missingDate) || row.issues.contains(.missingTag)
            default: return true
            }
        }
        if viewingSort == "final" { rows.sort { $0.target.lastPathComponent.localizedStandardCompare($1.target.lastPathComponent) == .orderedAscending } }
        if viewingSort == "status" { rows.sort { ($0.issues.first?.rawValue ?? "") < ($1.issues.first?.rawValue ?? "") } }
        return rows
    }

    private var fileControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker(L10n.text("处理顺序"), selection: $workspace.settings.sort) {
                    ForEach(RenameSettings.Sort.allCases, id: \.self) { Text(RenameLabels.sort($0)).tag($0) }
                }.frame(maxWidth: 260)
                Toggle(L10n.text("降序"), isOn: $workspace.settings.descending).disabled(workspace.settings.sort == .manual)
                Button(L10n.text("筛选处理文件…")) { showFileFilter = true }
                    .popover(isPresented: $showFileFilter) { fileFilterPanel }
                Spacer()
                Button(L10n.text("撤销文件排序")) { workspace.undoFileOrder() }
                    .disabled(!workspace.canUndoFileOrder)
            }
            if workspace.settings.sort == .metadata {
                HStack {
                    TextField(L10n.text("元数据排序标签"), text: Binding(get: { workspace.settings.metadataSortTag ?? "" },
                                                                         set: { workspace.settings.metadataSortTag = $0 }))
                    Menu(L10n.text("选择字段")) {
                        ForEach(workspace.availableTags, id: \.self) { tag in
                            Button(tag) { workspace.settings.metadataSortTag = tag }
                        }
                    }
                }
            }
            HStack {
                Picker(L10n.text("查看筛选"), selection: $resultFilter) {
                    Text(L10n.text("全部")).tag("all")
                    Text(L10n.text("将重命名")).tag("changes")
                    Text(L10n.text("名称不变")).tag("unchanged")
                    Text(L10n.text("冲突")).tag("conflict")
                    Text(L10n.text("错误")).tag("error")
                    Text(L10n.text("跳过")).tag("skipped")
                }
                Picker(L10n.text("查看排序"), selection: $viewingSort) {
                    Text(L10n.text("处理顺序")).tag("processing")
                    Text(L10n.text("新文件名")).tag("final")
                    Text(L10n.text("状态")).tag("status")
                }
                Text(L10n.text("查看排序和筛选不改变编号；拖动文件名可调整处理顺序。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(L10n.text("本次处理 %1$@ 组／%2$@ 个文件，当前显示 %3$@ 个文件", Set(workspace.rows.map(\.group)).count, workspace.rows.count, visibleRows.count))
                .font(.caption).foregroundStyle(.secondary)
        }.padding(12).disabled(workspace.executing || store.saveInProgress)
    }

    private var fileFilterPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("筛选本次处理文件")).font(.headline)
            Form {
                TextField(L10n.text("文件名或路径"), text: $workspace.fileFilter.query)
                TextField(L10n.text("文件扩展名"), text: $workspace.fileFilter.fileExtension)
                TextField(L10n.text("文件夹"), text: $workspace.fileFilter.folder)
                TextField(L10n.text("相机厂商或型号"), text: $workspace.fileFilter.camera)
                Toggle(L10n.text("限制起始时间"), isOn: Binding(get: { workspace.fileFilter.dateFrom != nil }, set: { workspace.fileFilter.dateFrom = $0 ? .now : nil }))
                if workspace.fileFilter.dateFrom != nil {
                    DatePicker(L10n.text("起始时间"), selection: Binding(get: { workspace.fileFilter.dateFrom ?? .now }, set: { workspace.fileFilter.dateFrom = $0 }))
                }
                Toggle(L10n.text("限制结束时间"), isOn: Binding(get: { workspace.fileFilter.dateTo != nil }, set: { workspace.fileFilter.dateTo = $0 ? .now : nil }))
                if workspace.fileFilter.dateTo != nil {
                    DatePicker(L10n.text("结束时间"), selection: Binding(get: { workspace.fileFilter.dateTo ?? .now }, set: { workspace.fileFilter.dateTo = $0 }))
                }
                Picker(L10n.text("定位"), selection: $workspace.fileFilter.gps) {
                    Text(L10n.text("全部")).tag(0); Text(L10n.text("有定位")).tag(1); Text(L10n.text("无定位")).tag(2)
                }
                TextField(L10n.text("元数据标签"), text: $workspace.fileFilter.tag)
                Picker(L10n.text("字段值"), selection: $workspace.fileFilter.presence) {
                    Text(L10n.text("不限")).tag(0); Text(L10n.text("有值")).tag(1); Text(L10n.text("未填写")).tag(2)
                }
            }.formStyle(.grouped)
            Text(L10n.text("筛选决定本次处理范围，编号按筛选后顺序重新计算；关联文件整组保留。"))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(L10n.text("重置筛选")) { workspace.fileFilter = RenameFileFilter() }
                Spacer()
                Button(L10n.text("完成")) { showFileFilter = false }
            }
        }.padding(16).frame(width: 460)
    }

    private func originalCell(_ row: RenamePreview) -> some View {
        Text(row.source.lastPathComponent).help(row.source.path)
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
            .contextMenu {
                Button(L10n.text("上移文件组")) { moveGroup(row, down: false) }
                Button(L10n.text("下移文件组")) { moveGroup(row, down: true) }
            }
    }

    private func dropFiles(_ items: [String], at index: Int) {
        guard viewingSort == "processing", resultFilter == "all", !store.saveInProgress else { return }
        let rows = visibleRows
        guard (0...rows.count).contains(index) else { return }
        let groups = Set(items.flatMap { item -> [String] in
            guard let data = item.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        })
        workspace.moveFiles(groups, before: index < rows.count ? rows[index].group : "")
    }

    private func dragPayload(_ row: RenamePreview) -> String {
        guard viewingSort == "processing", resultFilter == "all", !workspace.busy, !workspace.executing, !store.saveInProgress else { return "" }
        let groups = workspace.selectedRows.contains(row.source)
            ? Set(workspace.rows.filter { workspace.selectedRows.contains($0.source) }.map(\.group)) : [row.group]
        return String(data: (try? JSONEncoder().encode(Array(groups))) ?? Data(), encoding: .utf8) ?? ""
    }

    private func moveGroup(_ row: RenamePreview, down: Bool) {
        guard viewingSort == "processing", resultFilter == "all", !store.saveInProgress else { return }
        var seen = Set<String>()
        let groups = workspace.rows.map(\.group).filter { seen.insert($0).inserted }
        guard let index = groups.firstIndex(of: row.group) else { return }
        if down, index + 1 < groups.count { workspace.moveFiles([groups[index + 1]], before: row.group) }
        else if !down, index > 0 { workspace.moveFiles([row.group], before: groups[index - 1]) }
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
            fileControls
            Divider()
            Table(of: RenamePreview.self, selection: $workspace.selectedRows, columnCustomization: $tableColumns) {
                TableColumn(L10n.text("预览")) { row in
                    if let image = store.imageData.first(where: { $0.metadataCreatorImageURL == row.source }) {
                        PhotoThumbnail(image: image, maxDimension: 100).frame(width: 38, height: 32)
                    } else {
                        Image(systemName: "doc").foregroundStyle(.secondary).frame(width: 38, height: 32)
                    }
                }.width(46)
                    .customizationID("preview").disabledCustomizationBehavior(.all)
                TableColumn(L10n.text("原文件名")) { row in originalCell(row) }
                    .width(min: 140, ideal: 170)
                    .customizationID("original").disabledCustomizationBehavior([.reorder, .visibility])
                TableColumn(selectedStepTitle) { row in
                    Text(selectedRule == nil ? L10n.text("选择操作以查看")
                         : row.steps.first(where: { $0.id == selectedRule })?.name ?? "—")
                        .foregroundStyle(.secondary)
                }.width(min: 120, ideal: 140)
                    .customizationID("step").disabledCustomizationBehavior([.reorder, .visibility])
                TableColumn(L10n.text("新文件名")) { row in
                    Text(row.target.lastPathComponent).foregroundStyle(row.changes ? Color.primary : Color.secondary)
                        .help(row.target.path)
                }.width(min: 160, ideal: 200)
                    .customizationID("final").disabledCustomizationBehavior([.reorder, .visibility])
                TableColumn(L10n.text("状态")) { row in
                    if let issue = row.issues.first(where: { $0 == .conflict || $0 == .invalidName }) ?? row.issues.first {
                        Label(RenameCopy.issue(issue), systemImage: row.issues.contains(.conflict) || row.issues.contains(.invalidName) ? "xmark.octagon" : "info.circle")
                            .foregroundStyle(row.issues.contains(.conflict) || row.issues.contains(.invalidName) ? Color.red : Color.secondary)
                            .help(RenameCopy.issue(issue))
                    } else {
                        Label(L10n.text("将重命名"), systemImage: "checkmark.circle").foregroundStyle(.green)
                    }
                }.width(120)
                    .customizationID("status").disabledCustomizationBehavior(.all)
            } rows: {
                ForEach(visibleRows) { row in
                    TableRow(row).draggable(dragPayload(row))
                }.dropDestination(for: String.self) { index, items in dropFiles(items, at: index) }
            }
            .background(IndependentTableColumns(fitToViewport: true))
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
                    Button(L10n.text("取消操作选择")) { selectedRule = nil }.font(.caption)
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
    let original = RenameAction.all.reduce(into: [String]()) { if !$0.contains($1.categoryChinese) { $0.append($1.categoryChinese) } }
    let categories: [String] = {
        var ordered = original.filter { !["自定义（通用标签）", "设备信息", "定位信息"].contains($0) }
        if let index = ordered.firstIndex(of: "日期与时间") {
            ordered.insert(contentsOf: ["设备信息", "定位信息"], at: index + 1)
        }
        return ordered + ["自定义（通用标签）"]
    }()
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

struct RenameRuleCard: View {
    @Binding var rule: RenameRule
    @Binding var selectedRule: UUID?
    var collapseToken: UUID? = nil
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
        guard let action = RenameAction.all.first(where: { $0.number == rule.action }) else { return "R\(rule.action)" }
        let category: String
        if (100...111).contains(rule.action) {
            let field = rule.metadataField ?? (rule.action < 106 ? "CameraModel" : "IPTCCity")
            category = renameMetadataFields(device: rule.action < 106).first(where: { $0.0 == field })?.1 ?? action.categoryChinese
        } else { category = action.categoryChinese }
        return L10n.text(category) + " · " + L10n.text(action.titleChinese)
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
                Menu(L10n.text("更换动作")) {
                    actionMenu { action in
                        if (100...105).contains(rule.action) != (100...105).contains(action.number) { rule.metadataField = nil }
                        rule.action = action.number; selectedRule = rule.id
                    }
                }
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
        .background(selectedRule == rule.id ? Color.blue.opacity(0.08) : Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 10))
    }

    var body: some View {
        cardContents
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(
            selectedRule == rule.id ? Color.blue : Color.secondary.opacity(0.18),
            lineWidth: selectedRule == rule.id ? 1.5 : 1))
        .focused($editing)
        .onAppear { if collapseToken != nil { expanded = false } }
        .onChange(of: collapseToken) { if collapseToken != nil { expanded = false } }
        .simultaneousGesture(TapGesture().onEnded { selectedRule = rule.id })
        .onChange(of: editing) { if editing { selectedRule = rule.id } }
        .onChange(of: selectedRule) {
            if selectedRule != rule.id { editing = false }
        }
        .onChange(of: rule) { if editing { selectedRule = rule.id } }
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
    private var needsAnchor: Bool { [3,4,15,16,43,44,49,50,57,58,63,64,70,71,75,76,81,82,86,87,91,92,104,105,110,111].contains(action) }
    private var needsPosition: Bool { [5,14,26,27,45,51,59,65,69,77,83,88,93,103,109].contains(action) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if (100...111).contains(action) {
                Picker(L10n.text("字段"), selection: Binding(
                    get: { rule.metadataField ?? (action < 106 ? "CameraModel" : "IPTCCity") },
                    set: { rule.metadataField = $0 })) {
                    ForEach(renameMetadataFields(device: action < 106), id: \.0) { field in
                        Text(L10n.text(field.1)).tag(field.0)
                    }
                }
                affixFields
            }
            if action <= 19 || [32,94,95,96,97].contains(action) || (66...77).contains(action) {
                if [32,94].contains(action) || (66...77).contains(action) {
                    Text(L10n.text(action == 94 ? "每行新名称，或旧名与新名的 TSV" : action == 32 ? "词汇大小写例外（每行一个）" : "标签模板，例如 <CameraModel>"))
                        .font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $rule.text)
                        .font(.system(.callout, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .background(Color(nsColor: .textBackgroundColor))
                        .foregroundStyle(.primary)
                        .frame(height: 80)
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
                affixFields
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
            if (40...45).contains(action) || (66...83).contains(action) || action == 94 || (89...93).contains(action) || (100...111).contains(action) {
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
            affixFields
            Toggle(L10n.text("每个目录独立编号"), isOn: $rule.perDirectory)
        }
    }

    private var affixFields: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                TextField(L10n.text("前缀"), text: $rule.prefix)
                TextField(L10n.text("后缀"), text: $rule.suffix)
            }
            Text(L10n.text("通常用于添加分隔符；完整文字请使用文字卡片。"))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
        case .fileExtension: L10n.text("文件扩展名")
        case .folder: L10n.text("文件夹")
        case .size: L10n.text("文件大小")
        case .make: L10n.text("相机厂商")
        case .model: L10n.text("相机型号")
        case .city: L10n.text("城市")
        case .rating: L10n.text("评分")
        case .metadata: L10n.text("元数据字段")
        case .manual: L10n.text("手动顺序")
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

private func renameMetadataFields(device: Bool) -> [(String, String)] {
    device ? [("CameraModel", "设备型号"), ("CameraMake", "设备品牌"), ("Lens", "镜头型号"), ("CameraSerialNumber", "设备序列号")]
        : [("IPTCCity", "城市"), ("IPTCProvinceState", "省／州"), ("IPTCSubLocation", "区／县"),
           ("IPTCCountry", "国家"), ("CountryCode", "国家代码"), ("GPSLatitude", "纬度"), ("GPSLongitude", "经度")]
}
