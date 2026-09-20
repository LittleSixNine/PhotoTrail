import OSLog
import RunLogView
import SwiftUI
import UDF

@main
struct PhotoTrailApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate: AppDelegate
    @State private var store: Store<PhotoTrailState, PhotoTrailEvent>
    @State private var mainWindow: NSWindow?
    @AppStorage(AppAppearance.preferenceKey) private var appearance: AppAppearance = .system

    @AppStorage(Self.doNotBackupKey) var doNotBackup = false
    @AppStorage(Self.savedBookmarkKey) var savedBookmark = Data()

    let windowWidth = 1180.0
    let windowHeight = 700.0

    init() {
        PhotoTrailMigration.settings()
        let appStore = Store(initialState: PhotoTrailState(),
                             reduce: PhotoTrailReducer(),
                             undoEnabled: true,
                             didUndo: PhotoTrailState.didUndoRedo,
                             didRedo: PhotoTrailState.didUndoRedo)
        _store = State(initialValue: appStore)
        appDelegate.store = appStore
        appDelegate.logger.debug("Delegate store set")
        prepareForTesting()
    }

    var body: some Scene {
        Window("PhotoTrail", id: "main") {
            if ProcessInfo.processInfo.environment["PHOTOTRAIL_OFFLINE_TESTS"] == "1" {
                // Unit tests use the app bundle, not its interactive window or private state.
                Color.clear.frame(width: 1, height: 1)
            } else {
            ContentView()
                .preferredColorScheme(appearance.colorScheme)
                .background(WindowAccessor(window: $mainWindow))
                .frame(minWidth: windowWidth, minHeight: windowHeight)
                .onAppear { appDelegate.store = store }
                .onChange(of: mainWindow) {
                    appDelegate.logger.debug("mainWindow changed")
                    mainWindow?.delegate = appDelegate
                    store.send(.mainWindowChange(mainWindow), undoable: false)
                }
                .task {
                    if !doNotBackup {
                        if !savedBookmark.isEmpty {
                            store.send(.initBackupURL, undoable: false) {
                                if store.backupURL != nil {
                                    store.send(.backupFolderSizeCheck,
                                               undoable: false)
                                }
                            }
                        }
                    }
                    let savedPlaces = await PlaceSaver.shared.read()
                    store.send(.initPlaces(savedPlaces), undoable: false)
                }
                .environment(store)
            }
        }
        .commands {
            NewItemCommands(store: store)
            SaveItemCommands(store: store)
            UndoRedoCommands(store: store)
            PasteboardCommands(store: store)
            ToolbarCommands(store: store)
            HelpCommands(store: store)
        }

        Window(Self.adjustTimeZone, id: Self.adjustTimeZone) {
            AdjustTimezoneView()
                .preferredColorScheme(appearance.colorScheme)
                .frame(width: 500.0, height: 570.0)
                .environment(store)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commandsRemoved()

        Window(Self.showRunLog, id: Self.showRunLog) {
            RunLogView()
                .background(SubtleScrollbars())
                .preferredColorScheme(appearance.colorScheme)
                .frame(width: 700, height: 500)
        }
        .windowResizability(.contentSize)
        .commandsRemoved()

        Settings {
            SettingsView()
                .preferredColorScheme(appearance.colorScheme)
                .environment(store)
        }
        .windowResizability(.contentSize)

    }
}

// Window ids

extension PhotoTrailApp {
    static var adjustTimeZone = "Change Time Zone"
    static var showRunLog = "PhotoTrail Run/Debug Log"
}

// Special handling for UI testing.  Various flags may be passed to
// force the app into a specific state before running tests.

extension PhotoTrailApp {
    private func prepareForTesting() {
#if DEBUG
        if CommandLine.arguments.contains("-UIINIT") {
            SettingsView.clearAllSettings()
            MapView.resetMapDefaults()
            appDelegate.logger.debug("Settings cleared")
        }
        if CommandLine.arguments.contains("-NOBACKUP") {
            doNotBackup = true
        } else if CommandLine.arguments.contains("-NOBACKUPFOLDER") {
            doNotBackup = false
            savedBookmark = Data()
        } else if CommandLine.arguments.contains("-DOBACKUP") {
            doNotBackup = false
        }
        if CommandLine.arguments.contains("-NOPLACES") {
            store.send(.clearPlaces)
        }
#endif
    }
}

// Max number of concurrent tasks that will be fired up in any single
// task group. A number picked out of thin air.

extension PhotoTrailApp {
    nonisolated static let maxConcurrentTasks = 128
}

// Settings keys

extension PhotoTrailApp {
    static let doNotBackupKey = "DoNotBackup"
    static let savedBookmarkKey = "SavedBookmark"
}
