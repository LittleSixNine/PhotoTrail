import Coords
import Foundation
import Testing
import UDF

@testable import PhotoTrail

@MainActor
struct OpenHelperTests {
    @Test func unsupportedFilesAreIgnoredWhilePhotosAndGPXAreKept() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let filenames = ["clip.MOV", "clip-2.mp4", "clip-3.mkv", "photo.JPG", "track.gpx",
                         "notes.txt", "sidecar.csv"]
        for filename in filenames {
            try Data().write(to: folder.appendingPathComponent(filename))
        }

        let store = Store(initialState: PhotoTrailState(), reduce: PhotoTrailReducer())
        store.send(.openFiles([folder, folder.appendingPathComponent("clip.MOV")]))
        #expect(store.ignoredFileCount == 5)
        #expect(Set((store.uniqueURLs ?? []).map(\.lastPathComponent)) == ["photo.JPG", "track.gpx"])

        store.send(.openFiles([folder.appendingPathComponent("clip.MOV")]))
        #expect(store.ignoredFileCount == 1)
        #expect(store.uniqueURLs?.isEmpty == true)
    }

    @Test func onlyNonImagesAreSkippedAndDirectOpenDoesNotCreateGrayRows() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let text = folder.appendingPathComponent("notes.txt")
        let data = folder.appendingPathComponent("data.json")
        try Data("notes".utf8).write(to: text)
        try Data("{}".utf8).write(to: data)

        let store = Store(initialState: PhotoTrailState(), reduce: PhotoTrailReducer())
        store.send(.openFiles([text, data]))
        #expect(store.ignoredFileCount == 2)
        #expect(store.uniqueURLs?.isEmpty == true)

        let task = OpenHelper.open(store, urls: [text, data], description: "unsupported files",
                                   spinnerEnabled: nil)
        _ = await task.result
        #expect(store.imageData.isEmpty)
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
