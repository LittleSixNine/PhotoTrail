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
            .environment(store).environment(LocationWorkspace()).environment(MetadataLoadingQueue())
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        defer { window.close() }
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        let table = try #require(findTable(host))
        // SwiftUI uses NSOutlineView, which posts a different resize notification.
        #expect(table is NSOutlineView)
        let columns = table.tableColumns
        #expect(columns.count == 5)
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
        let pairWidth = columns[2].width + columns[3].width
        IndependentTableColumns.ColumnObserverView.resize(in: table, boundary: 2, widths: before, delta: 500)
        #expect(columns[3].width >= columns[3].minWidth)
        #expect(abs(columns[2].width + columns[3].width - pairWidth) < 0.01)
    }

    @Test func renamePreviewKeepsFiveColumnsAndFixedStatus() async throws {
        let domain = "PhotoTrail.RenameColumnTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let workspace = RenameWorkspace(defaults: defaults)
        let store = Store(initialState: PhotoTrailState(), reduce: PhotoTrailReducer())
        let host = NSHostingView(rootView: RenameWorkspaceView(workspace: workspace).environment(store).defaultAppStorage(defaults))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        defer { window.close() }
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        let table = try #require(findTable(host))
        #expect(table.tableColumns.count == 5)
        #expect(table.tableColumns[2].title == L10n.text("步骤结果"))
        let status = try #require(table.tableColumns.last)
        #expect(status.title == L10n.text("状态"))
        #expect(status.minWidth == 120 && status.maxWidth == 120 && status.width == 120)
        let column = table.tableColumns[2]
        let width = column.width + 20
        let finalWidth = table.tableColumns[3].width
        IndependentTableColumns.ColumnObserverView.resize(in: table, boundary: 2,
            widths: table.tableColumns.map(\.width), delta: 20)
        #expect(abs(column.width - width) < 0.01)
        #expect(abs(table.tableColumns[3].width - finalWidth + 20) < 0.01)
        try await Task.sleep(for: .milliseconds(100))
        #expect(defaults.data(forKey: "PhotoTrailRenameTableColumns.v1") != nil)
        let reopened = NSHostingView(rootView: RenameWorkspaceView(workspace: workspace).environment(store).defaultAppStorage(defaults))
        reopened.frame = host.frame
        window.contentView = reopened
        reopened.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        reopened.layoutSubtreeIfNeeded()
        let restored = try #require(findTable(reopened))
        #expect(abs(restored.tableColumns[2].width - width) < 0.01)
        #expect(abs(restored.tableColumns[3].width - finalWidth + 20) < 0.01)
        #expect(restored.tableColumns.last?.width == 120)
        window.setContentSize(NSSize(width: 1100, height: 700))
        reopened.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let scrollView = try #require(restored.enclosingScrollView)
        #expect(restored.rect(ofColumn: 4).maxX <= scrollView.contentSize.width + 1)
        #expect(restored.tableColumns.last?.width == 120)

    }

    @Test func tableSearchVisitsEachViewOnceAndStopsAtFirstMatch() {
        final class CountedView: NSView {
            var visits = 0
            override var subviews: [NSView] {
                get { visits += 1; return super.subviews }
                set { super.subviews = newValue }
            }
        }
        let table = NSTableView()
        for index in 0..<5 { table.addTableColumn(NSTableColumn(identifier: .init("column\(index)"))) }
        var child: NSView = table
        var nodes: [CountedView] = []
        for _ in 0..<20 {
            let parent = CountedView(); parent.addSubview(child); child = parent; nodes.append(parent)
        }
        let ignored = CountedView(); child.addSubview(ignored)
        for node in nodes { node.visits = 0 }
        ignored.visits = 0
        let observer = IndependentTableColumns.ColumnObserverView()
        #expect(observer.findTable(child) === table)
        #expect(nodes.allSatisfy { $0.visits == 1 })
        #expect(ignored.visits == 0)
    }

    private func findTable(_ view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        for child in view.subviews { if let table = findTable(child) { return table } }
        return nil
    }
}
