import Foundation
import Exiftool
import Metadata
import Testing
@testable import Imagetool

struct SandboxTests {

    // return the url of a folder in the standard temporaryDirectory
    // used to hold files that will be modified by tests
    // if an image url is passed to the function copy the image
    // into the folder before returning

    func makeTestFolder(andCopy url: URL? = nil) throws -> URL {
        let testFolder =
            URL.temporaryDirectory.appending(components: UUID().uuidString)

        try FileManager.default.createDirectory(at: testFolder,
                                                withIntermediateDirectories: true)
        if let url {
            let name = url.lastPathComponent
            let copy = testFolder.appending(component: name)
            try FileManager.default.copyItem(at: url, to: copy)
        }
        return testFolder
    }

    @Test func initSandbox() async throws {
        let url = try #require(URL(string: "file:///a/path/to/a/file.img"))
        var dir: URL?

        if let sandbox = try? Sandbox(for: url) {
            defer {
                sandbox.removeSandboxFolder()
            }
            dir = sandbox.imgDir
        }
        #expect(dir != nil)
        #expect(!FileManager.default.fileExists(atPath: dir!.path))
    }

    @Test func sandboxContents() async throws {
        let url = try #require(
            Bundle.module.url(forResource: "262M1559",
                              withExtension: "DNG"))
        let xmp = try #require(
            Bundle.module.url(forResource: "262M1559",
                              withExtension: "xmp"))

        let sandbox = try Sandbox(for: url)
        defer {
            sandbox.removeSandboxFolder()
        }
        let contents =
            try FileManager.default.contentsOfDirectory(at: sandbox.imgDir,
                                                        includingPropertiesForKeys: [.isSymbolicLinkKey])
        for link in contents {
            let wrapper = try FileWrapper(url: link)
            #expect(wrapper.isSymbolicLink)
            let original = link.resolvingSymlinksInPath()
            if link.pathExtension == xmpExtension {
                #expect(xmp == original)
            } else {
                #expect(url == original)
            }
        }
    }

    @Test func makeSidecar() async throws {
        let url = try #require(
            Bundle.module.url(forResource: "alldata",
                              withExtension: "jpg"))
        let testFolder = try makeTestFolder(andCopy: url)
        defer {
            try? FileManager.default.removeItem(at: testFolder)
        }
        let name = url.lastPathComponent
        let testImage = testFolder.appending(component: name)
        let testXmp = testImage.deletingPathExtension()
                               .appendingPathExtension(xmpExtension)

        let sandbox = try Sandbox(for: testImage)
        defer {
            sandbox.removeSandboxFolder()
        }
        try sandbox.makeSidecarFile()
        let contents =
            try FileManager.default.contentsOfDirectory(at: sandbox.imgDir,
                                                        includingPropertiesForKeys: [.isSymbolicLinkKey])
        for link in contents {
            let wrapper = try FileWrapper(url: link)
            #expect(wrapper.isSymbolicLink)
            let original = link.resolvingSymlinksInPath()
            if link.pathExtension == xmpExtension {
                #expect(testXmp == original)
            } else {
                #expect(testImage == original)
            }
        }
    }

    @Test func makeSidecarDoesNotReplaceExistingFile() async throws {
        let image = try #require(
            Bundle.module.url(forResource: "262M1559", withExtension: "DNG"))
        let sidecar = try #require(
            Bundle.module.url(forResource: "262M1559", withExtension: "xmp"))
        let folder = try makeTestFolder(andCopy: image)
        defer { try? FileManager.default.removeItem(at: folder) }
        let imageCopy = folder.appending(component: image.lastPathComponent)
        let sidecarCopy = folder.appending(component: sidecar.lastPathComponent)
        try FileManager.default.copyItem(at: sidecar, to: sidecarCopy)
        let before = try Data(contentsOf: sidecarCopy)
        let sandbox = try Sandbox(for: imageCopy)
        defer { sandbox.removeSandboxFolder() }

        #expect(throws: CocoaError.self) {
            try sandbox.makeSidecarFile()
        }
        #expect(try Data(contentsOf: sidecarCopy) == before)
    }

    @Test func backupFile() async throws {
        // Copy test image to test folder
        let url = try #require(
            Bundle.module.url(forResource: "alldata",
                              withExtension: "jpg"))
        let testFolder = try makeTestFolder(andCopy: url)
        defer {
            try? FileManager.default.removeItem(at: testFolder)
        }

        // make a sandbox entry for the copied test image
        let name = url.lastPathComponent
        let testImage = testFolder.appending(component: name)
        let sandbox = try Sandbox(for: testImage)
        defer {
            sandbox.removeSandboxFolder()
        }

        // make a backup folder
        let backupFolder = testFolder.appending(component: "backup/")
        try FileManager.default.createDirectory(at: backupFolder,
                                                withIntermediateDirectories: true)

        // make a backup file twice to verify backup naming
        try await sandbox.makeImageBackup(backupFolder)
        try await sandbox.makeImageBackup(backupFolder)

        // verify the backup folder contains both copies
        let contents =
            try FileManager.default.contentsOfDirectory(at: backupFolder,
                                                        includingPropertiesForKeys: nil)
        #expect(contents.contains { $0.lastPathComponent == name })
        #expect(contents.count == 2)
    }

    @Test func backupTargetsStayExplicitWhenBothFilesExist() async throws {
        // Copy test image to test folder
        let url = try #require(
            Bundle.module.url(forResource: "262M1559",
                              withExtension: "DNG"))
        let testFolder = try makeTestFolder(andCopy: url)
        defer {
            try? FileManager.default.removeItem(at: testFolder)
        }

        // Copy the Sidecar file, too.
        let xmp = try #require(
            Bundle.module.url(forResource: "262M1559",
                              withExtension: "xmp"))
        let xmpName = xmp.lastPathComponent
        let xmpCopy = testFolder.appending(component: xmpName)
        try FileManager.default.copyItem(at: xmp, to: xmpCopy)

        // make a sandbox for the image and sidecar
        let name = url.lastPathComponent
        let testImage = testFolder.appending(component: name)
        let sandbox = try Sandbox(for: testImage)
        defer {
            sandbox.removeSandboxFolder()
        }

        // make a backup folder
        let backupFolder = testFolder.appending(component: "backup/")
        try FileManager.default.createDirectory(at: backupFolder,
                                                withIntermediateDirectories: true)
        // Back up each physical target twice to verify both target selection
        // and collision-safe naming.
        try await sandbox.makeImageBackup(backupFolder)
        try await sandbox.makeImageBackup(backupFolder)
        try await sandbox.makeSidecarBackup(backupFolder)
        try await sandbox.makeSidecarBackup(backupFolder)

        // Verify neither target is substituted merely because a sidecar exists.
        let contents =
            try FileManager.default.contentsOfDirectory(at: backupFolder,
                                                        includingPropertiesForKeys: nil)
        #expect(contents.contains { $0.lastPathComponent == name })
        #expect(contents.contains { $0.lastPathComponent == "262M1559-1.DNG" })
        #expect(contents.contains { $0.lastPathComponent == xmpName })
        #expect(contents.contains { $0.lastPathComponent == "262M1559-1.xmp" })
        #expect(contents.count == 4)
    }

    @Test func saveImage() async throws {
        // Copy test image to test folder
        let url = try #require(
            Bundle.module.url(forResource: "alldata",
                              withExtension: "jpg"))
        let testFolder = try makeTestFolder(andCopy: url)
        defer {
            try? FileManager.default.removeItem(at: testFolder)
        }

        // make a sandbox entry for the copied test image
        let name = url.lastPathComponent
        let testImage = testFolder.appending(component: name)
        let sandbox = try Sandbox(for: testImage)
        defer {
            sandbox.removeSandboxFolder()
        }

        // Create a metadata entry for the image
        var metadata = Metadata(source: .image(testImage))
        metadata.dateTimeCreated =  "2019:03:11 11:47:20"

        // update the image using the created metadata
        try await sandbox.saveChanges(from: metadata, timeZone: nil)

        // see if the changes took effect
        let updatedMetadata = Imagetool.metadata(from: testImage)
        #expect(metadata == updatedMetadata)
    }

    // same as above, but using a file with a sidecar to check
    // sidecar updates.

    @Test func saveXmp() async throws {
        // Copy test image to test folder
        let url = try #require(
            Bundle.module.url(forResource: "262M1559",
                              withExtension: "DNG"))
        let testFolder = try makeTestFolder(andCopy: url)
        defer {
            try? FileManager.default.removeItem(at: testFolder)
        }

        // Copy the Sidecar file, too.
        let xmp = try #require(
            Bundle.module.url(forResource: "262M1559",
                              withExtension: "xmp"))
        let xmpName = xmp.lastPathComponent
        let xmpCopy = testFolder.appending(component: xmpName)
        try FileManager.default.copyItem(at: xmp, to: xmpCopy)

        // make a sandbox for the image and sidecar
        let name = url.lastPathComponent
        let testImage = testFolder.appending(component: name)
        let sandbox = try Sandbox(for: testImage)
        defer {
            sandbox.removeSandboxFolder()
        }

        // Things of minor interest
        print("sandbox.imgURL \(sandbox.imgURL.path())")
        let exists = FileManager.default.fileExists(atPath: sandbox.imgURL.path)
        print(exists ? "imgURL exists" : "ImgURL does not exist")
        print("sandbox.xmpURL \(sandbox.xmpURL.path())")
        print(sandbox.sidecarExists ? "xmpURL exists" : "xmpURL does not exist")

        // Create a metadata entry for the update
        var metadata = Metadata(source: .xmp(testImage))
        metadata.dateTimeCreated =  "2019:03:11 11:47:20"

        // update
        try await sandbox.saveChanges(from: metadata, timeZone: nil)

        // use exiftool to grab xmp data as the Imagetool function will create
        // another sandbox. See if it matches.
        let updatedMetadata = Exiftool.helper.metadata(from: sandbox.xmpURL,
                                                       primaryURL: testImage)
        #expect(metadata == updatedMetadata)
    }

    @Test func tagFile() async throws {
        // Copy test image to test folder
        let url = try #require(
            Bundle.module.url(forResource: "262M1559",
                              withExtension: "DNG"))
        let testFolder = try makeTestFolder(andCopy: url)
        defer {
            try? FileManager.default.removeItem(at: testFolder)
        }

        // make a sandbox for the image and sidecar
        let name = url.lastPathComponent
        let testImage = testFolder.appending(component: name)
        let sandbox = try Sandbox(for: testImage)
        defer {
            sandbox.removeSandboxFolder()
        }

        // tag the file with "TestTag"
        let tagName = "TestTag"
        try await sandbox.setTag(name: tagName)

        // Verify the file is tagged
        let tags = try sandbox.orgURL.resourceValues(forKeys: [.tagNamesKey])
        if let name = tags.tagNames {
            #expect(name.contains(tagName))
        } else {
            Issue.record("Tag not set")
        }

        // Tag a second time with the same tag
        try await sandbox.setTag(name: tagName)

        // verify the tag was not duplicated
        let tags2 = try sandbox.orgURL.resourceValues(forKeys: [.tagNamesKey])
        if let names = tags2.tagNames {
            #expect(names.count { $0 == tagName } == 1)
        }
    }
}
