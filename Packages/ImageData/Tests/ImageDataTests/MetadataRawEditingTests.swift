import Exiftool
import Foundation
import ImageIO
import Metadata
import Testing
@testable import ImageData

struct MetadataRawEditingTests {
    @Test func mixedFormatsSkipUnsupportedFieldsWithoutDroppingSupportedOperations() throws {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let tags: Set<MetadataTag> = [.creator, .exifArtist, .iptcByline]
        let readings = try ["ARW", "CR3", "CRW", "HEIC"].map { ext in
            let url = folder.appendingPathComponent("sample.\(ext)")
            try Data("synthetic capability test".utf8).write(to: url)
            return (image: ImageData(metadata: Metadata(source: .image(url)), name: url.lastPathComponent),
                    snapshot: try MetadataInspectionSnapshot.read(tags, from: url) { _, _ in [:] })
        }
        let operations = [MetadataOperation(tag: .creator, action: .replaceAuthors(["Author"])),
                          MetadataOperation(tag: .exifArtist, action: .setText("Artist"))]
        let plan = try MetadataWorkflowPreview.prepare(readings, operations: operations)
        #expect(plan.items.count == 3)
        #expect(plan.items[0].changes.count == 2)
        #expect(plan.items[1].changes.count == 2)
        #expect(plan.items[2].changes.count == 1)
        #expect(plan.skipped.count == 3)
        #expect(plan.skipReasons.values.allSatisfy { $0 == .unsupportedField })
        #expect(!readings[1].image.supportsMetadataEditing(.iptcByline))
        let iptc = try MetadataWorkflowPreview.prepare([readings[1]], operations: [
            MetadataOperation(tag: .iptcByline, action: .replaceKeywords(["Author"]))])
        #expect(iptc.items.isEmpty && iptc.skipReasons.values.first == .unsupportedField)
        #expect(throws: MetadataCreatorPlanError.self) {
            try MetadataWorkflowPreview.prepare([readings[3], readings[3]], operations: operations)
        }
        let allSkipped = try MetadataWorkflowPreview.prepare([readings[3]], operations: operations)
        #expect(allSkipped.items.isEmpty && allSkipped.skipped.count == 2)
        // Even a skipped source remains part of the frozen batch.
        try Data("changed".utf8).write(to: readings[3].snapshot.url)
        #expect(throws: MetadataCreatorPlanError.self) {
            try MetadataWorkflowPreview.prepare(readings, operations: operations)
        }
    }

    @Test func rawCopiesPreserveInvalidDNGAndRoundTripOptionalRAW() async throws {
        var sources = [try #require(Bundle.module.url(forResource: "262M1559", withExtension: "DNG"))]
        if let path = ProcessInfo.processInfo.environment["PHOTOTRAIL_RAW_TEST_FILE"] {
            sources.append(URL(fileURLWithPath: path))
        }
        for source in sources {
            let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let url = folder.appendingPathComponent("sample." + source.pathExtension)
            let before = try Data(contentsOf: source)
            try before.write(to: url)
            let backup = folder.appendingPathComponent("backup")
            try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
            let tags: Set<MetadataTag> = [.creator, .exifArtist, .rating, .captureDate]
            let snapshot = try MetadataInspectionSnapshot.read(tags, from: url)
            let image = ImageData(metadata: Metadata(source: .image(url)), name: url.lastPathComponent)
            let plan = try MetadataWorkflowPreview.prepare([(image, snapshot)], operations: [
                MetadataOperation(tag: .creator, action: .replaceAuthors(["RAW test 作者"])),
                MetadataOperation(tag: .exifArtist, action: .setText("RAW test Artist")),
                MetadataOperation(tag: .rating, action: .setText("3")),
                MetadataOperation(tag: .captureDate, action: .setText("2024:01:02 03:04:05.123+08:00"))])
            let item = try #require(plan.items.first)
            #expect(!item.sidecar && item.target == url)
            #expect(try Data(contentsOf: url) == before)
            let outcome = await item.save(backup: .folder(backup))
            if source == sources[0] {
                // This fixture has an invalid MakerNotes offset; never suppress the writer's refusal.
                #expect(outcome == .resultUnknown)
                #expect(try Data(contentsOf: url) == before)
                #expect(try Data(contentsOf: backup.appendingPathComponent(url.lastPathComponent)) == before)
                continue
            }
            #expect(outcome == .saved)
            #expect(try Data(contentsOf: backup.appendingPathComponent(url.lastPathComponent)) == before)
            let actual = try Exiftool.helper.metadataTags(tags, from: url)
            #expect(actual[.creator] == .list(["RAW test 作者"]))
            #expect(actual[.exifArtist] == .text("RAW test Artist"))
            #expect(actual[.rating] == .text("3"))
            #expect(actual[.captureDate] == .text("2024:01:02 03:04:05.123+08:00"))
            #expect(!FileManager.default.fileExists(atPath: url.deletingPathExtension().appendingPathExtension("xmp").path))
            let decoded = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
            #expect(CGImageSourceCreateImageAtIndex(decoded, 0, nil) != nil)
            #expect(try Data(contentsOf: source) == before)
            if let output = ProcessInfo.processInfo.environment["PHOTOTRAIL_RAW_TEST_OUTPUT"] {
                let target = URL(fileURLWithPath: output).appendingPathComponent(url.lastPathComponent)
                try FileManager.default.copyItem(at: url, to: target)
            }
        }
    }
}
