import Exiftool
import Foundation
import ImageData
import Testing
@testable import PhotoTrail

struct MetadataFormatImportTests {
    @Test func importsStaticImagesWithoutAdmittingDocumentsOrMovies() {
        for ext in MetadataImageFormat.readableExtensions {
            #expect(URL(fileURLWithPath: "/tmp/image." + ext).isSupportedPhotoImage)
        }
        for ext in ["mov", "mp4", "zip", "pdf", "docx", "exe"] {
            #expect(!URL(fileURLWithPath: "/tmp/file." + ext).isSupportedPhotoImage)
        }
    }

    @Test func sandboxCanEditCompressedJPEGXLWithOriginalBackup() async throws {
        let source = try #require(Bundle.main.url(forResource: "MetadataCompressed", withExtension: "jxl"))
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("sandbox.jxl")
        let original = try Data(contentsOf: source)
        try original.write(to: url)
        let image = ImageData(from: url)
        #expect(image.supportsMetadataEditing(.creator))
        let snapshot = try MetadataInspectionSnapshot.read([.creator], from: url)
        let plan = try MetadataCreatorEditPlan.prepare([(image, snapshot)], action: .set(["作者 🌿"]))
        let item = try #require(plan.items.first)
        let backup = folder.appendingPathComponent("backup")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        #expect(await item.save(backup: .folder(backup)) == .saved)
        #expect(try Exiftool.helper.metadataTags([.creator], from: url)[.creator] == .list(["作者 🌿"]))
        #expect(try Data(contentsOf: backup.appendingPathComponent(url.lastPathComponent)) == original)
    }
}
