import Darwin
import Foundation
import Metadata
import Testing
@testable import Imagetool

struct WorkDirectoryTests {
    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        return folder
    }

    @Test func activeWorkAndCopiesSurviveOtherOperations() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let root = folder.appendingPathComponent("work")
        let first = try WorkDirectory(root: root)
        let second = try WorkDirectory(root: root)
        #expect(FileManager.default.fileExists(atPath: first.url.path))
        second.remove()
        second.remove()
        #expect(FileManager.default.fileExists(atPath: first.url.path))
        #expect(!FileManager.default.fileExists(atPath: second.url.path))
        first.remove()
    }

    @Test func reapsOnlyOwnedUnlockedDirectoriesWithoutFollowingLinks() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let root = folder.appendingPathComponent("work")
        let active = try WorkDirectory(root: root)
        let original = folder.appendingPathComponent("original")
        try Data("untouched".utf8).write(to: original)
        let stale = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: false)
        try Data().write(to: stale.appendingPathComponent(".phototrail-work-v1"))
        try FileManager.default.createSymbolicLink(at: stale.appendingPathComponent("photo.jpg"),
                                                   withDestinationURL: original)
        let foreign = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: foreign, withIntermediateDirectories: false)
        try Data("keep".utf8).write(to: foreign.appendingPathComponent("unknown"))
        let directoryLink = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createSymbolicLink(at: directoryLink, withDestinationURL: folder)
        let ownerLink = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: ownerLink, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: ownerLink.appendingPathComponent(".phototrail-work-v1"),
                                                   withDestinationURL: original)
        let next = try WorkDirectory(root: root)
        defer { next.remove(); active.remove() }
        #expect(!FileManager.default.fileExists(atPath: stale.path))
        #expect(FileManager.default.fileExists(atPath: active.url.path))
        #expect(FileManager.default.fileExists(atPath: foreign.path))
        #expect(FileManager.default.fileExists(atPath: directoryLink.path))
        #expect(FileManager.default.fileExists(atPath: ownerLink.path))
        #expect(try Data(contentsOf: original) == Data("untouched".utf8))
    }

    @Test func rejectsLinkedRoot() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let linked = folder.appendingPathComponent("linked")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: folder)
        #expect(throws: CocoaError.self) { try WorkDirectory(root: linked) }
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent(".registry-lock-v1").path))
    }

    @Test func initializationFailureRemovesPartialLinks() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = folder.appendingPathComponent("collision.xmp")
        try Data("original".utf8).write(to: image)
        // Both generated link names collide, after mkdir and the first link have succeeded.
        #expect(throws: CocoaError.self) { try Sandbox(for: image) }
        let directories = try FileManager.default.contentsOfDirectory(at: WorkDirectory.root,
                                                                      includingPropertiesForKeys: nil)
        for directory in directories where UUID(uuidString: directory.lastPathComponent) != nil {
            let link = directory.appendingPathComponent(image.lastPathComponent)
            #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != image.path)
        }
        #expect(try Data(contentsOf: image) == Data("original".utf8))
    }

    @Test func rejectsWorkLinksAndKeepsOriginalMetadataIdentity() throws {
        let image = try #require(Bundle.module.url(forResource: "262M1559", withExtension: "DNG"))
        let sidecar = image.deletingPathExtension().appendingPathExtension("xmp")
        let sandbox = try Sandbox(for: image)
        let copy = sandbox
        defer { sandbox.removeSandboxFolder() }
        #expect(!sandbox.imgDir.pathComponents.starts(with: URL.documentsDirectory.pathComponents))
        #expect(throws: CocoaError.self) { try Sandbox(for: sandbox.imgURL) }
        #expect(!Imagetool.metadata(from: sandbox.imgURL).readable)
        let metadata = Imagetool.metadata(from: image, xmp: sidecar)
        #expect(metadata.source == .xmp(image))
        #expect(FileManager.default.fileExists(atPath: copy.imgURL.path))
    }

    @Test func failureAndCancellationReleaseWorkAndProtectOriginal() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = folder.appendingPathComponent("invalid.jpg")
        let bytes = Data("not an image".utf8)
        try bytes.write(to: image)
        var workURL: URL?
        do {
            let sandbox = try Sandbox(for: image)
            workURL = sandbox.imgDir
            defer { sandbox.removeSandboxFolder() }
            #expect(throws: (any Error).self) {
                try sandbox.updateMetadataTags([.creator: .set(.text("test"))], sidecar: false)
            }
        }
        #expect(!FileManager.default.fileExists(atPath: try #require(workURL).path))
        let task = Task {
            let sandbox = try Sandbox(for: image)
            defer { sandbox.removeSandboxFolder() }
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                try sandbox.makeSidecarFile()
                Issue.record("Cancelled work must not create a sidecar")
            } catch is CancellationError { }
            do {
                try await sandbox.setTag(name: "cancelled")
                Issue.record("Cancelled work must not write Finder tags")
            } catch is CancellationError { }
            return sandbox.imgDir
        }
        let cancelledDirectory = try await task.value
        #expect(!FileManager.default.fileExists(atPath: cancelledDirectory.path))
        let sidecar = image.deletingPathExtension().appendingPathExtension("xmp")
        #expect(!FileManager.default.fileExists(atPath: sidecar.path))
        #expect(try Data(contentsOf: image) == bytes)
    }

    @Test func lastOwnerAutomaticallyCleansDirectory() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var work: WorkDirectory? = try WorkDirectory(root: folder.appendingPathComponent("work"))
        let directory = try #require(work).url
        work = nil
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
}
