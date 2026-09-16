import Coords
import Foundation
import ImageData
import Metadata
import Testing
import UDF
@testable import GeoTag

@MainActor
struct PhotoListTests {
    @Test func pairedJPEGDisplaysOnceButSavesBothFiles() {
        let base = URL(fileURLWithPath: "/tmp/paired-photo")
        let raw = ImageData(metadata: Metadata(source: .xmp(base.appendingPathExtension("DNG"))),
                            name: "paired-photo.DNG")
        let jpg = ImageData(metadata: Metadata(source: .xmp(base.appendingPathExtension("JPG"))),
                            name: "paired-photo.JPG")
        let png = ImageData(metadata: Metadata(source: .xmp(base.appendingPathExtension("PNG"))),
                            name: "paired-photo.PNG")
        var state = GeoTagState()
        state.imageData = [raw, jpg, png]
        state.selection = [raw.id]
        state.linkPairedImages()
        #expect(state.visibleImages.map(\.id) == [jpg.id, png.id])
        #expect(state.selection == [jpg.id])
        #expect(state[jpg.id].isPairedJPEG)
        #expect(state[png.id].pairedID == nil)

        state.selection = [jpg.id]
        let store = Store(initialState: state, reduce: GeoTagReducer())
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
        var state = GeoTagState()
        state.imageData = [image]
        state.selection = [image.id]
        let store = Store(initialState: state, reduce: GeoTagReducer())
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
        let track = try #require(GeoTagState(forPreview: true).gpxTracks.first)
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
        var state = GeoTagState(forPreview: true)
        let image = try #require(state.imageData.first(where: { $0.updatable }))
        state.selection = [image.id]
        state.mostSelected = image.id
        let store = Store(initialState: state, reduce: GeoTagReducer(), undoEnabled: true)
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
