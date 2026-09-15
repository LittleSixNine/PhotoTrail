import SwiftUI

// Own the divider gesture: AppKit's normal resize shifts every following column.
struct IndependentTableColumns: NSViewRepresentable {
    func makeNSView(context: Context) -> ColumnObserverView { ColumnObserverView() }
    func updateNSView(_ view: ColumnObserverView, context: Context) {}

    final class ColumnObserverView: NSView {
        private var monitor: Any?
        private weak var table: NSTableView?
        private var boundary: Int?
        private var startX: CGFloat = 0
        private var startWidths: [CGFloat] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) {
                [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
        }

        private func findTable(_ view: NSView) -> NSTableView? {
            if let table = view as? NSTableView, table.tableColumns.count == 6 { return table }
            return view.subviews.lazy.compactMap { self.findTable($0) }.first
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let window, event.window === window else { return event }
            if event.type == .leftMouseDown {
                guard let root = window.contentView, let table = findTable(root),
                      let header = table.headerView else { return event }
                let point = header.convert(event.locationInWindow, from: nil)
                guard header.bounds.contains(point),
                      let index = (0..<(table.numberOfColumns - 1)).first(where: {
                          abs(header.headerRect(ofColumn: $0).maxX - point.x) <= 5
                      }) else { return event }
                self.table = table
                boundary = index
                startX = event.locationInWindow.x
                startWidths = table.tableColumns.map(\.width)
                return nil
            }
            guard let boundary, let table else { return event }
            if event.type == .leftMouseDragged {
                Self.resize(in: table, boundary: boundary, widths: startWidths,
                            delta: event.locationInWindow.x - startX)
                return nil
            }
            if event.type == .leftMouseUp {
                self.boundary = nil
                startWidths = []
                return nil
            }
            return event
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
