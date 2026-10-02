import Exiftool
import Foundation
import Metadata
import Testing
@testable import ImageData

struct MetadataWorkflowSaveTests {
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
