import OSLog
import SwiftUI
import UDF
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) var store
    @Environment(\.openWindow) var openWindow

    @AppStorage(Self.alternateLayoutKey) var alternateLayout = false

    @State private var locationWorkspace = LocationWorkspace()
    @State private var sheetType: SheetType?
    @State private var importFiles = false
    @State private var spinnerEnabled = false
    @State private var ignoredVideoNotice: Int?
    @State private var ignoredVideoNoticeID = UUID()
    @State private var inspectorPresented = false
    @State private var setupPresented = false
    @AppStorage(SetupGuideView.completedKey) private var setupCompleted = false

    private let testIDs = TestIDs.ContentView.self

    var body: some View {
        VStack(spacing: 0) {
            if let ignoredVideoNotice {
                HStack(spacing: 10) {
                    Label("本次已自动忽略 \(ignoredVideoNotice) 个视频文件。视频暂不支持导入。",
                          systemImage: "video.slash")
                    Spacer(minLength: 0)
                    Button { self.ignoredVideoNotice = nil } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭提示")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor))
            }
            if store.saveInProgress {
                Label("正在写入照片（已处理 \(store.saveCompleted)/\(store.saveTotal)）；请勿修改定位或关闭程序，可继续浏览。",
                      systemImage: "externaldrive.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.10))
            }
            Group {
                if alternateLayout {
                    PhotoDetailPage()
                } else {
                    HStack(spacing: 0) {
                        ImageTableView(inspectorPresented: $inspectorPresented) { alternateLayout = true }
                            .accessibilityIdentifier(testIDs.imageTableViewID)
                        Divider()
                        PhotoActionSidebar()
                    }
                }
            }
            .overlay { if spinnerEnabled { ProgressView("正在导入照片…") } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(.blue)
        .environment(locationWorkspace)
        .background(CredentialChangeObserver(workspace: locationWorkspace))
        .task {
            if ProcessInfo.processInfo.environment["PHOTOTRAIL_OFFLINE_TESTS"] != "1" {
                let restored = locationWorkspace.tracks.restore()
                store.send(.restoreTracks(restored), undoable: false)
            }
            locationWorkspace.tracks.synchronize(store.gpxTracks)
            if setupCompleted { await locationWorkspace.load() }
            else { setupPresented = true }
        }
        .onChange(of: store.gpxTracks) {
            locationWorkspace.tracks.synchronize(store.gpxTracks)
        }
        .onChange(of: setupCompleted) {
            if !setupCompleted { setupPresented = true }
        }
        .sheet(isPresented: $setupPresented) {
            SetupGuideView {
                setupPresented = false
                Task { await locationWorkspace.load() }
            }.environment(locationWorkspace)
        }
        .dropDestination(for: URL.self) { items, _ in
            guard !store.saveInProgress else { return false }
            importLocalFiles(items, description: "drag files")
            return true
        }
        .onChange(of: store.mapSearchActive) {
            if store.mapSearchActive { alternateLayout = true }
        }
        .onChange(of: store.searchActive) {
            if store.searchActive { alternateLayout = false }
        }
        .onChange(of: store.showTimeZoneWindow) {
            openWindow(id: PhotoTrailApp.adjustTimeZone)
        }
        .onChange(of: store.showLogWindow) {
            openWindow(id: PhotoTrailApp.showRunLog)
        }
        .onChange(of: store.sheetType) {
                sheetType = store.sheetType
        }
        .onChange(of: sheetType) {
            if sheetType == nil { scheduleIgnoredVideoNoticeDismissal() }
        }
        .sheet(item: $sheetType, onDismiss: sheetDismissed) { sheet in
            sheet
        }
        .areYouSure()  // confirmations
        .removeBackupsAlert()  // Alert: Remove Old Backup files
        .inspector(isPresented: $inspectorPresented) {
            ImageInspectorView()
                .inspectorColumnWidth(min: 300, ideal: 400, max: 500)
                .accessibilityIdentifier(testIDs.imageInspectorViewID)
        }
        .onChange(of: store.importFiles) {
            importFiles.toggle()
        }
        .fileImporter(isPresented: $importFiles,
                      allowedContentTypes: importTypes(),
                      allowsMultipleSelection: true) { result in
            switch result {
            case let .success(files):
                importLocalFiles(files, description: "add files")
            case let .failure(error):
                Logger(subsystem: Bundle.main.bundleIdentifier!,
                       category: "ContentView").error(
                    "file import: \(error.localizedDescription, privacy: .public)")
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                WorkspacePageSwitch(selection: $alternateLayout)
            }
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                if alternateLayout {
                    WorkspaceSaveButton().fixedSize()
                }
                Button { store.send(.openCommand, undoable: false) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "plus")
                        Text("导入照片")
                    }.fixedSize()
                }
                .labelStyle(.titleAndIcon)
                .disabled(store.saveInProgress)
                PhotoPickerView()
                    .disabled(store.saveInProgress)
                    .accessibilityIdentifier(testIDs.photoPickerViewID)
                InspectorButtonView(presented: $inspectorPresented)
                    .accessibilityIdentifier(testIDs.inspectorButtonViewID)
                }.buttonStyle(WorkspaceToolbarButtonStyle())
            }
        }
    }

    // when a sheet is dismissed check if there are more sheets to display

    private func sheetDismissed() {
        store.send(.sheetDismissed, undoable: false)
    }

    private func importLocalFiles(_ files: [URL], description: String) {
        ignoredVideoNotice = nil
        ignoredVideoNoticeID = UUID()
        store.send(.openFiles(files), undoable: false) {
            let urls = store.uniqueURLs ?? []
            let ignoredCount = store.ignoredVideoCount
            store.send(.clearUniqueURLs, undoable: false)
            guard !urls.isEmpty else {
                showIgnoredVideoNotice(ignoredCount)
                return
            }
            let task = OpenHelper.open(store, urls: urls, description: description,
                                       spinnerEnabled: $spinnerEnabled)
            Task {
                _ = await task.result
                showIgnoredVideoNotice(ignoredCount)
            }
        }
    }

    private func showIgnoredVideoNotice(_ count: Int) {
        guard count > 0 else { return }
        ignoredVideoNotice = count
        if sheetType == nil { scheduleIgnoredVideoNoticeDismissal() }
    }

    private func scheduleIgnoredVideoNoticeDismissal() {
        guard ignoredVideoNotice != nil else { return }
        let id = UUID()
        ignoredVideoNoticeID = id
        Task {
            try? await Task.sleep(for: .seconds(6))
            if ignoredVideoNoticeID == id && sheetType == nil { ignoredVideoNotice = nil }
        }
    }

    // the UTTypes that can be imported into this app.

    private func importTypes() -> [UTType] {
        var types: [UTType] = [.image, .folder]
        if let type = UTType(filenameExtension: "gpx") {
            types.append(type)
        }
        return types
    }
}

// AppSettings keys used to determine ContentView layout

extension ContentView {
    static let alternateLayoutKey = "AlternateLayout"
    static let splitHNormalKey = "SplitHNormalPercent"
    static let splitHAlternateKey = "SplitHAlternatePercent"
    static let splitVNormalKey = "SplitVNormalPercent"
    static let splitVAlternateKey = "SplitVAlternatePercent"
}

#Preview(traits: .store) {
    ContentView()
        .frame(width: 800, height: 1000)
}

private struct CredentialChangeObserver: View {
    let workspace: LocationWorkspace

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .onReceive(NotificationCenter.default.publisher(for: .photoTrailAMapCredentialsChanged)) { notice in
                if let credentials = notice.object as? AMapCredentials {
                    workspace.credentials = credentials
                    workspace.reload()
                }
            }
    }
}
