import SwiftUI
import UDF

// Replace the toolbar commands group.  The command has nothing to do with a
// toolbar, but it's in the View menu which is where I want it.

struct ToolbarCommands: Commands {
    var store: Store<GeoTagState, GeoTagEvent>

    var body: some Commands {
        CommandGroup(replacing: .toolbar) {
            Section {
                Button {
                    @AppStorage(ImageTableView.hideInvalidImagesKey) var hideInvalidImages = false

                    hideInvalidImages.toggle()
                } label: {
                    ShowHidePinView()
                }
                .keyboardShortcut("d")

                PinOptionView()

                Button {
                    @AppStorage(ContentView.alternateLayoutKey) var alternateLayout = false

                    alternateLayout.toggle()
                } label: {
                    AlternateLayoutOptionView()
                }
            }

        }
    }
}

struct ShowHidePinView: View {
    @AppStorage(ImageTableView.hideInvalidImagesKey) var hideInvalidImages = false

    var body: some View {
        if hideInvalidImages {
            Label("Show Disabled Files", systemImage: "eye")
        } else {
            Label("Hide Disabled Files", systemImage: "eye.slash")
        }
    }
}

struct PinOptionView: View {
    @AppStorage(SettingsPreferences.showAllPhotoLocationsKey) var showAllPhotoLocations = true

    var body: some View {
        Toggle(isOn: $showAllPhotoLocations) {
            Label("在地图上显示所有照片的位置", systemImage: "mappin.circle")
        }
    }
}

struct AlternateLayoutOptionView: View {
    @AppStorage(ContentView.alternateLayoutKey) var alternateLayout = false

    var body: some View {
        Label(alternateLayout ? "切换到列表页" : "切换到详情页",
              systemImage: "arrow.left.arrow.right.square")
    }
}
