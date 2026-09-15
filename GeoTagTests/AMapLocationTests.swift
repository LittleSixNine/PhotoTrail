import Coords
import ImageData
import Testing
import UDF
@testable import GeoTag

@MainActor
struct AMapLocationTests {
    @Test func confirmedLocationMarksDatumAndUndoRestoresOriginal() throws {
        var state = GeoTagState(forPreview: true)
        let image = try #require(state.imageData.first(where: { $0.updatable }))
        state.selection = [image.id]
        let store = Store(initialState: state, reduce: GeoTagReducer(), undoEnabled: true)
        let original = store[image.id].metadata
        store.send(.confirmedWGS84Location(Coords(latitude: 31.23, longitude: 121.48)))
        #expect(store[image.id].metadata.gpsMapDatum == "WGS-84")
        #expect(store[image.id].metadata.gpsProcessingMethod == "MANUAL")
        #expect(store.unsavedChanges)
        store.undo()
        #expect(store[image.id].metadata == original)
        store.redo()
        #expect(store[image.id].metadata.gpsMapDatum == "WGS-84")
        #expect(store[image.id].metadata.location == Coords(latitude: 31.23, longitude: 121.48))
    }

    @Test func savingRejectsNewMapResult() {
        var state = GeoTagState()
        state.saveInProgress = true
        let store = Store(initialState: state, reduce: GeoTagReducer())
        let version = store.version
        store.send(.confirmedWGS84Location(Coords(latitude: 31.23, longitude: 121.48)))
        #expect(store.version == version)
        #expect(!store.unsavedChanges)
    }
}
