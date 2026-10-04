import AppKit
import Exiftool
import ImageData
import Imagetool
import Testing
import UDF
@testable import PhotoTrail

@MainActor
struct MetadataQuickEditTests {
    @Test func quickChangesStayOnFrozenTargetsAndShareUndoAndSavePlans() throws {
        let source = try #require(PhotoTrailState(forPreview: true).imageData.compactMap { image -> URL? in
            guard case .image(let url) = image.metadata.source, url.pathExtension.lowercased() == "jpg" else { return nil }
            return url
        }.first)
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let urls = ["one.jpg", "two.jpg"].map { folder.appending(path: $0) }
        for url in urls { try FileManager.default.copyItem(at: source, to: url) }
        let bytes = try urls.map { try Data(contentsOf: $0) }
        var state = PhotoTrailState()
        state.imageData = urls.map { ImageData(metadata: Imagetool.metadata(from: $0), name: $0.lastPathComponent) }
        let store = Store(initialState: state, reduce: PhotoTrailReducer(), undoEnabled: true)
        let tags: Set<MetadataTag> = [.titleDefault, .subject, .captureDate]
        let reading = (image: state.imageData[0], snapshot: try MetadataInspectionSnapshot.read(tags, from: urls[0]))
        store.send(.selectionChanged([state.imageData[1].id]), undoable: false)
        store.beginUndoGroup(description: "quick typing")
        for text in ["A", "A title"] {
            try MetadataQuickEdit.apply(.setText(text), tag: .titleDefault, readings: [reading], store: store)
        }
        store.endUndoGroup()
        #expect(store.imageData[0].creatorDraft?.changes[.titleDefault] == .set(.text("A title")))
        #expect(store.imageData[1].creatorDraft == nil)
        #expect(SaveTargets(images: store.imageData).creator.count == 1)
        store.undo()
        #expect(store.imageData[0].creatorDraft == nil)
        try MetadataQuickEdit.apply(.appendKeywords(["旅行"]), tag: .subject, readings: [reading], store: store)
        let text = "2026-10-04 08:32:15.123456+08:00"
        try MetadataQuickEdit.apply(MetadataQuickEdit.action(text, tag: .captureDate), tag: .captureDate,
                                   readings: [reading], store: store)
        #expect(store.imageData[0].creatorDraft?.changes[.captureDate] == .set(.text("2026:10:04 08:32:15.123456+08:00")))
        #expect(store.imageData[0].creatorDraft?.changes[.subject] != nil)
        #expect(SaveTargets(images: store.imageData).conflicts.isEmpty)
        #expect(try urls.map { try Data(contentsOf: $0) } == bytes)
        #expect(throws: Error.self) {
            try MetadataQuickEdit.apply(.setText("invalid"), tag: .captureDate, readings: [reading], store: store)
        }
        let file = try FileHandle(forWritingTo: urls[0]); try file.seekToEnd(); try file.write(contentsOf: Data([0])); try file.close()
        #expect(throws: Error.self) {
            try MetadataQuickEdit.apply(.setText("stale"), tag: .titleDefault, readings: [reading], store: store)
        }
    }

    @Test func focusingMixedBlankFieldDoesNotClearValuesAndInvalidInputBlocksEndEditing() {
        var applied = [String]()
        var focusChanges = [Bool]()
        var cancelled: Bool?
        let field = MetadataQuickTextField(value: "", placeholder: "mixed", identifier: "test", editable: true,
            apply: { applied.append($0); return $0 != "invalid" }, editing: { focusChanges.append($0) },
            cancel: { cancelled = $0 })
        let coordinator = MetadataQuickTextField.Coordinator(field)
        let control = NSTextField(string: "")
        let editor = NSTextView()
        coordinator.begin(control)
        #expect(focusChanges == [true]) // Clipboard commands must work before the first keystroke.
        coordinator.controlTextDidBeginEditing(Notification(name: NSControl.textDidBeginEditingNotification, object: control))
        #expect(focusChanges == [true])
        #expect(coordinator.control(control, textShouldEndEditing: editor))
        #expect(applied.isEmpty)
        control.stringValue = "invalid"; editor.string = "invalid"
        coordinator.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: control))
        #expect(!coordinator.control(control, textShouldEndEditing: editor))
        #expect(coordinator.control(control, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        #expect(cancelled == false) // Dismiss the error without undoing another field's valid draft.
        #expect(editor.string.isEmpty)
        coordinator.end()
        #expect(focusChanges == [true, false])
    }
}
