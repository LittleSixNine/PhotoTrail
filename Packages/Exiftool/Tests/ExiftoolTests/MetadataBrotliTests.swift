import Foundation
import Testing
@testable import Exiftool

struct MetadataBrotliTests {
    @Test func compressedJPEGXLMetadataRoundTripsWithoutChangingImageData() throws {
        let source = try #require(Bundle.module.url(forResource: "JXL2", withExtension: "jxl"))
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("compressed.jxl")
        let original = try Data(contentsOf: source)
        try original.write(to: url)
        let pixels = try Exiftool.helper.run(["-s3", "-ImageDataMD5", url.path])
        #expect(pixels.count > 20)
        let changes: [MetadataTag: MetadataTagChange] = [
            .creator: .set(.list(["作者 🌿"])), .exifArtist: .set(.text("Artist")),
            .rightsDefault: .set(.text("© 2026")), .captureDate: .set(.text("2024:01:02 03:04:05.123+08:00"))]
        let result = try Exiftool.helper.update(image: url, changes: changes)
        for (tag, change) in changes {
            if case .set(let value) = change { #expect(tag.matches(result[tag], value)) }
        }
        #expect(try Exiftool.helper.run(["-s3", "-ImageDataMD5", url.path]) == pixels)
        #expect(try Data(contentsOf: source) == original)
    }

    @Test func unreadableCompressedMetadataIsNeverTreatedAsMissing() throws {
        let fixture = try #require(Bundle.module.url(forResource: "JXL2", withExtension: "jxl"))
        var bytes = try Data(contentsOf: fixture)
        var index = 0
        while index + 8 <= bytes.count {
            let size = bytes[index..<(index + 4)].reduce(0) { ($0 << 8) | Int($1) }
            guard size >= 8, index + size <= bytes.count else { throw Exiftool.ExiftoolError.invalidTagOutput }
            if String(decoding: bytes[(index + 4)..<(index + 8)], as: UTF8.self) == "brob" {
                bytes.replaceSubrange((index + 12)..<(index + size), with: repeatElement(UInt8(0), count: size - 12))
            }
            index += size
        }
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("bad.jxl")
        try bytes.write(to: url)
        #expect(throws: (any Error).self) {
            _ = try Exiftool.helper.metadataTags([.creator], from: url)
        }
        #expect(!Exiftool.helper.metadata(from: nil, primaryURL: url).readable)
        #expect(try Data(contentsOf: url) == bytes)
    }

    @Test func systemCodecBoundsOutputAndRejectsInvalidInput() throws {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let codec = Exiftool.helper.url.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MetadataBrotli.bin")
        let input = folder.appendingPathComponent("input")
        let encoded = folder.appendingPathComponent("encoded")
        let decoded = folder.appendingPathComponent("decoded")
        let invalid = folder.appendingPathComponent("invalid")
        let data = Data(String(repeating: "元数据 🌿", count: 1000).utf8)
        try data.write(to: input)
        func run(_ mode: String, _ source: URL, _ target: URL, limit: String = "100000000") throws -> Int32 {
            let process = Process(); process.executableURL = codec
            process.arguments = [mode, source.path, target.path, limit]
            try process.run(); process.waitUntilExit(); return process.terminationStatus
        }
        #expect(try run("encode", input, encoded) == 0)
        #expect(try run("decode", encoded, decoded) == 0)
        #expect(try Data(contentsOf: decoded) == data)
        #expect(try run("decode", encoded, invalid, limit: "32") != 0)
        #expect(!FileManager.default.fileExists(atPath: invalid.path))
        #expect(try run("decode", input, invalid) != 0)
        #expect(try run("decode", encoded, invalid, limit: "100000001") != 0)
    }
}
