import SwiftUI
import UDF

// Replace the undoRedo commands group

struct UndoRedoCommands: Commands {
    var store: Store<PhotoTrailState, PhotoTrailEvent>

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button(L10n.text("Undo"),
                   systemImage: "arrow.uturn.backward") {
                if !store.textfieldActive {
                    store.undo()
                }
            }
            .keyboardShortcut("z")
            .disabled(store.textfieldActive || store.saveInProgress || !store.canUndo)

            Button(L10n.text("Redo"),
                   systemImage: "arrow.uturn.forward") {
                if !store.textfieldActive {
                    store.redo()
                }
            }
            .keyboardShortcut("z", modifiers: [.shift, .command])
            .disabled(store.textfieldActive || store.saveInProgress || !store.canRedo)
        }
    }
}
