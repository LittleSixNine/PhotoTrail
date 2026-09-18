import AppKit
import SwiftUI
import Testing
import UDF
@testable import PhotoTrail

@MainActor
struct TableColumnResizeTests {
    @Test func adjacentResizeKeepsLaterBoundariesFixed() async throws {
        let store = Store(initialState: PhotoTrailState(), reduce: PhotoTrailReducer())
        let root = ImageTableView(inspectorPresented: .constant(false), batchActionsPresented: .constant(false))
            .environment(store).environment(LocationWorkspace())
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        let table = try #require(findTable(host))
        // SwiftUI uses NSOutlineView, which posts a different resize notification.
        #expect(table is NSOutlineView)
        let columns = table.tableColumns
        #expect(columns.count == 6)
        let before = columns.map(\.width)
        let header = try #require(table.headerView)
        let handle = try #require(header.subviews.compactMap {
            $0 as? IndependentTableColumns.ColumnObserverView.DividerHandle
        }.first { $0.boundary == 2 })
        let localPoint = NSPoint(x: handle.frame.midX, y: handle.frame.midY)
        #expect(header.hitTest(header.convert(localPoint, to: header.superview)) === handle)
        let point = header.convert(localPoint, to: nil)
        let down = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: point,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        let drag = try #require(NSEvent.mouseEvent(with: .leftMouseDragged,
            location: NSPoint(x: point.x + 20, y: point.y), modifierFlags: [], timestamp: 0.1,
            windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 1))
        handle.mouseDown(with: down)
        handle.mouseDragged(with: drag)
        #expect(abs(columns[2].width - before[2] - 20) < 0.01)
        #expect(abs(columns[3].width - before[3] + 20) < 0.01)
        handle.mouseUp(with: drag)
        IndependentTableColumns.ColumnObserverView.resize(in: table, boundary: 2, widths: before, delta: 20)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        #expect(abs(columns[2].width + columns[3].width - before[2] - before[3]) < 0.01)
        #expect(columns[3].width < before[3])
        #expect(columns[4].width == before[4])
        #expect(columns[5].width == before[5])
        let pairWidth = columns[2].width + columns[3].width
        IndependentTableColumns.ColumnObserverView.resize(in: table, boundary: 2, widths: before, delta: 500)
        #expect(columns[3].width >= columns[3].minWidth)
        #expect(abs(columns[2].width + columns[3].width - pairWidth) < 0.01)
    }

    private func findTable(_ view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        return view.subviews.lazy.compactMap { findTable($0) }.first
    }
}
