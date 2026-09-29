import Coords
import Exiftool
import Foundation
import ImageData
import Metadata
import Testing
import UDF

@testable import PhotoTrail

@MainActor
struct SaveHelperTests {
    @Test func cancelSaveSummaryLeavesChangesPending() {
        let key = SettingsPreferences.showSaveSummaryKey
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.set(true, forKey: key)

        var changed = ImageData(metadata: Metadata(source: .xmp(URL(fileURLWithPath: "/tmp/save-summary.xmp"))),
                                name: "changed.jpg")
        changed.metadata.location = Coords(latitude: 31.23, longitude: 121.48)
        let unchanged = ImageData(metadata: Metadata(source: .xmp(URL(fileURLWithPath: "/tmp/unchanged.xmp"))),
                                  name: "unchanged.jpg")
        var state = PhotoTrailState()
        state.imageData = [changed, unchanged]
        state.unsavedChanges = true
        let store = Store(initialState: state, reduce: PhotoTrailReducer())
        var prompted = false

        let started = SaveHelper.requestSave(store) { targets in
            prompted = true
            #expect(targets.total == 1)
            #expect(targets.xmp == [0])
            #expect(targets.files.isEmpty && targets.library.isEmpty)
            return false
        }

        #expect(prompted)
        #expect(!started)
        #expect(!store.saveInProgress)
        #expect(store.unsavedChanges)
        #expect(store.saveTotal == 0)
    }

    func copyTestImages(_ state: PhotoTrailState) throws -> URL {
        let url = URL.documentsDirectory.appending(component: UUID().uuidString,
                                                   directoryHint: .isDirectory)
        let fm = FileManager.default
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        var images = state.previewURLs()
        // copy the xmp files, too
        if let xmps = Bundle.main.urls(forResourcesWithExtension: "xmp",
                                       subdirectory: nil) {
            images.append(contentsOf: xmps)
        }
        for image in images {
            let dest = url.appending(component: image.lastPathComponent)
            try fm.copyItem(at: image, to: dest)
        }

        return url
    }

    func createBackupFolder(for store: Store<PhotoTrailState, PhotoTrailEvent>) throws {
        let fm = FileManager.default
        let backupURL =
            URL.temporaryDirectory.appending(components: UUID().uuidString,
                                             directoryHint: .isDirectory)
        try fm.createDirectory(at: backupURL,
                               withIntermediateDirectories: true)
        store.send(.backupURLChanged(backupURL))
    }

    @Test func firstSidecarSaveWritesXmpAndLeavesImageMetadataUnchanged() async throws {
        let preview = PhotoTrailState(forPreview: true)
        let source = try #require(preview.imageData.compactMap { image -> URL? in
            guard case .image(let url) = image.metadata.source,
                  url.pathExtension.lowercased() == "jpg" else { return nil }
            return url
        }.first)
        let folder = URL.temporaryDirectory.appending(component: UUID().uuidString,
                                                       directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let imageURL = folder.appending(component: source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: imageURL)

        let original = Exiftool.helper.metadata(from: nil, primaryURL: imageURL)
        var edited = original
        edited.dateTimeCreated = "2030:01:02 03:04:05"
        let image = ImageData(metadata: edited, name: imageURL.lastPathComponent)
        var state = PhotoTrailState()
        state.imageData = [image]
        let store = Store(initialState: state, reduce: PhotoTrailReducer())

        let status = await SaveHelper.saveToImageTasks(
            store, [image.id: edited], true, nil, nil, false, "PhotoTrail")

        #expect(status == .saveOK)
        let sidecarURL = imageURL.deletingPathExtension().appendingPathExtension("xmp")
        #expect(FileManager.default.fileExists(atPath: sidecarURL.path))
        let imageAfter = Exiftool.helper.metadata(from: nil, primaryURL: imageURL)
        let sidecarAfter = Exiftool.helper.metadata(from: sidecarURL, primaryURL: imageURL)
        #expect(imageAfter.dateTimeCreated == original.dateTimeCreated)
        #expect(sidecarAfter.dateTimeCreated == edited.dateTimeCreated)
        guard case .xmp = store[image.id].metadata.source else {
            Issue.record("Successful first sidecar save did not switch the in-memory source")
            return
        }
    }

    @Test func saveHelperTest() async throws {
        // create the test store
        let store = Store(initialState: PhotoTrailState(), reduce: PhotoTrailReducer())
        let fm = FileManager.default

        // copy images to be updated to a temporary location
        let userFolder = try copyTestImages(store.state)
        defer {
            try? fm.removeItem(at: userFolder)
        }

        // add the images to the store
        await store.send(.openFiles([userFolder]), undoable: false) {
            if let urls = store.uniqueURLs {
                let task = OpenHelper.open(store, urls: urls,
                                           description: "add files",
                                           spinnerEnabled: nil)
                _ = await task.result
            } else {
                Issue.record("No unique URLs found to open")
            }
        }
        #expect(!store.imageData.isEmpty)

        // - create a backup folder
        try createBackupFolder(for: store)
        defer {
            if let url = store.backupURL {
                try? fm.removeItem(at: url)
            }
        }

        // - modify the image metadata
        store.send(.selectAllRequest)
        store.send(.locationChanged(Coords(latitude: 34.567,
                                           longitude: -122.345)))
        #expect(store.unsavedChanges)

        // now invoke the save helper
        await store.send(.saveRequest) {
            let task = SaveHelper.save(store)
            _ = await task.result
        }
        #expect(!store.unsavedChanges)
        #expect(store.saveTotal > 0)
        #expect(store.saveCompleted == store.saveTotal)
        #expect(!store.locationSavedPhotoIDs.isEmpty)
    }
}
