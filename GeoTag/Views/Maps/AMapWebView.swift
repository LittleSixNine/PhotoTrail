import Coords
import SwiftUI
import WebKit

struct AMapWebView: NSViewRepresentable {
    let snapshot: AMapSnapshot
    let credentials: AMapCredentials
    let onPick: (MapCoordinate) -> Void
    let workspace: LocationWorkspace

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(context.coordinator, name: "geoTag")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        context.coordinator.browserView = view
        context.coordinator.connect()
        if let url = Bundle.main.url(forResource: "AMap", withExtension: "html") {
            context.coordinator.pageURL = url
            view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            context.coordinator.report("地图页面缺失，请重新构建应用。")
        }
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        let changed = context.coordinator.parent.snapshot != snapshot
        context.coordinator.parent = self
        if changed { context.coordinator.updateSnapshot() }
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.disposed = true
        view.stopLoading()
        view.configuration.userContentController.removeScriptMessageHandler(forName: "geoTag")
        view.navigationDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: AMapWebView
        weak var browserView: WKWebView?
        var pageURL: URL?
        var disposed = false
        private var ready = false
        private var pickSequence = 0

        init(_ parent: AMapWebView) { self.parent = parent }

        private var searchSequence = 0
        private var validationGeneration = 0

        func connect() {
            parent.workspace.invalidateSelection = { [weak self] in
                guard let self, !disposed else { return }
                validationGeneration += 1
                browserView?.callAsyncJavaScript("window.geoTag.clearPreview();", in: nil, in: .page) { _ in }
            }
            parent.workspace.search = { [weak self] query in self?.search(query) }
            parent.workspace.previewSearch = { [weak self] result in
                self?.preview(result.coordinate, wgs84: false)
            }
            parent.workspace.previewWGS84 = { [weak self] point in self?.preview(point, wgs84: true) }
            parent.workspace.chooseSearch = { [weak self] result, purpose in
                guard let self, !disposed, ready else { return }
                browserView?.callAsyncJavaScript(
                    "return await window.geoTag.selectSearch(point, purpose, name);",
                    arguments: ["point": ["latitude": result.coordinate.latitude,
                                          "longitude": result.coordinate.longitude],
                                "purpose": purpose, "name": result.name], in: nil, in: .page) { _ in }
            }
        }

        private func preview(_ point: MapCoordinate, wgs84: Bool) {
            validationGeneration += 1
            guard !disposed, ready else { return }
            browserView?.callAsyncJavaScript("return await window.geoTag.preview(point, wgs84);",
                arguments: ["point": ["latitude": point.latitude, "longitude": point.longitude],
                            "wgs84": wgs84], in: nil, in: .page) { _ in }
        }

        private func search(_ query: String) {
            guard !disposed, ready, !query.isEmpty else { return }
            searchSequence += 1
            let request = searchSequence
            parent.workspace.searching = true
            browserView?.callAsyncJavaScript("return await window.geoTag.search(query);",
                arguments: ["query": query], in: nil, in: .page) { [weak self] response in
                guard let self, !disposed, request == searchSequence,
                      query == parent.workspace.query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
                parent.workspace.searching = false
                guard case .success(let value) = response, let rows = value as? [[String: Any]] else {
                    parent.workspace.results = []
                    report("搜索失败，请检查网络或服务配额。")
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
                report(parent.workspace.results.isEmpty ? "没有找到地点，请补充城市或详细名称。" : "选择搜索结果可预览位置。")
            }
        }

        func report(_ message: String) {
            Task { @MainActor [weak self] in
                guard let self, !disposed else { return }
                parent.workspace.status = message
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.callAsyncJavaScript("return await window.geoTag.start(config);",
                                        arguments: ["config": ["key": parent.credentials.key,
                                                                "securityJsCode": parent.credentials.securityJsCode]],
                                        in: nil, in: .page) { [weak self] result in
                guard let self, !disposed else { return }
                switch result {
                case .success:
                    ready = true
                    parent.workspace.ready = true
                    updateSnapshot()
                case .failure:
                    report("高德地图加载失败，请检查 Key、安全密钥和网络后重新加载。")
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url, url.scheme == "https" {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(action.request.url == pageURL ? .allow : .cancel)
        }

        func updateSnapshot() {
            guard ready, !disposed, let webView = browserView,
                  let data = try? JSONEncoder().encode(parent.snapshot),
                  let value = try? JSONSerialization.jsonObject(with: data) else { return }
            webView.callAsyncJavaScript("return await window.geoTag.updateSnapshot(snapshot);",
                                        arguments: ["snapshot": value], in: nil, in: .page) { _ in }
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard !disposed, message.frameInfo.isMainFrame,
                  message.frameInfo.request.url == pageURL,
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }
            if type == "status", let text = body["message"] as? String {
                report(String(text.prefix(300)))
                return
            }
            let purpose = body["purpose"] as? String ?? "apply"
            guard purpose == "apply" || purpose == "favorite" else { return }
            let permitted = purpose == "favorite" || parent.snapshot.editable
            if type == "pickStarted", ready, permitted,
               let revision = body["revision"] as? Int, revision == parent.snapshot.revision,
               let sequence = body["sequence"] as? Int, sequence > pickSequence {
                pickSequence = sequence
                return
            }
            guard type == "pick", ready, permitted,
                  let revision = body["revision"] as? Int, revision == parent.snapshot.revision,
                  let sequence = body["sequence"] as? Int, sequence == pickSequence,
                  let latitude = body["latitude"] as? Double,
                  let longitude = body["longitude"] as? Double,
                  let code = body["adcode"] as? String else { return }
            guard CoordinateTransform.isMainlandAdministrativeCode(code) else {
                report("该点不在本原型支持的大陆行政区内，未修改照片位置。")
                return
            }
            let gcj = MapCoordinate(latitude: latitude, longitude: longitude)
            do {
                let wgs = try CoordinateTransform.gcj02ToWGS84(gcj, region: .mainlandChina)
                validate(wgs, against: gcj, revision: revision, sequence: sequence,
                         purpose: purpose, name: String((body["name"] as? String ?? "").prefix(120)))
            } catch {
                report("坐标转换失败，未修改照片位置。")
            }
        }

        // swiftlint:disable:next function_parameter_count
        private func validate(_ wgs: MapCoordinate, against gcj: MapCoordinate,
                              revision: Int, sequence: Int, purpose: String, name: String) {
            let generation = validationGeneration
            // One official forward check of the local inverse; no iterative API probing.
            browserView?.callAsyncJavaScript("return await window.geoTag.convertGPS(point);",
                                         arguments: ["point": ["latitude": wgs.latitude,
                                                                 "longitude": wgs.longitude]],
                                         in: nil, in: .page) { [weak self] result in
                guard let self, !disposed, generation == validationGeneration, sequence == pickSequence,
                      revision == parent.snapshot.revision,
                      purpose == "favorite" || parent.snapshot.editable else { return }
                guard case .success(let value) = result,
                      let point = value as? [String: Any],
                      let latitude = point["latitude"] as? Double,
                      let longitude = point["longitude"] as? Double else {
                    report("高德坐标校验失败，未修改照片位置。请检查网络与服务配额。")
                    return
                }
                let projected = MapCoordinate(latitude: latitude, longitude: longitude)
                guard projected.isValid, projected.distance(to: gcj) <= 5 else {
                    report("该点的转换误差超过 5 米，未修改照片位置。")
                    return
                }
                if purpose == "favorite" {
                    parent.workspace.favoriteDraft = SavedLocation(name: name, note: "", coordinate: wgs)
                    report("地点已校验，可保存收藏。")
                } else {
                    parent.onPick(wgs)
                    report("位置已设置，请保存照片。")
                }
            }
        }
    }
}
