import Coords
import MapKit
import SwiftUI
import UDF

struct SearchView: View {
    @Environment(Store<GeoTagState, GeoTagEvent>.self) private var store
    @Environment(LocationWorkspace.self) private var workspace
    @AppStorage("GeoTagCNMapProvider") private var provider = "amap"
    var mapFocus: FocusState<MapWithSearchView.MapFocus?>.Binding
    @Binding var searchInfo: MapWithSearchView.SearchInfo
    @State private var query = ""
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var expandedWidth: CGFloat = 360
    @State private var searching = false
    @State private var error: String?

    private var editable: Bool {
        !store.saveInProgress && !store.selection.isEmpty && store.selection.allSatisfy { store[$0].updatable }
    }

    private var resultCount: Int {
        provider == "amap" ? workspace.results.count : searchInfo.searchResponse.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if expanded && !query.isEmpty {
                resultsPanel
                    .padding(12)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
            }
            HStack(spacing: 0) {
                Button {
                    expanded = true
                    mapFocus.wrappedValue = .search
                } label: {
                    Image(systemName: "magnifyingglass")
                        .frame(width: 44, height: 44)
                }.buttonStyle(.plain).help("搜索地点")
                    .accessibilityLabel("展开地点搜索")
                if expanded {
                    TextField("搜索地点", text: $query)
                        .textFieldStyle(.plain)
                        .focused(mapFocus, equals: .search)
                        .disabled(provider == "amap" && !workspace.ready)
                        .transition(.opacity)
                    Button {
                        expanded = false
                        query = ""
                        mapFocus.wrappedValue = nil
                    } label: {
                        Image(systemName: "xmark").frame(width: 40, height: 44)
                    }.buttonStyle(.plain).help("收起搜索")
                        .accessibilityLabel("收起地点搜索")
                        .transition(.opacity)
                }
            }
            .frame(width: expanded ? expandedWidth : 44, height: 44, alignment: .leading)
            .clipShape(Capsule())
            .glassEffect(.regular.interactive(), in: Capsule())
            .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: expanded)
        }
        .buttonStyle(.bordered)
        .onChange(of: mapFocus.wrappedValue) {
            store.send(.textfieldFocusChanged(mapFocus.wrappedValue == .search), undoable: false)
        }
        .onChange(of: store.mapSearchActive) {
            if store.mapSearchActive { expanded = true; mapFocus.wrappedValue = .search }
        }
        .onChange(of: provider) { query = "" }
        .onDisappear { store.send(.textfieldFocusChanged(false), undoable: false) }
        .task(id: "\(provider):\(workspace.ready):\(query)") {
            workspace.invalidateSelection?()
            workspace.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
            workspace.results = []
            workspace.selectedResult = nil
            workspace.searching = false
            searchInfo.searchResponse = []
            searchInfo.selection = nil
            searching = false
            error = nil
            let current = workspace.query
            guard !current.isEmpty else { return }
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            if provider == "amap" {
                if workspace.ready { workspace.search?(current) }
            } else {
                searching = true
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = current
                do {
                    let response = try await MKLocalSearch(request: request).start()
                    guard !Task.isCancelled else { return }
                    searchInfo.searchResponse = response.mapItems.map { Place(from: $0) }
                    if searchInfo.searchResponse.isEmpty { error = "未找到地点，请补充城市或名称。" }
                } catch {
                    guard !Task.isCancelled else { return }
                    self.error = "搜索失败，请检查网络后重试。"
                }
                searching = false
            }
        }
    }

    private var resultsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
                if searching || workspace.searching { ProgressView("搜索中…").controlSize(.small) }
                if let error { Text(error).font(.caption).foregroundStyle(.secondary) }
                if resultCount > 0 {
                    ScrollView {
                        VStack(spacing: 4) {
                            if provider == "amap" {
                                ForEach(workspace.results) { result in
                                    resultButton(result.name, subtitle: result.address,
                                                 selected: workspace.selectedResult?.id == result.id) {
                                        workspace.selectedResult = result
                                        workspace.previewSearch?(result)
                                    }
                                }
                            } else {
                                ForEach(searchInfo.searchResponse) { place in
                                    resultButton(shortName(place), subtitle: region(place),
                                                 selected: searchInfo.selection?.id == place.id) {
                                        searchInfo.selection = place
                                        workspace.preview(MapCoordinate(latitude: place.coordinate.latitude,
                                                                        longitude: place.coordinate.longitude))
                                        searchInfo.recenterLocation = place.coordinate.coord2D
                                    }
                                }
                            }
                        }
                    }.frame(height: min(CGFloat(resultCount) * 58, 250))
                }
                if provider == "amap", let result = workspace.selectedResult {
                    HStack {
                        Button("应用到照片") { workspace.chooseSearch?(result, "apply") }
                            .disabled(!editable || !workspace.ready)
                        Button("收藏地点") { workspace.chooseSearch?(result, "favorite") }
                    }
                } else if let place = searchInfo.selection {
                    Button("应用到照片") {
                        store.send(.placeSelection(place))
                        store.send(.locationChanged(place.coordinate.coord2D), description: "search selection")
                    }.disabled(!editable)
                }
        }.frame(width: expandedWidth - 24)
    }

    private func resultButton(_ name: String, subtitle: String, selected: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.system(size: 13)).foregroundStyle(.primary).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                .background(selected ? Color.blue.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain)
    }

    private func shortName(_ place: Place) -> String {
        var name = place.name
        for suffix in [place.country, place.state, place.city].compactMap({ $0 })
            where name.hasSuffix(", " + suffix) {
            name.removeLast(suffix.count + 2)
        }
        return name
    }

    private func region(_ place: Place) -> String {
        var parts: [String] = []
        for part in [place.city, place.state, place.country].compactMap({ $0 }) where !parts.contains(part) {
            parts.append(part)
        }
        return parts.joined(separator: " · ")
    }
}
