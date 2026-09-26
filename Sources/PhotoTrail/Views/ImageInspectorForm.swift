import ImageData
import SwiftUI
import UDF

struct ImageInspectorForm: View {
    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) private var store
    var image: ImageData

    private var notice: String {
        L10n.text("Latitude and Longitude updates will not take effect until the *return* key is pressed when either field is active.")
    }

    var body: some View {
        Form {
            Section(L10n.text("Date and Time")) {
                DateTimeSectionView(image: image)
            }
            Section(L10n.text("Location")) {
                LatLonSectionView(image: image)
            }
            Section(L10n.text("Notice")) {
                Text(notice)
            }
        }
        .disabled(store.saveInProgress)
    }
}

#Preview {
    Text("""
       Look at **ImageInspectorView**
       to see a preview of this sub-view
       """)
        .multilineTextAlignment(.leading)
        .padding()

}
