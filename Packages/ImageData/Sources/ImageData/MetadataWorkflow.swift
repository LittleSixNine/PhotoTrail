import Exiftool
import Foundation

public struct MetadataOperation: Codable, Equatable, Sendable {
    public let tag: MetadataTag
    public let action: MetadataFieldEditAction
    public init(tag: MetadataTag, action: MetadataFieldEditAction) { self.tag = tag; self.action = action }
}

public struct MetadataPreset: Codable, Equatable, Sendable {
    public let version: Int
    public let name: String
    public let operations: [MetadataOperation]
    public init(name: String, operations: [MetadataOperation]) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !operations.isEmpty else {
            throw MetadataFieldEditError.invalidValue
        }
        version = 1; self.name = name; self.operations = operations
    }
    public static func decode(_ data: Data) throws -> Self {
        let preset = try JSONDecoder().decode(Self.self, from: data)
        guard preset.version == 1 else { throw MetadataFieldEditError.invalidAction }
        return try Self(name: preset.name, operations: preset.operations)
    }
    public func encode() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

public struct MetadataWorkflowPreview: Sendable {
    public let items: [MetadataCreatorEditPlan.Item]
    public let steps: [MetadataCreatorEditPlan.Item]
    public let skipped: [String]

    public init(items: [MetadataCreatorEditPlan.Item], steps: [MetadataCreatorEditPlan.Item], skipped: [String]) {
        self.items = items; self.steps = steps; self.skipped = skipped
    }

    public static func prepare(
        _ readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)],
        operations: [MetadataOperation]
    ) throws -> Self {
        guard !operations.isEmpty else { throw MetadataFieldEditError.invalidAction }
        var seen = Set<String>()
        for reading in readings {
            guard case .file(let device, let inode, _, _, _, _, _) = reading.snapshot.version,
                  seen.insert("\(device):\(inode)").inserted else { throw MetadataCreatorPlanError.duplicateTarget }
        }
        var working = readings
        var steps: [MetadataCreatorEditPlan.Item] = []
        var skipped: [String] = []
        for operation in operations {
            let sequence: [String]?
            switch operation.action {
            case .sequence(let start, let step):
                guard operation.tag.isDate else { throw MetadataFieldEditError.invalidAction }
                sequence = try MetadataDate.sequence(start: start, stepSeconds: step, count: readings.count)
            case .distribute(let start, let end):
                guard operation.tag.isDate else { throw MetadataFieldEditError.invalidAction }
                sequence = try MetadataDate.distribute(start: start, end: end, count: readings.count)
            default: sequence = nil
            }
            for index in working.indices {
                let reading = working[index]
                var action = operation.action
                func value(_ tag: MetadataTag) -> MetadataTagValue? {
                    if let pending = reading.image.creatorDraft?.changes[tag] {
                        switch pending { case .set(let value): return value; case .remove: return nil }
                    }
                    return reading.snapshot.values[tag]
                }
                if let sequence { action = .setText(sequence[index]) }
                switch action {
                case .filenameDate(let pattern, let template):
                    guard operation.tag.isDate else { throw MetadataFieldEditError.invalidAction }
                    let expression = try NSRegularExpression(pattern: pattern)
                    let name = reading.image.name
                    guard let match = expression.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
                          let parsed = try? MetadataDate(expression.replacementString(for: match, in: name, offset: 0, template: template)) else {
                        skipped.append("\(name) · \(operation.tag.rawValue)")
                        continue
                    }
                    action = .setText(parsed.text)
                case .copy(let source):
                    guard reading.snapshot.requestedTags.contains(source) else { throw MetadataCreatorPlanError.invalidValue }
                    guard let original = value(source) else {
                        skipped.append("\(reading.image.name) · \(source.rawValue)")
                        continue
                    }
                    switch (operation.tag, original) {
                    case (.creator, .list(let names)): action = .replaceAuthors(names)
                    case (_, .list(let words)) where operation.tag.isList: action = .replaceKeywords(words)
                    case (_, .text(let text)): action = .setText(text)
                    default: throw MetadataFieldEditError.invalidAction
                    }
                case .shiftDate(let seconds), .calendarDays(let seconds, _), .dateComponent(_, let seconds):
                    guard operation.tag.isDate, case .text(let text) = value(operation.tag) else {
                        throw MetadataDateError.missingDate
                    }
                    let date = try MetadataDate(text)
                    switch action {
                    case .shiftDate: action = .setText(try date.shifting(seconds: seconds).text)
                    case .calendarDays(_, let zone): action = .setText(try date.addingCalendarDays(seconds, timeZoneID: zone).text)
                    case .dateComponent(let name, let value):
                        let components: [String: Calendar.Component] = ["year": .year, "month": .month, "day": .day,
                                                                      "hour": .hour, "minute": .minute, "second": .second]
                        guard let component = components[name] else { throw MetadataDateError.invalidDate }
                        action = .setText(try date.replacing(component, with: value).text)
                    default: break
                    }
                default: break
                }
                let item = try MetadataCreatorEditPlan.prepare([reading], tag: operation.tag, action: action).items[0]
                working[index].image.applyMetadataDraft(item)
                steps.append(item)
            }
        }
        return Self(items: working.compactMap { $0.image.creatorDraft }, steps: steps, skipped: skipped)
    }
}
