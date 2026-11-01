import PhotosUI
import SwiftUI
import UDF

struct PhotoPickerView: View {
    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) var store
    @State private var photoLibrary = PhotoLibrary.shared
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var libraryEnabled = false
    @State private var libraryDisabled = false

    var body: some View {
        Group {
            if photoLibrary.enabled {
                PhotosPicker(selection: $pickerItems,
                             matching: .images,
                             photoLibrary: .shared()) {
                    Label(L10n.text("从图库导入"), systemImage: "photo.on.rectangle").fixedSize()
                }
                .keyboardShortcut("i", modifiers: [.shift, .command])
            } else {
                Button {
                    photoLibrary.requestAuth { @MainActor enabled in
                        photoLibrary.enabled = enabled
                        if photoLibrary.enabled {
                            libraryEnabled.toggle()

                        } else {
                            libraryDisabled.toggle()
                        }
                    }
                } label: {
                    Label(L10n.text("从图库导入"), systemImage: "photo.on.rectangle").fixedSize()
                }
            }
        }
        .labelStyle(.titleAndIcon)
        .help(L10n.text("从 macOS「照片」图库选择照片。"))
        .onChange(of: pickerItems) {
            if !pickerItems.isEmpty {
                let selectedItems = pickerItems
                pickerItems = []
                Task {
                    store.beginUndoGroup(description: "add from photos lib")
                    await photoLibrary.addPhotos(from: selectedItems,
                                                 store: store)
                    store.endUndoGroup()
                }
            }
        }
        .photoLibraryEnabledAlert(isPresented: $libraryEnabled)
        .photoLibraryDisabledAlert(isPresented: $libraryDisabled)
    }
}

#Preview{
    Text(L10n.text("Look at the toolbar of ContentView\nto see how these sub-views are used."))
        .padding()
}

struct WorkspaceToolbarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var prominent = false
    var outlined = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isEnabled ? (prominent ? Color.white : Color.primary) : Color.secondary)
            .padding(.horizontal, 6)
            .frame(minHeight: 34)
            .background(prominent && isEnabled ? Color.blue : Color(nsColor: .controlBackgroundColor), in: Capsule())
            .overlay {
                if outlined {
                    Capsule().strokeBorder(Color.primary.opacity(isEnabled ? 0.24 : 0.12), lineWidth: 1)
                }
            }
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
