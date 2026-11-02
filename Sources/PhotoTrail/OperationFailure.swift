import AppKit

// Explicit actions use a native modal so errors remain visible even inside a settings window or sheet.
enum OperationFailure {
    static func isCancellation(_ error: Error) -> Bool {
        let value = error as NSError
        return error is CancellationError || value.domain == NSCocoaErrorDomain
            && value.code == CocoaError.userCancelled.rawValue
            || value.domain == NSURLErrorDomain && value.code == NSURLErrorCancelled
    }

    static func message(_ context: String, error: Error) -> String {
        let value = error as NSError
        // Swift's private error bridge can expose unstable memory addresses instead of a readable reason.
        let reason = value.domain.contains("(unknown context at ") ? String(describing: error) : error.localizedDescription
        return context + "\n\n" + reason
    }

    @MainActor static func present(_ message: String) {
        guard ProcessInfo.processInfo.environment["PHOTOTRAIL_OFFLINE_TESTS"] != "1" else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.text("操作未完成")
        if message.count <= 1_200 { alert.informativeText = message }
        else {
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))
            let text = NSTextView(frame: scroll.bounds)
            text.string = message
            text.isEditable = false
            text.font = .systemFont(ofSize: NSFont.systemFontSize)
            text.textContainer?.widthTracksTextView = true
            text.autoresizingMask = [.width]
            scroll.documentView = text
            scroll.hasVerticalScroller = true
            alert.accessoryView = scroll
        }
        alert.addButton(withTitle: L10n.text("完成"))
        alert.runModal()
    }

    @MainActor static func present(_ context: String, error: Error) {
        guard !isCancellation(error) else { return }
        present(message(context, error: error))
    }
}
