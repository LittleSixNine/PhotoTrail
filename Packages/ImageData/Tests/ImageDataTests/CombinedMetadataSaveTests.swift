@testable import Exiftool
import Foundation
import Imagetool
import Metadata
import Testing
@testable import ImageData

struct CombinedMetadataSaveTests {
    @Test func combinedSaveKeepsPixelsOneOriginalBackupAndIndependentDates() async throws {
        let source: URL
        if let path = ProcessInfo.processInfo.environment["PHOTOTRAIL_COMBINED_SAMPLE"] {
            source = URL(fileURLWithPath: path)
            print("Combined save uses private-sample fixture")
        } else {
            source = try #require(Bundle.module.url(forResource: "alldata", withExtension: "jpg"))
        }
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("combined.jpg")
        let original = try Data(contentsOf: source)
        try original.write(to: url, options: .atomic)
        let pixels = try Exiftool.helper.run(["-s3", "-ImageDataMD5", url.path])
        let backup = folder.appendingPathComponent("backup")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        let image = ImageData(metadata: Imagetool.metadata(from: url), name: url.lastPathComponent)
        let date = "2026:10:31 21:40:05.123+08:00"
        let values: [MetadataTag: String] = [
            .captureDate: date, .exifCreateDate: "2020:01:02 03:04:05", .exifModifyDate: "2021:02:03 04:05:06",
            .sidecarDate: "2022:03:04 05:06:07", .dateOriginal: "2023:04:05 06:07:08",
            .dateDigitized: "2024:05:06 07:08:09", .dateModified: "2025:06:07 08:09:10",
            .iptcDateCreated: "2026:10:31", .iptcTimeCreated: "21:40:05+08:00",
            .fileCreateDate: "2020:01:02 03:04:05+08:00", .fileModifyDate: "2024:02:29 23:59:59+08:00",
            .descriptionDefault: "e\u{301}，🌿"]
        let operations = values.map { MetadataOperation(tag: $0.key, action: .setText($0.value)) }
        let snapshot = try MetadataInspectionSnapshot.read(Set(values.keys), from: url)
        let plan = try MetadataWorkflowPreview.prepare([(image, snapshot)], operations: operations)
        let item = try #require(plan.items.first)
        var map = image.metadata
        map.location = .init(latitude: -33.75, longitude: 151.25)
        map.dateTimeCreated = date; map.elevation = -4.25
        map.gpsMapDatum = "WGS-84"; map.gpsProcessingMethod = "MANUAL"
        #expect(await item.save(backup: .folder(backup), mapMetadata: map) == .saved)
        let actual = try Exiftool.helper.metadataTags(Set(values.keys), from: url)
        for (tag, value) in values { #expect(tag.matches(actual[tag], .text(value))) }
        try Exiftool.helper.verifyMapMetadata(map, in: url)
        #expect(try Exiftool.helper.run(["-s3", "-ImageDataMD5", url.path]) == pixels)
        let backups = try FileManager.default.contentsOfDirectory(at: backup, includingPropertiesForKeys: nil)
        #expect(backups.count == 1)
        #expect(try Data(contentsOf: #require(backups.first)) == original)
        #expect(try Data(contentsOf: source) == original)
    }
}
