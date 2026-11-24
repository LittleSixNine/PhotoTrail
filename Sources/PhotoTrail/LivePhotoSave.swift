import Darwin
import Exiftool
import Foundation
import ImageData
import Imagetool
import Metadata

/// Each exchange is atomic. Until the journal is committed, each exchanged staging file is the
/// original inode and can be exchanged back without relying on the user's optional backup policy.
enum LivePhotoSave {
    struct Member: Sendable {
        let image: ImageData
        let fields: MetadataCreatorEditPlan.Item?
        let map: Metadata?
    }

    struct RolledBack: LocalizedError {
        let versions: [ImageData.ID: MetadataInspectionFileVersion]
        let cause: String
        var errorDescription: String? { cause }
    }

    struct RecoveryNeeded: LocalizedError {
        let files: Set<URL>
        let cause: String
        var errorDescription: String? { cause }
    }

    private struct Entry: Codable {
        let original: URL
        let staged: URL
        let before: String
        let after: String
    }

    private struct Journal: Codable {
        let work: URL
        var entries: [Entry]
        var members: [URL]?
        var committed = false
    }

    private static var storage: URL { RenameExecutor.storage.deletingLastPathComponent().appendingPathComponent("LivePhotoSaves") }

    private static func exchange(_ first: URL, _ second: URL) throws {
        guard renamex_np(first.path, second.path, UInt32(RENAME_SWAP)) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    private static func persist(_ journal: Journal, at url: URL) throws {
        try JSONEncoder().encode(journal).write(to: url, options: .atomic)
    }

    private static func finish(_ journal: Journal, at url: URL) throws {
        if !journal.committed {
            var failure: Error?
            for entry in journal.entries.reversed() {
                do {
                    let current = try RenameExecutor.digest(entry.original)
                    if current == entry.before { continue }
                    guard current == entry.after, try RenameExecutor.digest(entry.staged) == entry.before else {
                        throw MetadataInspectionError.sourceChanged
                    }
                    try exchange(entry.original, entry.staged)
                } catch { failure = error }
            }
            if let failure { throw failure }
        }
        if FileManager.default.fileExists(atPath: journal.work.path) { try FileManager.default.removeItem(at: journal.work) }
        try FileManager.default.removeItem(at: url)
    }

    private static func locked<T>(_ directory: URL, _ action: () throws -> T) throws -> T {
        let fd = open(directory.path, O_RDONLY | O_DIRECTORY)
        guard fd >= 0 else { throw CocoaError(.fileReadNoPermission) }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw CocoaError(.fileLocking) }
        return try action()
    }

    static func recover(in directory: URL) throws {
        guard FileManager.default.fileExists(atPath: storage.path) else { return }
        let records = try FileManager.default.contentsOfDirectory(at: storage, includingPropertiesForKeys: nil)
        for url in records where url.pathExtension == "json" {
            let journal = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: url))
            if journal.work.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL {
                try locked(directory) { try recoverLocked(in: directory) }; return
            }
        }
    }

    private static func recoverLocked(in directory: URL) throws {
        var blocked: Set<URL> = []
        var reason: String?
        for url in try FileManager.default.contentsOfDirectory(at: storage, includingPropertiesForKeys: nil)
            where url.pathExtension == "json" {
            let journal = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: url))
            guard journal.work.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL else { continue }
            do { try finish(journal, at: url) }
            catch {
                blocked.formUnion((journal.members ?? journal.entries.map(\.original)).map(\.standardizedFileURL))
                reason = error.localizedDescription
            }
        }
        if let reason { throw RecoveryNeeded(files: blocked, cause: reason) }
    }

    static func write(_ members: [Member], backup: URL?, timeZone: TimeZone?,
                      beforeExchange: (Int) throws -> Void = { _ in }) throws {
        guard members.count == 2, let id = members.first?.image.livePhotoIdentifier,
              Set(members.map { $0.image.isLocalMovie }).count == 2,
              let folder = members.first?.image.metadataCreatorImageURL?.deletingLastPathComponent() else {
            throw MetadataInspectionError.sourceChanged
        }
        let fm = FileManager.default
        try locked(folder) {
            try fm.createDirectory(at: storage, withIntermediateDirectories: true)
            try recoverLocked(in: folder)
            let token = UUID().uuidString
            let work = folder.appendingPathComponent(".PhotoTrail-Live-" + token, isDirectory: true)
            let record = storage.appendingPathComponent(token + ".json")
            var journal = Journal(work: work, entries: [], members: members.compactMap { $0.image.metadataCreatorImageURL })
            try persist(journal, at: record)
            try fm.createDirectory(at: work, withIntermediateDirectories: false)
            var published = false
            defer { if !published { try? fm.removeItem(at: work); try? fm.removeItem(at: record) } }
            var versions: [URL: MetadataInspectionFileVersion] = [:]
            for member in members {
                let (url, version) = try preflight(member, id: id, folder: folder)
                versions[url] = version
                if member.fields != nil || member.map != nil {
                    let entry = try prepare(member, original: url, work: work, id: id, timeZone: timeZone)
                    if entry.before != entry.after { journal.entries.append(entry) }
                }
            }
            guard versions.allSatisfy({ MetadataInspectionFileVersion.read($0.key) == $0.value }) else { throw MetadataInspectionError.sourceChanged }
            if let backup { try backUp(members, in: backup, token: token) }
            try persist(journal, at: record)
            published = true
            do {
                for (index, entry) in journal.entries.enumerated() {
                    try beforeExchange(index)
                    guard MetadataInspectionFileVersion.read(entry.original) == versions[entry.original] else { throw MetadataInspectionError.sourceChanged }
                    try exchange(entry.original, entry.staged)
                    guard try RenameExecutor.digest(entry.staged) == entry.before else { throw MetadataInspectionError.sourceChanged }
                }
                for (url, version) in versions where !journal.entries.contains(where: { $0.original == url }) {
                    guard MetadataInspectionFileVersion.read(url) == version else { throw MetadataInspectionError.sourceChanged }
                }
                journal.committed = true
                try persist(journal, at: record)
            } catch {
                journal.committed = false
                try finish(journal, at: record)
                var restored: [ImageData.ID: MetadataInspectionFileVersion] = [:]
                for member in members {
                    guard let url = member.image.metadataCreatorImageURL else { continue }
                    // Only rebind snapshots for files whose exact original content was restored.
                    if journal.entries.contains(where: { $0.original == url }) {
                        restored[member.image.id] = MetadataInspectionFileVersion.read(url)
                    }
                }
                throw RolledBack(versions: restored, cause: error.localizedDescription)
            }
            // A committed transaction with deferred housekeeping is safe to finish on next import.
            try? finish(journal, at: record)
        }
    }

    private static func preflight(_ member: Member, id: String, folder: URL) throws -> (URL, MetadataInspectionFileVersion) {
        let fm = FileManager.default
        let image = member.image
        guard case .image(let url) = image.metadata.source, image.livePhotoIdentifier == id,
              url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL,
              image.metadataTargetWritable, fm.isWritableFile(atPath: url.path),
              try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]).isSymbolicLink != true else {
            throw CocoaError(.fileWriteNoPermission)
        }
        let version = MetadataInspectionFileVersion.read(url)
        guard case .file = version, version == image.livePhotoVersion,
              member.fields == nil || member.fields?.version == version,
              try identifier(url, movie: image.isLocalMovie) == id else { throw MetadataInspectionError.sourceChanged }
        return (url, version)
    }

    private static func prepare(_ member: Member, original url: URL, work: URL, id: String, timeZone: TimeZone?) throws -> Entry {
        let fm = FileManager.default
        let image = member.image
        let staged = work.appendingPathComponent(url.lastPathComponent)
        try fm.copyItem(at: url, to: staged)
        let before = try RenameExecutor.digest(staged)
        try writeFields(member, to: staged, timeZone: timeZone)
        guard try identifier(staged, movie: image.isLocalMovie) == id else { throw MetadataInspectionError.sourceChanged }
        let after = try RenameExecutor.digest(staged)
        return Entry(original: url, staged: staged, before: before, after: after)
    }

    private static func writeFields(_ member: Member, to staged: URL, timeZone: TimeZone?) throws {
        let image = member.image
        var changes = member.fields?.changes ?? [:]
        var map = member.map
        if let snapshot = member.map {
            if image.hasLegacyDateChanges {
                changes[.captureDate] = snapshot.dateTimeCreated.map { .set(.text($0)) } ?? .remove
            }
            if image.isLocalMovie {
                if !snapshot.preserveGPSOnSave {
                    changes[.captureLocation] = snapshot.location.map { .set(.text(CaptureLocationField.text($0))) } ?? .remove
                }
                for (tag, key) in [(MetadataTag.city, \.city), (.regionState, \.state), (.country, \.country)] as [(MetadataTag, KeyPath<Metadata, String?>)] {
                    if image.metadata[keyPath: key] != image.original?[keyPath: key] {
                        changes[tag] = image.metadata[keyPath: key].map { .set(.text($0)) } ?? .remove
                    }
                }
                map = nil
            } else {
                var writing = try RegionSaveSnapshot(snapshot, original: image.original).writing
                writing.applyCatalogRegions(changes)
                map = writing
            }
        }
        _ = try Exiftool.helper.update(image: staged, changes: changes, mapMetadata: map, timeZone: timeZone)
    }

    private static func backUp(_ members: [Member], in backup: URL, token: String) throws {
        for member in members {
            guard let url = member.image.metadataCreatorImageURL else { throw MetadataInspectionError.sourceChanged }
            try ManagedBackup.write(in: backup) { directory in
                let fm = FileManager.default
                var target = directory.appendingPathComponent(url.lastPathComponent)
                if fm.fileExists(atPath: target.path) { target = directory.appendingPathComponent(token + "-" + url.lastPathComponent) }
                try fm.copyItem(at: url, to: target)
                return target
            }
        }
    }

    private static func identifier(_ url: URL, movie: Bool) throws -> String? {
        if movie { return try Exiftool.helper.quickTimeVideoInfo(from: url).contentIdentifier }
        return ImageData.stillContentIdentifier(url)
    }
}
