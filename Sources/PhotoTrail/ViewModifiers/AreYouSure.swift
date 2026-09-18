import SwiftUI
import UDF

// modifier designed to add a confirmation dialog to any view that uses it.

struct AreYouSure: ViewModifier {
    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) var store
    @State private var presentConfirmation = false

    func body(content: Content) -> some View {
        content
            .alert("有未保存的修改", isPresented: Binding(
                get: { presentConfirmation && store.confirmationEvent == .terminateRequest },
                set: { presentConfirmation = $0 }
            )) {
                Button("继续编辑", role: .cancel) {}
                    .keyboardShortcut(.defaultAction)
                Button("放弃修改并退出", role: .destructive) {
                    store.send(.terminateRequest, undoable: false) { NSApp.terminate(nil) }
                }
            } message: {
                Text("退出后，尚未保存的拍摄时间、定位等修改将丢失。请先保存，或放弃修改后退出。")
            }
            .confirmationDialog("Are you sure?",
            isPresented: Binding(
                get: { presentConfirmation && store.confirmationEvent != .terminateRequest },
                set: { presentConfirmation = $0 }
            ))
        {
            Button("I'm sure", role: .destructive) {
                if let event = store.confirmationEvent {
                    store.send(event, undoable: false) {
                        if event == .terminateRequest {
                            NSApp.terminate(nil)
                        }
                    }
                }
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {}
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
    func areYouSure() -> some View {
        modifier(AreYouSure())
    }
}
