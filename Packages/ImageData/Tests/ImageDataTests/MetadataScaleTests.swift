import Exiftool
import Foundation
import Metadata
import Testing
@testable import ImageData

struct MetadataScaleTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PHOTOTRAIL_SCALE_TESTS"] == "1"))
    func thousandSidecarsHaveVerifiedBackupsAndBoundedState() async throws {
        let count = 1_000
        let fixture = try #require(Bundle.module.url(forResource: "alldata", withExtension: "jpg"))
        let sidecar = try #require(Bundle.module.url(forResource: "262M1559", withExtension: "xmp"))
        let imageBytes = try Data(contentsOf: fixture), sidecarBytes = try Data(contentsOf: sidecar)
        let folder = URL.temporaryDirectory.appending(component: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let backup = folder.appending(component: "backup", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        var readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)] = []
        let start = Date()
        for index in 0..<count {
            let image = folder.appending(component: "sample-\(index).jpg"), xmp = folder.appending(component: "sample-\(index).xmp")
            try FileManager.default.copyItem(at: fixture, to: image)
            try FileManager.default.copyItem(at: sidecar, to: xmp)
            readings.append((ImageData(metadata: Metadata(source: .xmp(image)), name: image.lastPathComponent),
                             try MetadataInspectionSnapshot.read(Set(MetadataTag.allCases), from: xmp)))
            if (index + 1).isMultiple(of: 100) { print("SCALE read \(index + 1)/\(count)") }
        }
        let readEnd = Date()
        let operations = [MetadataOperation(tag: .titleDefault, action: .setText("千张验证")),
                          MetadataOperation(tag: .descriptionDefault, action: .setText("说明，换行\n第二行")),
                          MetadataOperation(tag: .creator, action: .replaceAuthors(["PhotoTrail Test"])),
                          MetadataOperation(tag: .rightsDefault, action: .setText("© Test")),
                          MetadataOperation(tag: .subject, action: .appendKeywords(["Scale", "Scale"]))]
        let preview = try MetadataWorkflowPreview.prepare(readings, operations: operations)
        #expect(preview.items.count == count)
        let planEnd = Date()
        for (index, item) in preview.items.enumerated() {
            #expect(await item.save(backup: .folder(backup)) == .saved)
            #expect(try Data(contentsOf: item.imageURL) == imageBytes)
            #expect(try Data(contentsOf: backup.appending(component: item.target.lastPathComponent)) == sidecarBytes)
            if (index + 1).isMultiple(of: 100) { print("SCALE saved \(index + 1)/\(count)") }
        }
        let end = Date()
        print("SCALE metrics: files=\(count), read_seconds=\(readEnd.timeIntervalSince(start)), " +
              "plan_seconds=\(planEnd.timeIntervalSince(readEnd)), save_verify_seconds=\(end.timeIntervalSince(planEnd))")
        #expect(try Data(contentsOf: fixture) == imageBytes)
        #expect(try Data(contentsOf: sidecar) == sidecarBytes)
    }
}
