import AppKit
import SwiftUI
import Testing
@testable import GeoTag

@MainActor
struct AppAppearanceTests {
    @Test func lightAndDarkChoicesSurviveViewRecreation() async throws {
        let suite = "PhotoTrailAppearanceTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let light = try await host(scheme: .light, defaults: defaults)
        let dark = try await host(scheme: .dark, defaults: defaults)
        #expect(light.selection.wrappedValue == .light)
        #expect(dark.selection.wrappedValue == .dark)
        light.selection.wrappedValue = .normal
        dark.selection.wrappedValue = .darkblue
        #expect(defaults.string(forKey: AMapStyleName.lightPreferenceKey) == "normal")
        #expect(defaults.string(forKey: AMapStyleName.darkPreferenceKey) == "darkblue")
        let reopenedLight = try await host(scheme: .light, defaults: defaults)
        let reopenedDark = try await host(scheme: .dark, defaults: defaults)
        #expect(reopenedLight.selection.wrappedValue == .normal)
        #expect(reopenedDark.selection.wrappedValue == .darkblue)
        // A system appearance change updates the same live preference reader.
        var changedSelection: Binding<AMapStyleName>?
        light.view.rootView = AnyView(Probe { changedSelection = $0 }
            .environment(\.colorScheme, .dark).defaultAppStorage(defaults))
        light.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        #expect(try #require(changedSelection).wrappedValue == .darkblue)
    }

    @Test func legacyChoiceMigratesOnlyToLightAndNeverOverwritesANewChoice() throws {
        let suite = "PhotoTrailAppearanceMigration-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("wine", forKey: AMapStyleName.preferenceKey)
        AMapStyleName.migrateLegacyPreference(in: defaults)
        #expect(defaults.string(forKey: AMapStyleName.lightPreferenceKey) == "wine")
        #expect(defaults.object(forKey: AMapStyleName.darkPreferenceKey) == nil)
        defaults.set("normal", forKey: AMapStyleName.lightPreferenceKey)
        AMapStyleName.migrateLegacyPreference(in: defaults)
        #expect(defaults.string(forKey: AMapStyleName.lightPreferenceKey) == "normal")
        #expect(AppAppearance.system.colorScheme == nil)
        #expect(AppAppearance.light.colorScheme == .light)
        #expect(AppAppearance.dark.colorScheme == .dark)
    }

    private struct Probe: View {
        var preferences = AMapStylePreferences()
        @Environment(\.colorScheme) private var colorScheme
        let receive: (Binding<AMapStyleName>) -> Void
        var body: some View {
            Color.clear.task(id: colorScheme) { receive(preferences.selection) }
        }
    }

    private func host(scheme: ColorScheme, defaults: UserDefaults) async throws
        -> (view: NSHostingView<AnyView>, window: NSWindow, selection: Binding<AMapStyleName>) {
        var selection: Binding<AMapStyleName>?
        let root = AnyView(Probe { selection = $0 }
            .environment(\.colorScheme, scheme).defaultAppStorage(defaults))
        let view = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        return (view, window, try #require(selection))
    }
}
