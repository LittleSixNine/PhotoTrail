import Coords
import Foundation
import Testing
@testable import PhotoTrail

@MainActor struct AMapSearchScopeTests {
    private let harbin = AMapSearchCity(name: "哈尔滨市", adcode: "230100",
                                      coordinate: MapCoordinate(latitude: 45.8, longitude: 126.53))
    private let shanghai = AMapSearchCity(name: "上海市", adcode: "310000",
                                        coordinate: MapCoordinate(latitude: 31.23, longitude: 121.48))

    @Test func freshWorkspaceUsesVisibleMapBoundsAndChangingScopeInvalidatesOldResultsImmediately() {
        let workspace = LocationWorkspace()
        #expect(workspace.searchScope == .viewport)
        workspace.results = [.init(id: "old", name: "上海结果", address: "上海",
                                   coordinate: shanghai.coordinate)]
        workspace.selectedResult = workspace.results.first
        workspace.searchError = "old error"
        workspace.searchAreaChanged = true
        let revision = workspace.searchRevision
        workspace.searchScope = .city(harbin)
        #expect(workspace.searchRevision > revision)
        #expect(workspace.results.isEmpty && workspace.selectedResult == nil)
        #expect(workspace.searchError == nil && !workspace.searchAreaChanged)
        #expect(workspace.searchScope.arguments["adcode"] as? String == "230100")
        workspace.searchScope = .viewport
        #expect(workspace.searchScope.arguments["mode"] as? String == "viewport")
    }

    @Test func cityNavigationAndRecentHistoryDoNotPersistAnActiveCityLock() throws {
        let domain = "PhotoTrail.SearchScopeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let workspace = LocationWorkspace()
        var focused: AMapSearchCity?
        workspace.focusSearchCity = { focused = $0 }
        workspace.selectSearchCity(harbin, defaults: defaults)
        workspace.selectSearchCity(shanghai, defaults: defaults)
        workspace.selectSearchCity(harbin, defaults: defaults)
        let recent = AMapSearchCity.recent(from: defaults.data(forKey: AMapSearchCity.recentKey) ?? Data())
        #expect(recent.map(\.adcode) == ["230100", "310000"])
        #expect(focused == harbin)
        #expect(workspace.searchScope == .city(harbin))
        #expect(LocationWorkspace().searchScope == .viewport)
        defaults.set(false, forKey: SettingsPreferences.recordSearchesKey)
        let previous = defaults.data(forKey: AMapSearchCity.recentKey)
        workspace.selectSearchCity(shanghai, defaults: defaults)
        #expect(defaults.data(forKey: AMapSearchCity.recentKey) == previous)
        defaults.set(Data([1]), forKey: SettingsPreferences.recentSearchesKey)
        SettingsPreferences.clearRecentSearches(in: defaults)
        #expect(defaults.data(forKey: SettingsPreferences.recentSearchesKey) == nil)
        #expect(defaults.data(forKey: AMapSearchCity.recentKey) == nil)
        #expect(workspace.searchScope == .city(shanghai))
    }

    @Test func invalidStoredCitiesCannotBecomeSearchScopesOrNavigationTargets() throws {
        let invalid = [
            AMapSearchCity(name: "全国", adcode: "100000", coordinate: harbin.coordinate),
            AMapSearchCity(name: "区县", adcode: "230102", coordinate: harbin.coordinate),
            AMapSearchCity(name: "坏码", adcode: "２３０１００", coordinate: harbin.coordinate),
            AMapSearchCity(name: "坏坐标", adcode: "230100", coordinate: MapCoordinate(latitude: 100, longitude: 0))
        ]
        #expect(invalid.allSatisfy { !$0.isValid })
        #expect(AMapSearchCity.recent(from: try JSONEncoder().encode(invalid)).isEmpty)
        let workspace = LocationWorkspace()
        workspace.focusSearchCity = { _ in Issue.record("Invalid city must not move the map") }
        workspace.selectSearchCity(invalid[0])
        #expect(workspace.searchScope == .viewport)
    }
}
