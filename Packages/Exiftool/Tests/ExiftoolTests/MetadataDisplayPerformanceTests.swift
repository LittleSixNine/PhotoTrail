import Foundation
import Testing
@testable import Exiftool

struct MetadataDisplayPerformanceTests {
    @Test func synthetic530DisplayResolution() throws {
        guard let path = ProcessInfo.processInfo.environment["PHOTOTRAIL_DISPLAY_BENCH_PATH"] else { return }
        let url = URL(fileURLWithPath: path)
        let original = try Data(contentsOf: url)
        let values = try Exiftool.helper.inspectionTags(from: url)
        let tags = MetadataDisplaySection.standard.flatMap(\.tags)
        for iteration in 0..<3 {
            var present = 0
            let start = Date()
            for _ in 0..<530 {
                for tag in tags {
                    if MetadataDisplaySection.value(for: tag, in: values) != nil { present += 1 }
                    _ = MetadataDisplaySection.sourceKeys(for: tag, in: values)
                }
            }
            print("DISPLAY count=530 keys=\(values.count) fields=\(tags.count) iteration=\(iteration) seconds=\(Date().timeIntervalSince(start)) present=\(present)")
            #expect(present > 0)
        }
        #expect(try Data(contentsOf: url) == original)
    }
}
