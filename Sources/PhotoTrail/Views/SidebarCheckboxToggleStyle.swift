import SwiftUI

struct SidebarCheckboxToggleStyle: ToggleStyle {
    var size: CGFloat = 18
    var showsLabel = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: size == 16 ? 4 : 5)
                        .fill(configuration.isOn ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                    RoundedRectangle(cornerRadius: size == 16 ? 4 : 5)
                        .strokeBorder(configuration.isOn ? Color.accentColor : Color.secondary.opacity(0.55))
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: size * 0.62, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: size, height: size)
                if showsLabel { configuration.label }
            }
            .frame(minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.checkbox)
        }
    }
}
