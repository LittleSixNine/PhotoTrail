import SwiftUI

// Install narrow handles inside the real header, so AppKit never starts its own
// single-column tracking loop at these dividers. Header labels still sort normally.
struct IndependentTableColumns: NSViewRepresentable {
    func makeNSView(context: Context) -> ColumnObserverView { ColumnObserverView() }
    func updateNSView(_ view: ColumnObserverView, context: Context) {
        DispatchQueue.main.async { view.installHandles() }
    }

    final class ColumnObserverView: NSView {
        private weak var table: NSTableView?
        private var handles: [DividerHandle] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            if window == nil {
                handles.forEach { $0.removeFromSuperview() }
                handles = []
                table = nil
                return
            }
            DispatchQueue.main.async { [weak self] in self?.installHandles() }
        }

        override func layout() {
            super.layout()
            installHandles()
        }

        private func findTable(_ view: NSView) -> NSTableView? {
            if let table = view as? NSTableView, table.tableColumns.count == 6 { return table }
            return view.subviews.lazy.compactMap { self.findTable($0) }.first
        }

        func installHandles() {
            guard let root = window?.contentView, let found = findTable(root),
                  let header = found.headerView else { return }
            if table !== found || handles.first?.superview !== header {
                handles.forEach { $0.removeFromSuperview() }
                table = found
                NotificationCenter.default.removeObserver(self)
                for view in [found, header] {
                    view.postsFrameChangedNotifications = true
                    NotificationCenter.default.addObserver(self, selector: #selector(refreshHandles),
                        name: NSView.frameDidChangeNotification, object: view)
                }
                handles = (0..<(found.numberOfColumns - 1)).map { index in
                    let handle = DividerHandle(frame: .zero)
                    handle.owner = self
                    handle.boundary = index
                    handle.setAccessibilityElement(true)
                    handle.setAccessibilityRole(.splitter)
                    handle.setAccessibilityLabel("调整\(found.tableColumns[index].title)列宽")
                    header.addSubview(handle)
                    return handle
                }
            }
            refreshHandles()
        }

        @objc private func refreshHandles() {
            guard let header = table?.headerView else { return }
            for handle in handles {
                let rect = header.headerRect(ofColumn: handle.boundary)
                let frame = NSRect(x: rect.maxX - 5, y: rect.minY, width: 10, height: rect.height)
                if handle.frame != frame { handle.frame = frame }
            }
        }

        final class DividerHandle: NSView {
            weak var owner: ColumnObserverView?
            var boundary = 0
            private var startX: CGFloat = 0
            private var widths: [CGFloat] = []
            override var acceptsFirstResponder: Bool { true }
            override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
            override func mouseDown(with event: NSEvent) {
                window?.makeFirstResponder(self)
                startX = event.locationInWindow.x
                widths = owner?.table?.tableColumns.map(\.width) ?? []
            }
            override func mouseDragged(with event: NSEvent) {
                guard let table = owner?.table else { return }
                ColumnObserverView.resize(in: table, boundary: boundary, widths: widths,
                                          delta: event.locationInWindow.x - startX)
                owner?.refreshHandles()
            }
            override func mouseUp(with event: NSEvent) { widths = [] }
            override func keyDown(with event: NSEvent) {
                guard let table = owner?.table, [123, 124].contains(event.keyCode) else {
                    super.keyDown(with: event); return
                }
                ColumnObserverView.resize(in: table, boundary: boundary,
                    widths: table.tableColumns.map(\.width), delta: event.keyCode == 123 ? -10 : 10)
                owner?.refreshHandles()
            }
        }

        static func resize(in table: NSTableView, boundary: Int, widths: [CGFloat], delta: CGFloat) {
            let columns = table.tableColumns
            guard boundary >= 0, boundary + 1 < columns.count, widths.count == columns.count else { return }
            let left = columns[boundary], right = columns[boundary + 1]
            let lower = max(left.minWidth - widths[boundary], widths[boundary + 1] - right.maxWidth)
            let upper = min(left.maxWidth - widths[boundary], widths[boundary + 1] - right.minWidth)
            let movement = min(upper, max(lower, delta))
            left.width = widths[boundary] + movement
            right.width = widths[boundary + 1] - movement
        }
    }
}
