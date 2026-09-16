import Foundation
import SwiftUI
import Testing

@testable import GpxTrackLog

struct GpxTests {
    let badTrackFile = "BadTrack"
    let noTrackFile = "NoTrack"
    let testTrackFile = "TestTrack"
    let multiSegFile = "MultiSeg"
    let ext = "GPX"

    func testFileURL(fileName: String) throws -> URL {
        let testURL = Bundle.module.url(forResource: fileName,
                                        withExtension: ext)
        let fileURL = try #require(testURL)
        return fileURL
    }

    @Test func gpxParse() async throws {
        let gpxUrl = try testFileURL(fileName: testTrackFile)
        let trackLog = try GpxTrackLog(contentsOf: gpxUrl)
        let tracks = trackLog.tracks.count
        let segments = trackLog.tracks.reduce(0) { $0 + $1.segments.count }
        let points = trackLog.tracks.reduce(0) {
            $0 + $1.segments.reduce(0) { $0 + $1.points.count }
        }
        #expect(tracks == 1)
        #expect(segments == 1)
        #expect(points == 3813)
    }

    @Test func gpxParseMultiSeg() async throws {
        let gpxUrl = try testFileURL(fileName: multiSegFile)
        let trackLog = try GpxTrackLog(contentsOf: gpxUrl)
        let tracks = trackLog.tracks.count
        let segments = trackLog.tracks.reduce(0) { $0 + $1.segments.count }
        let points = trackLog.tracks.reduce(0) {
            $0 + $1.segments.reduce(0) { $0 + $1.points.count }
        }
        #expect(tracks == 1)
        #expect(segments == 29)
        #expect(points == 9999)
    }

    @Test func gpxParseNoTrack() async throws {
        let gpxUrl = try testFileURL(fileName: noTrackFile)
        #expect(throws: Error.self) {
            _ = try GpxTrackLog(contentsOf: gpxUrl)
        }
    }

    @Test func gpxParseBadTrack() async throws {
        let gpxUrl = try testFileURL(fileName: badTrackFile)
        #expect(throws: Error.self) {
            _ = try GpxTrackLog(contentsOf: gpxUrl)
        }
    }

    @Test func gpxSearch() async throws {
        let gpxUrl = try testFileURL(fileName: multiSegFile)
        let trackLog = try GpxTrackLog(contentsOf: gpxUrl)
        let formatter = ISO8601DateFormatter()
        let insideSegment = try #require(formatter.date(from: "2008-04-19T01:20:32Z"))

        // check for point within segment
        let insideInterval = insideSegment.timeIntervalSince1970
        #expect(trackLog.search(imageTime: insideInterval, extendedTime: 1) != nil)

        // check for point after segment
        let afterSegment = try #require(formatter.date(from: "2008-04-18T14:20:00Z"))
        let afterInterval = afterSegment.timeIntervalSince1970
        #expect(trackLog.search(imageTime: afterInterval, extendedTime: 1) == nil)
        #expect(trackLog.search(imageTime: afterInterval, extendedTime: 10) == nil)

        let beforeSegment = try #require(formatter.date(from: "2008-04-18T15:10:00Z"))
        let beforeInterval = beforeSegment.timeIntervalSince1970
        #expect(trackLog.search(imageTime: beforeInterval, extendedTime: 1) == nil)
        #expect(trackLog.search(imageTime: beforeInterval, extendedTime: 10) == nil)
    }

    @Test func conservativeInterpolationAndBoundaries() {
        let log = GpxTrackLog(sourceURL: URL(filePath: "/synthetic.gpx"), tracks: [
            .init(segments: [.init(points: [
                .init(hasRecordedTime: true, lat: 10, lon: 20, ele: 100, timeFromEpoch: 0),
                .init(hasRecordedTime: true, lat: 20, lon: 40, ele: 200, timeFromEpoch: 60)
            ])])
        ])
        guard case .matched(let midpoint) = log.match(imageTime: 30, maximumGap: 60) else {
            Issue.record("Expected an interpolated match")
            return
        }
        #expect(midpoint.method == .linear)
        #expect(midpoint.coordinate.latitude == 15)
        #expect(midpoint.coordinate.longitude == 30)
        #expect(midpoint.elevation == 150)
        guard case .unmatched = log.match(imageTime: -1, maximumGap: 60) else {
            Issue.record("Matching must not extrapolate before a segment")
            return
        }
        guard case .unmatched = log.match(imageTime: 30, maximumGap: 59) else {
            Issue.record("Matching must not bridge a gap beyond the configured limit")
            return
        }
    }

    @Test func segmentAndTrackConflictsAreAmbiguous() {
        let first = GpxTrackLog.Segment(points: [
            .init(hasRecordedTime: true, lat: 10, lon: 20, timeFromEpoch: 30)
        ])
        let second = GpxTrackLog.Segment(points: [
            .init(hasRecordedTime: true, lat: 30, lon: 40, timeFromEpoch: 30)
        ])
        let log = GpxTrackLog(sourceURL: URL(filePath: "/conflict.gpx"), tracks: [
            .init(segments: [first, second])
        ])
        guard case .ambiguous = log.match(imageTime: 30) else {
            Issue.record("Conflicting locations at one timestamp must not be chosen silently")
            return
        }
    }
}
