import Coords
import Foundation
import Testing
@testable import PhotoTrail

@MainActor
struct FavoriteLocationTests {
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
