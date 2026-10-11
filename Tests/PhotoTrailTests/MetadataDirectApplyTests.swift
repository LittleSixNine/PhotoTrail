import Exiftool
import Foundation
@testable import ImageData
import Metadata
import Testing
import UDF
@testable import PhotoTrail

@MainActor struct MetadataDirectApplyTests {
    func input(_ count: Int) throws -> (URL, [(image: ImageData, snapshot: MetadataInspectionSnapshot)]) {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let readings = try (0..<count).map { index in
            let url = folder.appendingPathComponent(String(format: "synthetic-%03d.jpg", index))
            try Data("synthetic-\(index)".utf8).write(to: url)
            let snapshot = MetadataInspectionSnapshot(url: url, requestedTags: [.creator, .captureDate, .titleDefault, .rightsDefault], values: [:], version: MetadataInspectionFileVersion.read(url))
            return (image: ImageData(metadata: Metadata(source: .image(url)), name: url.lastPathComponent), snapshot: snapshot)
        }
        return (folder, readings)
    }

    @Test func scaleCommitAndUndo() throws {
        let (folder, readings) = try input(530)
        defer { try? FileManager.default.removeItem(at: folder) }
        var state = PhotoTrailState(); state.imageData = readings.map(\.image); state.selection = Set(readings.map(\.image.id))
        let store = Store(initialState: state, reduce: PhotoTrailReducer(), undoEnabled: true)
        let plan = try MetadataWorkflowPreview.prepare(readings, operations: [MetadataOperation(tag: .titleDefault, action: .setText("Synthetic"))])
        for iteration in 0..<3 {
            let start = Date()
            store.send(.creatorDraftApplied(plan.items))
            print("COMMIT count=530 iteration=\(iteration) elapsed=\(Date().timeIntervalSince(start))")
            #expect(store.imageData.allSatisfy { $0.creatorDraft?.changes[.titleDefault] == .set(.text("Synthetic")) })
            store.undo()
            #expect(store.imageData.allSatisfy { $0.creatorDraft == nil })
        }
    }

    @Test func requestRejectsSelectionDraftMetadataSavingAndSkippedSourceChanges() throws {
        let (folder, readings) = try input(3)
        defer { try? FileManager.default.removeItem(at: folder) }
        var state = PhotoTrailState(); state.imageData = readings.map(\.image); state.selection = Set(readings.map(\.image.id))
        let request = MetadataDraftRequest(readings: readings)
        #expect(request.matches(state, checkFiles: true))
        var other = state; other.selection.remove(readings[0].image.id); #expect(!request.matches(other))
        other = state; other.saveInProgress = true; #expect(!request.matches(other))
        other = state; other.imageData[0].metadata.dateTimeCreated = "2024:01:15 10:20:30"; #expect(!request.matches(other))
        let old = try MetadataCreatorEditPlan.prepare(readings, tag: .rightsDefault, action: .setText("old"))
        other = state; other.imageData[0].applyMetadataDraft(old.items[0]); #expect(!request.matches(other))
        other = state; other.creatorSaveResults[readings[0].image.id] = .resultUnknown; #expect(!request.matches(other))
        try Data("changed skipped source".utf8).write(to: readings[1].snapshot.url)
        #expect(!request.matches(state, checkFiles: true))
    }

    @Test func asynchronousApplyCancellationAndOldDraftPreservation() async throws {
        let (folder, original) = try input(530)
        defer { try? FileManager.default.removeItem(at: folder) }
        var readings = original
        let old = try MetadataCreatorEditPlan.prepare(readings, tag: .rightsDefault, action: .setText("old"))
        for index in readings.indices { readings[index].image.applyMetadataDraft(old.items[index]) }
        var state = PhotoTrailState(); state.imageData = readings.map(\.image); state.selection = Set(readings.map(\.image.id))
        let store = Store(initialState: state, reduce: PhotoTrailReducer(), undoEnabled: true)
        let application = MetadataDraftApplication()
        let operations = [MetadataOperation(tag: .titleDefault, action: .setText("Synthetic"))]
        application.apply(readings: readings, operations: operations, store: store)
        #expect(application.busy)
        application.cancel()
        try await Task.sleep(for: .milliseconds(100))
        #expect(store.imageData.map(\.creatorDraft) == readings.map(\.image.creatorDraft))
        application.apply(readings: readings, operations: operations, store: store)
        while application.busy { try await Task.sleep(for: .milliseconds(10)) }
        #expect(store.imageData.allSatisfy { $0.creatorDraft?.changes[.titleDefault] == .set(.text("Synthetic")) })
        #expect(store.imageData.allSatisfy { $0.creatorDraft?.changes[.rightsDefault] == .set(.text("old")) })
        store.undo()
        #expect(store.imageData.map(\.creatorDraft) == readings.map(\.image.creatorDraft))
    }
}

extension MetadataDirectApplyTests {
    @Test(arguments: ["cancel", "selection", "draft", "source", "save"])
    func changesDuringStartedCalculationRejectEntireBatch(reason: String) async throws {
        let (folder, readings) = try input(530)
        defer { try? FileManager.default.removeItem(at: folder) }
        var state = PhotoTrailState(); state.imageData = readings.map(\.image); state.selection = Set(readings.map(\.image.id))
        let store = Store(initialState: state, reduce: PhotoTrailReducer(), undoEnabled: true)
        let application = MetadataDraftApplication()
        let operations = [MetadataOperation(tag: .captureDate, action: .shiftDate(seconds: 1))]
            + (0..<200).map { MetadataOperation(tag: .titleDefault, action: .setText("Synthetic \($0)")) }
        application.apply(readings: readings, operations: operations, store: store)
        while !application.calculationStarted && application.busy { try await Task.sleep(for: .milliseconds(1)) }
        #expect(application.calculationStarted)
        try await Task.sleep(for: .milliseconds(20))
        #expect(application.busy)
        switch reason {
        case "cancel": application.cancel()
        case "selection":
            store.send(.selectionChanged([readings[0].image.id]))
            application.stateChanged(store.state)
        case "draft":
            let old = try MetadataCreatorEditPlan.prepare([readings[0]], tag: .rightsDefault, action: .setText("new external draft"))
            store.send(.creatorDraftApplied(old.items))
            application.stateChanged(store.state)
        case "source":
            // This photo has no date and is skipped by the first operation.
            try Data("changed skipped source".utf8).write(to: readings[1].snapshot.url)
        default:
            var saving = store.state; saving.saveInProgress = true
            application.stateChanged(saving)
        }
        while application.busy { try await Task.sleep(for: .milliseconds(10)) }
        try await Task.sleep(for: .milliseconds(100))
        #expect(store.imageData.allSatisfy { $0.creatorDraft?.changes[.titleDefault] == nil })
        if reason == "draft" {
            #expect(store.imageData[0].creatorDraft?.changes[.rightsDefault] == .set(.text("new external draft")))
            #expect(store.imageData.dropFirst().allSatisfy { $0.creatorDraft == nil })
        } else { #expect(store.imageData.allSatisfy { $0.creatorDraft == nil }) }
        if reason == "cancel" {
            application.apply(readings: readings, operations: [MetadataOperation(tag: .titleDefault, action: .setText("new request"))], store: store)
            while application.busy { try await Task.sleep(for: .milliseconds(10)) }
            #expect(store.imageData.allSatisfy { $0.creatorDraft?.changes[.titleDefault] == .set(.text("new request")) })
        }
    }
}
