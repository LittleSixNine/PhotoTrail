import Coords
import CoreLocation
import ImageData
import SwiftUI
import UDF

struct LatLonSectionView: View {
    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) var store

    var image: ImageData

    @State private var latitude: Double?
    @State private var longitude: Double?
    @FocusState private var isFocused: Bool

    @AppStorage(Coords.coordFormatKey) var coordFormat: CoordFormat = .deg

    // notice the bogus "focused" value given to .focusedValue. I need a non
    // empty string to enable cut/copy/paste/select all and this was an
    // easy way to do it with a side effect of the menu commands being
    // enabled even when the fields are empty.

    var body: some View {
        VStack {
            LabeledContent(L10n.text("Latitude:")) {
                TextField(L10n.text("Latitude"), value: $latitude, format: .latitude)
                    .frame(width: 200)
                    .labelsHidden()
                    .padding()
                    .focused($isFocused)
            }

            LabeledContent(L10n.text("Longitude:")) {
                TextField(L10n.text("Longitude"), value: $longitude, format: .longitude)
                    .frame(width: 200)
                    .labelsHidden()
                    .padding()
                    .focused($isFocused)
            }

            LabeledContent(L10n.text("City:")) {
                Text(image.metadata.city ?? "?")
                    .frame(width: 200, alignment: .leading)
            }

            LabeledContent(L10n.text("State:")) {
                Text(image.metadata.state ?? "?")
                    .frame(width: 200, alignment: .leading)
            }

            LabeledContent(L10n.text("Country:")) {
                Text(image.metadata.country ?? "?")
                    .frame(width: 200, alignment: .leading)
            }

            LabeledContent(L10n.text("Country Code:")) {
                Text(image.metadata.countryCode ?? "?")
                    .frame(width: 200, alignment: .leading)
            }
        }
        .textFieldStyle(.roundedBorder)
        .onExitCommand {
            loadCoordinates()
            isFocused = false
        }
        .onSubmit {
            if validateLocation() {
                if let latitude, let longitude {
                    store.send(.locationChanged(Coords(latitude: latitude,
                                                       longitude: longitude)),
                               description: "update location") {
                        let selected = store.selection
                        Task {
                            let address =
                            await ReverseLocationFinder.reverseGeocode(store: store,
                                                                       id: image.id)
                            if let address {
                                store.send(.addressChanged(selected, address),
                                           undoable: false)
                            }
                        }
                    }
                    isFocused = false
                }
            }
        }
        .onChange(of: coordFormat) {
            loadCoordinates()
        }
        .onChange(of: isFocused) {
            store.send(.textfieldFocusChanged(isFocused), undoable: false)
        }
        .task(id: image.metadata.location) {
            loadCoordinates()
        }
    }

    // set state variables from image location

    private func loadCoordinates() {
        if let location = image.metadata.location {
            latitude = location.latitude
            longitude = location.longitude
        } else {
            latitude = nil
            longitude = nil
        }
    }

    // check that latitude and longitude are non-nil and in appropriate range

    private func validateLocation() -> Bool {
        if let latitude,
            let longitude,
            (0 ... 90).contains(latitude.magnitude),
            (0 ... 180).contains(longitude.magnitude)
        {
            return true
        }
        return false
    }
}

// I want my labels in line with the text field.

struct InlineLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            configuration.content
        }
    }
}

extension LabeledContentStyle where Self == InlineLabeledContentStyle {
    static var inline: InlineLabeledContentStyle { InlineLabeledContentStyle() }
}

#Preview {
    Text("""
       Look at **ImageInspectorView**
       to see a preview of this sub-view
       """)
        .multilineTextAlignment(.leading)
        .padding()

}
