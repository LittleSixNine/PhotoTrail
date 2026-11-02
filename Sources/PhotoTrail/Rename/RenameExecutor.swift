import CryptoKit
import Darwin
import Foundation

struct RenameFileIdentity: Codable, Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
    let size: Int64
    let modifiedSeconds: Int
    let modifiedNanoseconds: Int
    let changedSeconds: Int
    let changedNanoseconds: Int
    var copyCompatible: Bool?

    static func read(_ url: URL) throws -> Self {
        var info = stat()
        let status = url.withUnsafeFileSystemRepresentation { path in
            path.map { lstat($0, &info) } ?? -1
        }
        guard status == 0, (info.st_mode & S_IFMT) == S_IFREG else { throw RenameError.invalidSource }
        return Self(device: UInt64(info.st_dev), inode: UInt64(info.st_ino), size: info.st_size,
                    modifiedSeconds: info.st_mtimespec.tv_sec, modifiedNanoseconds: info.st_mtimespec.tv_nsec,
                    changedSeconds: info.st_ctimespec.tv_sec, changedNanoseconds: info.st_ctimespec.tv_nsec,
                    copyCompatible: (try? url.resourceValues(forKeys: [.volumeSupportsExclusiveRenamingKey])
                        .volumeSupportsExclusiveRenaming) == false ? true : nil)
    }

    // Compatible copies change inode; callers also verify the content hash.
    func sameFile(_ other: Self) -> Bool {
        device == other.device && (inode == other.inode || copyCompatible == true) && size == other.size &&
        modifiedSeconds == other.modifiedSeconds && modifiedNanoseconds == other.modifiedNanoseconds
    }
}

struct RenamePlan: Sendable {
    let rows: [RenamePreview]
    let versions: [URL: RenameFileIdentity]
    var counterValues: [Int: Int] = [:]
    var counterAdvances: [Int: Int] = [:]
}

struct RenameJournal: Codable, Identifiable, Sendable {
    struct Entry: Codable, Sendable {
        let original: URL
        let target: URL
        let temporary: URL
        let identity: RenameFileIdentity
        let hash: String
        var bookmark: Data?
    }
    var id = UUID()
    var version = 1
    var created = Date()
    var state = "prepared"
    var entries: [Entry]
    var failure: String?
}

struct RenameExecutionResult: Sendable {
    let journal: RenameJournal
    let mappings: [URL: URL]
    let error: String?
    let needsRecovery: Bool
}

struct RenameProgress: Sendable {
    enum Phase: Sendable { case checking, staging, renaming, verifying, restoring }
    let phase: Phase
    let completed: Int
    let total: Int
    var fraction: Double {
        guard total > 0 else { return 0 }
        let step: Int
        switch phase {
        case .checking, .restoring: step = 0
        case .staging: step = 1
        case .renaming: step = 2
        case .verifying: step = 3
        }
        return phase == .restoring ? Double(completed) / Double(total)
            : Double(step * total + completed) / Double(4 * total)
    }
}

private struct RenameProgressReporter {
    let report: @Sendable (RenameProgress) -> Void
    private var last = -Double.infinity
    private var phase: RenameProgress.Phase?
    init(_ report: @escaping @Sendable (RenameProgress) -> Void) { self.report = report }
    mutating func update(_ phase: RenameProgress.Phase, completed: Int, total: Int) {
        let now = ProcessInfo.processInfo.systemUptime
        guard self.phase != phase || completed == total || now - last >= 0.15 else { return }
        self.phase = phase
        last = now
        report(.init(phase: phase, completed: completed, total: total))
    }
}

enum RenameExecutor {
    static var storage: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PhotoTrail/Rename", isDirectory: true)
    }

    static func digest(_ url: URL, cancelled: @Sendable () -> Bool = { false }) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while true {
            guard !cancelled() else { throw CancellationError() }
            // FileHandle returns autoreleased NSData; a synchronous batch otherwise retains every block.
            let count = try autoreleasepool {
                let bytes = try handle.read(upToCount: 1_048_576) ?? Data()
                hash.update(data: bytes)
                return bytes.count
            }
            if count == 0 { break }
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func write(_ journal: RenameJournal, directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent(journal.id.uuidString + ".json")
        let data = try JSONEncoder().encode(journal)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let handle = try FileHandle(forWritingTo: url)
        try handle.synchronize()
        try handle.close()
    }

    static func saveFailure(_ journal: inout RenameJournal, directory: URL) {
        do { try write(journal, directory: directory) }
        catch {
            journal.failure = (journal.failure ?? "") + "\n" + L10n.text("执行记录未能保存：%1$@", RenameCopy.error(error))
        }
    }

    static func journals(directory: URL = storage) throws -> (records: [RenameJournal], unreadable: Int) {
        let urls: [URL]
        do { urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) }
        catch CocoaError.fileReadNoSuchFile { return ([], 0) }
        var records: [RenameJournal] = []
        var unreadable = 0
        for url in urls where url.pathExtension == "json" {
            do {
                let journal = try JSONDecoder().decode(RenameJournal.self, from: Data(contentsOf: url))
                guard journal.version == 1 else { unreadable += 1; continue }
                records.append(journal)
            } catch { unreadable += 1 }
        }
        return (records.sorted { $0.created > $1.created }, unreadable)
    }

    static func pairedSources(_ urls: [URL], settings: RenameSettings, directories: Set<URL>) throws -> [URL] {
        var uniqueURLs = Set<URL>()
        var urls = urls.map(\.standardizedFileURL).filter { uniqueURLs.insert($0).inserted }
        let initial = urls
        let sources = Set(settings.sourceExtensions.split(separator: ",").map { RenameEngine.key($0.trimmingCharacters(in: .whitespaces)) })
        let targets = Set(settings.targetExtensions.split(separator: ",").map { RenameEngine.key($0.trimmingCharacters(in: .whitespaces)) })
        if settings.pair {
            var seen = Set(urls)
            var directoryCache: [URL: [String]] = [:]
            for url in initial where sources.contains(RenameEngine.key(url.pathExtension)) {
                let parent = url.deletingLastPathComponent()
                guard directories.contains(parent.standardizedFileURL) else { continue }
                if directoryCache[parent] == nil { directoryCache[parent] = try FileManager.default.contentsOfDirectory(atPath: parent.path) }
                for name in directoryCache[parent]! {
                    let parts = RenameEngine.split(name)
                    let ext = RenameEngine.key(String(parts.ext.dropFirst()))
                    guard RenameEngine.key(parts.stem) == RenameEngine.key(RenameEngine.split(url.lastPathComponent).stem),
                          targets.contains(ext) || sources.contains(ext) else { continue }
                    let candidate = parent.appendingPathComponent(name)
                    if seen.insert(candidate).inserted { urls.append(candidate) }
                }
            }
        }
        return urls
    }

    static func occupied(_ directories: Set<URL>) throws -> [String: Set<String>] {
        var result: [String: Set<String>] = [:]
        for directory in directories {
            let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            result[directory.path] = Set(names.map(RenameEngine.key))
        }
        return result
    }

    /// Use an exclusive native rename, or an exclusive verified copy on volumes without it.
    static func move(_ source: URL, to target: URL) throws {
        guard source.deletingLastPathComponent().standardizedFileURL == target.deletingLastPathComponent().standardizedFileURL,
              RenameEngine.validName(target.lastPathComponent.replacingOccurrences(of: ":", with: "_")) else { throw RenameError.invalidSource }
        let status = source.withUnsafeFileSystemRepresentation { from in
            target.withUnsafeFileSystemRepresentation { to in
                guard let from, let to else { return Int32(-1) }
                return renamex_np(from, to, UInt32(RENAME_EXCL))
            }
        }
        guard status != 0 else { return }
        let code = POSIXErrorCode(rawValue: errno) ?? .EIO
        guard code == .ENOTSUP else { throw POSIXError(code) }
        try copyMove(source, to: target)
    }

    static func copyMove(_ source: URL, to target: URL) throws {
        let before = try RenameFileIdentity.read(source)
        let sourceFD = open(source.path, O_RDONLY | O_NOFOLLOW)
        guard sourceFD >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(sourceFD) }
        var opened = stat()
        guard fstat(sourceFD, &opened) == 0, UInt64(opened.st_ino) == before.inode,
              UInt64(opened.st_dev) == before.device else { throw RenameError.stalePlan }
        let hash = try digest(source)
        var expectedCopy = before
        expectedCopy.copyCompatible = true
        // O_EXCL reserves the destination even if another process creates the same name concurrently.
        let targetFD = open(target.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard targetFD >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(targetFD) }
        var created = stat()
        guard fstat(targetFD, &created) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        do {
            guard fcopyfile(sourceFD, targetFD, nil, copyfile_flags_t(COPYFILE_ALL)) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            var attributes = attrlist()
            attributes.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
            attributes.commonattr = attrgroup_t(ATTR_CMN_CRTIME)
            var creation = opened.st_birthtimespec
            guard fsetattrlist(targetFD, &attributes, &creation, MemoryLayout<timespec>.size, 0) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            guard fsync(targetFD) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            guard fstat(targetFD, &created) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            let copied = try RenameFileIdentity.read(target)
            guard copied.inode == UInt64(created.st_ino), copied.device == UInt64(created.st_dev),
                  expectedCopy.sameFile(copied), try digest(target) == hash,
                  try RenameFileIdentity.read(source) == before, try digest(source) == hash else {
                throw RenameError.stalePlan
            }
            guard unlink(source.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        } catch {
            // Remove only our own destination, and only while the unchanged source still exists.
            if fstat(targetFD, &created) == 0, let current = try? RenameFileIdentity.read(target),
               current.inode == UInt64(created.st_ino), current.device == UInt64(created.st_dev),
               (try? RenameFileIdentity.read(source)) == before {
                _ = unlink(target.path)
            }
            throw error
        }
    }

    static func execute(_ plan: RenamePlan, directory: URL = storage,
                        cancelled: @Sendable () -> Bool = { false },
                        progress: @escaping @Sendable (RenameProgress) -> Void = { _ in }) throws -> RenameExecutionResult {
        guard !plan.rows.contains(where: { $0.issues.contains(.conflict) || $0.issues.contains(.invalidName) }) else {
            throw RenameError.occupied
        }
        let rows = plan.rows.filter(\.changes)
        guard !rows.isEmpty else { throw RenameError.invalidSource }
        guard rows.allSatisfy({ RenameEngine.validName($0.target.lastPathComponent) }) else { throw RenameError.invalidSource }
        var seen = Set<String>()
        var entries: [RenameJournal.Entry] = []
        var reporter = RenameProgressReporter(progress)
        reporter.update(.checking, completed: 0, total: rows.count)
        var bookmarks: [URL: Data] = [:]
        // Revalidate every source before any mutation. Content hashes bind undo and crash recovery to these files.
        for row in rows {
            if cancelled() { throw CancellationError() }
            guard let version = plan.versions[row.source], try RenameFileIdentity.read(row.source) == version else {
                throw RenameError.stalePlan
            }
            guard seen.insert("\(version.device):\(version.inode)").inserted else { throw RenameError.invalidSource }
            let hash = try digest(row.source, cancelled: cancelled)
            guard try RenameFileIdentity.read(row.source) == version else { throw RenameError.stalePlan }
            let temporary = row.source.deletingLastPathComponent().appendingPathComponent(".phototrail-rename-" + UUID().uuidString)
            let parent = row.source.deletingLastPathComponent()
            let bookmark = bookmarks[parent] ?? (try? autoreleasepool {
                try parent.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            })
            if let bookmark { bookmarks[parent] = bookmark }
            entries.append(.init(original: row.source, target: row.target, temporary: temporary,
                                 identity: version, hash: hash, bookmark: bookmark))
            reporter.update(.checking, completed: entries.count, total: rows.count)
        }
        var journal = RenameJournal(entries: entries)
        try write(journal, directory: directory)
        var stage = L10n.text("正在准备修改名称…")
        var currentFile: URL?
        do {
            reporter.update(.staging, completed: 0, total: entries.count)
            for (index, entry) in entries.enumerated() {
                currentFile = entry.original
                if cancelled() { throw CancellationError() }
                guard try RenameFileIdentity.read(entry.original) == entry.identity else { throw RenameError.stalePlan }
                try move(entry.original, to: entry.temporary)
                guard entry.identity.sameFile(try RenameFileIdentity.read(entry.temporary)), try digest(entry.temporary, cancelled: cancelled) == entry.hash else {
                    throw RenameError.stalePlan
                }
                reporter.update(.staging, completed: index + 1, total: entries.count)
            }
            journal.state = "staged"
            try write(journal, directory: directory)
            stage = L10n.text("正在修改文件名…")
            reporter.update(.renaming, completed: 0, total: entries.count)
            for (index, entry) in entries.enumerated() {
                currentFile = entry.original
                if cancelled() { throw CancellationError() }
                guard entry.identity.sameFile(try RenameFileIdentity.read(entry.temporary)),
                      try digest(entry.temporary, cancelled: cancelled) == entry.hash else { throw RenameError.stalePlan }
                try move(entry.temporary, to: entry.target)
                reporter.update(.renaming, completed: index + 1, total: entries.count)
            }
            stage = L10n.text("正在核对结果…")
            reporter.update(.verifying, completed: 0, total: entries.count)
            for (index, entry) in entries.enumerated() {
                currentFile = entry.original
                guard entry.identity.sameFile(try RenameFileIdentity.read(entry.target)), try digest(entry.target, cancelled: cancelled) == entry.hash else {
                    throw RenameError.stalePlan
                }
                reporter.update(.verifying, completed: index + 1, total: entries.count)
            }
            journal.state = "completed"
            try write(journal, directory: directory)
            return .init(journal: journal, mappings: Dictionary(uniqueKeysWithValues: entries.map { ($0.original, $0.target) }),
                         error: nil, needsRecovery: false)
        } catch {
            // Recovery validates identity and content; ambiguous copies are preserved instead of guessed.
            let failure = L10n.text("阶段：%1$@；文件：%2$@。%3$@", stage,
                                    currentFile?.lastPathComponent ?? "—", RenameCopy.error(error))
            journal.failure = failure
            do {
                try restore(&journal, directory: directory, progress: progress)
                return .init(journal: journal, mappings: [:], error: failure, needsRecovery: false)
            } catch {
                journal.state = "recoveryRequired"
                journal.failure = failure + "\n" + L10n.text("恢复未完成：%1$@。原文件未被覆盖。", RenameCopy.error(error))
                saveFailure(&journal, directory: directory)
                let mappings = currentMappings(journal)
                return .init(journal: journal, mappings: mappings, error: journal.failure, needsRecovery: true)
            }
        }
    }

    static func locate(_ entry: RenameJournal.Entry) throws -> URL {
        let matches = [entry.original, entry.temporary, entry.target].filter { url in
            guard let version = try? RenameFileIdentity.read(url), entry.identity.sameFile(version) else { return false }
            return (try? digest(url)) == entry.hash
        }
        guard let match = Set(matches).first, Set(matches).count == 1 else { throw RenameError.stalePlan }
        return match
    }

    static func access(_ journal: RenameJournal) -> [URL] {
        journal.entries.compactMap { entry in
            guard let bookmark = entry.bookmark else { return nil }
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: bookmark,
                                     options: [.withSecurityScope, .withoutUI, .withoutMounting], relativeTo: nil,
                                     bookmarkDataIsStale: &stale), url.startAccessingSecurityScopedResource() else { return nil }
            return url
        }
    }

    static func currentMappings(_ journal: RenameJournal) -> [URL: URL] {
        let scopes = access(journal)
        defer { scopes.forEach { $0.stopAccessingSecurityScopedResource() } }
        var result: [URL: URL] = [:]
        for entry in journal.entries {
            if let current = try? locate(entry), current != entry.original { result[entry.original] = current }
        }
        return result
    }

    /// Restage every changed file before restoring originals, so swap and longer cycles can be undone safely.
    static func restore(_ journal: inout RenameJournal, directory: URL = storage,
                        progress: @escaping @Sendable (RenameProgress) -> Void = { _ in }) throws {
        guard journal.version == 1 else { throw RenameError.invalidPreset }
        let scopes = access(journal)
        defer { scopes.forEach { $0.stopAccessingSecurityScopedResource() } }
        var reporter = RenameProgressReporter(progress)
        reporter.update(.restoring, completed: 0, total: journal.entries.count)
        let located = try journal.entries.map { entry in (entry, try locate(entry)) }
        let moving = located.filter { $0.1 != $0.0.original }
        let movingPaths = Set(moving.map { $0.1.standardizedFileURL.path })
        for (entry, _) in moving {
            guard entry.original.deletingLastPathComponent() == entry.temporary.deletingLastPathComponent(),
                  entry.original.deletingLastPathComponent() == entry.target.deletingLastPathComponent() else { throw RenameError.invalidSource }
            if FileManager.default.fileExists(atPath: entry.original.path), !movingPaths.contains(entry.original.standardizedFileURL.path) {
                throw RenameError.occupied
            }
        }
        journal.state = "restoring"
        try write(journal, directory: directory)
        for (entry, current) in moving where current != entry.temporary {
            // Check again immediately before staging each file.
            guard entry.identity.sameFile(try RenameFileIdentity.read(current)), try digest(current) == entry.hash else { throw RenameError.stalePlan }
            try move(current, to: entry.temporary)
        }
        for (entry, _) in moving {
            guard entry.identity.sameFile(try RenameFileIdentity.read(entry.temporary)), try digest(entry.temporary) == entry.hash else { throw RenameError.stalePlan }
            try move(entry.temporary, to: entry.original)
        }
        for (index, entry) in journal.entries.enumerated() {
            guard entry.identity.sameFile(try RenameFileIdentity.read(entry.original)), try digest(entry.original) == entry.hash else { throw RenameError.stalePlan }
            reporter.update(.restoring, completed: index + 1, total: journal.entries.count)
        }
        journal.state = "restored"
        try write(journal, directory: directory)
    }
}
