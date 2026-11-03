import Exiftool
import Foundation
import ImageData

struct MetadataDateCopyPolicy: Codable, Equatable, Sendable {
    var missingTime: String?
    var offset = ""
    var isEmpty: Bool { missingTime == nil && offset.isEmpty }
}

struct MetadataRecipeIssue: Equatable, Sendable {
    let photoID: ImageData.ID
    let filename: String
    let tag: MetadataTag
    let reason: String
}

struct MetadataRecipeResult: Sendable {
    let preview: MetadataWorkflowPreview
    let issues: [MetadataRecipeIssue]
}

enum MetadataBatchRecipe {
    static func validate(_ cards: [MetadataWorkflowCard]) throws {
        guard !cards.isEmpty, cards.allSatisfy(\.isComplete) else { throw MetadataFieldEditError.invalidValue }
        for card in cards {
            if let time = card.datePolicy.missingTime { _ = try MetadataDate(MetadataBatchField.dateText(time)) }
            if !card.datePolicy.offset.isEmpty { _ = try MetadataDate("2000:01:01 00:00:00" + card.datePolicy.offset) }
            for operation in card.operations {
                switch operation.action {
                case .sequence(let start, let step): _ = try MetadataDate.sequence(start: start, stepSeconds: step, count: 1)
                case .distribute(let start, let end): _ = try MetadataDate.distribute(start: start, end: end, count: 2)
                default: _ = try MetadataWorkflowPreview.prepare([], operations: [operation])
                }
                switch operation.action {
                case .setText, .fillMissingText, .replaceAuthors, .fillMissingAuthors,
                     .replaceKeywords, .appendKeywords, .removeKeywords, .appendText:
                    _ = try operation.action.change(for: operation.tag, from: nil)
                case .filenameDate(let pattern, _): _ = try NSRegularExpression(pattern: pattern)
                default: break
                }
            }
        }
    }

    static func prepare(_ readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)],
                        cards: [MetadataWorkflowCard]) throws -> MetadataRecipeResult {
        try validate(cards)
        try MetadataWorkflowPreview.validateSources(readings)
        var working = readings
        var parts: [MetadataWorkflowPreview] = []
        var issues: [MetadataRecipeIssue] = []
        for card in cards {
            try Task.checkCancellation()
            let results: [MetadataWorkflowPreview]
            if let source = card.dateCopySource {
                var batch = MetadataDateBatch()
                batch.source = source
                batch.targets = Set(card.operations.map(\.tag))
                batch.missingTime = card.datePolicy.missingTime
                batch.offset = card.datePolicy.offset
                let rows = try batch.inspect(working)
                results = try zip(working, rows).map { reading, row in
                    if row.missing {
                        issues.append(MetadataRecipeIssue(photoID: row.id, filename: row.filename, tag: source,
                                                          reason: L10n.text("来源值缺失")))
                        return try MetadataWorkflowPreview.prepare([reading], operations: card.operations)
                    }
                    if row.needsTimeZone {
                        issues.append(MetadataRecipeIssue(photoID: row.id, filename: row.filename, tag: .iptcTimeCreated,
                                                          reason: L10n.text("未指定拍摄时区，IPTC 时间保留原值。")))
                    }
                    for tag in row.unsupported {
                        issues.append(MetadataRecipeIssue(photoID: row.id, filename: row.filename, tag: tag,
                                                          reason: L10n.text("文件不支持此字段")))
                    }
                    guard !row.operations.isEmpty else { return MetadataWorkflowPreview(items: [], steps: [], skipped: []) }
                    return try MetadataWorkflowPreview.prepare([reading], operations: row.operations)
                }
            } else {
                results = [try MetadataWorkflowPreview.prepare(working, operations: card.operations)]
            }
            for result in results {
                for detail in result.skipDetails {
                    issues.append(MetadataRecipeIssue(photoID: detail.photoID, filename: detail.filename, tag: detail.tag,
                        reason: detail.reason == .missingValue ? L10n.text("来源值缺失")
                            : detail.reason == .filenameMismatch ? L10n.text("文件名未匹配日期规则") : L10n.text("文件不支持此字段")))
                }
                for step in result.steps {
                    if let index = working.firstIndex(where: { $0.image.id == step.id }) { working[index].image.applyMetadataDraft(step) }
                }
            }
            parts += results
        }
        let items = zip(readings, working).compactMap { before, after -> MetadataCreatorEditPlan.Item? in
            guard let draft = after.image.creatorDraft else { return nil }
            let tags = Set(before.image.creatorDraft?.changes.keys.map { $0 } ?? []).union(draft.changes.keys)
            return tags.contains { MetadataBatchValues.value($0, in: before) != MetadataBatchValues.value($0, in: after) } ? draft : nil
        }
        let skipped = issues.map { $0.filename + " · " + $0.tag.displayName + " · " + $0.reason }
        let preview = MetadataWorkflowPreview(items: items, steps: parts.flatMap(\.steps), skipped: skipped,
            skipDetails: parts.flatMap(\.skipDetails), operationResults: parts.flatMap(\.operationResults))
        return MetadataRecipeResult(preview: preview, issues: issues)
    }
}

// Additional Mac UI parameters are local; the shared v1 operation format is unchanged.
enum MetadataPresetParameters {
    static let key = "PhotoTrail.MetadataPresetParameters.v1"
    struct Entry: Codable {
        let operations: [MetadataOperation]
        let policies: [MetadataDateCopyPolicy]
        var operationCounts: [Int]?
    }
    static func cards(_ preset: MetadataPreset, data: Data) throws -> [MetadataWorkflowCard] {
        var cards = MetadataWorkflowCard.cards(from: preset.operations)
        let entries = try entries(data)
        if let entry = entries[preset.name], entry.operations == preset.operations {
            if let counts = entry.operationCounts {
                guard counts.count == entry.policies.count else { throw MetadataFieldEditError.invalidValue }
                var start = 0
                cards = []
                for count in counts {
                    guard count > 0, count <= preset.operations.count - start else { throw MetadataFieldEditError.invalidValue }
                    cards.append(MetadataWorkflowCard(operations: Array(preset.operations[start..<(start + count)])))
                    start += count
                }
                guard start == preset.operations.count else { throw MetadataFieldEditError.invalidValue }
            }
            guard entry.policies.count == cards.count else { throw MetadataFieldEditError.invalidValue }
            for index in cards.indices { cards[index].datePolicy = entry.policies[index] }
        }
        return cards
    }
    static func entries(_ data: Data) throws -> [String: Entry] {
        data.isEmpty ? [:] : try JSONDecoder().decode([String: Entry].self, from: data)
    }
    static func updating(_ preset: MetadataPreset, cards: [MetadataWorkflowCard], data: Data) throws -> Data {
        var entries = try entries(data)
        entries[preset.name] = Entry(operations: preset.operations, policies: cards.map(\.datePolicy),
                                    operationCounts: cards.map { $0.operations.count })
        return try JSONEncoder().encode(entries)
    }
    static func renamed(_ original: String, to name: String, data: Data, copy: Bool = false) throws -> Data {
        var entries = try entries(data)
        entries[name] = entries[original]
        if !copy { entries[original] = nil }
        return try JSONEncoder().encode(entries)
    }
}
