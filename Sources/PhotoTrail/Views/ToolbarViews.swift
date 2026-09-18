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
                    Image(systemName: "photo").frame(width: 16)
                        .accessibilityLabel("照片图库")
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
                    Image(systemName: "photo").frame(width: 16)
                        .accessibilityLabel("照片图库")
                }
            }
        }
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

struct InspectorButtonView: View {
    @Binding var presented: Bool

    var body: some View {
        Button {
            presented.toggle()
        } label: {
            Image(systemName: "info.circle").frame(width: 16)
                .accessibilityLabel("照片信息")
        }
        .help("显示或隐藏照片信息（⌘I）")
        .keyboardShortcut("i")
    }
}

#Preview{
    Text("""
        Look at the toolbar of ContentView
        to see how these sub-views are used.
        """)
        .padding()
}

struct WorkspaceToolbarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isEnabled ? (prominent ? Color.white : Color.primary) : Color.secondary)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(prominent && isEnabled ? Color.blue : Color(nsColor: .controlBackgroundColor), in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
