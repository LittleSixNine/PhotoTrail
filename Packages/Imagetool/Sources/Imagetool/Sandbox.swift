import Darwin
import Exiftool
import Metadata
import SwiftUI

// Image URLs reference their files relative to the application sandbox.
// Exiftool must do its work inside the sandbox as it creates temporary files.
// macOS does not allow creation of files in folders unless folder access
// is explicitly allowed by the user.

public struct Sandbox {
    let orgURL: URL         // URL of image
    let imgDir: URL         // Application-owned temporary work directory
    let imgURL: URL         // URL of symlink in imgDir -> orgURL
    let xmpURL: URL         // URL of symline in imgDir -> orgURL xmp file
    private let workDirectory: WorkDirectory
    let xmpPresenter: XmpPresenter

    public init(for url: URL) throws {
        try Task.checkCancellation()
        guard url.isFileURL, !WorkDirectory.contains(url) else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        orgURL = url
        let sidecar = url.deletingPathExtension()
                         .appendingPathExtension(xmpExtension)

        let fileManager = FileManager.default
        let work = try WorkDirectory()
        var initialized = false
        defer { if !initialized { work.remove() } }
        workDirectory = work
        imgDir = work.url

        // create symbolic links to the image and xmp file in the folder
        imgURL = imgDir.appendingPathComponent(url.lastPathComponent)
        try fileManager.createSymbolicLink(at: imgURL,
                                           withDestinationURL: url)

        xmpURL = imgDir.appendingPathComponent(sidecar.lastPathComponent)
        try fileManager.createSymbolicLink(at: xmpURL,
                                           withDestinationURL: sidecar)

        // create an NSFilePresenter for the symbolic links
        xmpPresenter = XmpPresenter(for: imgURL, sidecar: xmpURL)
        initialized = true
    }

    public var sidecarExists: Bool {
        FileManager.default.fileExists(atPath: xmpURL.path)
    }

    enum BackupError: Error {
        case backupError(String)
    }
}

// Function to remove a sandbox's imgDir

extension Sandbox {
    public func removeSandboxFolder() {
        workDirectory.remove()
    }
}

// Create a sidecar file in the sandbox.

extension Sandbox {
    public func makeSidecarFile() throws {
        try Task.checkCancellation()
        guard !sidecarExists else {
            throw CocoaError(.fileWriteFileExists,
                             userInfo: [NSFilePathErrorKey: xmpURL.path])
        }
        NSFileCoordinator.addFilePresenter(xmpPresenter)
        defer {
            NSFileCoordinator.removeFilePresenter(xmpPresenter)
        }
        try Exiftool.helper.makeSidecar(from: imgURL)
    }
}

// image and sidecar backup functions

extension Sandbox {

    // copy an image file into the backup folder.  Because copyItems doesn't
    // follow symbolic links reference the original file instead of using
    // the link in the sandbox.

    public func makeImageBackup(_ backupFolder: URL) async throws {
        _ = try copyImageBackup(backupFolder)
    }

    private func copyImageBackup(_ backupFolder: URL) throws -> URL {
        try Task.checkCancellation()
        let fileName = orgURL.lastPathComponent
        return try writeBackup(named: fileName, in: backupFolder) { url in
            try FileManager.default.copyItem(at: orgURL, to: url)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw BackupError.backupError("Image \(fileName) copy failed!")
            }
        }
    }

    // Copy a sidecar file into the backup folder. The copy is done this
    // way as otherise a copy of of related item (sidecar file) to a
    // security scoped folder using FileManager's copyItem(at:to:) throws
    // an error.

    public func makeSidecarBackup(_ backupFolder: URL) async throws {
        _ = try copySidecarBackup(backupFolder)
    }

    private func copySidecarBackup(_ backupFolder: URL) throws -> URL {
        try Task.checkCancellation()
        let fileName = imgURL.deletingPathExtension()
                             .appendingPathExtension(xmpExtension)
                             .lastPathComponent
        NSFileCoordinator.addFilePresenter(xmpPresenter)
        defer { NSFileCoordinator.removeFilePresenter(xmpPresenter) }

        guard let data = xmpPresenter.readData() else {
            throw BackupError.backupError("Sidecar \(fileName) copy failed!")
        }
        return try writeBackup(named: fileName, in: backupFolder) { try data.write(to: $0, options: .withoutOverwriting) }
    }

    public func makeManagedBackup(in folder: URL, sidecar: Bool) async throws {
        try ManagedBackup.write(in: folder) { directory in
            if sidecar { return try copySidecarBackup(directory) }
            return try copyImageBackup(directory)
        }
    }

    // The exclusive copy/write chooses the winner if two same-named photos are backed up concurrently.
    private func writeBackup(named name: String, in folder: URL, write: (URL) throws -> Void) throws -> URL {
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        var suffix = 0
        while true {
            try Task.checkCancellation()
            var candidate = name
            if suffix > 0 {
                let dot = candidate.lastIndex(of: ".") ?? candidate.endIndex
                candidate.insert(contentsOf: "-\(suffix)", at: dot)
            }
            let url = folder.appendingPathComponent(candidate, isDirectory: false)
            // After a collision, skip occupied names cheaply (including dangling symlinks).
            // The exclusive write still decides the winner if another process races us.
            if suffix > 0 {
                var info = stat()
                if url.withUnsafeFileSystemRepresentation({ path in
                    path.map { lstat($0, &info) == 0 } ?? false
                }) {
                    suffix += 1
                    continue
                }
            }
            do { try write(url); return url }
            catch CocoaError.fileWriteFileExists { suffix += 1 }
        }
    }
}

// metadata and finder updates

extension Sandbox {

    public func updateMetadataTags(_ changes: [MetadataTag: MetadataTagChange],
                                   sidecar: Bool, mapMetadata: Metadata? = nil,
                                   timeZone: TimeZone? = nil) throws -> [MetadataTag: MetadataTagValue] {
        try Task.checkCancellation()
        NSFileCoordinator.addFilePresenter(xmpPresenter)
        defer { NSFileCoordinator.removeFilePresenter(xmpPresenter) }
        return try Exiftool.helper.update(image: sidecar ? xmpURL : imgURL,
                                          changes: changes, mapMetadata: mapMetadata, timeZone: timeZone)
    }

    public func metadataTags(_ tags: Set<MetadataTag>,
                             sidecar: Bool, mapMetadata: Metadata? = nil) throws -> [MetadataTag: MetadataTagValue] {
        NSFileCoordinator.addFilePresenter(xmpPresenter)
        defer { NSFileCoordinator.removeFilePresenter(xmpPresenter) }
        let target = sidecar ? xmpURL : imgURL
        let values = try Exiftool.helper.metadataTags(tags, from: target)
        if let mapMetadata { try Exiftool.helper.verifyMapMetadata(mapMetadata, in: target) }
        return values
    }

    // use exiftool to save metadata changes to the image or xmp file

    public func saveChanges(from metadata: Metadata,
                            timeZone: TimeZone?) async throws {
        try Task.checkCancellation()
        let url: URL
        if case .xmp = metadata.source {
            url = xmpURL
        } else {
            url = imgURL
        }
        NSFileCoordinator.addFilePresenter(xmpPresenter)
        defer { NSFileCoordinator.removeFilePresenter(xmpPresenter) }
        try await Exiftool.helper.update(image: url,
                                         from: metadata,
                                         timeZone: timeZone)
    }

    // add a Finder tag to the image file

    public func setTag(name: String) async throws {
        try Task.checkCancellation()
        var tagValues: [String]
        let tags = try orgURL.resourceValues(forKeys: [.tagNamesKey])
        if let tagNames = tags.tagNames {
            tagValues = tagNames
            if tagValues.contains(name) {
                return
            }
            tagValues.append(name)
        } else {
            tagValues = [name]
        }
        let url = orgURL as NSURL
        try url.setResourceValue(tagValues, forKey: .tagNamesKey)
    }
}
