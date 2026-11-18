import Foundation
import Metadata
import Testing
@testable import Exiftool

extension MetadataTagTests {
    @Test func exFATReadbackAcceptsOnlyExpectedTruncation() {
        let requested = MetadataTagValue.text("2026:11:18 15:02:31.486+08:00")
        let wholeSecond = MetadataTagValue.text("2026:11:18 15:02:31.000+08:00")
        let centisecond = MetadataTagValue.text("2026:11:18 15:02:31.480+08:00")
        #expect(MetadataFileTime.matchesExFAT(wholeSecond, requested, tag: .fileCreateDate))
        #expect(MetadataFileTime.matchesExFAT(centisecond, requested, tag: .fileModifyDate))
        #expect(!MetadataFileTime.matchesExFAT(wholeSecond, requested, tag: .fileModifyDate))
        #expect(!MetadataFileTime.matchesExFAT(.text("2026:11:18 15:02:31.490+08:00"), requested, tag: .fileModifyDate))
        #expect(!MetadataFileTime.matchesExFAT(.text("2026:11:18 15:02:32+08:00"), requested, tag: .fileCreateDate))
        #expect(!MetadataFileTime.matchesExFAT(nil, requested, tag: .fileCreateDate))
        #expect(!MetadataTag.fileCreateDate.matches(wholeSecond, requested))
        #expect(!MetadataTag.fileModifyDate.matches(centisecond, requested))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["PHOTOTRAIL_EXFAT_TEST_DIRECTORY"] != nil))
    func fileTimesAndGPSOnCard() throws {
        let env = ProcessInfo.processInfo.environment
        let path = try #require(env["PHOTOTRAIL_EXFAT_TEST_DIRECTORY"])
        let volumeFolder = URL(fileURLWithPath: path, isDirectory: true)
        try #require(MetadataFileTime.isExFAT(volumeFolder))
        let fixture = try #require(env["PHOTOTRAIL_EXFAT_TEST_FIXTURE"].map { URL(fileURLWithPath: $0) }
            ?? Bundle.module.url(forResource: "alldata", withExtension: "jpg"))
        let manager = FileManager.default
        let copyFolder = volumeFolder.appending(component: UUID().uuidString)
        try manager.createDirectory(at: copyFolder, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: copyFolder) }
        let target = copyFolder.appending(component: "test.jpg")
        try manager.copyItem(at: fixture, to: target)
        let work = try makeTestFolder()
        defer { try? manager.removeItem(at: work) }
        let image = work.appending(component: target.lastPathComponent)
        try manager.createSymbolicLink(at: image, withDestinationURL: target)

        let date = "2026:11:18 15:02:31.486+08:00"
        let modified = "2026:11:18 15:06:09.873+08:00"
        var map = Metadata(source: .image(image))
        map.location = .init(latitude: 12.34, longitude: -56.78)
        map.gpsMapDatum = "WGS-84"
        map.gpsProcessingMethod = "MANUAL"
        let changes: [MetadataTag: MetadataTagChange] = [
            .fileCreateDate: .set(.text(date)),
            .fileModifyDate: .set(.text(modified)),
            .captureDate: .set(.text(date))
        ]
        let pixels = try #require(try textValue("ImageDataMD5", from: target))
        let saved = try Exiftool.helper.update(image: image, changes: changes, mapMetadata: map)
        let actual = try Exiftool.helper.metadataTags(Set(changes.keys), from: target)
        #expect(saved == actual)
        #expect(actual[.captureDate] == .text(date))
        print("exFAT creation time: \(String(describing: actual[.fileCreateDate]))")
        print("exFAT modification time: \(String(describing: actual[.fileModifyDate]))")
        try Exiftool.helper.verifyMapMetadata(map, in: target)
        #expect(try textValue("ImageDataMD5", from: target) == pixels)
    }
}
