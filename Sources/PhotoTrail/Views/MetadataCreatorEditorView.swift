import AppKit
import Exiftool
import ImageData
import SwiftUI
import UDF

enum MetadataCreatorEditorMode: Hashable, CaseIterable {
    case set, fillMissing, append, removeKeywords, offset, remove

    var label: String {
        switch self {
        case .set: L10n.text("设为")
        case .fillMissing: L10n.text("仅补空值")
        case .append: L10n.text("追加关键词")
        case .removeKeywords: L10n.text("移除指定关键词")
        case .offset: L10n.text("时间偏移")
        case .remove: L10n.text("清除字段")
        }
    }
}


struct MetadataCreatorEditorSelection: Identifiable {
    let id = UUID()
    let readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)]
    let tag: MetadataTag
    var mode: MetadataCreatorEditorMode = .set
    var input: String?
}

struct MetadataBatchEditorSelection: Identifiable {
    let id = UUID()
    let readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)]
    let tags: [MetadataTag]
    let excludedCount: Int
    let mode: String
    let input: String
}

struct MetadataCreatorEditorView: View {
    let readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)]
    let tag: MetadataTag
    var initialMode: MetadataCreatorEditorMode = .set
    var initialInput: String?

    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .set
    @State private var authors = ""
    @State private var originalInput = ""
    @State private var currentSummary = ""
    @State private var originalList: [String]?
    @State private var preview: MetadataCreatorEditPlan?
    @State private var error: String?
    @State private var dateOffsets = Array(repeating: "0", count: 6)

    private typealias Mode = MetadataCreatorEditorMode

    private var modes: [Mode] {
        if tag.isFileTime { return [.set, .offset] }
        if tag.isDate { return [.set, .fillMissing, .offset, .remove] }
        return tag.isList && tag != .creator ? [.set, .append, .removeKeywords, .remove] : [.set, .fillMissing, .remove]
    }

    private var names: [String] {
        if authors.utf8.elementsEqual(originalInput.utf8), let originalList { return originalList }
        return authors.split(separator: "\n").map(String.init)
    }

    private func prepare() throws -> MetadataCreatorEditPlan {
        if tag.isDate, mode == .offset {
            let amounts = try dateOffsets.map { text in
                guard let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    throw MetadataDateError.invalidDate
                }
                return value
            }
            return try MetadataCreatorEditPlan.prepare(readings, tag: tag, action: .offsetDate(
                years: amounts[0], months: amounts[1], days: amounts[2],
                hours: amounts[3], minutes: amounts[4], seconds: amounts[5]))
        }
        if tag == .creator {
            let action: MetadataCreatorEditAction = switch mode {
            case .set: .set(names)
            case .fillMissing: .fillMissing(names)
            default: .remove
            }
            return try MetadataCreatorEditPlan.prepare(readings, action: action)
        }
        let action: MetadataFieldEditAction = switch mode {
        case .set: tag.isList && tag != .creator ? .replaceKeywords(names) : .setText(authors)
        case .fillMissing: .fillMissingText(authors)
        case .append: .appendKeywords(names)
        case .removeKeywords: .removeKeywords(names)
        case .remove: .remove
        case .offset: throw MetadataFieldEditError.invalidAction
        }
        return try MetadataCreatorEditPlan.prepare(readings, tag: tag, action: action)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tag.displayName).font(.system(size: 24, weight: .semibold))
                    Text(tag.rawValue).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(L10n.text("已选择 %1$@ 张照片", readings.count))
                    Text(L10n.text("编辑 → 预览 → 加入待保存"))
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .top, spacing: 18) {
                ScrollView { editorContent.padding(18) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
                previewContent.frame(width: 270)
            }.frame(maxHeight: .infinity)
            if let error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            Divider()
            HStack(spacing: 12) {
                Button(L10n.text("预览")) { makePreview() }.accessibilityIdentifier("metadataPreview")
                Spacer()
                Button(L10n.text("取消")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.text("加入待保存修改")) { applyPreview() }
                    .buttonStyle(.borderedProminent)
                    .disabled(preview?.items.contains(where: { $0.change != nil }) != true)
                    .accessibilityIdentifier("metadataApplyDraft")
            }.controlSize(.large)
        }
        .font(.system(size: 15))
        .padding(24).frame(width: 880, height: 660)
        .onAppear {
            let values = readings.map { reading -> [MetadataTag: MetadataTagValue] in
                var values = reading.snapshot.values
                for (tag, change) in reading.image.creatorDraft?.changes ?? [:] {
                    switch change { case .set(let value): values[tag] = value; case .remove: values[tag] = nil }
                }
                return values
            }
            let summary = MetadataSelectionValue.summarize(values, tag: tag)
            switch summary {
            case .uniform(let value): currentSummary = display(value)
            case .mixed(let present, let total): currentSummary = L10n.text("多个值（%1$@/%2$@ 张有值）", present, total)
            default: currentSummary = L10n.text("未填写")
            }
            if case .uniform(let value) = summary {
                switch value { case .text(let text): authors = text; case .list(let names): originalList = names; authors = names.joined(separator: "\n") }
            }
            originalInput = authors
            if let initialInput { authors = initialInput }
            mode = modes.contains(initialMode) ? initialMode : .set
        }
        .onChange(of: mode) { preview = nil; error = nil }
        .onChange(of: authors) { preview = nil; error = nil }
        .onChange(of: dateOffsets) { mode = .offset; preview = nil; error = nil }
    }

    private var deviceIdentity: (make: String?, model: String?) {
        let isEXIF = [.exifMake, .exifModel].contains(tag)
        return (uniformText(for: isEXIF ? .exifMake : .make), uniformText(for: isEXIF ? .exifModel : .model))
    }

    private func uniformText(for tag: MetadataTag) -> String? {
        let values = readings.map { reading -> String? in
            if let change = reading.image.creatorDraft?.changes[tag] {
                if case .set(.text(let value)) = change { return value }
                return nil
            }
            if case .text(let value) = reading.snapshot.values[tag] { return value }
            return nil
        }
        return Set(values).count == 1 ? values.first ?? nil : nil
    }

    private var dateBinding: Binding<Date> {
        Binding(get: { (try? MetadataDate(authors))?.date ?? Date() }, set: { date in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            if let original = try? MetadataDate(authors),
               let changed = try? original.shifting(seconds: Int(date.timeIntervalSince(original.date).rounded())) {
                authors = changed.text
            } else { authors = formatter.string(from: date) }
        })
    }

    private func makePreview() {
        do {
            preview = try prepare()
            error = nil
        } catch {
            preview = nil
            if case Exiftool.ExiftoolError.unsupportedIPTCEncoding = error {
                self.error = L10n.text("现有 IPTC 未明确声明 UTF-8，已阻止写入以保留原编码。")
            } else { self.error = L10n.text("无法预览字段修改；请检查输入并重新读取元数据。") }
        }
    }

    private func applyPreview() {
        guard let preview else { return }
        do {
            let current = try prepare()
            guard current.items == preview.items, !store.saveInProgress,
                  readings.allSatisfy({ store[$0.image.id].creatorDraft == $0.image.creatorDraft
                      && store[$0.image.id].metadata == $0.image.metadata
                      && store.creatorSaveResults[$0.image.id] != .resultUnknown }) else {
                self.preview = nil
                error = L10n.text("来源文件已变化；请重新读取元数据。")
                return
            }
            store.send(.creatorDraftApplied(current.items), description: L10n.text("编辑元数据…"))
            dismiss()
        } catch {
            self.preview = nil
            self.error = L10n.text("来源文件已变化；请重新读取元数据。")
        }
    }

    private func display(_ value: MetadataTagValue?) -> String {
        switch value {
        case nil: L10n.text("未填写")
        case .text(let text):
            (tag.numericChoices ?? (tag == .exifFlash ? tag.flashPresets : [])).first { String($0.0) == text }?.1 ?? text
        case .list(let names): names.joined(separator: "\n")
        }
    }

    private func display(_ item: MetadataCreatorEditPlan.Item) -> String {
        switch item.change {
        case nil: display(item.originalValue)
        case .remove: L10n.text("未填写")
        case .set(let value): display(value)
        }
    }
}

private extension MetadataCreatorEditorView {
    private func operationLabel(_ mode: Mode) -> String {
        if ![MetadataTag.subject, .iptcKeywords].contains(tag) {
            if mode == .append { return L10n.text("追加项目") }
            if mode == .removeKeywords { return L10n.text("移除指定项目") }
        }
        return mode.label
    }

    var editorContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.text("编辑内容")).font(.headline)
            Picker(L10n.text("字段操作"), selection: $mode) {
                ForEach(modes, id: \.self) { Text(operationLabel($0)).tag($0) }
            }.pickerStyle(.segmented).controlSize(.large)
            if mode == .remove {
                Label(L10n.text("预览清除结果，再加入待保存修改。"), systemImage: "eraser")
                    .foregroundStyle(.secondary).padding(.vertical, 16)
            } else if mode == .offset {
                dateOffsetContent
            } else {
                fieldInput
            }
            Divider()
            HStack(spacing: 14) {
                Button(L10n.text("复制")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(authors, forType: .string)
                }
                Button(L10n.text("粘贴")) {
                    if let text = NSPasteboard.general.string(forType: .string) { authors = text; mode = .set }
                }
                Spacer()
                Button(L10n.text("恢复原值")) { authors = originalInput; mode = .set }
            }.buttonStyle(.link).font(.callout)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    var fieldInput: some View {
        if tag.isDeviceIdentity {
            MetadataDevicePicker(tag: tag, make: deviceIdentity.make, model: deviceIdentity.model, value: $authors)
        }
        if tag == .exifFlash {
            Picker(L10n.text("常用状态"), selection: $authors) {
                if !tag.flashPresets.contains(where: { String($0.0) == authors }) {
                    Text(authors.isEmpty ? L10n.text("自定义") : L10n.text("当前值：%1$@", authors)).tag(authors)
                }
                ForEach(tag.flashPresets, id: \.0) { number, label in Text(label).tag(String(number)) }
            }.controlSize(.large)
        }
        if let choices = tag.numericChoices {
            Picker(L10n.text("合法值"), selection: $authors) {
                Text(L10n.text("未填写")).tag("")
                // Unknown existing codes stay visible until the user explicitly chooses a replacement.
                if !authors.isEmpty && !choices.contains(where: { String($0.0) == authors }) {
                    Text(authors).tag(authors)
                }
                ForEach(choices, id: \.0) { number, label in
                    Text(label.components(separatedBy: " · ").last ?? label).tag(String(number))
                }
            }.pickerStyle(.radioGroup).controlSize(.large)
                .accessibilityIdentifier("metadataEnumValue")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text(tag.isDeviceIdentity ? "最终写入内容" : "字段值")).font(.subheadline.weight(.medium))
                if tag.isList || tag.isLongText {
                    TextField(tag == .creator ? L10n.text("每行一位作者") : tag.isList ? L10n.text("列表值每行一项；逗号属于内容。") : tag.displayName,
                              text: $authors, axis: .vertical)
                        .lineLimit(5...9).textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("metadataInput")
                } else {
                    HStack {
                        TextField(tag.inputExample, text: $authors).textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("metadataInput")
                        if !tag.numericUnit.isEmpty { Text(tag.numericUnit).foregroundStyle(.secondary) }
                    }
                }
            }.controlSize(.large)
            if tag.isDate {
                DatePicker(L10n.text("Date and Time"), selection: dateBinding, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.field).controlSize(.large)
                    .environment(\.timeZone, (try? MetadataDate(authors))?.displayTimeZone ?? TimeZone.current)
                Text("YYYY:MM:DD HH:mm:ss[.subseconds][±HH:mm]").font(.caption).foregroundStyle(.secondary)
            }
            Text(tag.editorHint).font(.callout).foregroundStyle(.secondary)
            if let limit = tag.maxUTF8Length {
                Text(L10n.text("每项最多 %1$@ 个 UTF-8 字节", limit)).font(.caption).foregroundStyle(.secondary)
            }
            if let range = tag.numericRange {
                let format = FloatingPointFormatStyle<Double>.number.grouping(.never).precision(.fractionLength(0...6))
                Text("\(range.lowerBound.formatted(format))…\(range.upperBound.formatted(format))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    var dateOffsetContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.text("正数增加，负数减少；分别以每张照片的当前字段值计算。"))
                .font(.callout).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
                ForEach(0..<dateOffsets.count, id: \.self) { index in
                    let title = ["年", "月", "日", "时", "分", "秒"][index]
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text(title)).font(.subheadline.weight(.medium))
                        TextField(L10n.text(title), text: $dateOffsets[index]).textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("metadataDateOffset." + String(index))
                    }
                }
            }.controlSize(.large)
            Text(L10n.text("按年→月→日→时→分→秒计算；无效日期不会自动改成月末。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    var previewContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("当前内容 / 修改预览")).font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L10n.text("当前内容")).font(.callout).foregroundStyle(.secondary)
                    Text(currentSummary).frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                    if let preview {
                        Text(L10n.text("预览：%1$@ 张将修改", preview.items.filter { $0.change != nil }.count))
                            .font(.callout.weight(.semibold)).foregroundStyle(Color.accentColor)
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(preview.items, id: \.id) { item in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.imageURL.lastPathComponent).font(.caption.weight(.medium)).lineLimit(2)
                                    Text(display(item.originalValue)).foregroundStyle(.secondary)
                                    Image(systemName: "arrow.down").font(.caption).foregroundStyle(.secondary)
                                    Text(display(item)).foregroundStyle(item.change == nil ? Color.secondary : Color.accentColor)
                                    Text(item.target.path).font(.caption2).foregroundStyle(.tertiary)
                                }
                                Divider()
                            }
                        }
                    } else {
                        Label(L10n.text("点击“预览”检查每张照片的修改结果。"), systemImage: "eye")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
            Text(L10n.text("加入待保存后，回到列表保存照片。"))
                .font(.caption).foregroundStyle(.secondary)
        }.padding(18).frame(maxHeight: .infinity, alignment: .top)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
    }
}
