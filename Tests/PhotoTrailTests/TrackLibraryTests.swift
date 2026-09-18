import Coords
import Foundation
import GpxTrackLog
import Testing
@testable import PhotoTrail

@MainActor
struct TrackLibraryTests {
    private func fixture(_ directory: URL, name: String = "test.gpx", changed: Bool = false,
                         times: Bool = true) throws -> GpxTrackLog {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let time1 = times ? "<time>2026-09-09T06:31:00Z</time>" : ""
        let time2 = times ? "<time>2026-09-10T08:08:00Z</time>" : ""
        let path = directory.appendingPathComponent(name)
        try """
        <gpx><trk><trkseg>
        <trkpt lat="31.23" lon="121.48">\(time1)</trkpt>
        <trkpt lat="31.24" lon="\(changed ? "121.51" : "121.49")">\(time2)</trkpt>
        </trkseg><trkseg><trkpt lat="31.25" lon="121.50"/><trkpt lat="31.26" lon="121.51"/></trkseg></trk></gpx>
        """.write(to: path, atomically: true, encoding: .utf8)
        return try GpxTrackLog(contentsOf: path)
    }

    @Test func cacheSurvivesVisibilityAndRestartWithoutConversionRequests() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = try fixture(dir), id = log.sourceURL.path
        let url = dir.appendingPathComponent("cache.json")
        let library = TrackLibrary(url: url)
        library.synchronize([log])
        #expect(library.requests.isEmpty)
        library.select(id, amap: true)
        let token = try #require(library.requests[id])
        let segments = try #require(library.record(id)?.segments)
        library.complete(id, request: token, converted: segments)
        #expect(library.storageError == nil)
        let cache = try Data(contentsOf: url)
        library.setVisible(id, false, amap: true)
        library.setVisible(id, true, amap: true)
        #expect(library.requests.isEmpty)
        #expect(library.displays(amap: true).count == 1)
        #expect(try Data(contentsOf: url) == cache)
        let restored = TrackLibrary(url: url)
        #expect(restored.restore() == [log])
        #expect(restored.visible.isEmpty)
        restored.select(id, amap: true)
        #expect(restored.requests.isEmpty)
        #expect(restored.displays(amap: true).first?.segments == segments)
        #expect(restored.restore().isEmpty)
        #expect(try GpxTrackLog(contentsOf: log.sourceURL) == log)
    }

    @Test func refreshFailureCancellationAndStaleResponsePreserveCache() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = try fixture(dir), id = log.sourceURL.path
        let library = TrackLibrary(url: dir.appendingPathComponent("cache.json"))
        library.synchronize([log]); library.select(id, amap: true)
        let segments = try #require(library.record(id)?.segments)
        library.complete(id, request: try #require(library.requests[id]), converted: segments)
        _ = try fixture(dir, changed: true)
        _ = library.refresh(id, amap: true)
        #expect(library.record(id)?.cacheIsCurrent == false)
        let failed = try #require(library.requests[id])
        library.fail(id, request: failed, reason: "测试服务失败")
        #expect(library.record(id)?.converted == segments)
        _ = library.refresh(id, amap: true)
        let cancelled = try #require(library.requests[id])
        library.cancel(id)
        library.complete(id, request: cancelled, converted: [])
        #expect(library.record(id)?.converted == segments)
        #expect(library.states[id] == nil)
        #expect(library.displays(amap: true).count == 1)
    }

    @Test func sourceChangesInvalidateCacheAndUpdateTimestampMetadata() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = try fixture(dir), id = log.sourceURL.path
        let url = dir.appendingPathComponent("cache.json")
        let library = TrackLibrary(url: url)
        library.synchronize([log]); library.select(id, amap: true)
        let before = try #require(library.record(id))
        library.complete(id, request: try #require(library.requests[id]), converted: before.segments)
        let changed = try fixture(dir, changed: true, times: false)
        let restored = TrackLibrary(url: url)
        #expect(restored.restore() == [changed])
        #expect(restored.record(id)?.converted == nil)
        #expect(restored.record(id)?.timeRange == "无记录时间")
        #expect(restored.requests.isEmpty)
        restored.select(id, amap: true)
        #expect(restored.requests.count == 1)
    }

    @Test func missingSourceKeepsCachedPreviewButIsNotRestoredForPhotoMatching() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = try fixture(dir), id = log.sourceURL.path
        let url = dir.appendingPathComponent("cache.json")
        let library = TrackLibrary(url: url)
        library.synchronize([log]); library.select(id, amap: true)
        library.complete(id, request: try #require(library.requests[id]), converted: try #require(library.record(id)?.segments))
        try FileManager.default.removeItem(at: log.sourceURL)
        let restored = TrackLibrary(url: url)
        #expect(restored.restore().isEmpty)
        #expect(restored.record(id)?.sourceUnavailable == true)
        restored.synchronize([])
        restored.select(id, amap: true)
        #expect(restored.requests.isEmpty)
        #expect(restored.displays(amap: true).count == 1)
    }

    @Test func malformedCacheIsPreservedAndInvalidResultsNeverReplaceGoodData() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = try fixture(dir), id = log.sourceURL.path
        let url = dir.appendingPathComponent("cache.json")
        try Data("broken".utf8).write(to: url)
        let library = TrackLibrary(url: url)
        #expect(library.restore().isEmpty)
        library.synchronize([log]); library.select(id, amap: true)
        library.complete(id, request: try #require(library.requests[id]), converted: [[MapCoordinate(latitude: 0, longitude: 0)]])
        #expect(library.record(id)?.converted == nil)
        #expect(library.storageError != nil)
        #expect(try Data(contentsOf: url) == Data("broken".utf8))
    }

    @Test func fileIdentitySurvivesSortingDuplicateImportsAndIndividualRemoval() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = try fixture(dir, name: "a.gpx"), b = try fixture(dir, name: "b.gpx", changed: true)
        let reducer = PhotoTrailReducer()
        var state = PhotoTrailState()
        state = reducer.reduce(state, .readTrackLog(a.sourceURL.path, a))
        state = reducer.reduce(state, .readTrackLog(b.sourceURL.path, b))
        state = reducer.reduce(state, .readTrackLog(a.sourceURL.path, a))
        #expect(state.gpxTracks.count == 2)
        let library = TrackLibrary(url: dir.appendingPathComponent("cache.json"))
        library.synchronize(state.gpxTracks)
        library.select(b.sourceURL.path, amap: false)
        #expect(library.selected == b.sourceURL.path)
        #expect(library.displays(amap: false).first?.segments == TrackRecord(log: b).segments)
        state = reducer.reduce(state, .removeTrack(a.sourceURL))
        library.synchronize(state.gpxTracks)
        #expect(library.records.map(\.id) == [b.sourceURL.path])
        #expect(FileManager.default.fileExists(atPath: a.sourceURL.path))
    }

    @Test func thumbnailPreservesShapeAndSegmentBreaksAndTimeUsesGPXContent() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let record = TrackRecord(log: try fixture(dir))
        let path = TrackThumbnail.normalized(record.segments)
        #expect(path.map(\.count) == [2, 2])
        #expect(path[0][0].y != path[0][1].y)
        #expect(path.flatMap { $0 }.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
        #expect(record.timeRange.contains("2026/09/09"))
        #expect(record.timeRange.contains("2026/09/10"))
        #expect(record.fingerprint == record.fingerprint)
        #expect(TrackRecord(log: try fixture(dir, times: false)).timeRange == "无记录时间")
    }

    @Test func photoGeneratedTrackKeepsItsOriginBadgeAcrossCacheRestore() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let source = dir.appendingPathComponent("PhotoTrail-photos.gpx")
        try """
        <gpx creator="PhotoTrail"><trk><name>PhotoTrail Photos</name><trkseg>
        <trkpt lat="31.23" lon="121.48"><time>2026-09-09T06:31:00Z</time></trkpt>
        <trkpt lat="31.24" lon="121.49"><time>2026-09-09T06:32:00Z</time></trkpt>
        </trkseg></trk></gpx>
        """.write(to: source, atomically: true, encoding: .utf8)
        let log = try GpxTrackLog(contentsOf: source)
        let cache = dir.appendingPathComponent("cache.json")
        let library = TrackLibrary(url: cache)

        library.synchronize([log])

        #expect(library.record(log.sourceURL.path)?.generatedFromPhotos == true)
        let restored = TrackLibrary(url: cache)
        #expect(restored.restore() == [log])
        #expect(restored.record(log.sourceURL.path)?.generatedFromPhotos == true)
    }
}
