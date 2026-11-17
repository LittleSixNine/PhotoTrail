import Darwin
import Foundation

// A lock belongs to the lifetime of the work, including copies of Sandbox.
final class WorkDirectory: Sendable {
    static let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        .appendingPathComponent("PhotoTrail-Imagetool-v1", isDirectory: true)
    private static let ownerName = ".phototrail-work-v1"
    let url: URL
    private let descriptor: Int32

    static func contains(_ url: URL) -> Bool {
        // Resolve the parent only: resolving the photo link itself would hide its work-directory origin.
        let path = url.deletingLastPathComponent().resolvingSymlinksInPath().pathComponents
        return path.starts(with: root.pathComponents)
    }

    init(root: URL = WorkDirectory.root) throws {
        let result = try Self.withRootLock(root) {
            try Self.reapUnlocked(in: root)
            let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
            guard mkdir(directory.path, 0o700) == 0 else { throw Self.posixError() }
            do {
                let descriptor = open(directory.appendingPathComponent(Self.ownerName).path,
                                      O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
                guard descriptor >= 0 else { throw Self.posixError() }
                guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
                    let error = Self.posixError()
                    close(descriptor)
                    throw error
                }
                return (directory, descriptor)
            } catch {
                try? FileManager.default.removeItem(at: directory)
                throw error
            }
        }
        url = result.0
        descriptor = result.1
    }

    deinit {
        remove()
        close(descriptor)
    }

    func remove() {
        do {
            try Self.withRootLock(url.deletingLastPathComponent()) {
                guard Self.isDirectory(url) else { return }
                let owner = url.appendingPathComponent(Self.ownerName)
                var held = stat()
                var current = stat()
                // Never remove a replacement directory or traverse a replacement ownership link.
                guard fstat(descriptor, &held) == 0, lstat(owner.path, &current) == 0,
                      current.st_dev == held.st_dev, current.st_ino == held.st_ino else { return }
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            Imagetool.logger.error("Work directory cleanup failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // Called on the next operation, so a killed process needs no exit handler to recover its work.
    private static func reapUnlocked(in root: URL) throws {
        for directory in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            guard UUID(uuidString: directory.lastPathComponent) != nil, isDirectory(directory) else { continue }
            let owner = directory.appendingPathComponent(ownerName)
            let descriptor = open(owner.path, O_RDWR | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
            if descriptor < 0 {
                // A crash between mkdir and owner creation can leave only an empty directory.
                if errno == ENOENT { _ = rmdir(directory.path) }
                continue
            }
            defer { close(descriptor) }
            var info = stat()
            guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
                  info.st_uid == geteuid(), info.st_nlink == 1, info.st_size == 0,
                  flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { continue }
            try FileManager.default.removeItem(at: directory)
        }
    }

    private static func withRootLock<T>(_ root: URL, body: () throws -> T) throws -> T {
        if mkdir(root.path, 0o700) != 0 && errno != EEXIST { throw posixError() }
        var rootInfo = stat()
        guard isDirectory(root), lstat(root.path, &rootInfo) == 0,
              rootInfo.st_mode & 0o077 == 0 else { throw CocoaError(.fileWriteNoPermission) }
        let descriptor = open(root.appendingPathComponent(".registry-lock-v1").path,
                              O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, 0o600)
        guard descriptor >= 0 else { throw posixError() }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == geteuid() else { throw CocoaError(.fileWriteNoPermission) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw posixError() }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR && info.st_uid == geteuid()
    }

    private static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
