import Exiftool
import Foundation
import ImageData
import Metadata
import Testing
import UDF
@testable import PhotoTrail

@MainActor struct MetadataDateBatchTests {
    @Test func defaultSourceIsEXIFAndAutoFallbackRequiresExplicitSelection() throws {
        let (folder, readings) = try MetadataBatchEditingTests().input([[.dateOriginal: .text("2024:02:29 12:34:56")]])
        defer { try? FileManager.default.removeItem(at: folder) }
        var batch = MetadataDateBatch()
        #expect(batch.source == .captureDate)
        #expect(try batch.inspect(readings)[0].missing)
        batch.source = nil
        #expect(try !batch.inspect(readings)[0].missing)
        let preset = try MetadataPreset(name: "EXIF", operations: [MetadataOperation(tag: .dateOriginal, action: .copy(.captureDate))])
        #expect(MetadataDateBatch(preset: preset)?.source == .captureDate)
    }

    @Test func timeZoneLabelsIncludeLocalizedRegionNamesAndKeepExactOffsets() throws {
        #expect(Set(MetadataDateTimeZoneOption.options.map(\.offset)).count == MetadataDateTimeZoneOption.options.count)
        for option in MetadataDateTimeZoneOption.options {
            let zone = try #require(TimeZone(identifier: option.identifier))
            let reference = Date(timeIntervalSince1970: 1767225600)
            let standardOffset = zone.secondsFromGMT(for: reference) - Int(zone.daylightSavingTimeOffset(for: reference))
                + (option.daylight ? 3600 : 0)
            let parsed = try MetadataDate("2026:01:01 00:00:00" + option.offset)
            #expect(parsed.displayTimeZone.secondsFromGMT() == standardOffset)
            for language in AppLanguage.allCases {
                let label = option.label(locale: Locale(identifier: language.rawValue))
                #expect(label.hasPrefix("UTC" + option.offset + " · "))
                #expect(label.count > ("UTC" + option.offset + " · ").count)
            }
        }
        let china = try #require(MetadataDateTimeZoneOption.options.first { $0.offset == "+08:00" })
        #expect(china.label(locale: Locale(identifier: "zh-Hans")).contains("中国"))
    }

    @Test func fallbackMissingAndConflictArePerPhotoAndPreservePrecision() throws {
        let date = "2024:02:29 12:34:56.123456789+08:00"
        let other = "2023:01:02 03:04:05"
        let (folder, readings) = try MetadataBatchEditingTests().input([
            [.captureDate: .text(date)], [.dateOriginal: .text(other)], [:],
            [.captureDate: .text(date), .dateOriginal: .text(other)]])
        defer { try? FileManager.default.removeItem(at: folder) }
        var batch = MetadataDateBatch(); batch.source = nil
        var rows = try batch.inspect(readings)
        #expect(rows[0].candidates.first?.tag == .captureDate)
        #expect(rows[1].candidates.first?.tag == .dateOriginal)
        #expect(rows[2].missing)
        #expect(rows[3].conflict)
        #expect(throws: Error.self) { try batch.prepare(readings) }
        batch.sourceOverrides[readings[3].image.id] = .dateOriginal
        rows = try batch.inspect(readings)
        #expect(!rows[3].conflict)
        let plan = try batch.prepare(readings)
        #expect(plan.items.count == 3)
        #expect(plan.items[0].changes[.dateOriginal] == .set(.text(date)))
        #expect(plan.items[1].changes[.captureDate] == .set(.text(other)))
        #expect(plan.items[2].changes[.captureDate] == .set(.text(other)))
        #expect(plan.items.allSatisfy { $0.changes[.fileCreateDate] == nil && $0.changes[.dateModified] == nil })
        #expect(readings.allSatisfy { $0.image.creatorDraft == nil })
        batch.missingTime = other
        #expect(try batch.prepare(readings).items.count == 4)
    }

    @Test func missingZoneSkipsOnlyIPTCTimeAndExplicitZonePreservesRecordedOffset() throws {
        let (folder, readings) = try MetadataBatchEditingTests().input([
            [.captureDate: .text("2024:02:29 12:34:56.123456789")],
            [.captureDate: .text("2024:02:29 12:34:56.123456789-05:00")]])
        defer { try? FileManager.default.removeItem(at: folder) }
        var batch = MetadataDateBatch()
        batch.targets.insert(.iptcTimeCreated)
        let rows = try batch.inspect(readings)
        #expect(rows[0].needsTimeZone)
        #expect(!rows[1].needsTimeZone)
        #expect(!rows[0].operations.contains { $0.tag == .iptcTimeCreated })
        #expect(rows[0].operations.contains { $0.tag == .dateOriginal })
        batch.offset = "+08:00"
        let zoned = try batch.inspect(readings)
        #expect(!zoned[0].needsTimeZone)
        #expect(zoned[0].operations.first?.action == .setText("2024:02:29 12:34:56.123456789+08:00"))
        #expect(zoned[1].operations.first?.action == .setText("2024:02:29 12:34:56.123456789-05:00"))
    }

    @Test func sameAndShiftHandleMissingAndInvalidInputBeforeApplying() throws {
        let (folder, readings) = try MetadataBatchEditingTests().input([
            [.captureDate: .text("2024:02:29 23:59:59.987654321")], [:]])
        defer { try? FileManager.default.removeItem(at: folder) }
        var batch = MetadataDateBatch()
        batch.mode = .shift; batch.shiftSeconds = 1
        let shifted = try batch.prepare(readings)
        #expect(shifted.items.count == 1)
        #expect(shifted.items[0].changes[.captureDate] == .set(.text("2024:03:01 00:00:00.987654321")))
        batch.mode = .same; batch.specifiedTime = "2026-11-03 11:22:33"
        #expect(try batch.prepare(readings).items.count == 2)
        batch.specifiedTime = "2026:02:30 00:00:00"
        #expect(throws: Error.self) { try batch.prepare(readings) }
        batch.mode = .shift; batch.shiftSeconds = Int.max
        #expect(throws: Error.self) { try batch.prepare([readings[1]]) }
        batch.shiftSeconds = 1; batch.offset = "+14:30"
        #expect(throws: Error.self) { try batch.prepare([readings[1]]) }
    }

    @Test func presetRoutingPreservesExplicitTargetsAndLeavesOtherWorkflowsAlone() throws {
        let preset = try MetadataPreset(name: "custom", operations: [
            MetadataOperation(tag: .dateModified, action: .copy(.captureDate)),
            MetadataOperation(tag: .iptcTimeCreated, action: .copy(.captureDate))])
        let batch = try #require(MetadataDateBatch(preset: preset))
        #expect(batch.targets == [.captureDate, .dateModified, .iptcTimeCreated])
        #expect(MetadataDateBatch(preset: try MetadataPreset(name: "mixed", operations: preset.operations + [
            MetadataOperation(tag: .creator, action: .replaceAuthors(["A"]))])) == nil)
    }

    @Test func applyIsAtomicUndoableAndRejectsChangedMissingSource() async throws {
        let (folder, readings) = try MetadataBatchEditingTests().input([
            [.dateOriginal: .text("2024:02:29 12:34:56.123456789")], [:]])
        defer { try? FileManager.default.removeItem(at: folder) }
        var state = PhotoTrailState(); state.imageData = readings.map(\.image); state.selection = Set(readings.map(\.image.id))
        let store = Store(initialState: state, reduce: PhotoTrailReducer(), undoEnabled: true)
        let application = MetadataDraftApplication()
        var batch = MetadataDateBatch(); batch.source = nil; batch.targets.insert(.iptcTimeCreated)
        application.apply(readings: readings, operations: [], dateBatch: batch, store: store)
        while application.busy { try await Task.sleep(for: .milliseconds(5)) }
        #expect(application.result?.items.count == 1)
        #expect(store.imageData[0].creatorDraft?.changes[.captureDate] == .set(.text("2024:02:29 12:34:56.123456789")))
        #expect(store.imageData[0].creatorDraft?.changes[.iptcTimeCreated] == nil)
        #expect(store.imageData[1].creatorDraft == nil)
        application.undo(in: store)
        #expect(store.imageData.allSatisfy { $0.creatorDraft == nil })
        try Data("source changed".utf8).write(to: readings[1].snapshot.url)
        #expect(throws: Error.self) { try batch.prepare(readings) }
        #expect(store.imageData.allSatisfy { $0.creatorDraft == nil })
    }
    @Test func inlinePasteCompletesValidAndSameValuesButKeepsInvalidInput() async throws {
        let (folder, readings) = try MetadataBatchEditingTests().input([[.dateOriginal: .text("2024:02:29 12:34:56")]])
        defer { try? FileManager.default.removeItem(at: folder) }
        var state = PhotoTrailState(); state.imageData = readings.map(\.image); state.selection = Set(readings.map(\.image.id))
        let store = Store(initialState: state, reduce: PhotoTrailReducer(), undoEnabled: true)
        let invalid = MetadataBatchEditSession(readings: readings, tags: [.dateOriginal], inline: true)
        #expect(await invalid.pasteInline("invalid", in: store) == false)
        #expect(invalid.fields[0].input == "invalid" && invalid.hasInput)
        #expect(store.imageData[0].creatorDraft == nil)
        #expect(await invalid.pasteInline("2024:02:29 12:34:56.123456789", in: store))
        #expect(!invalid.hasInput)
        #expect(store.imageData[0].creatorDraft?.changes[.dateOriginal] == .set(.text("2024:02:29 12:34:56.123456789")))
        store.undo()
        let same = MetadataBatchEditSession(readings: readings, tags: [.dateOriginal], inline: true)
        #expect(await same.pasteInline("2024:02:29 12:34:56", in: store))
        #expect(!same.hasInput)
        #expect(store.imageData[0].creatorDraft == nil)
    }

    @Test func realCopySavesZonedIPTCTimeWithBackupAndReadback() async throws {
        let source = try #require(PhotoTrailState(forPreview: true).imageData.compactMap { image -> URL? in
            guard case .image(let url) = image.metadata.source, url.pathExtension.lowercased() == "jpg" else { return nil }
            return url
        }.first)
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("sample.jpg")
        let backup = folder.appendingPathComponent("backup")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: url)
        let before = try Data(contentsOf: url)
        let image = ImageData(metadata: Metadata(source: .image(url)), name: url.lastPathComponent)
        let reading = (image: image, snapshot: try MetadataInspectionSnapshot.read(Set(MetadataTag.allCases), from: url))
        var batch = MetadataDateBatch(); batch.mode = .same
        batch.specifiedTime = "2024:02:29 23:59:59"; batch.offset = "+08:00"
        batch.targets.formUnion([.iptcDateCreated, .iptcTimeCreated])
        let item = try #require(batch.prepare([reading]).items.first)
        #expect(item.changes[.iptcTimeCreated] == .set(.text("23:59:59+08:00")))
        #expect(await item.save(backup: .folder(backup)) == .saved)
        let actual = try MetadataInspectionSnapshot.read(batch.targets, from: url)
        #expect(actual.values[.captureDate] == .text("2024:02:29 23:59:59+08:00"))
        #expect(actual.values[.iptcTimeCreated] == .text("23:59:59+08:00"))
        #expect(try Data(contentsOf: backup.appendingPathComponent(url.lastPathComponent)) == before)
    }

}
