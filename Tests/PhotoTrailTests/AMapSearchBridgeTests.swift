import Coords
import Testing
import WebKit
@testable import PhotoTrail

@MainActor struct AMapSearchBridgeTests {
    private func bridge() async throws -> (LocationWorkspace, WKWebView, AMapWebView.Coordinator) {
        let workspace = LocationWorkspace()
        let parent = AMapWebView(snapshot: AMapSnapshot(revision: 0, point: nil, editable: false, photos: []),
            credentials: AMapCredentials(key: "test-only", securityJsCode: "test-only"), startupCoordinate: nil,
            trackRevision: 0, fitRevision: 0, mapStyle: .normal, trackColor: "#000000", trackWidth: 0,
            onMapTap: {}, onPick: { _, _ in Issue.record("Searching must not edit photos") }, workspace: workspace)
        let coordinator = AMapWebView.Coordinator(parent)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(coordinator, name: "photoTrail")
        let view = WKWebView(frame: .zero, configuration: configuration)
        coordinator.browserView = view
        coordinator.pageURL = URL(string: "about:blank")
        view.navigationDelegate = coordinator
        coordinator.connect()
        view.loadHTMLString("""
        <script>window.requests = []; window.photoTrail = {
          start: async () => true, updateSnapshot: async () => {},
          setMapStyle: () => {}, setTrackStyle: () => {}, renderTracks: () => {}, clearPreview: () => {},
          search: (query, scope) => new Promise(resolve => window.requests.push({ query, scope, resolve })),
          cities: async query => [{ name:'哈尔滨市', adcode:'230100', latitude:45.8, longitude:126.53 }],
          focusCity: city => { window.cityFocus = city; }
        };</script>
        """, baseURL: nil)
        for _ in 0..<100 {
            if workspace.ready { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        try #require(workspace.ready)
        return (workspace, view, coordinator)
    }

    @Test func identicalKeywordCannotAcceptLateResultsFromPreviousScope() async throws {
        let (workspace, view, coordinator) = try await bridge()
        defer { AMapWebView.dismantleNSView(view, coordinator: coordinator) }
        workspace.query = "酒店"
        workspace.search?("酒店")
        let city = AMapSearchCity(name: "哈尔滨市", adcode: "230100",
                                  coordinate: MapCoordinate(latitude: 45.8, longitude: 126.53))
        workspace.searchScope = .city(city)
        workspace.search?("酒店")
        let sent = try await view.evaluateJavaScript("JSON.stringify(window.requests.map(r=>r.scope))") as? String
        #expect(sent?.contains("230100") == true)
        _ = try await view.evaluateJavaScript("""
        window.requests[1].resolve([{id:'new',name:'哈尔滨酒店',address:'哈尔滨',latitude:45.8,longitude:126.53}]);
        """)
        for _ in 0..<100 {
            if !workspace.searching { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(workspace.results.map(\.id) == ["new"])
        _ = try await view.evaluateJavaScript("""
        window.requests[0].resolve([{id:'old',name:'上海酒店',address:'上海',latitude:31.23,longitude:121.48}]);
        """)
        try await Task.sleep(for: .milliseconds(100))
        #expect(workspace.results.map(\.id) == ["new"])
        let lookup = try #require(workspace.searchCities)
        let cities = try await lookup("哈尔")
        #expect(cities.first == city)
        workspace.selectSearchCity(city)
        let focus = try await view.evaluateJavaScript("window.cityFocus.latitude") as? Double
        #expect(focus == 45.8)
    }

    @Test func cityRowsAreNavigationOnlyAndAreaChangesDoNotAutomaticallySearch() async throws {
        let (workspace, view, coordinator) = try await bridge()
        defer { AMapWebView.dismantleNSView(view, coordinator: coordinator) }
        workspace.searchScope = .nationwide
        workspace.query = "哈尔滨"
        workspace.search?("哈尔滨")
        _ = try await view.evaluateJavaScript("""
        window.requests[0].resolve([
          {id:'city',kind:'city',name:'哈尔滨市',adcode:'230100',latitude:45.8,longitude:126.53},
          {id:'invalid',kind:'city',name:'坏城市',adcode:'bad',latitude:45.8,longitude:126.53}]);
        """)
        for _ in 0..<100 {
            if !workspace.searching { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(workspace.results.count == 1)
        #expect(workspace.results.first?.city?.adcode == "230100")
        #expect(workspace.selectedResult == nil)
        workspace.searchScope = .viewport
        _ = try await view.evaluateJavaScript("window.webkit.messageHandlers.photoTrail.postMessage({type:'searchAreaChanged'}); true;")
        for _ in 0..<100 {
            if workspace.searchAreaChanged { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(workspace.searchAreaChanged)
        let count = try await view.evaluateJavaScript("window.requests.length") as? Int
        #expect(count == 1)
    }
}
