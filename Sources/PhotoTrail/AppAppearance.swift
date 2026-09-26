import SwiftUI

// Native macOS surfaces and type; neutral dark panels retain the existing blue actions.
// Hallmark · pre-emit critique: P4 H4 E4 S4 R5 V4

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let preferenceKey = "PhotoTrailAppearance"
    var id: Self { self }
    var title: String {
        switch self {
        case .system: L10n.text("跟随系统")
        case .light: L10n.text("亮色")
        case .dark: L10n.text("暗色")
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct AppAppearancePicker: View {
    @AppStorage(AppAppearance.preferenceKey) private var appearance: AppAppearance = .system

    var body: some View {
        Picker(L10n.text("界面外观"), selection: $appearance) {
            ForEach(AppAppearance.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.menu)
    }
}
