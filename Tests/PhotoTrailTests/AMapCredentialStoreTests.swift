import CryptoKit
import Foundation
import Security
import Testing
@testable import PhotoTrail

struct AMapCredentialStoreTests {
    private final class Legacy: @unchecked Sendable {
        private let lock = NSLock()
        private var value: AMapCredentials?
        private var reads = 0
        private var writes = 0
        var requiresInteraction = false

        init(_ value: AMapCredentials? = nil) { self.value = value }
        func exists() -> Bool { lock.withLock { value != nil } }
        func read(_ allowUI: Bool) throws -> AMapCredentials? {
            try lock.withLock {
                reads += 1
                if requiresInteraction && !allowUI { throw AMapCredentials.KeychainError(status: errSecInteractionNotAllowed) }
                return value
            }
        }
        func write(_ credentials: AMapCredentials) { lock.withLock { value = credentials; writes += 1 } }
        var counts: (reads: Int, writes: Int) { lock.withLock { (reads, writes) } }
    }

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AMapCredentials-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func store(_ directory: URL, legacy: Legacy = Legacy()) -> AMapCredentialStore {
        AMapCredentialStore(directory: directory, keychainExists: { legacy.exists() },
                            readKeychain: { try legacy.read($0) }, writeKeychain: { legacy.write($0) })
    }

    private let first = AMapCredentials(key: "synthetic-key-A", securityJsCode: "synthetic-code-A")
    private let second = AMapCredentials(key: "synthetic-key-B", securityJsCode: "synthetic-code-B")

    @Test func freshUsersDefaultToLocalWithoutCreatingKeychainItems() throws {
        let parent = try folder()
        defer { try? FileManager.default.removeItem(at: parent) }
        let legacy = Legacy()
        let shared = store(parent.appendingPathComponent("config"), legacy: legacy)
        #expect(try shared.preferredStorage() == .local)
        #expect(try shared.load() == nil)
        #expect(!FileManager.default.fileExists(atPath: shared.directory.path))
        try shared.save(first)
        #expect(try shared.load()?.key == first.key)
        #expect(legacy.counts.writes == 0)
    }

    @Test func independentStoresShareEncryptedCredentialsAndReloadUpdates() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstApp = store(directory)
        try firstApp.save(first)
        let testApp = store(directory)
        #expect(try testApp.load()?.securityJsCode == first.securityJsCode)
        try testApp.save(second)
        #expect(try firstApp.load()?.key == second.key)
        #expect(try firstApp.load()?.storage == .local)
        let data = try Data(contentsOf: firstApp.credentialsURL)
        #expect(data.range(of: Data(second.key.utf8)) == nil)
        #expect(data.range(of: Data(second.securityJsCode.utf8)) == nil)
        #expect(try Data(contentsOf: firstApp.encryptionKeyURL).count == 32)
        for url in [firstApp.credentialsURL, firstApp.encryptionKeyURL] {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    }

    @Test func existingKeychainUsersKeepTheirBackend() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        var old = first
        old.storage = .keychain
        let legacy = Legacy(old)
        let shared = store(directory, legacy: legacy)
        #expect(try shared.preferredStorage() == .keychain)
        #expect(try shared.load()?.storage == .keychain)
        var edited = second
        edited.storage = .keychain
        try shared.save(edited)
        #expect(legacy.counts.writes == 1)
        #expect(!FileManager.default.fileExists(atPath: shared.credentialsURL.path))
        #expect(!FileManager.default.fileExists(atPath: shared.encryptionKeyURL.path))
    }

    @Test func deniedLegacyAccessDoesNotBecomeANewLocalUser() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        var old = first
        old.storage = .keychain
        let legacy = Legacy(old)
        legacy.requiresInteraction = true
        let shared = store(directory, legacy: legacy)
        #expect(try shared.preferredStorage() == .keychain)
        #expect(throws: AMapCredentials.KeychainError.self) { try shared.load() }
        #expect(!FileManager.default.fileExists(atPath: shared.credentialsURL.path))
        #expect(legacy.counts.writes == 0)
    }

    @Test func explicitLocalMigrationPreservesLegacyAndStopsKeychainReads() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        var old = first
        old.storage = .keychain
        let legacy = Legacy(old)
        let shared = store(directory, legacy: legacy)
        try shared.save(first)
        legacy.requiresInteraction = true
        #expect(try shared.preferredStorage() == .local)
        #expect(try shared.load()?.key == first.key)
        #expect(legacy.exists())
        #expect(legacy.counts.reads == 0 && legacy.counts.writes == 0)
        #expect(throws: (any Error).self) { try shared.save(old) }
        #expect(try shared.load()?.key == first.key)
    }

    @Test func tamperedCiphertextCannotBeSilentlyOverwrittenOrReadFromKeychain() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacy = Legacy(first)
        let shared = store(directory, legacy: legacy)
        try shared.save(first)
        var bytes = try Data(contentsOf: shared.credentialsURL)
        bytes[bytes.count - 1] ^= 1
        try bytes.write(to: shared.credentialsURL)
        #expect(throws: (any Error).self) { try shared.load() }
        #expect(throws: (any Error).self) { try shared.save(second) }
        #expect(try Data(contentsOf: shared.credentialsURL) == bytes)
        #expect(legacy.counts.reads == 0 && legacy.counts.writes == 0)
    }

    @Test func missingEncryptionKeyPreservesExistingCiphertext() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let shared = store(directory)
        try shared.save(first)
        let bytes = try Data(contentsOf: shared.credentialsURL)
        try FileManager.default.removeItem(at: shared.encryptionKeyURL)
        #expect(throws: (any Error).self) { try shared.load() }
        #expect(throws: (any Error).self) { try shared.save(second) }
        #expect(try Data(contentsOf: shared.credentialsURL) == bytes)
        #expect(!FileManager.default.fileExists(atPath: shared.encryptionKeyURL.path))
    }

    @Test func symbolicLinkKeysAndDirectoriesAreRejected() throws {
        let parent = try folder()
        defer { try? FileManager.default.removeItem(at: parent) }
        let directory = parent.appendingPathComponent("actual")
        let shared = store(directory)
        try shared.save(first)
        let key = try Data(contentsOf: shared.encryptionKeyURL)
        let outside = parent.appendingPathComponent("outside-key")
        try key.write(to: outside)
        try FileManager.default.removeItem(at: shared.encryptionKeyURL)
        try FileManager.default.createSymbolicLink(at: shared.encryptionKeyURL, withDestinationURL: outside)
        #expect(throws: (any Error).self) { try shared.load() }
        #expect(throws: (any Error).self) { try shared.save(second) }
        #expect(try Data(contentsOf: outside) == key)
        let alias = parent.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: directory)
        #expect(throws: (any Error).self) { try store(alias).load() }
    }

    @Test func emptyCredentialsDoNotChangeExistingFiles() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let shared = store(directory)
        try shared.save(first)
        let original = try Data(contentsOf: shared.credentialsURL)
        #expect(throws: (any Error).self) {
            try shared.save(AMapCredentials(key: " ", securityJsCode: ""))
        }
        #expect(try Data(contentsOf: shared.credentialsURL) == original)
    }

    @Test func concurrentFirstSavesNeverMixKeysOrCredentialPairs() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let shared = store(directory)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<16 {
                group.addTask {
                    try shared.save(AMapCredentials(key: "key-\(index)", securityJsCode: "code-\(index)"))
                }
            }
            try await group.waitForAll()
        }
        let saved = try #require(try shared.load())
        #expect(saved.key.replacingOccurrences(of: "key-", with: "")
                == saved.securityJsCode.replacingOccurrences(of: "code-", with: ""))
        #expect(try Data(contentsOf: shared.encryptionKeyURL).count == 32)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).allSatisfy { !$0.hasSuffix(".tmp") })
    }

    @Test func permissiveKeyFilePermissionsAreRejectedWithoutChangingCredentials() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let shared = store(directory)
        try shared.save(first)
        let bytes = try Data(contentsOf: shared.credentialsURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: shared.encryptionKeyURL.path)
        #expect(throws: (any Error).self) { try shared.load() }
        #expect(throws: (any Error).self) { try shared.save(second) }
        #expect(try Data(contentsOf: shared.credentialsURL) == bytes)
    }

    @Test(arguments: [0, 16, 33]) func invalidKeyLengthsAreNotRegenerated(length: Int) throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let shared = store(directory)
        try shared.save(first)
        let bytes = try Data(contentsOf: shared.credentialsURL)
        let badKey = Data(repeating: 7, count: length)
        try badKey.write(to: shared.encryptionKeyURL)
        #expect(throws: (any Error).self) { try shared.save(second) }
        #expect(try Data(contentsOf: shared.credentialsURL) == bytes)
        #expect(try Data(contentsOf: shared.encryptionKeyURL) == badKey)
    }

    @Test func invalidDestinationPreservesItsOriginalContents() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("not-a-directory")
        let bytes = Data("preserve this file".utf8)
        try bytes.write(to: destination)
        #expect(throws: (any Error).self) { try store(destination).save(first) }
        #expect(try Data(contentsOf: destination) == bytes)
    }
}
