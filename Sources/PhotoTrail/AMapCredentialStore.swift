import CryptoKit
import Darwin
import Foundation

struct AMapCredentialStore: Sendable {
    enum Storage: Sendable { case local, keychain }

    let directory: URL
    var keychainExists: @Sendable () throws -> Bool = AMapCredentials.keychainExists
    var readKeychain: @Sendable (Bool) throws -> AMapCredentials? = AMapCredentials.loadKeychain
    var writeKeychain: @Sendable (AMapCredentials) throws -> Void = AMapCredentials.saveKeychain

    var credentialsURL: URL { directory.appendingPathComponent("amap-credentials.enc") }
    // shortcut: a local wrapping key permits prompt-free sharing; it does not isolate apps under the same user.
    var encryptionKeyURL: URL { directory.appendingPathComponent(".amap-storage-key") }
    private static let header = Data("PhotoTrail.AMap.v1\0".utf8)

    static func shared() throws -> Self {
        var entry = passwd()
        var result: UnsafeMutablePointer<passwd>?
        var buffer = [CChar](repeating: 0, count: 16_384)
        let home = buffer.withUnsafeMutableBufferPointer { pointer -> String? in
            guard getpwuid_r(getuid(), &entry, pointer.baseAddress, pointer.count, &result) == 0,
                  result != nil, let path = entry.pw_dir else { return nil }
            return String(cString: path)
        }
        guard let home else { throw CocoaError(.fileReadNoSuchFile) }
        return Self(directory: URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Library/Application Support/PhotoTrail", isDirectory: true))
    }

    func preferredStorage() throws -> Storage {
        if try localFileExists() { return .local }
        return try keychainExists() ? .keychain : .local
    }

    func load() throws -> AMapCredentials? {
        if try localFileExists() { return try withLock { try readLocal() } }
        return try readKeychain(false)
    }

    func save(_ credentials: AMapCredentials) throws {
        guard !credentials.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !credentials.securityJsCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CocoaError(.validationMissingMandatoryProperty)
        }
        if credentials.storage == .keychain {
            // Existing users keep their original backend; local migration is explicit and one-way here.
            guard try !localFileExists() else { throw CocoaError(.fileWriteFileExists) }
            try writeKeychain(credentials)
            return
        }
        try prepareDirectory()
        try withLock {
            // Validate before replacing anything; damaged files and missing keys remain recoverable.
            if try localFileExists() { _ = try readLocal() }
            let key: Data
            if try exists(encryptionKeyURL) {
                key = try readFile(encryptionKeyURL, limit: 32)
                guard key.count == 32 else { throw CocoaError(.fileReadCorruptFile) }
            } else {
                key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
                try writeFile(key, to: encryptionKeyURL)
            }
            let payload = try JSONEncoder().encode(credentials)
            guard payload.count <= 65_536 else { throw CocoaError(.fileWriteInapplicableStringEncoding) }
            let sealed = try AES.GCM.seal(payload, using: SymmetricKey(data: key), authenticating: Self.header)
            guard let combined = sealed.combined else { throw CocoaError(.fileWriteUnknown) }
            try writeFile(Self.header + combined, to: credentialsURL)
            let saved = try readLocal()
            guard saved.key == credentials.key, saved.securityJsCode == credentials.securityJsCode else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }
    }

    private func readLocal() throws -> AMapCredentials {
        let sealed = try readFile(credentialsURL, limit: 70_000)
        guard sealed.starts(with: Self.header) else { throw CocoaError(.fileReadCorruptFile) }
        let key = try readFile(encryptionKeyURL, limit: 32)
        guard key.count == 32 else { throw CocoaError(.fileReadCorruptFile) }
        let box = try AES.GCM.SealedBox(combined: sealed.dropFirst(Self.header.count))
        let payload = try AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: Self.header)
        let credentials = try JSONDecoder().decode(AMapCredentials.self, from: payload)
        guard !credentials.key.isEmpty, !credentials.securityJsCode.isEmpty else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return credentials
    }

    private func localFileExists() throws -> Bool {
        guard try exists(directory) else { return false }
        try validateDirectory()
        return try exists(credentialsURL)
    }

    private func exists(_ url: URL) throws -> Bool {
        var attributes = stat()
        if lstat(url.path, &attributes) == 0 { return true }
        if errno == ENOENT { return false }
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    private func validateDirectory() throws {
        var attributes = stat()
        guard lstat(directory.path, &attributes) == 0,
              attributes.st_mode & S_IFMT == S_IFDIR, attributes.st_uid == getuid() else {
            throw CocoaError(.fileReadNoPermission)
        }
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try validateDirectory()
        guard chmod(directory.path, 0o700) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private func withLock<T>(_ operation: () throws -> T) throws -> T {
        try validateDirectory()
        let lock = directory.appendingPathComponent(".amap-credentials.lock")
        let descriptor = open(lock.path, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0, attributes.st_mode & S_IFMT == S_IFREG,
              attributes.st_uid == getuid(), attributes.st_mode & 0o077 == 0 else {
            throw CocoaError(.fileReadNoPermission)
        }
        guard flock(descriptor, LOCK_EX) == 0 else { throw POSIXError(.EIO) }
        defer { flock(descriptor, LOCK_UN) }
        return try operation()
    }

    private func readFile(_ url: URL, limit: Int) throws -> Data {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0, attributes.st_mode & S_IFMT == S_IFREG,
              attributes.st_uid == getuid(), attributes.st_mode & 0o077 == 0,
              attributes.st_size > 0, attributes.st_size <= limit else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var data = Data(count: Int(attributes.st_size))
        try data.withUnsafeMutableBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.read(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw POSIXError(.EIO) }
                offset += count
            }
        }
        return data
    }

    private func writeFile(_ data: Data, to destination: URL) throws {
        if try exists(destination) { _ = try readFile(destination, limit: 70_000) }
        let temporary = directory.appendingPathComponent(".amap-\(UUID().uuidString).tmp")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor); unlink(temporary.path) }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw POSIXError(.EIO) }
                offset += count
            }
        }
        guard fsync(descriptor) == 0, rename(temporary.path, destination.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
