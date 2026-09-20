import AppKit
import SwiftUI
import Testing
import UDF
@testable import PhotoTrail

@MainActor
struct SubtleScrollbarTests {
    @Test func installsOnSwiftUIScrollViewsAndTable() async throws {
        let store = Store(initialState: PhotoTrailState(), reduce: PhotoTrailReducer())
        let content = VStack {
            ScrollView {
                Color.clear.frame(height: 1200)
            }.background(SubtleScrollbars()).frame(height: 120)
            ScrollView(.horizontal) {
                Color.clear.frame(width: 2000, height: 60)
            }.background(SubtleScrollbars()).frame(height: 100)
            ImageTableView(inspectorPresented: .constant(false), batchActionsPresented: .constant(false))
                .environment(store).environment(LocationWorkspace())
        }
        let host = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        let scrolls = findScrolls(host)
        #expect(scrolls.count >= 3)
        #expect(scrolls.contains { $0.documentView is NSTableView })
        for scroll in scrolls {
            if let vertical = scroll.verticalScroller { #expect(vertical is SubtleScroller) }
            if let horizontal = scroll.horizontalScroller { #expect(horizontal is SubtleScroller) }
        }
        let vertical = try #require(scrolls.first { ($0.documentView?.frame.height ?? 0) > 1000 })
        vertical.contentView.scroll(to: NSPoint(x: 0, y: 300))
        vertical.reflectScrolledClipView(vertical.contentView)
        #expect(vertical.contentView.bounds.origin.y == 300)
        let scroller = try #require(vertical.verticalScroller as? SubtleScroller)
        #expect(scroller.knobProportion > 0 && scroller.knobProportion < 1)
        #expect(scroller.target != nil)
        #expect(scroller.action != nil)
    }

    @Test func threeSecondFadeResetsOnScrollAndHover() async throws {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 240, height: 200))
        scroll.hasVerticalScroller = true
        scroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 1400))
        let window = NSWindow(contentRect: scroll.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = scroll
        defer { window.contentView = nil }
        SubtleScrollbars.Installer.configure(scroll)
        scroll.tile()
        let scroller = try #require(scroll.verticalScroller as? SubtleScroller)
        #expect(scroller.controlSize == .small)
        try await Task.sleep(for: .seconds(2))
        #expect(scroller.layer?.opacity == 1)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 200))
        scroll.reflectScrolledClipView(scroll.contentView)
        try await Task.sleep(for: .seconds(2))
        #expect(scroller.layer?.opacity == 1)
        try await Task.sleep(for: .milliseconds(1400))
        #expect(scroller.layer?.opacity == 0)
        #expect(scroller.alphaValue == 1)
        #expect(!scroller.isHidden)
        #expect(scroll.contentView.bounds.origin.y == 200)
        let event = try #require(NSEvent.mouseEvent(with: .mouseMoved, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 0, pressure: 0))
        scroller.mouseEntered(with: event)
        #expect(scroller.layer?.opacity == 1)
        try await Task.sleep(for: .milliseconds(3400))
        #expect(scroller.layer?.opacity == 1)
        scroller.mouseExited(with: event)
        try await Task.sleep(for: .milliseconds(3400))
        #expect(scroller.layer?.opacity == 0)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 400))
        scroll.reflectScrolledClipView(scroll.contentView)
        #expect(scroller.layer?.opacity == 1)
    }

    private func findScrolls(_ view: NSView) -> [NSScrollView] {
        if let scroll = view as? NSScrollView { return [scroll] }
        return view.subviews.flatMap { findScrolls($0) }
    }
}
