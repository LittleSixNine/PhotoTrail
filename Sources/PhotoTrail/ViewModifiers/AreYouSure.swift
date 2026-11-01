import SwiftUI
import UDF

// modifier designed to add a confirmation dialog to any view that uses it.

struct AreYouSure: ViewModifier {
    var discardMetadataInput: () -> Void = {}
    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) var store
    @State private var presentConfirmation = false

    func body(content: Content) -> some View {
        content
            .alert(L10n.text("有未保存的修改"), isPresented: Binding(
                get: { presentConfirmation && store.confirmationEvent == .terminateRequest },
                set: { presentConfirmation = $0 }
            )) {
                Button(L10n.text("继续编辑"), role: .cancel) {}
                    .keyboardShortcut(.defaultAction)
                Button(L10n.text("放弃修改并退出"), role: .destructive) {
                    discardMetadataInput()
                    store.send(.terminateRequest, undoable: false) { NSApp.terminate(nil) }
                }
            } message: {
                Text(L10n.text("退出后，未保存的照片修改与尚未应用的批量输入将丢失。请先保存，或放弃修改后退出。"))
            }
            .confirmationDialog(L10n.text("Are you sure?"),
            isPresented: Binding(
                get: { presentConfirmation && store.confirmationEvent != .terminateRequest },
                set: { presentConfirmation = $0 }
            ))
        {
            Button(L10n.text("I'm sure"), role: .destructive) {
                if let event = store.confirmationEvent {
                    store.send(event, undoable: false) {
                        if event == .terminateRequest {
                            discardMetadataInput()
                            NSApp.terminate(nil)
                        }
                    }
                }
            }
            .keyboardShortcut(.defaultAction)
            Button(L10n.text("Cancel"), role: .cancel) {}
                .keyboardShortcut(.cancelAction)
        } message: {
            let message = store.confirmationMessage ?? ""
            Text(LocalizedStringKey(message))
        }
        .onChange(of: store.presentConfirmation) {
            presentConfirmation = true
        }
    }
}

extension View {
    func areYouSure(discardMetadataInput: @escaping () -> Void = {}) -> some View {
        modifier(AreYouSure(discardMetadataInput: discardMetadataInput))
    }
}
