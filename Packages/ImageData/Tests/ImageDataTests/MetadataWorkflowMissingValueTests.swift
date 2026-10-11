import Exiftool
import Foundation
import Metadata
import Testing
@testable import ImageData

struct MetadataWorkflowMissingValueTests {
    private let date = "2024:01:15 10:20:30.123456+08:00"
    private let actions: [MetadataFieldEditAction] = [
        .shiftDate(seconds: 1), .calendarDays(1, timeZoneID: nil), .dateComponent("hour", 12),
        .offsetDate(years: 0, months: 0, days: 0, hours: 0, minutes: 0, seconds: 1)]

    private func readings(_ folder: URL, values: [MetadataTagValue?]) throws
        -> [(image: ImageData, snapshot: MetadataInspectionSnapshot)] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try values.enumerated().map { index, value in
            let url = folder.appendingPathComponent("sample-\(index).jpg")
            try Data("synthetic input \(index)".utf8).write(to: url)
            let snapshot = try MetadataInspectionSnapshot.read([.captureDate, .titleDefault, .rightsDefault], from: url) { _, _ in
                value.map { [.captureDate: $0] } ?? [:]
            }
            return (ImageData(metadata: Metadata(source: .image(url)), name: url.lastPathComponent), snapshot)
        }
    }

    @Test func mixedMissingDatesKeepOrderAndOtherOperations() throws {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = try readings(folder, values: [.text(date), nil, .text("2023:12:31 01:02:03")])
        for action in actions {
            let operation = MetadataOperation(tag: .captureDate, action: action)
            let preview = try MetadataWorkflowPreview.prepare(input, operations: [operation])
            #expect(preview.items.map(\.id) == [input[0].image.id, input[2].image.id])
            #expect(preview.skipped == ["sample-1.jpg · \(MetadataTag.captureDate.rawValue)"])
            #expect(preview.skipReasons[preview.skipped[0]] == .missingValue)
            let compound = try MetadataWorkflowPreview.prepare(input, operations: [operation,
                MetadataOperation(tag: .titleDefault, action: .setText("Keep going"))])
            #expect(compound.items.map(\.id) == input.map(\.image.id))
            #expect(compound.items[1].changes[.captureDate] == nil)
            #expect(compound.items[1].changes[.titleDefault] == .set(.text("Keep going")))
        }
        #expect(input.allSatisfy { $0.image.creatorDraft == nil })
    }

    @Test(arguments: [0, 1, 2])
    func mixedDatesSaveRealCopiesAndPreserveOtherFields(actionIndex: Int) async throws {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let fixture = try #require(Bundle.module.url(forResource: "alldata", withExtension: "jpg"))
        let tags: Set<MetadataTag> = [.captureDate, .rightsDefault, .exifModel]
        var input: [(image: ImageData, snapshot: MetadataInspectionSnapshot)] = []
        for index in 0..<3 {
            let url = folder.appendingPathComponent("real-\(index).jpg")
            try FileManager.default.copyItem(at: fixture, to: url)
            _ = try Exiftool.helper.update(image: url, changes: [
                .captureDate: index == 1 ? .remove : .set(.text(date))])
            input.append((ImageData(metadata: Metadata(source: .image(url)), name: url.lastPathComponent),
                          try MetadataInspectionSnapshot.read(tags, from: url)))
        }
        let originals = try input.map { try Data(contentsOf: $0.snapshot.url) }
        let preset = try MetadataPreset.decode(MetadataPreset(name: "mixed", operations: [
            MetadataOperation(tag: .captureDate, action: actions[actionIndex]),
            MetadataOperation(tag: .rightsDefault, action: .setText("© Synthetic"))]).encode())
        let preview = try MetadataWorkflowPreview.prepare(input, operations: preset.operations)
        #expect(preview.items.count == 3 && preview.skipped.count == 1)
        #expect(try input.map { try Data(contentsOf: $0.snapshot.url) } == originals)
        let backup = folder.appendingPathComponent("backup")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        for (index, item) in preview.items.enumerated() {
            #expect(await item.save(backup: .folder(backup)) == .saved)
            #expect(try Data(contentsOf: backup.appendingPathComponent(item.target.lastPathComponent)) == originals[index])
            let actual = try MetadataInspectionSnapshot.read(tags, from: item.target)
            #expect(actual.values[.exifModel] == input[index].snapshot.values[.exifModel])
            #expect(actual.values[.rightsDefault] == .text("© Synthetic"))
            if index == 1 { #expect(actual.values[.captureDate] == nil) }
            else {
                guard case .set(let expected) = item.changes[.captureDate] else {
                    Issue.record("Expected adjusted date"); continue
                }
                #expect(actual.values[.captureDate] == expected)
            }
        }
    }

    @Test func draftsNoOpsAndOrderedChangesDoNotEnableOldDrafts() throws {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var input = try readings(folder, values: [nil])
        let old = try MetadataCreatorEditPlan.prepare(input, tag: .titleDefault, action: .setText("old")).items[0]
        input[0].image.applyMetadataDraft(old)
        for action in actions {
            let adjust = MetadataOperation(tag: .captureDate, action: action)
            let skipped = try MetadataWorkflowPreview.prepare(input, operations: [adjust])
            #expect(skipped.items.isEmpty && skipped.skipped.count == 1)
            #expect(input[0].image.creatorDraft == old)
            let set = MetadataOperation(tag: .captureDate, action: .setText(date))
            let clear = MetadataOperation(tag: .captureDate, action: .remove)
            let setThenAdjust = try MetadataWorkflowPreview.prepare(input, operations: [set, adjust])
            #expect(setThenAdjust.skipped.isEmpty && setThenAdjust.items.count == 1)
            #expect(setThenAdjust.items[0].changes[.captureDate] != .set(.text(date)))
            let skipThenSet = try MetadataWorkflowPreview.prepare(input, operations: [adjust, set])
            #expect(skipThenSet.items[0].changes[.captureDate] == .set(.text(date)))
            #expect(try MetadataWorkflowPreview.prepare(input, operations: [set, clear, adjust]).items.isEmpty)
        }
        let draftDate = try MetadataCreatorEditPlan.prepare(input, tag: .captureDate, action: .setText(date)).items[0]
        input[0].image.applyMetadataDraft(draftDate)
        let clear = MetadataOperation(tag: .captureDate, action: .remove)
        let adjust = MetadataOperation(tag: .captureDate, action: .shiftDate(seconds: 1))
        let cleared = try MetadataWorkflowPreview.prepare(input, operations: [clear, adjust])
        #expect(cleared.items[0].changes[.captureDate] == .remove && cleared.skipped.count == 1)
        #expect(try MetadataWorkflowPreview.prepare(input, operations: [adjust]).skipped.isEmpty)
        #expect(try MetadataWorkflowPreview.prepare(input, operations: [
            MetadataOperation(tag: .captureDate, action: .shiftDate(seconds: 0))]).items.isEmpty)
        #expect(try MetadataWorkflowPreview.prepare(input, operations: [adjust,
            MetadataOperation(tag: .captureDate, action: .shiftDate(seconds: -1))]).items.isEmpty)
    }

    @Test(arguments: [0, 1, 2, 3, 4, 5])
    func missingDatesStillValidateEveryOffsetUnit(unit: Int) throws {
        let limits = [9999, 120000, 3660000, 87840000, 5270400000, 316224000000]
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var input = try readings(folder, values: [nil, nil, nil])
        let old = try MetadataCreatorEditPlan.prepare(input, tag: .titleDefault, action: .setText("old"))
        for index in input.indices { input[index].image.applyMetadataDraft(old.items[index]) }
        let originalDrafts = input.map { $0.image.creatorDraft }
        func operation(_ amount: Int) -> MetadataOperation {
            var offsets = [Int](repeating: 0, count: 6)
            offsets[unit] = amount
            return MetadataOperation(tag: .captureDate, action: .offsetDate(
                years: offsets[0], months: offsets[1], days: offsets[2],
                hours: offsets[3], minutes: offsets[4], seconds: offsets[5]))
        }
        for amount in [-limits[unit] - 1, limits[unit] + 1, Int.min, Int.max] {
            let invalid = operation(amount)
            #expect(throws: MetadataDateError.invalidDate) {
                try MetadataWorkflowPreview.prepare(input, operations: [invalid])
            }
            for tag in [MetadataTag.titleDefault, .rightsDefault] {
                let valid = MetadataOperation(tag: tag, action: .setText("new"))
                for operations in [[invalid, valid], [valid, invalid]] {
                    #expect(throws: MetadataDateError.invalidDate) {
                        try MetadataWorkflowPreview.prepare(input, operations: operations)
                    }
                    #expect(input.map { $0.image.creatorDraft } == originalDrafts)
                }
            }
        }
        for amount in [-limits[unit], 0, limits[unit]] {
            let preview = try MetadataWorkflowPreview.prepare(input, operations: [operation(amount)])
            #expect(preview.items.isEmpty && preview.skipped.count == input.count)
            #expect(input.map { $0.image.creatorDraft } == originalDrafts)
        }
    }

    @Test func missingDoesNotBypassValidationOrMutateInputs() throws {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = try readings(folder, values: [nil])
        for action in [MetadataFieldEditAction.dateComponent("invalid", 1), .dateComponent("month", 13),
                       .calendarDays(1, timeZoneID: "invalid"), .calendarDays(Int.max, timeZoneID: nil),
                       .shiftDate(seconds: Int.max)] {
            #expect(throws: MetadataDateError.self) {
                try MetadataWorkflowPreview.prepare(input, operations: [MetadataOperation(tag: .captureDate, action: action)])
            }
        }
        for action in actions {
            #expect(throws: MetadataFieldEditError.self) {
                try MetadataWorkflowPreview.prepare(input, operations: [MetadataOperation(tag: .titleDefault, action: action)])
            }
        }
        let adjust = MetadataOperation(tag: .captureDate, action: .shiftDate(seconds: 1))
        for value in [MetadataTagValue.text("invalid"), .text(""), .list([date])] {
            let snapshot = MetadataInspectionSnapshot(url: input[0].snapshot.url, requestedTags: [.captureDate],
                values: [.captureDate: value], version: input[0].snapshot.version)
            #expect(throws: (any Error).self) {
                try MetadataWorkflowPreview.prepare([(input[0].image, snapshot)], operations: [adjust])
            }
        }
        let unrequested = MetadataInspectionSnapshot(url: input[0].snapshot.url, requestedTags: [], values: [:],
                                                     version: input[0].snapshot.version)
        #expect(throws: MetadataCreatorPlanError.self) {
            try MetadataWorkflowPreview.prepare([(input[0].image, unrequested)], operations: [adjust])
        }
        #expect(throws: MetadataCreatorPlanError.self) {
            try MetadataWorkflowPreview.prepare(input + input, operations: [adjust])
        }
        #expect(throws: (any Error).self) {
            try MetadataWorkflowPreview.prepare(input, operations: [
                MetadataOperation(tag: .titleDefault, action: .setText("temporary")),
                MetadataOperation(tag: .captureDate, action: .setText("invalid"))])
        }
        #expect(input[0].image.creatorDraft == nil)
        try Data("changed".utf8).write(to: input[0].snapshot.url)
        #expect(throws: MetadataCreatorPlanError.self) { try MetadataWorkflowPreview.prepare(input, operations: [adjust]) }
    }
}
