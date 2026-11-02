import Exiftool
import Foundation
import SwiftUI
import ImageData
import UDF

struct MetadataBatchField: Identifiable, Equatable {
    enum Mode: String, CaseIterable {
        case keep, set, fill, append, removeItems, clear, offset, sequence, distribute, copy, copyTo

        var label: String {
            switch self {
            case .keep: L10n.text("保持原值")
            case .set: L10n.text("设为")
            case .fill: L10n.text("仅补空值")
            case .append: L10n.text("追加项目")
            case .removeItems: L10n.text("移除指定项目")
            case .clear: L10n.text("清除字段")
            case .offset: L10n.text("时间偏移")
            case .sequence: L10n.text("逐张设置时间（固定间隔）")
            case .distribute: L10n.text("在起止时间之间平均分配")
            case .copy: L10n.text("从其他字段复制…")
            case .copyTo: L10n.text("将此字段复制到…")
            }
        }
    }

    private(set) var id = UUID()
    let tag: MetadataTag
    var mode: Mode = .keep
    var input = ""
    var end = ""
    var interval = "1"
    var offsets = Array(repeating: "0", count: 6)
    var subtract = false
    var source = MetadataTag.captureDate
    var destinations = Set<MetadataTag>()
    private var originalList: [String]?
    private var originalInput = ""

    init(tag: MetadataTag, value: MetadataTagValue? = nil) {
        self.tag = tag
        switch value {
        case .text(let text): input = text
        case .list(let values): originalList = values; input = values.joined(separator: "\n")
        case nil: break
        }
        originalInput = input
    }

    var modes: [Mode] {
        if tag.isDate { return [.keep, .set, .offset, .sequence, .distribute, .copy, .copyTo] + (tag.isFileTime ? [] : [.fill, .clear]) }
        if tag.isList && tag != .creator { return [.keep, .set, .append, .removeItems, .copy, .copyTo, .clear] }
        return [.keep, .set, .fill, .copy, .copyTo, .clear]
    }

    func duplicated() -> Self {
        var copy = self
        copy.id = UUID()
        return copy
    }

    static func canCopy(from source: MetadataTag, to target: MetadataTag) -> Bool {
        guard source != target else { return false }
        if target.isDate { return source.isDate }
        if target.isPartialDate { return source.isDate || source.isPartialDate }
        return source.isList == target.isList && !source.isDate
    }

    var operations: [MetadataOperation] {
        get throws {
            guard mode == .copyTo else { return try operation().map { [$0] } ?? [] }
            guard !destinations.isEmpty, destinations.allSatisfy({ Self.canCopy(from: tag, to: $0) }) else {
                throw MetadataFieldEditError.invalidAction
            }
            return MetadataTag.allCases.filter { destinations.contains($0) }.map { MetadataOperation(tag: $0, action: .copy(tag)) }
        }
    }

    mutating func updateInput(_ value: String, clearEmpty: Bool = false) {
        guard !input.utf8.elementsEqual(value.utf8) else { return }
        input = value
        if clearEmpty { mode = value.isEmpty ? .clear : .set }
        else if mode == .keep { mode = .set }
    }

    mutating func use(_ value: MetadataTagValue) {
        switch value {
        case .text(let text): input = text; originalList = nil
        case .list(let values): input = values.joined(separator: "\n"); originalList = values
        }
        originalInput = input
        mode = .set
    }

    func operation() throws -> MetadataOperation? {
        guard mode != .keep else { return nil }
        guard modes.contains(mode) else { throw MetadataFieldEditError.invalidAction }
        let names = input.utf8.elementsEqual(originalInput.utf8) ? originalList ?? input.split(separator: "\n").map(String.init)
            : input.split(separator: "\n").map(String.init)
        let text: String
        if tag.isDate && [.set, .fill, .sequence, .distribute].contains(mode) {
            text = try MetadataDate(Self.dateText(input)).text
        } else { text = input }
        let action: MetadataFieldEditAction
        switch mode {
        case .keep: return nil
        case .set:
            action = tag == .creator ? .replaceAuthors(names) : tag.isList ? .replaceKeywords(names) : .setText(text)
        case .fill: action = tag == .creator ? .fillMissingAuthors(names) : .fillMissingText(text)
        case .append: action = .appendKeywords(names)
        case .removeItems: action = .removeKeywords(names)
        case .clear: action = .remove
        case .copy: action = .copy(source)
        case .copyTo: throw MetadataFieldEditError.invalidAction
        case .offset:
            let amounts = try offsets.map { value -> Int in
                guard let amount = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)), amount >= 0 else { throw MetadataDateError.invalidDate }
                return subtract ? -amount : amount
            }
            action = .offsetDate(years: amounts[0], months: amounts[1], days: amounts[2],
                                 hours: amounts[3], minutes: amounts[4], seconds: amounts[5])
        case .sequence:
            guard let seconds = Int(interval) else { throw MetadataDateError.invalidSequence }
            action = .sequence(start: text, stepSeconds: seconds)
        case .distribute:
            let last = try MetadataDate(Self.dateText(end)).text
            _ = try MetadataDate.distribute(start: text, end: last, count: 2)
            action = .distribute(start: text, end: last)
        }
        guard !action.hasEmptyInput else { throw MetadataFieldEditError.invalidValue }
        switch action {
        case .setText, .fillMissingText, .replaceAuthors, .fillMissingAuthors, .replaceKeywords, .appendKeywords, .removeKeywords:
            // Check the input here; whole-result and source validation still run for every photo on Apply.
            _ = try action.change(for: tag, from: nil)
            if tag == .creator { _ = try names.map(tag.checkedText) }
        default: break
        }
        return MetadataOperation(tag: tag, action: action)
    }

    static func dateText(_ input: String) -> String {
        guard input.count >= 10 else { return input }
        return input.prefix(10).replacingOccurrences(of: "-", with: ":")
            + input.dropFirst(10).replacingOccurrences(of: "T", with: " ")
    }
}

struct MetadataBatchItemStatistics {
    let changed: Set<ImageData.ID>
    let unchanged: Set<ImageData.ID>
    let skipped: Set<ImageData.ID>

    static func group(_ results: [MetadataWorkflowPreview.OperationResult], by groups: [(UUID, Int)]) -> [UUID: Self] {
        var output: [UUID: Self] = [:], cursor = 0
        for (id, count) in groups where count > 0 {
            guard cursor + count <= results.count else { return [:] }
            let members = results[cursor..<(cursor + count)]
            let changed = members.reduce(into: Set<ImageData.ID>()) { $0.formUnion($1.changed) }
            let skipped = members.reduce(into: Set<ImageData.ID>()) { $0.formUnion($1.skipped) }.subtracting(changed)
            let unchanged = members.reduce(into: Set<ImageData.ID>()) { $0.formUnion($1.unchanged) }.subtracting(changed).subtracting(skipped)
            output[id] = Self(changed: changed, unchanged: unchanged, skipped: skipped)
            cursor += count
        }
        return output
    }
}

struct MetadataValueGroup: Identifiable {
    let id: Data
    let value: MetadataTagValue?
    var photoIDs: Set<ImageData.ID>
}

enum MetadataBatchValues {
    static func value(_ tag: MetadataTag, in reading: (image: ImageData, snapshot: MetadataInspectionSnapshot)) -> MetadataTagValue? {
        switch reading.image.creatorDraft?.changes[tag] {
        case .set(let value): value
        case .remove: nil
        case nil: reading.snapshot.values[tag]
        }
    }

    static func groups(_ tag: MetadataTag, readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)]) -> [MetadataValueGroup] {
        var groups: [MetadataValueGroup] = []
        var indices: [Data: Int] = [:]
        for reading in readings {
            let value = value(tag, in: reading)
            // JSON preserves missing vs text vs list, exact UTF-8, list order and embedded newlines.
            let key = (try? JSONEncoder().encode(value)) ?? Data()
            if let index = indices[key] { groups[index].photoIDs.insert(reading.image.id) }
            else {
                indices[key] = groups.count
                groups.append(MetadataValueGroup(id: key, value: value, photoIDs: [reading.image.id]))
            }
        }
        return groups.sorted { $0.photoIDs.count > $1.photoIDs.count }
    }

    static func text(_ value: MetadataTagValue?) -> String {
        switch value {
        case .text(let text): text
        case .list(let values): values.joined(separator: " / ")
        case nil: L10n.text("未填写")
        }
    }

    static func items(_ tag: MetadataTag, readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)]) -> [MetadataValueGroup] {
        var groups: [MetadataValueGroup] = []
        var indices: [Data: Int] = [:]
        for reading in readings {
            guard case .list(let values) = value(tag, in: reading) else { continue }
            for text in values {
                let key = Data(text.utf8)
                if let index = indices[key] { groups[index].photoIDs.insert(reading.image.id) }
                else {
                    indices[key] = groups.count
                    groups.append(MetadataValueGroup(id: key, value: .list([text]), photoIDs: [reading.image.id]))
                }
            }
        }
        return groups.sorted { $0.photoIDs.count > $1.photoIDs.count }
    }
}

@MainActor @Observable final class MetadataBatchEditSession: Identifiable {
    let id = UUID()
    let inline: Bool
    var editingInput = false
    private(set) var readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)]
    var fields: [MetadataBatchField]
    let application = MetadataDraftApplication()
    var statistics: [UUID: MetadataBatchItemStatistics] = [:]
    var statisticsBusy = false
    var statisticsError = ""
    private var statisticsTask: Task<Void, Never>?
    private var statisticsWorker: Task<MetadataWorkflowPreview, Error>?
    var examples: [String] = []
    var exampleError = ""
    var examplesBusy = false
    private var exampleID: UUID?
    private var exampleWorker: Task<[String], Error>?

    init(readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)], tags: [MetadataTag], inline: Bool = false) {
        self.inline = inline
        self.readings = readings
        fields = []
        for tag in tags where !fields.contains(where: { $0.tag == tag }) { add(tag) }
    }

    var hasInput: Bool { editingInput || application.busy || (application.result == nil && !application.applied && fields.contains { $0.mode != .keep }) }
    var changedFieldCount: Int { fields.filter { $0.mode != .keep }.count }
    var operations: [MetadataOperation] { get throws { try fields.flatMap { try $0.operations } } }
    var isValid: Bool { (try? operations.isEmpty) == false }
    var photoIDs: Set<ImageData.ID> { Set(readings.map(\.image.id)) }

    func add(_ tag: MetadataTag) {
        let groups = MetadataBatchValues.groups(tag, readings: readings)
        fields.append(MetadataBatchField(tag: tag, value: groups.count == 1 ? groups.first?.value : nil))
    }

    func narrow(to ids: Set<ImageData.ID>) {
        guard !application.busy, !application.applied, !photoIDs.isDisjoint(with: ids) else { return }
        readings = readings.filter { ids.contains($0.image.id) }
        application.resetFeedback()
        refreshStatistics()
        invalidateExamples()
    }

    func invalidateExamples() {
        exampleID = nil; exampleWorker?.cancel(); exampleWorker = nil
        examples = []; exampleError = ""; examplesBusy = false
    }

    func discardInput() {
        editingInput = false
        cancelStatistics()
        application.cancel()
        invalidateExamples()
        for index in fields.indices { fields[index].mode = .keep }
    }

    func refreshStatistics() {
        cancelStatistics(); statistics = [:]; statisticsError = ""
        guard !inline, let operations = try? operations, !operations.isEmpty else { statisticsBusy = false; return }
        let readings = readings, groups = fields.map { ($0.id, (try? $0.operations.count) ?? 0) }
        statisticsBusy = true
        let worker = Task.detached(priority: .userInitiated) {
            try MetadataWorkflowPreview.prepare(readings, operations: operations)
        }
        statisticsWorker = worker
        statisticsTask = Task {
            do {
                let result = try await worker.value
                guard !Task.isCancelled else { return }
                statistics = MetadataBatchItemStatistics.group(result.operationResults, by: groups)
            } catch {
                guard !Task.isCancelled else { return }
                statisticsError = L10n.text("操作失败：%1$@", String(describing: error))
            }
            statisticsBusy = false; statisticsWorker = nil
        }
    }

    func cancelStatistics() {
        statisticsTask?.cancel(); statisticsWorker?.cancel(); statisticsWorker = nil; statisticsBusy = false
    }

    func duplicate(_ id: UUID) {
        guard !application.busy, !application.applied, let index = fields.firstIndex(where: { $0.id == id }) else { return }
        fields.insert(fields[index].duplicated(), at: index + 1)
    }

    var appliedStatistics: [UUID: MetadataBatchItemStatistics] {
        guard let result = application.result else { return [:] }
        return MetadataBatchItemStatistics.group(result.operationResults,
            by: fields.map { ($0.id, (try? $0.operations.count) ?? 0) })
    }

    func remove(_ id: UUID) {
        guard !application.busy, !application.applied else { return }
        fields.removeAll { $0.id == id }
    }

    func move(_ id: UUID, by offset: Int) {
        guard !application.busy, !application.applied, let index = fields.firstIndex(where: { $0.id == id }),
              fields.indices.contains(index + offset) else { return }
        fields.swapAt(index, index + offset)
    }

    @MainActor func finishInline(in store: Store<PhotoTrailState, PhotoTrailEvent>) async -> Bool {
        guard inline else { return false }
        if application.busy {
            while application.busy { try? await Task.sleep(for: .milliseconds(10)) }
            return application.result != nil
        }
        if application.applied || application.result != nil { return true }
        guard let operations = try? operations, !operations.isEmpty else { return !hasInput }
        application.apply(readings: readings, operations: operations, requiresSelection: false, store: store)
        while application.busy { try? await Task.sleep(for: .milliseconds(10)) }
        return application.result != nil
    }

    @MainActor func requestSave(in store: Store<PhotoTrailState, PhotoTrailEvent>, workspace: LocationWorkspace) async {
        if inline { guard await finishInline(in: store) else { return } }
        SaveHelper.requestSave(store, workspace: workspace)
    }

    func loadExamples() {
        invalidateExamples()
        guard let operations = try? operations, !operations.isEmpty else { return }
        let readings = readings
        let id = UUID(); exampleID = id; examplesBusy = true
        let worker = Task.detached(priority: .userInitiated) {
            try Self.sample(readings, operations: operations)
        }
        exampleWorker = worker
        Task {
            do {
                let result = try await worker.value
                guard exampleID == id else { return }
                examples = result
            } catch {
                guard exampleID == id else { return }
                exampleError = L10n.text("示例无法计算，请检查输入或来源文件。")
            }
            examplesBusy = false; exampleWorker = nil
        }
    }

    nonisolated static func sample(_ readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)],
                                   operations: [MetadataOperation]) throws -> [String] {
        var examples: [String] = []
        for (index, reading) in readings.prefix(3).enumerated() {
            try Task.checkCancellation()
            let sampled = try operations.map { operation -> MetadataOperation in
                let action: MetadataFieldEditAction
                switch operation.action {
                case .sequence(let start, let step):
                    let (seconds, overflow) = step.multipliedReportingOverflow(by: index)
                    guard !overflow else { throw MetadataDateError.invalidSequence }
                    action = .setText(try MetadataDate(start).shifting(seconds: seconds).text)
                case .distribute(let start, let end):
                    let first = try MetadataDate(start), last = try MetadataDate(end)
                    _ = try MetadataDate.distribute(start: start, end: end, count: 2)
                    let delta = readings.count <= 1 ? 0 : Int((last.date.timeIntervalSince(first.date) * Double(index) / Double(readings.count - 1)).rounded())
                    action = .setText(try first.shifting(seconds: delta).text)
                default: action = operation.action
                }
                return MetadataOperation(tag: operation.tag, action: action)
            }
            let result = try MetadataWorkflowPreview.prepare([reading], operations: sampled)
            let final = result.items.first?.changes ?? reading.image.creatorDraft?.changes ?? [:]
            for operation in operations {
                let before = MetadataBatchValues.value(operation.tag, in: reading)
                let after: MetadataTagValue?
                switch final[operation.tag] {
                case .set(let value): after = value
                case .remove: after = nil
                case nil: after = reading.snapshot.values[operation.tag]
                }
                examples.append(reading.image.name + " · " + operation.tag.rawValue + "\n"
                    + MetadataBatchValues.text(before) + " → " + MetadataBatchValues.text(after))
            }
            for skip in result.skipped { examples.append(skip + " · " + L10n.text("跳过")) }
        }
        return examples
    }
}

private struct MetadataEditSessionKey: EnvironmentKey {
    static var defaultValue: MetadataBatchEditSession? { nil }
}

extension EnvironmentValues {
    var metadataEditSession: MetadataBatchEditSession? {
        get { self[MetadataEditSessionKey.self] }
        set { self[MetadataEditSessionKey.self] = newValue }
    }
}

extension MetadataPreset {
    static func stored(in data: Data) throws -> [MetadataPreset] {
        guard !data.isEmpty else { return [] }
        let entries = try JSONDecoder().decode([MetadataPreset].self, from: data)
        guard entries.allSatisfy({ $0.version == 1 }) else { throw CocoaError(.fileReadCorruptFile) }
        return entries
    }
}
