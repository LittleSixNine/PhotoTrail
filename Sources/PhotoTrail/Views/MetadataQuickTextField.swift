import AppKit
import SwiftUI

/// Native editing keeps IME composition local; complete values become undoable drafts.
struct MetadataQuickTextField: NSViewRepresentable {
    let value: String
    let placeholder: String
    let identifier: String
    let editable: Bool
    let apply: (String) -> Bool
    let editing: (Bool) -> Void
    let cancel: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
        let field = FocusAwareTextField(string: value)
        field.delegate = context.coordinator
        field.didFocus = { [weak coordinator = context.coordinator, weak field] in
            if let field { coordinator?.begin(field) }
        }
        field.font = .systemFont(ofSize: 13)
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .exterior
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.identifier = NSUserInterfaceItemIdentifier(identifier)
        field.setAccessibilityIdentifier(identifier)
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.placeholderString = placeholder
        field.isEditable = editable
        field.isEnabled = editable
        if field.currentEditor() == nil { field.stringValue = value }
    }

    static func dismantleNSView(_ field: NSTextField, coordinator: Coordinator) {
        coordinator.end()
    }

    private final class FocusAwareTextField: NSTextField {
        var didFocus: (() -> Void)?
        override func becomeFirstResponder() -> Bool {
            let focused = super.becomeFirstResponder()
            if focused { didFocus?() }
            return focused
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: MetadataQuickTextField
        private var sessionApply: ((String) -> Bool)?
        private var sessionEditing: ((Bool) -> Void)?
        private var sessionCancel: ((Bool) -> Void)?
        private var original = ""
        private var dirty = false
        private var applied = false
        init(_ parent: MetadataQuickTextField) { self.parent = parent }

        func controlTextDidBeginEditing(_ notification: Notification) {
            if let field = notification.object as? NSTextField { begin(field) }
        }
        func begin(_ field: NSTextField) {
            guard sessionApply == nil else { return }
            original = field.stringValue
            // Freeze target IDs and read versions for this edit, even if selection changes.
            sessionApply = parent.apply
            sessionEditing = parent.editing
            sessionCancel = parent.cancel
            dirty = false; applied = false
            sessionEditing?(true)
        }
        func controlTextDidChange(_ notification: Notification) {
            dirty = true
            guard let field = notification.object as? NSTextField,
                  (field.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
            if sessionApply?(field.stringValue) == true { applied = true }
        }
        func control(_ control: NSControl, textShouldEndEditing fieldEditor: NSText) -> Bool {
            !dirty || (sessionApply?(fieldEditor.string) ?? true)
        }
        func controlTextDidEndEditing(_ notification: Notification) { end() }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)), let field = control as? NSTextField {
                field.stringValue = original
                textView.string = original
                let revert = sessionCancel
                dirty = false
                end()
                revert?(applied)
                field.window?.makeFirstResponder(nil)
                return true
            }
            return false
        }
        func end() {
            sessionEditing?(false)
            sessionApply = nil
            sessionEditing = nil
            sessionCancel = nil
        }
    }
}
