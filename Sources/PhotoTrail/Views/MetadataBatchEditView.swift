import Exiftool
import ImageData
import SwiftUI
import UDF

struct MetadataBatchEditView: View {
    @Bindable var session: MetadataBatchEditSession
    var visiblePhotoIDs: Set<ImageData.ID>?
    var close: () -> Void
    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) private var store
    @AppStorage("PhotoTrail.MetadataPresets") private var presetData = Data()
    @State private var discardRequested = false
    @State private var namingPreset = false
    @State private var presetName = ""
    @State private var presetNotice = ""
    @State private var fieldPicker = false
    @State private var fieldQuery = ""
    @State private var editingField: MetadataBatchField?

    private var availableTags: [MetadataTag] {
        MetadataTag.allCases.filter { tag in session.readings.contains { $0.image.supportsMetadataEditing(tag) } }
    }
    private var currentScope: Bool { MetadataDraftRequest(readings: session.readings).matches(store.state) }
    private var visibleSelection: Set<ImageData.ID> { session.photoIDs.intersection(visiblePhotoIDs ?? session.photoIDs) }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(14)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !currentScope && !session.application.applied {
                        Label(L10n.text("选择或照片内容已变化。请返回字段列表后重新开始，当前输入会保留到你关闭编辑。"), systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(.orange).padding(.bottom, 14)
                    }
                    if session.fields.isEmpty {
                        Text(L10n.text("添加修改项，按顺序编排本次批量操作。"))
                            .foregroundStyle(.secondary).padding(.vertical, 24)
                    } else {
                        HStack {
                            Text(L10n.text("修改项")).frame(maxWidth: .infinity, alignment: .leading)
                            Text(L10n.text("修改")).frame(width: 64)
                            Text(L10n.text("不变")).frame(width: 44)
                            Text(L10n.text("跳过")).frame(width: 44)
                            Color.clear.frame(width: 72, height: 1)
                        }.font(.caption).foregroundStyle(.secondary).padding(.bottom, 8)
                        ForEach(session.fields) { field in
                            operationRow(field)
                            Divider().padding(.vertical, 10)
                        }
                    }
                    if !session.statisticsError.isEmpty {
                        Text(session.statisticsError).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                    }
                    HStack {
                        Button(L10n.text("添加修改项"), systemImage: "plus") { fieldPicker = true }
                            .popover(isPresented: $fieldPicker) { addFields }
                        Spacer()
                        Button(L10n.text("查看修改示例")) { session.loadExamples() }
                            .disabled(!session.isValid || session.examplesBusy)
                    }
                    if session.examplesBusy { ProgressView().controlSize(.small).padding(.top, 12) }
                    if !session.examples.isEmpty {
                        Text(L10n.text("前 3 张的修改示例；尚未修改照片。"))
                            .font(.caption).foregroundStyle(.secondary).padding(.top, 14)
                        ForEach(Array(session.examples.enumerated()), id: \.offset) { _, example in
                            Text(example).font(.caption.monospaced()).textSelection(.enabled).padding(.top, 10)
                        }
                    }
                    if !session.exampleError.isEmpty { Text(session.exampleError).font(.caption).foregroundStyle(.orange) }
                }
                .disabled(session.application.busy || session.application.applied)
                .padding(14)
                if session.application.result != nil {
                    MetadataBatchResultView(application: session.application, readings: session.readings, select: select)
                        .padding(14)
                }
            }
            Divider()
            footer.padding(14)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: session.fields) { session.invalidateExamples(); session.application.resetFeedback(); session.refreshStatistics() }
        .task { session.refreshStatistics() }
        .onChange(of: store.state) { session.application.stateChanged(store.state) }
        .onDisappear { session.invalidateExamples(); session.cancelStatistics(); session.application.cancel() }
        .confirmationDialog(L10n.text("放弃尚未应用的输入？"), isPresented: $discardRequested) {
            Button(L10n.text("放弃输入并关闭"), role: .destructive) { session.discardInput(); close() }
            Button(L10n.text("继续编辑"), role: .cancel) {}
        } message: { Text(L10n.text("照片与已有草稿保持不变。")) }
        .sheet(item: $editingField, onDismiss: { session.editingInput = false }) { field in
            MetadataBatchItemEditor(field: field, session: session, availableTags: availableTags, narrow: narrow) { updated in
                if let index = session.fields.firstIndex(where: { $0.id == updated.id }) { session.fields[index] = updated }
                else { session.fields.append(updated) }
                editingField = nil
            } cancel: { editingField = nil }
        }
        .alert(L10n.text("新建预设"), isPresented: $namingPreset) {
            TextField(L10n.text("预设名称"), text: $presetName)
            Button(L10n.text("取消"), role: .cancel) {}
            Button(L10n.text("保存")) { savePreset() }.disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: { Text(L10n.text("只保存本次动作，不保存照片、选择范围或私人路径。")) }
        .accessibilityIdentifier("metadataBatchForm")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.text("复杂批量规则")).font(.headline)
                Spacer()
                Menu {
                    Button(L10n.text("放弃输入并关闭"), role: .destructive) { discardRequested = true }
                        .disabled(!session.hasInput)
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .disabled(session.application.busy)
                .accessibilityLabel(L10n.text("规则操作"))
                Button(L10n.text("返回字段列表"), systemImage: "chevron.left") { close() }
                    .disabled(session.application.busy)
            }
            Text(L10n.text("固定处理 %1$@ 张照片 · 当前可见 %2$@ 张", session.readings.count, visibleSelection.count))
                .font(.callout).accessibilityIdentifier("metadataBatchScope")
            if visibleSelection.count < session.readings.count && !session.application.applied {
                Button(L10n.text("仅处理当前可见的选择")) { narrow(visibleSelection) }
                    .font(.caption).disabled(visibleSelection.isEmpty || session.application.busy)
            }
            Text(L10n.text("未改动的字段保持原样；应用后仍需保存照片。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if session.application.result == nil && !session.application.notice.isEmpty {
                Text(session.application.notice).font(.caption).textSelection(.enabled)
            }
            if !presetNotice.isEmpty { Text(presetNotice).font(.caption).foregroundStyle(.secondary) }
            HStack {
                if session.application.busy {
                    ProgressView().controlSize(.small)
                    Button(L10n.text("取消本次计算")) { session.application.cancel() }
                } else if session.application.applied {
                    Button(L10n.text("存为预设…")) { namingPreset = true }
                } else {
                    Text(L10n.text("本次操作：%1$@ 项", session.changedFieldCount)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if session.application.applied {
                    Button(L10n.text("完成")) { close() }.buttonStyle(.borderedProminent)
                } else {
                    Button(L10n.text("应用到 %1$@ 张照片", session.readings.count)) { apply() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!session.isValid || session.application.busy || !currentScope || store.saveInProgress)
                        .accessibilityIdentifier("metadataBatchApply")
                }
            }
        }
    }

    private var addFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(L10n.text("搜索名称或标签"), text: $fieldQuery).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(availableTags.filter { tag in
                        fieldQuery.isEmpty || tag.displayName.localizedCaseInsensitiveContains(fieldQuery)
                            || tag.rawValue.localizedCaseInsensitiveContains(fieldQuery)
                    }, id: \.self) { tag in
                        Button {
                            let groups = MetadataBatchValues.groups(tag, readings: session.readings)
                            editingField = MetadataBatchField(tag: tag, value: groups.count == 1 ? groups.first?.value : nil)
                            fieldPicker = false; fieldQuery = ""
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(tag.displayName)
                                Text(tag.rawValue).font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }.padding(14).frame(width: 330, height: 380)
    }

    private func operationRow(_ field: MetadataBatchField) -> some View {
        let result = session.appliedStatistics[field.id] ?? session.statistics[field.id]
        return HStack(spacing: 8) {
            Button { editingField = field } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(field.tag.displayName).font(.system(size: 13, weight: .semibold))
                    Text(field.mode == .set && field.tag.isDate ? L10n.text("设置同一时间") : field.mode.label)
                        .font(.caption).foregroundStyle(.secondary)
                    if field.mode == .copyTo {
                        Text(MetadataTag.allCases.filter { field.destinations.contains($0) }.map(\.displayName).joined(separator: " / "))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
            Text(result.map { "\($0.changed.count)/\(session.readings.count)" } ?? (session.statisticsBusy ? "…" : "—")).frame(width: 64)
            Text(result.map { String($0.unchanged.count) } ?? (session.statisticsBusy ? "…" : "—")).frame(width: 44)
            Text(result.map { String($0.skipped.count) } ?? (session.statisticsBusy ? "…" : "—")).frame(width: 44)
            HStack(spacing: 6) {
                Button { editingField = field } label: { Image(systemName: "pencil") }.help(L10n.text("编辑元数据…"))
                Button { session.duplicate(field.id) } label: { Image(systemName: "doc.on.doc") }
                    .help(L10n.text("复制修改项")).accessibilityLabel(L10n.text("复制修改项"))
                Button { session.remove(field.id) } label: { Image(systemName: "trash") }
                    .help(L10n.text("删除修改项，不清除照片字段"))
            }.buttonStyle(.borderless).frame(width: 72)
        }.font(.caption.monospacedDigit())
        .accessibilityIdentifier("metadataTask." + field.id.uuidString)
        .contextMenu {
            if let index = session.fields.firstIndex(where: { $0.id == field.id }) {
                Button(L10n.text("上移")) { session.move(field.id, by: -1) }.disabled(index == 0)
                Button(L10n.text("下移")) { session.move(field.id, by: 1) }.disabled(index + 1 == session.fields.count)
            }
        }
    }

    private func select(_ ids: Set<ImageData.ID>) { store.send(.selectionChanged(ids), undoable: false) }
    private func narrow(_ ids: Set<ImageData.ID>) {
        guard !ids.isEmpty, !session.application.busy, !session.application.applied else { return }
        session.narrow(to: ids); select(session.photoIDs)
    }
    private func apply() {
        guard let operations = try? session.operations, !operations.isEmpty else { return }
        session.application.apply(readings: session.readings, operations: operations,
            description: L10n.text("批量修改 %1$@ 项", session.changedFieldCount), store: store)
    }
    private func savePreset() {
        do {
            let operations = try session.operations
            let entries = try MetadataPreset.stored(in: presetData)
            let name = MetadataWorkflowCard.uniquePresetName(presetName.trimmingCharacters(in: .whitespacesAndNewlines),
                                                           existing: entries.map(\.name), allowOriginal: true)
            let preset = try MetadataPreset(name: name, operations: operations)
            presetData = try JSONEncoder().encode(entries + [preset])
            presetNotice = L10n.text("预设已保存。")
        } catch {
            presetNotice = OperationFailure.message(L10n.text("预设无法保存，请检查名称和操作。"), error: error)
            OperationFailure.present(presetNotice)
        }
    }
}

struct MetadataInlineFieldEditor: View {
    @Bindable var session: MetadataBatchEditSession
    var close: () -> Void
    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) private var store
    @FocusState private var focused: Bool

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
        .onAppear { focused = true }
        .onChange(of: focused) { if !focused { finish() } }
        .onDisappear { if session.hasInput { finish() } }
        .onExitCommand { session.discardInput(); close() }
    }

    private func finish() {
        Task { @MainActor in
            if await session.finishInline(in: store) { close() }
        }
    }
}

private struct MetadataBatchItemEditor: View {
    @State var field: MetadataBatchField
    let session: MetadataBatchEditSession
    let availableTags: [MetadataTag]
    var narrow: (Set<ImageData.ID>) -> Void
    var commit: (MetadataBatchField) -> Void
    var cancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                MetadataBatchFieldRow(field: $field, readings: session.readings, availableTags: availableTags, narrow: narrow)
                    .padding(20)
            }
            Divider()
            HStack {
                Button(L10n.text("取消")) { cancel() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(L10n.text("完成")) { commit(field) }.keyboardShortcut(.defaultAction)
                    .disabled(field.mode == .keep || (try? field.operations.isEmpty) != false)
            }.padding(16)
        }.frame(width: 560, height: 480)
        .onChange(of: field) { session.editingInput = true }
    }
}

private struct MetadataBatchFieldRow: View {
    @Binding var field: MetadataBatchField
    let readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)]
    let availableTags: [MetadataTag]
    var narrow: (Set<ImageData.ID>) -> Void
    @State private var showsValues = false
    @State private var dateDetails = false

    private var valueGroups: [MetadataValueGroup] { MetadataBatchValues.groups(field.tag, readings: readings) }
    private var currentValue: String {
        let groups = valueGroups
        if groups.count == 1 { return MetadataBatchValues.text(groups.first?.value) }
        return L10n.text("多个值（%1$@/%2$@ 张有值）", readings.count - (groups.first { $0.value == nil }?.photoIDs.count ?? 0), readings.count)
    }
    private var input: Binding<String> {
        Binding(get: { field.input }, set: { field.updateInput($0) })
    }
    private var sourceTags: [MetadataTag] {
        availableTags.filter { MetadataBatchField.canCopy(from: $0, to: field.tag) }
    }
    private var destinationTags: [MetadataTag] {
        availableTags.filter { MetadataBatchField.canCopy(from: field.tag, to: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(field.tag.displayName).font(.system(size: 13, weight: .semibold))
                    Text(field.tag.rawValue).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer(minLength: 8)
                Picker(L10n.text("字段操作"), selection: $field.mode) {
                    ForEach(field.modes, id: \.self) { mode in
                        Text(field.tag.isDate && mode == .set ? L10n.text("设置同一时间") : mode.label).tag(mode)
                    }
                }.labelsHidden().fixedSize().accessibilityIdentifier("batchMode." + field.tag.rawValue)
            }
            Button { showsValues = true } label: {
                HStack(spacing: 5) {
                    Text(L10n.text("当前值：%1$@", currentValue)).lineLimit(2).multilineTextAlignment(.leading)
                    Image(systemName: "chevron.down").font(.caption2)
                }.font(.caption).foregroundStyle(.secondary)
            }.buttonStyle(.plain)
                .popover(isPresented: $showsValues) {
                    MetadataValueDistributionView(tag: field.tag, readings: readings, select: { ids in
                        showsValues = false; narrow(ids)
                    }, use: { value in
                        if let value { field.use(value) }
                        showsValues = false
                    })
                }
            inputControls
            if field.mode != .keep && (try? field.operations.isEmpty) != false {
                Text(L10n.text("输入不完整或格式无效；此字段尚未准备好应用。"))
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .onChange(of: field.mode) { old, mode in
            if [.append, .removeItems].contains(mode) && old != mode { field.input = "" }
            if mode == .copy && !sourceTags.contains(field.source) { field.source = sourceTags.first ?? .captureDate }
        }
    }

    @ViewBuilder private var inputControls: some View {
        if field.mode == .clear {
            Label(L10n.text("清除字段"), systemImage: "eraser").font(.callout).foregroundStyle(.orange)
        } else if field.mode == .offset {
            Picker(L10n.text("偏移方向"), selection: $field.subtract) {
                Text(L10n.text("增加（＋）")).tag(false)
                Text(L10n.text("减少（－）")).tag(true)
            }.pickerStyle(.segmented)
            offsetFields([3, 4, 5])
            DisclosureGroup(L10n.text("年、月、日"), isExpanded: $dateDetails) { offsetFields([0, 1, 2]).padding(.top, 6) }
            Text(L10n.text("保留每张照片原有的亚秒与时区记录；缺失时间跳过。"))
                .font(.caption).foregroundStyle(.secondary)
        } else if field.mode == .copy {
            Picker(L10n.text("来源字段"), selection: $field.source) {
                ForEach(sourceTags, id: \.self) { Text($0.displayName + " · " + $0.rawValue).tag($0) }
            }
            Text(L10n.text("每张照片使用自己的来源值（含待保存修改）；来源缺失时跳过。"))
                .font(.caption).foregroundStyle(.secondary)
        } else if field.mode == .copyTo {
            Text(L10n.text("选择接收字段；每张照片复制自己的当前来源值（含前面操作的结果），来源缺失时跳过。"))
                .font(.caption).foregroundStyle(.secondary)
            ForEach(destinationTags, id: \.self) { target in
                Toggle(target.displayName + " · " + target.rawValue, isOn: Binding(
                    get: { field.destinations.contains(target) },
                    set: { selected in
                        if selected { field.destinations.insert(target) } else { field.destinations.remove(target) }
                    }))
            }
            if destinationTags.isEmpty { Text(L10n.text("没有可接收此类型值的字段。")) .font(.caption).foregroundStyle(.secondary) }
            Text(L10n.text("按照片统计：任一接收字段改变即计为修改；其余照片有跳过项则计为跳过，否则计为不变。"))
                .font(.caption2).foregroundStyle(.secondary)
        } else {
            if field.tag.isDeviceIdentity {
                MetadataDevicePicker(tag: field.tag, make: nil, model: nil, value: input)
            }
            if field.tag == .exifFlash {
                Picker(L10n.text("常用状态"), selection: input) {
                    if !field.tag.flashPresets.contains(where: { String($0.0) == field.input }) {
                        Text(field.input.isEmpty ? L10n.text("自定义") : L10n.text("当前值：%1$@", field.input)).tag(field.input)
                    }
                    ForEach(field.tag.flashPresets, id: \.0) { Text($0.1).tag(String($0.0)) }
                }
            }
            if let choices = field.tag.numericChoices {
                Picker(L10n.text("字段值"), selection: input) {
                    if !choices.contains(where: { String($0.0) == field.input }) {
                        Text(field.input.isEmpty ? L10n.text("未填写") : field.input).tag(field.input)
                    }
                    ForEach(choices, id: \.0) { Text($0.1).tag(String($0.0)) }
                }
            } else {
                HStack {
                    TextField(field.mode == .keep ? L10n.text("输入以修改；留空不清除") : field.tag.inputExample,
                              text: input, axis: .vertical)
                        .lineLimit(field.tag.isList || field.tag.isLongText ? 2...5 : 1...3)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("batchInput." + field.tag.rawValue)
                    if !field.tag.numericUnit.isEmpty { Text(field.tag.numericUnit).font(.caption).foregroundStyle(.secondary) }
                }
            }
            if field.tag.isDate {
                Text("YYYY:MM:DD HH:mm:ss[.subseconds][±HH:mm]").font(.caption2).foregroundStyle(.secondary)
            }
            if field.mode == .sequence {
                TextField(L10n.text("间隔（秒）"), text: $field.interval).textFieldStyle(.roundedBorder)
                Text(L10n.text("按列表顺序逐张设置。例如从 10:00 开始，间隔 5 秒：10:00、10:00:05、10:00:10。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if field.mode == .distribute {
                TextField(L10n.text("结束时间"), text: $field.end).textFieldStyle(.roundedBorder)
                Text(L10n.text("第一张使用开始时间，最后一张使用结束时间，中间照片按列表顺序平均分配。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(field.tag.editorHint).font(.caption2).foregroundStyle(.secondary)
            if let range = field.tag.numericRange {
                let format = FloatingPointFormatStyle<Double>.number.grouping(.never).precision(.fractionLength(0...6))
                Text("\(range.lowerBound.formatted(format))…\(range.upperBound.formatted(format))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let limit = field.tag.maxUTF8Length {
                Text(L10n.text("每项最多 %1$@ 个 UTF-8 字节", limit)).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func offsetFields(_ indices: [Int]) -> some View {
        HStack(spacing: 10) {
            ForEach(indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text(["年", "月", "日", "时", "分", "秒"][index])).font(.caption)
                    TextField("0", text: $field.offsets[index]).textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("batchOffset." + String(index))
                }
            }
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
