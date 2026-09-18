import ImageData
import SwiftUI
import UDF

struct ImageInspectorForm: View {
    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) private var store
    var image: ImageData

    let notice: LocalizedStringKey = """
        Latitude and Longitude updates will not take effect until the \
        *return* key is pressed when either field is active.
        """

    var body: some View {
        Form {
            Section("Date and Time") {
                DateTimeSectionView(image: image)
            }
            Section("Location") {
                LatLonSectionView(image: image)
            }
            Section("Notice") {
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
