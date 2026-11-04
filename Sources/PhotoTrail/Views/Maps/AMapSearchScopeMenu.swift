import SwiftUI
import UDF

struct AMapSearchScopeMenu: View {
    @Environment(LocationWorkspace.self) private var workspace
    @AppStorage(AMapSearchCity.recentKey) private var recentData = Data()
    @AppStorage(SettingsPreferences.recordSearchesKey) private var recordsSearches = true
    @Binding var choosingCity: Bool

    private var recent: [AMapSearchCity] { recordsSearches ? AMapSearchCity.recent(from: recentData) : [] }

    var body: some View {
        Menu {
            Button(L10n.text("当前画面"), systemImage: workspace.searchScope == .viewport ? "checkmark" : "viewfinder") {
                workspace.searchScope = .viewport
            }
            Button(L10n.text("全国"), systemImage: workspace.searchScope == .nationwide ? "checkmark" : "globe.asia.australia") {
                workspace.searchScope = .nationwide
            }
            Divider()
            Button(L10n.text("选择城市…"), systemImage: "building.2") { choosingCity = true }
            if !recent.isEmpty {
                Divider()
                ForEach(recent) { city in
                    Button(city.name) { workspace.selectSearchCity(city) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(workspace.searchScope.title).lineLimit(1).truncationMode(.tail)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 8).frame(maxWidth: 104, minHeight: 32)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .padding(.horizontal, 6).frame(height: 32)
        .background(Color.primary.opacity(0.07), in: Capsule())
        .accessibilityLabel(L10n.text("搜索范围"))
        .accessibilityValue(workspace.searchScope.title)
        .accessibilityIdentifier("amapSearchScope")
        .help(workspace.searchScope.title)
        .popover(isPresented: $choosingCity, arrowEdge: .top) {
            AMapCityPicker(recent: recent) { city in
                workspace.selectSearchCity(city)
                choosingCity = false
            }
        }
    }
}

private struct AMapCityPicker: View {
    @Environment(LocationWorkspace.self) private var workspace
    let recent: [AMapSearchCity]
    let choose: (AMapSearchCity) -> Void
    @State private var query = ""
    @State private var cities: [AMapSearchCity] = []
    @State private var searching = false
    @State private var error: String?
    @State private var retry = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(L10n.text("搜索城市"), text: $query)
                .textFieldStyle(.roundedBorder).focused($focused)
                .accessibilityIdentifier("amapCityQuery")
                .disabled(!workspace.ready)
                .onSubmit { if cities.count == 1, let city = cities.first { choose(city) } }
            if searching { ProgressView().controlSize(.small) }
            if let error {
                Text(error).font(.caption).foregroundStyle(.secondary)
                Button(L10n.text("重试")) { retry += 1 }
            }
            let displayed = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? recent : cities
            if !displayed.isEmpty {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(displayed) { city in
                            Button { choose(city) } label: {
                                HStack {
                                    Image(systemName: "building.2").foregroundStyle(.secondary)
                                    Text(city.name)
                                    Spacer()
                                }.padding(8).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }.frame(maxHeight: 220)
            }
        }.padding(12).frame(width: 280)
            .onAppear { focused = true }
            .task(id: "\(query):\(workspace.ready):\(retry)") {
                cities = []; error = nil; searching = false
                let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !keyword.isEmpty, workspace.ready else { return }
                do {
                    try await Task.sleep(for: .milliseconds(300))
                    searching = true
                    guard let lookup = workspace.searchCities else { throw URLError(.notConnectedToInternet) }
                    let result = try await lookup(keyword)
                    guard !Task.isCancelled else { return }
                    cities = result
                    if cities.isEmpty { error = L10n.text("未找到城市，请输入完整城市名。") }
                } catch {
                    guard !Task.isCancelled else { return }
                    self.error = L10n.text("城市查询失败，请检查网络后重试。")
                }
                searching = false
            }
    }
}
