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
    public enum SkipReason: Equatable, Sendable { case missingValue, filenameMismatch, unsupportedField }
    public struct SkippedItem: Equatable, Sendable {
        public let photoID: ImageData.ID
        public let filename: String
        public let tag: MetadataTag
        public let reason: SkipReason
    }
    public struct OperationResult: Sendable {
        public let tag: MetadataTag
        public let changed: Set<ImageData.ID>
        public let unchanged: Set<ImageData.ID>
        public let skipped: Set<ImageData.ID>
    }
    public let operationResults: [OperationResult]
    public let skipDetails: [SkippedItem]
    public let skipReasons: [String: SkipReason]

    public init(items: [MetadataCreatorEditPlan.Item], steps: [MetadataCreatorEditPlan.Item], skipped: [String],
                skipReasons: [String: SkipReason] = [:], skipDetails: [SkippedItem] = [], operationResults: [OperationResult] = []) {
        self.items = items; self.steps = steps; self.skipped = skipped; self.skipReasons = skipReasons; self.skipDetails = skipDetails
        self.operationResults = operationResults
    }

    public static func prepare(
        _ readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)],
        operations: [MetadataOperation]
    ) throws -> Self {
        guard !operations.isEmpty else { throw MetadataFieldEditError.invalidAction }
        try validateSources(readings)
        let validation = MetadataEditValidation()
        var working = readings
        var steps: [MetadataCreatorEditPlan.Item] = []
        var skipped: [String] = []
        var skipReasons: [String: SkipReason] = [:]
        var skipDetails: [SkippedItem] = []
        var operationResults: [OperationResult] = []
        for operation in operations {
            var changedIDs = Set<ImageData.ID>(), unchangedIDs = Set<ImageData.ID>(), skippedIDs = Set<ImageData.ID>()
            try Task.checkCancellation()
            try MetadataCreatorEditPlan.validate(working.filter { $0.image.supportsMetadataEditing(operation.tag) },
                                                tag: operation.tag, validation: validation)
            try validateDateParameters(operation)
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
                try Task.checkCancellation()
                let reading = working[index]
                guard reading.image.supportsMetadataEditing(operation.tag) else {
                    let entry = "\(reading.image.name) · \(operation.tag.rawValue)"
                    skipped.append(entry); skipReasons[entry] = .unsupportedField
                    skipDetails.append(SkippedItem(photoID: reading.image.id, filename: reading.image.name,
                                                   tag: operation.tag, reason: .unsupportedField))
                    skippedIDs.insert(reading.image.id)
                    continue
                }
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
                        let entry = "\(name) · \(operation.tag.rawValue)"
                        skipped.append(entry); skipReasons[entry] = .filenameMismatch
                        skipDetails.append(SkippedItem(photoID: reading.image.id, filename: reading.image.name,
                                                       tag: operation.tag, reason: .filenameMismatch))
                        skippedIDs.insert(reading.image.id)
                        continue
                    }
                    action = .setText(parsed.text)
                case .copy(let source):
                    guard reading.snapshot.requestedTags.contains(source) else { throw MetadataCreatorPlanError.invalidValue }
                    guard let original = value(source) else {
                        let entry = "\(reading.image.name) · \(source.rawValue)"
                        skipped.append(entry); skipReasons[entry] = .missingValue
                        skipDetails.append(SkippedItem(photoID: reading.image.id, filename: reading.image.name,
                                                       tag: operation.tag, reason: .missingValue))
                        skippedIDs.insert(reading.image.id)
                        continue
                    }
                    switch (operation.tag, original) {
                    case (.creator, .list(let names)): action = .replaceAuthors(names)
                    case (_, .list(let words)) where operation.tag.isList: action = .replaceKeywords(words)
                    case (_, .text(let text)): action = .setText(text)
                    default: throw MetadataFieldEditError.invalidAction
                    }
                case .shiftDate(let seconds), .calendarDays(let seconds, _), .dateComponent(_, let seconds):
                    guard let current = value(operation.tag) else {
                        let entry = "\(reading.image.name) · \(operation.tag.rawValue)"
                        skipped.append(entry); skipReasons[entry] = .missingValue
                        skipDetails.append(SkippedItem(photoID: reading.image.id, filename: reading.image.name,
                                                       tag: operation.tag, reason: .missingValue))
                        skippedIDs.insert(reading.image.id)
                        continue
                    }
                    guard case .text(let text) = current else { throw MetadataFieldEditError.invalidValue }
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
                case .offsetDate:
                    guard operation.tag.isDate else { throw MetadataFieldEditError.invalidAction }
                    if value(operation.tag) == nil {
                        let entry = "\(reading.image.name) · \(operation.tag.rawValue)"
                        skipped.append(entry); skipReasons[entry] = .missingValue
                        skipDetails.append(SkippedItem(photoID: reading.image.id, filename: reading.image.name,
                                                       tag: operation.tag, reason: .missingValue))
                        skippedIDs.insert(reading.image.id)
                        continue
                    }
                default: break
                }
                let item = try MetadataCreatorEditPlan.prepare([reading], tag: operation.tag, action: action, validation: validation).items[0]
                let before = value(operation.tag)
                working[index].image.applyMetadataDraft(item)
                let after: MetadataTagValue?
                switch item.changes[operation.tag] {
                case .set(let value): after = value
                case .remove: after = nil
                case nil: after = reading.snapshot.values[operation.tag]
                }
                if before == after { unchangedIDs.insert(reading.image.id) }
                else { changedIDs.insert(reading.image.id) }
                steps.append(item)
            }
            operationResults.append(OperationResult(tag: operation.tag, changed: changedIDs, unchanged: unchangedIDs, skipped: skippedIDs))
        }
        let items = zip(readings, working).compactMap { original, final -> MetadataCreatorEditPlan.Item? in
            guard let draft = final.image.creatorDraft else { return nil }
            func value(_ tag: MetadataTag, changes: [MetadataTag: MetadataTagChange]) -> MetadataTagValue? {
                switch changes[tag] {
                case .set(let value): return value
                case .remove: return nil
                case nil: return original.snapshot.values[tag]
                }
            }
            let before = original.image.creatorDraft?.changes ?? [:]
            let tags = Set(before.keys).union(draft.changes.keys)
            return tags.contains { value($0, changes: before) != value($0, changes: draft.changes) } ? draft : nil
        }
        return Self(items: items, steps: steps, skipped: skipped, skipReasons: skipReasons, skipDetails: skipDetails, operationResults: operationResults)
    }

    public static func validateSources(_ readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)]) throws {
        var seen = Set<String>()
        for reading in readings {
            guard reading.image.metadataInspectionURL?.standardizedFileURL == reading.snapshot.url.standardizedFileURL,
                  MetadataInspectionFileVersion.read(reading.snapshot.url) == reading.snapshot.version,
                  case .file(let device, let inode, _, _, _, _, _) = reading.snapshot.version else {
                throw MetadataCreatorPlanError.sourceChanged
            }
            guard seen.insert("\(device):\(inode)").inserted else { throw MetadataCreatorPlanError.duplicateTarget }
        }
    }

    private static func validateDateParameters(_ operation: MetadataOperation) throws {
        switch operation.action {
        case .offsetDate(let years, let months, let days, let hours, let minutes, let seconds):
            guard operation.tag.isDate else { throw MetadataFieldEditError.invalidAction }
            // Match the six parameter bounds in the unchanged shared date core.
            let offsets = [(years, 9999), (months, 120000), (days, 3660000),
                           (hours, 87840000), (minutes, 5270400000), (seconds, 316224000000)]
            guard offsets.allSatisfy({ (-$0.1...$0.1).contains($0.0) }) else {
                throw MetadataDateError.invalidDate
            }
        case .shiftDate(let seconds):
            guard operation.tag.isDate else { throw MetadataFieldEditError.invalidAction }
            guard (-315537897599...315537897599).contains(seconds) else { throw MetadataDateError.invalidDate }
        case .calendarDays(let days, let zone):
            guard operation.tag.isDate else { throw MetadataFieldEditError.invalidAction }
            guard (-3652058...3652058).contains(days) else {
                throw MetadataDateError.invalidDate
            }
            if let zone, TimeZone(identifier: zone) == nil { throw MetadataDateError.invalidDate }
        case .dateComponent(let name, let value):
            guard operation.tag.isDate else { throw MetadataFieldEditError.invalidAction }
            let ranges = ["year": 1...9999, "month": 1...12, "day": 1...31,
                          "hour": 0...23, "minute": 0...59, "second": 0...59]
            guard ranges[name]?.contains(value) == true else { throw MetadataDateError.invalidDate }
        default: break
        }
    }

}
