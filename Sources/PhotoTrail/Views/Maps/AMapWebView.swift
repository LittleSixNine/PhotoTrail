import Coords
import GpxTrackLog
import SwiftUI
import WebKit

// The representable and its WebKit coordinator intentionally share lifecycle state.
// swiftlint:disable type_body_length
struct AMapWebView: NSViewRepresentable {
    let snapshot: AMapSnapshot
    let credentials: AMapCredentials
    let startupCoordinate: MapCoordinate?
    var deviceCoordinate: MapCoordinate?
    var deviceFocusID: UUID?
    let trackRevision: Int
    let fitRevision: Int
    let mapStyle: AMapStyleName
    let trackColor: String
    let trackWidth: Double
    let onMapTap: () -> Void
    let onPick: (Int?, MapCoordinate) -> Void
    let workspace: LocationWorkspace

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.addUserScript(WKUserScript(
            source: L10n.mapScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController.add(context.coordinator, name: "photoTrail")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.underPageBackgroundColor = .windowBackgroundColor
        // WebKit skips equal inset values. Establish an explicit value before zeroing
        // to disable its automatic titlebar inset, including before window attachment.
        view.obscuredContentInsets = NSEdgeInsets(top: 1, left: 0, bottom: 0, right: 0)
        view.obscuredContentInsets = .init()
        view.navigationDelegate = context.coordinator
        context.coordinator.browserView = view
        context.coordinator.connect()
        if let url = Bundle.main.url(forResource: "AMap", withExtension: "html") {
            context.coordinator.pageURL = url
            view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            context.coordinator.report(L10n.text("地图页面缺失，请重新构建应用。"))
        }
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        let changed = context.coordinator.parent.snapshot != snapshot
        let startupChanged = context.coordinator.parent.startupCoordinate != startupCoordinate
        let deviceChanged = context.coordinator.parent.deviceCoordinate != deviceCoordinate
        let deviceFocusChanged = context.coordinator.parent.deviceFocusID != deviceFocusID
        let tracksChanged = context.coordinator.parent.trackRevision != trackRevision
        let mapStyleChanged = context.coordinator.parent.mapStyle != mapStyle
        let styleChanged = context.coordinator.parent.trackColor != trackColor
            || context.coordinator.parent.trackWidth != trackWidth
        context.coordinator.parent = self
        if changed { context.coordinator.updateSnapshot() }
        if startupChanged {
            if startupCoordinate == nil { context.coordinator.cancelStartupCoordinate() }
            else { context.coordinator.focusStartupCoordinate() }
        }
        if deviceChanged || deviceFocusChanged {
            context.coordinator.updateDeviceLocation(focus: deviceFocusChanged && deviceCoordinate != nil)
        }
        if mapStyleChanged { context.coordinator.updateMapStyle() }
        if styleChanged { context.coordinator.updateTrackStyle() }
        if tracksChanged { context.coordinator.updateTracks() }
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.disposed = true
        let workspace = coordinator.parent.workspace
        // A replacement can connect before SwiftUI dismantles the previous map.
        // Only the current connection may clear the shared callbacks and overlays.
        if workspace.amapConnectionID == coordinator.connectionID {
            workspace.amapConnectionID = nil
            workspace.amapPhotoPositions = []
            workspace.amapPhotoEdges = []
            workspace.moveAMapPhoto = nil
            workspace.focusPhoto = nil
            workspace.zoomAMap = nil
        }
        view.stopLoading()
        view.configuration.userContentController.removeScriptMessageHandler(forName: "photoTrail")
        view.navigationDelegate = nil
        // Discard the JS context so an in-flight conversion cannot start another batch.
        view.loadHTMLString("", baseURL: nil)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: AMapWebView
        let connectionID = UUID()
        weak var browserView: WKWebView?
        var pageURL: URL?
        var disposed = false
        private var ready = false
        private var pickSequence = 0
        private var activeTracks: [String: Int] = [:]
        private var fittedRevision = -1
        private var fittedVersion: String?
        private var sentPhotos: [AMapPhoto]?
        private static let lastLatitudeKey = "PhotoTrailAMapLastMapLatitude"
        private static let lastLongitudeKey = "PhotoTrailAMapLastMapLongitude"
        private static let lastZoomKey = "PhotoTrailAMapLastMapZoom"

        init(_ parent: AMapWebView) { self.parent = parent }

        private var searchSequence = 0
        private var validationGeneration = 0

        func connect() {
            parent.workspace.amapConnectionID = connectionID
            parent.workspace.amapNavigation = { [weak self] command in
                guard let self, !disposed, ready else { return }
                browserView?.callAsyncJavaScript("window.photoTrail.navigate(command);",
                    arguments: ["command": command], in: nil, in: .page) { _ in }
            }
            parent.workspace.lookupAMapRegion = { [weak self] point in
                guard let self, !disposed, ready, let browserView else { throw URLError(.notConnectedToInternet) }
                let name: String = try await withCheckedThrowingContinuation { continuation in
                    browserView.callAsyncJavaScript("return await window.photoTrail.region(point);",
                        arguments: ["point": ["latitude": point.latitude, "longitude": point.longitude]],
                        in: nil, in: .page) { result in
                        switch result {
                        case .success(let value):
                            guard let name = value as? String, !name.isEmpty else {
                                continuation.resume(throwing: URLError(.badServerResponse))
                                return
                            }
                            continuation.resume(returning: name)
                        case .failure(let error): continuation.resume(throwing: error)
                        }
                    }
                }
                guard !disposed else { throw CancellationError() }
                return name
            }
            parent.workspace.setSatellite = { [weak self] enabled in
                guard let self, !disposed, ready else { return }
                browserView?.callAsyncJavaScript("window.photoTrail.setSatellite(enabled);",
                    arguments: ["enabled": enabled], in: nil, in: .page) { _ in }
            }
            parent.workspace.invalidateSelection = { [weak self] in
                guard let self, !disposed else { return }
                validationGeneration += 1
                browserView?.callAsyncJavaScript("window.photoTrail.clearPreview();", in: nil, in: .page) { _ in }
            }
            parent.workspace.search = { [weak self] query in self?.search(query) }
            parent.workspace.previewSearch = { [weak self] result in
                self?.preview(result.coordinate, wgs84: false, name: result.name)
            }
            parent.workspace.previewWGS84 = { [weak self] point in
                guard let self else { return }
                self.preview(point, wgs84: true, name: self.parent.workspace.previewName)
            }
            parent.workspace.moveAMapPhoto = { [weak self] id, point in
                guard let self, !disposed, ready, parent.snapshot.allowDragPin else { return }
                browserView?.callAsyncJavaScript("window.photoTrail.pickPhotoAt(id, point);",
                    arguments: ["id": id, "point": ["x": point.x, "y": point.y]],
                    in: nil, in: .page) { _ in }
            }
            parent.workspace.focusPhoto = { [weak self] id in
                guard let self, !disposed, ready else { return }
                browserView?.callAsyncJavaScript("window.photoTrail.focusPhoto(id);",
                    arguments: ["id": id], in: nil, in: .page) { _ in }
            }
            parent.workspace.zoomAMap = { [weak self] steps, point in
                guard let self, !disposed, ready else { return }
                browserView?.callAsyncJavaScript("window.photoTrail.zoomByWheel(steps, point);",
                    arguments: ["steps": steps, "point": ["x": point.x, "y": point.y]],
                    in: nil, in: .page) { _ in }
            }
            parent.workspace.chooseSearch = { [weak self] result, purpose in
                guard let self, !disposed, ready else { return }
                browserView?.callAsyncJavaScript(
                    "return await window.photoTrail.selectSearch(point, purpose, name);",
                    arguments: ["point": ["latitude": result.coordinate.latitude,
                                          "longitude": result.coordinate.longitude],
                                "purpose": purpose, "name": result.name], in: nil, in: .page) { _ in }
            }
        }

        private func preview(_ point: MapCoordinate, wgs84: Bool, name: String) {
            validationGeneration += 1
            guard !disposed, ready else { return }
            browserView?.callAsyncJavaScript("return await window.photoTrail.preview(point, wgs84, name);",
                arguments: ["point": ["latitude": point.latitude, "longitude": point.longitude],
                            "wgs84": wgs84, "name": name], in: nil, in: .page) { _ in }
        }

        func updateDeviceLocation(focus: Bool = false) {
            guard ready, !disposed, let point = parent.deviceCoordinate, point.isValid else { return }
            browserView?.callAsyncJavaScript("return await window.photoTrail.setDeviceLocation(point, focus);",
                arguments: ["point": ["latitude": point.latitude, "longitude": point.longitude],
                            "focus": focus], in: nil, in: .page) { _ in }
        }

        private func search(_ query: String) {
            guard !disposed, ready, !query.isEmpty else { return }
            searchSequence += 1
            let request = searchSequence
            parent.workspace.searching = true
            browserView?.callAsyncJavaScript("return await window.photoTrail.search(query);",
                arguments: ["query": query], in: nil, in: .page) { [weak self] response in
                guard let self, !disposed, request == searchSequence,
                      query == parent.workspace.query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
                parent.workspace.searching = false
                guard case .success(let value) = response, let rows = value as? [[String: Any]] else {
                    parent.workspace.results = []
                    report(L10n.text("搜索失败，请检查网络或服务配额。"))
                    return
                }
                parent.workspace.results = rows.compactMap { row in
                    guard let id = row["id"] as? String, let name = row["name"] as? String,
                          let latitude = row["latitude"] as? Double,
                          let longitude = row["longitude"] as? Double else { return nil }
                    let point = MapCoordinate(latitude: latitude, longitude: longitude)
                    guard point.isValid else { return nil }
                    return AMapSearchResult(id: id, name: name, address: row["address"] as? String ?? "",
                                            coordinate: point)
                }
                report(parent.workspace.results.isEmpty ? L10n.text("没有找到地点，请补充城市或详细名称。") : L10n.text("选择搜索结果可预览位置。"))
            }
        }

        func report(_ message: String) {
            Task { @MainActor [weak self] in
                guard let self, !disposed else { return }
                parent.workspace.status = message
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let defaults = UserDefaults.standard
            let center = MapCoordinate(latitude: defaults.double(forKey: Self.lastLatitudeKey),
                                       longitude: defaults.double(forKey: Self.lastLongitudeKey))
            let zoom = defaults.double(forKey: Self.lastZoomKey)
            let hasLast = defaults.object(forKey: Self.lastLatitudeKey) != nil
                && defaults.object(forKey: Self.lastLongitudeKey) != nil
                && center.isValid && (2...20).contains(zoom)
            let initialCenter: [Double] = hasLast ? [center.longitude, center.latitude] : [121.48, 31.23]
            let initialZoom = hasLast ? zoom : 12
            webView.callAsyncJavaScript("return await window.photoTrail.start(config);",
                                        arguments: ["config": ["key": parent.credentials.key,
                                                                "securityJsCode": parent.credentials.securityJsCode,
                                                                "preferWebGL": true,
                                                                "mapStyle": parent.mapStyle.rawValue,
                                                                "initialCenter": initialCenter,
                                                                "initialZoom": initialZoom]],
                                        in: nil, in: .page) { [weak self] result in
                guard let self, !disposed else { return }
                switch result {
                case .success:
                    ready = true
                    sentPhotos = nil
                    parent.workspace.ready = true
                    updateSnapshot()
                    updateDeviceLocation()
                    updateMapStyle()
                    updateTrackStyle()
                    updateTracks()
                    focusStartupCoordinate()

                case .failure:
                    report(L10n.text("高德地图加载失败，请检查 Key、安全密钥和网络后重新加载。"))
                }
            }
        }

        func focusStartupCoordinate() {
            guard ready, !disposed, let point = parent.startupCoordinate, point.isValid else { return }
            browserView?.callAsyncJavaScript("return await window.photoTrail.focusWGS84(point);",
                arguments: ["point": ["latitude": point.latitude, "longitude": point.longitude]],
                in: nil, in: .page) { _ in }
        }

        func cancelStartupCoordinate() {
            guard ready, !disposed else { return }
            browserView?.callAsyncJavaScript("window.photoTrail.cancelStartup();",
                in: nil, in: .page) { _ in }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url, url.scheme == "https" {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(action.request.url == pageURL ? .allow : .cancel)
        }

        func updateSnapshot() {
            struct State: Encodable {
                let revision: Int
                let point: MapCoordinate?
                let editable: Bool
                let selectedPhotoIDs: [Int]
            }
            guard ready, !disposed, let webView = browserView else { return }
            let state = State(revision: parent.snapshot.revision, point: parent.snapshot.point,
                              editable: parent.snapshot.editable,
                              selectedPhotoIDs: parent.snapshot.selectedPhotoIDs)
            guard let stateData = try? JSONEncoder().encode(state),
                  let stateValue = try? JSONSerialization.jsonObject(with: stateData) else { return }
            let photosValue: Any
            if sentPhotos != parent.snapshot.photos,
               let data = try? JSONEncoder().encode(parent.snapshot.photos),
               let value = try? JSONSerialization.jsonObject(with: data) {
                sentPhotos = parent.snapshot.photos
                photosValue = value
            } else {
                photosValue = NSNull()
            }
            webView.callAsyncJavaScript("return await window.photoTrail.updateSnapshot(snapshot, photos);",
                                        arguments: ["snapshot": stateValue, "photos": photosValue],
                                        in: nil, in: .page) { _ in }
        }

        func updateMapStyle() {
            guard ready, !disposed else { return }
            browserView?.callAsyncJavaScript("window.photoTrail.setMapStyle(style);",
                arguments: ["style": parent.mapStyle.rawValue], in: nil, in: .page) { _ in }
        }

        func updateTrackStyle() {
            guard ready, !disposed else { return }
            browserView?.callAsyncJavaScript("window.photoTrail.setTrackStyle(color, width);",
                arguments: ["color": parent.trackColor, "width": parent.trackWidth], in: nil, in: .page) { _ in }
        }

        func updateTracks() {
            guard ready, !disposed, let browserView else { return }
            let library = parent.workspace.tracks
            for (id, request) in activeTracks where library.requests[id] != request {
                browserView.callAsyncJavaScript("window.photoTrail.cancelTrack(request);",
                    arguments: ["request": request], in: nil, in: .page) { _ in }
                activeTracks.removeValue(forKey: id)
            }
            let displays = library.displays(amap: true)
            if let data = try? JSONEncoder().encode(displays),
               let records = try? JSONSerialization.jsonObject(with: data) {
                browserView.callAsyncJavaScript("window.photoTrail.renderTracks(records, selected);",
                    arguments: ["records": records, "selected": library.selected as Any? ?? NSNull()],
                    in: nil, in: .page) { _ in }
                if let selected = library.selected, let display = displays.first(where: { $0.id == selected }),
                   fittedRevision != parent.fitRevision || fittedVersion != display.version {
                    fittedRevision = parent.fitRevision
                    fittedVersion = display.version
                    browserView.callAsyncJavaScript("window.photoTrail.fitTracks(id);",
                        arguments: ["id": selected], in: nil, in: .page) { _ in }
                }
            }
            for record in library.records {
                guard record.id == library.nextRequestID,
                      let request = library.requests[record.id], activeTracks[record.id] != request,
                      let data = try? JSONEncoder().encode(record.segments),
                      let segments = try? JSONSerialization.jsonObject(with: data) else { continue }
                activeTracks[record.id] = request
                let id = record.id
                browserView.callAsyncJavaScript("return await window.photoTrail.convertTracks(segments, request);",
                    arguments: ["segments": segments, "request": request], in: nil, in: .page) { [weak self] result in
                    guard let self, !disposed, library.requests[id] == request else { return }
                    activeTracks.removeValue(forKey: id)
                    if case .success(let value) = result, let body = value as? [String: Any] {
                        if let paths = body["segments"], let data = try? JSONSerialization.data(withJSONObject: paths),
                           let converted = try? JSONDecoder().decode([[MapCoordinate]].self, from: data) {
                            library.complete(id, request: request, converted: converted)
                            return
                        }
                        if let error = body["error"] as? String {
                            library.fail(id, request: request, reason: L10n.mapError(error))
                            return
                        }
                    }
                    library.fail(id, request: request, reason: L10n.text("地图未能完成转换，请重试。"))
                }
            }
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard !disposed, message.frameInfo.isMainFrame,
                  message.frameInfo.request.url == pageURL,
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }
            if type == "tracks", ready,
               let request = body["request"] as? Int,
               let id = activeTracks.first(where: { $0.value == request })?.key,
               let completed = body["completed"] as? Int, let total = body["total"] as? Int {
                parent.workspace.tracks.progress(id, request: request, completed: completed, total: total)
                return
            }
            if type == "rendering" {
                #if DEBUG
                if let metrics = body["metrics"] as? [String: Any],
                   let data = try? JSONSerialization.data(withJSONObject: metrics, options: [.sortedKeys]) {
                    try? data.write(to: FileManager.default.temporaryDirectory
                        .appendingPathComponent("geotag-map-render.json"))
                }
                #endif
                return
            }
            if type == "heading", let heading = body["value"] as? Double, heading.isFinite {
                parent.workspace.amapHeading = heading
                return
            }
            if type == "mapClick" {
                parent.onMapTap()
                return
            }
            if type == "camera", let latitude = body["latitude"] as? Double,
               let longitude = body["longitude"] as? Double,
               let zoom = body["zoom"] as? Double,
               MapCoordinate(latitude: latitude, longitude: longitude).isValid,
               (2...20).contains(zoom) {
                let defaults = UserDefaults.standard
                defaults.set(latitude, forKey: Self.lastLatitudeKey)
                defaults.set(longitude, forKey: Self.lastLongitudeKey)
                defaults.set(zoom, forKey: Self.lastZoomKey)
                return
            }
            if type == "status", let text = body["message"] as? String {
                report(String(text.prefix(300)))
                return
            }
            if type == "photoPositions", let rows = body["positions"] as? [[String: Any]],
               rows.count <= 2_000 {
                parent.workspace.amapPhotoPositions = rows.compactMap { row in
                    let ids = (row["ids"] as? [NSNumber])?.map(\.intValue)
                        ?? row["ids"] as? [Int] ?? []
                    guard !ids.isEmpty,
                          let x = row["x"] as? Double, let y = row["y"] as? Double,
                          x.isFinite, y.isFinite else { return nil }
                    return AMapPhotoPosition(ids: ids, x: x, y: y)
                }
                let edges = body["edges"] as? [[String: Any]] ?? []
                parent.workspace.amapPhotoEdges = edges.prefix(100).compactMap { row in
                    guard let id = row["id"] as? Int,
                          let x = row["x"] as? Double, let y = row["y"] as? Double,
                          let angle = row["angle"] as? Double,
                          x.isFinite, y.isFinite, angle.isFinite else { return nil }
                    return AMapPhotoEdgePosition(id: id, x: x, y: y, angle: angle)
                }
                return
            }
            let purpose = body["purpose"] as? String ?? "apply"
            guard ["apply", "map", "favorite", "photo"].contains(purpose) else { return }
            let photoID = body["photoID"] as? Int
            let originalRow = body["originalPhotoPoint"] as? [String: Any]
            let originalPoint = originalRow.flatMap { row -> MapCoordinate? in
                guard let latitude = row["latitude"] as? Double,
                      let longitude = row["longitude"] as? Double else { return nil }
                return MapCoordinate(latitude: latitude, longitude: longitude)
            }
            let permitted = purpose == "favorite"
                || (purpose == "photo" ? photoIsCurrent(photoID, original: originalPoint)
                    : parent.snapshot.editable && (purpose != "map" || parent.snapshot.allowDoubleClick))
            if purpose == "photo", !permitted {
                report(L10n.text("照片状态已变化，请重新拖动。"))
                return
            }
            if type == "pickStarted", ready, permitted,
               let revision = body["revision"] as? Int,
               purpose == "photo" || revision == parent.snapshot.revision,
               let sequence = body["sequence"] as? Int, sequence > pickSequence {
                pickSequence = sequence
                return
            }
            guard type == "pick", ready, permitted,
                  let revision = body["revision"] as? Int,
                  purpose == "photo" || revision == parent.snapshot.revision,
                  let sequence = body["sequence"] as? Int, sequence == pickSequence,
                  let latitude = body["latitude"] as? Double,
                  let longitude = body["longitude"] as? Double,
                  let code = body["adcode"] as? String else { return }
            guard CoordinateTransform.isMainlandAdministrativeCode(code) else {
                report(L10n.text("该点不在本原型支持的大陆行政区内，未修改照片位置。"))
                return
            }
            let gcj = MapCoordinate(latitude: latitude, longitude: longitude)
            do {
                let wgs = try CoordinateTransform.gcj02ToWGS84(gcj, region: .mainlandChina)
                validate(wgs, against: gcj, revision: revision, sequence: sequence,
                         purpose: purpose, name: String((body["name"] as? String ?? "").prefix(120)),
                         photoID: photoID, originalPhotoPoint: originalPoint)
            } catch {
                report(L10n.text("坐标转换失败，未修改照片位置。"))
            }
        }

        private func photoIsCurrent(_ id: Int?, original: MapCoordinate?) -> Bool {
            guard let id, let original, original.isValid,
                  parent.snapshot.allowDragPin, parent.snapshot.selectedPhotoIDs.contains(id) else { return false }
            return parent.snapshot.photos.contains {
                $0.id == id && $0.editable && $0.point == original
            }
        }

        // swiftlint:disable:next function_parameter_count
        private func validate(_ wgs: MapCoordinate, against gcj: MapCoordinate,
                              revision: Int, sequence: Int, purpose: String, name: String,
                              photoID: Int?, originalPhotoPoint: MapCoordinate?) {
            let generation = validationGeneration
            // One official forward check of the local inverse; no iterative API probing.
            browserView?.callAsyncJavaScript("return await window.photoTrail.convertGPS(point);",
                                         arguments: ["point": ["latitude": wgs.latitude,
                                                                 "longitude": wgs.longitude]],
                                         in: nil, in: .page) { [weak self] result in
                guard let self, !disposed, sequence == pickSequence else { return }
                guard generation == validationGeneration else {
                    if purpose == "photo" { report(L10n.text("位置校验已取消，请重新拖动。")) }
                    return
                }
                guard purpose == "photo" ? photoIsCurrent(photoID, original: originalPhotoPoint)
                    : revision == parent.snapshot.revision && (purpose == "favorite"
                        || (parent.snapshot.editable
                            && (purpose != "map" || parent.snapshot.allowDoubleClick))) else {
                    if purpose == "photo" { report(L10n.text("照片状态已变化，请重新拖动。")) }
                    return
                }
                guard case .success(let value) = result,
                      let point = value as? [String: Any],
                      let latitude = point["latitude"] as? Double,
                      let longitude = point["longitude"] as? Double else {
                    report(L10n.text("高德坐标校验失败，未修改照片位置。请检查网络与服务配额。"))
                    return
                }
                let projected = MapCoordinate(latitude: latitude, longitude: longitude)
                guard projected.isValid, projected.distance(to: gcj) <= 5 else {
                    report(L10n.text("该点的转换误差超过 5 米，未修改照片位置。"))
                    return
                }
                if purpose == "favorite" {
                    parent.workspace.favoriteDraft = SavedLocation(name: name, note: "", coordinate: wgs)
                    report(L10n.text("地点已校验，可保存收藏。"))
                } else {
                    parent.onPick(photoID, wgs)
                    report(L10n.text("位置已设置，请保存照片。"))
                }
            }
        }
    }
}
// swiftlint:enable type_body_length
