import Exiftool
import Foundation
import ImageData
import Imagetool
import Testing

@testable import PhotoTrail

@MainActor
struct MetadataClipboardTests {
    @Test func clipboardTimePreservesPrecisionAndInvalidTargetLeavesEverythingUnchanged() throws {
        let source = try #require(PhotoTrailState(forPreview: true).imageData.compactMap { image -> URL? in
            guard case .image(let url) = image.metadata.source, url.pathExtension.lowercased() == "jpg" else { return nil }
            return url
        }.first)
        let folder = URL.temporaryDirectory.appending(component: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(component: "clipboard.jpg")
        try FileManager.default.copyItem(at: source, to: url)
        let image = ImageData(metadata: Imagetool.metadata(from: url), name: url.lastPathComponent)
        let targets: [MetadataTag] = [.captureDate, .dateDigitized, .fileModifyDate, .iptcDateCreated, .iptcTimeCreated]
        let snapshot = try MetadataInspectionSnapshot.read(Set(targets + [.rating]), from: url)
        let before = try Data(contentsOf: url)
        let text = "2024:02:29 23:59:59.123456+08:00"
        let operations = try MetadataFieldClipboard.operations(text: text, targets: targets)
        let plan = try MetadataWorkflowPreview.prepare([(image, snapshot)], operations: operations)
        let changes = try #require(plan.items.first).changes
        #expect(changes[.captureDate] == .set(.text(text)))
        #expect(changes[.dateDigitized] == .set(.text(text)))
        var state = PhotoTrailState()
        state.imageData = [image]; state.selection = [image.id]
        let projection = PhotoListProjection()
        #expect(projection.selected(state).first?.creatorDraft == nil)
        let changed = PhotoTrailReducer().reduce(state, .creatorDraftApplied(plan.items))
        #expect(projection.selected(changed).first?.creatorDraft?.changes[.dateDigitized] == .set(.text(text)))
        #expect(changes[.fileModifyDate] == .set(.text(text)))
        #expect(changes[.iptcDateCreated] == .set(.text("2024:02:29")))
        #expect(changes[.iptcTimeCreated] == .set(.text("23:59:59+08:00")))
        #expect(throws: (any Error).self) {
            let invalid = try MetadataFieldClipboard.operations(text: text, targets: targets + [.rating])
            _ = try MetadataWorkflowPreview.prepare([(image, snapshot)], operations: invalid)
        }
        #expect(image.creatorDraft == nil)
        #expect(try Data(contentsOf: url) == before)
    }

    @Test func clipboardTextAndListsUseTheirOwnTypesAndRejectEmptyInput() throws {
        let operations = try MetadataFieldClipboard.operations(text: "Alice\nBob", targets: [.titleDefault, .creator, .subject])
        #expect(operations.map(\.action) == [.setText("Alice\nBob"), .replaceAuthors(["Alice", "Bob"]),
                                            .replaceKeywords(["Alice", "Bob"])])
        #expect(throws: (any Error).self) { try MetadataFieldClipboard.operations(text: "", targets: [.titleDefault]) }
        #expect(throws: (any Error).self) { try MetadataFieldClipboard.operations(text: "Alice", targets: []) }
    }
}
