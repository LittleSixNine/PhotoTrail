import Coords
import ImageData
import SwiftUI
import Testing
import UDF

@testable import PhotoTrail

@MainActor
struct ReducerTests {
    func testPlace(_ id: Int = 1) -> Place {
        return Place(name: "Test Place \(id)",
                     city: "Test City",
                     state: "Test State",
                     country: "Test Country",
                     countryCode: "Test Country Code",
                     coordinate: Coordinate(latitude: 37.123,
                                            longitude: -123.456))
    }

    @Test func addImageEvent() async throws {
        let store = Store(initialState: PhotoTrailState(forPreview: true),
                          reduce: PhotoTrailReducer())
        #expect(!store.imageData.isEmpty)
        let count = store.imageData.count
        store.send(.addImage(ImageData()))
        let expectedCount = count + 1
        #expect(store.imageData.count == expectedCount)
    }

    @Test func addImagesEvent() async throws {
        let state = PhotoTrailState(forPreview: true)
        // state is a source of images for this test
        // The store will use a different instance of state
        let store = Store(initialState: PhotoTrailState(), reduce: PhotoTrailReducer())
        #expect(store.imageData.isEmpty)
        store.send(.addImages(state.imageData))
        #expect(store.imageData.count == state.imageData.count)
    }

    @Test func addressChangedEvent() async throws {
        let store = Store(initialState: PhotoTrailState(forPreview: true),
                          reduce: PhotoTrailReducer())
        #expect(!store.imageData.isEmpty)
        let id = store.imageData[1].id
        let selection: Set<ImageData.ID> = [id]
        let place = testPlace()
        store.send(.addressChanged(selection, place))
        #expect(store[id].metadata.city == place.city)
        #expect(store[id].metadata.state == place.state)
        #expect(store[id].metadata.country == place.country)
        #expect(store[id].metadata.countryCode == place.countryCode)
        // .addressChanged event does not update location/coordinate
    }

    @Test func backupFolderSizeEvent() async throws {
        let fm = FileManager.default
        var state = PhotoTrailState()
        let backupURL =
            URL.temporaryDirectory.appending(components: UUID().uuidString,
                                             directoryHint: .isDirectory)
        try fm.createDirectory(at: backupURL,
                               withIntermediateDirectories: true)

        defer {
            try? fm.removeItem(at: backupURL)
        }
        state.backupURL = backupURL
        let store = Store(initialState: state, reduce: PhotoTrailReducer())

        // check with empty folder
        store.send(.backupFolderSizeCheck)
        #expect(store.oldFiles.isEmpty)
        #expect(store.folderSize == 0)
        #expect(store.deletedSize == 0)

        // check with data
        let urls = state.previewURLs()
        print(urls)
        for url in urls {
            let name = url.lastPathComponent
            try fm.copyItem(at: url, to: backupURL.appending(component: name))
        }
        store.send(.backupFolderSizeCheck)
        #expect(store.oldFiles.count == 0)
        #expect(store.folderSize == 226059455)
        #expect(store.deletedSize == 0)

        // no test for old files
    }

    @Test func backupURLChangedEvent() async throws {
        let fm = FileManager.default
        let backupURL =
            URL.temporaryDirectory.appending(components: UUID().uuidString,
                                             directoryHint: .isDirectory)
        try fm.createDirectory(at: backupURL,
                               withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: backupURL)
        }
        var state = PhotoTrailState()
        state.backupURL = nil
        let store = Store(initialState: state, reduce: PhotoTrailReducer())

        store.send(.backupURLChanged(backupURL))

        #expect(store.backupURL == backupURL)
    }

    @Test func badGpxFileEvent() async throws {
        let badFileName = "/Bad/File/Name"
        var state = PhotoTrailState()
        state.gpxBadFileNames = []
        let store = Store(initialState: state, reduce: PhotoTrailReducer())

        store.send(.badGpxFile(badFileName))

        #expect(store.gpxBadFileNames.count == 1)
        #expect(store.gpxBadFileNames[0] == badFileName)
    }

    @Test func catchUnexpectedErrorEvent() async throws {
        let error = "The error string goes here"
        let message = "An optional message to go with the error"
        let store = Store(initialState: PhotoTrailState(), reduce: PhotoTrailReducer())

        store.send(.catchUnexpectedError(nil, nil))
        #expect(store.sheetType == .unexpectedErrorSheet)
        #expect(store.sheetError == nil)
        #expect(store.sheetMessage == nil)
        #expect(store.sheetStack.isEmpty)

        store.send(.catchUnexpectedError(nil, message))
        #expect(store.sheetStack.count == 1)
        #expect(store.sheetStack[0].sheetType == .unexpectedErrorSheet)
        #expect(store.sheetStack[0].sheetError == nil)
        #expect(store.sheetStack[0].sheetMessage == message)

        store.send(.catchUnexpectedError(error, message))
        #expect(store.sheetStack.count == 2)
        #expect(store.sheetStack[1].sheetType == .unexpectedErrorSheet)
        #expect(store.sheetStack[1].sheetError == error)
        #expect(store.sheetStack[1].sheetMessage == message)
    }

    @Test func changeTimeZoneEvent() async throws {
        let store = Store(initialState: PhotoTrailState(), reduce: PhotoTrailReducer())
        #expect(!store.showTimeZoneWindow)
        store.send(.changeTimeZone)
        #expect(store.showTimeZoneWindow)
    }

    @Test func clearImagesRequestEvent() async throws {
        let store = Store(initialState: PhotoTrailState(forPreview: true),
                          reduce: PhotoTrailReducer())
        #expect(!store.imageData.isEmpty)
        store.send(.clearImagesRequest)
        #expect(store.mostSelected == nil)
        #expect(store.selection.isEmpty)
        #expect(store.scopedURLs.isEmpty)
        #expect(store.imageData.isEmpty)
    }

    @Test func clearPlacesEvent() async throws {
        var state = PhotoTrailState()
        let place = testPlace()
        state.places.append(place)
        let store = Store(initialState: state, reduce: PhotoTrailReducer())
        store.send(.clearPlaces)
        #expect(store.places.isEmpty)
        // The disk file containing save places is updated in a task
        // give the task time to complete before verifying that the
        // file has been emptied. Fragile.
        try? await Task.sleep(for: .milliseconds(300))
        let savedPlaces = await PlaceSaver.shared.read()
        #expect(savedPlaces.isEmpty)
    }

    @Test func clearUniqueURLsEvent() async throws {
        var state = PhotoTrailState()
        state.uniqueURLs = [
            URL(filePath: "Fake/URL/1"),
            URL(filePath: "Fake/URL/2")
        ]
        let store = Store(initialState: state, reduce: PhotoTrailReducer())
        store.send(.clearUniqueURLs)
        #expect(store.uniqueURLs == nil)
    }

    @Test func deleteRequestEvent() async throws {
        var state = PhotoTrailState(forPreview: true)
        state.selection = Set(state.imageData.filter { $0.metadata.location != nil }
                                             .map { $0.id })
        #expect(!state.selection.isEmpty)
        state.mostSelected = state.selection.first

        let store = Store(initialState: state, reduce: PhotoTrailReducer())
        store.send(.deleteRequest)

        for id in state.selection {
            #expect(store[id].metadata.location == nil)
            #expect(store[id].metadata.city == nil)
            #expect(store[id].metadata.state == nil)
            #expect(store[id].metadata.country == nil)
            #expect(store[id].metadata.countryCode == nil)
            if let pairedID = store[id].pairedID, store[pairedID].updatable {
                #expect(store[pairedID].metadata.location == nil)
                #expect(store[pairedID].metadata.city == nil)
                #expect(store[pairedID].metadata.state == nil)
                #expect(store[pairedID].metadata.country == nil)
                #expect(store[pairedID].metadata.countryCode == nil)
            }
        }
    }

    @Test func onePhotoLocationCanBeAppliedToMultipleSelectedPhotos() throws {
        var state = PhotoTrailState(forPreview: true)
        let ids = Array(state.imageData.filter(\.updatable).prefix(2).map(\.id))
        #expect(ids.count == 2)
        state.selection = Set(ids)
        state.mostSelected = ids.first
        let store = Store(initialState: state, reduce: PhotoTrailReducer())
        let location = Coords(latitude: 31.23, longitude: 121.48)

        store.send(.locationFromPhoto(location, 18), description: "test")

        for id in ids {
            #expect(store[id].metadata.location == location)
            #expect(store[id].metadata.elevation == 18)
            #expect(store[id].metadata.gpsMapDatum == "WGS-84")
        }
    }

    @Test func discardChangesRequestEvent() async throws {
        var state = PhotoTrailState(forPreview: true)
        let ids = state.imageData
                       .filter { $0.metadata.location != nil }
                       .map { $0.id }
        for id in ids {
            state[id].metadata.location = nil
        }
        let store = Store(initialState: state, reduce: PhotoTrailReducer())

        store.send(.discardChangesRequest)
        for id in ids {
            #expect(store[id].metadata.location != nil)
        }
    }

    @Test func discardTracksRequestEvent() async throws {
        let state = PhotoTrailState(forPreview: true)
        #expect(!state.gpxTracks.isEmpty)
        let store = Store(initialState: state, reduce: PhotoTrailReducer())

        store.send(.discardTracksRequest)
        #expect(store.gpxTracks.isEmpty)
    }

    @Test func duplicateImagesEvent() async throws {
        let store = Store(initialState: PhotoTrailState(), reduce: PhotoTrailReducer())
        store.send(.duplicateImages)
        #expect(store.sheetType == .duplicateImageSheet)
        #expect(store.sheetError == nil)
        #expect(store.sheetMessage == nil)
    }

    @Test func findInMapEvent() async throws {
        let store = Store(initialState: PhotoTrailState(), reduce: PhotoTrailReducer())
        store.send(.findInMap(true))
        #expect(store.mapSearchActive)
        store.send(.findInMap(false))
        #expect(!store.mapSearchActive)
    }

    @Test func finishAddingTracksEvent() async throws {
        let store = Store(initialState: PhotoTrailState(), reduce: PhotoTrailReducer())
        store.send(.finishedAddingTracks)
        #expect(store.gpxImportRevision == 1)
        store.send(.finishedAddingTracks)
        #expect(store.gpxImportRevision == 2)
        #expect(store.sheetType == nil)
        #expect(store.sheetError == nil)
        #expect(store.sheetMessage == nil)
    }

    @Test func goodGpxFileEvent() async throws {
        let store = Store(initialState: PhotoTrailState(), reduce: PhotoTrailReducer())
        let name = "Good/file.gpx"
        store.send(.goodGpxFile(name))
        #expect(store.gpxGoodFileNames.count == 1)
        #expect(store.gpxGoodFileNames[0] == name)
    }

    @Test func gpxLoadViewClosedEvent() async throws {
        var state = PhotoTrailState()
        state.gpxGoodFileNames.append("Good/File/Name:")
        state.gpxBadFileNames.append("Bad/File/Name:")
        let store = Store(initialState: state, reduce: PhotoTrailReducer())

        store.send(.gpxLoadViewClosed)
        #expect(store.gpxBadFileNames.isEmpty)
        #expect(store.gpxGoodFileNames.isEmpty)
    }
}
