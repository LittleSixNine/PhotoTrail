import Foundation
import Exiftool
import Metadata
import Testing
@testable import Imagetool

struct ImagetoolTests {
    @Test func structuredRegionSurvivesJPEGReopening() async throws {
        let source = try #require(Bundle.module.url(forResource: "alldata", withExtension: "jpg"))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let copy = folder.appendingPathComponent("region.jpg")
        try FileManager.default.copyItem(at: source, to: copy)
        var metadata = Imagetool.metadata(from: copy)
        metadata.state = "黑龙江省"
        metadata.city = "哈尔滨市"
        metadata.sublocation = "香坊区"
        metadata.country = "中国"
        metadata.countryCode = "CN"
        try await Exiftool.helper.update(image: copy, from: metadata, timeZone: nil)
        let reopened = Imagetool.metadata(from: copy)
        #expect(reopened.state == metadata.state && reopened.city == metadata.city)
        #expect(reopened.sublocation == metadata.sublocation)
        #expect(reopened.country == metadata.country && reopened.countryCode == metadata.countryCode)
        #expect(reopened.location == metadata.location)
    }

    @Test func imageSourceCreateFailure() async throws {
        let url = URL(string: "bad url")!
        let metadata = Imagetool.metadata(from: url)
        #expect(metadata.dateTimeCreated == nil)
        #expect(metadata.location == nil)
    }

    // this test used to fail. It looks like Apple can now handle compressed
    // RAW Fuji files.  I'll need to find another file that fails in order
    // to re-enable this test.

    @Test(.disabled()) func imageSourceNoMetadata() async throws {
        let url = try #require(
            Bundle.module.url(forResource: "nometadata",
                              withExtension: "RAF")
        )
        let metadata = Imagetool.metadata(from: url)
        #expect(metadata.dateTimeCreated == nil)
        #expect(metadata.location == nil)
    }

    @Test func imageWithTimestamp() async throws {
        let url = try #require(
            Bundle.module.url(forResource: "nolocation",
                              withExtension: "jpg")
        )
        let metadata = Imagetool.metadata(from: url)
        #expect(metadata.timestamp == "2026:01:23 09:20:11.831-08:00")
        #expect(metadata.location == nil)
        #expect(metadata.city == nil)
    }

    @Test func imageWithLocation() async throws {
        let url = try #require(
            Bundle.module.url(forResource: "location",
                              withExtension: "jpg")
        )
        let metadata = Imagetool.metadata(from: url)
        #expect(metadata.timestamp == "2025:10:12 09:38:23")
        let location = try #require(metadata.location)
        #expect(location.latitude == 37.837316666666666)
        #expect(location.longitude == -122.47303666666667)
        #expect(metadata.elevation == 31.0)
        #expect(metadata.city == nil)
    }

    @Test func imageWithVoidStatus() async throws {
        let url = try #require(
            Bundle.module.url(forResource: "status",
                              withExtension: "DNG")
        )
        let metadata = Imagetool.metadata(from: url)
        #expect(metadata.timestamp == "2016:04:01 15:54:48")
        #expect(metadata.location == nil)
        #expect(metadata.elevation == nil)
        #expect(metadata.city == nil)
    }

    @Test func imageNoElevation() async throws {
        let url = try #require(
            Bundle.module.url(forResource: "noelevation",
                              withExtension: "jpg")
        )
        let metadata = Imagetool.metadata(from: url)
        #expect(metadata.timestamp == "2016:04:24 12:12:47")
        let location = try #require(metadata.location)
        #expect(location.latitude == 21.27491)
        #expect(location.longitude == -157.82393666666667)
        #expect(metadata.elevation == nil)
        #expect(metadata.city == "Honolulu")
        #expect(metadata.state == "HI")
        #expect(metadata.country == "United States")
        #expect(metadata.countryCode == "US")
    }

    @Test func imageAllData() async throws {
        let url = try #require(
            Bundle.module.url(forResource: "alldata",
                              withExtension: "jpg")
        )
        let metadata = Imagetool.metadata(from: url)
        #expect(metadata.timestamp == "2025:12:07 10:00:51")
        let location = try #require(metadata.location)
        #expect(location.latitude == 37.224048333333336)
        #expect(location.longitude == -122.40566666666666)
        #expect(metadata.elevation == 2.0)
        #expect(metadata.city == "Pescadero")
        #expect(metadata.state == "CA")
        #expect(metadata.country == "United States")
        #expect(metadata.countryCode == "US")
    }

    @Test func imageWithXmp() async throws {
        let url = try #require(
            Bundle.module.url(forResource: "262M1559",
                              withExtension: "DNG"))
        let xmp = try #require(
            Bundle.module.url(forResource: "262M1559",
                              withExtension: "xmp"))
        let metadata = Imagetool.metadata(from: url, xmp: xmp)
        #expect(metadata.dateTimeCreated == "2019:03:11 11:47:20")
        #expect(metadata.location == nil)
        #expect(metadata.elevation == nil)
        #expect(metadata.city == nil)
        #expect(metadata.state == nil)
        #expect(metadata.country == nil)
        #expect(metadata.countryCode == nil)
    }

    @Test func imageThumbnail() async throws {
        let url = try #require(
            Bundle.module.url(forResource: "262M1559",
                              withExtension: "DNG"))
        let thumbnail = Imagetool.imageThumbnail(url: url)
        #expect(thumbnail != nil)
        let bogus = URL(filePath: "/some/file/path.img")
        let noThumbnail = Imagetool.imageThumbnail(url: bogus)
        #expect(noThumbnail == nil)
        let smallImg = try #require(
            Bundle.module.url(forResource: "toosmall",
                              withExtension: "jpg"))
        let small = Imagetool.imageThumbnail(url: smallImg)
        #expect(small != nil)
    }
}
