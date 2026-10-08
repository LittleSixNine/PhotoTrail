import Exiftool
import Foundation
import Metadata
import Testing
@testable import ImageData

struct MetadataWorkflowSaveTests {
    @Test func customPresetCopiesEachCamerasModelIntoTitleAndUsesOrderedResults() async throws {
        let folder = URL.temporaryDirectory.appending(component: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let fixture = try #require(Bundle.module.url(forResource: "alldata", withExtension: "jpg"))
        let models = ["Camera A", "Camera B"]
        let tags: Set<MetadataTag> = [.exifModel, .titleDefault, .descriptionDefault]
        var readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)] = []
        for (index, model) in models.enumerated() {
            let url = folder.appending(component: "preset-\(index).jpg")
            try FileManager.default.copyItem(at: fixture, to: url)
            _ = try Exiftool.helper.update(image: url, changes: [.exifModel: .set(.text(model))])
            readings.append((ImageData(metadata: Metadata(source: .image(url)), name: url.lastPathComponent),
                             try MetadataInspectionSnapshot.read(tags, from: url)))
        }
        let configured = try MetadataPreset(name: "Camera as title", operations: [
            MetadataOperation(tag: .titleDefault, action: .copy(.exifModel)),
            MetadataOperation(tag: .titleDefault, action: .appendText(" · photo")),
            MetadataOperation(tag: .descriptionDefault, action: .copy(.titleDefault))])
        let imported = try MetadataPreset.decode(configured.encode())
        let before = try readings.map { try Data(contentsOf: $0.snapshot.url) }
        let preview = try MetadataWorkflowPreview.prepare(readings, operations: imported.operations)
        #expect(try readings.map { try Data(contentsOf: $0.snapshot.url) } == before)
        for (index, item) in preview.items.enumerated() {
            #expect(await item.save(backup: .disabled) == .saved)
            let values = try Exiftool.helper.metadataTags(tags, from: item.target)
            #expect(values[.titleDefault] == .text(models[index] + " · photo"))
            #expect(values[.descriptionDefault] == values[.titleDefault])
            #expect(values[.exifModel] == .text(models[index]))
        }
    }

    @Test func shootingDateCopiesToFileAndIPTCTimesThroughSandboxSave() async throws {
        let folder = URL.temporaryDirectory.appending(component: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let fixture = try #require(Bundle.module.url(forResource: "alldata", withExtension: "jpg"))
        let url = folder.appending(component: "copy-times.jpg")
        try FileManager.default.copyItem(at: fixture, to: url)
        let source = "2024:02:29 23:59:59.123456+08:00"
        _ = try Exiftool.helper.update(image: url, changes: [.captureDate: .set(.text(source))])
        let targets: [MetadataTag] = [.fileCreateDate, .fileModifyDate, .iptcDateCreated, .iptcTimeCreated, .dateModified]
        let tags = Set(targets + [.captureDate])
        let image = ImageData(metadata: Metadata(source: .image(url)), name: url.lastPathComponent)
        let reading = (image: image, snapshot: try MetadataInspectionSnapshot.read(tags, from: url))
        let before = try Data(contentsOf: url)
        let preview = try MetadataWorkflowPreview.prepare([reading], operations: targets.map {
            MetadataOperation(tag: $0, action: .copy(.captureDate))
        })
        #expect(try Data(contentsOf: url) == before)
        let item = try #require(preview.items.first)
        let backup = folder.appending(component: "backup", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        #expect(await item.save(backup: .folder(backup)) == .saved)
        #expect(try Data(contentsOf: backup.appending(component: url.lastPathComponent)) == before)
        let actual = try Exiftool.helper.metadataTags(tags, from: url)
        #expect(MetadataTag.fileCreateDate.matches(actual[.fileCreateDate], .text(source)))
        #expect(MetadataTag.fileModifyDate.matches(actual[.fileModifyDate], .text(source)))
        #expect(actual[.iptcDateCreated] == .text("2024:02:29"))
        #expect(actual[.iptcTimeCreated] == .text("23:59:59+08:00"))
        #expect(actual[.captureDate] == .text(source))
        #expect(actual[.dateModified] == .text(source))
    }

    @Test func copyCreateDateToMultipleFieldsPreservesEachPhotosPrecisionAndSkipsMissingSource() async throws {
        let folder = URL.temporaryDirectory.appending(component: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let fixture = try #require(Bundle.module.url(forResource: "alldata", withExtension: "jpg"))
        let targets: [MetadataTag] = [.captureDate, .exifModifyDate, .sidecarDate, .dateOriginal, .dateDigitized, .dateModified]
        let tags = Set(targets + [.exifCreateDate, .titleDefault])
        let sourceDates: [String?] = ["2024:02:29 23:59:59.123456+08:00", "2023:12:31 01:02:03", "2022:01:01 00:00:00", nil]
        let oldDate = "2000:01:02 03:04:05"
        var readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)] = []
        var originals: [Data] = []
        for (index, date) in sourceDates.enumerated() {
            let url = folder.appending(component: "date-\(index).jpg")
            try FileManager.default.copyItem(at: fixture, to: url)
            var changes = Dictionary(uniqueKeysWithValues: targets.map { ($0, MetadataTagChange.set(.text(oldDate))) })
            changes[.exifCreateDate] = date.map { .set(.text($0)) } ?? .remove
            _ = try Exiftool.helper.update(image: url, changes: changes)
            originals.append(try Data(contentsOf: url))
            readings.append((ImageData(metadata: Metadata(source: .image(url)), name: url.lastPathComponent),
                             try MetadataInspectionSnapshot.read(tags, from: url)))
        }
        // A pending source edit is the effective value; copying must not discard unrelated drafts.
        let pendingDate = "2025:06:07 08:09:10.50-03:30"
        let pending = try MetadataWorkflowPreview.prepare([readings[2]], operations: [
            MetadataOperation(tag: .exifCreateDate, action: .setText(pendingDate)),
            MetadataOperation(tag: .titleDefault, action: .setText("Keep this draft"))])
        readings[2].image.applyMetadataDraft(try #require(pending.items.first))
        let plan = try MetadataWorkflowPreview.prepare(readings, operations: targets.map {
            MetadataOperation(tag: $0, action: .copy(.exifCreateDate))
        })
        #expect(plan.items.count == 3)
        #expect(plan.skipped.count == targets.count)
        #expect(plan.skipped.allSatisfy { $0.contains("date-3.jpg") })
        for (index, reading) in readings.enumerated() {
            #expect(try Data(contentsOf: reading.snapshot.url) == originals[index])
        }
        let backup = folder.appending(component: "backup", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        for (index, item) in plan.items.enumerated() {
            let expected = index == 2 ? pendingDate : sourceDates[index]!
            for target in targets { #expect(item.changes[target] == .set(.text(expected))) }
            #expect(await item.save(backup: .folder(backup)) == .saved)
            #expect(try Data(contentsOf: backup.appending(component: item.target.lastPathComponent)) == originals[index])
            let values = try Exiftool.helper.metadataTags(tags, from: item.target)
            for target in targets + [.exifCreateDate] { #expect(values[target] == .text(expected)) }
            if index == 2 { #expect(values[.titleDefault] == .text("Keep this draft")) }
        }
        #expect(try Data(contentsOf: readings[3].snapshot.url) == originals[3])
        #expect(readings[3].snapshot.values[.captureDate] == .text(oldDate))
    }

    @Test func orderedPresetsDatesAndCSVUseOneVerifiedSidecarSave() async throws {
        let folder = URL.temporaryDirectory.appending(component: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let dngFixture = try #require(Bundle.module.url(forResource: "262M1559", withExtension: "DNG"))
        let xmpFixture = try #require(Bundle.module.url(forResource: "262M1559", withExtension: "xmp"))
        var readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)] = []
        let tags = Set(MetadataTag.allCases)
        var originals: [Data] = []
        for name in ["third", "first", "second"] {
            let image = folder.appending(component: name + ".DNG"), xmp = folder.appending(component: name + ".xmp")
            try FileManager.default.copyItem(at: dngFixture, to: image)
            try FileManager.default.copyItem(at: xmpFixture, to: xmp)
            originals.append(try Data(contentsOf: xmp))
            readings.append((ImageData(metadata: Metadata(source: .xmp(image)), name: image.lastPathComponent),
                             try MetadataInspectionSnapshot.read(tags, from: xmp)))
        }
        let byName = readings.map { reading in
            (image: ImageData(metadata: reading.image.metadata, name: reading.image.name == "second.DNG" ? "bad-name.DNG" : "20240229_scan.DNG"), snapshot: reading.snapshot)
        }
        let filenamePlan = try MetadataWorkflowPreview.prepare(byName, operations: [
            MetadataOperation(tag: .sidecarDate, action: .filenameDate(pattern: "^(\\d{4})(\\d{2})(\\d{2})", template: "$1:$2:$3 12:00:00"))])
        #expect(filenamePlan.items.count == 2 && filenamePlan.skipped.count == 1)
        #expect(filenamePlan.items.allSatisfy { $0.captureDateValue == "2024:02:29 12:00:00" })
        let operations = [MetadataOperation(tag: .dateOriginal, action: .sequence(start: "2024:02:29 23:59:59.125+08:00", stepSeconds: 2)),
                          MetadataOperation(tag: .dateDigitized, action: .copy(.dateOriginal)),
                          MetadataOperation(tag: .sidecarDate, action: .copy(.dateOriginal)),
                          MetadataOperation(tag: .dateOriginal, action: .offsetDate(years: 0, months: 0, days: 0,
                                                                                   hours: -2, minutes: 0, seconds: 0)),
                          MetadataOperation(tag: .make, action: .setText("Olympus")),
                          MetadataOperation(tag: .model, action: .setText("35EC")),
                          MetadataOperation(tag: .lens, action: .setText("42 mm f/2.8")),
                          MetadataOperation(tag: .rightsDefault, action: .setText("© 六九")),
                          MetadataOperation(tag: .subject, action: .replaceKeywords(["Gold 400"])),
                          MetadataOperation(tag: .subject, action: .appendKeywords(["Gold 400", "扫描"]))]
        let preset = try MetadataPreset.decode(MetadataPreset(name: "胶片补录与时间同步", operations: operations).encode())
        let plan = try MetadataWorkflowPreview.prepare(readings, operations: preset.operations)
        let backup = folder.appending(component: "backup", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        for (index, item) in plan.items.enumerated() {
            #expect(try Data(contentsOf: item.target) == originals[index])
            #expect(await item.save(backup: .folder(backup)) == .saved)
            #expect(try Data(contentsOf: backup.appending(component: item.target.lastPathComponent)) == originals[index])
            #expect(try Data(contentsOf: item.imageURL) == Data(contentsOf: dngFixture))
            let values = try Exiftool.helper.metadataTags(tags, from: item.target)
            #expect(Exiftool.helper.metadata(from: item.target, primaryURL: item.imageURL).dateTimeCreated == values[.sidecarDate].flatMap { if case .text(let value) = $0 { value } else { nil } })
            #expect(values[.dateOriginal] == .text(try MetadataDate.sequence(start: "2024:02:29 21:59:59.125+08:00", stepSeconds: 2, count: 3)[index]))
            #expect(values[.dateDigitized] == .text(try MetadataDate.sequence(start: "2024:02:29 23:59:59.125+08:00", stepSeconds: 2, count: 3)[index]))
            #expect(values[.subject] == .list(["Gold 400", "扫描"]))
            let fresh = try MetadataInspectionSnapshot.read(tags, from: item.target)
            let repeated = try MetadataWorkflowPreview.prepare([(readings[index].image, fresh)], operations: [operations.last!])
            #expect(repeated.items.isEmpty)
            let record = try MetadataCSVRecord(url: item.target, relativePath: item.target.lastPathComponent, values: values)
            let csv = try MetadataCSV.export([record], tags: MetadataTag.allCases)
            let imported = try MetadataCSV.load(csv, authorized: [record])
            let roundTrip = try MetadataWorkflowPreview.prepare([(readings[index].image, fresh)], operations: imported.operations[record.id]!)
            #expect(roundTrip.items.isEmpty)
        }
        #expect(throws: MetadataCreatorPlanError.self) { try MetadataWorkflowPreview.prepare(readings, operations: operations) }
        #expect(throws: MetadataDateError.self) {
            let fresh = try MetadataInspectionSnapshot.read(tags, from: plan.items[0].target)
            try MetadataWorkflowPreview.prepare([(readings[0].image, fresh)], operations: [MetadataOperation(tag: .dateModified, action: .shiftDate(seconds: 1)),
                                                                                           MetadataOperation(tag: .dateModified, action: .remove),
                                                                                           MetadataOperation(tag: .dateModified, action: .shiftDate(seconds: 1))])
        }
    }
}
