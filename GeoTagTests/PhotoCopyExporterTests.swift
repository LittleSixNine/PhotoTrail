import Coords
import Foundation
@testable import GeoTag
import ImageData
import Imagetool
import Testing

struct PhotoCopyExporterTests {
    @Test func writesVerifiedCopyReportWithoutChangingSource() async throws {
        let source = try #require(Bundle.main.url(forResource: "P1000658", withExtension: "JPG"))
        let sourceData = try Data(contentsOf: source)
        var image = ImageData(from: source)
        image.metadata.location = Coords(latitude: 42.123456, longitude: 24.654321)
        image.metadata.gpsMapDatum = "WGS-84"
        let destination = URL.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }

        let report = try await PhotoCopyExporter.export(images: [image], destination: destination,
                                                        timeZone: .current)

        #expect(report.written == 1)
        #expect(report.failed == 0)
        #expect(try Data(contentsOf: source) == sourceData)
        let outputPath = try #require(report.results.first?.output)
        let output = URL(fileURLWithPath: outputPath)
        let saved = Imagetool.metadata(from: output)
        #expect(abs((saved.location?.latitude ?? 0) - 42.123456) < 0.000001)
        #expect(FileManager.default.fileExists(atPath:
            URL(fileURLWithPath: report.outputDirectory).appendingPathComponent("geotag-report.json").path))
    }
}
