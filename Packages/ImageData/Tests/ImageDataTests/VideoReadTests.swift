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
        #expect(item.metadata.readable && !item.updatable && !item.supportsMetadataEditing)
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
        #expect(!item.updatable)
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
