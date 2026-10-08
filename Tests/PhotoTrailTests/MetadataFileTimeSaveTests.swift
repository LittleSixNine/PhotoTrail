import Exiftool
import Foundation
import ImageData
import Imagetool
import Testing
import UDF

@testable import PhotoTrail

@MainActor
struct MetadataFileTimeSaveTests {
    @Test func fileTimesSurviveTheApplicationSavePipeline() async throws {
        let source = try #require(PhotoTrailState(forPreview: true).imageData.compactMap { image -> URL? in
            guard case .image(let url) = image.metadata.source, url.pathExtension.lowercased() == "jpg" else { return nil }
            return url
        }.first)
        let folder = URL.temporaryDirectory.appending(component: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(component: "file-times.jpg")
        try FileManager.default.copyItem(at: source, to: url)
        let image = ImageData(metadata: Imagetool.metadata(from: url), name: url.lastPathComponent)
        var state = PhotoTrailState()
        state.imageData = [image]
        state.backupURL = folder.appending(component: "backup", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: state.backupURL!, withIntermediateDirectories: true)
        let store = Store(initialState: state, reduce: PhotoTrailReducer(), undoEnabled: true)
        let tags: Set<MetadataTag> = [.fileCreateDate, .fileModifyDate, .titleDefault]
        let snapshot = try MetadataInspectionSnapshot.read(tags, from: url)
        let timestamp = "2024:02:29 23:59:59.123456+08:00"
        let preview = try MetadataWorkflowPreview.prepare([(image, snapshot)], operations: [
            MetadataOperation(tag: .titleDefault, action: .setText("File time save")),
            MetadataOperation(tag: .fileCreateDate, action: .setText(timestamp)),
            MetadataOperation(tag: .fileModifyDate, action: .setText(timestamp))])
        store.send(.creatorDraftApplied(preview.items))
        await store.send(.saveRequest) { _ = await SaveHelper.save(store).result }
        #expect(!store.unsavedChanges)
        #expect(store.creatorSaveResults[image.id] == .saved)
        let actual = try Exiftool.helper.metadataTags(tags, from: url)
        #expect(MetadataTag.fileCreateDate.matches(actual[.fileCreateDate], .text(timestamp)))
        #expect(MetadataTag.fileModifyDate.matches(actual[.fileModifyDate], .text(timestamp)))
        #expect(actual[.titleDefault] == .text("File time save"))
    }

}
