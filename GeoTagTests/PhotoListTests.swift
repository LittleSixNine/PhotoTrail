import Coords
import Testing
import UDF
@testable import GeoTag

@MainActor
struct PhotoListTests {
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
