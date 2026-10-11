import AppKit
import Exiftool
import Foundation
import Metadata
import Testing
@testable import ImageData

struct MetadataDirectApplyPerformanceTests {
    @Test func syntheticScale() throws {
        guard ProcessInfo.processInfo.environment["PHOTOTRAIL_DIRECT_APPLY_BENCH"] == "1" else { return }
        let folder = URL.temporaryDirectory.appendingPathComponent("PhotoTrail-direct-apply-bench")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        memset(bitmap.bitmapData!, 128, bitmap.bytesPerRow * 2)
        let jpeg = bitmap.representation(using: .jpeg, properties: [:])!
        let scenarios = ["single", "multi", "iptc"]
        for count in (ProcessInfo.processInfo.environment["PHOTOTRAIL_DIRECT_BENCH_COUNTS"]?.split(separator: ",").compactMap { Int($0) } ?? [1, 100, 530]) {
            for scenario in scenarios {
                var readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)] = []
                for index in 0..<count {
                    let url = folder.appendingPathComponent("sample-\(index).jpg")
                    try jpeg.write(to: url)
                    let snapshot = try MetadataInspectionSnapshot.read(Set(MetadataTag.allCases), from: url) { _, _ in
                        [.captureDate: .text("2024:01:15 10:20:30.123456+08:00")]
                    }
                    var image = ImageData(metadata: Metadata(source: .image(url)), name: url.lastPathComponent)
                    if scenario == "iptc" {
                        image.applyMetadataDraft(try MetadataCreatorEditPlan.prepare([(image, snapshot)],
                            tag: .iptcCity, action: .setText("Synthetic")).items[0])
                    }
                    readings.append((image, snapshot))
                }
                let operations = [MetadataOperation(tag: .captureDate, action: .shiftDate(seconds: 1))]
                    + (scenario == "single" ? [] : [MetadataOperation(tag: .titleDefault, action: .setText("Synthetic")),
                        MetadataOperation(tag: .rightsDefault, action: .setText("Synthetic"))])
                for iteration in 0..<(count == 530 ? 3 : 1) {
                    let start = Date()
                    let result = try MetadataWorkflowPreview.prepare(readings, operations: operations)
                    let calculation = Date().timeIntervalSince(start)
                    let checkStart = Date()
                    #expect(readings.allSatisfy { MetadataInspectionFileVersion.read($0.snapshot.url) == $0.snapshot.version })
                    let check = Date().timeIntervalSince(checkStart)
                    #expect(result.items.count == count)
                    print("BENCH count=\(count) scenario=\(scenario) iteration=\(iteration) calculate=\(calculation) recheck=\(check) steps=\(result.steps.count)")
                }
            }
        }
    }
}

extension MetadataDirectApplyPerformanceTests {
    @Test func syntheticSidecarScale() throws {
        guard ProcessInfo.processInfo.environment["PHOTOTRAIL_DIRECT_XMP_BENCH"] == "1" else { return }
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for count in [1, 100, 530] {
            let readings = try (0..<count).map { index in
                let imageURL = folder.appendingPathComponent("synthetic-\(index).jpg")
                let xmpURL = imageURL.deletingPathExtension().appendingPathExtension("xmp")
                try Data("synthetic paired placeholder".utf8).write(to: imageURL)
                try Data("""
                <x:xmpmeta xmlns:x="adobe:ns:meta/">
                <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
                <rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmp:CreateDate="2024-01-15T10:20:30+08:00"/>
                </rdf:RDF></x:xmpmeta>
                """.utf8).write(to: xmpURL)
                let snapshot = try MetadataInspectionSnapshot.read([.sidecarDate, .titleDefault, .rightsDefault], from: xmpURL) { _, _ in
                    [.sidecarDate: .text("2024:01:15 10:20:30+08:00")]
                }
                return (image: ImageData(metadata: Metadata(source: .xmp(imageURL)), name: imageURL.lastPathComponent), snapshot: snapshot)
            }
            for scenario in ["single", "multi"] {
                let operations = [MetadataOperation(tag: .sidecarDate, action: .shiftDate(seconds: 1))]
                    + (scenario == "single" ? [] : [MetadataOperation(tag: .titleDefault, action: .setText("Synthetic")),
                        MetadataOperation(tag: .rightsDefault, action: .setText("Synthetic"))])
                for iteration in 0..<(count == 530 ? 3 : 1) {
                    let start = Date()
                    let result = try MetadataWorkflowPreview.prepare(readings, operations: operations)
                    #expect(result.items.count == count)
                    print("XMPBENCH count=\(count) scenario=\(scenario) iteration=\(iteration) calculate=\(Date().timeIntervalSince(start))")
                }
            }
        }
    }
}
