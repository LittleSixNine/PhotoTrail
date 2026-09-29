import Exiftool
import Foundation
import Metadata

public extension ImageData {
    var metadataInspectionURL: URL? {
        switch metadata.source {
        case .image(let url), .xmp(let url): url
        case .photos, .copy: nil
        }
    }
}

public enum MetadataSelectionValue: Equatable, Sendable {
    case unselected
    case absent
    case uniform(MetadataTagValue)
    case mixed(present: Int, total: Int)

    // Pass only successful reads; a read error must be shown separately.
    public static func summarize(_ values: [[MetadataTag: MetadataTagValue]],
                                 tag: MetadataTag) -> Self {
        guard !values.isEmpty else { return .unselected }
        let present = values.compactMap { $0[tag] }
        guard !present.isEmpty else { return .absent }
        guard present.count == values.count,
              present.dropFirst().allSatisfy({ $0 == present[0] }) else {
            return .mixed(present: present.count, total: values.count)
        }
        return .uniform(present[0])
    }
}
