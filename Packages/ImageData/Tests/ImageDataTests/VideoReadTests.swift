import Exiftool
import Foundation
import Testing
@testable import ImageData

struct VideoReadTests {
    func fixture(_ name: String, _ ext: String) throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "VideoFixtures"))
    }

    @Test func movieIgnoresSameStemPhotoSidecar() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let video = folder.appendingPathComponent("shared.MOV")
        let photo = folder.appendingPathComponent("shared.jpg")
        let xmp = folder.appendingPathComponent("shared.xmp")
        let fm = FileManager.default
        try fm.copyItem(at: fixture("tagged", "mov"), to: video)
        try fm.copyItem(at: #require(Bundle.module.url(forResource: "alldata", withExtension: "jpg")), to: photo)
        try fm.copyItem(at: #require(Bundle.module.url(forResource: "262M1559", withExtension: "xmp")), to: xmp)
        let files = [video, photo, xmp]
        let before = try files.map { try Data(contentsOf: $0) }
        let item = ImageData(from: video)
        let info = try #require(item.videoInfo)
        #expect(item.metadata.readable && item.updatable && item.supportsMetadataEditing(.captureLocation) && !item.supportsMetadataEditing(.lens))
        #expect(item.metadataInspectionURL == video)
        #expect(item.name == "shared.MOV")
        #expect(info.duration == 1 && info.frameRate == 5)
        #expect(info.width == 160 && info.height == 90 && info.codec == "avc1")
        #expect(info.creationDate == "2026:11:23 08:00:00+08:00" && info.model == "TestCam")
        #expect(item.metadata.location?.latitude == 12.5 && item.metadata.location?.longitude == 34.25)
        #expect(ImageData(from: photo).metadataInspectionURL == xmp)
        #expect(try files.map { try Data(contentsOf: $0) } == before)
    }

    @Test func plainVideoAndAudioOnlyContainer() throws {
        let item = ImageData(from: try fixture("plain", "mp4"))
        let info = try #require(item.videoInfo)
        #expect(info.width == 160 && info.height == 90)
        #expect(info.containerDate == nil && info.creationDate == nil && info.location == nil)
        #expect(!item.supportsMetadataEditing(.captureDate))
        let audio = ImageData(from: try fixture("audio", "mp4"))
        #expect(audio.videoInfo == nil && !audio.metadata.readable && !audio.updatable)
    }

    @Test func photoWithVideoSuffixIsRejected() throws {
        let fake = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        try FileManager.default.copyItem(at: #require(Bundle.module.url(forResource: "alldata", withExtension: "jpg")), to: fake)
        defer { try? FileManager.default.removeItem(at: fake) }
        let item = ImageData(from: fake)
        #expect(item.videoInfo == nil && !item.metadata.readable && !item.updatable)
    }
}

extension VideoReadTests {
    @Test func mixedLocationsAndLensUsePerRuleTargets() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let backup = folder.appendingPathComponent("backups")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)] = []
        let tags: Set<MetadataTag> = [.captureLocation, .lens]
        for index in 0..<10 {
            let source = try index < 8 ? #require(Bundle.module.url(forResource: "alldata", withExtension: "jpg"))
                : fixture(index == 8 ? "tagged" : "plain", index == 8 ? "mov" : "mp4")
            let url = folder.appendingPathComponent("\(index)." + source.pathExtension)
            try FileManager.default.copyItem(at: source, to: url)
            readings.append((ImageData(from: url), try MetadataInspectionSnapshot.read(tags, from: url)))
        }
        let target = "-12.375 34.54321"
        let ops = [MetadataOperation(tag: .captureLocation, action: .setText(target)),
                   MetadataOperation(tag: .lens, action: .setText("Test lens"))]
        let preview = try MetadataWorkflowPreview.prepare(readings, operations: ops)
        #expect(preview.items.count == 10 && preview.skipDetails.count == 2)
        for (reading, item) in zip(readings, preview.items) {
            let original = try Data(contentsOf: item.target)
            var draft = reading.image
            draft.applyMetadataDraft(item)
            #expect(draft.metadata.location?.latitude == -12.375 && !draft.hasLegacyChanges)
            #expect(item.changes.count == (draft.isLocalMovie ? 1 : 2))
            #expect(await item.save(backup: .folder(backup)) == .saved)
            #expect(try Data(contentsOf: backup.appendingPathComponent(item.target.lastPathComponent)) == original)
            let reopened = ImageData(from: item.target)
            #expect(abs((reopened.metadata.location?.longitude ?? 0) - 34.54321) < 0.000002)
            let values = try Exiftool.helper.metadataTags(tags, from: item.target)
            #expect(values[.lens] == (draft.isLocalMovie ? nil : .text("Test lens")))
        }
    }

    @Test func videoDraftRejectsChangedSource() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        try FileManager.default.copyItem(at: fixture("plain", "mp4"), to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let image = ImageData(from: file)
        let snapshot = try MetadataInspectionSnapshot.read([.captureLocation], from: file)
        let plan = try MetadataWorkflowPreview.prepare([(image, snapshot)], operations: [
            MetadataOperation(tag: .captureLocation, action: .setText("1, 2"))])
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: file.path)
        let item = try #require(plan.items.first)
        #expect(await item.save(backup: .disabled) == .staleSource)
        #expect(ImageData(from: file).metadata.location == nil)
    }
}

extension VideoReadTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PHOTOTRAIL_TIMED_GPS_FIXTURE"] != nil))
    func deviceMovieKeepsTimedLocationsOnSave() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["PHOTOTRAIL_TIMED_GPS_FIXTURE"])
        let source = URL(fileURLWithPath: path)
        let file = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + source.pathExtension)
        try FileManager.default.copyItem(at: source, to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let points = try Exiftool.helper.timedVideoLocations(from: file)
        #expect(points.count > 1)
        let image = ImageData(from: file)
        let snapshot = try MetadataInspectionSnapshot.read([.captureLocation], from: file)
        let result = try MetadataWorkflowPreview.prepare([(image, snapshot)], operations: [
            MetadataOperation(tag: .captureLocation, action: .setText("12.5, 34.25"))])
        let item = try #require(result.items.first)
        #expect(await item.save(backup: .disabled) == .saved)
        let after = try Exiftool.helper.timedVideoLocations(from: file)
        #expect(points.map(\.seconds) == after.map(\.seconds))
        #expect(points.map(\.location) == after.map(\.location))
        #expect(points.map(\.gpsDate) == after.map(\.gpsDate))
        #expect(ImageData(from: file).metadata.location?.longitude == 34.25)
        try keepVerificationCopy(file, named: source.lastPathComponent)
    }
}

extension VideoReadTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PHOTOTRAIL_LIVE_MOV_FIXTURE"] != nil))
    func companionMovieKeepsItsIdentifierOnSave() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["PHOTOTRAIL_LIVE_MOV_FIXTURE"])
        let file = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let tag = "Keys:ContentIdentifier"
        let identifier = try #require(Exiftool.helper.inspectionTags(from: file)[tag])
        let image = ImageData(from: file)
        #expect(image.videoInfo?.hasContentIdentifier == true)
        let snapshot = try MetadataInspectionSnapshot.read([.captureLocation], from: file)
        let preview = try MetadataWorkflowPreview.prepare([(image, snapshot)], operations: [
            .init(tag: .captureLocation, action: .setText("-10, -34"))])
        let item = try #require(preview.items.first)
        #expect(await item.save(backup: .disabled) == .saved)
        #expect(try Exiftool.helper.inspectionTags(from: file)[tag] == identifier)
        #expect(ImageData(from: file).metadata.location?.longitude == -34)
        try keepVerificationCopy(file, named: URL(fileURLWithPath: path).lastPathComponent)
    }

    private func keepVerificationCopy(_ file: URL, named name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["PHOTOTRAIL_VIDEO_PROOF_DIRECTORY"] else { return }
        try FileManager.default.copyItem(at: file, to: URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent(name))
    }

    @Test func settingSidecarLocationPreservesSameStemMovieAndImage() throws {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let photo = folder.appendingPathComponent("same.jpg")
        let video = folder.appendingPathComponent("same.mov")
        let sidecar = folder.appendingPathComponent("same.xmp")
        try FileManager.default.copyItem(at: #require(Bundle.module.url(forResource: "alldata", withExtension: "jpg")), to: photo)
        try FileManager.default.copyItem(at: fixture("tagged", "mov"), to: video)
        try FileManager.default.copyItem(at: #require(Bundle.module.url(forResource: "262M1559", withExtension: "xmp")), to: sidecar)
        let original = try [photo, video].map { try Data(contentsOf: $0) }
        #expect(ImageData(from: photo).metadataInspectionURL == sidecar)
        let values = try Exiftool.helper.update(image: sidecar, changes: [.captureLocation: .set(.text("-12.25, -54.5"))])
        #expect(MetadataTag.captureLocation.matches(values[.captureLocation], .text("-12.25 -54.5")))
        let cleared = try Exiftool.helper.update(image: sidecar, changes: [.captureLocation: .remove])
        #expect(cleared[.captureLocation] == nil)
        #expect(try [photo, video].map { try Data(contentsOf: $0) } == original)
    }
}
