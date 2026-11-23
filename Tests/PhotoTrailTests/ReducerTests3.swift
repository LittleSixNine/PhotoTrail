import Coords
import ImageData
import Imagetool
import Metadata
import SwiftUI
import Testing
import UDF

@testable import PhotoTrail

extension ReducerTests {
    @Test func placeSelectionEvent() async throws {
        var state = PhotoTrailState()
        for id in 1..<maxPlaces {
            state.places.append(testPlace(id))
        }
        let store = Store(initialState: state, reduce: PhotoTrailReducer())

        // add a place
        let place = testPlace(maxPlaces)
        store.send(.placeSelection(place))
        #expect(store.places.contains { $0.name == place.name })
        #expect(store.places.count == maxPlaces)

        // Add a dup, should be ignored
        store.send(.placeSelection(place))
        #expect(store.places.count == maxPlaces)
        #expect(store.places.filter { $0.name == place.name }
                            .count == 1)

        // Add a new entry.  The first entry should have been dropped
        let firstName = store.places.first?.name
        let lastPlace = testPlace(maxPlaces + 1)
        store.send(.placeSelection(lastPlace))
        #expect(store.places.count == maxPlaces)
        #expect(store.places.first?.name != firstName)
        #expect(store.places.last?.name == lastPlace.name)
    }

    @Test func quitRequestedEvent() async throws {
        var state = PhotoTrailState()
        let storeNormal = Store(initialState: state, reduce: PhotoTrailReducer())
        storeNormal.send(.quitRequested)
        // nothing happens save the state version being bumped
        #expect(storeNormal.state.version == state.version + 1)

        state.saveInProgress = true
        let storeSaving = Store(initialState: state, reduce: PhotoTrailReducer())
        storeSaving.send(.quitRequested)
        #expect(storeSaving.sheetType == .savingUpdatesSheet)

        state.unsavedChanges = true
        let storeSavingChanges = Store(initialState: state, reduce: PhotoTrailReducer())
        storeSavingChanges.send(.quitRequested)
        #expect(storeSavingChanges.sheetType == .savingUpdatesSheet)
        #expect(!storeSavingChanges.presentConfirmation)

        state.saveInProgress = false
        let storeUnsaved = Store(initialState: state, reduce: PhotoTrailReducer())
        storeUnsaved.send(.quitRequested)
        #expect(storeUnsaved.confirmationEvent == .terminateRequest)
        #expect(storeUnsaved.confirmationMessage != nil)
        #expect(storeUnsaved.presentConfirmation)
    }

    @Test func closingWindowWithUnsavedChangesRequestsConfirmation() {
        var state = PhotoTrailState()
        state.unsavedChanges = true
        let store = Store(initialState: state, reduce: PhotoTrailReducer())
        let delegate = AppDelegate()
        delegate.store = store

        #expect(!delegate.windowShouldClose(NSWindow()))
        #expect(store.unsavedChanges)
        #expect(store.confirmationEvent == .terminateRequest)
        #expect(store.presentConfirmation)
    }

    @Test func quittingUsesCurrentUnsavedStateAndPreservesEdits() {
        let store = Store(initialState: PhotoTrailState(), reduce: PhotoTrailReducer())
        let delegate = AppDelegate()
        delegate.store = store
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateNow)

        var image = ImageData(metadata: Metadata(source: .xmp(URL(fileURLWithPath: "/tmp/quit-check.jpg"))),
                              name: "quit-check.jpg")
        image.metadata.location = Coords(latitude: 31, longitude: 121)
        var state = PhotoTrailState()
        state.imageData = [image]
        state.unsavedChanges = true
        let dirtyStore = Store(initialState: state, reduce: PhotoTrailReducer())
        delegate.store = dirtyStore
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateCancel)
        #expect(dirtyStore.presentConfirmation)
        #expect(dirtyStore.unsavedChanges)
        #expect(dirtyStore[image.id].metadata.location == image.metadata.location)
        #expect(!delegate.windowShouldClose(NSWindow()))
        #expect(dirtyStore.confirmationEvent == .terminateRequest)
        #expect(dirtyStore.unsavedChanges)
    }

    @Test func readTrackLogEvent() async throws {
        let store = Store(initialState: PhotoTrailState(), reduce: PhotoTrailReducer())
        let goodName = "TestTrack.GPX"
        let badName = "BadTrack.GPX"
        let anotherName = "AnotherTrack.GPX"
        let track = store.state.previewTrack()

        store.send(.readTrackLog(goodName, track))
        #expect(!store.gpxTracks.isEmpty)
        #expect(!store.gpxGoodFileNames.isEmpty)
        #expect(store.gpxGoodFileNames.first == goodName)
        #expect(store.gpxBadFileNames.isEmpty)

        store.send(.readTrackLog(badName, nil))
        #expect(!store.gpxBadFileNames.isEmpty)
        #expect(store.gpxBadFileNames.first == badName)

        store.send(.gpxLoadViewClosed)
        let anotherTrack = store.state.previewAnotherTrack()
        store.send(.readTrackLog(anotherName, anotherTrack))
        #expect(store.gpxGoodFileNames.first == anotherName)
        #expect(store.gpxBadFileNames.isEmpty)
    }

    @Test func cleanupOnlyRemovesConfirmedUnchangedManagedBackups() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let original = root.appendingPathComponent("original.jpg")
        try Data([1]).write(to: original)
        for name in ["first.jpg", "second.jpg"] {
            try ManagedBackup.write(in: root) { directory in
                let file = directory.appendingPathComponent(name)
                try fm.copyItem(at: original, to: file)
                return file
            }
        }
        let confirmation = try ManagedBackup.list(in: root)
        #expect(confirmation.count == 2)
        let managed = ManagedBackup.directory(in: root)
        let second = managed.appendingPathComponent("second.jpg")
        try Data([2]).write(to: second, options: .atomic)
        let extra = managed.appendingPathComponent("foreign.jpg")
        try Data([3]).write(to: extra)
        try ManagedBackup.write(in: root) { directory in
            let file = directory.appendingPathComponent("later.jpg")
            try fm.copyItem(at: original, to: file)
            return file
        }
        for backup in confirmation { try backup.remove(from: root) }
        #expect(!fm.fileExists(atPath: managed.appendingPathComponent("first.jpg").path))
        #expect(try Data(contentsOf: second) == Data([2]))
        #expect(try Data(contentsOf: original) == Data([1]))
        #expect(try Data(contentsOf: extra) == Data([3]))
        #expect(try ManagedBackup.list(in: root).map(\.name) == ["later.jpg"])
    }

    @Test func saveCompleteEvent() async throws {
        var state = PhotoTrailState()
        state.saveInProgress = true
        state.unsavedChanges = true
        let store = Store(initialState: state, reduce: PhotoTrailReducer())

        store.send(.saveComplete(.saveErrorSupressWarning))
        #expect(!store.saveInProgress)
        #expect(!store.unsavedChanges) // No images carry a pending change in this fixture.
        #expect(store.sheetType == nil)

        store.send(.saveComplete(.saveError))
        #expect(!store.saveInProgress)
        #expect(!store.unsavedChanges)
        #expect(store.sheetType == .saveErrorSheet)

        store.send(.saveComplete(.saveOK))
        #expect(!store.unsavedChanges)
    }

    @Test func saveRequestEvent() async throws {
        let store = Store(initialState: PhotoTrailState(forPreview: true),
                          reduce: PhotoTrailReducer())
        store.send(.saveRequest)
        #expect(store.saveInProgress)
        #expect(store.libraryImages.isEmpty)
        #expect(store.fileImages.isEmpty)
        #expect(store.xmpImages.isEmpty)

        store.send(.saveComplete(.saveOK))
        store.send(.selectAllRequest)
        store.send(.locationChanged(Coords(latitude: 34.567,
                                           longitude: -122.235)))
        store.send(.saveRequest)
        #expect(store.libraryImages.isEmpty)
        #expect(store.fileImages.count >= 13)
        #expect(store.xmpImages.count == 2)
        #expect(store.saveTotal == store.fileImages.count + store.xmpImages.count)
    }

    @Test func searchActiveChangedEvent() async throws {
        let store = Store(initialState: PhotoTrailState(), reduce: PhotoTrailReducer())
        store.send(.searchActiveChanged(true))
        #expect(store.searchActive)
        store.send(.searchActiveChanged(false))
        #expect(!store.searchActive)
    }

    @Test func searchTextChangedEvent() async throws {
        let store = Store(initialState: PhotoTrailState(), reduce: PhotoTrailReducer())
        let text = "search text"
        store.send(.searchTextChanged(text))
        #expect(store.searchText == text)
    }

    @Test func selectAllRequestEvent() async throws {
        let store = Store(initialState: PhotoTrailState(), reduce: PhotoTrailReducer())
        store.send(.selectAllRequest)
        #expect(store.mostSelected == nil)
        #expect(store.selection.isEmpty)

        let state = PhotoTrailState(forPreview: true)
        let storeImages = Store(initialState: state, reduce: PhotoTrailReducer())
        storeImages.send(.selectAllRequest)
        #expect(storeImages.mostSelected != nil)
        #expect(storeImages.selection.count == 15)
    }

    @Test func selectionChangedEvent() async throws {
        let store = Store(initialState: PhotoTrailState(forPreview: true),
                          reduce: PhotoTrailReducer())
        let proposedSelection = Set(store.imageData.map { $0.id })
        store.send(.selectionChanged(proposedSelection))
        #expect(store.selection != proposedSelection)
        #expect(store.selection.count == 15)
        for id in store.selection {
            #expect(store[id].updatable)
        }
    }

    @Test func sheetDismissedEvent() async throws {
        let store = Store(initialState: PhotoTrailState(), reduce: PhotoTrailReducer())
        store.send(.duplicateImages)
        store.send(.finishedAddingTracks)
        #expect(store.sheetType == .duplicateImageSheet)

        store.send(.sheetDismissed)
        #expect(store.sheetType == nil)

        store.send(.sheetDismissed)
        #expect(store.sheetType == nil)
    }

    @Test func sidecarCreatedEvent() async throws {
        let store = Store(initialState: PhotoTrailState(forPreview: true),
                          reduce: PhotoTrailReducer())
        var id: ImageData.ID?
        for ix in store.imageData.indices {
            if case .image = store.imageData[ix].metadata.source {
                id = store.imageData[ix].id
                break
            }
        }
        let imageId = try #require(id)
        store.send(.sidecarCreated(imageId))
        if case .xmp = store[imageId].metadata.source {
            return
        }
        Issue.record(".sidecarCreated failed")
    }

    @Test func sortOrderChangedEvent() async throws {
        let store = Store(initialState: PhotoTrailState(forPreview: true),
                          reduce: PhotoTrailReducer())

        let nameOrder = [KeyPathComparator(\ImageData.name)]
        let timeOrder = [KeyPathComparator(\ImageData.metadata.timestamp)]

        #expect(store.sortOrder == nameOrder)
        store.send(.sortOrderChanged(timeOrder))
        #expect(store.sortOrder == timeOrder)
        var prevOrder = ""
        for ix in store.imageData.indices {
            #expect(prevOrder <= store.imageData[ix].metadata.timestamp)
            prevOrder = store.imageData[ix].metadata.timestamp
        }
    }

    @Test func sortUsingCurrentComparatorEvent() async throws {
        var state = PhotoTrailState(forPreview: true)
        state.sortOrder = [KeyPathComparator(\ImageData.metadata.timestamp)]
        let store = Store(initialState: state, reduce: PhotoTrailReducer())
        store.send(.sortUsingCurrentComparator)

        var prevOrder = ""
        for ix in store.imageData.indices {
            #expect(prevOrder <= store.imageData[ix].metadata.timestamp)
            prevOrder = store.imageData[ix].metadata.timestamp
        }
    }

    @Test func terminateRequestEvent() async throws {
        var state = PhotoTrailState()
        state.unsavedChanges = true
        let store = Store(initialState: state, reduce: PhotoTrailReducer())
        store.send(.terminateRequest)
        #expect(!store.unsavedChanges)
    }

    @Test func textfieldFocusChangedEvent() async throws {
        let store = Store(initialState: PhotoTrailState(), reduce: PhotoTrailReducer())
        store.send(.textfieldFocusChanged(true))
        #expect(store.textfieldActive)
        store.send(.textfieldFocusChanged(false))
        #expect(!store.textfieldActive)
    }

    @Test func timeZoneChangedEvent() async throws {
        let store = Store(initialState: PhotoTrailState(), reduce: PhotoTrailReducer())
        #expect(store.timeZone == TimeZone.current)
        let timeZone = TimeZoneName.plus3.timeZone
        store.send(.timeZoneChanged(timeZone))
        #expect(store.timeZone == timeZone)
    }

    @Test func toggleLogWindowEvent() async throws {
        let store = Store(initialState: PhotoTrailState(), reduce: PhotoTrailReducer())
        store.send(.toggleLogWindow)
        #expect(store.showLogWindow)
    }
}

extension ReducerTests {
    @Test func terminationPreservesDocumentInIsolatedTestContainer() throws {
        // This check creates a sentinel only inside an independent sandboxed test host.
        let dir = URL.documentsDirectory
        guard let id = Bundle.main.bundleIdentifier, id != "local.GeoTagCN",
              dir.pathComponents.contains(id), dir.pathComponents.contains("Containers") else { return }
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("PhotoTrail-quit-test-" + UUID().uuidString)
        defer { try? fm.removeItem(at: file) }
        let bytes = Data("preserve".utf8)
        try bytes.write(to: file, options: .withoutOverwriting)
        AppDelegate().applicationWillTerminate(.init(name: NSApplication.willTerminateNotification))
        #expect(try Data(contentsOf: file) == bytes)
        print("Verified Documents sentinel in independent sandbox")
    }
}
