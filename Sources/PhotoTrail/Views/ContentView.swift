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

    @Environment(LocationWorkspace.self) private var locationWorkspace
    @State private var metadataQueue = MetadataLoadingQueue()
    @State private var sheetType: SheetType?
    @State private var importFiles = false
    @State private var ignoredFileNotice: Int?
    @State private var ignoredFileNoticeID = UUID()
    @State private var inspectorPresented = false
    @State private var renameSelected = false
    @State private var startupApplied = false
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
            if !renameSelected && !metadataQueue.isPreparing && !store.importProgress.isActive {
                MetadataReadProgressView(progress: metadataQueue.progress,
                                         pause: metadataQueue.pauseReading, resume: metadataQueue.resumeReading)
            }
            Group {
                if store.importProgress.isActive {
                    ImportPreparationView(progress: store.importProgress, metadataProgress: metadataQueue.progress)
                } else if metadataQueue.isPreparing && !store.saveInProgress && !renameSelected {
                    MetadataPreparationView(importedPhotoCount: store.importProgress.photoCount,
                                            progress: metadataQueue.progress, pause: metadataQueue.pauseReading)
                } else if renameSelected {
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if renameWorkspace.executing {
                RenameExecutionProgressView(workspace: renameWorkspace)
            }
        }
        .tint(.blue)
        .environment(locationWorkspace)
        .environment(metadataQueue)
    }

    var body: some View {
        workspaceContent
        .onAppear {
            if !startupApplied {
                let page = SettingsPreferences.initialWorkspace()
                renameSelected = page == .rename
                alternateLayout = page == .map
                startupApplied = true
                rememberWorkspace()
            }
            metadataQueue.setPaused(store.saveInProgress || store.importProgress.isActive)
            metadataQueue.prioritize(ids: store.selection)
            metadataQueue.synchronize(store.imageData)
        }
        .onChange(of: alternateLayout) { rememberWorkspace() }
        .onChange(of: renameSelected) { rememberWorkspace() }
        .onChange(of: store.imageData.map(\.id)) { metadataQueue.synchronize(store.imageData) }
        .onChange(of: store.imageData.map(\.metadataInspectionURL)) { metadataQueue.synchronize(store.imageData) }
        .onChange(of: store.importProgress.isActive) {
            metadataQueue.setPaused(store.saveInProgress || store.importProgress.isActive)
            if !store.importProgress.isActive { metadataQueue.synchronize(store.imageData) }
        }
        .onChange(of: store.selection) { metadataQueue.prioritize(ids: store.selection) }
        .onChange(of: store.saveInProgress) {
            metadataQueue.setPaused(store.saveInProgress || store.importProgress.isActive)
            if !store.saveInProgress { metadataQueue.synchronize(store.imageData) }
        }
        .background(CredentialChangeObserver(workspace: locationWorkspace))
        .task {
            if ProcessInfo.processInfo.environment["PHOTOTRAIL_OFFLINE_TESTS"] != "1" {
                await locationWorkspace.tracks.restore()
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
                    .disabled(store.renameInProgress)
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
        OpenHelper.importFiles(store, urls: files, description: description) {
            showIgnoredFileNotice(store.ignoredFileCount)
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

    private func rememberWorkspace() {
        guard startupApplied else { return }
        let page: SettingsPreferences.Workspace = renameSelected ? .rename : alternateLayout ? .map : .metadata
        UserDefaults.standard.set(page.rawValue, forKey: SettingsPreferences.lastWorkspaceKey)
    }

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
        .environment(LocationWorkspace())
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
