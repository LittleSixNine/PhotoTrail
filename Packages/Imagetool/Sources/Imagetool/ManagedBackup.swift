import Darwin
import Foundation

/// A receipt is created only after a backup has been written. Unknown, replaced and
/// pre-existing files never become cleanup candidates merely by being in this folder.
public struct ManagedBackup: Codable, Equatable, Sendable {
    public let name: String
    public let bytes: Int
    public let created: Date
    private let id: UUID
    private let inode: UInt64
    private let modified: Int
    private let nanoseconds: Int
    private let changed: Int
    private let changedNanos: Int

    public static func directory(in folder: URL) -> URL {
        folder.appendingPathComponent("PhotoTrail Backups", isDirectory: true)
    }

    private static func directoryExists(_ url: URL) throws -> Bool {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            if errno == ENOENT { return false }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard info.st_mode & S_IFMT == S_IFDIR else { throw CocoaError(.fileReadInvalidFileName) }
        return true
    }

    private static func receipts(_ folder: URL, create: Bool) throws -> URL? {
        let managed = directory(in: folder)
        let receipts = managed.appendingPathComponent(".receipts-v1", isDirectory: true)
        for url in [managed, receipts] {
            if create, mkdir(url.path, 0o700) != 0, errno != EEXIST {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            guard try directoryExists(url) else { return nil }
        }
        return receipts
    }

    public static func write(in folder: URL, copy: (URL) throws -> URL) throws {
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        guard let receipts = try receipts(folder, create: true) else { throw CocoaError(.fileWriteUnknown) }
        let url = try copy(directory(in: folder))
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { throw CocoaError(.fileWriteUnknown) }
        let receipt = Self(name: url.lastPathComponent, bytes: Int(info.st_size), created: Date(), id: UUID(),
                           inode: UInt64(info.st_ino), modified: info.st_mtimespec.tv_sec, nanoseconds: info.st_mtimespec.tv_nsec,
                           changed: info.st_ctimespec.tv_sec, changedNanos: info.st_ctimespec.tv_nsec)
        try JSONEncoder().encode(receipt).write(to: receipts.appendingPathComponent(receipt.id.uuidString), options: .atomic)
    }

    private func matches(_ url: URL) -> Bool {
        var info = stat()
        return !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\0")
            && lstat(url.path, &info) == 0 && info.st_mode & S_IFMT == S_IFREG
            && UInt64(info.st_ino) == inode && info.st_size == bytes
            && info.st_mtimespec.tv_sec == modified && info.st_mtimespec.tv_nsec == nanoseconds
            && info.st_ctimespec.tv_sec == changed && info.st_ctimespec.tv_nsec == changedNanos
    }

    public static func list(in folder: URL) throws -> [Self] {
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        guard let receipts = try receipts(folder, create: false) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: receipts, includingPropertiesForKeys: [.isRegularFileKey])
        return try files.compactMap { url in
            try Task.checkCancellation()
            guard let id = UUID(uuidString: url.lastPathComponent),
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  let receipt = try? JSONDecoder().decode(Self.self, from: Data(contentsOf: url)),
                  receipt.id == id, receipt.matches(directory(in: folder).appendingPathComponent(receipt.name)) else { return nil }
            return receipt
        }
    }

    public func remove(from folder: URL) throws {
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        guard let receipts = try Self.receipts(folder, create: false) else { return }
        let marker = receipts.appendingPathComponent(id.uuidString)
        let url = Self.directory(in: folder).appendingPathComponent(name)
        guard try JSONDecoder().decode(Self.self, from: Data(contentsOf: marker)) == self, matches(url) else { return }
        guard unlink(url.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        try FileManager.default.removeItem(at: marker)
    }
}
