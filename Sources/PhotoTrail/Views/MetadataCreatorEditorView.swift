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
    @State private var originalList: [String]?
    @State private var preview: MetadataCreatorEditPlan?
    @State private var error: String?
    @State private var dateOffsets = Array(repeating: "0", count: 6)

    private typealias Mode = MetadataCreatorEditorMode

    private var modes: [Mode] {
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
        VStack(alignment: .leading, spacing: 14) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L10n.text("编辑元数据…")).font(.title2.bold())
                    Text(tag.rawValue).font(.caption).textSelection(.enabled)
                    Text(L10n.text("已选择 %1$@ 张照片", readings.count))
                        .font(.subheadline).foregroundStyle(.secondary)
                    Picker(L10n.text("字段操作"), selection: $mode) {
                        ForEach(modes, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }.pickerStyle(.segmented)
                    if mode != .remove && mode != .offset {
                        if let choices = tag.numericChoices {
                            Picker(L10n.text("合法值"), selection: $authors) {
                                Text("—").tag("")
                                ForEach(choices, id: \.0) { number, label in Text(label).tag(String(number)) }
                            }
                        } else {
                            TextField(tag == .creator ? L10n.text("每行一位作者") : tag.isList ? L10n.text("列表值每行一项；逗号属于内容。") : L10n.text("字段值"), text: $authors, axis: .vertical)
                                .lineLimit(2...5).textFieldStyle(.roundedBorder)
                        }
                        if tag.isDate {
                            DatePicker(L10n.text("Date and Time"), selection: dateBinding, displayedComponents: [.date, .hourAndMinute])
                                .datePickerStyle(.graphical)
                                .environment(\.timeZone, (try? MetadataDate(authors))?.displayTimeZone ?? TimeZone.current)
                            Text("YYYY:MM:DD HH:mm:ss[.subseconds][±HH:mm]").font(.caption)
                        }
                        if let limit = tag.maxUTF8Length { Text(L10n.text("每项最多 %1$@ 个 UTF-8 字节", limit)).font(.caption) }
                        if let range = tag.numericRange { Text("\(tag.numericUnit) · \(range.lowerBound)…\(range.upperBound)").font(.caption) }
                    }
                    if tag.isDate { dateOffsetCard }
                    HStack {
                        Button(L10n.text("复制")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(authors, forType: .string) }
                        Button(L10n.text("粘贴")) { if let text = NSPasteboard.general.string(forType: .string) { authors = text; mode = .set } }
                        Button(L10n.text("恢复原值")) { authors = originalInput; mode = .set }
                        Spacer()
                        Button(L10n.text("清除字段")) { mode = .remove }
                    }
                    if let error {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                    if let preview {
                        let count = preview.items.filter { $0.change != nil }.count
                        Text(L10n.text("预览：%1$@ 张将修改", count))
                            .font(.headline)
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(preview.items, id: \.id) { item in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.imageURL.lastPathComponent).fontWeight(.medium)
                                    Text(item.target.path).font(.caption2).textSelection(.enabled)
                                    Text("\(display(item.originalValue)) → \(display(item))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Divider()
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Button(L10n.text("预览")) { makePreview() }
                Spacer()
                Button(L10n.text("取消")) { dismiss() }
                Button(L10n.text("加入待保存修改")) { applyPreview() }
                    .disabled(preview?.items.contains(where: { $0.change != nil }) != true)
            }
        }
        .padding(24)
        .frame(width: 620, height: tag.isDate ? 640 : 480)
        .onAppear {
            let values = readings.map { reading -> [MetadataTag: MetadataTagValue] in
                var values = reading.snapshot.values
                for (tag, change) in reading.image.creatorDraft?.changes ?? [:] {
                    switch change { case .set(let value): values[tag] = value; case .remove: values[tag] = nil }
                }
                return values
            }
            if case .uniform(let value) = MetadataSelectionValue.summarize(values, tag: tag) {
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

    private var dateOffsetCard: some View {
        GroupBox(L10n.text("时间偏移")) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.text("正数增加，负数减少；分别以每张照片的当前字段值计算。"))
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ForEach(0..<dateOffsets.count, id: \.self) { index in
                        let title = ["年", "月", "日", "时", "分", "秒"][index]
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.text(title)).font(.caption).foregroundStyle(.secondary)
                            TextField(L10n.text(title), text: $dateOffsets[index])
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("metadataDateOffset." + String(index))
                        }
                    }
                }
                Text(L10n.text("按年→月→日→时→分→秒计算；无效日期不会自动改成月末。"))
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding(8)
        }
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
        case .text(let text): text
        case .list(let names): names.joined(separator: ", ")
        }
    }

    private func display(_ item: MetadataCreatorEditPlan.Item) -> String {
        switch item.change {
        case nil: display(item.originalValue)
        case .remove: L10n.text("未填写")
        case .set(.list(let names)): names.joined(separator: ", ")
        case .set(.text(let name)): name
        }
    }
}
