import Darwin
import Exiftool
import Foundation
import Metadata

public enum MetadataInspectionFileVersion: Equatable, Sendable {
    case unavailable
    case missing
    case file(device: UInt64, inode: UInt64, size: Int64,
              modifiedSeconds: Int, modifiedNanoseconds: Int,
              changedSeconds: Int, changedNanoseconds: Int)

    public static func read(_ url: URL?) -> Self {
        guard let url else { return .unavailable }
        var info = stat()
        let found = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return fstatat(AT_FDCWD, path, &info, 0) == 0
        }
        guard found else { return .missing }
        return .file(device: UInt64(info.st_dev), inode: UInt64(info.st_ino),
                     size: info.st_size,
                     modifiedSeconds: info.st_mtimespec.tv_sec,
                     modifiedNanoseconds: info.st_mtimespec.tv_nsec,
                     changedSeconds: info.st_ctimespec.tv_sec,
                     changedNanoseconds: info.st_ctimespec.tv_nsec)
    }
}

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
