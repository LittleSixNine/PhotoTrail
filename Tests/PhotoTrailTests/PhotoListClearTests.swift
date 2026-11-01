import Foundation
import Exiftool
import GpxTrackLog
import ImageData
import Testing
import UDF
@testable import PhotoTrail

@MainActor struct PhotoListClearTests {
    @Test func clearsAllPhotosAndDraftsButKeepsTracksFilesAndScopesAndSupportsUndo() throws {
        let (folder, readings) = try MetadataBatchEditingTests().input([[:], [:], [:]])
        defer { try? FileManager.default.removeItem(at: folder) }
        let trackURL = folder.appendingPathComponent("track.gpx")
        try Data("track".utf8).write(to: trackURL)
        var state = PhotoTrailState()
        state.imageData = readings.map(\.image)
        state.selection = [readings[0].image.id]
        state.gpxTracks = [GpxTrackLog(sourceURL: trackURL, tracks: [])]
        state.scopedURLs = [folder]
        state.trackMatches = readings.map { LocationHelper.LocationById(id: $0.image.id, timestamp: 1) }
        let store = Store(initialState: state, reduce: PhotoTrailReducer(), undoEnabled: true)
        let preview = try MetadataWorkflowPreview.prepare(readings,
            operations: [MetadataOperation(tag: .titleDefault, action: .setText("pending"))])
        store.send(.creatorDraftApplied(preview.items))
        let before = store.state
        let inline = MetadataBatchEditSession(readings: readings, tags: [.titleDefault], inline: true)
        inline.fields[0].mode = .set; inline.fields[0].input = "unfinished inline"
        let rules = MetadataBatchEditSession(readings: readings, tags: [.creator])
        rules.fields[0].mode = .set; rules.fields[0].input = "unfinished rules"
        #expect(OpenHelper.clearPhotoList(store, inline: inline, rules: rules))
        #expect(store.imageData.isEmpty && store.selection.isEmpty && store.mostSelected == nil)
        #expect(!store.unsavedChanges && store.creatorSaveResults.isEmpty && store.trackMatches.isEmpty)
        #expect(store.gpxTracks == before.gpxTracks && store.scopedURLs == before.scopedURLs)
        #expect(!inline.hasInput && !rules.hasInput)
        store.send(.locationFromTrack(before.trackMatches), undoable: false)
        #expect(store.trackMatches.isEmpty) // Late matching cannot revive removed photo results.
        for (index, reading) in readings.enumerated() {
            #expect(try Data(contentsOf: reading.snapshot.url) == Data("synthetic-\(index)".utf8))
        }
        #expect(try Data(contentsOf: trackURL) == Data("track".utf8))
        store.undo()
        #expect(store.imageData == before.imageData && store.selection == before.selection)
        #expect(store.unsavedChanges && store.trackMatches == before.trackMatches)
        #expect(store.imageData.allSatisfy { $0.creatorDraft != nil })
    }

    @Test func busyAndEmptyListsDoNotDiscardInput() throws {
        let (folder, readings) = try MetadataBatchEditingTests().input([[:]])
        defer { try? FileManager.default.removeItem(at: folder) }
        for busy in ["save", "rename", "import", "empty"] {
            var state = PhotoTrailState()
            if busy != "empty" { state.imageData = readings.map(\.image) }
            state.saveInProgress = busy == "save"
            state.renameInProgress = busy == "rename"
            if busy == "import" { state.importProgress.begin(.scanning) }
            let store = Store(initialState: state, reduce: PhotoTrailReducer(), undoEnabled: true)
            let session = MetadataBatchEditSession(readings: readings, tags: [.titleDefault], inline: true)
            session.fields[0].mode = .set; session.fields[0].input = "keep"
            #expect(!OpenHelper.canClearPhotoList(store.state))
            #expect(!OpenHelper.clearPhotoList(store, inline: session, rules: nil))
            #expect(session.hasInput && store.imageData == state.imageData)
            if busy == "import" { state.importProgress.finish() }
        }
    }
}
