import OSLog
import SwiftUI
import UDF
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) var store
    @Environment(\.openWindow) var openWindow

    @AppStorage(L10n.languageKey) private var language = L10n.language.rawValue
    @AppStorage("PhotoTrailMapProvider") private var mapProvider = "amap"
    @AppStorage(Self.alternateLayoutKey) var alternateLayout = false

    @State private var locationWorkspace = LocationWorkspace()
    @State private var metadataQueue = MetadataLoadingQueue()
    @State private var sheetType: SheetType?
    @State private var importFiles = false
    @State private var spinnerEnabled = false
    @State private var ignoredFileNotice: Int?
    @State private var ignoredFileNoticeID = UUID()
    @State private var inspectorPresented = false
    @State private var renameSelected = false
    @State private var renameWorkspace = RenameWorkspace()
    @State private var batchActionsPresented = false
    @State private var setupPresented = false
    @AppStorage(SetupGuideView.completedKey) private var setupCompleted = false

    private let testIDs = TestIDs.ContentView.self

    private var workspaceContent: some View {
        VStack(spacing: 0) {
            if let ignoredFileNotice {
                HStack(spacing: 10) {
                    Label(L10n.text("本次已跳过 %1$@ 个不支持的文件。支持导入图片及 GPX、KML、KMZ 轨迹。", ignoredFileNotice),
                          systemImage: "doc.badge.ellipsis")
                    Spacer(minLength: 0)
                    Button { self.ignoredFileNotice = nil } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.text("关闭提示"))
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor))
            }
            if !alternateLayout && !store.gpxBadFileNames.isEmpty {
                HStack {
                    Text(L10n.text("部分轨迹文件未能导入，请在轨迹卡片中查看。"))
                    Spacer()
                    Button(L10n.text("查看")) { renameSelected = false; alternateLayout = true }
                    Button(L10n.text("关闭")) { store.send(.gpxLoadViewClosed, undoable: false) }
                }
                .font(.callout).padding(12)
            }
            if store.renameInProgress {
                Label(L10n.text("正在重命名文件，请勿关闭程序。"), systemImage: "character.cursor.ibeam")
                    .font(.callout).padding(8)
            } else if store.saveInProgress {
                Label(L10n.text("正在写入照片（已处理 %1$@/%2$@）；请勿修改定位或关闭程序，可继续浏览。", store.saveCompleted, store.saveTotal),
                      systemImage: "externaldrive.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.10))
            }
            if metadataQueue.total > 0 && !renameSelected {
                HStack(spacing: 12) {
                    ProgressView(value: Double(metadataQueue.completed), total: Double(metadataQueue.total))
                        .frame(width: 160)
                    Text(L10n.text("元数据：已读取 %1$@/%2$@，失败 %3$@",
                                   metadataQueue.completed - metadataQueue.failures, metadataQueue.total, metadataQueue.failures))
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    Spacer()
                }.padding(.horizontal, 14).padding(.vertical, 6)
            }
            Group {
                if renameSelected {
                    RenameWorkspaceView(workspace: renameWorkspace)
                } else if alternateLayout {
                    PhotoDetailPage()
                } else {
                    HSplitView {
                        HStack(spacing: 0) {
                            ImageTableView(inspectorPresented: $inspectorPresented,
                                           batchActionsPresented: $batchActionsPresented) { alternateLayout = true }
                                .accessibilityIdentifier(testIDs.imageTableViewID)
                            if batchActionsPresented {
                                Divider()
                                PhotoActionSidebar()
                            }
                        }.frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
                        MetadataListInspectorView()
                            .frame(minWidth: 380, idealWidth: 540, maxWidth: .infinity, maxHeight: .infinity)
                            .accessibilityIdentifier(testIDs.imageInspectorViewID)
                    }
                }
            }
            .id(language)
            .overlay { if spinnerEnabled { ProgressView(L10n.text("正在导入照片…")) } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(.blue)
        .environment(locationWorkspace)
        .environment(metadataQueue)
    }

    var body: some View {
        workspaceContent
        .onAppear {
            metadataQueue.prioritize(ids: store.selection)
            metadataQueue.synchronize(store.imageData)
        }
        .onChange(of: store.imageData.map(\.id)) { metadataQueue.synchronize(store.imageData) }
        .onChange(of: store.imageData.map(\.metadataInspectionURL)) { metadataQueue.synchronize(store.imageData) }
        .onChange(of: store.selection) { metadataQueue.prioritize(ids: store.selection) }
        .onChange(of: store.saveInProgress) {
            if !store.saveInProgress { metadataQueue.synchronize(store.imageData) }
        }
        .background(CredentialChangeObserver(workspace: locationWorkspace))
        .task {
            if ProcessInfo.processInfo.environment["PHOTOTRAIL_OFFLINE_TESTS"] != "1" {
                _ = locationWorkspace.tracks.restore()
            }
            locationWorkspace.tracks.synchronize(store.gpxTracks, amap: mapProvider == "amap")
            if setupCompleted {
                await locationWorkspace.load()
                SoftwareUpdate.shared.presentDownloadedUpdateIfNeeded()
            }
            else { setupPresented = true }
        }
        .onChange(of: store.trackMatches) {
            if !store.trackMatches.isEmpty { locationWorkspace.listMatchResults = store.trackMatches }
        }
        .onChange(of: store.gpxTracks) {
            locationWorkspace.tracks.synchronize(store.gpxTracks, amap: mapProvider == "amap")
        }
        .onChange(of: store.gpxImportRevision) {
            let library = locationWorkspace.tracks
            library.synchronize(store.gpxTracks, amap: mapProvider == "amap")
            for record in library.activeRecords where store.gpxGoodFileNames.contains(record.id) {
                library.setVisible(record.id, true, amap: mapProvider == "amap")
            }
        }
        .onChange(of: mapProvider) {
            locationWorkspace.tracks.changeProvider(amap: mapProvider == "amap")
        }
        .onChange(of: setupCompleted) {
            if !setupCompleted { setupPresented = true }
        }
        .onChange(of: setupPresented) {
            if !setupPresented { SoftwareUpdate.shared.presentDownloadedUpdateIfNeeded() }
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
            if store.mapSearchActive { renameSelected = false; alternateLayout = true }
        }
        .onChange(of: store.searchActive) {
            if store.searchActive { renameSelected = false; alternateLayout = false }
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
            if sheetType == nil { scheduleIgnoredFileNoticeDismissal() }
        }
        .sheet(item: $sheetType, onDismiss: sheetDismissed) { sheet in
            sheet
        }
        .areYouSure()  // confirmations
        .removeBackupsAlert()  // Alert: Remove Old Backup files
        .inspector(isPresented: Binding(get: { !renameSelected && alternateLayout && inspectorPresented },
                                        set: { inspectorPresented = $0 })) {
            ImageInspectorView()
                .environment(metadataQueue)
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
                WorkspacePageSwitch(selection: $alternateLayout, renameSelected: $renameSelected, showsRename: true)
            }
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                if !renameSelected {
                    WorkspaceSaveButton().fixedSize()
                }
                Button { store.send(.openCommand, undoable: false) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "plus")
                        Text(L10n.text("导入照片"))
                    }.fixedSize()
                }
                .labelStyle(.titleAndIcon)
                .disabled(store.saveInProgress)
                PhotoPickerView()
                    .disabled(store.saveInProgress)
                    .accessibilityIdentifier(testIDs.photoPickerViewID)
                if !renameSelected {
                    InspectorButtonView(presented: $inspectorPresented)
                        // Keep the shared save action stationary when changing pages.
                        .opacity(alternateLayout ? 1 : 0)
                        .disabled(!alternateLayout)
                        .allowsHitTesting(alternateLayout)
                        .accessibilityHidden(!alternateLayout)
                        .accessibilityIdentifier(testIDs.inspectorButtonViewID)
                }
                }.buttonStyle(WorkspaceToolbarButtonStyle())
            }
        }
    }

    // when a sheet is dismissed check if there are more sheets to display

    private func sheetDismissed() {
        store.send(.sheetDismissed, undoable: false)
    }

    private func importLocalFiles(_ files: [URL], description: String) {
        ignoredFileNotice = nil
        ignoredFileNoticeID = UUID()
        store.send(.openFiles(files), undoable: false) {
            let urls = store.uniqueURLs ?? []
            let ignoredCount = store.ignoredFileCount
            store.send(.clearUniqueURLs, undoable: false)
            guard !urls.isEmpty else {
                showIgnoredFileNotice(ignoredCount)
                return
            }
            let task = OpenHelper.open(store, urls: urls, description: description,
                                       spinnerEnabled: $spinnerEnabled)
            Task {
                _ = await task.result
                showIgnoredFileNotice(ignoredCount)
            }
        }
    }

    private func showIgnoredFileNotice(_ count: Int) {
        guard count > 0 else { return }
        ignoredFileNotice = count
        if sheetType == nil { scheduleIgnoredFileNoticeDismissal() }
    }

    private func scheduleIgnoredFileNoticeDismissal() {
        guard ignoredFileNotice != nil else { return }
        let id = UUID()
        ignoredFileNoticeID = id
        Task {
            try? await Task.sleep(for: .seconds(6))
            if ignoredFileNoticeID == id && sheetType == nil { ignoredFileNotice = nil }
        }
    }

    // the UTTypes that can be imported into this app.

    private func importTypes() -> [UTType] {
        [.image, .folder] + UTType.photoTrailTracks
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
