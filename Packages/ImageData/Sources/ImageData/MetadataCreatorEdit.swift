import Exiftool
import Foundation

public enum MetadataCreatorValue: Equatable, Sendable {
    case absent
    case names([String])
}

public enum MetadataCreatorEditError: Error {
    case invalidNames
}

public enum MetadataCreatorEditAction: Equatable, Sendable {
    case set([String])
    case fillMissing([String])
    case remove

    // The caller must supply a successfully read value; a read failure is not
    // an absent field and must never trigger fillMissing or removal.
    public func change(from current: MetadataCreatorValue) throws -> MetadataTagChange? {
        switch self {
        case .set(let names):
            try Self.check(names)
            return current == .names(names) ? nil : .set(.list(names))
        case .fillMissing(let names):
            try Self.check(names)
            return current == .absent ? .set(.list(names)) : nil
        case .remove:
            return current == .absent ? nil : .remove
        }
    }

    private static func check(_ names: [String]) throws {
        guard !names.isEmpty, names.allSatisfy({ !$0.isEmpty }) else {
            throw MetadataCreatorEditError.invalidNames
        }
    }
}

public enum MetadataCreatorPlanError: Error {
    case unavailableTarget
    case sourceChanged
    case duplicateTarget
}

public struct MetadataCreatorEditPlan: Sendable {
    public struct Item: Sendable {
        public let id: ImageData.ID
        public let target: URL
        public let original: MetadataCreatorValue
        public let version: MetadataInspectionFileVersion
        public let change: MetadataTagChange?
    }

    public let items: [Item]

    // Supply the version captured with each successful read, not a fresh
    // version paired with a stale value. The selection order is frozen here.
    public static func prepare(
        _ readings: [(image: ImageData, value: MetadataCreatorValue,
                     version: MetadataInspectionFileVersion)],
        action: MetadataCreatorEditAction
    ) throws -> Self {
        struct FileID: Hashable {
            let device: UInt64
            let inode: UInt64
        }
        var seen = Set<FileID>()
        var items: [Item] = []
        for reading in readings {
            switch reading.image.metadata.source {
            case .xmp:
                break
            case .image(let url) where ["jpg", "jpeg"].contains(url.pathExtension.lowercased()):
                break
            default:
                throw MetadataCreatorPlanError.unavailableTarget
            }
            guard reading.image.updatable,
                  let target = reading.image.metadataInspectionURL else {
                throw MetadataCreatorPlanError.unavailableTarget
            }
            guard case .file(let device, let inode, _, _, _, _, _) = reading.version,
                  MetadataInspectionFileVersion.read(target) == reading.version else {
                throw MetadataCreatorPlanError.sourceChanged
            }
            guard seen.insert(FileID(device: device, inode: inode)).inserted else {
                throw MetadataCreatorPlanError.duplicateTarget
            }
            items.append(Item(id: reading.image.id, target: target,
                              original: reading.value, version: reading.version,
                              change: try action.change(from: reading.value)))
        }
        return Self(items: items)
    }
}
