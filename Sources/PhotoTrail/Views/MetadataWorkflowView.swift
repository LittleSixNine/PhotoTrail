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
    var quickPreset: MetadataPreset?
    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("PhotoTrail.MetadataPresets") private var presetData = Data()
    @State private var tag = MetadataTag.captureDate
    @State private var mode = "offset"
    @State private var input = ""
    @State private var copySource = MetadataTag.dateOriginal
    @State private var workflowTab = "actions"
    @State private var cards: [MetadataWorkflowCard] = []
    @State private var selectedCard: UUID?
    @State private var namingPreset = false
    @State private var renamingPreset: String?
    @State private var deletingPreset: String?
    private var operations: [MetadataOperation] {
        get { cards.flatMap(\.operations) }
        nonmutating set { cards = MetadataWorkflowCard.cards(from: newValue); preview = nil }
    }
    private var incompleteCards: Bool { cards.contains { $0.operations.isEmpty } }
    @State private var preview: MetadataWorkflowPreview?
    @State private var presetName = ""
    @State private var selectedPreset = ""
    @State private var notice = ""
    @State private var busy = false

    private var availableTags: [MetadataTag] {
        MetadataTag.allCases.filter { tag in
            tag.supportsSidecar || readings.allSatisfy { if case .image = $0.image.metadata.source { true } else { false } }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(quickPreset?.name ?? (isBatch ? L10n.text("批量编辑字段") : L10n.text("编辑预设…")))
                        .font(.system(size: 24, weight: .semibold))
                    Text(L10n.text("已选择 %1$@ 张照片", readings.count)).foregroundStyle(.secondary)
                }
                Spacer()
                Text(L10n.text("编辑 → 预览 → 加入待保存")).font(.callout).foregroundStyle(.secondary)
            }
            if quickPreset != nil {
                workflowPreview
            } else {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    if isBatch {
                        ScrollView { batchForm.padding(18) }
                    } else {
                        Picker(L10n.text("批量预设…"), selection: $workflowTab) {
                            Text(L10n.text("编排操作")).tag("actions")
                            Text(L10n.text("比较与交换")).tag("exchange")
                            Text(L10n.text("修改预览")).tag("preview")
                        }.pickerStyle(.segmented).padding([.top, .horizontal], 18)
                        ZStack(alignment: .topLeading) {
                            ScrollView { actionForm.padding(18) }
                                .opacity(workflowTab == "actions" ? 1 : 0)
                                .allowsHitTesting(workflowTab == "actions")
                                .accessibilityHidden(workflowTab != "actions")
                            if workflowTab == "exchange" {
                                exchangeForm.padding(18)
                            } else if workflowTab == "preview" {
                                workflowPreview
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(.background, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
                if isBatch {
                    workflowPreview.frame(width: 270)
                } else {
                    Button {
                        renamingPreset = nil; presetName = ""; namingPreset = true
                    } label: {
                        Image(systemName: "arrow.right").font(.title2).frame(width: 30, height: 44)
                    }.buttonStyle(.borderless)
                        .help(L10n.text("将当前操作链新建为预设"))
                        .accessibilityLabel(L10n.text("将当前操作链新建为预设"))
                        .disabled(operations.isEmpty || incompleteCards)
                        .frame(maxHeight: .infinity)
                    presetForm.padding(18)
                        .frame(width: 270, alignment: .topLeading)
                        .frame(maxHeight: .infinity)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
                }
            }.frame(maxHeight: .infinity)
            }
            if !notice.isEmpty { Text(notice).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
            Divider()
            HStack(spacing: 12) {
                if quickPreset == nil {
                    Button(L10n.text("预览")) { makePreview() }.disabled(activeOperations.isEmpty || busy || incompleteCards)
                }
                Spacer()
                Button(L10n.text("取消")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.text("加入待保存修改")) { apply() }
                    .buttonStyle(.borderedProminent)
                    .disabled(preview?.items.isEmpty != false || busy || store.saveInProgress)
            }.controlSize(.large)
        }.font(.system(size: 15)).controlSize(.large).textFieldStyle(.roundedBorder)
            .padding(24)
            .frame(width: min(1120, (NSScreen.main?.visibleFrame.width ?? 1200) - 80),
                   height: min(800, (NSScreen.main?.visibleFrame.height ?? 900) - 100))
            .onAppear {
                if let quickPreset {
                    operations = quickPreset.operations
                    makePreview()
                }
                if isBatch {
                    mode = initialBatchMode; input = initialBatchInput
                    copySource = copySources.contains(.captureDate) ? .captureDate : copySources.first ?? .sidecarDate
                } else if readings.allSatisfy({ if case .xmp = $0.image.metadata.source { true } else { false } }) {
                    tag = .sidecarDate
                }
            }
            .onChange(of: mode) { if isBatch { preview = nil } }
            .onChange(of: input) { if isBatch { preview = nil } }
            .onChange(of: copySource) { if isBatch { preview = nil } }
            .alert(renamingPreset == nil ? L10n.text("新建预设") : L10n.text("重命名"), isPresented: $namingPreset) {
                TextField(L10n.text("预设名称"), text: $presetName)
                Button(L10n.text("取消"), role: .cancel) {}
                Button(L10n.text("保存")) {
                    perform {
                        let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let original = renamingPreset {
                            presetData = try JSONEncoder().encode(MetadataWorkflowCard.renamePreset(original, to: name, in: presets))
                            if selectedPreset == original { selectedPreset = name }
                        } else {
                            try storePreset(MetadataPreset(name: name, operations: operations))
                            selectedPreset = name
                        }
                        notice = L10n.text("预设已保存。")
                    }
                }.disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                           || presets.contains { $0.name != renamingPreset
                               && $0.name == presetName.trimmingCharacters(in: .whitespacesAndNewlines) })
            } message: {
                Text(L10n.text("请输入一个未使用的预设名称。"))
            }
            .alert(L10n.text("删除预设"), isPresented: Binding(
                get: { deletingPreset != nil }, set: { if !$0 { deletingPreset = nil } }),
                   presenting: deletingPreset) { name in
                Button(L10n.text("取消"), role: .cancel) { deletingPreset = nil }
                Button(L10n.text("删除预设"), role: .destructive) {
                    perform { presetData = try JSONEncoder().encode(presets.filter { $0.name != name }) }
                    if selectedPreset == name { selectedPreset = "" }
                    deletingPreset = nil
                }
            } message: { name in
                Text(L10n.text("确定删除预设“%1$@”吗？", name))
            }
    }

}

private extension MetadataWorkflowView {
    var actionForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("操作按顺序执行；每张照片使用自己的字段值，后一步读取前一步的结果。"))
                .font(.caption).foregroundStyle(.secondary)
            ForEach(cards) { card in
                let index = cards.firstIndex { $0.id == card.id } ?? 0
                MetadataOperationCardView(operations: Binding(
                    get: { cards.first(where: { $0.id == card.id })?.operations ?? [] },
                    set: { value in
                        if let current = cards.firstIndex(where: { $0.id == card.id }) {
                            cards[current].operations = value; selectedCard = card.id; preview = nil
                        }
                    }), readings: readings,
                    selected: Binding(get: { selectedCard == card.id }, set: { if $0 { selectedCard = card.id } }),
                    availableTags: availableTags, index: index,
                    moveUp: index > 0 ? { cards.swapAt(index, index - 1); preview = nil } : nil,
                    moveDown: index + 1 < cards.count ? { cards.swapAt(index, index + 1); preview = nil } : nil,
                    remove: { cards.removeAll { $0.id == card.id }; preview = nil })
            }
            Button(L10n.text("新建操作"), systemImage: "plus") {
                preview = nil
                cards.append(MetadataWorkflowCard(operations: [MetadataOperation(tag: tag,
                    action: .offsetDate(years: 0, months: 0, days: 0, hours: 0, minutes: 0, seconds: 0))]))
                selectedCard = cards.last?.id
            }
            Button(L10n.text("清空操作")) { resetOperations() }.disabled(cards.isEmpty)
        }.padding(.vertical, 8)
    }

    private var presetForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("预设")).font(.headline)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(presets, id: \.name) { preset in
                        Button {
                            selectedPreset = preset.name; loadPreset(preset)
                        } label: {
                            HStack {
                                Text(preset.name).lineLimit(2)
                                Spacer()
                                if selectedPreset == preset.name { Image(systemName: "checkmark") }
                            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                .background(selectedPreset == preset.name ? Color.accentColor.opacity(0.12) : .clear,
                                            in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                            .contextMenu {
                                Button(L10n.text("复制")) {
                                    perform {
                                        let name = MetadataWorkflowCard.uniquePresetName(preset.name, existing: presets.map(\.name))
                                        try storePreset(MetadataPreset(name: name, operations: preset.operations))
                                    }
                                }
                                Button(L10n.text("重命名")) {
                                    renamingPreset = preset.name; presetName = preset.name; namingPreset = true
                                }
                                Button(L10n.text("删除"), role: .destructive) { deletingPreset = preset.name }
                            }
                    }
                }
            }.frame(maxHeight: .infinity)
            HStack {
                Spacer()
                Menu {
                    Button(L10n.text("导入预设 JSON")) {
                        perform {
                            guard let url = openFile(type: .json) else { return }
                            let imported = try MetadataPreset.decode(Data(contentsOf: url))
                            let name = MetadataWorkflowCard.uniquePresetName(imported.name, existing: presets.map(\.name), allowOriginal: true)
                            let preset = try MetadataPreset(name: name, operations: imported.operations)
                            try storePreset(preset)
                            selectedPreset = name; loadPreset(preset)
                            notice = L10n.text("预设已导入，可编辑并预览。")
                        }
                    }
                    Button(L10n.text("导出预设 JSON")) {
                        perform {
                            guard let preset = presets.first(where: { $0.name == selectedPreset }) else { return }
                            try saveFile(preset.encode(), name: preset.name + ".json", type: .json)
                        }
                    }.disabled(selectedPreset.isEmpty)
                } label: { Image(systemName: "square.and.arrow.up.on.square").font(.title3) }
                    .menuStyle(.borderlessButton).fixedSize()
                    .help(L10n.text("导入／导出预设"))
                    .accessibilityLabel(L10n.text("导入／导出预设"))
            }
        }
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
        perform {
            preview = try MetadataWorkflowPreview.prepare(readings, operations: activeOperations)
            if !isBatch { workflowTab = "preview" }
        }
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
        case .fileCreateDate: "Metadata field: FileCreateDate"
        case .fileModifyDate: "Metadata field: FileModifyDate"
        case .iptcDateCreated: "Metadata field: DateCreated"
        case .iptcTimeCreated: "Metadata field: TimeCreated"
        case .exifOrientation: "Metadata field: Orientation"
        case .exifXResolution: "Metadata field: XResolution"
        case .exifYResolution: "Metadata field: YResolution"
        case .exifResolutionUnit: "Metadata field: ResolutionUnit"
        case .lensSerial: "Metadata field: LensSerialNumber"
        case .rating: "XMP Rating"
        case .label: "XMP Label"
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
                        VStack(alignment: .leading, spacing: 3) {
                            Text(target.displayName).font(.system(size: 15, weight: .medium))
                            Text(target.rawValue).font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: min(CGFloat(initialTargets.count) * 48, 150))
            if excludedFieldCount > 0 {
                Text(L10n.text("已排除 %1$@ 个只读字段。", excludedFieldCount)).font(.caption).foregroundStyle(.secondary)
            }
            Picker(L10n.text("字段操作"), selection: $mode) {
                Text(L10n.text("把值复制到字段")).tag("copy")
                Text(L10n.text("设为")).tag("set")
                if !initialTargets.contains(where: \.isFileTime) { Text(L10n.text("清除字段")).tag("clear") }
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
            HStack {
                TextField(L10n.text("预设名称"), text: $presetName)
                Button(L10n.text("保存命名预设")) {
                    perform {
                        try storePreset(MetadataPreset(name: presetName, operations: activeOperations))
                        notice = L10n.text("预设已保存。")
                    }
                }.disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text(L10n.text("先预览全部目标，加入待保存修改后再保存照片。"))
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 8)
    }

}

private extension MetadataWorkflowView {
    var workflowPreview: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("修改预览")).font(.headline)
            ScrollView {
                if let preview {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        Text(L10n.text("预览：%1$@ 张将修改", preview.items.filter { !$0.changes.isEmpty }.count))
                            .font(.callout.weight(.semibold)).foregroundStyle(Color.accentColor)
                        ForEach(Array(preview.steps.enumerated()), id: \.offset) { _, item in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.imageURL.lastPathComponent).font(.caption.weight(.medium))
                                Text(item.tag.displayName).font(.callout.weight(.medium))
                                Text(display(item.originalValue)).foregroundStyle(.secondary)
                                Image(systemName: "arrow.down").font(.caption).foregroundStyle(.secondary)
                                Text(display(item.changeValue)).foregroundStyle(Color.accentColor)
                                Text(item.target.path).font(.caption2).foregroundStyle(.tertiary)
                            }
                            Divider()
                        }
                        ForEach(Array(Set(preview.skipped)).sorted(), id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                    }.textSelection(.enabled)
                } else {
                    Label(L10n.text("点击“预览”检查每张照片的修改结果。"), systemImage: "eye")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(L10n.text("加入待保存后，回到列表保存照片。"))
                .font(.caption).foregroundStyle(.secondary)
        }.padding(18).frame(maxHeight: .infinity, alignment: .top)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
    }
}

private extension MetadataWorkflowView {
    func resetOperations() { cards = []; preview = nil }

    func storePreset(_ preset: MetadataPreset) throws {
        var entries = presets.filter { $0.name != preset.name }
        entries.append(preset)
        presetData = try JSONEncoder().encode(entries)
    }

    func loadPreset(_ preset: MetadataPreset) {
        resetOperations(); operations = preset.operations; presetName = preset.name; workflowTab = "actions"
    }
}

struct MetadataWorkflowCard: Identifiable, Equatable {
    let id = UUID()
    var operations: [MetadataOperation]

    static func renamePreset(_ original: String, to name: String, in presets: [MetadataPreset]) throws -> [MetadataPreset] {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = presets.firstIndex(where: { $0.name == original }),
              !presets.contains(where: { $0.name == name && $0.name != original }) else {
            throw MetadataFieldEditError.invalidValue
        }
        var result = presets
        result[index] = try MetadataPreset(name: name, operations: presets[index].operations)
        return result
    }

    static func cards(from operations: [MetadataOperation]) -> [Self] {
        var cards: [Self] = []
        // Version 1 stores each copy destination as a separate operation.
        for operation in operations {
            if case .copy(let source) = operation.action, operation.tag != source,
               let last = cards.last, last.operations.first?.action == operation.action,
               !last.operations.contains(where: { $0.tag == source || $0.tag == operation.tag }) {
                cards[cards.count - 1].operations.append(operation)
            } else { cards.append(Self(operations: [operation])) }
        }
        return cards
    }

    static func uniquePresetName(_ name: String, existing: [String], allowOriginal: Bool = false) -> String {
        let names = Set(existing)
        if allowOriginal && !names.contains(name) { return name }
        var number = 2
        while names.contains(name + " \(number)") { number += 1 }
        return name + " \(number)"
    }
}

private struct MetadataOperationCardView: View {
    @Binding var operations: [MetadataOperation]
    let readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)]
    @Binding var selected: Bool
    @FocusState private var editing: Bool
    let availableTags: [MetadataTag]
    let index: Int
    let moveUp: (() -> Void)?
    let moveDown: (() -> Void)?
    let remove: () -> Void
    @State private var expanded = true
    @State private var loaded = false
    @State private var lastDraft: [MetadataOperation] = []
    @State private var tag = MetadataTag.captureDate
    @State private var mode = "offset"
    @State private var input = ""
    @State private var end = ""
    @State private var amount = 0
    @State private var zone = ""
    @State private var component = "year"
    @State private var copySource = MetadataTag.captureDate
    @State private var copyTargets: Set<MetadataTag> = []
    @State private var dateOffsets = Array(repeating: 0, count: 6)
    @State private var offsetNegative = Array(repeating: false, count: 6)
    private let actionLabels = ["set": "设为", "fill": "仅补空值", "clear": "清除字段", "append": "追加文字",
                                "keywords": "追加关键词", "removeKeywords": "移除指定关键词", "shift": "整体偏移（秒）",
                                "offset": "时间偏移", "days": "日历增加天数", "component": "修改时间中的指定部分", "sequence": "按固定间隔设置时间",
                                "filename": "从文件名解析日期", "distribute": "在时间范围内均匀分配", "copy": "把值复制到字段"]
    private var modes: [String] {
        if tag.isFileTime { return ["set", "offset", "component", "sequence", "distribute", "filename", "copy"] }
        if tag.isDate { return ["set", "clear", "offset", "component", "sequence", "distribute", "filename", "copy"] }
        if tag.isList && tag != .creator { return ["set", "clear", "keywords", "removeKeywords", "copy"] }
        if tag == .creator { return ["set", "fill", "clear", "copy"] }
        if tag.isPartialDate { return ["set", "fill", "clear", "copy"] }
        if tag.numericRange != nil { return ["set", "fill", "clear", "copy"] }
        return ["set", "fill", "clear", "append", "copy"]
    }

    private var unit: String { tag.numericUnit }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { expanded.toggle() } label: {
                    HStack {
                        Text("\(index + 1)").monospacedDigit().foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tag.displayName).fontWeight(.medium)
                            Text(L10n.text(actionLabels[mode] ?? "字段操作")).font(.caption).foregroundStyle(.secondary)
                        }
                        Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.caption)
                    }
                }.buttonStyle(.plain)
                Spacer()
                Button(L10n.text("上移"), systemImage: "arrow.up") { moveUp?() }.disabled(moveUp == nil)
                Button(L10n.text("下移"), systemImage: "arrow.down") { moveDown?() }.disabled(moveDown == nil)
                Button(L10n.text("删除操作"), systemImage: "trash", action: remove)
            }.labelStyle(.iconOnly).buttonStyle(.borderless)
            if expanded { editor }
        }.padding(14)
            .background(selected || editing ? Color.blue.opacity(0.08) : Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(
                selected || editing ? Color.blue : Color.secondary.opacity(0.18), lineWidth: selected || editing ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .focused($editing)
            .simultaneousGesture(TapGesture().onEnded { selected = true })
            .onChange(of: editing) { if editing { selected = true } }
            .onAppear {
                guard !loaded, let first = operations.first else { return }
                if case .copy(let source) = first.action {
                    tag = source; copyTargets = Set(operations.map(\.tag))
                } else { tag = first.tag }
                loadAction(first.action)
                lastDraft = draftOperations
                loaded = true
            }
            .onChange(of: draftOperations) {
                if loaded && draftOperations != lastDraft {
                    lastDraft = draftOperations; operations = draftOperations
                }
            }
            .onChange(of: tag) {
                if !(modes + ["shift", "days"]).contains(mode) { mode = tag.isDate ? "offset" : "set"; input = "" }
            }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(mode == "copy" ? L10n.text("来源字段") : L10n.text("目标字段"), selection: $tag) {
                ForEach(availableTags, id: \.self) { Text("\($0.displayName) · \($0.rawValue)").tag($0) }
            }
            Text(L10n.text("当前值：%1$@", display(value(readings[0], tag: tag)))).font(.caption).textSelection(.enabled)
            Picker(L10n.text("字段操作"), selection: $mode) {
                ForEach(modes + (["shift", "days"].contains(mode) ? [mode] : []), id: \.self) { Text(L10n.text(actionLabels[$0]!)).tag($0) }
            }
            if mode == "filename" {
                TextField(L10n.text("文件名正则表达式"), text: $input)
                TextField(L10n.text("日期模板（如 $1:$2:$3 12:00:00）"), text: $end)
            } else if mode == "copy" {
                copyDestinationFields
                Text(L10n.text("每张照片使用自己的来源值（含待保存修改）；来源缺失时跳过。"))
                    .font(.caption).foregroundStyle(.secondary)
            } else if mode == "offset" {
                let labels = ["年", "月", "日", "时", "分", "秒"]
                ForEach(0..<6, id: \.self) { index in
                    HStack(spacing: 10) {
                        Text(L10n.text(labels[index])).frame(width: 26, alignment: .leading)
                        Picker(L10n.text("偏移方向"), selection: offsetDirection(index)) {
                            Text(L10n.text("增加（＋）")).tag(false)
                            Text(L10n.text("减少（－）")).tag(true)
                        }.labelsHidden().frame(width: 120)
                        TextField(L10n.text(labels[index]), value: offsetMagnitude(index), format: .number)
                            .labelsHidden()
                    }
                }
            } else if ["shift", "days", "component"].contains(mode) {
                Stepper(L10n.text("数值：%1$@", amount), value: $amount, in: -1_000_000...1_000_000)
                TextField(L10n.text("整数数值"), value: $amount, format: .number)
                if mode == "days" { TextField(L10n.text("时区标识（可选，如 America/New_York）"), text: $zone) }
                if mode == "component" {
                    Picker(L10n.text("要修改的部分"), selection: $component) {
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
                    if ["sequence", "distribute"].contains(mode) { Text(L10n.text("开始时间")).font(.callout) }
                    TextField(["sequence", "distribute"].contains(mode) ? L10n.text("开始时间") : L10n.text("字段值"),
                              text: $input, axis: .vertical).lineLimit(2...4)
                }
                if tag.isDate { Text("YYYY:MM:DD HH:mm:ss[.subseconds][±HH:mm]").font(.caption) }
                if tag.isList { Text(L10n.text("列表值每行一项；逗号属于内容。")) }
                if let limit = tag.maxUTF8Length { Text(L10n.text("每项最多 %1$@ 个 UTF-8 字节", limit)).font(.caption) }
                if let range = tag.numericRange { Text("\(unit) · \(range.lowerBound)…\(range.upperBound)").font(.caption) }
                if mode == "sequence" {
                    Text(L10n.text("每张照片间隔（秒）")).font(.callout)
                    TextField(L10n.text("每张照片间隔（秒）"), value: $amount, format: .number)
                }
                if mode == "distribute" {
                    Text(L10n.text("结束时间")).font(.callout)
                    TextField(L10n.text("结束时间"), text: $end)
                }
            }
        }
    }

    private var copyDestinationFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("接收字段")).font(.headline)
            Text(L10n.text("将上方来源字段的值复制到以下字段，覆盖原值；来源字段保持不变。"))
                .font(.caption).foregroundStyle(.secondary)
            Menu(L10n.text("添加接收字段…")) {
                ForEach(availableTags.filter { $0 != tag }, id: \.self) { target in
                    Toggle("\(target.displayName) · \(target.rawValue)", isOn: Binding(
                        get: { copyTargets.contains(target) },
                        set: { selected in
                            if selected { copyTargets.insert(target) } else { copyTargets.remove(target) }
                        }))
                }
            }
            ForEach(availableTags.filter { $0 != tag && copyTargets.contains($0) }, id: \.self) { target in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(target.displayName)
                        Text(target.rawValue).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L10n.text("删除操作"), systemImage: "minus.circle") { copyTargets.remove(target) }
                        .labelStyle(.iconOnly).buttonStyle(.borderless)
                }
            }
        }
    }

    private var draftOperations: [MetadataOperation] {
        let words = input.split(separator: "\n").map(String.init)
        let action: MetadataFieldEditAction
        switch mode {
        case "clear": action = .remove
        case "fill": action = tag == .creator ? .fillMissingAuthors(words) : .fillMissingText(input)
        case "append": action = .appendText(input)
        case "keywords": action = .appendKeywords(words)
        case "removeKeywords": action = .removeKeywords(words)
        case "offset": action = .offsetDate(years: dateOffsets[0], months: dateOffsets[1], days: dateOffsets[2],
                                             hours: dateOffsets[3], minutes: dateOffsets[4], seconds: dateOffsets[5])
        case "shift": action = .shiftDate(seconds: amount)
        case "days": action = .calendarDays(amount, timeZoneID: zone.isEmpty ? nil : zone)
        case "component": action = .dateComponent(component, amount)
        case "sequence": action = .sequence(start: input, stepSeconds: amount)
        case "distribute": action = .distribute(start: input, end: end)
        case "filename": action = .filenameDate(pattern: input, template: end)
        case "copy": action = .copy(tag)
        default: action = tag == .creator ? .replaceAuthors(words) : tag.isList && tag != .creator ? .replaceKeywords(words) : .setText(input)
        }
        let targets = mode == "copy" ? availableTags.filter { $0 != tag && copyTargets.contains($0) } : [tag]
        return targets.map { MetadataOperation(tag: $0, action: action) }
    }

    private func value(_ reading: (image: ImageData, snapshot: MetadataInspectionSnapshot), tag: MetadataTag) -> MetadataTagValue? {
        if let pending = reading.image.creatorDraft?.changes[tag] {
            switch pending { case .set(let value): return value; case .remove: return nil }
        }
        return reading.snapshot.values[tag]
    }
    private func display(_ value: MetadataTagValue?) -> String {
        switch value { case nil: L10n.text("未填写"); case .text(let text): text; case .list(let values): values.joined(separator: " / ") }
    }

    func loadAction(_ action: MetadataFieldEditAction) {
        input = ""; end = ""; zone = ""
        switch action {
        case .setText(let text): mode = "set"; input = text
        case .fillMissingText(let text): mode = "fill"; input = text
        case .replaceAuthors(let words), .replaceKeywords(let words): mode = "set"; input = words.joined(separator: "\n")
        case .fillMissingAuthors(let words): mode = "fill"; input = words.joined(separator: "\n")
        case .appendText(let text): mode = "append"; input = text
        case .appendKeywords(let words): mode = "keywords"; input = words.joined(separator: "\n")
        case .removeKeywords(let words): mode = "removeKeywords"; input = words.joined(separator: "\n")
        case .remove: mode = "clear"
        case .copy(let source): mode = "copy"; copySource = source
        case .shiftDate(let seconds): mode = "offset"; dateOffsets = [0, 0, 0, 0, 0, seconds]
        case .calendarDays(let days, let timeZone):
            if let timeZone { mode = "days"; amount = days; zone = timeZone }
            else { mode = "offset"; dateOffsets = [0, 0, days, 0, 0, 0] }
        case .dateComponent(let name, let value): mode = "component"; component = name; amount = value
        case .sequence(let start, let step): mode = "sequence"; input = start; amount = step
        case .distribute(let start, let finish): mode = "distribute"; input = start; end = finish
        case .filenameDate(let pattern, let template): mode = "filename"; input = pattern; end = template
        case .offsetDate(let years, let months, let days, let hours, let minutes, let seconds):
            mode = "offset"; dateOffsets = [years, months, days, hours, minutes, seconds]
        }
        offsetNegative = dateOffsets.map { $0 < 0 }
    }

    func offsetDirection(_ index: Int) -> Binding<Bool> {
        Binding(get: { dateOffsets[index] < 0 || (dateOffsets[index] == 0 && offsetNegative[index]) }, set: { negative in
            offsetNegative[index] = negative
            let magnitude = dateOffsets[index] == .min ? Int.max : abs(dateOffsets[index])
            dateOffsets[index] = negative ? -magnitude : magnitude
        })
    }

    func offsetMagnitude(_ index: Int) -> Binding<Int> {
        Binding(get: { dateOffsets[index] == .min ? Int.max : abs(dateOffsets[index]) }, set: { value in
            let negative = offsetDirection(index).wrappedValue
            let magnitude = value == .min ? Int.max : abs(value)
            dateOffsets[index] = negative ? -magnitude : magnitude
            offsetNegative[index] = negative
        })
    }

}
