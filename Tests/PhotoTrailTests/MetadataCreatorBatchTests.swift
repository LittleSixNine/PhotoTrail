import Exiftool
import Foundation
import ImageData
import Testing
import UDF

@testable import PhotoTrail

@MainActor
struct MetadataCreatorBatchTests {
    @Test func partialSaveClearsOnlySuccessfulCreatorDraft() async throws {
        let source = try #require(PhotoTrailState(forPreview: true).imageData.compactMap { image -> URL? in
            guard case .image(let url) = image.metadata.source,
                  url.pathExtension.lowercased() == "jpg" else { return nil }
            return url
        }.first)
        let folder = URL.temporaryDirectory.appending(component: UUID().uuidString,
                                                       directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let urls = ["first.jpg", "second.jpg"].map { folder.appending(component: $0) }
        for url in urls { try FileManager.default.copyItem(at: source, to: url) }
        let images = urls.map {
            ImageData(metadata: Exiftool.helper.metadata(from: nil, primaryURL: $0),
                      name: $0.lastPathComponent)
        }
        let readings = try zip(images, urls).map { image, url in
            (image: image, snapshot: try MetadataInspectionSnapshot.read([.creator], from: url))
        }
        let plan = try MetadataCreatorEditPlan.prepare(readings, action: .set(["Batch author"]))

        var state = PhotoTrailState()
        state.imageData = images
        state.backupURL = folder.appending(component: "backup", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: state.backupURL!, withIntermediateDirectories: true)
        let store = Store(initialState: state, reduce: PhotoTrailReducer(), undoEnabled: true)
        store.send(.creatorDraftApplied(plan.items))
        #expect(SaveTargets(images: store.imageData).creator == [0, 1])

        _ = try Exiftool.helper.update(image: urls[1],
                                      changes: [.creator: .set(.list(["External author"]))])
        await store.send(.saveRequest) {
            _ = await SaveHelper.save(store).result
        }

        #expect(store.saveTotal == 2 && store.saveCompleted == 2)
        #expect(store.creatorSaveResults[images[0].id] == .saved)
        #expect(store.creatorSaveResults[images[1].id] == .staleSource)
        #expect(store[images[0].id].creatorDraft == nil)
        #expect(store[images[1].id].creatorDraft != nil && store.unsavedChanges)
        #expect(try Exiftool.helper.metadataTags([.creator], from: urls[0])[.creator]
                == .list(["Batch author"]))
        #expect(try Exiftool.helper.metadataTags([.creator], from: urls[1])[.creator]
                == .list(["External author"]))
    }
}
