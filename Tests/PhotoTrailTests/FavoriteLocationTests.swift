import Coords
import Foundation
import ImageData
import Metadata
import Testing
import UDF
@testable import PhotoTrail

@MainActor
struct FavoriteLocationTests {
    @Test func trackMatchConfirmsFavoriteCoordinatesForPhotoAndPairAndUndoRestoresUnknown() {
        var state = PhotoTrailState()
        let first = ImageData(metadata: Metadata(source: .xmp(URL(fileURLWithPath: "/tmp/favorite-track.jpg"))),
                              name: "favorite-track.jpg")
        let second = ImageData(metadata: Metadata(source: .xmp(URL(fileURLWithPath: "/tmp/favorite-track.dng"))),
                               name: "favorite-track.dng")
        state.imageData = [first, second]
        state[first.id].pairedID = second.id
        state[second.id].pairedID = first.id
        state.trackMatches = [.init(id: first.id, timestamp: 0,
            coords: Coords(latitude: 31.2, longitude: 121.5), elevation: nil)]
        let store = Store(initialState: state, reduce: PhotoTrailReducer(), undoEnabled: true)
        store.send(.applyTrackMatches)
        for id in [first.id, second.id] {
            #expect(store[id].metadata.gpsMapDatum == "WGS-84")
            #expect(LocationHelper.favoriteCoordinate(store[id].metadata)
                == MapCoordinate(latitude: 31.2, longitude: 121.5))
        }
        store.undo()
        #expect(LocationHelper.favoriteCoordinate(store[first.id].metadata) == nil)
        #expect(LocationHelper.favoriteCoordinate(store[second.id].metadata) == nil)
    }

    @Test(arguments: ["", " ", "GCJ-02", "unknown"])
    func unconfirmedFavoriteCoordinatesRemainRejected(datum: String) {
        var metadata = Metadata(source: .xmp(URL(fileURLWithPath: "/tmp/favorite-unknown.jpg")))
        metadata.location = Coords(latitude: 31.2, longitude: 121.5)
        metadata.gpsMapDatum = datum
        #expect(LocationHelper.favoriteCoordinate(metadata) == nil)
        metadata.gpsMapDatum = nil
        #expect(LocationHelper.favoriteCoordinate(metadata) == nil)
    }

    @Test func favoritesSurviveRenameRestartAndDelete() throws {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Favorites.json")
        let first = LocationWorkspace(favoritesURL: url)
        var value = SavedLocation(name: "测试地点", note: "入口",
                                  coordinate: MapCoordinate(latitude: 31.23, longitude: 121.48))
        try first.saveFavorite(value)
        value.name = "新名称"
        value.note = "新备注"
        try first.saveFavorite(value)
        let restarted = LocationWorkspace(favoritesURL: url)
        restarted.loadFavorites()
        #expect(restarted.favorites == [value])
        try restarted.deleteFavorite(value.id)
        let final = LocationWorkspace(favoritesURL: url)
        final.loadFavorites()
        #expect(final.favorites.isEmpty)
    }

    @Test func corruptFavoritesAreNeverOverwritten() throws {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Favorites.json")
        let original = Data("invalid json".utf8)
        try original.write(to: url)
        let workspace = LocationWorkspace(favoritesURL: url)
        workspace.loadFavorites()
        #expect(workspace.favoriteError != nil)
        #expect(throws: (any Error).self) {
            try workspace.saveFavorite(SavedLocation(name: "测试", note: "",
                coordinate: MapCoordinate(latitude: 31.23, longitude: 121.48)))
        }
        #expect(try Data(contentsOf: url) == original)
    }
}
