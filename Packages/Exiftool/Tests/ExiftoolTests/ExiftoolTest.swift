import Coords
import Metadata
import SwiftUI
import Testing

@testable import Exiftool

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

struct ExiftoolTests {

    // read the version of the embedded exiftool
    // verifies the tool is part of the bundle and can be
    // accessed by package code.

    @Test func getVersion() async throws {
        let version = try #require(try Exiftool.helper.version())
        print("Using Exiftool version: \(version)")
    }

    @Test func concurrentCommandsKeepOutputAndErrorsSeparate() async throws {
        let fixture = try #require(Bundle.module.url(forResource: "alldata", withExtension: "jpg"))
        let folder = try makeTestFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = try (0..<12).map { index in
            let url = folder.appendingPathComponent("并发-\(index).jpg")
            try FileManager.default.copyItem(at: fixture, to: url)
            return url
        }
        await withTaskGroup(of: Void.self) { group in
            for file in files {
                group.addTask {
                    do {
                        let data = try Exiftool.helper.run(["-j", "-FileName", file.path])
                        let values = try JSONSerialization.jsonObject(with: data) as? [[String: String]]
                        #expect(values?.first?["FileName"] == file.lastPathComponent)
                    } catch { Issue.record("Valid command failed: \(error)") }
                }
            }
            group.addTask {
                do {
                    _ = try Exiftool.helper.run(["-j", folder.appendingPathComponent("missing.jpg").path])
                    Issue.record("Missing file unexpectedly succeeded")
                } catch let Exiftool.ExiftoolError.runFailed(code) { #expect(code != 0) }
                catch { Issue.record("Wrong error: \(error)") }
            }
            group.addTask {
                do { #expect(try Exiftool.helper.run(["-listx", "-EXIF:all"]).count > 64 * 1024) }
                catch { Issue.record("Large output failed: \(error)") }
            }
        }
        #expect(try Exiftool.helper.version() != nil)
    }

    @Test func failedProcessLaunchDoesNotReplayWritesOrBlockFollowingCommands() async throws {
        let fixture = try #require(Bundle.module.url(forResource: "alldata", withExtension: "jpg"))
        let folder = try makeTestFolder(andCopy: fixture)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent(fixture.lastPathComponent)
        let bytes = try Data(contentsOf: file)
        var failing = Exiftool.helper
        failing.url = folder.appendingPathComponent("missing-executable")
        let unavailable = failing
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<12 {
                group.addTask {
                    do {
                        _ = try unavailable.run(["-overwrite_original", "-GPSLatitude=1", file.path])
                        Issue.record("Unavailable executable unexpectedly succeeded")
                    } catch { }
                }
            }
            group.addTask {
                do {
                    try await unavailable.update(image: file, from: Metadata(source: .image(file)), timeZone: nil)
                    Issue.record("Async write unexpectedly succeeded")
                } catch { }
            }
        }
        #expect(try Data(contentsOf: file) == bytes)
        #expect(try Exiftool.helper.version() != nil)
    }

    @Test func largeOutputDoesNotBlock() throws {
        let data = try Exiftool.helper.run(["-listx", "-EXIF:all"])
        #expect(data.count > 64 * 1_024)
    }

    // Check for writable and not writable file types where
    // writable is defined as can be read by core graphics
    // and updated by exiftool. There are file types that could
    // be written by exiftool but are flagged as not writable
    // because core graphics can't read file metadata.

    @Test func commonExtensionAliasesUseExistingKnownTypePolicy() {
        #expect(Exiftool.helper.fileTypeIsWritable(for: URL(fileURLWithPath: "/not-present/photo.JPG")))
        #expect(Exiftool.helper.fileTypeIsWritable(for: URL(fileURLWithPath: "/not-present/photo.TIF")))
    }

    @Test func checkNotWritableType() async throws {
        let url = try #require(
            Bundle.module.url(forResource: "nowrite",
                              withExtension: "typ")
        )
        #expect(!Exiftool.helper.fileTypeIsWritable(for: url))
    }

    @Test func checkWritableType() async throws {
        let url = try #require(
            Bundle.module.url(forResource: "262M1559",
                              withExtension: "DNG")
        )
        #expect(Exiftool.helper.fileTypeIsWritable(for: url))
    }

    // Copy a test image to the documents folder and create an
    // xmp sidecar file from the image

    @Test func createSidecar() async throws {
        // setup
        let testImage = try #require(
            Bundle.module.url(forResource: "262M1559",
                              withExtension: "DNG")
        )
        let testFolder = try makeTestFolder(andCopy: testImage)
        defer {
            try? FileManager.default.removeItem(at: testFolder)
        }

        // now attempt to create a sidecar file from the copied
        // image. Verify a sidecar file exists.

        let name = testImage.lastPathComponent
        let copy = testFolder.appending(component: name)
        try Exiftool.helper.makeSidecar(from: copy)
        let sidecar = copy.deletingPathExtension()
            .appendingPathExtension(Metadata.xmpExtension)
        #expect(FileManager.default.fileExists(atPath: sidecar.path))
    }

    // Verify data extracted from a created sidecar file.

    @Test func verifySidecar() async throws {
        // setup
        let testImage = try #require(
            Bundle.module.url(forResource: "IMG_5654",
                              withExtension: "HEIC")
        )
        let testFolder = try makeTestFolder(andCopy: testImage)
        defer {
            try? FileManager.default.removeItem(at: testFolder)
        }
        let name = testImage.lastPathComponent
        let copy = testFolder.appending(component: name)
        try Exiftool.helper.makeSidecar(from: copy)
        let sidecar = copy.deletingPathExtension()
            .appendingPathExtension(Metadata.xmpExtension)
        #expect(FileManager.default.fileExists(atPath: sidecar.path))

        // Extract needed data from the created sidecar file

        let metadata = Exiftool.helper.metadata(from: sidecar, primaryURL: copy)
        #expect(metadata.dateTimeCreated == "2025:12:03 16:25:49")
        #expect(metadata.location?.latitude == 37.51878611116667)
        #expect(metadata.location?.longitude == -122.34516111116666)
        #expect(metadata.elevation == 174.0)
        #expect(metadata.city == nil)
        #expect(metadata.state == nil)
        #expect(metadata.country == nil)
        #expect(metadata.countryCode == nil)
    }

    // Verify the data from the created sidecar is the same as
    // a known good sidecar file.

    @Test func verifySidecarSame() async throws {
        // setup
        let testImage = try #require(
            Bundle.module.url(forResource: "262M1559",
                              withExtension: "DNG")
        )
        let testFolder = try makeTestFolder(andCopy: testImage)
        defer {
            try? FileManager.default.removeItem(at: testFolder)
        }
        let name = testImage.lastPathComponent
        let copy = testFolder.appending(component: name)

        try Exiftool.helper.makeSidecar(from: copy)
        let sidecar = copy.deletingPathExtension()
            .appendingPathExtension(Metadata.xmpExtension)
        #expect(FileManager.default.fileExists(atPath: sidecar.path))

        // Extract needed data from the created sidecar file

        let newData = Exiftool.helper.metadata(from: sidecar, primaryURL: copy)

        // Extract the same data from an existing sidecar file

        let oldSidecar = try #require(
            Bundle.module.url(forResource: "262M1559",
                              withExtension: "xmp")
        )
        let oldData = Exiftool.helper.metadata(from: oldSidecar,
                                               primaryURL: testImage)

        #expect(newData == oldData)
    }
}

// tests that use and modify global state (user defaults) that must be
// serialized so one test doesn't clobber data used by another.

@Suite(.serialized)
struct ExiftoolSerializedTests {
    func makeTestData(_ metadata: inout Metadata) {
        metadata.dateTimeCreated = "2019:03:12 18:47:20"
        metadata.location = Coords(latitude: 33.123,
                                   longitude: -122.345)
        metadata.elevation = 125.5
        metadata.sublocation = "香坊区"
        metadata.city = "哈尔滨市"
        metadata.state = "黑龙江省"
        metadata.country = "United States"
        metadata.countryCode = "USA"
    }

    // Note: the following test can not use ImageData or Imagetool as
    // Exiftool is a dependency of those packages and using them will
    // cause Xcode to compile/link twice as it creates an Exiftool_Exiftool
    // target to break the dependency cycle. Grab existing image file
    // metadata using Exiftool even though that is not how we get it
    // in the main app. The tests are for updates, not reads, making this
    // an acceptable workaround

    @Test(.serialized,
        arguments: [
        (false, false),
        (false, true),
        (true, false),
        (true, true)
    ])
    func updateImage(ufm: Bool, ugt: Bool) async throws {
        @AppStorage(Exiftool.updateFileModificationTimesKey) var updateFileModificationTimes = false
        @AppStorage(Exiftool.updateGPSTimestampsKey) var updateGPSTimestamps = false

        // setup
        updateFileModificationTimes = ufm
        updateGPSTimestamps = ugt

        let testImage = try #require(
            Bundle.module.url(forResource: "262M1559",
                              withExtension: "DNG")
        )
        let testFolder = try makeTestFolder(andCopy: testImage)
        defer {
            try? FileManager.default.removeItem(at: testFolder)
        }
        let name = testImage.lastPathComponent
        let copy = testFolder.appending(component: name)
        #expect(FileManager.default.fileExists(atPath: copy.path))

        let beforeDate = try FileManager.default
                                        .attributesOfItem(atPath: copy.path)[
            FileAttributeKey.creationDate] as? Date

        // grab metadata from the image file
        var metadata = Exiftool.helper.metadata(from: nil, primaryURL: copy)
        makeTestData(&metadata)

        // run
        try await Exiftool.helper.update(image: copy, from: metadata,
                                         timeZone: TimeZone(identifier: "America/Los_Angeles"))

        // verify results
        let newdata = Exiftool.helper.metadata(from: nil, primaryURL: copy)
        #expect(newdata == metadata)

        // see if the file modification date was updated if requested
        let afterDate = try FileManager.default
                                       .attributesOfItem(atPath: copy.path)[
            FileAttributeKey.creationDate] as? Date
        if ufm {
            #expect(beforeDate != afterDate)
            let df = DateFormatter()
            df.dateFormat = "yyyy:MM:dd HH:mm:ss"
            let expectedDate = df.date(from: metadata.dateTimeCreated!)
            #expect(afterDate == expectedDate)
        } else {
            #expect(beforeDate == afterDate)
        }

        // see if the gps timestamp was updated when requested
        let timestamp = try await Exiftool.helper
                                          .getGPSTimestamp(for: copy)?
                                          .trimmingCharacters(in: .whitespacesAndNewlines)

        if ugt {
            #expect(timestamp == "2019:03:13 01:47:20Z")
        } else {
            #expect(timestamp == "2019:03:11 18:47:20Z")
        }
    }

    // roughly the same as above but for XMP file updates

    @Test(.serialized,
        arguments: [
        (false, false),
        (false, true),
        (true, false),
        (true, true)
    ])
    func updateXmp(ufm: Bool, ugt: Bool) async throws {
        @AppStorage(Exiftool.updateFileModificationTimesKey) var updateFileModificationTimes = false
        @AppStorage(Exiftool.updateGPSTimestampsKey) var updateGPSTimestamps = false

        enum TestError: Error {
            case testError
        }

        // setup
        updateFileModificationTimes = ufm
        updateGPSTimestamps = ugt

        let testImage = try #require(
            Bundle.module.url(forResource: "262M1559",
                              withExtension: "DNG")
        )
        let testFolder = try makeTestFolder(andCopy: testImage)
        defer {
            try? FileManager.default.removeItem(at: testFolder)
        }

        let name = testImage.lastPathComponent
        let copy = testFolder.appending(component: name)
        #expect(FileManager.default.fileExists(atPath: copy.path))

        // copy the xmp file, too
        let xmpImage = testImage.deletingPathExtension()
                                .appendingPathExtension(Metadata.xmpExtension)
        let xmpName = xmpImage.lastPathComponent
        let xmpCopy = testFolder.appending(component: xmpName)
        try FileManager.default.copyItem(at: xmpImage, to: xmpCopy)
        #expect(FileManager.default.fileExists(atPath: xmpCopy.path))

        let beforeDate = try FileManager.default
                                        .attributesOfItem(atPath: xmpCopy.path)[
            FileAttributeKey.creationDate] as? Date

        // grab metadata from the xmp file
        var metadata = Exiftool.helper.metadata(from: xmpCopy,
                                                primaryURL: copy)
        makeTestData(&metadata)

        // run
        try await Exiftool.helper.update(image: xmpCopy, from: metadata,
                                         timeZone: TimeZone(identifier: "America/Los_Angeles"))

        // verify results
        let newdata = Exiftool.helper.metadata(from: xmpCopy,
                                               primaryURL: copy)
        #expect(newdata == metadata)

        // see if the file modification date was updated if requested
        let afterDate = try FileManager.default
                                       .attributesOfItem(atPath: xmpCopy.path)[
            FileAttributeKey.creationDate] as? Date
        if ufm {
            #expect(beforeDate != afterDate)
            let df = DateFormatter()
            df.dateFormat = "yyyy:MM:dd HH:mm:ss"
            let expectedDate = df.date(from: metadata.dateTimeCreated!)
            #expect(afterDate == expectedDate)
        } else {
            #expect(beforeDate == afterDate)
        }

        // see if the gps timestamp was updated when requested
        let timestamp = try await Exiftool.helper
                                          .getGPSTimestamp(for: xmpCopy)?
                                          .trimmingCharacters(in: .whitespacesAndNewlines)

        if ugt {
            #expect(timestamp == "2019:03:13 01:47:20Z")
        } else {
            #expect(timestamp == "2019:03:11 18:47:20Z")
        }
    }
}
