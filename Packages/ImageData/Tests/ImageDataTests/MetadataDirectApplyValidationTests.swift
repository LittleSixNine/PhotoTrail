import AppKit
import Foundation
import Metadata
import Testing
@testable import Exiftool
@testable import ImageData

struct MetadataDirectApplyValidationTests {
    @Test func encodingReadReuseStillRejectsChangedOrUndeclaredSources() async throws {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("synthetic.jpg")
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        memset(bitmap.bitmapData!, 128, bitmap.bytesPerRow * 2)
        try bitmap.representation(using: .jpeg, properties: [:])!.write(to: url)
        _ = try Exiftool.helper.update(image: url, changes: [.exifModel: .set(.text("Synthetic Camera"))])
        let tags: Set<MetadataTag> = [.iptcCity, .iptcCountry, .titleDefault, .exifModel]
        func input() throws -> [(image: ImageData, snapshot: MetadataInspectionSnapshot)] {
            [(ImageData(metadata: Metadata(source: .image(url)), name: url.lastPathComponent),
              try MetadataInspectionSnapshot.read(tags, from: url))]
        }
        let validation = MetadataEditValidation()
        var readings = try input()
        let original = try Data(contentsOf: url)
        let first = try MetadataCreatorEditPlan.prepare(readings, tag: .iptcCity, action: .setText("Synthetic"), validation: validation)
        readings[0].image.applyMetadataDraft(first.items[0])
        try MetadataCreatorEditPlan.validate(readings, tag: .titleDefault, validation: validation)
        _ = try MetadataCreatorEditPlan.prepare(readings, tag: .iptcCountry, action: .setText("Synthetic"), validation: validation)
        #expect(validation.iptcVersions.count == 1)
        #expect(try Data(contentsOf: url) == original)
        _ = try Exiftool.helper.update(image: url, changes: [.iptcCity: .set(.text("UTF8"))])
        #expect(throws: MetadataCreatorPlanError.sourceChanged) {
            try MetadataCreatorEditPlan.validate(readings, tag: .titleDefault, validation: validation)
        }
        let utf8 = try MetadataWorkflowPreview.prepare(input(), operations: [
            MetadataOperation(tag: .iptcCountry, action: .setText("Synthetic")),
            MetadataOperation(tag: .titleDefault, action: .setText("Synthetic"))])
        #expect(utf8.items.count == 1)
        let beforeSave = try Data(contentsOf: url)
        let backup = folder.appendingPathComponent("backup")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        #expect(await utf8.items[0].save(backup: .folder(backup)) == .saved)
        #expect(try Data(contentsOf: backup.appendingPathComponent(url.lastPathComponent)) == beforeSave)
        let readback = try Exiftool.helper.metadataTags(tags, from: url)
        #expect(readback[.titleDefault] == .text("Synthetic"))
        #expect(readback[.iptcCountry] == .text("Synthetic"))
        #expect(readback[.exifModel] == .text("Synthetic Camera"))
        _ = try Exiftool.helper.run(["-overwrite_original", "-IPTC:CodedCharacterSet=", url.path])
        #expect(throws: Exiftool.ExiftoolError.self) {
            try MetadataCreatorEditPlan.prepare(input(), tag: .iptcCity, action: .setText("Synthetic"), validation: validation)
        }
        #expect(throws: Exiftool.ExiftoolError.self) {
            try MetadataWorkflowPreview.prepare(input(), operations: [MetadataOperation(tag: .iptcCity, action: .setText("Synthetic"))])
        }
        #expect(try MetadataWorkflowPreview.prepare(input(), operations: [MetadataOperation(tag: .titleDefault, action: .setText("Safe"))]).items.count == 1)
    }
}
