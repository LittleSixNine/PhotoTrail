import AppKit
import Exiftool
import ImageData
import SwiftUI
import UDF
import UniformTypeIdentifiers

struct MetadataBatchEditView: View {
    @Bindable var session: MetadataBatchEditSession
    var visiblePhotoIDs: Set<ImageData.ID>?
    var close: () -> Void
    var saved: ((MetadataPreset) -> Void)?
    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) private var store
    @AppStorage("PhotoTrail.MetadataPresets") private var presetData = Data()
    @AppStorage(MetadataPresetParameters.key) private var parameterData = Data()
    @AppStorage("PhotoTrail.MetadataPresetShortcuts") private var shortcutData = Data()
    @State private var selectedCard: UUID?
    @State private var choosingAction = false
    @State private var showingExamples = false
    @State private var naming = false
    @State private var name = ""
    @State private var notice = ""
    @State private var discard = false

    private var cards: [MetadataWorkflowCard] {
        get { session.workflowCards ?? [] }
        nonmutating set { session.workflowCards = newValue }
    }
    private var currentScope: Bool { MetadataDraftRequest(readings: session.readings).matches(store.state) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("批量编辑")).font(.headline)
                    Text(L10n.text("已选择 %1$@ 张照片", session.readings.count)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    ForEach(presets, id: \.name) { preset in
                        Button(preset.name) { load(preset) }
                    }
                } label: { Label(L10n.text("载入预设"), systemImage: "bookmark") }
                Button(L10n.text("返回字段列表"), systemImage: "chevron.left", action: close)
            }.padding(14)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !currentScope {
                        Text(L10n.text("选择或照片内容已变化。请返回字段列表后重新开始，当前输入会保留到你关闭编辑。"))
                            .font(.callout).foregroundStyle(.orange)
                    }
                    if cards.isEmpty { actionChoices }
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        MetadataOperationCardView(operations: operationBinding(card.id), readings: session.readings,
                            selected: Binding(get: { selectedCard == card.id }, set: { selectedCard = $0 ? card.id : nil }),
                            availableTags: MetadataTag.allCases, index: index,
                            moveUp: index > 0 ? { cards.swapAt(index, index - 1) } : nil,
                            moveDown: index + 1 < cards.count ? { cards.swapAt(index, index + 1) } : nil,
                            remove: { cards.removeAll { $0.id == card.id } }, inlineLayout: true,
                            datePolicy: policyBinding(card.id), duplicate: { cards.insert(card.duplicated(), at: index + 1) })
                            .contextMenu {
                                Button(L10n.text("复制修改项")) { cards.insert(card.duplicated(), at: index + 1) }
                            }
                    }
                    if !cards.isEmpty {
                        if choosingAction { actionChoices }
                        else { Button(L10n.text("添加操作"), systemImage: "plus") { choosingAction = true } }
                    }
                    if !session.statisticsError.isEmpty {
                        Text(session.statisticsError).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                    }
                    if let preview = session.recipePreview, !preview.issues.isEmpty {
                        let groups = Dictionary(grouping: preview.issues, by: \.photoID)
                        DisclosureGroup(L10n.text("%1$@ 张照片有跳过项", groups.count)) {
                            ForEach(session.readings.filter { groups[$0.image.id] != nil }, id: \.image.id) { reading in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(reading.image.name)
                                    ForEach(Array(Set((groups[reading.image.id] ?? []).map(\.reason))).sorted(), id: \.self) { reason in
                                        Text(reason).foregroundStyle(.secondary)
                                    }
                                }.font(.caption).padding(.vertical, 4)
                            }
                        }.font(.callout).foregroundStyle(.orange)
                    }
                    if !cards.isEmpty {
                        DisclosureGroup(L10n.text("修改前后"), isExpanded: $showingExamples) {
                            if let preview = session.recipePreview { examples(preview.preview) }
                        }.font(.callout)
                    }
                }.padding(14)
                .disabled(session.application.busy)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if !notice.isEmpty { Text(notice).font(.caption).foregroundStyle(.secondary) }
                if session.application.result == nil && !session.application.notice.isEmpty {
                    Text(session.application.notice).font(.caption).foregroundStyle(.orange)
                }
                if let preview = session.recipePreview {
                    Text(L10n.text("将修改：%1$@ 张 · 无变化：%2$@ 张 · 未处理：%3$@ 张",
                        preview.preview.items.count, Set(preview.preview.steps.map(\.id)).subtracting(preview.preview.items.map(\.id)).count,
                        session.readings.count - Set(preview.preview.steps.map(\.id)).count))
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Menu {
                        Button(L10n.text("存为预设…")) { name = ""; naming = true }
                        if let presetName = session.presetName {
                            Button(L10n.text("更新预设")) { save(name: presetName, replace: true) }
                        }
                    } label: { Label(L10n.text("保存预设"), systemImage: "bookmark") }
                        .disabled(!session.isValid || session.application.busy)
                    Spacer(minLength: 6)
                    if session.statisticsBusy || session.application.busy { ProgressView().controlSize(.small) }
                    Button(L10n.text("取消")) { discard = true }.labelStyle(.titleOnly)
                        .disabled(session.application.busy)
                    Button(L10n.text("应用到 %1$@ 张照片", session.readings.count)) {
                        session.application.apply(readings: session.readings, operations: [], cards: cards, store: store)
                    }.buttonStyle(.borderedProminent)
                        .disabled(!session.isValid || !currentScope || session.statisticsBusy || !session.statisticsError.isEmpty || session.application.busy || store.saveInProgress)
                        .accessibilityIdentifier("metadataBatchApply")
                }
            }.padding(14)
        }
        .textFieldStyle(.roundedBorder)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if session.workflowCards == nil {
                session.workflowCards = session.fields.map { field in
                    MetadataWorkflowCard(operations: [MetadataOperation(tag: field.tag,
                        action: field.tag == .creator ? .replaceAuthors(field.input.split(separator: "\n").map(String.init))
                            : field.tag.isList ? .replaceKeywords(field.input.split(separator: "\n").map(String.init)) : .setText(field.input))])
                }
            }
            selectedCard = cards.first?.id
            session.refreshStatistics()
        }
        .onChange(of: cards) { session.application.resetFeedback(); session.refreshStatistics() }
        .onChange(of: store.state) { session.application.stateChanged(store.state) }
        .onChange(of: session.application.busy) {
            if !session.application.busy && session.application.result != nil { close() }
        }
        .onDisappear { session.cancelStatistics(); session.application.cancel() }
        .alert(L10n.text("存为预设…"), isPresented: $naming) {
            TextField(L10n.text("预设名称"), text: $name)
            Button(L10n.text("取消"), role: .cancel) {}
            Button(L10n.text("保存")) { save(name: name, replace: false) }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .confirmationDialog(L10n.text("放弃尚未应用的输入？"), isPresented: $discard) {
            Button(L10n.text("放弃输入并关闭"), role: .destructive) { session.discardInput(); close() }
            Button(L10n.text("继续编辑"), role: .cancel) {}
        }
        .accessibilityIdentifier("metadataBatchForm")
    }

    private var presets: [MetadataPreset] { (try? MetadataPreset.stored(in: presetData)) ?? [] }
    private var actionChoices: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(["set", "copy", "offset", "clear", "filename"], id: \.self) { mode in
                Button { add(mode) } label: {
                    Label(L10n.text(["set": "设置值", "copy": "复制字段", "offset": "调整时间", "clear": "清除字段", "filename": "从文件名恢复拍摄时间"][mode] ?? "添加操作"),
                          systemImage: ["set": "textformat", "copy": "doc.on.doc", "offset": "clock", "clear": "eraser", "filename": "calendar"][mode] ?? "plus")
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                }
            }
        }
    }
    private func add(_ mode: String) {
        let operation: MetadataOperation
        switch mode {
        case "copy": operation = MetadataOperation(tag: .dateOriginal, action: .copy(.captureDate))
        case "offset": operation = MetadataOperation(tag: .captureDate, action: .offsetDate(years: 0, months: 0, days: 0, hours: 1, minutes: 0, seconds: 0))
        case "clear": operation = MetadataOperation(tag: .titleDefault, action: .remove)
        case "filename": operation = MetadataOperation(tag: .captureDate, action: MetadataFilenameDateFormat.compactDateTime.action)
        default: operation = MetadataOperation(tag: .titleDefault, action: .setText(""))
        }
        let card = MetadataWorkflowCard(operations: [operation]); cards.append(card); selectedCard = card.id; choosingAction = false
    }
    private func operationBinding(_ id: UUID) -> Binding<[MetadataOperation]> {
        Binding(get: { cards.first { $0.id == id }?.operations ?? [] }, set: { value in
            if let index = cards.firstIndex(where: { $0.id == id }) { cards[index].operations = value }
        })
    }
    private func policyBinding(_ id: UUID) -> Binding<MetadataDateCopyPolicy> {
        Binding(get: { cards.first { $0.id == id }?.datePolicy ?? .init() }, set: { value in
            if let index = cards.firstIndex(where: { $0.id == id }) { cards[index].datePolicy = value }
        })
    }
    private func load(_ preset: MetadataPreset) {
        do { cards = try MetadataPresetParameters.cards(preset, data: parameterData); session.presetName = preset.name; selectedCard = cards.first?.id }
        catch { notice = L10n.text("预设无法读取，原数据已保留。") }
    }
    private func save(name: String, replace: Bool) {
        do {
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let data = try MetadataPresetSession.stored(name: name, cards: cards, presetData: presetData, parameterData: parameterData, replace: replace)
            presetData = data.0; parameterData = data.1; session.presetName = name
            let presets = try MetadataPreset.stored(in: data.0)
            shortcutData = MetadataPresetShortcuts.updating(name, enabled: true, in: presets, data: shortcutData)
            let preset = try MetadataPreset(name: name, operations: cards.flatMap(\.operations))
            saved?(preset)
            session.discardInput()
            close()
        } catch { notice = L10n.text("预设未保存，请检查名称、参数或已有预设数据。") }
    }
    private func examples(_ result: MetadataWorkflowPreview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(session.readings.prefix(3), id: \.image.id) { reading in
                let item = result.items.first { $0.id == reading.image.id }
                VStack(alignment: .leading, spacing: 4) {
                    Text(reading.image.name).fontWeight(.medium)
                    ForEach(Array(Set(cards.flatMap(\.operations).map(\.tag))).sorted { $0.rawValue < $1.rawValue }, id: \.self) { tag in
                        let before = MetadataBatchValues.value(tag, in: reading)
                        let after: MetadataTagValue? = switch item?.changes[tag] {
                        case .set(let value): value
                        case .remove: nil
                        case nil: before
                        }
                        if before != after {
                            Text(tag.displayName + "\n" + MetadataBatchValues.text(before) + " → " + MetadataBatchValues.text(after))
                                .font(.caption).textSelection(.enabled)
                        }
                    }
                }
            }
        }.padding(.top, 8)
    }
}

struct MetadataInlineFieldEditor: View {
    @Bindable var session: MetadataBatchEditSession
    var close: () -> Void
    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) private var store
    @FocusState private var focused: Bool
    @State private var active = false

    private var field: MetadataBatchField { session.fields[0] }
    private var input: Binding<String> {
        Binding(get: { session.fields[0].input }, set: { value in
            session.fields[0].updateInput(value, clearEmpty: true)
            session.application.resetFeedback()
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top) {
                TextField(field.tag.inputExample, text: input, axis: .vertical)
                    .lineLimit(field.tag.isList || field.tag.isLongText ? 2...8 : 1...3)
                    .textFieldStyle(.roundedBorder).focused($focused)
                    .onSubmit { finish() }
                    .onPasteCommand(of: [.text]) { _ in paste() }
                    .focusedValue(\.metadataFieldClipboard, MetadataFieldClipboardActions(
                        copy: { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) },
                        paste: paste, textInput: true))
                    .accessibilityIdentifier("metadataInlineInput." + field.tag.rawValue)
                if !field.tag.numericUnit.isEmpty { Text(field.tag.numericUnit).font(.caption).foregroundStyle(.secondary) }
                if let choices = field.tag.numericChoices {
                    Menu {
                        ForEach(choices, id: \.0) { number, label in
                            Button(label) { input.wrappedValue = String(number); finish() }
                        }
                    } label: { Image(systemName: "chevron.down") }.fixedSize()
                } else if field.tag == .exifFlash {
                    Menu {
                        ForEach(field.tag.flashPresets, id: \.0) { number, label in
                            Button(label) { input.wrappedValue = String(number); finish() }
                        }
                    } label: { Image(systemName: "chevron.down") }.fixedSize()
                }
            }
            Text(field.tag.editorHint).font(.caption2).foregroundStyle(.secondary)
            if session.hasInput && !session.isValid && !session.application.busy {
                Text(L10n.text("输入格式无效，尚未加入待保存。请修改或按 Esc 放弃。"))
                    .font(.caption).foregroundStyle(.orange)
            }
            if session.application.busy { ProgressView().controlSize(.small) }
            if !session.application.notice.isEmpty && session.application.result == nil {
                Text(session.application.notice).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
            }
        }
        .disabled(session.application.busy)
        .onAppear { active = true; focused = true }
        .onChange(of: focused) { if !focused { finish() } }
        .onDisappear { active = false; if session.hasInput { finish() } }
        .onExitCommand { session.discardInput(); close() }
    }

    private func paste() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        Task { @MainActor in
            guard active else { return }
            if await session.pasteInline(text, in: store) { close() }
        }
    }

    private func finish() {
        Task { @MainActor in
            if await session.finishInline(in: store) { close() }
        }
    }
}

struct MetadataValueDistributionView: View {
    let tag: MetadataTag
    let readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)]
    var select: ((Set<ImageData.ID>) -> Void)?
    var use: ((MetadataTagValue?) -> Void)?
    @State private var individualItems = false

    var body: some View {
        let groups = individualItems ? MetadataBatchValues.items(tag, readings: readings)
            : MetadataBatchValues.groups(tag, readings: readings)
        VStack(alignment: .leading, spacing: 12) {
            Text(tag.displayName).font(.headline)
            Text(L10n.text("原有内容与已应用的草稿")) .font(.caption).foregroundStyle(.secondary)
            if tag.isList {
                Picker(L10n.text("查看方式"), selection: $individualItems) {
                    Text(L10n.text("完整列表" )).tag(false)
                    Text(L10n.text("项目覆盖数量")).tag(true)
                }.pickerStyle(.segmented)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top) {
                                Text(MetadataBatchValues.text(group.value)).textSelection(.enabled)
                                Spacer()
                                Text(L10n.text("%1$@ 张", group.photoIDs.count)).monospacedDigit().foregroundStyle(.secondary)
                            }
                            HStack {
                                if let use, !individualItems, group.value != nil { Button(L10n.text("使用此值")) { use(group.value) } }
                                if let select { Button(L10n.text("仅选这组照片")) { select(group.photoIDs) } }
                            }.font(.caption)
                        }
                        Divider()
                    }
                }
            }
        }.padding(16).frame(width: 350, height: min(420, CGFloat(groups.count) * 100 + 100))
    }
}

struct MetadataBatchResultView: View {
    let application: MetadataDraftApplication
    let readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)]
    var select: ((Set<ImageData.ID>) -> Void)?
    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) private var store

    var body: some View {
        if let result = application.result {
            let changed = Set(result.items.map(\.id))
            let processed = Set(result.steps.map(\.id)).union(changed)
            let unprocessed = Set(readings.map(\.image.id)).subtracting(processed)
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.text("已加入待保存：%1$@ 张 · 无变化：%2$@ 张 · 未处理：%3$@ 张",
                               changed.count, processed.subtracting(changed).count, unprocessed.count))
                    .font(.callout).accessibilityIdentifier("metadataBatchResult")
                if !result.skipDetails.isEmpty {
                    DisclosureGroup(L10n.text("跳过了 %1$@ 项字段操作，查看原因", result.skipDetails.count)) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(result.skipDetails.prefix(100).enumerated()), id: \.offset) { _, item in
                                Text(item.filename + " · " + item.tag.rawValue + " · " + reason(item.reason)).font(.caption).textSelection(.enabled)
                            }
                            if result.skipDetails.count > 100 { Text(L10n.text("仅显示前 100 项；选择未处理照片可继续检查。")) .font(.caption) }
                        }.padding(.top, 8)
                    }
                }
                if result.skipReasons.isEmpty && !result.skipped.isEmpty {
                    Text(result.skipped.joined(separator: "\n")).font(.caption)
                        .foregroundStyle(.orange).textSelection(.enabled)
                }
                if !unprocessed.isEmpty, let select {
                    Button(L10n.text("选中未处理照片")) { select(unprocessed) }
                }
                if !result.skipDetails.isEmpty, let select {
                    Button(L10n.text("选中有跳过项的照片")) { select(Set(result.skipDetails.map(\.photoID))) }
                }
                if application.applied {
                    Button(L10n.text("撤销本次批量修改"), systemImage: "arrow.uturn.backward") { application.undo(in: store) }
                        .disabled(!application.canUndo(in: store))
                }
            }
        }
    }

    private func reason(_ reason: MetadataWorkflowPreview.SkipReason) -> String {
        switch reason {
        case .missingValue: L10n.text("来源值缺失")
        case .filenameMismatch: L10n.text("文件名未匹配日期规则")
        case .unsupportedField: L10n.text("文件不支持此字段")
        }
    }
}
