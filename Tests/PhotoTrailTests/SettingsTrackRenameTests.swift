import Foundation
import GpxTrackLog
import ImageData
import Metadata
import Testing
import UDF
@testable import PhotoTrail

struct SettingsTrackRenameTests {
    @Test func photoSortRoundtripAndUnknownFieldFallback() throws {
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let sorts = [KeyPathComparator(\ImageData.metadata.timestamp, order: .reverse), KeyPathComparator(\ImageData.name)]
        SettingsPreferences.savePhotoSort(sorts, defaults: defaults)
        let read = SettingsPreferences.photoSort(defaults: defaults)
        #expect(read.map(\.keyPath) == sorts.map(\.keyPath))
        #expect(read.map(\.order) == sorts.map(\.order))
        defaults.set(try JSONEncoder().encode([SettingsPreferences.PhotoSort(field: "unknown", descending: true)]), forKey: SettingsPreferences.photoSortKey)
        #expect(SettingsPreferences.photoSort(defaults: defaults)[0].keyPath == \ImageData.name)
    }

    @Test func filteredBlockMovementPreservesHiddenPositions() {
        let full = ["A", "hidden", "B", "C", "D"]
        #expect(RenameFileOrder.moving(["C", "D"], before: "A", visible: ["A", "B", "C", "D"], full: full) == ["C", "hidden", "D", "A", "B"])
        #expect(RenameFileOrder.moving(["outside"], before: "A", visible: ["A"], full: full) == full)
        #expect(RenameFileOrder.moving(["A"], before: "", visible: ["A", "B", "C", "D"], full: full) == ["B", "hidden", "C", "D", "A"])
    }

    @Test func groupSortingUsesLeaderAndMissingDatesStayLastDescending() {
        let root = URL(fileURLWithPath: "/tmp/order")
        let a = RenameInput(url: root.appendingPathComponent("a.jpg"), created: Date(timeIntervalSince1970: 10))
        let sidecar = RenameInput(url: root.appendingPathComponent("a.xmp"), created: Date(timeIntervalSince1970: 100))
        let b = RenameInput(url: root.appendingPathComponent("b.jpg"), created: Date(timeIntervalSince1970: 20))
        let missing = RenameInput(url: root.appendingPathComponent("missing.jpg"))
        var settings = RenameSettings()
        settings.sort = .created; settings.descending = true
        #expect(RenameEngine.ordered([a, sidecar, missing, b], settings: settings).map(\.name) == ["b.jpg", "a.jpg", "a.xmp", "missing.jpg"])
        #expect(RenameFileFilter(query: "a.jpg").matches(a, settings: settings))
        #expect(!RenameFileFilter(gps: 2).matches(RenameInput(url: a.url, metadataFailure: true), settings: settings))
        settings.sort = .metadata; settings.descending = false; settings.metadataSortTag = "Custom"
        let mixed = ["2", "10", "11a", ""].map { RenameInput(url: root.appendingPathComponent($0 + ".jpg"), tags: ["Custom": $0]) }
        #expect(RenameEngine.ordered(Array(mixed.reversed()), settings: settings).map(\.name) == ["2.jpg", "10.jpg", "11a.jpg", ".jpg"])
    }

    @Test @MainActor func adjustedTrackPersistsWithoutSourceWriteAndRejectsStaleApply() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appendingPathComponent("source.gpx")
        let bytes = Data("""
        <gpx version="1.1"><trk><trkseg>
        <trkpt lat="30" lon="120"><ele>3</ele><time>2023-11-14T22:13:20.125Z</time></trkpt>
        <trkpt lat="30.001" lon="120"><time>2023-11-14T22:14:20.125Z</time></trkpt>
        </trkseg></trk></gpx>
        """.utf8)
        try bytes.write(to: sourceURL)
        let source = try GpxTrackLog(contentsOf: sourceURL)
        let cache = directory.appendingPathComponent("cache.json")
        let library = TrackLibrary(url: cache)
        library.synchronize([source])
        let moved = try source.adjusted(seconds: 3600, east: 100, north: 0)
        try library.applyAdjustment(sourceURL.path, expected: source, adjusted: moved, amap: false)
        #expect(try Data(contentsOf: sourceURL) == bytes)
        #expect(library.synchronize([source]) == [moved])
        #expect(library.record(sourceURL.path)?.log == moved)
        #expect(throws: (any Error).self) { try library.applyAdjustment(sourceURL.path, expected: source, adjusted: moved, amap: false) }
        let restored = TrackLibrary(url: cache)
        await restored.restore()
        #expect(restored.record(sourceURL.path)?.log == moved)
        #expect(await restored.addHistory(sourceURL.path, amap: false) == moved)
        #expect(try library.undoAdjustment(sourceURL.path, amap: false) == source)
        try library.applyAdjustment(sourceURL.path, expected: source, adjusted: moved, amap: false)
        #expect(try library.restoreOriginal(sourceURL.path, amap: false) == source)
        #expect(try Data(contentsOf: sourceURL) == bytes)
        library.select(sourceURL.path, amap: true)
        let cached = try #require(library.record(sourceURL.path)?.segments)
        library.complete(sourceURL.path, request: try #require(library.requests[sourceURL.path]), converted: cached)
        let fitRevision = library.fitRevision
        let timed = try source.adjusted(seconds: 30, east: 0, north: 0)
        try library.applyAdjustment(sourceURL.path, expected: source, adjusted: timed, amap: true)
        #expect(library.record(sourceURL.path)?.converted == cached)
        #expect(library.fitRevision == fitRevision)
        library.start(sourceURL.path)
        let staleRequest = try #require(library.requests[sourceURL.path])
        try library.applyAdjustment(sourceURL.path, expected: timed, adjusted: moved, amap: true)
        #expect(library.fitRevision == fitRevision + 1)
        library.complete(sourceURL.path, request: staleRequest, converted: cached)
        #expect(library.record(sourceURL.path)?.converted == nil)
        let external = try source.adjusted(seconds: 60, east: 0, north: 0)
        try external.gpxData().write(to: sourceURL)
        #expect(library.synchronize([external]).isEmpty)
        #expect(library.record(sourceURL.path)?.log == moved)
        #expect(throws: (any Error).self) { try library.applyAdjustment(sourceURL.path, expected: moved, adjusted: timed, amap: false) }
        #expect(try library.restoreOriginal(sourceURL.path, amap: false)?.tracks == external.tracks)
    }

    @Test @MainActor func trackChangeDiscardsLateMatchingResults() async {
        var state = PhotoTrailState(forPreview: true)
        state.selection = Set(state.imageData.prefix(1).map(\.id))
        state.gpxTracks = [GpxTrackLog(sourceURL: URL(fileURLWithPath: "/tmp/late-track.gpx"), tracks: [])]
        let store = Store(initialState: state, reduce: PhotoTrailReducer())
        let task = LocationHelper.locationFromTrack(store, extendedTime: 5)
        store.send(.removeTrack(store.gpxTracks[0].sourceURL), undoable: false)
        await task.value
        #expect(store.trackMatches.isEmpty)
    }

    @Test @MainActor func movingSelectedScopeKeepsUnselectedManualPositions() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let images = try ["A", "B", "C", "D"].map { name in
            let url = directory.appendingPathComponent(name + ".jpg")
            try Data("disposable identity fixture".utf8).write(to: url)
            return ImageData(metadata: Metadata(source: .image(url)), name: name + ".jpg")
        }
        let domain = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let workspace = RenameWorkspace(defaults: defaults)
        workspace.rules = [RenameRule(action: 46)]
        workspace.settings.sort = .input
        func refresh() async throws {
            workspace.refresh(images: images, selection: [images[2].id, images[3].id], directoryScopes: [directory])
            for _ in 0..<400 where workspace.busy { try await Task.sleep(for: .milliseconds(25)) }
            #expect(!workspace.busy)
        }
        try await refresh()
        let groups = Dictionary(uniqueKeysWithValues: workspace.rows.map { ($0.source.lastPathComponent, $0.group) })
        workspace.moveFiles([try #require(groups["D.jpg"])], before: try #require(groups["A.jpg"]))
        try await refresh()
        #expect(workspace.rows.map { $0.source.lastPathComponent } == ["D.jpg", "A.jpg", "B.jpg", "C.jpg"])
        workspace.onlySelected = true
        try await refresh()
        workspace.moveFiles([try #require(groups["C.jpg"])], before: try #require(groups["D.jpg"]))
        try await refresh()
        workspace.onlySelected = false
        try await refresh()
        #expect(workspace.rows.map { $0.source.lastPathComponent } == ["C.jpg", "A.jpg", "B.jpg", "D.jpg"])
        workspace.undoFileOrder()
        try await refresh()
        #expect(workspace.rows.map { $0.source.lastPathComponent } == ["D.jpg", "A.jpg", "B.jpg", "C.jpg"])
    }
}
