import AppKit
import Exiftool
import Foundation
@testable import ImageData
import Metadata
import Testing
import UDF
@testable import PhotoTrail

@MainActor struct MetadataBatchEditingTests {
    func input(_ values: [[MetadataTag: MetadataTagValue]], sameName: Bool = false) throws -> (URL, [(image: ImageData, snapshot: MetadataInspectionSnapshot)]) {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let readings = try values.enumerated().map { index, values in
            let url = folder.appendingPathComponent("sample-\(index).jpg")
            try Data("synthetic-\(index)".utf8).write(to: url)
            let snapshot = MetadataInspectionSnapshot(url: url, requestedTags: Set(MetadataTag.allCases),
                values: values, version: MetadataInspectionFileVersion.read(url))
            let image = ImageData(metadata: Metadata(source: .image(url)), name: sameName ? "same.jpg" : url.lastPathComponent)
            return (image: image, snapshot: snapshot)
        }
        return (folder, readings)
    }

    @Test func independentFieldsKeepUntouchedValuesAndRequireExplicitClearing() throws {
        let (folder, readings) = try input([[.creator: .list(["A"]), .titleDefault: .text("one")],
                                          [.creator: .list(["B"]), .titleDefault: .text("two")]])
        defer { try? FileManager.default.removeItem(at: folder) }
        let session = MetadataBatchEditSession(readings: readings, tags: [.creator, .subject, .titleDefault])
        #expect(try session.operations.isEmpty)
        #expect(!session.hasInput)
        session.fields[0].input = "六九"; session.fields[0].mode = .set
        session.fields[1].input = "旅行\n胶片"; session.fields[1].mode = .append
        let operations = try session.operations
        #expect(operations.count == 2)
        let plan = try MetadataWorkflowPreview.prepare(readings, operations: operations)
        #expect(plan.items.count == 2)
        #expect(plan.items.allSatisfy { $0.changes[.creator] == .set(.list(["六九"])) })
        #expect(plan.items.allSatisfy { $0.changes[.titleDefault] == nil })
        session.fields[1].input = ""; session.fields[1].mode = .set
        #expect(!session.isValid)
        #expect(throws: Error.self) { try session.operations }
        session.fields[1].mode = .clear
        #expect(try session.operations.last?.action == .remove)
        #expect(try Data(contentsOf: readings[0].snapshot.url) == Data("synthetic-0".utf8))
    }

    @Test func distributionsPreserveExactUnicodeAndIndependentKeywordMembership() throws {
        let (folder, readings) = try input([[.subject: .list(["é", "旅行", "旅行"])],
                                          [.subject: .list(["e\u{301}", "旅行"])], [:],
                                          [.subject: .list(["旅行", "A,B"])]] )
        defer { try? FileManager.default.removeItem(at: folder) }
        let groups = MetadataBatchValues.groups(.subject, readings: readings)
        #expect(groups.count == 4)
        #expect(groups.first { $0.value == nil }?.photoIDs == [readings[2].image.id])
        let words = MetadataBatchValues.items(.subject, readings: readings)
        #expect(words.count == 4)
        #expect(words.first?.value == .list(["旅行"]))
        #expect(words.first?.photoIDs.count == 3) // Repeated tokens count a photo once.
        #expect(words.filter { $0.id == Data("é".utf8) }.count == 1)
        #expect(words.filter { $0.id == Data("e\u{301}".utf8) }.count == 1)
        var author = MetadataBatchField(tag: .creator)
        author.use(.list(["one\ntwo", "é", "e\u{301}"]))
        #expect(try author.operation()?.action == .replaceAuthors(["one\ntwo", "é", "e\u{301}"]))
    }

    @Test func narrowingKeepsTypedActionsAndFrozenOrder() throws {
        let (folder, readings) = try input([[:], [:], [:]])
        defer { try? FileManager.default.removeItem(at: folder) }
        let session = MetadataBatchEditSession(readings: readings, tags: [.titleDefault])
        session.fields[0].mode = .set; session.fields[0].input = "keep my input"
        session.narrow(to: [readings[2].image.id, readings[0].image.id])
        #expect(session.readings.map(\.image.id) == [readings[0].image.id, readings[2].image.id])
        #expect(try session.operations.first?.action == .setText("keep my input"))
        session.narrow(to: [])
        #expect(session.readings.count == 2)
    }

    @Test func timeExamplesUseFullBatchSpacingAndPreserveNineDigits() throws {
        let (folder, readings) = try input(Array(repeating: [.captureDate: .text("2024:01:02 03:04:05.123456789+08:00")], count: 5))
        defer { try? FileManager.default.removeItem(at: folder) }
        for action: MetadataFieldEditAction in [
            .sequence(start: "2024:01:02 03:04:05.123456789+08:00", stepSeconds: 7),
            .distribute(start: "2024:01:02 03:04:05.123456789+08:00", end: "2024:01:02 03:04:45.123456789+08:00")] {
            let operations = [MetadataOperation(tag: .captureDate, action: action)]
            let plan = try MetadataWorkflowPreview.prepare(readings, operations: operations)
            let examples = try MetadataBatchEditSession.sample(readings, operations: operations)
            #expect(examples.count == 3)
            for index in 0..<3 {
                let change = plan.items.first { $0.id == readings[index].image.id }?.changes[.captureDate]
                let expected: MetadataTagValue?
                if case .set(let value) = change { expected = value }
                else { expected = readings[index].snapshot.values[.captureDate] }
                #expect(examples[index].hasSuffix("→ " + MetadataBatchValues.text(expected)))
            }
        }
        var field = MetadataBatchField(tag: .captureDate)
        field.mode = .set; field.input = "2024-01-02T03:04:05.123456789+08:00"
        #expect(try field.operation()?.action == .setText("2024:01:02 03:04:05.123456789+08:00"))
        field.mode = .offset; field.offsets[3] = "2"; field.subtract = true
        #expect(try field.operation()?.action == .offsetDate(years: 0, months: 0, days: 0, hours: -2, minutes: 0, seconds: 0))
    }

    @Test func skippedOperationsKeepPhotoIdentityWithDuplicateFilenames() throws {
        let (folder, readings) = try input([[:], [:], [:]], sameName: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let result = try MetadataWorkflowPreview.prepare(readings,
            operations: [MetadataOperation(tag: .dateOriginal, action: .copy(.captureDate))])
        #expect(result.skipDetails.count == 3)
        #expect(Set(result.skipDetails.map(\.photoID)) == Set(readings.map(\.image.id)))
        #expect(result.skipDetails.allSatisfy { $0.reason == .missingValue && $0.tag == .dateOriginal })
    }

    @Test func appliedFormSharesUndoAndDoesNotUndoALaterAction() async throws {
        let (folder, readings) = try input([[:], [:]])
        defer { try? FileManager.default.removeItem(at: folder) }
        var state = PhotoTrailState(); state.imageData = readings.map(\.image); state.selection = Set(readings.map(\.image.id))
        let store = Store(initialState: state, reduce: PhotoTrailReducer(), undoEnabled: true)
        let session = MetadataBatchEditSession(readings: readings, tags: [.titleDefault])
        session.fields[0].input = "new"; session.fields[0].mode = .set
        session.application.apply(readings: readings, operations: try session.operations, description: "named batch", store: store)
        while session.application.busy { try await Task.sleep(for: .milliseconds(5)) }
        #expect(session.application.applied)
        #expect(!session.hasInput)
        #expect(session.application.canUndo(in: store))
        store.send(.selectionChanged([readings[0].image.id]), description: "later selection")
        #expect(!session.application.canUndo(in: store))
        session.application.undo(in: store)
        #expect(store.imageData.allSatisfy { $0.creatorDraft != nil })
        store.undo()
        session.application.undo(in: store)
        #expect(store.imageData.allSatisfy { $0.creatorDraft == nil })
        #expect(session.hasInput) // The user's input remains available for another Apply.
    }

    @Test func quitWithUnappliedInputRequiresConfirmationWithoutPhotoDrafts() {
        let state = PhotoTrailState()
        let result = PhotoTrailReducer().reduce(state, .quitWithMetadataInputRequested)
        #expect(!state.unsavedChanges)
        #expect(result.presentConfirmation)
        #expect(result.confirmationEvent == .terminateRequest)
    }

    @Test func delegateProtectsInputAndExplicitDiscardAllowsQuit() throws {
        let (folder, readings) = try input([[:]])
        defer { try? FileManager.default.removeItem(at: folder) }
        let session = MetadataBatchEditSession(readings: readings, tags: [.titleDefault])
        session.fields[0].input = "unapplied"; session.fields[0].mode = .set
        let delegate = AppDelegate()
        delegate.store = Store(initialState: PhotoTrailState(), reduce: PhotoTrailReducer(), undoEnabled: false)
        delegate.metadataEditSession = session
        #expect(delegate.applicationShouldTerminate(NSApp) == .terminateCancel)
        #expect(delegate.store?.presentConfirmation == true)
        session.discardInput()
        #expect(!session.hasInput)
        #expect(delegate.applicationShouldTerminate(NSApp) == .terminateNow)
    }

    @Test func completedNoOpDoesNotLeavePhantomUnappliedInput() async throws {
        let (folder, readings) = try input([[.titleDefault: .text("same")]])
        defer { try? FileManager.default.removeItem(at: folder) }
        var state = PhotoTrailState(); state.imageData = readings.map(\.image); state.selection = Set(readings.map(\.image.id))
        let store = Store(initialState: state, reduce: PhotoTrailReducer(), undoEnabled: true)
        let session = MetadataBatchEditSession(readings: readings, tags: [.titleDefault])
        session.fields[0].mode = .set
        #expect(session.hasInput)
        session.application.apply(readings: readings, operations: try session.operations, store: store)
        while session.application.busy { try await Task.sleep(for: .milliseconds(5)) }
        #expect(session.application.result?.items.isEmpty == true)
        #expect(!session.hasInput)
        session.narrow(to: session.photoIDs)
        #expect(session.application.result == nil)
        #expect(session.hasInput)
        session.fields[0].input = "different"
        session.application.resetFeedback()
        #expect(session.hasInput)
    }
    @Test func operationCountsPartitionPhotosAndFollowEarlierActions() throws {
        let date = "2024:01:02 03:04:05.123456789+08:00"
        let (folder, readings) = try input([
            [.creator: .list(["A"]), .captureDate: .text(date), .dateOriginal: .text(date)],
            [.creator: .list(["B"]), .captureDate: .text(date)], [:]])
        defer { try? FileManager.default.removeItem(at: folder) }
        let plan = try MetadataWorkflowPreview.prepare(readings, operations: [
            MetadataOperation(tag: .creator, action: .replaceAuthors(["A"])),
            MetadataOperation(tag: .creator, action: .replaceAuthors(["A"])),
            MetadataOperation(tag: .dateOriginal, action: .copy(.captureDate))])
        #expect(plan.operationResults.count == 3)
        #expect(plan.operationResults[0].changed.count == 2)
        #expect(plan.operationResults[0].unchanged.count == 1)
        #expect(plan.operationResults[1].changed.isEmpty)
        #expect(plan.operationResults[1].unchanged.count == 3)
        let dates = plan.operationResults[2]
        #expect(dates.changed == [readings[1].image.id])
        #expect(dates.unchanged == [readings[0].image.id])
        #expect(dates.skipped == [readings[2].image.id])
        for result in plan.operationResults {
            #expect(result.changed.isDisjoint(with: result.unchanged))
            #expect(result.changed.union(result.unchanged).isDisjoint(with: result.skipped))
            #expect(result.changed.union(result.unchanged).union(result.skipped) == Set(readings.map(\.image.id)))
        }
        let sidecars = try readings.map { reading in
            let url = reading.snapshot.url.deletingPathExtension().appendingPathExtension("xmp")
            try Data("synthetic sidecar".utf8).write(to: url)
            let snapshot = MetadataInspectionSnapshot(url: url, requestedTags: Set(MetadataTag.allCases),
                values: [:], version: MetadataInspectionFileVersion.read(url))
            return (image: ImageData(metadata: Metadata(source: .xmp(reading.snapshot.url)), name: reading.image.name), snapshot: snapshot)
        }
        let unsupported = try MetadataWorkflowPreview.prepare(sidecars,
            operations: [MetadataOperation(tag: .fileCreateDate, action: .setText(date))])
        #expect(unsupported.operationResults[0].skipped.count == 3)
    }

    @Test func taskListAllowsRepeatedFieldsAndRemovalWithoutPhotoChanges() async throws {
        let (folder, readings) = try input([[.creator: .list(["A"])], [:]])
        defer { try? FileManager.default.removeItem(at: folder) }
        let session = MetadataBatchEditSession(readings: readings, tags: [])
        #expect(session.fields.isEmpty)
        session.add(.creator); session.add(.creator)
        #expect(session.fields.count == 2)
        #expect(session.fields[0].id != session.fields[1].id)
        session.fields[0].mode = .set; session.fields[0].input = "B"
        session.fields[1].mode = .set; session.fields[1].input = "B"
        session.refreshStatistics()
        while session.statisticsBusy { try await Task.sleep(for: .milliseconds(5)) }
        #expect(session.statistics[session.fields[0].id]?.changed.count == 2)
        #expect(session.statistics[session.fields[1].id]?.unchanged.count == 2)
        let removed = session.fields[0].id
        session.remove(removed); session.refreshStatistics()
        while session.statisticsBusy { try await Task.sleep(for: .milliseconds(5)) }
        #expect(session.fields.count == 1)
        #expect(session.statistics[removed] == nil)
        #expect(readings.allSatisfy { $0.image.creatorDraft == nil })
    }

    @Test func inlineFinishAppliesOnlyFrozenPhotoEvenAfterSelectionChanges() async throws {
        let (folder, readings) = try input([[.exifComment: .text("old")], [.exifComment: .text("other")]])
        defer { try? FileManager.default.removeItem(at: folder) }
        var state = PhotoTrailState(); state.imageData = readings.map(\.image); state.selection = [readings[1].image.id]
        let store = Store(initialState: state, reduce: PhotoTrailReducer(), undoEnabled: true)
        let session = MetadataBatchEditSession(readings: [readings[0]], tags: [.exifComment], inline: true)
        session.fields[0].input = "new note"; session.fields[0].mode = .set
        #expect(await session.finishInline(in: store))
        #expect(store[readings[0].image.id].creatorDraft?.changes[.exifComment] == .set(.text("new note")))
        #expect(store[readings[1].image.id].creatorDraft == nil)
        #expect(store.state.selection == [readings[1].image.id])
        #expect(store.unsavedChanges)
        #expect(try Data(contentsOf: readings[0].snapshot.url) == Data("synthetic-0".utf8))
        store.undo()
        #expect(store.imageData.allSatisfy { $0.creatorDraft == nil })
    }

    @Test func inlineClearAndSourceFailureNeverSilentlyLoseInput() async throws {
        let (folder, readings) = try input([[.exifComment: .text("old")]])
        defer { try? FileManager.default.removeItem(at: folder) }
        var state = PhotoTrailState(); state.imageData = readings.map(\.image); state.selection = [readings[0].image.id]
        let store = Store(initialState: state, reduce: PhotoTrailReducer(), undoEnabled: true)
        let clear = MetadataBatchEditSession(readings: readings, tags: [.exifComment], inline: true)
        clear.fields[0].mode = .clear
        #expect(await clear.finishInline(in: store))
        #expect(store[readings[0].image.id].creatorDraft?.changes[.exifComment] == .remove)
        store.undo()
        let invalid = MetadataBatchEditSession(readings: readings, tags: [.exifISO], inline: true)
        invalid.fields[0].mode = .set; invalid.fields[0].input = "not a number"
        #expect(!(await invalid.finishInline(in: store)))
        #expect(invalid.hasInput && store.imageData[0].creatorDraft == nil)
        let stale = MetadataBatchEditSession(readings: readings, tags: [.exifComment], inline: true)
        stale.fields[0].mode = .set; stale.fields[0].input = "retain this"
        try Data("external change".utf8).write(to: readings[0].snapshot.url)
        #expect(!(await stale.finishInline(in: store)))
        #expect(stale.hasInput && store.imageData[0].creatorDraft == nil)
    }

    @Test func focusSynchronizationDoesNotActivateAnUnchangedField() throws {
        var field = MetadataBatchField(tag: .exifComment, value: .text("old note"))
        field.updateInput("old note", clearEmpty: true)
        #expect(field.mode == .keep)
        #expect(try field.operation() == nil)
        field.updateInput("new note", clearEmpty: true)
        #expect(try field.operation()?.action == .setText("new note"))
        field.updateInput("", clearEmpty: true)
        #expect(try field.operation()?.action == .remove)
        var empty = MetadataBatchField(tag: .captureDate)
        empty.updateInput("")
        #expect(empty.mode == .keep)
        empty.mode = .offset
        empty.updateInput("")
        #expect(empty.mode == .offset)
    }

    @Test func copyOutExpandsDestinationsUsingEachPhotoAndKeepsPresetCompatibility() throws {
        let first = "2024:01:02 03:04:05.123456789+08:00", second = "2025:02:03 04:05:06"
        let (folder, readings) = try input([[.captureDate: .text(first), .dateOriginal: .text(first)],
                                           [.captureDate: .text(second)], [:]])
        defer { try? FileManager.default.removeItem(at: folder) }
        var field = MetadataBatchField(tag: .captureDate)
        field.mode = .copyTo
        #expect(throws: Error.self) { try field.operations }
        field.destinations = [.dateOriginal, .dateDigitized]
        let operations = try field.operations
        #expect(operations.count == 2)
        #expect(operations.allSatisfy { $0.action == .copy(.captureDate) })
        let plan = try MetadataWorkflowPreview.prepare(readings, operations: operations)
        for (index, date) in [first, second].enumerated() {
            let item = try #require(plan.items.first { $0.id == readings[index].image.id })
            #expect(item.changes[.dateDigitized] == .set(.text(date)))
            #expect(item.changes[.captureDate] == nil)
        }
        #expect(plan.skipDetails.count == 2)
        let stats = try #require(MetadataBatchItemStatistics.group(plan.operationResults, by: [(field.id, 2)])[field.id])
        #expect(stats.changed.count == 2 && stats.skipped.count == 1 && stats.unchanged.isEmpty)
        let preset = try MetadataPreset(name: "copy out", operations: operations)
        #expect(try MetadataPreset.decode(preset.encode()).operations == operations)
        field.destinations = [.captureDate]
        #expect(throws: Error.self) { try field.operations }
        field.destinations = [.creator]
        #expect(throws: Error.self) { try field.operations }
    }

    @Test func duplicateInsertsBelowAndPreservesAllSettingsWithIndependentIdentity() throws {
        let (folder, readings) = try input([[:]])
        defer { try? FileManager.default.removeItem(at: folder) }
        let session = MetadataBatchEditSession(readings: readings, tags: [.creator, .captureDate, .subject])
        session.fields[1].mode = .copyTo; session.fields[1].destinations = [.dateOriginal, .dateDigitized]
        session.fields[1].offsets[3] = "2"; session.fields[1].subtract = true
        session.fields[1].input = "2024:01:02 03:04:05.123456789+08:00"
        let original = session.fields[1]
        session.duplicate(original.id)
        #expect(session.fields.count == 4)
        let copy = session.fields[2]
        #expect(copy.id != original.id)
        #expect(copy.tag == original.tag && copy.mode == original.mode)
        #expect(copy.destinations == original.destinations && copy.offsets == original.offsets)
        #expect(copy.input == original.input && copy.subtract == original.subtract)
        #expect(try copy.operations == original.operations)
        session.fields[2].destinations.remove(.dateOriginal)
        #expect(session.fields[1].destinations.count == 2)
        var authors = MetadataBatchField(tag: .creator)
        authors.use(.list(["one\ntwo", "é", "e\u{301}"]))
        #expect(try authors.duplicated().operation()?.action == authors.operation()?.action)
    }

    @Test func copyOutStatisticsPartitionPartialDestinationSkips() throws {
        let (folder, readings) = try input([[.captureDate: .text("2024:01:02 03:04:05")], [:]])
        defer { try? FileManager.default.removeItem(at: folder) }
        let ids = readings.map(\.image.id)
        let session = MetadataBatchEditSession(readings: readings, tags: [.captureDate, .titleDefault])
        session.fields[0].mode = .copyTo; session.fields[0].destinations = [.dateOriginal, .dateDigitized]
        session.fields[1].mode = .set; session.fields[1].input = "title"
        let result = try MetadataWorkflowPreview.prepare(readings, operations: session.operations)
        let grouped = MetadataBatchItemStatistics.group(result.operationResults, by: [(session.fields[0].id, 2), (session.fields[1].id, 1)])
        #expect(grouped[session.fields[0].id]?.changed == [ids[0]])
        #expect(grouped[session.fields[0].id]?.skipped == [ids[1]])
        #expect(grouped[session.fields[1].id]?.changed == Set(ids))
        let sidecars = try [[:], [MetadataTag.sidecarDate: MetadataTagValue.text("2024:01:02 03:04:05")]].enumerated().map { index, values in
            let imageURL = folder.appendingPathComponent("mixed-\(index).jpg")
            let url = imageURL.deletingPathExtension().appendingPathExtension("xmp")
            try Data("image".utf8).write(to: imageURL); try Data("sidecar".utf8).write(to: url)
            var values = values; values[.dateOriginal] = .text("2024:01:02 03:04:05")
            return (image: ImageData(metadata: Metadata(source: .xmp(imageURL)), name: "mixed-\(index).jpg"),
                    snapshot: MetadataInspectionSnapshot(url: url, requestedTags: Set(MetadataTag.allCases),
                        values: values, version: MetadataInspectionFileVersion.read(url)))
        }
        var mixed = MetadataBatchField(tag: .dateOriginal)
        mixed.mode = .copyTo; mixed.destinations = [.sidecarDate, .fileCreateDate]
        let partial = try MetadataWorkflowPreview.prepare(sidecars, operations: mixed.operations)
        let aggregate = try #require(MetadataBatchItemStatistics.group(partial.operationResults, by: [(mixed.id, 2)])[mixed.id])
        #expect(aggregate.changed == [sidecars[0].image.id])
        #expect(aggregate.skipped == [sidecars[1].image.id])
        #expect(aggregate.unchanged.isEmpty)
    }

}

extension MetadataBatchEditingTests {
    @Test func hiddenRulesStillProtectQuitWhileInlineEditingIsIndependent() throws {
        let (folder, readings) = try input([[:]])
        defer { try? FileManager.default.removeItem(at: folder) }
        let rules = MetadataBatchEditSession(readings: readings, tags: [.titleDefault])
        rules.fields[0].mode = .set; rules.fields[0].input = "retained rule"
        let inline = MetadataBatchEditSession(readings: readings, tags: [.creator], inline: true)
        let delegate = AppDelegate()
        delegate.store = Store(initialState: PhotoTrailState(), reduce: PhotoTrailReducer(), undoEnabled: false)
        delegate.metadataRuleSession = rules
        delegate.metadataEditSession = inline
        #expect(!inline.hasInput && rules.hasInput)
        #expect(delegate.applicationShouldTerminate(NSApp) == .terminateCancel)
        inline.discardInput()
        #expect(rules.fields[0].input == "retained rule" && rules.hasInput)
        rules.discardInput()
        #expect(delegate.applicationShouldTerminate(NSApp) == .terminateNow)
    }

}
