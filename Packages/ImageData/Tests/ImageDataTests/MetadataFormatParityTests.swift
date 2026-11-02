@testable import Exiftool
import Foundation
import CoreGraphics
import ImageIO
import Imagetool
import Metadata
import Testing
import UniformTypeIdentifiers
@testable import ImageData

struct MetadataFormatParityTests {
    @Test(arguments: ["png", "tiff", "gif", "bmp"])
    func generatedImagesRespectFieldFamiliesAndKeepPixels(ext: String) async throws {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("test." + ext)
        let context = try #require(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8,
            bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let type = try #require(UTType(filenameExtension: ext))
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        let original = try Data(contentsOf: url)
        let pixels = try decodedPixels(url)
        var image = ImageData(from: url)
        #expect(image.metadata.readable)
        if ext == "bmp" {
            image.metadata.dateTimeCreated = "2004:01:02 03:04:05"
            #expect(!image.hasLegacyChanges && !image.hasLegacyDateChanges)
        }
        let operations = [
            MetadataOperation(tag: .creator, action: .replaceAuthors(["作者 🌿"])),
            MetadataOperation(tag: .subject, action: .replaceKeywords(["旅行"])),
            MetadataOperation(tag: .exifArtist, action: .setText("Artist")),
            MetadataOperation(tag: .captureDate, action: .setText("2024:01:02 03:04:05.123+08:00")),
            MetadataOperation(tag: .dateOriginal, action: .setText("2020:01:02 03:04:05")),
            MetadataOperation(tag: .iptcByline, action: .replaceKeywords(["Author"]))]
        let tags = Set(operations.map(\.tag))
        let snapshot = try MetadataInspectionSnapshot.read(tags, from: url)
        let plan = try MetadataWorkflowPreview.prepare([(image, snapshot)], operations: operations)
        if ext == "bmp" {
            #expect(plan.items.isEmpty && plan.skipped.count == operations.count)
            #expect(try Data(contentsOf: url) == original)
            return
        }
        #expect(plan.skipped.count == (ext == "gif" ? 3 : 0))
        let item = try #require(plan.items.first)
        let backup = folder.appendingPathComponent("backup")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        var map = image.metadata
        map.location = .init(latitude: -33.75, longitude: -122.25)
        map.elevation = -4.25; map.gpsMapDatum = "WGS-84"; map.gpsProcessingMethod = "MANUAL"
        #expect(await item.save(backup: .folder(backup), mapMetadata: map) == .saved)
        let values = try Exiftool.helper.metadataTags(tags, from: url)
        #expect(values[.creator] == .list(["作者 🌿"]))
        #expect(values[.subject] == .list(["旅行"]))
        if ext != "gif" {
            #expect(values[.exifArtist] == .text("Artist"))
            #expect(values[.iptcByline] == .list(["Author"]))
        }
        try Exiftool.helper.verifyMapMetadata(map, in: url)
        let reloaded = Imagetool.metadata(from: url)
        #expect(abs(try #require(reloaded.location).latitude + 33.75) < 0.000001)
        #expect(abs(try #require(reloaded.location).longitude + 122.25) < 0.000001)
        #expect(try decodedPixels(url) == pixels)
        #expect(try Data(contentsOf: backup.appendingPathComponent(url.lastPathComponent)) == original)
        if ext != "gif" {
            let updated = ImageData(from: url)
            let clear = try MetadataCreatorEditPlan.prepare(
                [(updated, MetadataInspectionSnapshot.read([.captureDate], from: url))],
                tag: .captureDate, action: .remove)
            let clearItem = try #require(clear.items.first)
            #expect(await clearItem.save(backup: .disabled) == .saved)
            #expect(Imagetool.metadata(from: url).dateTimeCreated == nil)
            #expect(try Exiftool.helper.metadataTags([.dateOriginal], from: url)[.dateOriginal] != nil)
        }
    }

    private func decodedPixels(_ url: URL) throws -> Data {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return try #require(image.dataProvider?.data) as Data
    }
}

extension MetadataFormatParityTests {
    @Test func officialFixturesExerciseImportBackupReadbackAndRefusal() async throws {
        guard let path = ProcessInfo.processInfo.environment["PHOTOTRAIL_FORMAT_FIXTURES"] else { return }
        let sources = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: path), includingPropertiesForKeys: nil)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        #expect(sources.count >= 40)
        var saved = 0, readOnly = 0, refused = 0
        let refusedSamples: Set<String> = ["KyoceraRaw.raw", "Nikon.nef", "Sigma.x3f"]
        for source in sources {
            let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let original = try Data(contentsOf: source)
            let url = folder.appendingPathComponent(source.lastPathComponent)
            try original.write(to: url)
            let image = ImageData(from: url)
            #expect(image.metadata.readable, "Metadata unreadable: \(source.lastPathComponent)")
            let snapshot = try MetadataInspectionSnapshot.read([.creator], from: url)
            let plan = try MetadataWorkflowPreview.prepare([(image, snapshot)], operations: [
                MetadataOperation(tag: .creator, action: .replaceAuthors(["格式验证 🌿"]))])
            if plan.items.isEmpty {
                #expect(!MetadataImageFormat.writableExtensions.contains(url.pathExtension.lowercased()))
                #expect(plan.skipped.count == 1)
                #expect(try Data(contentsOf: url) == original)
                readOnly += 1
            } else {
                let item = try #require(plan.items.first)
                let backup = folder.appendingPathComponent("backup")
                try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
                var map = image.metadata
                let testMap = source.lastPathComponent == "PostScript.eps" || source.pathExtension.lowercased() == "gif"
                if testMap {
                    map.location = .init(latitude: -33.75, longitude: -122.25)
                    map.elevation = -4.25; map.gpsMapDatum = "WGS-84"; map.gpsProcessingMethod = "MANUAL"
                }
                let outcome = await item.save(backup: .folder(backup), mapMetadata: testMap ? map : nil)
                if testMap { try Exiftool.helper.verifyMapMetadata(map, in: url) }
                if refusedSamples.contains(source.lastPathComponent) {
                    #expect(outcome == .resultUnknown || outcome == .failed)
                    #expect(try Data(contentsOf: url) == original)
                    refused += 1
                } else {
                    #expect(outcome == .saved, "Write failed: \(source.lastPathComponent)")
                    #expect(try Exiftool.helper.metadataTags([.creator], from: url)[.creator] == .list(["格式验证 🌿"]))
                    if let output = ProcessInfo.processInfo.environment["PHOTOTRAIL_FORMAT_OUTPUT"] {
                        let target = URL(fileURLWithPath: output).appendingPathComponent(source.lastPathComponent)
                        try Data(contentsOf: url).write(to: target)
                    }
                    saved += 1
                }
                #expect(try Data(contentsOf: backup.appendingPathComponent(url.lastPathComponent)) == original)
            }
            #expect(try Data(contentsOf: source) == original)
        }
        print("Format fixtures: \(saved) saved, \(readOnly) read-only, \(refused) safely refused")
        #expect(refused == refusedSamples.count)
    }
}
