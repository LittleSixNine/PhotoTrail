import Coords
import Foundation
import GpxTrackLog
import Testing
import WebKit
@testable import GeoTag

@MainActor
struct AMapTrackTests {
    @Test func regionBridgeReceivesJavaScriptValue() async throws {
        let workspace = LocationWorkspace()
        let parent = AMapWebView(snapshot: AMapSnapshot(revision: 0, point: nil,
                                                       editable: false, photos: []),
            credentials: AMapCredentials(key: "test-only", securityJsCode: "test-only"),
            startupCoordinate: nil,
            trackRevision: 0, fitRevision: 0, mapStyle: .normal, trackColor: "#000000", trackWidth: 0,
            onMapTap: {},
            onPick: { _, _ in Issue.record("A region query must not change a photo") }, workspace: workspace)
        let coordinator = AMapWebView.Coordinator(parent)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        coordinator.browserView = view
        coordinator.pageURL = URL(string: "about:blank")
        view.navigationDelegate = coordinator
        coordinator.connect()
        defer { AMapWebView.dismantleNSView(view, coordinator: coordinator) }
        view.loadHTMLString("""
        <script>window.geoTag = {
          start: async () => true, updateSnapshot: async () => {},
          setTrackStyle: () => {}, renderTracks: () => {},
          region: async point => point.latitude === 31.23 ? '上海市' : ''
        };</script>
        """, baseURL: nil)
        for _ in 0..<100 {
            if workspace.ready { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        try #require(workspace.ready)
        let lookup = try #require(workspace.lookupAMapRegion)
        let region = try await lookup(MapCoordinate(latitude: 31.23, longitude: 121.48))
        #expect(region == "上海市")
        await #expect(throws: (any Error).self) {
            try await lookup(MapCoordinate(latitude: 0, longitude: 0))
        }
    }

    @Test func cachedTracksCrossTheWebViewBridgeWithoutAnotherConversion() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("synthetic.gpx")
        try "<gpx><trk><trkseg><trkpt lat='31.23' lon='121.48'/><trkpt lat='31.24' lon='121.49'/></trkseg></trk></gpx>"
            .write(to: file, atomically: true, encoding: .utf8)
        let log = try GpxTrackLog(contentsOf: file)
        let library = TrackLibrary(url: dir.appendingPathComponent("cache.json"))
        library.synchronize([log])
        let workspace = LocationWorkspace(tracks: library)
        let parent = AMapWebView(snapshot: AMapSnapshot(revision: 0, point: nil,
                                                       editable: false, photos: []),
            credentials: AMapCredentials(key: "test-only", securityJsCode: "test-only"),
            startupCoordinate: nil,
            trackRevision: 0, fitRevision: 0, mapStyle: .normal, trackColor: "#FF3B30", trackWidth: 3,
            onMapTap: {},
            onPick: { _, _ in Issue.record("Track display must not write photo locations") }, workspace: workspace)
        let coordinator = AMapWebView.Coordinator(parent)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        coordinator.browserView = view
        coordinator.pageURL = URL(string: "about:blank")
        view.navigationDelegate = coordinator
        coordinator.connect()
        defer { AMapWebView.dismantleNSView(view, coordinator: coordinator) }
        view.loadHTMLString("""
        <script>window.calls = 0; window.draws = []; window.fitted = null;
        window.geoTag = { start: async () => true, updateSnapshot: async () => {}, setTrackStyle: () => {},
          renderTracks: (records) => { window.draws = records; }, fitTracks: id => { window.fitted = id; },
          cancelTrack: () => {}, convertTracks: async segments => { window.calls++; return {segments}; }
        };</script>
        """, baseURL: nil)
        for _ in 0..<100 {
            if workspace.ready { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        try #require(workspace.ready)
        library.select(file.path, amap: true)
        coordinator.updateTracks()
        for _ in 0..<100 {
            if library.requests.isEmpty { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(library.record(file.path)?.cacheIsCurrent == true)
        coordinator.updateTracks()
        library.setVisible(file.path, false, amap: true)
        coordinator.updateTracks()
        library.setVisible(file.path, true, amap: true)
        coordinator.updateTracks()
        let result: String = try await withCheckedThrowingContinuation { continuation in
            view.callAsyncJavaScript("return [window.calls, window.draws.length, window.fitted !== null].join(',');",
                in: nil, in: .page) { result in
                switch result {
                case .success(let value): continuation.resume(returning: value as? String ?? "")
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
        #expect(result == "1,1,true")
    }

    @Test func displayPreservesSegmentsAndDoesNotAffectTimeMatching() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("track-\(UUID()).gpx")
        defer { try? FileManager.default.removeItem(at: url) }
        try """
        <gpx version="1.1"><trk>
        <trkseg>
          <trkpt lat="31.23" lon="121.48"><ele>10</ele><time>2026-01-01T00:00:00Z</time></trkpt>
          <trkpt lat="31.24" lon="121.49"><time>2026-01-01T00:01:00Z</time></trkpt>
        </trkseg><trkseg>
          <trkpt lat="37.77" lon="-122.42"><time>2026-01-02T00:00:00Z</time></trkpt>
          <trkpt lat="37.78" lon="-122.41"><time>2026-01-02T00:01:00Z</time></trkpt>
        </trkseg><trkseg/><trkseg><trkpt lat="0" lon="0"/></trkseg>
        </trk></gpx>
        """.write(to: url, atomically: true, encoding: .utf8)
        let track = try GpxTrackLog(contentsOf: url)
        let original = try Data(contentsOf: url)
        let input = [LocationHelper.LocationById(id: 1, timestamp: 1_767_225_600)]
        let before = await LocationHelper.locations(for: input, extendedTime: 0, tracks: [track])
        let segments = try AMapView.trackSegments([track])
        #expect(segments.map(\.count) == [2, 2])
        #expect(segments[0][0] == MapCoordinate(latitude: 31.23, longitude: 121.48))
        #expect(segments[1][0] == MapCoordinate(latitude: 37.77, longitude: -122.42))
        let after = await LocationHelper.locations(for: input, extendedTime: 0, tracks: [track])
        #expect(before == after)
        #expect(after.count == 1)
        #expect(after.first?.coords?.longitude == 121.48)
        #expect(try Data(contentsOf: url) == original)
        #expect(LocationWorkspace().tracks.visible.isEmpty)
    }

    @Test func emptyAndInvalidCoordinates() throws {
        #expect(try AMapView.trackSegments([]).isEmpty)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("track-\(UUID()).gpx")
        defer { try? FileManager.default.removeItem(at: url) }
        try """
        <gpx><trk><trkseg><trkpt lat="100" lon="121"/><trkpt lat="31" lon="121"/></trkseg></trk></gpx>
        """.write(to: url, atomically: true, encoding: .utf8)
        let track = try GpxTrackLog(contentsOf: url)
        #expect(throws: (any Error).self) { try AMapView.trackSegments([track]) }
    }
}
