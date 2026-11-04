import AppKit
import SwiftUI
import Testing
import UDF
@testable import PhotoTrail

@MainActor
struct SubtleScrollbarTests {
    @Test func ownedSidebarConfiguresBeforeFirstLayoutAndPropagatesEnvironment() async throws {
        func content(_ height: CGFloat) -> some View {
            SidebarScrollView { EnvironmentHeightContent() }
                .environment(\.defaultMinListRowHeight, height)
                .frame(width: 300, height: 320)
        }
        let host = NSHostingView(rootView: content(319))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 320),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        let scroll = try #require(findScrolls(host).first)
        let width = scroll.contentView.bounds.width
        #expect(width == 287)
        #expect(scroll.scrollerStyle == .legacy)
        #expect(scroll.verticalScroller is SubtleScroller)
        #expect(scroll.hasVerticalScroller && !scroll.autohidesScrollers)
        #expect(!scroll.hasHorizontalScroller)
        for height in [319.0, 321.0, 320.0, 1_000.0, 1_100.0] as [CGFloat] {
            host.rootView = content(height)
            host.layoutSubtreeIfNeeded()
            #expect(scroll.contentView.bounds.width == width)
            #expect(scroll.documentView?.frame.width == width)
            try await Task.sleep(for: .milliseconds(20))
            host.layoutSubtreeIfNeeded()
            #expect(scroll.documentView?.frame.height == height)
            if height == 1_000 {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: 300))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            if height == 1_100 { #expect(scroll.contentView.bounds.origin.y == 300) }
            #expect(scroll.contentView.bounds.width == width)
        }
    }

    @Test func ownedSidebarFitsWidthDependentContentsWithoutHorizontalOverflow() async throws {
        func content(_ width: CGFloat) -> some View {
            SidebarScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Color.clear.aspectRatio(1.5, contentMode: .fit)
                    Text(String(repeating: "A long track name with a recorded time. ", count: 12))
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity)
            }.frame(width: width, height: 320)
        }
        let host = NSHostingView(rootView: content(260))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 320),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        var measuredHeights = Set<CGFloat>()
        for width in [260.0, 300.0, 380.0, 300.0] as [CGFloat] {
            host.rootView = content(width)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
            host.layoutSubtreeIfNeeded()
            let scroll = try #require(findScrolls(host).first)
            #expect(scroll.bounds.width == width)
            #expect(scroll.contentView.bounds.width == width - 13)
            #expect(scroll.documentView?.frame.width == width - 13)
            #expect((scroll.documentView?.frame.height ?? 0) > (width - 13) / 1.5)
            #expect((scroll.documentView?.frame.height ?? 0) < 2_000)
            measuredHeights.insert(scroll.documentView?.frame.height ?? 0)
            #expect(!scroll.hasHorizontalScroller)
        }
        #expect(measuredHeights.count > 1)
    }

    @Test func recreatedPhotoDetailPageRetainsSavedSidebarRatio() async throws {
        let name = "PhotoTrail.SidebarTest.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(0.31, forKey: "PhotoTrailDetailWidthRatio")
        defaults.set("amap", forKey: "PhotoTrailMapProvider")
        let store = Store(initialState: PhotoTrailState(), reduce: PhotoTrailReducer())
        let workspace = LocationWorkspace()
        let queue = MetadataLoadingQueue()
        let host = NSHostingView(rootView: AnyView(Color.clear))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        for _ in 0..<3 {
            host.rootView = AnyView(PhotoDetailPage().environment(store).environment(workspace)
                .environment(queue).defaultAppStorage(defaults))
            host.layoutSubtreeIfNeeded()
            let sidebar = try #require(findScrolls(host).first { $0.hasVerticalScroller && !$0.hasHorizontalScroller })
            #expect(sidebar.bounds.width == 372)
            #expect(sidebar.contentView.bounds.width == 359)
            #expect(sidebar.documentView?.frame.width == 359)
            #expect(sidebar.verticalScroller is SubtleScroller)
            try await Task.sleep(for: .milliseconds(30))
            host.layoutSubtreeIfNeeded()
            #expect(sidebar.contentView.bounds.width == 359)
            host.rootView = AnyView(Color.clear)
            host.layoutSubtreeIfNeeded()
        }
        #expect(defaults.double(forKey: "PhotoTrailDetailWidthRatio") == 0.31)
    }

    @Test func repeatedInstallationDoesNotResetTheScrollerStyle() {
        let scroll = StyleCountingScrollView()
        scroll.scrollerStyle = .overlay
        SubtleScrollbars.Installer.configure(scroll, reservesVerticalScroller: true)
        let updates = scroll.styleUpdates
        for _ in 0..<10 { SubtleScrollbars.Installer.configure(scroll, reservesVerticalScroller: true) }
        #expect(scroll.styleUpdates == updates)
        #expect(scroll.scrollerStyle == .legacy)
        #expect(scroll.hasVerticalScroller && !scroll.autohidesScrollers)
    }

    @Test func reservedSwiftUISidebarKeepsItsGutterWhenContentFitsOrOverflows() async throws {
        func content(_ height: CGFloat) -> some View {
            ScrollView { Color.clear.frame(height: height) }
                .scrollIndicators(.visible, axes: .vertical)
                .background(SubtleScrollbars(reservesVerticalScroller: true))
                .frame(width: 300, height: 320)
        }
        let host = NSHostingView(rootView: content(319))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 320),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let scroll = try #require(findScrolls(host).first)
        let width = scroll.contentView.bounds.width
        #expect(width < 300)
        for height in [319.0, 321.0, 319.0, 321.0, 320.0, 319.0] {
            host.rootView = content(height)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
            #expect(scroll.contentView.bounds.width == width)
            #expect(scroll.hasVerticalScroller && !scroll.autohidesScrollers)
            #expect(scroll.verticalScroller?.isHidden == false)
        }
    }

    @Test func installsOnSwiftUIScrollViewsAndTable() async throws {
        let store = Store(initialState: PhotoTrailState(), reduce: PhotoTrailReducer())
        let content = VStack {
            ScrollView {
                Color.clear.frame(height: 1200)
            }.background(SubtleScrollbars()).frame(height: 120)
            ScrollView(.horizontal) {
                Color.clear.frame(width: 2000, height: 60)
            }.background(SubtleScrollbars()).frame(height: 100)
            ImageTableView(inspectorPresented: .constant(false))
                .environment(store).environment(LocationWorkspace()).environment(MetadataLoadingQueue())
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

private struct EnvironmentHeightContent: View {
    @Environment(\.defaultMinListRowHeight) private var height
    var body: some View { Color.clear.frame(height: height) }
}

@MainActor
private final class StyleCountingScrollView: NSScrollView {
    var styleUpdates = 0
    override var scrollerStyle: NSScroller.Style {
        didSet { styleUpdates += 1 }
    }
}
