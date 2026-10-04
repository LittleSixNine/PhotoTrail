import Coords
import Foundation
import Testing
import UDF
import UniformTypeIdentifiers

@testable import PhotoTrail

@MainActor
struct OpenHelperTests {
    @Test func unsupportedFilesAreIgnoredWhilePhotosAndTracksAreKept() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let filenames = ["clip.MOV", "clip-2.mp4", "clip-3.mkv", "photo.JPG", "track.gpx",
                         "line.KML", "packed.KMZ", "notes.txt", "sidecar.csv"]
        for filename in filenames {
            try Data().write(to: folder.appendingPathComponent(filename))
        }

        let store = Store(initialState: PhotoTrailState(), reduce: PhotoTrailReducer())
        store.send(.openFiles([folder, folder.appendingPathComponent("clip.MOV")]))
        #expect(store.ignoredFileCount == 5)
        #expect(Set((store.uniqueURLs ?? []).map(\.lastPathComponent)) == ["photo.JPG", "track.gpx", "line.KML", "packed.KMZ"])
        #expect(Set(UTType.photoTrailTracks.compactMap(\.preferredFilenameExtension)) == ["gpx", "kml", "kmz"])

        store.send(.openFiles([folder.appendingPathComponent("clip.MOV")]))
        #expect(store.ignoredFileCount == 1)
        #expect(store.uniqueURLs?.isEmpty == true)
    }

    @Test func kmlAndKMZUseTheSharedImportPath() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let kml = folder.appendingPathComponent("doc.kml")
        let kmz = folder.appendingPathComponent("track.kmz")
        try """
        <kml xmlns="http://www.opengis.net/kml/2.2" xmlns:gx="http://www.google.com/kml/ext/2.2">
        <Placemark><gx:Track><when>2026-10-04T00:00:00Z</when><when>2026-10-04T00:01:00Z</when>
        <gx:coord>120 30 0</gx:coord><gx:coord>121 31 0</gx:coord></gx:Track></Placemark></kml>
        """.write(to: kml, atomically: true, encoding: .utf8)
        let zip = Process()
        zip.executableURL = URL(filePath: "/usr/bin/zip")
        zip.currentDirectoryURL = folder
        zip.arguments = ["-q", kmz.path, "doc.kml"]
        try zip.run(); zip.waitUntilExit()
        #expect(zip.terminationStatus == 0)
        let store = Store(initialState: PhotoTrailState(), reduce: PhotoTrailReducer())
        store.send(.openFiles([kml, kmz]))
        await OpenHelper.open(store, urls: try #require(store.uniqueURLs), description: "track import", spinnerEnabled: nil).value
        #expect(store.imageData.isEmpty)
        #expect(store.gpxBadFileNames.isEmpty)
        #expect(store.gpxTracks.count == 2)
        #expect(store.gpxTracks.allSatisfy { $0.hasRecordedTimes })
        #expect(Set(store.gpxTracks.map(\.sourceURL)) == [kml, kmz])
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
