import Coords
import Foundation
@testable import GeoTag
import ImageData
import Metadata
import Testing

struct PhotoGPXDocumentTests {
    @Test func exportsSortedUTCPointsAndSplitsLongGaps() throws {
        let first = image(name: "A&B.jpg", timestamp: "2026:09:16 08:00:00", latitude: 31, longitude: 121)
        let second = image(name: "later.jpg", timestamp: "2026:09:16 08:10:00", latitude: 32, longitude: 122)
        let document = PhotoGPXDocument(images: [second, first], timeZone: TimeZone(secondsFromGMT: 8 * 3600)!)
        let xml = String(data: document.data, encoding: .utf8)!

        #expect(document.exportedCount == 2)
        #expect(xml.contains("<time>2026-09-16T00:00:00Z</time>"))
        #expect(xml.contains("<name>A&amp;B.jpg</name>"))
        #expect(xml.components(separatedBy: "<trkseg>").count - 1 == 2)
        #expect(xml.range(of: "lat=\"31.00000000\"")!.lowerBound < xml.range(of: "lat=\"32.00000000\"")!.lowerBound)
        #expect(document.suggestedFilename(timeZone: TimeZone(secondsFromGMT: 8 * 3600)!,
                    createdAt: Date(timeIntervalSince1970: 1_789_589_000))
            .hasSuffix("_2点_20260916-0800-0810.gpx"))
    }

    @Test func skipsMissingTimeLocationAndUnknownDatum() {
        var missingTime = Metadata(source: .copy)
        missingTime.location = Coords(latitude: 1, longitude: 2)
        var unknownDatum = Metadata(source: .copy)
        unknownDatum.dateTimeCreated = "2026:09:16 08:00:00"
        unknownDatum.location = Coords(latitude: 1, longitude: 2)
        unknownDatum.gpsMapDatum = "GCJ-02"
        let document = PhotoGPXDocument(images: [ImageData(metadata: missingTime, name: "no-time.jpg"),
                                                 ImageData(metadata: unknownDatum, name: "gcj.jpg")],
                                        timeZone: .current)

        #expect(document.exportedCount == 0)
        #expect(document.skippedCount == 2)
    }

    private func image(name: String, timestamp: String, latitude: Double, longitude: Double) -> ImageData {
        var metadata = Metadata(source: .copy)
        metadata.dateTimeCreated = timestamp
        metadata.location = Coords(latitude: latitude, longitude: longitude)
        metadata.gpsMapDatum = "WGS-84"
        return ImageData(metadata: metadata, name: name)
    }
}
