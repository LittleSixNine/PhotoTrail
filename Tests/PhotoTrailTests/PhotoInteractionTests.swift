import Coords
import Foundation
import ImageData
import Metadata
import SwiftUI
import Testing
import UDF
@testable import PhotoTrail

@MainActor struct PhotoInteractionTests {
    @Test func twoThousandPhotoSelectionsReuseProjectionsAndEditsInvalidateThem() throws {
        var state = PhotoTrailState()
        state.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        state.imageData = (0..<2_000).map { index in
            var metadata = Metadata(source: .xmp(URL(fileURLWithPath: "/tmp/projection-\(index).jpg")))
            metadata.dateTimeCreated = String(format: "2026:10:08 12:%02d:%02d", index / 60, index % 60)
            return ImageData(metadata: metadata, name: "photo-\(index).jpg")
        }
        let first = try #require(state.imageData.first)
        let last = try #require(state.imageData.last)
        let store = Store(initialState: state, reduce: PhotoTrailReducer(), undoEnabled: true)
        var parses = 0
        let projection = PhotoListProjection { metadata, zone in
            parses += 1
            return metadata.parsedDate(timeZone: zone)
        }
        func filmstrip() -> [ImageData] {
            projection.filmstrip(store.state, filter: .all, mode: .capturedAt, ascending: true)
        }
        let clock = ContinuousClock()
        let coldStart = clock.now
        #expect(filmstrip().first?.id == first.id)
        let cold = coldStart.duration(to: clock.now)
        #expect(parses == 2_000)
        let revision = store.imageRevision
        let warmStart = clock.now
        for image in state.imageData.suffix(100) {
            store.send(.selectionChanged([image.id]), undoable: false)
            #expect(filmstrip().last?.id == last.id)
            #expect(projection.selected(store.state).map(\.id) == [image.id])
        }
        let warm = warmStart.duration(to: clock.now)
        #expect(store.imageRevision == revision)
        #expect(parses == 2_000)
        print("PHOTO_INTERACTION_PROJECTION count=2000 cold=\(cold) selections=100 warm=\(warm)")

        store.send(.selectionChanged([first.id]), undoable: false)
        store.send(.newTimestamp(Date(), 86_400))
        let editedRevision = store.imageRevision
        #expect(editedRevision != revision)
        #expect(filmstrip().last?.id == first.id)
        #expect(parses == 2_001)
        #expect(projection.selected(store.state).first?.metadata.timestamp == store[first.id].metadata.timestamp)
        store.undo()
        #expect(store.imageRevision == revision)
        #expect(filmstrip().first?.id == first.id)
        #expect(parses == 2_002)
        store.redo()
        #expect(filmstrip().last?.id == first.id)
        store.undo()
        store.send(.newTimestamp(Date(), -86_400))
        #expect(store.imageRevision != editedRevision)
        #expect(filmstrip().first?.id == first.id)

        let table = projection.table(store.state, search: "", hideInvalid: false, filter: .pending, unmatchedIDs: nil)
        #expect(table.ids == [first.id])
        #expect(table.counts[.all] == 2_000)
        #expect(table.counts[.pending] == 1)
        #expect(table.total == 2_000)
        #expect(projection.table(store.state, search: "", hideInvalid: false, filter: .all,
                                 unmatchedIDs: [last.id]).ids == [last.id])
        store.send(.removeImages([last.id]))
        #expect(!filmstrip().contains { $0.id == last.id })
        #expect(projection.table(store.state, search: "", hideInvalid: false, filter: .all,
                                 unmatchedIDs: [last.id]).images.isEmpty)
    }

    @Test func filmstripSortPreservesMissingDatesTiesTimeZonesAndPairing() throws {
        let zone = try #require(TimeZone(secondsFromGMT: 0))
        let names = ["z.jpg", "a.jpg", "missing.jpg", "a.DNG"]
        var state = PhotoTrailState()
        state.timeZone = zone
        state.imageData = names.map { name in
            var metadata = Metadata(source: .xmp(URL(fileURLWithPath: "/tmp/\(name)")))
            metadata.dateTimeCreated = name == "missing.jpg" ? nil : "2026:10:08 12:00:00"
            return ImageData(metadata: metadata, name: name)
        }
        let ids = state.imageData.map(\.id)
        state.linkPairedImages()
        let projection = PhotoListProjection()
        #expect(projection.filmstrip(state, filter: .all, mode: .capturedAt, ascending: true).map(\.id)
                == [ids[0], ids[1], ids[2]])
        #expect(projection.filmstrip(state, filter: .all, mode: .capturedAt, ascending: false).map(\.id)
                == [ids[2], ids[1], ids[0]])
        #expect(projection.filmstrip(state, filter: .all, mode: .filename, ascending: true).map(\.id)
                == [ids[1], ids[2], ids[0]])
        state[ids[0]].metadata.dateTimeCreated = "2026:10:08 11:00:00Z"
        state.timeZone = try #require(TimeZone(secondsFromGMT: 8 * 3_600))
        #expect(projection.filmstrip(state, filter: .all, mode: .capturedAt, ascending: true).map(\.id)
                == [ids[1], ids[0], ids[2]])
        state[ids[0]].metadata.location = Coords(latitude: 31, longitude: 121)
        let located = projection.filmstrip(state, filter: .located, mode: .importOrder, ascending: true)
        #expect(located.map(\.id) == [ids[0]])
        let searched = projection.table(state, search: "a.jpg", hideInvalid: true, filter: .all, unmatchedIDs: nil)
        #expect(searched.ids == [ids[1]])
        #expect(searched.counts[.all] == 1)
    }

    @Test func previewBudgetCannotEvictListThumbnailsOrBypassRequestedSize() async {
        var listReads = 0
        var previewReads = 0
        let list = PhotoThumbnailCache { _, _, _ in listReads += 1; return Image(systemName: "photo") }
        let preview = PhotoThumbnailCache { _, _, _ in previewReads += 1; return Image(systemName: "photo") }
        let images = (0..<20).map { ImageData(metadata: Metadata(source: .copy), name: "budget-\($0).jpg") }
        var first = images[0]
        first.thumbnail = Image(systemName: "star")
        _ = await list.image(for: first, scale: 2, maxDimension: 160)
        #expect(listReads == 1)
        for image in images { _ = await preview.image(for: image, scale: 2, maxDimension: 1024) }
        #expect(previewReads == 20)
        _ = await list.image(for: first, scale: 2, maxDimension: 160)
        #expect(listReads == 1)
        _ = await preview.image(for: images[0], scale: 2, maxDimension: 1024)
        #expect(previewReads == 21)
        #expect(PhotoThumbnail.pixelDimension(width: 126, scale: 2) == 256)
        #expect(PhotoThumbnail.pixelDimension(width: 180, scale: 2) == 384)
        #expect(PhotoThumbnail.pixelDimension(width: 700, scale: 2) == 1024)
    }

}
