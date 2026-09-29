import Exiftool
import Foundation
import Metadata
import Testing
@testable import ImageData

struct MetadataSelectionValueTests {
    @Test func sourceRoutesToTheActualMetadataFile() {
        let imageURL = URL(fileURLWithPath: "/tmp/photo.jpg")
        let sidecarURL = URL(fileURLWithPath: "/tmp/photo.xmp")
        let image = ImageData(metadata: Metadata(source: .image(imageURL)), name: "photo.jpg")
        let sidecar = ImageData(metadata: Metadata(source: .xmp(sidecarURL)), name: "photo.jpg")
        let unavailable = ImageData(metadata: Metadata(source: .copy), name: "copy")

        #expect(image.metadataInspectionURL == imageURL)
        #expect(sidecar.metadataInspectionURL == sidecarURL)
        #expect(unavailable.metadataInspectionURL == nil)
    }

    @Test func selectionKeepsMissingDistinctFromMixedValues() {
        let alice = MetadataTagValue.list(["Alice"])
        let bob = MetadataTagValue.list(["Bob"])
        let tag = MetadataTag.creator

        #expect(MetadataSelectionValue.summarize([], tag: tag) == .unselected)
        #expect(MetadataSelectionValue.summarize([[:], [:]], tag: tag) == .absent)
        #expect(MetadataSelectionValue.summarize([[tag: alice], [tag: alice]], tag: tag)
                == .uniform(alice))
        #expect(MetadataSelectionValue.summarize([[tag: alice], [:]], tag: tag)
                == .mixed(present: 1, total: 2))
        #expect(MetadataSelectionValue.summarize([[tag: alice], [tag: bob]], tag: tag)
                == .mixed(present: 2, total: 2))
    }
}
