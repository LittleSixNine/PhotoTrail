import Foundation
import Testing
@testable import GpxTrackLog

struct TrackAdjustmentTests {
    private func log(latitude: Double = 0, longitude: Double = 179.999) -> GpxTrackLog {
        GpxTrackLog(sourceURL: URL(fileURLWithPath: "/tmp/adjust.gpx"), tracks: [
            .init(segments: [.init(points: [
                .init(hasRecordedTime: true, lat: latitude, lon: longitude, ele: 12, timeFromEpoch: 1_700_000_000.125),
                .init(hasRecordedTime: false, lat: latitude, lon: longitude, ele: nil, timeFromEpoch: 0)
            ])])
        ])
    }

    @Test func timeShiftPreservesMissingTimeAndElevation() throws {
        let source = log()
        let moved = try source.adjusted(seconds: -3_600.5, east: 0, north: 0)
        let points = moved.tracks[0].segments[0].points
        #expect(points[0].timeFromEpoch == 1_699_996_399.625)
        #expect(points[0].lat == 0 && points[0].lon == 179.999 && points[0].ele == 12)
        #expect(!points[1].hasRecordedTime && points[1].timeFromEpoch == 0)
        #expect(try source.adjusted(seconds: -3_600.5, east: 0, north: 0) == moved)
    }

    @Test func cardinalDisplacementAndDateline() throws {
        let north = try log(longitude: 0).adjusted(seconds: 0, east: 0, north: 100)
        #expect(abs(north.tracks[0].segments[0].points[0].lat - 0.000899320363724538) < 1e-12)
        let east = try log().adjusted(seconds: 0, east: 1_000, north: 0)
        #expect(east.tracks[0].segments[0].points[0].lon < -179.99)
        #expect(east.tracks[0].segments[0].points[0].timeFromEpoch == 1_700_000_000.125)
        #expect(throws: TrackAdjustmentError.self) { try log(latitude: 85).adjusted(seconds: 0, east: 1, north: 0) }
        #expect(throws: TrackAdjustmentError.self) { try log().adjusted(seconds: .nan, east: 0, north: 0) }
        #expect(throws: TrackAdjustmentError.self) { try log().adjusted(seconds: 0, east: 100_001, north: 0) }
    }

    @Test func exportedGPXRetainsFractionsAndUntimedPoints() throws {
        let source = try log().adjusted(seconds: 1.5, east: -12, north: 23)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gpx")
        defer { try? FileManager.default.removeItem(at: url) }
        try source.gpxData().write(to: url)
        let read = try GpxTrackLog(contentsOf: url)
        #expect(read.tracks == source.tracks)
    }
}
