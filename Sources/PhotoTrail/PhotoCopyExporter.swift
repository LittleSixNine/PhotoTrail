import CryptoKit
import Exiftool
import Foundation
import ImageData
import Imagetool

enum PhotoCopyExporter {
    struct Item: Codable, Sendable {
        let source: String
        var output: String?
        var status: String
        var reason: String
    }

    struct Report: Codable, Sendable {
        let createdAt: Date
        let outputDirectory: String
        let written: Int
        let skipped: Int
        let failed: Int
        let results: [Item]
    }

    enum ExportError: LocalizedError {
        case outputInsideSource
        case noLocalFiles

        var errorDescription: String? {
            switch self {
            case .outputInsideSource: L10n.text("输出目录不能位于源照片目录内。")
            case .noLocalFiles: L10n.text("选中的照片没有可导出的本地文件。")
            }
        }
    }

    static func export(images: [ImageData], destination: URL,
                       timeZone: TimeZone) async throws -> Report {
        let fileManager = FileManager.default
        let sources = images.compactMap { sourceURL(for: $0) }
        guard !sources.isEmpty else { throw ExportError.noLocalFiles }
        let output = availableOutput(in: destination, fileManager: fileManager)
        guard !sources.contains(where: {
            isDescendant(output, of: $0.deletingLastPathComponent())
        }) else { throw ExportError.outputInsideSource }

        try fileManager.createDirectory(at: output, withIntermediateDirectories: false)
        let commonRoot = commonDirectory(for: sources)
        var results = [Item]()
        var written = 0
        var skipped = 0
        var failed = 0

        for image in images {
            guard let source = sourceURL(for: image) else {
                skipped += 1
                results.append(Item(source: image.name, status: "skipped",
                                    reason: L10n.text("仅支持本地照片文件。")))
                continue
            }
            guard image.metadata.location != nil, image.metadata.canDisplayAsWGS84 else {
                skipped += 1
                results.append(Item(source: source.path, status: "skipped",
                                    reason: L10n.text("照片缺少已确认的 WGS-84 定位。")))
                continue
            }
            let values = try? source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values?.isRegularFile == true, values?.isSymbolicLink != true else {
                skipped += 1
                results.append(Item(source: source.path, status: "skipped",
                                    reason: L10n.text("源文件不可用或为符号链接。")))
                continue
            }

            let relative = Array(source.standardizedFileURL.pathComponents
                .dropFirst(commonRoot.pathComponents.count))
            let target = relative.reduce(output) { $0.appendingPathComponent($1) }
            var item = Item(source: source.path, output: target.path,
                            status: "failed", reason: L10n.text("副本写入或回读验证失败。"))
            do {
                let originalHash = try digest(source)
                try fileManager.createDirectory(at: target.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
                guard !fileManager.fileExists(atPath: target.path) else {
                    throw CocoaError(.fileWriteFileExists)
                }
                try fileManager.copyItem(at: source, to: target)
                var metadata = image.metadata
                metadata.gpsMapDatum = "WGS-84"
                metadata.preserveGPSOnSave = false
                try await Exiftool.helper.update(image: target, from: metadata, timeZone: timeZone)
                let saved = Imagetool.metadata(from: target)
                guard let expected = metadata.location, let actual = saved.location,
                      abs(expected.latitude - actual.latitude) <= 0.000001,
                      abs(expected.longitude - actual.longitude) <= 0.000001,
                      try digest(source) == originalHash else {
                    throw CocoaError(.fileWriteUnknown)
                }
                item.status = "written"
                item.reason = L10n.text("已写入副本并回读验证；源文件哈希未改变。")
                written += 1
            } catch {
                try? fileManager.removeItem(at: target)
                item.output = nil
                failed += 1
            }
            results.append(item)
        }

        let report = Report(createdAt: .now, outputDirectory: output.path,
                            written: written, skipped: skipped, failed: failed, results: results)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let reportURL = output.appendingPathComponent("geotag-report.json")
        try encoder.encode(report).write(to: reportURL, options: .withoutOverwriting)
        return report
    }

    private static func sourceURL(for image: ImageData) -> URL? {
        switch image.metadata.source {
        case .image(let url), .xmp(let url): url.standardizedFileURL
        case .photos, .copy: nil
        }
    }

    private static func availableOutput(in destination: URL, fileManager: FileManager) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let base = "PhotoTrail Export \(formatter.string(from: .now))"
        var candidate = destination.appendingPathComponent(base, isDirectory: true)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = destination.appendingPathComponent("\(base)-\(suffix)", isDirectory: true)
            suffix += 1
        }
        return candidate
    }

    private static func commonDirectory(for urls: [URL]) -> URL {
        var components = urls[0].deletingLastPathComponent().standardizedFileURL.pathComponents
        for url in urls.dropFirst() {
            let other = url.deletingLastPathComponent().standardizedFileURL.pathComponents
            components = Array(zip(components, other).prefix { $0.0 == $0.1 }.map(\.0))
        }
        return URL(fileURLWithPath: NSString.path(withComponents: components), isDirectory: true)
    }

    private static func isDescendant(_ url: URL, of directory: URL) -> Bool {
        let child = url.standardizedFileURL.pathComponents
        let parent = directory.standardizedFileURL.pathComponents
        return child.count >= parent.count && Array(child.prefix(parent.count)) == parent
    }

    private static func digest(_ url: URL) throws -> SHA256.Digest {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize()
    }
}
