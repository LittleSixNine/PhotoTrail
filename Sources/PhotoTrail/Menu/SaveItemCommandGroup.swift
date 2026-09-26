import SwiftUI
import UDF

// Add Save... and other menu, items

struct SaveItemCommands: Commands {
    var store: Store<PhotoTrailState, PhotoTrailEvent>

    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Button(L10n.text("Save…"), systemImage: "square.and.arrow.down.on.square") {
                SaveHelper.requestSave(store)
            }
            .keyboardShortcut("s")
            .disabled(saveDisabled())

            Button(L10n.text("Discard changes"), systemImage: "mappin.slash") {
                store.send(.discardChangesRequest,
                           description: "discard changes")
            }
            .disabled(discardChangesDisabled())

            Button(L10n.text("Discard tracks"),
                   systemImage: "stroke.line.diagonal.slash") {
                store.send(.discardTracksRequest,
                           description: "discard tracks")
            }
            .disabled(discardTracksDisabled())

            Divider()

            Button(L10n.text("Clear Image List"), systemImage: "rectangle.stack.slash") {
                store.send(.clearImagesRequest,
                           description: "clear image list")
            }
            .keyboardShortcut("k")
            .disabled(clearDisabled())
        }
    }
}

extension SaveItemCommands {
    private func saveDisabled() -> Bool {
        return store.saveInProgress || !store.unsavedChanges
    }

    private func discardChangesDisabled() -> Bool {
        return store.saveInProgress || !store.unsavedChanges
    }

    private func discardTracksDisabled() -> Bool {
        return store.saveInProgress || store.gpxTracks.isEmpty
    }

    private func clearDisabled() -> Bool {
        return store.saveInProgress || store.imageData.isEmpty || store.unsavedChanges
    }
}
