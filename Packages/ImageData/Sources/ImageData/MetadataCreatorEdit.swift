import Exiftool
import Foundation
import Imagetool

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
    case invalidValue
}

public struct MetadataCreatorEditPlan: Sendable {
    public struct Item: Equatable, Sendable {
        public let id: ImageData.ID
        public let imageURL: URL
        public let target: URL
        public let sidecar: Bool
        public let original: MetadataCreatorValue
        public let version: MetadataInspectionFileVersion
        public let change: MetadataTagChange?
    }

    public let items: [Item]

    // A snapshot binds the successful read to its file version. The selection
    // order is frozen here.
    public static func prepare(
        _ readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)],
        action: MetadataCreatorEditAction
    ) throws -> Self {
        struct FileID: Hashable {
            let device: UInt64
            let inode: UInt64
        }
        var seen = Set<FileID>()
        var items: [Item] = []
        for reading in readings {
            let imageURL: URL
            let sidecar: Bool
            switch reading.image.metadata.source {
            case .xmp(let url):
                imageURL = url
                sidecar = true
            case .image(let url) where ["jpg", "jpeg"].contains(url.pathExtension.lowercased()):
                imageURL = url
                sidecar = false
            default:
                throw MetadataCreatorPlanError.unavailableTarget
            }
            guard reading.image.updatable,
                  let target = reading.image.metadataInspectionURL else {
                throw MetadataCreatorPlanError.unavailableTarget
            }
            guard reading.snapshot.url.standardizedFileURL == target.standardizedFileURL,
                  reading.snapshot.requestedTags.contains(.creator),
                  case .file(let device, let inode, _, _, _, _, _) = reading.snapshot.version,
                  MetadataInspectionFileVersion.read(target) == reading.snapshot.version else {
                throw MetadataCreatorPlanError.sourceChanged
            }
            guard seen.insert(FileID(device: device, inode: inode)).inserted else {
                throw MetadataCreatorPlanError.duplicateTarget
            }
            let value: MetadataCreatorValue
            switch reading.snapshot.values[.creator] {
            case nil:
                value = .absent
            case .list(let names) where !names.isEmpty:
                value = .names(names)
            default:
                throw MetadataCreatorPlanError.invalidValue
            }
            items.append(Item(id: reading.image.id, imageURL: imageURL,
                              target: target, sidecar: sidecar,
                              original: value, version: reading.snapshot.version,
                              change: try action.change(from: value)))
        }
        return Self(items: items)
    }
}

public enum MetadataCreatorBackup: Sendable {
    case folder(URL)
    case disabled
}

public enum MetadataCreatorSaveResult: Equatable, Sendable {
    case unchanged
    case saved
    case staleSource
    case preparationFailed
    case failed
    case resultUnknown
}

public extension MetadataCreatorEditPlan.Item {
    func save(backup: MetadataCreatorBackup) async -> MetadataCreatorSaveResult {
        guard let change else { return .unchanged }
        guard MetadataInspectionFileVersion.read(target) == version else { return .staleSource }

        let sandbox: Sandbox
        do {
            sandbox = try Sandbox(for: imageURL)
        } catch {
            return .preparationFailed
        }
        defer { sandbox.removeSandboxFolder() }
        do {
            switch backup {
            case .folder(let folder):
                if sidecar {
                    try await sandbox.makeSidecarBackup(folder)
                } else {
                    try await sandbox.makeImageBackup(folder)
                }
            case .disabled:
                break
            }
        } catch {
            return .preparationFailed
        }
        guard MetadataInspectionFileVersion.read(target) == version else { return .staleSource }

        return Self.write(change: change, update: {
            _ = try sandbox.updateMetadataTags([.creator: change], sidecar: sidecar)
        }, readback: {
            try sandbox.metadataTags([.creator], sidecar: sidecar)[.creator]
        })
    }

    internal static func write(
        change: MetadataTagChange,
        update: () throws -> Void,
        readback: () throws -> MetadataTagValue?
    ) -> MetadataCreatorSaveResult {
        do {
            try update()
            return .saved
        } catch is MetadataTagUpdateError {
            let actual: MetadataTagValue?
            do {
                actual = try readback()
            } catch {
                return .resultUnknown
            }
            switch change {
            case .set(let expected) where actual == expected:
                return .saved
            case .remove where actual == nil:
                return .saved
            default:
                return .resultUnknown
            }
        } catch {
            return .failed
        }
    }
}
