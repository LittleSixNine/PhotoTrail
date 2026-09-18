import Coords
import Foundation
import Testing
import UDF

@testable import PhotoTrail

@MainActor
struct OpenHelperTests {
    @Test func videoFilesAreIgnoredBeforeImport() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let filenames = ["clip.MOV", "clip-2.mp4", "clip-3.mkv", "photo.JPG", "track.gpx"]
        for filename in filenames {
            try Data().write(to: folder.appendingPathComponent(filename))
        }

        let store = Store(initialState: PhotoTrailState(), reduce: PhotoTrailReducer())
        store.send(.openFiles([folder, folder.appendingPathComponent("clip.MOV")]))
        #expect(store.ignoredVideoCount == 3)
        #expect(Set((store.uniqueURLs ?? []).map(\.lastPathComponent)) == ["photo.JPG", "track.gpx"])

        store.send(.openFiles([folder.appendingPathComponent("clip.MOV")]))
        #expect(store.ignoredVideoCount == 1)
        #expect(store.uniqueURLs?.isEmpty == true)
    }

    @Test func openHelperTest() async throws {
        let store = Store(initialState: PhotoTrailState(), reduce: PhotoTrailReducer())

        var urls = store.state.previewURLs()
        if let trackURL = Bundle.main.url(forResource: "TestTrack",
                                          withExtension: "GPX") {
            urls.append(trackURL)
        }
        await store.send(.openFiles(urls)) {
            if let urls = store.uniqueURLs {
                let task = OpenHelper.open(store, urls: urls,
                                           description: "openhelper test",
                                           spinnerEnabled: nil)
                _ = await task.result
            } else {
                Issue.record("No unique URLs found to open")
            }
        }
        #expect(!store.imageData.isEmpty)
        #expect(!store.gpxTracks.isEmpty)
    }
}
