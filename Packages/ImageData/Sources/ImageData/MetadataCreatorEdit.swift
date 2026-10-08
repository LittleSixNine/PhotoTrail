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

public enum MetadataCreatorEditAction: Equatable, Codable, Sendable {
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

public enum MetadataFieldEditError: Error {
    case invalidAction
    case invalidValue
}

public enum MetadataFieldEditAction: Equatable, Codable, Sendable {
    case replaceAuthors([String])
    case fillMissingAuthors([String])
    case offsetDate(years: Int, months: Int, days: Int, hours: Int, minutes: Int, seconds: Int)
    case shiftDate(seconds: Int)
    case calendarDays(Int, timeZoneID: String?)
    case dateComponent(String, Int)
    case filenameDate(pattern: String, template: String)
    case sequence(start: String, stepSeconds: Int)
    case distribute(start: String, end: String)
    case appendText(String)
    case copy(MetadataTag)
    case setText(String)
    case fillMissingText(String)
    case replaceKeywords([String])
    case appendKeywords([String])
    case removeKeywords([String])
    case remove

    // A failed read must never be passed as nil: nil means a confirmed absence.
    public func change(for tag: MetadataTag,
                       from current: MetadataTagValue?) throws -> MetadataTagChange? {
        switch (tag, self) {
        case (_, .setText(let text)) where !tag.isList:
            let final = try tag.checkedText(tag.isDate ? MetadataDate(text).text : text)
            return current == .text(final) ? nil : .set(.text(final))
        case (_, .fillMissingText(let text)) where !tag.isList:
            let final = try tag.checkedText(tag.isDate ? MetadataDate(text).text : text)
            return current == nil ? .set(.text(final)) : nil
        case (_, .appendText(let text)) where !tag.isList && !tag.isDate && tag.numericRange == nil:
            guard !text.isEmpty else { throw MetadataFieldEditError.invalidValue }
            let existing: String
            switch current {
            case nil: existing = ""
            case .text(let value): existing = value
            default: throw MetadataFieldEditError.invalidValue
            }
            return .set(.text(existing + text))
        case (_, .replaceKeywords(let words)) where tag.isList && tag != .creator:
            let final = try Self.unique(words).map(tag.checkedText)
            if final.isEmpty { return current == nil ? nil : .remove }
            return Self.sameKeywords(current, final) ? nil : .set(.list(final))
        case (_, .appendKeywords(let words)) where tag.isList && tag != .creator:
            guard !words.isEmpty else { throw MetadataFieldEditError.invalidValue }
            let existing = try Self.keywords(from: current)
            let final = try Self.unique(existing + words).map(tag.checkedText)
            return Self.sameKeywords(current, final) ? nil : .set(.list(final))
        case (_, .removeKeywords(let words)) where tag.isList && tag != .creator:
            guard !words.isEmpty, words.allSatisfy({ !$0.isEmpty }) else {
                throw MetadataFieldEditError.invalidValue
            }
            let existing = try Self.keywords(from: current)
            let removed = Set(words.map { Data($0.utf8) })
            let final = try existing.filter { !removed.contains(Data($0.utf8)) }.map(tag.checkedText)
            if Self.sameKeywords(current, final) { return nil }
            return final.isEmpty ? .remove : .set(.list(final))
        case (.creator, .replaceAuthors(let names)), (.creator, .fillMissingAuthors(let names)):
            let creator: MetadataCreatorValue
            switch current {
            case nil: creator = .absent
            case .list(let names): creator = .names(names)
            default: throw MetadataFieldEditError.invalidValue
            }
            let action: MetadataCreatorEditAction = if case .replaceAuthors = self { .set(names) } else { .fillMissing(names) }
            return try action.change(from: creator)
        case (_, .offsetDate(let years, let months, let days, let hours, let minutes, let seconds)) where tag.isDate:
            guard case .text(let text) = current else { throw MetadataDateError.missingDate }
            let final = try tag.checkedText(MetadataDate(text).offsetting(
                years: years, months: months, days: days, hours: hours, minutes: minutes, seconds: seconds).text)
            return current == .text(final) ? nil : .set(.text(final))
        case (_, .remove) where !tag.isFileTime:
            return current == nil ? nil : .remove
        default:
            throw MetadataFieldEditError.invalidAction
        }
    }

    private static func keywords(from value: MetadataTagValue?) throws -> [String] {
        switch value {
        case nil: return []
        case .list(let words): return words
        default: throw MetadataFieldEditError.invalidValue
        }
    }

    private static func unique(_ words: [String]) throws -> [String] {
        guard words.allSatisfy({ !$0.isEmpty }) else {
            throw MetadataFieldEditError.invalidValue
        }
        var seen = Set<Data>()
        return words.filter { seen.insert(Data($0.utf8)).inserted }
    }

    private static func sameKeywords(_ current: MetadataTagValue?, _ words: [String]) -> Bool {
        guard case .list(let old) = current, old.count == words.count else { return false }
        return zip(old, words).allSatisfy { $0.0.utf8.elementsEqual($0.1.utf8) }
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
        public let tag: MetadataTag
        public let originalValue: MetadataTagValue?
        public let version: MetadataInspectionFileVersion
        public let change: MetadataTagChange?
        public let changes: [MetadataTag: MetadataTagChange]
    }

    public let items: [Item]

    // A snapshot binds the successful read to its file version. The selection
    // order is frozen here.
    public static func prepare(
        _ readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)],
        action: MetadataCreatorEditAction
    ) throws -> Self {
        try prepare(readings, tag: .creator) { value in
            let creator: MetadataCreatorValue
            switch value {
            case nil: creator = .absent
            case .list(let names) where !names.isEmpty: creator = .names(names)
            default: throw MetadataCreatorPlanError.invalidValue
            }
            return try action.change(from: creator)
        }
    }

    public static func prepare(
        _ readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)],
        tag: MetadataTag, action: MetadataFieldEditAction
    ) throws -> Self {
        return try prepare(readings, tag: tag) { value in
            switch (tag, value) {
            case (_, nil):
                return try action.change(for: tag, from: value)
            case (_, .list) where tag.isList:
                return try action.change(for: tag, from: value)
            case (_, .text) where !tag.isList:
                return try action.change(for: tag, from: value)
            default:
                throw MetadataCreatorPlanError.invalidValue
            }
        }
    }

    private static func prepare(
        _ readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)],
        tag: MetadataTag,
        change: (MetadataTagValue?) throws -> MetadataTagChange?
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
            guard !sidecar || tag.supportsSidecar else { throw MetadataCreatorPlanError.unavailableTarget }
            guard reading.image.updatable,
                  let target = reading.image.metadataInspectionURL else {
                throw MetadataCreatorPlanError.unavailableTarget
            }
            guard reading.snapshot.url.standardizedFileURL == target.standardizedFileURL,
                  reading.snapshot.requestedTags.contains(tag),
                  case .file(let device, let inode, _, _, _, _, _) = reading.snapshot.version,
                  MetadataInspectionFileVersion.read(target) == reading.snapshot.version else {
                throw MetadataCreatorPlanError.sourceChanged
            }
            guard seen.insert(FileID(device: device, inode: inode)).inserted else {
                throw MetadataCreatorPlanError.duplicateTarget
            }
            var value = reading.snapshot.values[tag]
            var changes = reading.image.creatorDraft?.changes ?? [:]
            if let draft = reading.image.creatorDraft {
                guard draft.target == target, draft.version == reading.snapshot.version else {
                    throw MetadataCreatorPlanError.sourceChanged
                }
                if let pending = changes[tag] {
                    switch pending {
                    case .set(let final): value = final
                    case .remove: value = nil
                    }
                }
            }
            let edit = try change(value)
            if let edit { changes[tag] = edit }
            if changes.keys.contains(where: { $0.rawValue.hasPrefix("IPTC:") }) {
                _ = try Exiftool.helper.needsIPTCUTF8Declaration(image: target, changes: changes)
                guard MetadataInspectionFileVersion.read(target) == reading.snapshot.version else {
                    throw MetadataCreatorPlanError.sourceChanged
                }
            }
            items.append(Item(id: reading.image.id, imageURL: imageURL,
                              target: target, sidecar: sidecar,
                              tag: tag, originalValue: value,
                              version: reading.snapshot.version,
                              change: edit, changes: changes))
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
    var captureDateChange: MetadataTagChange? { changes[sidecar ? .sidecarDate : .captureDate] }

    var captureDateValue: String? {
        guard case .set(.text(let value)) = captureDateChange else { return nil }
        return value
    }

    func save(backup: MetadataCreatorBackup) async -> MetadataCreatorSaveResult {
        guard !changes.isEmpty else { return .unchanged }
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

        return Self.write(changes: changes, update: {
            _ = try sandbox.updateMetadataTags(changes, sidecar: sidecar)
        }, readback: {
            try sandbox.metadataTags(Set(changes.keys), sidecar: sidecar)
        })
    }

    internal static func write(
        change: MetadataTagChange,
        update: () throws -> Void,
        readback: () throws -> MetadataTagValue?
    ) -> MetadataCreatorSaveResult {
        write(changes: [.creator: change], update: update) {
            try readback().map { [.creator: $0] } ?? [:]
        }
    }

    internal static func write(
        changes: [MetadataTag: MetadataTagChange],
        update: () throws -> Void,
        readback: () throws -> [MetadataTag: MetadataTagValue]
    ) -> MetadataCreatorSaveResult {
        do {
            try update()
            return .saved
        } catch is MetadataTagUpdateError {
            guard let actual = try? readback() else { return .resultUnknown }
            for (tag, change) in changes {
                switch change {
                case .set(let expected) where tag.matches(actual[tag], expected): break
                case .remove where actual[tag] == nil: break
                default: return .resultUnknown
                }
            }
            return .saved
        } catch {
            return .failed
        }
    }
}
