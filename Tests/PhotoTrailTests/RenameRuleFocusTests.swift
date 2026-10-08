import AppKit
import SwiftUI
import Testing
import UDF
@testable import PhotoTrail

@MainActor
struct RenameRuleFocusTests {
    @Observable final class Selection {
        var rules = [RenameRule(action: 1), RenameRule(action: 68)]
        var selected: UUID?
    }

    private struct Cards: View {
        @Bindable var selection: Selection
        let workspace: RenameWorkspace

        var body: some View {
            VStack {
                ForEach($selection.rules) { $rule in
                    RenameRuleCard(rule: $rule, selectedRule: $selection.selected,
                                   index: 0, restingFrame: .zero,
                                   reorder: { _, _ in }, remove: {}, duplicate: {})
                }
            }.environment(workspace)
        }
    }

    @Test func switchingRulesAndClearingSelectionEndsTextEditing() async throws {
        let domain = "PhotoTrail.RenameFocusTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let selection = Selection()
        let host = NSHostingView(rootView: Cards(selection: selection, workspace: RenameWorkspace(defaults: defaults)))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        let editor = try #require(descendants(host).compactMap { $0 as? NSTextView }.first { $0.isEditable })
        #expect(window.makeFirstResponder(editor))
        try await Task.sleep(for: .milliseconds(100))
        #expect(selection.selected == selection.rules[1].id)
        selection.selected = selection.rules[0].id
        try await Task.sleep(for: .milliseconds(100))
        #expect(window.firstResponder !== editor)
        #expect(selection.selected == selection.rules[0].id)

        let field = try #require(descendants(host).compactMap { $0 as? NSTextField }.first { $0.isEditable })
        #expect(window.makeFirstResponder(field))
        try await Task.sleep(for: .milliseconds(100))
        let fieldEditor = window.firstResponder
        #expect(fieldEditor is NSTextView)
        selection.selected = selection.rules[1].id
        try await Task.sleep(for: .milliseconds(100))
        #expect(window.firstResponder !== fieldEditor)
        #expect(selection.selected == selection.rules[1].id)

        #expect(window.makeFirstResponder(editor))
        try await Task.sleep(for: .milliseconds(100))
        selection.selected = nil
        try await Task.sleep(for: .milliseconds(100))
        #expect(window.firstResponder !== editor)
        #expect(selection.selected == nil)
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func themeRendersReadableTemplateBackground(scheme: ColorScheme) async throws {
        let domain = "PhotoTrail.RenameThemeTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let workspace = RenameWorkspace(defaults: defaults)
        workspace.activateCommonPreset(name: L10n.text("照片通用"),
                                       rules: [RenameRule(action: 40), RenameRule(action: 68, text: ".<CameraModel>")])
        let store = Store(initialState: PhotoTrailState(), reduce: PhotoTrailReducer())
        let host = NSHostingView(rootView: RenameWorkspaceView(workspace: workspace)
            .environment(store).defaultAppStorage(defaults).preferredColorScheme(scheme))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 1000),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        for _ in 0..<100 where workspace.busy { try await Task.sleep(for: .milliseconds(25)) }
        #expect(!workspace.busy)
        host.layoutSubtreeIfNeeded()
        let editor = try #require(descendants(host).compactMap { $0 as? NSTextView }.first { $0.isEditable })
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let point = host.convert(NSPoint(x: 15, y: 40), from: editor)
        let scale = Double(bitmap.pixelsWide) / host.bounds.width
        let pixelY = host.isFlipped ? point.y : host.bounds.height - point.y
        let color = try #require(bitmap.colorAt(x: Int(point.x * scale), y: Int(pixelY * scale))?
            .usingColorSpace(.deviceRGB))
        let brightness = (color.redComponent + color.greenComponent + color.blueComponent) / 3
        #expect(scheme == .dark ? brightness < 0.3 : brightness > 0.8)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        Attachment.record(data, named: scheme == .dark ? "rename-dark.png" : "rename-light.png")
    }
}
