import AppKit
import ImageData
import SwiftUI
import UDF
import UniformTypeIdentifiers

struct RenameWorkspaceView: View {
    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) private var store
    @Bindable var workspace: RenameWorkspace
    @State private var selectedRule: UUID?
    @State private var confirm = false
    @State private var showHistory = false
    @State private var showPresetSave = false
    @State private var showAdvanced = false
    @State private var confirmSaveFirst = false
    @State private var awaitingSave = false

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
        .environment(workspace)
        .accessibilityIdentifier("renameWorkspace")
        .task {
            workspace.initializeScope(selection: store.selection)
            refresh()
        }
        .onChange(of: workspace.rules) { refresh() }
        .onChange(of: workspace.settings) { refresh() }
        .onChange(of: workspace.onlySelected) { refresh() }
        .onChange(of: workspace.includeImportedPhotos) { refresh() }
        .onChange(of: workspace.extraURLs) { refresh() }
        .onChange(of: workspace.authorizedDirectories) { refresh() }
        .onChange(of: workspace.counterRevision) { refresh() }
        .onChange(of: store.selection) { if workspace.onlySelected { refresh() } }
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
        .sheet(isPresented: $showHistory) { historySheet }
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
                Menu(L10n.text("预设方案")) {
                    Button(L10n.text("保存当前预设…")) { showPresetSave = true }
                    if !workspace.presets.isEmpty {
                        Divider()
                        ForEach(workspace.presets) { preset in
                            Button(preset.name) { workspace.rules = preset.rules; workspace.settings = preset.settings }
                        }
                        Menu(L10n.text("删除预设")) {
                            ForEach(workspace.presets) { preset in
                                Button(preset.name) { workspace.presets.removeAll { $0.id == preset.id }; workspace.persistPresets() }
                            }
                        }
                    }
                    Divider()
                    Button(L10n.text("导入预设…")) { importPreset() }
                    Button(L10n.text("导出预设…")) { exportPreset() }
                }.fixedSize()
            }.padding(14)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.text("本次处理范围")).font(.headline)
                    Toggle(L10n.text("包含已导入照片"), isOn: $workspace.includeImportedPhotos)
                    if workspace.includeImportedPhotos {
                        Picker(L10n.text("照片范围"), selection: $workspace.onlySelected) {
                            Text(L10n.text("全部导入照片")).tag(false)
                            Text(L10n.text("选中照片及配对文件")).tag(true)
                        }
                        Text(L10n.text("照片：%1$@ · 额外文件：%2$@；配对文件一并列入右侧预览。",
                            store.imageData.filter { (!workspace.onlySelected || store.selection.contains($0.id)) && $0.metadataCreatorImageURL != nil }.count,
                            workspace.extraURLs.count))
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(L10n.text("额外文件：%1$@；配对文件一并列入右侧预览。", workspace.extraURLs.count))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                    Menu(L10n.text("从常用方案开始")) {
                        Button(L10n.text("拍摄日期＋编号")) { setRules([RenameRule(action: 40), RenameRule(action: 48, prefix: "_")]) }
                        Button(L10n.text("保留原名加前缀")) { setRules([RenameRule(action: 1)]) }
                        Button(L10n.text("查找并替换")) { setRules([RenameRule(action: 11)]) }
                        Button(L10n.text("自定义规则")) { setRules([]) }
                    }
                    ForEach($workspace.rules) { $rule in
                        RenameRuleCard(rule: $rule, selectedRule: $selectedRule,
                                       index: workspace.rules.firstIndex(where: { $0.id == rule.id }) ?? 0,
                                       count: workspace.rules.count,
                                       move: { move(rule.id, offset: $0) },
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
                    Text(L10n.text("任务选项")).font(.headline)
                    Picker(L10n.text("排序"), selection: $workspace.settings.sort) {
                        ForEach(RenameSettings.Sort.allCases, id: \.self) { Text(RenameLabels.sort($0)).tag($0) }
                    }
                    Toggle(L10n.text("降序"), isOn: $workspace.settings.descending)
                    Toggle(L10n.text("保持照片与旁车同名"), isOn: $workspace.settings.pair)
                    if workspace.settings.pair {
                        Text(L10n.text("同目录、同主体的照片与旁车会加入预览，请核对实际文件范围。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Picker(L10n.text("文件名冲突"), selection: $workspace.settings.conflict) {
                        Text(L10n.text("阻止执行")).tag(RenameSettings.Conflict.stop)
                        Text(L10n.text("添加数字后缀")).tag(RenameSettings.Conflict.numbers)
                        Text(L10n.text("添加字母后缀")).tag(RenameSettings.Conflict.letters)
                    }
                    Toggle(L10n.text("第一项保留无后缀名称"), isOn: $workspace.settings.keepFirst)
                    DisclosureGroup(L10n.text("高级设置"), isExpanded: $showAdvanced) {
                        VStack(alignment: .leading, spacing: 10) {
                            TextField(L10n.text("配对来源扩展名"), text: $workspace.settings.sourceExtensions)
                            TextField(L10n.text("配对目标扩展名"), text: $workspace.settings.targetExtensions)
                            Text(L10n.text("拍摄时间来源优先级（每行一个标签）")).font(.caption)
                            TextEditor(text: $workspace.settings.datePriority)
                                .font(.system(.caption, design: .monospaced)).frame(height: 150)
                                .border(Color.secondary.opacity(0.2))
                        }.padding(.top, 8)
                    }
                    Button(L10n.text("执行记录与恢复…")) { showHistory = true }
                }.padding(14)
            }
        }
        .disabled(workspace.executing || store.saveInProgress)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func setRules(_ rules: [RenameRule]) {
        workspace.rules = rules
        selectedRule = nil
    }

    private func move(_ id: UUID, offset: Int) {
        guard let index = workspace.rules.firstIndex(where: { $0.id == id }),
              workspace.rules.indices.contains(index + offset) else { return }
        workspace.rules.swapAt(index, index + offset)
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
                Button(L10n.text("添加文件…")) { addFiles() }
                    .disabled(workspace.executing || store.saveInProgress)
                    .accessibilityIdentifier("renameAddFiles")
                if !workspace.extraURLs.isEmpty {
                    Button(L10n.text("清空额外文件")) { workspace.extraURLs = [] }
                        .disabled(workspace.executing || store.saveInProgress)
                }
                if !workspace.rows.isEmpty && !workspace.directoriesAuthorized {
                    Button(L10n.text("授权文件目录…")) { authorizeDirectories(workspace.rows.map(\.source)) }
                        .disabled(workspace.executing || store.saveInProgress)
                }
                if workspace.busy { ProgressView().controlSize(.small) }
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
                TableColumn(L10n.text("原文件名")) { row in Text(row.source.lastPathComponent).help(row.source.path)
                        .contextMenu {
                            if workspace.extraURLs.contains(row.source) {
                                Button(L10n.text("从重命名页移除")) { workspace.removeFile(row.source) }
                            }
                        } }
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
            .overlay {
                if workspace.rows.isEmpty && !workspace.busy {
                    ContentUnavailableView(L10n.text("暂无可重命名的文件"), systemImage: "character.cursor.ibeam",
                                           description: Text(L10n.text("导入本地照片或添加文件后设置规则，先核对预览，再执行改名。照片图库项目不支持文件改名。")))
                }
            }
            if let row = workspace.rows.first(where: { workspace.selectedRows.contains($0.source) }) {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(row.source.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        ForEach(row.steps) { step in
                            HStack(alignment: .firstTextBaseline) {
                                let action = workspace.rules.first(where: { $0.id == step.id })?.action ?? 0
                                Text("R\(action)").font(.caption.monospaced()).frame(width: 38, alignment: .leading)
                                Text(step.name).textSelection(.enabled)
                                Spacer()
                                if let issue = step.issue { Text(RenameCopy.issue(issue)).foregroundStyle(.secondary).font(.caption) }
                            }
                        }
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 140)
            }
            Divider()
            HStack {
                Text(L10n.text("选行可查看改名过程；执行范围以上方设置和完整预览为准。"))
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
                    if workspace.executing {
                        ProgressView().controlSize(.small)
                        if workspace.restoring { Text(L10n.text("恢复原名")) }
                        else { Button(L10n.text("停止并恢复")) { workspace.cancel() } }
                    } else {
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

    private var historySheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("执行记录与恢复")).font(.title2)
            Text(L10n.text("恢复前核对文件身份、内容与原名占用；不会覆盖后来创建的文件。"))
                .foregroundStyle(.secondary)
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
                            .disabled(workspace.executing || store.saveInProgress || dirty)
                    }
                }
            }
            if !workspace.notice.isEmpty { Text(workspace.notice).font(.callout) }
            HStack { Spacer(); Button(L10n.text("完成")) { showHistory = false }.keyboardShortcut(.cancelAction) }
        }.padding(20).frame(width: 700, height: 450)
    }

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            authorizeDirectories(panel.urls)
            workspace.addFiles(panel.urls)
        }
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

private struct RenameRuleCard: View {
    @Binding var rule: RenameRule
    @Binding var selectedRule: UUID?
    let index: Int
    let count: Int
    let move: (Int) -> Void
    let remove: () -> Void
    let duplicate: () -> Void
    @State private var expanded = true
    private var title: String { RenameAction.all.first(where: { $0.number == rule.action }).map { L10n.text($0.titleChinese) } ?? "R\(rule.action)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Toggle("", isOn: $rule.enabled).labelsHidden().toggleStyle(.checkbox)
                    .accessibilityLabel(L10n.text("启用规则"))
                Button { expanded.toggle(); selectedRule = rule.id } label: {
                    HStack { Text("\(index + 1)").monospacedDigit().foregroundStyle(.secondary)
                        Text(title).fontWeight(.medium)
                        Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.caption) }
                }.buttonStyle(.plain)
                Spacer(minLength: 0)
                Menu {
                    Button(L10n.text("上移")) { move(-1) }.disabled(index == 0)
                    Button(L10n.text("下移")) { move(1) }.disabled(index == count - 1)
                    Button(L10n.text("复制规则"), action: duplicate)
                    Button(L10n.text("删除规则"), role: .destructive, action: remove)
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
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
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selectedRule == rule.id ? Color.blue.opacity(0.55) : Color.secondary.opacity(0.18)))
        .onTapGesture { selectedRule = rule.id }
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
