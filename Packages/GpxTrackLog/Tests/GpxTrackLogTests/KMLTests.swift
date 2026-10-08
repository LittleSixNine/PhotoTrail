import Foundation
import Testing
@testable import GpxTrackLog

struct KMLTests {
    private func document(_ geometry: String) -> String {
        """
        <kml xmlns="http://www.opengis.net/kml/2.2" xmlns:g="http://www.google.com/kml/ext/2.2">
        <Document><Folder><Placemark>\(geometry)</Placemark></Folder></Document></kml>
        """
    }

    private func parse(_ geometry: String) throws -> GpxTrackLog {
        .init(sourceURL: URL(filePath: "/synthetic.kml"),
              tracks: try KMLTrackReader(data: Data(document(geometry).utf8)).parse())
    }

    @Test func largeTrackRetainsEveryCoordinateWithoutChangingOrder() throws {
        let count = 16_000
        let geometry = "<g:Track>" + (0..<count).map { "<g:coord>\(120 + Double($0) / 100_000) 30 0</g:coord>" }.joined() + "</g:Track>"
        let log = try parse(geometry)
        let points = try #require(log.tracks.first?.segments.first?.points)
        #expect(points.count == count)
        #expect(points.first?.lon == 120)
        #expect(points.last?.lon == 120 + Double(count - 1) / 100_000)
        #expect(points.allSatisfy { !$0.hasRecordedTime })
    }

    @Test func timedTrackRetainsPrecisionAndReusesMatching() throws {
        let log = try parse("""
        <g:Track><altitudeMode>absolute</altitudeMode>
        <when>2026-10-04T08:00:00.125+08:00</when><when>2026-10-04T00:01:00.125Z</when>
        <g:coord>120 30 10</g:coord><g:coord>122 32 30</g:coord></g:Track>
        """)
        let points = try #require(log.tracks.first?.segments.first?.points)
        #expect(log.hasRecordedTimes)
        #expect(points[1].timeFromEpoch - points[0].timeFromEpoch == 60)
        #expect(points[0].timeFromEpoch.truncatingRemainder(dividingBy: 1) == 0.125)
        guard case .matched(let match) = log.match(imageTime: points[0].timeFromEpoch + 30) else {
            Issue.record("Expected an interpolated KML match"); return
        }
        #expect(match.coordinate.latitude == 31)
        #expect(match.coordinate.longitude == 121)
        #expect(match.elevation == 20)
    }

    @Test func linesRemainDisplayOnlyAndDoNotInventAltitudeOrTimes() throws {
        let log = try parse("""
        <TimeStamp><when>2026-10-04T00:00:00Z</when></TimeStamp>
        <MultiGeometry>
        <LineString><coordinates>120,30,100 121,31,101</coordinates></LineString>
        <LineString><altitudeMode>relativeToGround</altitudeMode><coordinates>122,32,50 123,33,60</coordinates></LineString>
        </MultiGeometry>
        """)
        #expect(!log.hasRecordedTimes)
        #expect(log.tracks[0].segments.map(\.points.count) == [2, 2])
        #expect(log.tracks[0].segments.flatMap(\.points).allSatisfy { $0.ele == nil })
        guard case .unmatched = log.match(imageTime: 0) else {
            Issue.record("A feature timestamp must not become per-point timestamps"); return
        }
    }

    @Test func multiTrackAndMissingCoordinatesKeepGaps() throws {
        let log = try parse("""
        <g:MultiTrack><g:interpolate>1</g:interpolate>
        <g:Track><when>2026-10-04T00:00:00Z</when><when>2026-10-04T00:01:00Z</when>
        <when>2026-10-04T00:02:00Z</when><g:coord>120 30 0</g:coord><g:coord/><g:coord>122 32 0</g:coord></g:Track>
        <g:Track><when>2026-10-04T00:04:00Z</when><g:coord>124 34 0</g:coord></g:Track>
        </g:MultiTrack>
        """)
        #expect(log.tracks[0].segments.map(\.points.count) == [1, 1, 1])
        let first = log.tracks[0].segments[0].points[0].timeFromEpoch
        for delta in [60.0, 180.0] {
            guard case .unmatched = log.match(imageTime: first + delta) else {
                Issue.record("Must not match across missing coordinates or separate tracks"); return
            }
        }
    }

    @Test(arguments: [
        "<g:Track><when>2026-10-04T00:00:00Z</when><g:coord>120 30 0</g:coord><g:coord>121 31 0</g:coord></g:Track>",
        "<g:Track><when>2026-10-04T00:00:00</when><g:coord>120 30 0</g:coord></g:Track>",
        "<LineString><coordinates>120,91 121,30</coordinates></LineString>",
        "<LineString><coordinates>NaN,30 121,30</coordinates></LineString>",
        "<LineString><coordinates>120,30,Infinity</coordinates></LineString>",
        "<LineString><coordinates>120,30 121,30</coordinates>",
        "<NetworkLink><Link><href>https://example.invalid/private.kml</href></Link></NetworkLink>"
    ])
    func rejectsMalformedOrUnusableData(_ geometry: String) {
        #expect(throws: Error.self) { try parse(geometry) }
    }

    @Test func entitiesAreRejected() {
        let xml = """
        <!DOCTYPE kml [<!ENTITY path "120,30 121,31">]>
        <kml><Placemark><LineString><coordinates>&path;</coordinates></LineString></Placemark></kml>
        """
        #expect(throws: Error.self) { try KMLTrackReader(data: Data(xml.utf8)).parse() }
    }

    @Test(arguments: ["doc.kml", "tracks/山路.kml", "track[1]*?.kml"])
    func kmzReadsDocumentWithoutExtractingResources(_ filename: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent(filename)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try document("<LineString><coordinates>120,30 121,31</coordinates></LineString>")
            .write(to: file, atomically: true, encoding: .utf8)
        try Data([0, 1, 2]).write(to: directory.appendingPathComponent("image.jpg"))
        let archive = directory.appendingPathComponent("route.KMZ")
        let zip = Process()
        zip.executableURL = URL(filePath: "/usr/bin/zip")
        zip.currentDirectoryURL = directory
        zip.arguments = ["-q", archive.path, filename, "image.jpg"]
        try zip.run(); zip.waitUntilExit()
        #expect(zip.terminationStatus == 0)
        try FileManager.default.removeItem(at: file)
        let log = try GpxTrackLog(contentsOf: archive)
        #expect(log.sourceURL == archive.standardizedFileURL)
        #expect(log.tracks[0].segments[0].points.count == 2)
        #expect(!log.hasRecordedTimes)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func ambiguousOrCorruptKMZIsRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = directory.appendingPathComponent("bad.kmz")
        try Data("Not a ZIP archive".utf8).write(to: archive)
        #expect(throws: Error.self) { try GpxTrackLog(contentsOf: archive) }
        try FileManager.default.removeItem(at: archive)
        for name in ["one.kml", "two.kml"] {
            try document("<LineString><coordinates>120,30 121,31</coordinates></LineString>")
                .write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let zip = Process()
        zip.executableURL = URL(filePath: "/usr/bin/zip")
        zip.currentDirectoryURL = directory
        zip.arguments = ["-q", archive.path, "one.kml", "two.kml"]
        try zip.run(); zip.waitUntilExit()
        #expect(throws: Error.self) { try GpxTrackLog(contentsOf: archive) }
    }
}
