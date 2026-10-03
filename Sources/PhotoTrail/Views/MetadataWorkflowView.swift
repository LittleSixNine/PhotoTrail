import AppKit
import Exiftool
import ImageData
import SwiftUI
import UDF
import UniformTypeIdentifiers

struct MetadataWorkflowView: View {
    let readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)]
    var initialTargets: [MetadataTag] = []
    var excludedFieldCount = 0
    var initialBatchMode = "copy"
    var initialBatchInput = ""
    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("PhotoTrail.MetadataPresets") private var presetData = Data()
    @State private var tag = MetadataTag.captureDate
    @State private var mode = "shift"
    @State private var input = ""
    @State private var end = ""
    @State private var amount = 0
    @State private var zone = ""
    @State private var component = "year"
    @State private var copySource = MetadataTag.dateOriginal
    @State private var operations: [MetadataOperation] = []
    @State private var preview: MetadataWorkflowPreview?
    @State private var presetName = ""
    @State private var selectedPreset = ""
    @State private var notice = ""
    @State private var busy = false

    private let actionLabels = ["set": "设为", "fill": "仅补空值", "clear": "清除字段", "append": "追加文字",
                                "keywords": "追加关键词", "removeKeywords": "移除指定关键词", "shift": "整体偏移（秒）",
                                "days": "日历增加天数", "component": "修改日期组件", "sequence": "起点＋步长",
                                "filename": "从文件名解析日期", "distribute": "区间均分", "copy": "从字段复制"]
    private var modes: [String] {
        if tag.isDate { return ["set", "clear", "shift", "days", "component", "sequence", "distribute", "filename", "copy"] }
        if tag.isList && tag != .creator { return ["set", "clear", "keywords", "removeKeywords", "copy"] }
        if tag == .creator { return ["set", "fill", "clear", "copy"] }
        if tag.numericRange != nil { return ["set", "fill", "clear", "copy"] }
        return ["set", "fill", "clear", "append", "copy"]
    }
    private var availableTags: [MetadataTag] {
        MetadataTag.allCases.filter { tag in
            tag.supportsSidecar || readings.allSatisfy { if case .image = $0.image.metadata.source { true } else { false } }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isBatch ? L10n.text("批量编辑字段") : L10n.text("日期、预设与交换…")).font(.title2.bold())
            Text(L10n.text("已选择 %1$@ 张照片", readings.count))
            if !isBatch {
                Text(L10n.text("按列表排序冻结顺序；只写所选规范标签。EXIF 拍摄时间含亚秒与时区；其他字段不同步同义标签或配对文件。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if isBatch { batchForm } else { TabView {
                actionForm.tabItem { Text(L10n.text("编辑元数据…")) }
                presetForm.tabItem { Text(L10n.text("预设")) }
                exchangeForm.tabItem { Text(L10n.text("比较与交换")) }
            }.frame(minHeight: 320) }
            if !notice.isEmpty { Text(notice).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            if let preview {
                Text(L10n.text("预览：%1$@ 张将修改", preview.items.filter { !$0.changes.isEmpty }.count))
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(preview.steps.enumerated()), id: \.offset) { _, item in
                            Text("\(item.imageURL.lastPathComponent) · \(item.tag.rawValue)").font(.caption.bold())
                            Text("\(display(item.originalValue)) → \(display(item.changeValue))").font(.caption)
                            Text(item.target.path).font(.caption2).foregroundStyle(.secondary)
                        }
                        ForEach(Array(Set(preview.skipped)).sorted(), id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                    }.textSelection(.enabled)
                }.frame(maxHeight: 200)
            }
            HStack {
                Button(L10n.text("预览")) { makePreview() }.disabled(activeOperations.isEmpty || busy)
                Spacer()
                Button(L10n.text("取消")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.text("加入待保存修改")) { apply() }
                    .disabled(preview?.items.isEmpty != false || busy || store.saveInProgress)
            }
        }.padding(20).frame(minWidth: 560, idealWidth: 680, maxWidth: 850)
            .onAppear {
                if isBatch {
                    mode = initialBatchMode; input = initialBatchInput
                    copySource = copySources.contains(.exifCreateDate) ? .exifCreateDate : copySources.first ?? .sidecarDate
                } else if readings.allSatisfy({ if case .xmp = $0.image.metadata.source { true } else { false } }) {
                    tag = .sidecarDate
                }
            }
            .onChange(of: mode) { if isBatch { preview = nil } }
            .onChange(of: input) { if isBatch { preview = nil } }
            .onChange(of: copySource) { if isBatch { preview = nil } }
            .onChange(of: tag) { mode = tag.isDate ? "shift" : "set"; input = ""; preview = nil }
    }

    private var actionForm: some View {
        Form {
            Picker(L10n.text("字段"), selection: $tag) {
                ForEach(availableTags, id: \.self) { Text("\($0.displayName) · \($0.rawValue)").tag($0) }
            }
            Text(L10n.text("当前值：%1$@", display(value(readings[0], tag: tag)))).font(.caption).textSelection(.enabled)
            Picker(L10n.text("字段操作"), selection: $mode) {
                ForEach(modes, id: \.self) { Text(L10n.text(actionLabels[$0]!)).tag($0) }
            }
            if mode == "filename" {
                TextField(L10n.text("文件名正则表达式"), text: $input)
                TextField(L10n.text("日期模板（如 $1:$2:$3 12:00:00）"), text: $end)
            } else if mode == "copy" {
                Picker(L10n.text("来源字段"), selection: $copySource) {
                    ForEach(availableTags, id: \.self) { Text("\($0.displayName) · \($0.rawValue)").tag($0) }
                }
            } else if ["shift", "days", "component"].contains(mode) {
                Stepper(L10n.text("数值：%1$@", amount), value: $amount, in: -1_000_000...1_000_000)
                TextField(L10n.text("整数数值"), value: $amount, format: .number)
                if mode == "days" { TextField(L10n.text("时区标识（可选，如 America/New_York）"), text: $zone) }
                if mode == "component" {
                    Picker(L10n.text("日期组件"), selection: $component) {
                        ForEach(["year", "month", "day", "hour", "minute", "second"], id: \.self) { component in
                            let label = ["year": "年", "month": "月", "day": "日", "hour": "时", "minute": "分", "second": "秒"][component]!
                            Text(L10n.text(label)).tag(component)
                        }
                    }
                }
            } else if mode != "clear" {
                if let choices = tag.numericChoices {
                    Picker(L10n.text("合法值"), selection: $input) {
                        Text("—").tag("")
                        ForEach(choices, id: \.0) { number, label in Text(label).tag(String(number)) }
                    }
                } else {
                    TextField(L10n.text("字段值"), text: $input, axis: .vertical).lineLimit(2...4)
                }
                if tag.isDate { Text("YYYY:MM:DD HH:mm:ss[.subseconds][±HH:mm]").font(.caption) }
                if tag.isList { Text(L10n.text("列表值每行一项；逗号属于内容。")) }
                if let limit = tag.maxUTF8Length { Text(L10n.text("每项最多 %1$@ 个 UTF-8 字节", limit)).font(.caption) }
                if let range = tag.numericRange { Text("\(unit) · \(range.lowerBound)…\(range.upperBound)").font(.caption) }
                if mode == "sequence" {
                    TextField(L10n.text("步长（秒）"), value: $amount, format: .number)
                }
                if mode == "distribute" { TextField(L10n.text("结束时间"), text: $end) }
            }
            Button(L10n.text("添加动作")) { addOperation() }
            Text(L10n.text("动作数量：%1$@", operations.count))
            ScrollView {
                ForEach(Array(operations.enumerated()), id: \.offset) { index, operation in
                    Text("\(index + 1). \(operation.tag.rawValue) · \(operationLabel(operation.action))").font(.caption)
                }
            }.frame(maxHeight: 90)
            Button(L10n.text("清空动作")) { operations = []; preview = nil }
        }.padding(.vertical, 8)
    }

    private var unit: String { tag.numericUnit }

    private func addOperation() {
        let words = input.split(separator: "\n").map(String.init)
        let action: MetadataFieldEditAction
        switch mode {
        case "clear": action = .remove
        case "fill": action = tag == .creator ? .fillMissingAuthors(words) : .fillMissingText(input)
        case "append": action = .appendText(input)
        case "keywords": action = .appendKeywords(words)
        case "removeKeywords": action = .removeKeywords(words)
        case "shift": action = .shiftDate(seconds: amount)
        case "days": action = .calendarDays(amount, timeZoneID: zone.isEmpty ? nil : zone)
        case "component": action = .dateComponent(component, amount)
        case "sequence": action = .sequence(start: input, stepSeconds: amount)
        case "distribute": action = .distribute(start: input, end: end)
        case "filename": action = .filenameDate(pattern: input, template: end)
        case "copy": action = .copy(copySource)
        default: action = tag == .creator ? .replaceAuthors(words) : tag.isList && tag != .creator ? .replaceKeywords(words) : .setText(input)
        }
        preview = nil
        operations.append(MetadataOperation(tag: tag, action: action))
    }

    private func operationLabel(_ action: MetadataFieldEditAction) -> String {
        switch action {
        case .setText(let text): "\(L10n.text("设为")) · \(text)"
        case .fillMissingText(let text): "\(L10n.text("仅补空值")) · \(text)"
        case .replaceAuthors(let words), .replaceKeywords(let words): "\(L10n.text("设为")) · \(words.joined(separator: " / "))"
        case .fillMissingAuthors(let words): "\(L10n.text("仅补空值")) · \(words.joined(separator: " / "))"
        case .appendText(let text): "\(L10n.text("追加文字")) · \(text)"
        case .appendKeywords(let words): "\(L10n.text("追加关键词")) · \(words.joined(separator: " / "))"
        case .removeKeywords(let words): "\(L10n.text("移除指定关键词")) · \(words.joined(separator: " / "))"
        case .remove: L10n.text("清除字段")
        case .offsetDate(let years, let months, let days, let hours, let minutes, let seconds):
            "\(L10n.text("时间偏移")) · \(years) / \(months) / \(days) / \(hours) / \(minutes) / \(seconds)"
        case .shiftDate(let seconds): "\(L10n.text("整体偏移（秒）")) · \(seconds)"
        case .calendarDays(let days, let zone): "\(L10n.text("日历增加天数")) · \(days) · \(zone ?? "")"
        case .dateComponent(let component, let value): "\(L10n.text("修改日期组件")) · \(component) · \(value)"
        case .sequence(let start, let step): "\(L10n.text("起点＋步长")) · \(start) · \(step) s"
        case .distribute(let start, let end): "\(L10n.text("区间均分")) · \(start) → \(end)"
        case .filenameDate(let pattern, let template): "\(L10n.text("从文件名解析日期")) · \(pattern) → \(template)"
        case .copy(let source): "\(L10n.text("从字段复制")) · \(source.rawValue)"
        }
    }

    private var presetForm: some View {
        Form {
            TextField(L10n.text("预设名称"), text: $presetName)
            Button(L10n.text("保存命名预设")) {
                perform {
                    let preset = try MetadataPreset(name: presetName, operations: operations)
                    var entries = presets.filter { $0.name != preset.name }; entries.append(preset)
                    presetData = try JSONEncoder().encode(entries)
                }
            }.disabled(operations.isEmpty)
            Picker(L10n.text("预设"), selection: $selectedPreset) {
                Text("—").tag("")
                ForEach(presets, id: \.name) { Text($0.name).tag($0.name) }
            }
            Button(L10n.text("载入预设动作")) {
                if let preset = presets.first(where: { $0.name == selectedPreset }) { preview = nil; operations = preset.operations; presetName = preset.name }
            }
            HStack {
                Button(L10n.text("导出预设 JSON")) {
                    perform { try saveFile(try MetadataPreset(name: presetName, operations: operations).encode(), name: "preset.json", type: .json) }
                }.disabled(operations.isEmpty)
                Button(L10n.text("导入预设 JSON")) {
                    perform {
                        guard let url = openFile(type: .json) else { return }
                        let preset = try MetadataPreset.decode(Data(contentsOf: url))
                        preview = nil; operations = preset.operations; presetName = preset.name
                    }
                }
            }
        }.padding(.vertical, 8)
    }

    private var exchangeForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(L10n.text("导出可回写 CSV")) { exportCSV(displayOnly: false) }
                Button(L10n.text("导出安全显示 CSV")) { exportCSV(displayOnly: true) }
                Button(L10n.text("导入 CSV 并预览")) { importCSV() }
            }
            Text(L10n.text("可回写 CSV：空单元格保持，@clear 清除；文字与列表使用 JSON 值。显示版不可导回。"))
                .font(.caption)
            HStack {
                Button(L10n.text("导出磁盘 XMP")) { exportXMP() }.disabled(readings.count != 1 || busy)
                Button(L10n.text("导入 XMP 并预览")) { importXMP() }
            }
            Text(L10n.text("XMP 导入只合并已开放字段；缺失值保持，先预览冲突，不替换整个文件。"))
                .font(.caption)
            ScrollView([.horizontal, .vertical]) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow { Text(L10n.text("字段")); ForEach(readings.prefix(20), id: \.image.id) { Text($0.image.name) } }
                    ForEach(availableTags, id: \.self) { tag in
                        GridRow { Text(tag.rawValue); ForEach(readings.prefix(20), id: \.image.id) { Text(display(value($0, tag: tag))) } }
                    }
                }.font(.caption).textSelection(.enabled)
            }
            if readings.count > 20 { Text(L10n.text("比较仅显示前 20 张；导出与编辑作用于全部选择。")) }
        }.padding(.vertical, 8)
    }

    private func makePreview() {
        perform { preview = try MetadataWorkflowPreview.prepare(readings, operations: activeOperations) }
    }
    private func apply() {
        guard let preview, !store.saveInProgress else { return }
        perform {
            guard readings.allSatisfy({ store[$0.image.id].creatorDraft == $0.image.creatorDraft
                && store.creatorSaveResults[$0.image.id] != .resultUnknown
                && store[$0.image.id].metadata == $0.image.metadata }),
                  preview.items.allSatisfy({ MetadataInspectionFileVersion.read($0.target) == $0.version }) else {
                throw MetadataCreatorPlanError.sourceChanged
            }
            store.send(.creatorDraftApplied(preview.items), description: L10n.text("编辑元数据…"))
            dismiss()
        }
    }
    private func records() throws -> [MetadataCSVRecord] {
        var common = readings[0].snapshot.url.deletingLastPathComponent()
        while !readings.allSatisfy({ $0.snapshot.url.path.hasPrefix(common.path + "/") }) && common.path != "/" {
            common.deleteLastPathComponent()
        }
        let prefix = common.path == "/" ? "/" : common.path + "/"
        return try readings.map { reading in
            var values = reading.snapshot.values
            for (tag, change) in reading.image.creatorDraft?.changes ?? [:] {
                switch change { case .set(let value): values[tag] = value; case .remove: values[tag] = nil }
            }
            return try MetadataCSVRecord(url: reading.snapshot.url,
                                         relativePath: String(reading.snapshot.url.path.dropFirst(prefix.count)), values: values)
        }
    }
    private func exportCSV(displayOnly: Bool) {
        perform { try saveFile(Data(MetadataCSV.export(records(), tags: MetadataTag.allCases, displayOnly: displayOnly).utf8),
                               name: displayOnly ? "metadata-display.csv" : "metadata.csv", type: .commaSeparatedText) }
    }
    private func importCSV() {
        perform {
            guard let url = openFile(type: .commaSeparatedText) else { return }
            let records = try records()
            let imported = try MetadataCSV.load(String(contentsOf: url, encoding: .utf8), authorized: records)
            var items: [MetadataCreatorEditPlan.Item] = [], steps: [MetadataCreatorEditPlan.Item] = []
            for (record, reading) in zip(records, readings) {
                guard let actions = imported.operations[record.id], !actions.isEmpty else { continue }
                let plan = try MetadataWorkflowPreview.prepare([reading], operations: actions)
                items += plan.items; steps += plan.steps
            }
            // The original selection is also validated as a whole to reject shared physical targets.
            _ = try MetadataCreatorEditPlan.prepare(readings, action: .fillMissing(["validation"]))
            preview = MetadataWorkflowPreview(items: items, steps: steps, skipped: imported.warnings)
            notice = imported.warnings.joined(separator: "\n")
        }
    }
    private func exportXMP() {
        busy = true
        let url = readings[0].snapshot.url
        Task {
            do {
                let data = try await Task.detached { try Exiftool.helper.xmpData(from: url) }.value
                try saveFile(data, name: url.deletingPathExtension().lastPathComponent + "-export.xmp", type: UTType(filenameExtension: "xmp") ?? .data)
            } catch { notice = L10n.text("操作失败：%1$@", String(describing: error)) }
            busy = false
        }
    }
    private func importXMP() {
        perform {
            guard let url = openFile(type: UTType(filenameExtension: "xmp") ?? .data) else { return }
            let values = try Exiftool.helper.metadataTags(Set(MetadataTag.allCases), from: url)
            operations = MetadataTag.allCases.compactMap { tag in
                guard let value = values[tag] else { return nil }
                let action: MetadataFieldEditAction = switch value {
                case .text(let text): .setText(text)
                case .list(let words): tag == .creator ? .replaceAuthors(words) : .replaceKeywords(words)
                }
                return MetadataOperation(tag: tag, action: action)
            }
            makePreview()
        }
    }
    private func perform(_ operation: () throws -> Void) {
        do { notice = ""; try operation() }
        catch {
            preview = nil
            if case Exiftool.ExiftoolError.unsupportedIPTCEncoding = error {
                notice = L10n.text("现有 IPTC 未明确声明 UTF-8，已阻止写入以保留原编码。")
            } else { notice = L10n.text("操作失败：%1$@", String(describing: error)) }
        }
    }
    private func openFile(type: UTType) -> URL? {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [type]; panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }
    private func saveFile(_ data: Data, name: String, type: UTType) throws {
        let panel = NSSavePanel(); panel.allowedContentTypes = [type]; panel.nameFieldStringValue = name
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let destination = url.resolvingSymlinksInPath().standardizedFileURL
        let version = MetadataInspectionFileVersion.read(url)
        for reading in readings {
            for source in [reading.snapshot.url, reading.image.metadataCreatorImageURL].compactMap({ $0 }) {
                if source.resolvingSymlinksInPath().standardizedFileURL == destination {
                    throw MetadataCreatorPlanError.duplicateTarget
                }
                if case .file = version, version == MetadataInspectionFileVersion.read(source) {
                    throw MetadataCreatorPlanError.duplicateTarget
                }
            }
        }
        try data.write(to: url, options: .atomic)
    }
}

private extension MetadataCreatorEditPlan.Item {
    var changeValue: MetadataTagValue? {
        switch change { case nil: originalValue; case .set(let value): value; case .remove: nil }
    }
}


extension MetadataTag {
    var displayName: String {
        let key: String = switch self {
        case .titleDefault: "标题"
        case .descriptionDefault: "说明"
        case .rightsDefault: "版权"
        case .creator: "作者"
        case .subject: "关键词"
        case .captureDate: "拍摄时间（EXIF，含亚秒与时区）"
        case .sidecarDate: "列表时间（XMP CreateDate）"
        case .dateOriginal: "拍摄日期（XMP）"
        case .dateDigitized: "数字化日期（XMP）"
        case .dateModified: "修改日期（XMP）"
        case .make: "相机厂商"
        case .model: "相机型号"
        case .lens: "镜头型号"
        case .exposureTime: "曝光时间"
        case .fNumber: "光圈值"
        case .iso: "ISO"
        case .focalLength: "焦距"
        case .exposureBias: "曝光补偿"
        case .exposureProgram: "曝光程序"
        case .whiteBalance: "白平衡"
        case .exifMake: "Metadata field: Make"
        case .exifModel: "Metadata field: Model"
        case .exifSerial: "Metadata field: SerialNumber"
        case .exifLensMake: "Metadata field: LensMake"
        case .exifLensModel: "Metadata field: LensModel"
        case .exifLensSerial: "Metadata field: LensSerialNumber"
        case .exifExposureTime: "Metadata field: ExposureTime"
        case .exifFNumber: "Metadata field: FNumber"
        case .exifISO: "Metadata field: ISO"
        case .exifAperture: "Metadata field: ApertureValue"
        case .exifShutter: "Metadata field: ShutterSpeedValue"
        case .exifFocalLength: "Metadata field: FocalLength"
        case .exifFocal35: "Metadata field: FocalLengthIn35mmFormat"
        case .exifExposureBias: "Metadata field: ExposureCompensation"
        case .exifFlash: "Metadata field: Flash"
        case .exifColorSpace: "Metadata field: ColorSpace"
        case .exifMaxAperture: "Metadata field: MaxApertureValue"
        case .exifExposureMode: "Metadata field: ExposureMode"
        case .exifExposureProgram: "Metadata field: ExposureProgram"
        case .exifMeteringMode: "Metadata field: MeteringMode"
        case .exifWhiteBalance: "Metadata field: WhiteBalance"
        case .exifSaturation: "Metadata field: Saturation"
        case .exifSharpness: "Metadata field: Sharpness"
        case .exifCreateDate: "Metadata field: CreateDate"
        case .exifModifyDate: "Metadata field: ModifyDate"
        case .exifArtist: "Metadata field: Artist"
        case .exifDescription: "Metadata field: ImageDescription"
        case .exifCopyright: "Metadata field: Copyright"
        case .exifSoftware: "Metadata field: Software"
        case .exifComment: "Metadata field: UserComment"
        case .iptcByline: "Metadata field: By-line"
        case .iptcBylineTitle: "Metadata field: By-lineTitle"
        case .iptcContact: "Metadata field: Contact"
        case .iptcHeadline: "Metadata field: Headline"
        case .iptcCaption: "Metadata field: Caption-Abstract"
        case .iptcObjectName: "Metadata field: ObjectName"
        case .iptcKeywords: "Metadata field: Keywords"
        case .iptcCity: "Metadata field: City"
        case .iptcProvince: "Metadata field: Province-State"
        case .iptcLocation: "Metadata field: Sub-location"
        case .iptcCountry: "Metadata field: Country-PrimaryLocationName"
        case .iptcCountryCode: "Metadata field: Country-PrimaryLocationCode"
        }
        return key == "ISO" ? key : L10n.text(key)
    }
}

extension MetadataTag {
    var numericChoices: [(Int, String)]? {
        let keys: [String]
        switch self {
        case .whiteBalance, .exifWhiteBalance: keys = ["自动", "手动"]
        case .exposureProgram, .exifExposureProgram: keys = ["未定义", "手动", "程序自动", "光圈优先", "快门优先", "创意程序", "运动程序", "人像模式", "风景模式"]
        case .exifExposureMode: keys = ["自动", "手动", "包围曝光"]
        case .exifSaturation: keys = ["正常", "低", "高"]
        case .exifSharpness: keys = ["正常", "柔和", "锐利"]
        case .exifColorSpace: return [(1, "sRGB"), (65535, L10n.text("未校准"))]
        case .exifMeteringMode:
            return zip([0, 1, 2, 3, 4, 5, 6, 255], ["未知", "平均", "中央重点", "点测光", "多点测光", "评价测光", "局部测光", "其他"]).map { ($0.0, "\($0.0) · \(L10n.text($0.1))") }
        default: return nil
        }
        return keys.enumerated().map { ($0.offset, "\($0.offset) · \(L10n.text($0.element))") }
    }
}

extension MetadataTag {
    var numericUnit: String {
        switch self {
        case .exposureTime, .exifExposureTime, .exifShutter: "s"
        case .fNumber, .exifFNumber, .exifAperture, .exifMaxAperture: "f/"
        case .iso, .exifISO: "ISO"
        case .focalLength, .exifFocalLength, .exifFocal35: "mm"
        case .exposureBias, .exifExposureBias: "EV"
        default: ""
        }
    }
}

private extension MetadataWorkflowView {
    var presets: [MetadataPreset] {
        guard let entries = try? JSONDecoder().decode([MetadataPreset].self, from: presetData) else { return [] }
        return entries.filter { $0.version == 1 }
    }

    func value(_ reading: (image: ImageData, snapshot: MetadataInspectionSnapshot), tag: MetadataTag) -> MetadataTagValue? {
        if let pending = reading.image.creatorDraft?.changes[tag] {
            switch pending { case .set(let value): return value; case .remove: return nil }
        }
        return reading.snapshot.values[tag]
    }
    func display(_ value: MetadataTagValue?) -> String {
        switch value { case nil: L10n.text("未填写"); case .text(let text): text; case .list(let values): values.joined(separator: " / ") }
    }


    var isBatch: Bool { !initialTargets.isEmpty }
    var copySources: [MetadataTag] {
        availableTags.filter { source in
            !initialTargets.allSatisfy(\.isDate) || source.isDate
        }
    }
    var activeOperations: [MetadataOperation] {
        guard isBatch else { return operations }
        return initialTargets.map { target in
            let action: MetadataFieldEditAction
            switch mode {
            case "copy": action = .copy(copySource)
            case "clear": action = .remove
            default:
                let words = input.split(separator: "\n").map(String.init)
                action = target == .creator ? .replaceAuthors(words)
                    : target.isList ? .replaceKeywords(words) : .setText(input)
            }
            return MetadataOperation(tag: target, action: action)
        }
    }
    var batchForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("目标字段：%1$@", initialTargets.count)).font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(initialTargets, id: \.self) { target in
                        Text("\(target.displayName) · \(target.rawValue)").font(.caption)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: min(CGFloat(initialTargets.count) * 36, 120))
            if excludedFieldCount > 0 {
                Text(L10n.text("已排除 %1$@ 个只读字段。", excludedFieldCount)).font(.caption).foregroundStyle(.secondary)
            }
            Picker(L10n.text("字段操作"), selection: $mode) {
                Text(L10n.text("从字段复制")).tag("copy")
                Text(L10n.text("设为")).tag("set")
                Text(L10n.text("清除字段")).tag("clear")
            }
            if mode == "copy" {
                Picker(L10n.text("来源字段"), selection: $copySource) {
                    ForEach(copySources, id: \.self) { source in
                        Text("\(source.displayName) · \(source.rawValue)").tag(source)
                    }
                }.accessibilityIdentifier("metadataBatchSource")
                Text(L10n.text("每张照片使用自己的来源值（含待保存修改）；来源缺失时跳过。"))
                    .font(.caption).foregroundStyle(.secondary)
            } else if mode == "set" {
                TextField(L10n.text("字段值"), text: $input, axis: .vertical).lineLimit(2...5)
                if initialTargets.contains(where: \.isDate) { Text("YYYY:MM:DD HH:mm:ss[.subseconds][±HH:mm]").font(.caption) }
                if initialTargets.contains(where: \.isList) { Text(L10n.text("列表值每行一项；逗号属于内容。")).font(.caption) }
            }
            Text(L10n.text("先预览全部目标，加入待保存修改后再保存照片。"))
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 8)
    }

}
