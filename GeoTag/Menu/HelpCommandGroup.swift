import SwiftUI
import UDF

// Add a help button that will link to the on line help pages.

struct HelpCommands: Commands {
    var store: Store<GeoTagState, GeoTagEvent>

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Link(destination: URL(string: "https://github.com/LittleSixNine/PhotoTrail")!) {
                Label("PhotoTrail Help…", systemImage: "link")
            }
            Divider()
            Link(destination: URL(string: "https://github.com/LittleSixNine/PhotoTrail/issues")!) {
                Label("Report a bug…", systemImage: "link")
            }
            Button("Show log…", systemImage: "list.clipboard") {
                store.send(.toggleLogWindow, undoable: false)
            }
        }
    }
}
