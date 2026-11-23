import Exiftool
import Foundation

public struct MetadataOperation: Codable, Equatable, Sendable {
    public let tag: MetadataTag
    public let action: MetadataFieldEditAction
    public let photosOnly: Bool

    private var source: MetadataTag? {
        if case .copy(let source) = action { return source }
        return nil
    }
    public var supportsMovieEditing: Bool {
        !photosOnly && tag.supportsMovieEditing && source?.supportsMovieEditing != false
    }
    public var supportsPhotoEditing: Bool {
        tag.supportsPhotoEditing && source?.supportsPhotoEditing != false
    }

    public func applies(to image: ImageData) -> Bool {
        image.supportsMetadataEditing(tag) && (image.isLocalMovie ? supportsMovieEditing : supportsPhotoEditing)
    }

    public init(tag: MetadataTag, action: MetadataFieldEditAction, photosOnly: Bool = false) {
        self.tag = tag
        self.action = action
        self.photosOnly = photosOnly
    }

    public init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        tag = try fields.decode(MetadataTag.self, forKey: .tag)
        action = try fields.decode(MetadataFieldEditAction.self, forKey: .action)
        // These existing fields gained movie support after RC2. Keep old recipes scoped
        // to photos even when one of them occurs only as the source of a copy.
        photosOnly = try fields.decodeIfPresent(Bool.self, forKey: .photosOnly) ?? Self.wasPhotoOnly(tag, action)
    }

    private static func wasPhotoOnly(_ tag: MetadataTag, _ action: MetadataFieldEditAction) -> Bool {
        let expanded: Set<MetadataTag> = [.lens, .rating]
        if case .copy(let source) = action, expanded.contains(source) { return true }
        return expanded.contains(tag)
    }

    private enum CodingKeys: String, CodingKey { case tag, action, photosOnly }

    public func encode(to encoder: Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(tag, forKey: .tag)
        try fields.encode(action, forKey: .action)
        if photosOnly != Self.wasPhotoOnly(tag, action) {
            try fields.encode(photosOnly, forKey: .photosOnly)
        }
    }
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
    public enum SkipReason: Equatable, Sendable { case missingValue, filenameMismatch, unsupportedField, readOnlyFile, missingVideoTimeZone, localizedMovieField }
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

    private static func adjustedDate(_ date: MetadataDate, action: MetadataFieldEditAction, amount: Int) throws -> String {
        switch action {
        case .shiftDate: return try date.shifting(seconds: amount).text
        case .calendarDays(_, let zone): return try date.addingCalendarDays(amount, timeZoneID: zone).text
        case .dateComponent(let name, let value):
            let components: [String: Calendar.Component] = ["year": .year, "month": .month, "day": .day,
                                                          "hour": .hour, "minute": .minute, "second": .second]
            guard let component = components[name] else { throw MetadataDateError.invalidDate }
            return try date.replacing(component, with: value).text
        default: throw MetadataFieldEditError.invalidAction
        }
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
            try MetadataCreatorEditPlan.validate(working.filter { operation.applies(to: $0.image) },
                                                tag: operation.tag, validation: validation)
            try validateDateParameters(operation)
            let eligibleCount = working.filter { operation.applies(to: $0.image) }.count
            var sequenceIndex = 0
            let sequence: [String]?
            switch operation.action {
            case .sequence(let start, let step):
                guard operation.tag.isDate else { throw MetadataFieldEditError.invalidAction }
                sequence = try MetadataDate.sequence(start: start, stepSeconds: step, count: max(1, eligibleCount))
            case .distribute(let start, let end):
                guard operation.tag.isDate else { throw MetadataFieldEditError.invalidAction }
                sequence = try MetadataDate.distribute(start: start, end: end, count: max(1, eligibleCount))
            default: sequence = nil
            }
            for index in working.indices {
                try Task.checkCancellation()
                let reading = working[index]
                func skip(_ reason: SkipReason, source: MetadataTag? = nil) {
                    let entry = "\(reading.image.name) · \((source ?? operation.tag).rawValue)"
                    skipped.append(entry)
                    skipReasons[entry] = reason
                    skipDetails.append(SkippedItem(photoID: reading.image.id, filename: reading.image.name, tag: operation.tag, reason: reason))
                    skippedIDs.insert(reading.image.id)
                }
                guard operation.applies(to: reading.image) else {
                    skip(reading.image.metadataTargetWritable ? .unsupportedField : .readOnlyFile)
                    continue
                }
                if operation.action == .remove, reading.image.videoInfo?.localizedFields.contains(operation.tag) == true {
                    skip(.localizedMovieField)
                    continue
                }
                var action = operation.action
                func value(_ tag: MetadataTag) -> MetadataTagValue? {
                    if let pending = reading.image.creatorDraft?.changes[tag] {
                        switch pending { case .set(let value): return value; case .remove: return nil }
                    }
                    return reading.snapshot.values[tag]
                }
                if let sequence { action = .setText(sequence[sequenceIndex]); sequenceIndex += 1 }
                switch action {
                case .filenameDate(let pattern, let template):
                    guard operation.tag.isDate else { throw MetadataFieldEditError.invalidAction }
                    let expression = try NSRegularExpression(pattern: pattern)
                    let name = reading.image.name
                    guard let match = expression.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
                          let parsed = try? MetadataDate(expression.replacementString(for: match, in: name, offset: 0, template: template)) else {
                        skip(.filenameMismatch)
                        continue
                    }
                    if reading.image.isLocalMovie, parsed.offset.isEmpty, case .text(let prior) = value(.captureDate) {
                        action = .setText(parsed.text + ((try? MetadataDate(prior).offset) ?? ""))
                    } else { action = .setText(parsed.text) }
                case .copy(let source):
                    guard reading.snapshot.requestedTags.contains(source) else { throw MetadataCreatorPlanError.invalidValue }
                    guard let original = value(source) else {
                        skip(.missingValue, source: source)
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
                        skip(.missingValue)
                        continue
                    }
                    guard case .text(let text) = current else { throw MetadataFieldEditError.invalidValue }
                    let date = try MetadataDate(text)
                    action = .setText(try adjustedDate(date, action: action, amount: seconds))
                case .offsetDate:
                    guard operation.tag.isDate else { throw MetadataFieldEditError.invalidAction }
                    if value(operation.tag) == nil {
                        skip(.missingValue)
                        continue
                    }
                default: break
                }
                let item = try MetadataCreatorEditPlan.prepare([reading], tag: operation.tag, action: action, validation: validation).items[0]
                if reading.image.isLocalMovie, operation.tag == .captureDate,
                   case .set(.text(let time)) = item.changes[.captureDate], try MetadataDate(time).offset.isEmpty {
                    skip(.missingVideoTimeZone)
                    continue
                }
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
