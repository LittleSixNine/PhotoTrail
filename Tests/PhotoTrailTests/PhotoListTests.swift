import Coords
import Foundation
import ImageData
import Metadata
import Testing
import UDF
@testable import PhotoTrail

@MainActor
struct PhotoListTests {
    @Test func removeFromListPreservesFilesAndCanUndoPairedPendingEdits() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let urls = ["pair.JPG", "pair.DNG", "other.JPG"].map { folder.appendingPathComponent($0) }
        for url in urls { try Data("unchanged original".utf8).write(to: url) }
        var state = PhotoTrailState()
        state.imageData = urls.map { ImageData(metadata: Metadata(source: .xmp($0)), name: $0.lastPathComponent) }
        let ids = state.imageData.map(\.id)
        state.pairingEligibleIDs = Set(ids)
        state.linkPairedImages()
        state.selection = [ids[0], ids[2]]
        state.mostSelected = ids[0]
        let store = Store(initialState: state, reduce: PhotoTrailReducer(), undoEnabled: true)
        let point = Coords(latitude: 31.23, longitude: 121.48)
        store.send(.locationForImageChanged(ids[0], point))
        store.send(.removeImages([ids[0]]))
        #expect(store.imageData.map(\.id) == [ids[2]])
        #expect(store.selection == [ids[2]])
        #expect(store.mostSelected == ids[2])
        #expect(!store.unsavedChanges)
        for url in urls { #expect(try Data(contentsOf: url) == Data("unchanged original".utf8)) }
        store.undo()
        #expect(store.imageData.count == 3)
        #expect(store[ids[0]].metadata.location == point)
        #expect(store[ids[1]].metadata.location == point)
        #expect(store.unsavedChanges)
    }

    @Test func removingImagesIsBlockedDuringSave() {
        let image = ImageData(metadata: Metadata(source: .copy), name: "keep.jpg")
        var state = PhotoTrailState()
        state.imageData = [image]
        state.saveInProgress = true
        let result = PhotoTrailReducer().reduce(state, .removeImages([image.id]))
        #expect(result.imageData.count == 1)
    }

    @Test func unupdatableImageCanBeRemovedDirectly() {
        let image = ImageData(metadata: Metadata(source: .copy), name: "invalid-image.foo")
        #expect(!image.updatable)
        var state = PhotoTrailState()
        state.imageData = [image]

        let result = PhotoTrailReducer().reduce(state, .removeImages([image.id]))

        #expect(result.imageData.isEmpty)
    }

    @Test func clearLocationKeepsThePhotoInTheList() {
        var image = ImageData(metadata: Metadata(source: .xmp(URL(fileURLWithPath: "/tmp/clear-only.jpg"))),
                              name: "clear-only.jpg")
        image.metadata.location = Coords(latitude: 31.23, longitude: 121.48)
        var state = PhotoTrailState()
        state.imageData = [image]
        state.selection = [image.id]
        let result = PhotoTrailReducer().reduce(state, .deleteRequest)
        #expect(result.imageData.map(\.id) == [image.id])
        #expect(result[image.id].metadata.location == nil)
        #expect(result.unsavedChanges)
    }

    @Test func mapPhotoSwitchUsesSelectionWithoutChangingIt() {
        let first = ImageData(metadata: Metadata(source: .copy), name: "first.jpg")
        let second = ImageData(metadata: Metadata(source: .copy), name: "second.jpg")
        var state = PhotoTrailState()
        state.imageData = [first, second]
        state.selection = [first.id, second.id]
        state.mostSelected = second.id

        #expect(SettingsPreferences.displayedPhotos(state.visibleImages, selection: state.selection,
                                                     showAll: true).count == 2)
        #expect(SettingsPreferences.displayedPhotos(state.visibleImages, selection: [second.id],
                                                     showAll: false).map(\.id) == [second.id])
        #expect(SettingsPreferences.displayedPhotos(state.visibleImages, selection: [],
                                                     showAll: false).isEmpty)
        #expect(state.selection.count == 2)
    }

    @Test func pairingOnlyLinksEligibleImports() {
        let base = URL(fileURLWithPath: "/tmp/independent-photo")
        let raw = ImageData(metadata: Metadata(source: .xmp(base.appendingPathExtension("DNG"))),
                            name: "independent-photo.DNG")
        let jpg = ImageData(metadata: Metadata(source: .xmp(base.appendingPathExtension("JPG"))),
                            name: "independent-photo.JPG")
        var state = PhotoTrailState()
        state.imageData = [raw, jpg]
        state.pairingEligibleIDs = [jpg.id]
        state.linkPairedImages()
        #expect(state.visibleImages.map(\.id) == [raw.id, jpg.id])
        state.pairingEligibleIDs = [raw.id, jpg.id]
        state.linkPairedImages()
        #expect(state.visibleImages.map(\.id) == [jpg.id])
    }

    @Test func pairedJPEGDisplaysOnceButSavesBothFiles() {
        let base = URL(fileURLWithPath: "/tmp/paired-photo")
        let raw = ImageData(metadata: Metadata(source: .xmp(base.appendingPathExtension("DNG"))),
                            name: "paired-photo.DNG")
        let jpg = ImageData(metadata: Metadata(source: .xmp(base.appendingPathExtension("JPG"))),
                            name: "paired-photo.JPG")
        let png = ImageData(metadata: Metadata(source: .xmp(base.appendingPathExtension("PNG"))),
                            name: "paired-photo.PNG")
        var state = PhotoTrailState()
        state.imageData = [raw, jpg, png]
        state.selection = [raw.id]
        state.linkPairedImages()
        #expect(state.visibleImages.map(\.id) == [jpg.id, png.id])
        #expect(state.selection == [jpg.id])
        #expect(state[jpg.id].isPairedJPEG)
        #expect(state[png.id].pairedID == nil)

        state.selection = [jpg.id]
        let store = Store(initialState: state, reduce: PhotoTrailReducer())
        store.send(.selectionChanged([raw.id]))
        #expect(store.selection == [jpg.id])
        let coordinate = Coords(latitude: 31.23, longitude: 121.48)
        store.send(.locationForImageChanged(jpg.id, coordinate))
        #expect(store[raw.id].metadata.location == coordinate)
        #expect(store[jpg.id].metadata.location == coordinate)
        store.send(.newTimestamp(Date(timeIntervalSince1970: 1_000_000), 0))
        #expect(store[raw.id].metadata.dateTimeCreated == store[jpg.id].metadata.dateTimeCreated)
        store.send(.saveRequest)
        #expect(store.saveTotal == 2)
    }

    @Test func manualMapLocationShowsPendingThenSavedStatus() {
        let image = ImageData(metadata: Metadata(source: .xmp(URL(fileURLWithPath: "/tmp/map-photo.xmp"))),
                              name: "map-photo.jpg")
        var state = PhotoTrailState()
        state.imageData = [image]
        state.selection = [image.id]
        let store = Store(initialState: state, reduce: PhotoTrailReducer())
        let coordinate = Coords(latitude: 31.23, longitude: 121.48)

        store.send(.locationForImageChanged(image.id, coordinate))
        #expect(store[image.id].hasPendingLocationChanges)
        #expect(!store.locationSavedPhotoIDs.contains(image.id))

        store.send(.saveRequest)
        #expect(store.saveTotal == 1)
        store.send(.locationForImageChanged(image.id, Coords(latitude: 32, longitude: 122)))
        #expect(store[image.id].metadata.location == coordinate)
        let mapRevision = store.mapRevision
        store.send(.saveProgress(1))
        #expect(store.saveCompleted == 1)
        #expect(store.mapRevision == mapRevision)
        store.send(.imageSaved(image.id, store[image.id].metadata))
        store.send(.saveComplete(.saveOK))
        #expect(store.mapRevision > mapRevision)
        #expect(!store[image.id].hasPendingLocationChanges)
        #expect(store.locationSavedPhotoIDs.contains(image.id))
    }

    @Test func selectsPhotosWithinTrackRecordTime() throws {
        let track = try #require(PhotoTrailState(forPreview: true).gpxTracks.first)
        var inside = Metadata(source: .xmp(URL(fileURLWithPath: "/tmp/inside.xmp")))
        inside.dateTimeCreated = "2015:11:12 16:08:43"
        var outside = Metadata(source: .xmp(URL(fileURLWithPath: "/tmp/outside.xmp")))
        outside.dateTimeCreated = "2014:11:12 16:08:43"
        let first = ImageData(metadata: inside, name: "inside.jpg")
        let second = ImageData(metadata: outside, name: "outside.jpg")
        #expect(LocationHelper.photoIDs(in: [first, second], timeZone: TimeZone(secondsFromGMT: 0)!,
                                         tracks: [track]) == [first.id])
    }

    @Test func statusAndFiltersFollowEditsUndoAndSave() throws {
        var state = PhotoTrailState(forPreview: true)
        let image = try #require(state.imageData.first(where: { $0.updatable }))
        state.selection = [image.id]
        state.mostSelected = image.id
        let store = Store(initialState: state, reduce: PhotoTrailReducer(), undoEnabled: true)
        #expect(!store[image.id].hasPendingChanges)
        store.send(.confirmedWGS84Location(Coords(latitude: 31.23, longitude: 121.48)))
        #expect(PhotoListFilter.pending.includes(store[image.id]))
        #expect(PhotoListFilter.located.includes(store[image.id]))
        #expect(!PhotoListFilter.unlocated.includes(store[image.id]))
        store.undo()
        #expect(!store[image.id].hasPendingChanges)
        store.redo()
        var saved = store[image.id]
        saved.original = saved.metadata
        #expect(!saved.hasPendingChanges)
        saved.metadata.location = nil
        #expect(PhotoListFilter.unlocated.includes(saved))
        #expect(saved.hasPendingChanges)
        saved.original = saved.metadata
        #expect(!saved.hasPendingChanges)
        #expect(PhotoListFilter.unlocated.includes(saved))
    }
}
