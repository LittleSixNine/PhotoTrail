import Exiftool
import Foundation
import ImageData

// Mac presentation policy; the date engine and v1 presets keep their existing semantics.
struct MetadataDateBatch: Hashable, Sendable {
    enum Mode: String, CaseIterable { case existing, same, shift }
    static let sources: [MetadataTag] = [.captureDate, .dateOriginal, .sidecarDate]
    static let commonTargets: Set<MetadataTag> = [.captureDate, .exifCreateDate, .dateOriginal, .dateDigitized, .sidecarDate]
    var mode = Mode.existing
    var targets = commonTargets
    var source: MetadataTag? = .captureDate
    var sourceOverrides: [ImageData.ID: MetadataTag] = [:]
    var specifiedTime = ""
    var missingTime: String?
    var offset = ""
    var shiftSeconds = 0

    init() {}
    init?(preset: MetadataPreset) {
        guard let first = preset.operations.first, case .copy(let source) = first.action, source.isDate,
              preset.operations.allSatisfy({ operation in
                  (operation.tag.isDate || operation.tag.isPartialDate) && operation.action == .copy(source)
              }) else { return nil }
        targets = Set(preset.operations.map(\.tag)).union([source])
        self.source = source
    }

    struct Candidate: Identifiable {
        let tag: MetadataTag
        let text: String
        var id: MetadataTag { tag }
    }
    struct Row {
        let id: ImageData.ID
        let filename: String
        let candidates: [Candidate]
        let conflict: Bool
        let missing: Bool
        let needsTimeZone: Bool
        let unsupported: [MetadataTag]
        let operations: [MetadataOperation]
    }

    func candidates(in reading: (image: ImageData, snapshot: MetadataInspectionSnapshot)) throws -> [Candidate] {
        try (source.map { [$0] } ?? Self.sources).compactMap { tag in
            guard case .text(let text) = MetadataBatchValues.value(tag, in: reading) else { return nil }
            return Candidate(tag: tag, text: try MetadataDate(MetadataBatchField.dateText(text)).text)
        }
    }

    func inspect(_ readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)]) throws -> [Row] {
        guard !targets.isEmpty, targets.allSatisfy({ $0.isDate || $0.isPartialDate }),
              (-316224000000...316224000000).contains(shiftSeconds) else { throw MetadataDateError.invalidDate }
        // Validate explicit inputs even when every photo is missing its source.
        let fixed = mode == .same ? try MetadataDate(MetadataBatchField.dateText(specifiedTime)).text : nil
        let fallback = try missingTime.map { try MetadataDate(MetadataBatchField.dateText($0)).text }
        if !offset.isEmpty { _ = try MetadataDate("2000:01:01 00:00:00" + offset) }
        return try readings.map { reading in
            try Task.checkCancellation()
            let candidates = mode == .same ? [] : try candidates(in: reading)
            let conflict = Set(candidates.map(\.text)).count > 1 && sourceOverrides[reading.image.id] == nil
            let chosen = sourceOverrides[reading.image.id].flatMap { tag in candidates.first { $0.tag == tag } } ?? candidates.first
            var text = fixed ?? chosen?.text ?? fallback
            if let current = text {
                var date = try MetadataDate(current)
                if date.offset.isEmpty && !offset.isEmpty { date = try MetadataDate(date.text + offset) }
                if mode == .shift { date = try date.shifting(seconds: shiftSeconds) }
                text = date.text
            }
            let missingZone = try text.map { try MetadataDate($0).offset.isEmpty } ?? false
            let needsZone = missingZone && targets.contains(.iptcTimeCreated) && reading.image.supportsMetadataEditing(.iptcTimeCreated)
            let unsupported = MetadataTag.allCases.filter { targets.contains($0) && !reading.image.supportsMetadataEditing($0) }
            let operations = MetadataTag.allCases.compactMap { tag -> MetadataOperation? in
                guard targets.contains(tag), !unsupported.contains(tag), let text, !conflict,
                      !(tag == .iptcTimeCreated && needsZone) else { return nil }
                return MetadataOperation(tag: tag, action: .setText(text))
            }
            return Row(id: reading.image.id, filename: reading.image.name, candidates: candidates, conflict: conflict,
                       missing: text == nil, needsTimeZone: needsZone, unsupported: unsupported, operations: operations)
        }
    }

    func prepare(_ readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)]) throws -> MetadataWorkflowPreview {
        try MetadataWorkflowPreview.validateSources(readings)
        let rows = try inspect(readings)
        guard !rows.contains(where: \.conflict) else { throw MetadataFieldEditError.invalidValue }
        var results: [MetadataWorkflowPreview] = []
        for (reading, row) in zip(readings, rows) {
            try Task.checkCancellation()
            if !row.operations.isEmpty {
                results.append(try MetadataWorkflowPreview.prepare([reading], operations: row.operations))
            }
        }
        return MetadataWorkflowPreview(items: results.flatMap(\.items), steps: results.flatMap(\.steps),
                                       skipped: results.flatMap(\.skipped),
                                       skipDetails: results.flatMap(\.skipDetails), operationResults: results.flatMap(\.operationResults))
    }
}
