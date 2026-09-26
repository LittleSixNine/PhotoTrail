import SwiftUI
import UDF

// Add a help button that will link to the on line help pages.

struct HelpCommands: Commands {
    var store: Store<PhotoTrailState, PhotoTrailEvent>

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Link(destination: L10n.helpURL) {
                Label(L10n.text("PhotoTrail Help…"), systemImage: "link")
            }
            Divider()
            Link(destination: URL(string: "https://github.com/LittleSixNine/PhotoTrail/issues")!) {
                Label(L10n.text("Report a bug…"), systemImage: "link")
            }
            Button(L10n.text("Show log…"), systemImage: "list.clipboard") {
                store.send(.toggleLogWindow, undoable: false)
            }
        }
    }
}
