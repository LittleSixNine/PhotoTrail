import Coords
import MapKit
import SwiftUI
import UDF

struct SearchView: View {
    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) private var store
    @Environment(LocationWorkspace.self) private var workspace
    @AppStorage("PhotoTrailMapProvider") private var provider = "amap"
    var mapFocus: FocusState<MapWithSearchView.MapFocus?>.Binding
    @Binding var searchInfo: MapWithSearchView.SearchInfo
    @Binding var expanded: Bool
    @AppStorage(SettingsPreferences.recordSearchesKey) private var recordSearches = true
    @AppStorage(SettingsPreferences.recentSearchesKey) private var recentSearchesData = Data()
    @State private var query = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var expandedWidth: CGFloat = 360
    @State private var searching = false
    @State private var error: String?
    @State private var choosingCity = false

    private var editable: Bool {
        !store.saveInProgress && !store.selection.isEmpty && store.selection.allSatisfy { store[$0].updatable }
    }

    private var resultCount: Int {
        provider == "amap" ? workspace.results.count : searchInfo.searchResponse.count
    }

    private var recentSearches: [String] {
        (try? JSONDecoder().decode([String].self, from: recentSearchesData)) ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if expanded && provider == "amap" && workspace.searchScope == .viewport
                && workspace.searchAreaChanged && !query.isEmpty {
                Button(L10n.text("搜索此区域"), systemImage: "arrow.clockwise") {
                    workspace.searchRefresh += 1
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("amapSearchThisArea")
            }
            if expanded && !query.isEmpty {
                resultsPanel
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
            if recordSearches && expanded && query.isEmpty && !recentSearches.isEmpty {
                HStack(spacing: 6) {
                    ForEach(recentSearches, id: \.self) { term in
                        Button {
                            rememberSearch(term)
                            query = term
                            mapFocus.wrappedValue = .search
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 9))
                                Text(term).lineLimit(1).truncationMode(.tail)
                            }
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 9)
                            .frame(maxWidth: (expandedWidth - 12) / 3)
                            .frame(height: 22)
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .mapControlBackground(in: Capsule(), regular: true)
                        .accessibilityLabel(L10n.text("最近搜索：%1$@", term))
                    }
                }
                .frame(width: expandedWidth, alignment: .leading)
            }
            HStack(spacing: 0) {
                Button {
                    expanded = true
                    mapFocus.wrappedValue = .search
                } label: {
                    Image(systemName: "magnifyingglass")
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }.buttonStyle(.plain).help(L10n.text("搜索地点"))
                    .accessibilityLabel(L10n.text("展开地点搜索"))
                if expanded {
                    if provider == "amap" {
                        AMapSearchScopeMenu(choosingCity: $choosingCity).padding(.trailing, 6)
                    }
                    TextField(L10n.text("搜索地点"), text: $query)
                        .textFieldStyle(.plain)
                        .focused(mapFocus, equals: .search)
                        .onSubmit { rememberSearch(query) }
                        .disabled(provider == "amap" && !workspace.ready)
                        .transition(.opacity)
                    Button {
                        expanded = false
                    } label: {
                        Image(systemName: "xmark").frame(width: 40, height: 44)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).help(L10n.text("收起搜索"))
                        .accessibilityLabel(L10n.text("收起地点搜索"))
                        .transition(.opacity)
                }
            }
            .frame(width: expanded ? expandedWidth : 44, height: 44, alignment: .leading)
            .clipShape(Capsule())
            .mapControlBackground(in: Capsule(), regular: expanded)
            .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: expanded)
        }
        .buttonStyle(.bordered)
        .onChange(of: mapFocus.wrappedValue) {
            store.send(.textfieldFocusChanged(mapFocus.wrappedValue == .search || choosingCity), undoable: false)
        }
        .onChange(of: choosingCity) {
            store.send(.textfieldFocusChanged(choosingCity || mapFocus.wrappedValue == .search), undoable: false)
            if !choosingCity && expanded { mapFocus.wrappedValue = .search }
        }
        .onChange(of: expanded) {
            if !expanded {
                choosingCity = false
                query = ""
                mapFocus.wrappedValue = nil
            }
        }
        .onChange(of: store.mapSearchActive) {
            if store.mapSearchActive { expanded = true; mapFocus.wrappedValue = .search }
        }
        .onChange(of: provider) { query = "" }
        .onDisappear { store.send(.textfieldFocusChanged(false), undoable: false) }
        .task(id: "\(provider):\(workspace.ready):\(query):\(workspace.searchScope.id):\(workspace.searchRefresh)") {
            workspace.searchRevision += 1
            workspace.invalidateSelection?()
            workspace.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
            workspace.results = []
            workspace.selectedResult = nil
            workspace.searching = false
            workspace.searchError = nil
            workspace.searchAreaChanged = false
            searchInfo.searchResponse = []
            searchInfo.selection = nil
            searching = false
            error = nil
            let current = workspace.query
            guard !current.isEmpty else { return }
            if provider == "amap", workspace.ready { workspace.searching = true }
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
                    if searchInfo.searchResponse.isEmpty { error = L10n.text("未找到地点，请补充城市或名称。") }
                } catch {
                    guard !Task.isCancelled else { return }
                    self.error = L10n.text("搜索失败，请检查网络后重试。")
                }
                searching = false
            }
        }
    }

    private var resultsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
                if searching || workspace.searching { ProgressView(L10n.text("搜索中…")).controlSize(.small) }
                if let error { Text(error).font(.caption).foregroundStyle(.secondary) }
                if provider == "amap", !workspace.ready {
                    Text(L10n.text("地图尚未就绪")).font(.caption).foregroundStyle(.secondary)
                } else if provider == "amap", !workspace.searching {
                    if let failure = workspace.searchError {
                        Text(failure).font(.caption).foregroundStyle(.secondary)
                        Button(L10n.text("重试")) { workspace.searchRefresh += 1 }
                    } else if resultCount == 0 {
                        Text(L10n.text("%1$@未找到相关地点", workspace.searchScope.title))
                            .font(.caption).foregroundStyle(.secondary)
                        if workspace.searchScope != .nationwide {
                            Button(L10n.text("改搜全国")) { workspace.searchScope = .nationwide }
                        }
                    }
                }
                if resultCount > 0 {
                    ScrollView {
                        VStack(spacing: 4) {
                            if provider == "amap" {
                                ForEach(workspace.results) { result in
                                    resultButton(result.name, subtitle: result.city == nil ? result.address : "",
                                                 selected: workspace.selectedResult?.id == result.id,
                                                 icon: result.city == nil ? nil : "building.2") {
                                        rememberSearch(query)
                                        if let city = result.city {
                                            workspace.selectSearchCity(city)
                                            if city.name.contains(query.trimmingCharacters(in: .whitespacesAndNewlines)) {
                                                query = ""
                                            }
                                            mapFocus.wrappedValue = .search
                                        } else {
                                            workspace.selectedResult = result
                                            workspace.previewSearch?(result)
                                        }
                                    }
                                }
                            } else {
                                ForEach(searchInfo.searchResponse) { place in
                                    resultButton(shortName(place), subtitle: region(place),
                                                 selected: searchInfo.selection?.id == place.id) {
                                        rememberSearch(query)
                                        searchInfo.selection = place
                                        workspace.preview(MapCoordinate(latitude: place.coordinate.latitude,
                                                                        longitude: place.coordinate.longitude),
                                                          name: shortName(place))
                                        searchInfo.recenterLocation = place.coordinate.coord2D
                                    }
                                }
                            }
                        }
                    }.frame(height: min(CGFloat(resultCount) * 58, 250))
                        .background(SubtleScrollbars())
                }
                if provider == "amap", let result = workspace.selectedResult {
                    HStack {
                        Button(L10n.text("应用到照片")) { workspace.chooseSearch?(result, "apply") }
                            .disabled(!editable || !workspace.ready)
                        Button(L10n.text("收藏地点")) { workspace.chooseSearch?(result, "favorite") }
                    }
                } else if let place = searchInfo.selection {
                    Button(L10n.text("应用到照片")) {
                        let ids = store.selection
                        store.send(.placeSelection(place))
                        store.send(.confirmedWGS84Location(place.coordinate.coord2D), description: "search selection")
                        LocationHelper.scheduleLinkedRegions(store, workspace: workspace, ids: ids)
                    }.disabled(!editable)
                }
        }.frame(width: expandedWidth - 24)
    }

    private func resultButton(_ name: String, subtitle: String, selected: Bool, icon: String? = nil,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).foregroundStyle(.secondary) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.system(size: 13)).foregroundStyle(.primary).lineLimit(1)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                .background(selected ? Color.blue.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(RoundedRectangle(cornerRadius: 6))
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

    private func rememberSearch(_ text: String) {
        guard recordSearches else { return }
        recentSearchesData = (try? JSONEncoder().encode(Self.updatedRecentSearches(text, in: recentSearches))) ?? Data()
    }

    nonisolated static func updatedRecentSearches(_ text: String, in history: [String]) -> [String] {
        let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return history }
        let updated = [term] + history.filter {
            $0.localizedCaseInsensitiveCompare(term) != .orderedSame
        }
        return Array(updated.prefix(3))
    }
}
