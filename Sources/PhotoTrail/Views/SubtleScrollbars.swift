import AppKit
import QuartzCore
import SwiftUI

/// Attach only to an app-owned scroll container, never to a whole window or WebKit.
struct SubtleScrollbars: NSViewRepresentable {
    func makeNSView(context: Context) -> Installer { Installer() }
    func updateNSView(_ view: Installer, context: Context) {
        DispatchQueue.main.async { [weak view] in view?.install() }
    }

    final class Installer: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in self?.install() }
        }

        override func layout() {
            super.layout()
            install()
        }

        func install() {
            guard window != nil else { return }
            var ancestor = superview
            while let view = ancestor {
                let scrolls = scrollViews(in: view)
                if !scrolls.isEmpty {
                    scrolls.forEach(Self.configure)
                    return
                }
                ancestor = view.superview
            }
        }

        private func scrollViews(in view: NSView) -> [NSScrollView] {
            if let scroll = view as? NSScrollView { return [scroll] }
            return view.subviews.flatMap { scrollViews(in: $0) }
        }

        static func configure(_ scroll: NSScrollView) {
            // Overlay scrollers own an OS-controlled fade timer. Use native legacy
            // tracking with a clear track so the app can consistently wait three seconds.
            scroll.scrollerStyle = .legacy
            if let old = scroll.verticalScroller, !(old is SubtleScroller) {
                scroll.verticalScroller = replacement(for: old)
            }
            if let old = scroll.horizontalScroller, !(old is SubtleScroller) {
                scroll.horizontalScroller = replacement(for: old)
            }
        }

        private static func replacement(for old: NSScroller) -> SubtleScroller {
            let scroller = SubtleScroller(frame: old.frame)
            scroller.controlSize = .small
            scroller.target = old.target
            scroller.action = old.action
            scroller.doubleValue = old.doubleValue
            scroller.knobProportion = old.knobProportion
            return scroller
        }
    }
}

final class SubtleScroller: NSScroller {
    private var fadeWork: DispatchWorkItem?
    private var hoverArea: NSTrackingArea?
    private var hovering = false
    private var dragging = false

    override static var isCompatibleWithOverlayScrollers: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: nil)
        fadeWork?.cancel()
        hovering = false
        dragging = false
        guard window != nil, let scroll = superview as? NSScrollView else { return }
        wantsLayer = true
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(showForActivity),
            name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        showForActivity()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        showForActivity()
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        showForActivity()
    }

    override func mouseDown(with event: NSEvent) {
        dragging = true
        showForActivity()
        super.mouseDown(with: event)
        dragging = false
        hovering = bounds.contains(convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil))
        showForActivity()
    }

    @objc func showForActivity() {
        fadeWork?.cancel()
        layer?.removeAnimation(forKey: "idleFade")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.opacity = 1
        CATransaction.commit()
        needsDisplay = true
        guard !hovering, !dragging else { return }
        let work = DispatchWorkItem { [weak self] in self?.fade() }
        fadeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    private func fade() {
        guard !hovering, !dragging, let layer else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = layer.presentation()?.opacity ?? layer.opacity
        animation.toValue = 0
        animation.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.3
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 0
        CATransaction.commit()
        layer.add(animation, forKey: "idleFade")
        // Keep the native view and hit area alive even when its drawing is invisible.
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isEnabled, knobProportion < 1 else { return }
        var knob = rect(for: .knob)
        let thickness: CGFloat = 5
        if bounds.height > bounds.width {
            knob.origin.x = bounds.midX - thickness / 2
            knob.size.width = thickness
        } else {
            knob.origin.y = bounds.midY - thickness / 2
            knob.size.height = thickness
        }
        let highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let color = highContrast ? NSColor.labelColor : NSColor.secondaryLabelColor
        color.withAlphaComponent(highContrast ? 1 : (hovering || dragging ? 0.65 : 0.45)).setFill()
        NSBezierPath(roundedRect: knob, xRadius: thickness / 2, yRadius: thickness / 2).fill()
    }
}
