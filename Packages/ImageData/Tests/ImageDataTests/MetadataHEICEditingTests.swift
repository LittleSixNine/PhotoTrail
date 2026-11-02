@testable import Exiftool
import Foundation
import ImageIO
import Imagetool
import Metadata
import Testing
@testable import ImageData

struct MetadataHEICEditingTests {
    @Test func singleFieldEditAndRemovalKeepOriginalBackup() async throws {
        let source = try #require(Bundle.module.url(forResource: "blank", withExtension: "heic"))
        let original = try Data(contentsOf: source)
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("single.heic")
        try original.write(to: url)
        let backup = folder.appendingPathComponent("backup")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        let image = ImageData(metadata: Imagetool.metadata(from: url), name: url.lastPathComponent)
        let snapshot = try MetadataInspectionSnapshot.read([.creator], from: url)
        let plan = try MetadataCreatorEditPlan.prepare([(image, snapshot)], action: .set(["摄影师 🌿"]))
        let item = try #require(plan.items.first)
        #expect(await item.save(backup: .folder(backup)) == .saved)
        #expect(try Exiftool.helper.metadataTags([.creator], from: url)[.creator] == .list(["摄影师 🌿"]))
        let backups = try FileManager.default.contentsOfDirectory(at: backup, includingPropertiesForKeys: nil)
        #expect(backups.count == 1)
        #expect(try Data(contentsOf: #require(backups.first)) == original)
        let updated = ImageData(metadata: Imagetool.metadata(from: url), name: url.lastPathComponent)
        let removal = try MetadataCreatorEditPlan.prepare(
            [(updated, MetadataInspectionSnapshot.read([.creator], from: url))], action: .remove)
        let removalItem = try #require(removal.items.first)
        #expect(await removalItem.save(backup: .disabled) == .saved)
        #expect(try Exiftool.helper.metadataTags([.creator], from: url)[.creator] == nil)
        #expect(try Data(contentsOf: source) == original)
    }

    @Test func mixedBatchPresetWritesHEICHEIFAndJPEGWithoutChangingPixels() async throws {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let operations = [
            MetadataOperation(tag: .creator, action: .replaceAuthors(["作者 🌿"])),
            MetadataOperation(tag: .rightsDefault, action: .setText("© 2026")),
            MetadataOperation(tag: .subject, action: .appendKeywords(["旅行", "film"])),
            MetadataOperation(tag: .exifArtist, action: .setText("Artist")),
            MetadataOperation(tag: .captureDate, action: .shiftDate(seconds: 3600)),
            MetadataOperation(tag: .dateOriginal, action: .copy(.captureDate)),
            MetadataOperation(tag: .fileModifyDate, action: .setText("2024:02:29 23:59:59+08:00")),
            MetadataOperation(tag: .iptcByline, action: .replaceKeywords(["IPTC author"]))]
        let preset = try MetadataPreset(name: "HEIC batch", operations: operations)
        let restored = try MetadataPreset.decode(preset.encode())
        let tags = Set(operations.map(\.tag))
        var readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)] = []
        var pixels: [URL: Data] = [:]
        var originals: [URL: Data] = [:]
        for ext in ["heic", "HEIF", "jpg"] {
            let resource = ext == "jpg" ? "alldata" : "blank"
            let source = try #require(Bundle.module.url(forResource: resource, withExtension: ext == "jpg" ? "jpg" : "heic"))
            let url = folder.appendingPathComponent("batch.\(ext)")
            try Data(contentsOf: source).write(to: url)
            _ = try Exiftool.helper.update(image: url, changes: [.captureDate: .set(.text("2024:01:02 03:04:05.123+08:00"))])
            originals[url] = try Data(contentsOf: url)
            pixels[url] = try Exiftool.helper.run(["-s3", "-ImageDataMD5", url.path])
            #expect(pixels[url]?.isEmpty == false)
            readings.append((ImageData(metadata: Imagetool.metadata(from: url), name: url.lastPathComponent),
                             try MetadataInspectionSnapshot.read(tags, from: url)))
        }
        let plan = try MetadataWorkflowPreview.prepare(readings, operations: restored.operations)
        #expect(plan.items.count == 3)
        #expect(plan.skipped.count == 2)
        #expect(plan.skipDetails.allSatisfy { $0.tag == .iptcByline && $0.reason == .unsupportedField })
        for item in plan.items {
            let backup = folder.appendingPathComponent("backup-" + item.target.pathExtension)
            try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
            var map = Imagetool.metadata(from: item.target)
            map.location = .init(latitude: -33.75, longitude: 151.25)
            map.elevation = -4.25; map.gpsMapDatum = "WGS-84"; map.gpsProcessingMethod = "MANUAL"
            #expect(await item.save(backup: .folder(backup), mapMetadata: map) == .saved)
            let values = try Exiftool.helper.metadataTags(tags, from: item.target)
            #expect(values[.creator] == .list(["作者 🌿"]))
            #expect(values[.rightsDefault] == .text("© 2026"))
            #expect(values[.exifArtist] == .text("Artist"))
            #expect(values[.captureDate] == .text("2024:01:02 04:04:05.123+08:00"))
            #expect(values[.dateOriginal] == values[.captureDate])
            if case .list(let words) = values[.subject] { #expect(words.contains("旅行") && words.contains("film")) }
            else { Issue.record("Missing keywords") }
            if item.target.pathExtension != "jpg" { #expect(values[.iptcByline] == nil) }
            try Exiftool.helper.verifyMapMetadata(map, in: item.target)
            #expect(try Exiftool.helper.run(["-s3", "-ImageDataMD5", item.target.path]) == pixels[item.target])
            let decoded = try #require(CGImageSourceCreateWithURL(item.target as CFURL, nil))
            #expect(CGImageSourceCreateImageAtIndex(decoded, 0, nil) != nil)
            let backups = try FileManager.default.contentsOfDirectory(at: backup, includingPropertiesForKeys: nil)
            #expect(backups.count == 1)
            #expect(try Data(contentsOf: #require(backups.first)) == originals[item.target])
            #expect(!FileManager.default.fileExists(atPath: item.target.deletingPathExtension().appendingPathExtension("xmp").path))
        }
    }
}
