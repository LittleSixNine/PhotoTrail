import Foundation
import ImageData
import Metadata
import Testing
import UDF
@testable import PhotoTrail

@MainActor
struct OperationFailureTests {
    private enum PrivateFailure: Error { case invalidContents }
    private func fixture() throws -> URL {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func cancellationAndUnknownDetails() {
        #expect(OperationFailure.isCancellation(CancellationError()))
        #expect(OperationFailure.isCancellation(URLError(.cancelled)))
        #expect(OperationFailure.isCancellation(CocoaError(.userCancelled)))
        #expect(!OperationFailure.isCancellation(CocoaError(.fileReadNoPermission)))
        let error = NSError(domain: "Fixture", code: 42, userInfo: [NSLocalizedDescriptionKey: "specific reason"])
        #expect(OperationFailure.message("Import", error: error) == "Import\n\nspecific reason")
        let privateReason = OperationFailure.message("Import", error: PrivateFailure.invalidContents)
        #expect(privateReason.contains("invalidContents") && !privateReason.contains("unknown context"))
    }

    @Test func corruptPlacesArePreservedAndWriteCanRecover() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Places"), bytes = Data("corrupt".utf8)
        try bytes.write(to: url)
        let saver = PlaceSaver(url: url)
        await #expect(throws: (any Error).self) { try await saver.read() }
        await #expect(throws: (any Error).self) { try await saver.write(places: []) }
        #expect(try Data(contentsOf: url) == bytes)
        try FileManager.default.removeItem(at: url)
        #expect(try await saver.read().isEmpty)
        try await saver.write(places: [])
        #expect(try await saver.read().isEmpty)
        let blocker = root.appendingPathComponent("blocker")
        try bytes.write(to: blocker)
        let retry = PlaceSaver(url: blocker.appendingPathComponent("Places"))
        await #expect(throws: (any Error).self) { try await retry.write(places: []) }
        try FileManager.default.removeItem(at: blocker)
        try await retry.write(places: [])
        #expect(try await retry.read().isEmpty)
    }

    @Test func importAndCleanupReportMissingFilesAndContinue() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let photo = root.appendingPathComponent("good.jpg"), missing = root.appendingPathComponent("missing.jpg")
        try Data("fixture".utf8).write(to: photo)
        let result = PhotoTrailReducer().scanFiles([missing, photo])
        #expect(result.urls == [photo])
        #expect(result.failures.count == 1 && result.failures[0].contains("missing.jpg"))
        var errors: [String] = []
        #expect(PhotoTrailReducer().urlsIn(folder: missing, failures: &errors).isEmpty)
        #expect(!errors.isEmpty)
        let failures = await PhotoTrailReducer().removeFiles(filesToRemove: [missing, photo], from: root).value
        #expect(failures.count == 1 && !FileManager.default.fileExists(atPath: photo.path))
    }

    @Test func invalidImageProducesVisibleFailureState() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let image = root.appendingPathComponent("invalid.jpg")
        try Data("not an image".utf8).write(to: image)
        let store = Store(initialState: PhotoTrailState(), reduce: PhotoTrailReducer())
        await OpenHelper.importFiles(store, urls: [image], description: "fixture").value
        #expect(store.sheetType == .unexpectedErrorSheet)
        #expect(store.sheetError?.contains("invalid.jpg") == true)
        #expect(!store.importProgress.isActive)
    }

    @Test nonisolated func saveRetainsActualReasons() async {
        var reason = ""
        let outcome = await SaveHelper.saveThenTag(save: { throw CocoaError(.fileWriteNoPermission) }, tag: nil,
                                                   onFailure: { reason = $0.localizedDescription })
        #expect(outcome == .failed && !reason.isEmpty)
        reason = ""
        let tagOutcome = await SaveHelper.saveThenTag(save: {}, tag: { throw CocoaError(.fileWriteOutOfSpace) },
                                                      onFailure: { reason = $0.localizedDescription })
        #expect(tagOutcome == .savedWithoutTag && !reason.isEmpty)
    }

    @Test func saveWarningsReachTheUser() {
        var state = PhotoTrailState()
        let image = ImageData(metadata: Metadata(source: .image(URL(fileURLWithPath: "/tmp/fixture.jpg"))), name: "fixture.jpg")
        state.imageData = [image]
        let result = SaveHelper.LocalSaveResult(id: image.id, metadata: image.metadata, sidecarCreated: false,
                                               outcome: .failed, failure: "no space")
        state = PhotoTrailReducer().reduce(state, .localSaveBatch([result]))
        #expect(state.saveFailures == ["fixture.jpg: no space"])
        #expect(state.imageData[0].original == image.original)
        state = PhotoTrailReducer().reduce(state, .saveComplete(.saveError))
        #expect(state.sheetType == .saveErrorSheet)
        PhotoTrailReducer().save(&state)
        #expect(state.saveFailures.isEmpty)
        state = PhotoTrailReducer().reduce(state, .saveFailure("lookup failed"))
        state.sheetType = nil
        state = PhotoTrailReducer().reduce(state, .saveComplete(.saveOK))
        #expect(state.sheetType == .unexpectedErrorSheet && state.sheetError == "lookup failed")
        #expect(!SaveHelper.creatorFailure(.resultUnknown).isEmpty)
    }

    @Test func invalidPresetsAreNotAnEmptyList() throws {
        #expect(try MetadataPreset.stored(in: Data()).isEmpty)
        #expect(try MetadataPreset.stored(in: Data("[]".utf8)).isEmpty)
        #expect(throws: (any Error).self) { try MetadataPreset.stored(in: Data("invalid".utf8)) }
        #expect(throws: (any Error).self) {
            try MetadataPreset.stored(in: Data(#"[{"version":99,"name":"future","operations":[]}]"#.utf8))
        }
    }
}
