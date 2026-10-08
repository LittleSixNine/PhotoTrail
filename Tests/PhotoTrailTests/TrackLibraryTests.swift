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

    @Test func cacheSurvivesVisibilityAndRestartWithoutConversionRequests() async throws {
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
        await restored.restore()
        #expect(restored.records.map(\.log) == [log])
        #expect(restored.visible.isEmpty)
        restored.select(id, amap: true)
        #expect(restored.requests.isEmpty)
        #expect(restored.displays(amap: true).first?.segments == segments)
        await restored.restore()
        #expect(try GpxTrackLog(contentsOf: log.sourceURL) == log)
    }

    @Test func refreshFailureCancellationAndStaleResponsePreserveCache() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = try fixture(dir), id = log.sourceURL.path
        let library = TrackLibrary(url: dir.appendingPathComponent("cache.json"))
        library.synchronize([log]); library.select(id, amap: true)
        let segments = try #require(library.record(id)?.segments)
        library.complete(id, request: try #require(library.requests[id]), converted: segments)
        _ = try fixture(dir, changed: true)
        _ = await library.refresh(id, amap: true)
        #expect(library.record(id)?.cacheIsCurrent == false)
        let failed = try #require(library.requests[id])
        library.fail(id, request: failed, reason: "测试服务失败")
        #expect(library.record(id)?.converted == segments)
        _ = await library.refresh(id, amap: true)
        let cancelled = try #require(library.requests[id])
        library.cancel(id)
        library.complete(id, request: cancelled, converted: [])
        #expect(library.record(id)?.converted == segments)
        #expect(library.states[id] == nil)
        #expect(library.displays(amap: true).count == 1)
    }

    @Test func sourceChangesInvalidateCacheAndUpdateTimestampMetadata() async throws {
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
        await restored.restore()
        #expect(restored.records.map(\.log) == [log])
        #expect(await restored.addHistory(id, amap: false) == changed)
        #expect(restored.record(id)?.converted == nil)
        #expect(restored.record(id)?.timeRange == "无记录时间")
        #expect(restored.requests.isEmpty)
        restored.select(id, amap: true)
        #expect(restored.requests.count == 1)
    }

    @Test func missingSourceKeepsCachedPreviewButIsNotRestoredForPhotoMatching() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = try fixture(dir), id = log.sourceURL.path
        let url = dir.appendingPathComponent("cache.json")
        let library = TrackLibrary(url: url)
        library.synchronize([log]); library.select(id, amap: true)
        library.complete(id, request: try #require(library.requests[id]), converted: try #require(library.record(id)?.segments))
        try FileManager.default.removeItem(at: log.sourceURL)
        let restored = TrackLibrary(url: url)
        await restored.restore()
        #expect(await restored.addHistory(id, amap: true) == nil)
        #expect(restored.record(id)?.sourceUnavailable == true)
        restored.synchronize([])
        restored.select(id, amap: true)
        #expect(restored.requests.isEmpty)
        #expect(restored.displays(amap: true).count == 1)
    }

    @Test func malformedCacheIsPreservedAndInvalidResultsNeverReplaceGoodData() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = try fixture(dir), id = log.sourceURL.path
        let url = dir.appendingPathComponent("cache.json")
        try Data("broken".utf8).write(to: url)
        let library = TrackLibrary(url: url)
        await library.restore()
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
        #expect(library.displays(amap: false).first(where: { $0.id == b.sourceURL.path })?.segments == TrackRecord(log: b).segments)
        state = reducer.reduce(state, .removeTrack(a.sourceURL))
        library.synchronize(state.gpxTracks)
        #expect(library.activeRecords.map(\.id) == [b.sourceURL.path])
        #expect(library.records.count == 2)
        #expect(FileManager.default.fileExists(atPath: a.sourceURL.path))
    }

    @Test func importsQueueAutomaticallyAndFailureOrCancellationAdvances() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let logs = try ["a.gpx", "b.gpx", "c.gpx"].map { try fixture(dir, name: $0) }
        let ids = logs.map { $0.sourceURL.path }
        let library = TrackLibrary(url: dir.appendingPathComponent("cache.json"))
        library.synchronize(logs, amap: true)
        #expect(library.activeIDs == ids)
        #expect(library.visible == Set(ids))
        #expect(library.requests.count == 3)
        #expect(library.nextRequestID == ids[0])
        let stale = try #require(library.requests[ids[0]])
        library.fail(ids[0], request: stale, reason: "测试失败")
        #expect(library.nextRequestID == ids[1])
        library.cancel(ids[1])
        #expect(library.nextRequestID == ids[2])
        library.complete(ids[0], request: stale, converted: [])
        #expect(library.record(ids[0])?.converted == nil)
        library.complete(ids[2], request: try #require(library.requests[ids[2]]),
                         converted: try #require(library.record(ids[2])?.segments))
        #expect(library.nextRequestID == nil)
        library.synchronize(logs, amap: true)
        #expect(library.requests.isEmpty) // Unrelated updates must not restart cancelled/failed work.
    }

    @Test func historyStartsEmptyAndReusesCacheAfterRemovalAndRestart() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = try fixture(dir), id = log.sourceURL.path
        let cache = dir.appendingPathComponent("cache.json")
        let library = TrackLibrary(url: cache)
        library.synchronize([log], amap: true)
        library.complete(id, request: try #require(library.requests[id]),
                         converted: try #require(library.record(id)?.segments))
        library.synchronize([])
        #expect(library.activeRecords.isEmpty)
        #expect(library.record(id)?.cacheIsCurrent == true)
        let restored = TrackLibrary(url: cache)
        await restored.restore()
        restored.synchronize([], amap: true)
        #expect(restored.activeRecords.isEmpty)
        #expect(restored.requests.isEmpty)
        #expect(restored.records.count == 1)
        #expect(await restored.addHistory(id, amap: true) == log)
        #expect(restored.requests.isEmpty)
        #expect(restored.visible == [id])
        #expect(await restored.addHistory(id, amap: true) == nil)
        #expect(restored.activeRecords.count == 1)
        restored.remove(id)
        _ = try fixture(dir, changed: true)
        #expect(await restored.addHistory(id, amap: true) != nil)
        #expect(restored.record(id)?.cacheIsCurrent == false)
        #expect(restored.nextRequestID == id)
    }

    @Test func missingHistoricalSourceIsPreviewOnlyAndProviderSwitchQueuesActiveTracks() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = try fixture(dir), id = log.sourceURL.path
        let library = TrackLibrary(url: dir.appendingPathComponent("cache.json"))
        library.synchronize([log], amap: false)
        #expect(library.requests.isEmpty)
        library.changeProvider(amap: true)
        #expect(library.nextRequestID == id)
        library.complete(id, request: try #require(library.requests[id]),
                         converted: try #require(library.record(id)?.segments))
        library.synchronize([])
        try FileManager.default.removeItem(at: log.sourceURL)
        #expect(await library.addHistory(id, amap: true) == nil)
        #expect(library.record(id)?.sourceUnavailable == true)
        #expect(library.displays(amap: true).count == 1)
        #expect(library.requests.isEmpty)
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

    @Test func photoGeneratedTrackKeepsItsOriginBadgeAcrossCacheRestore() async throws {
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
        await restored.restore()
        #expect(restored.records.map(\.log) == [log])
        #expect(restored.record(log.sourceURL.path)?.generatedFromPhotos == true)
    }

    @Test func kmlHistoryAndRefreshPreserveSourceIdentityAndDisplayOnlyState() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("route.kml")
        let xml = "<kml><Placemark><LineString><coordinates>120,30 121,31</coordinates></LineString></Placemark></kml>"
        try xml.write(to: source, atomically: true, encoding: .utf8)
        let log = try GpxTrackLog(contentsOf: source)
        let cache = dir.appendingPathComponent("cache.json")
        let library = TrackLibrary(url: cache)
        library.synchronize([log])
        let restored = TrackLibrary(url: cache)
        await restored.restore()
        #expect(restored.records.map(\.log) == [log])
        #expect(await restored.addHistory(source.path, amap: false) == log)
        #expect(restored.record(source.path)?.log.hasRecordedTimes == false)
        try xml.replacingOccurrences(of: "121,31", with: "122,32").write(to: source, atomically: true, encoding: .utf8)
        let refreshed = try #require(await restored.refresh(source.path, amap: false))
        #expect(refreshed.sourceURL == source)
        #expect(refreshed.tracks[0].segments[0].points.last?.lon == 122)
    }
    @Test func importsBeforeRestoreDoNotOverwriteHistoryOrNewerData() async throws {
        let dir = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let old = try fixture(dir), other = try fixture(dir, name: "other.gpx")
        let cache = dir.appendingPathComponent("cache.json")
        let first = TrackLibrary(url: cache)
        first.synchronize([old, other])
        let before = try Data(contentsOf: cache)
        let next = TrackLibrary(url: cache)
        let changed = try fixture(dir, changed: true)
        next.synchronize([changed])
        #expect(try Data(contentsOf: cache) == before)
        async let a: Void = next.restore()
        async let b: Void = next.restore()
        _ = await (a, b)
        #expect(next.records.count == 2)
        #expect(next.record(old.sourceURL.path)?.log == changed)
        #expect(next.activeIDs == [changed.sourceURL.path])
        let reopened = TrackLibrary(url: cache)
        await reopened.restore()
        #expect(reopened.records.count == 2)
        #expect(reopened.record(old.sourceURL.path)?.log == changed)
    }

    @Test func corruptCacheIsNotOverwrittenByImportsBeforeRestore() async throws {
        let dir = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = try fixture(dir)
        let cache = dir.appendingPathComponent("cache.json")
        let broken = Data("broken".utf8)
        try broken.write(to: cache)
        let library = TrackLibrary(url: cache)
        library.synchronize([log])
        await library.restore()
        #expect(library.record(log.sourceURL.path)?.log == log)
        #expect(library.storageError != nil)
        #expect(try Data(contentsOf: cache) == broken)
    }

    @Test func removingTrackDuringReadRejectsLateResult() async throws {
        let dir = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("large.kml")
        let xml = "<kml xmlns:g=\"http://www.google.com/kml/ext/2.2\"><Placemark><g:Track>"
            + String(repeating: "<g:coord>120 30 0</g:coord>", count: 40_000) + "</g:Track></Placemark></kml>"
        try xml.write(to: source, atomically: true, encoding: .utf8)
        let log = try GpxTrackLog(contentsOf: source)
        let library = TrackLibrary(url: dir.appendingPathComponent("cache.json"))
        library.synchronize([log]); library.synchronize([])
        let operation = Task { await library.addHistory(source.path, amap: false) }
        await Task.yield()
        #expect(library.readingSources[source.path] != nil)
        library.remove(source.path)
        #expect(await operation.value == nil)
        #expect(library.activeIDs.isEmpty)
        #expect(library.record(source.path)?.log == log)
    }

}
