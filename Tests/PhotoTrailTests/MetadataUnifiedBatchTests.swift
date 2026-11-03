import Exiftool
import Foundation
import ImageData
import Metadata
import Testing
import UDF
@testable import PhotoTrail

@MainActor struct MetadataUnifiedBatchTests {
    @Test func cardsReadEarlierResultsAndCopyPoliciesNeverChangeSource() throws {
        let time = "2024:02:29 12:34:56.123456789"
        let (folder, readings) = try MetadataBatchEditingTests().input([[.captureDate: .text(time)], [:]])
        defer { try? FileManager.default.removeItem(at: folder) }
        let shift = MetadataWorkflowCard(operations: [MetadataOperation(tag: .captureDate,
            action: .offsetDate(years: 0, months: 0, days: 0, hours: 1, minutes: 0, seconds: 0))])
        var copy = MetadataWorkflowCard(operations: [.init(tag: .dateOriginal, action: .copy(.captureDate))])
        copy.datePolicy.offset = "+08:00"
        copy.datePolicy.missingTime = "2024:03:01 00:00:00"
        let result = try MetadataBatchRecipe.prepare(readings, cards: [shift, copy])
        #expect(result.preview.items.count == 2)
        #expect(result.preview.items[0].changes[.captureDate] == .set(.text("2024:02:29 13:34:56.123456789")))
        #expect(result.preview.items[0].changes[.dateOriginal] == .set(.text("2024:02:29 13:34:56.123456789+08:00")))
        #expect(result.preview.items[1].changes[.captureDate] == nil)
        #expect(result.preview.items[1].changes[.dateOriginal] == .set(.text("2024:03:01 00:00:00+08:00")))
        #expect(readings.allSatisfy { $0.image.creatorDraft == nil })
    }

    @Test func missingTimeZoneOnlySkipsIPTCAndCancelledChainsHaveNoNetDraft() throws {
        let time = "2024:02:29 12:34:56.123456789"
        let (folder, readings) = try MetadataBatchEditingTests().input([[.captureDate: .text(time)]])
        defer { try? FileManager.default.removeItem(at: folder) }
        let copy = MetadataWorkflowCard(operations: [.init(tag: .dateOriginal, action: .copy(.captureDate)),
                                                      .init(tag: .iptcTimeCreated, action: .copy(.captureDate))])
        let result = try MetadataBatchRecipe.prepare(readings, cards: [copy])
        #expect(result.preview.items[0].changes[.dateOriginal] == .set(.text(time)))
        #expect(result.preview.items[0].changes[.iptcTimeCreated] == nil)
        #expect(result.issues.contains { $0.tag == .iptcTimeCreated })
        let out = MetadataWorkflowCard(operations: [.init(tag: .captureDate, action: .shiftDate(seconds: 1))])
        let back = MetadataWorkflowCard(operations: [.init(tag: .captureDate, action: .shiftDate(seconds: -1))])
        #expect(try MetadataBatchRecipe.prepare(readings, cards: [out, back]).preview.items.isEmpty)
    }

    @Test func presetEditsAreTemporaryUntilExplicitStoreAndPreserveOldV1() throws {
        let preset = try MetadataPreset(name: "dates", operations: [.init(tag: .dateOriginal, action: .copy(.captureDate))])
        let original = try JSONEncoder().encode([preset])
        let session = try MetadataPresetSession(preset: preset, parameters: Data())
        session.cards[0].datePolicy.offset = "+08:00"
        #expect(try MetadataPreset.stored(in: original) == [preset])
        #expect(try MetadataPresetParameters.cards(preset, data: Data())[0].datePolicy.isEmpty)
        let saved = try MetadataPresetSession.stored(name: "dates", cards: session.cards,
            presetData: original, parameterData: Data(), replace: true)
        #expect(try MetadataPreset.stored(in: saved.0) == [preset])
        let cards = try MetadataPresetParameters.cards(preset, data: saved.1)
        #expect(cards[0].datePolicy.offset == "+08:00")
        let reopened = try MetadataPresetSession(preset: preset, parameters: saved.1)
        reopened.cards[0].datePolicy.offset = "+09:00"
        #expect(try MetadataPresetParameters.cards(preset, data: saved.1)[0].datePolicy.offset == "+08:00")
        let renamed = try MetadataPresetParameters.renamed("dates", to: "copy", data: saved.1, copy: true)
        let duplicate = try MetadataPreset(name: "copy", operations: preset.operations)
        #expect(try MetadataPresetParameters.cards(duplicate, data: renamed)[0].datePolicy.offset == "+08:00")
        #expect(throws: Error.self) {
            try MetadataPresetSession.stored(name: "dates", cards: session.cards, presetData: original, parameterData: Data(), replace: false)
        }
        #expect(throws: Error.self) {
            try MetadataPresetSession.stored(name: "new", cards: session.cards, presetData: Data("bad".utf8), parameterData: Data(), replace: false)
        }
    }

    @Test func malformedSavedParametersNeverOverwriteExistingPresets() throws {
        let operations = [MetadataOperation(tag: .captureDate, action: .setText("invalid"))]
        let card = MetadataWorkflowCard(operations: operations)
        #expect(throws: Error.self) { try MetadataPresetSession.stored(name: "invalid", cards: [card], presetData: Data(), parameterData: Data(), replace: false) }
        var date = MetadataWorkflowCard(operations: [.init(tag: .dateOriginal, action: .copy(.captureDate))])
        date.datePolicy.offset = "+14:30"
        #expect(throws: Error.self) { try MetadataBatchRecipe.validate([date]) }
        let sequence = MetadataWorkflowCard(operations: [.init(tag: .captureDate, action: .sequence(start: "2024:02:29 12:00:00", stepSeconds: 60))])
        try MetadataBatchRecipe.validate([sequence])
    }

    @Test func adjacentCopyCardsKeepSeparatePoliciesWhenReopened() throws {
        var first = MetadataWorkflowCard(operations: [.init(tag: .dateOriginal, action: .copy(.captureDate))])
        var second = MetadataWorkflowCard(operations: [.init(tag: .dateModified, action: .copy(.captureDate))])
        first.datePolicy.offset = "+08:00"; second.datePolicy.offset = "+09:00"
        let saved = try MetadataPresetSession.stored(name: "separate", cards: [first, second],
            presetData: Data(), parameterData: Data(), replace: false)
        let preset = try #require(MetadataPreset.stored(in: saved.0).first)
        let reopened = try MetadataPresetParameters.cards(preset, data: saved.1)
        #expect(reopened.map(\.operations) == [first.operations, second.operations])
        #expect(reopened.map(\.datePolicy) == [first.datePolicy, second.datePolicy])
    }

    @Test func allPhotosRequestIgnoresSelectionButRejectsNewPhotosAndOrderChanges() throws {
        let (folder, readings) = try MetadataBatchEditingTests().input([[:], [:], [:]])
        defer { try? FileManager.default.removeItem(at: folder) }
        var state = PhotoTrailState(); state.imageData = readings.map(\.image)
        let indices = Dictionary(uniqueKeysWithValues: state.imageData.sorted(using: state.sortOrder).enumerated().map { ($0.element.id, $0.offset) })
        let ordered = readings.sorted { indices[$0.image.id, default: 0] < indices[$1.image.id, default: 0] }
        let request = MetadataDraftRequest(readings: ordered, requiresSelection: false, requiresAllPhotos: true)
        state.selection = [readings[0].image.id]
        #expect(request.matches(state, checkFiles: true))
        state.selection = [readings[2].image.id]
        #expect(request.matches(state, checkFiles: true))
        let extra = ImageData(metadata: Metadata(source: .image(folder.appendingPathComponent("extra.jpg"))), name: "extra.jpg")
        state.imageData.append(extra)
        #expect(!request.matches(state))
        state.imageData.removeLast()
        let reversed = MetadataDraftRequest(readings: Array(ordered.reversed()), requiresSelection: false, requiresAllPhotos: true)
        #expect(!reversed.matches(state))
        state.imageData.removeLast()
        #expect(!request.matches(state))
    }

    @Test func applyAllLoadsAndChangesUnselectedPhotosWithoutSavingPreset() async throws {
        let (folder, readings) = try MetadataBatchEditingTests().input([[:], [:], [:]])
        defer { try? FileManager.default.removeItem(at: folder) }
        var state = PhotoTrailState(); state.imageData = readings.map(\.image); state.selection = [readings[0].image.id]
        let store = Store(initialState: state, reduce: PhotoTrailReducer(), undoEnabled: true)
        let snapshots = Dictionary(uniqueKeysWithValues: readings.map { ($0.image.id, $0.snapshot) })
        let queue = MetadataLoadingQueue(reader: { job in
            guard let snapshot = snapshots[job.request.id] else { return nil }
            return .editable(snapshot, [:])
        })
        let preset = try MetadataPreset(name: "title", operations: [.init(tag: .titleDefault, action: .setText("saved"))])
        let session = try MetadataPresetSession(preset: preset, parameters: Data())
        session.cards[0].operations = [.init(tag: .titleDefault, action: .setText("temporary"))]
        session.applyAll(in: store, queue: queue)
        while session.busy { try await Task.sleep(for: .milliseconds(5)) }
        #expect(session.application.result?.items.count == 3)
        #expect(store.imageData.allSatisfy { $0.creatorDraft?.changes[.titleDefault] == .set(.text("temporary")) })
        #expect(session.original == preset)
        store.undo()
        #expect(store.imageData.allSatisfy { $0.creatorDraft == nil })
    }
}
