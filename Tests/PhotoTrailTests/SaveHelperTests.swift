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
    @Test nonisolated func finderTagFailureDoesNotUndoSavedMetadata() async {
        enum ControlledFailure: Error { case save, tag }
        var saveCount = 0
        var tagCount = 0
        let outcome = await SaveHelper.saveThenTag(
            save: { saveCount += 1 },
            tag: { tagCount += 1; throw ControlledFailure.tag })
        #expect(outcome == .savedWithoutTag)
        #expect(saveCount == 1 && tagCount == 1)

        let failed = await SaveHelper.saveThenTag(
            save: { throw ControlledFailure.save },
            tag: { tagCount += 1 })
        #expect(failed == .failed)
        #expect(tagCount == 1)
    }

    @Test func finderTagFailureMarksMetadataSavedInState() {
        var edited = ImageData(
            metadata: Metadata(source: .xmp(URL(fileURLWithPath: "/tmp/tag-failure.xmp"))),
            name: "tag-failure.jpg")
        edited.metadata.location = Coords(latitude: 31.23, longitude: 121.48)
        var state = PhotoTrailState()
        state.imageData = [edited]
        state.unsavedChanges = true
        let store = Store(initialState: state, reduce: PhotoTrailReducer())
        store.send(.saveRequest)
        store.send(.imageSaved(edited.id, edited.metadata))
        store.send(.saveComplete(.saveTagError))

        #expect(!store.unsavedChanges)
        #expect(store[edited.id].original == store[edited.id].metadata)
        #expect(store.sheetType == .unexpectedErrorSheet)
    }

    @Test func metadataTagSaveReconcilesUnknownWithoutReplayingWrite() {
        enum ControlledFailure: Error { case validation, readback }
        let image = URL(fileURLWithPath: "/tmp/metadata-tag-save.xmp")
        let changes: [MetadataTag: MetadataTagChange] = [
            .subject: .set(.list(["existing", "appended"]))
        ]
        var updateCount = 0
        var readbackCount = 0

        let reconciled = SaveHelper.saveMetadataTags(
            image: image,
            changes: changes,
            update: { _, _ in
                updateCount += 1
                throw MetadataTagUpdateError.readbackFailed(
                    underlying: ControlledFailure.readback)
            },
            readback: { _, _ in
                readbackCount += 1
                return [.subject: .list(["existing", "appended"])]
            })
        #expect(reconciled == .saved)
        #expect(updateCount == 1)
        #expect(readbackCount == 1)

        let unknown = SaveHelper.saveMetadataTags(
            image: image,
            changes: changes,
            update: { _, _ in
                throw MetadataTagUpdateError.writeFailed(
                    underlying: ControlledFailure.readback)
            },
            readback: { _, _ in [.subject: .list(["third value"])] })
        #expect(unknown == .resultUnknown)

        var validationReadbackCount = 0
        let failed = SaveHelper.saveMetadataTags(
            image: image,
            changes: changes,
            update: { _, _ in throw ControlledFailure.validation },
            readback: { _, _ in
                validationReadbackCount += 1
                return [:]
            })
        #expect(failed == .failed)
        #expect(validationReadbackCount == 0)
    }

    @Test func creatorDraftSavesThroughStoreAndRetainsStaleFailure() async throws {
        let source = try #require(PhotoTrailState(forPreview: true).imageData.compactMap { image -> URL? in
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
        let image = ImageData(metadata: Exiftool.helper.metadata(from: nil, primaryURL: imageURL),
                              name: imageURL.lastPathComponent)
        var state = PhotoTrailState()
        state.imageData = [image]
        state.backupURL = folder.appending(component: "backup", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: state.backupURL!,
                                                withIntermediateDirectories: true)
        let store = Store(initialState: state, reduce: PhotoTrailReducer(), undoEnabled: true)

        func plan(_ author: String) throws -> MetadataCreatorEditPlan {
            let snapshot = try MetadataInspectionSnapshot.read([.creator], from: imageURL)
            return try MetadataCreatorEditPlan.prepare(
                [(image: store[image.id], snapshot: snapshot)], action: .set([author]))
        }
        store.send(.creatorDraftApplied(try plan("Draft author").items))
        #expect(store.unsavedChanges)
        #expect(SaveTargets(images: store.imageData).creator == [0])
        store.undo()
        #expect(!store.unsavedChanges)

        store.send(.creatorDraftApplied(try plan("Saved author").items))
        await store.send(.saveRequest) {
            _ = await SaveHelper.save(store).result
        }
        #expect(!store.unsavedChanges)
        #expect(store.creatorSaveResults[image.id] == .saved)
        #expect(try Exiftool.helper.metadataTags([.creator], from: imageURL)[.creator]
                == .list(["Saved author"]))

        store.send(.creatorDraftApplied(try plan("Pending author").items))
        _ = try Exiftool.helper.update(image: imageURL,
                                      changes: [.creator: .set(.list(["External author"]))])
        await store.send(.saveRequest) {
            _ = await SaveHelper.save(store).result
        }
        #expect(store.unsavedChanges)
        #expect(store[image.id].creatorDraft != nil)
        #expect(store.creatorSaveResults[image.id] == .staleSource)
        #expect(try Exiftool.helper.metadataTags([.creator], from: imageURL)[.creator]
                == .list(["External author"]))

        store.send(.creatorDraftRemoved(image.id))
        store.send(.creatorDraftApplied(try plan("Unknown author").items))
        store.send(.creatorSaveResult(image.id, .resultUnknown), undoable: false)
        let beforeUnknownRetry = try Data(contentsOf: imageURL)
        await store.send(.saveRequest) {
            _ = await SaveHelper.save(store).result
        }
        #expect(try Data(contentsOf: imageURL) == beforeUnknownRetry)
        #expect(store.creatorSaveResults[image.id] == .resultUnknown)
        #expect(store[image.id].creatorDraft != nil && store.unsavedChanges)

        store.send(.selectionChanged([image.id]))
        store.send(.locationChanged(Coords(latitude: 31.23, longitude: 121.48)))
        #expect(SaveTargets(images: store.imageData).conflicts == [0])
        #expect(!SaveHelper.requestSave(store))
        #expect(!store.saveInProgress && store.unsavedChanges)
        #expect(store[image.id].creatorDraft != nil)
        store.send(.creatorDraftRemoved(image.id))
        #expect(store[image.id].creatorDraft == nil && store.creatorSaveResults[image.id] == nil)
        #expect(store.unsavedChanges)
    }

    @Test func cancelSaveSummaryIncludesBothPagesAndUnselectedPhotos() throws {
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
        let source = try #require(PhotoTrailState(forPreview: true).imageData.compactMap { image -> URL? in
            guard case .image(let url) = image.metadata.source, url.pathExtension.lowercased() == "jpg" else { return nil }
            return url
        }.first)
        let creator = ImageData(metadata: Exiftool.helper.metadata(from: nil, primaryURL: source), name: source.lastPathComponent)
        let snapshot = try MetadataInspectionSnapshot.read([.creator], from: source)
        let plan = try MetadataCreatorEditPlan.prepare([(image: creator, snapshot: snapshot)], action: .set(["Unsaved test author"]))
        var state = PhotoTrailState()
        state.imageData = [changed, unchanged, creator]
        state.selection = [unchanged.id]
        state.unsavedChanges = true
        let store = Store(initialState: state, reduce: PhotoTrailReducer())
        store.send(.creatorDraftApplied(plan.items))
        var prompted = false

        let started = SaveHelper.requestSave(store) { targets in
            prompted = true
            #expect(targets.total == 2)
            #expect(targets.xmp == [0])
            #expect(targets.creator == [2])
            #expect(targets.files.isEmpty && targets.library.isEmpty)
            return false
        }

        #expect(prompted)
        #expect(!started)
        #expect(!store.saveInProgress)
        #expect(store.unsavedChanges)
        #expect(store.saveTotal == 0)
        #expect(store[creator.id].creatorDraft != nil)
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
