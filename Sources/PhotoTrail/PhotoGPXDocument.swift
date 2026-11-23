import Foundation
import ImageData
import SwiftUI
import UniformTypeIdentifiers

struct PhotoGPXDocument: FileDocument {
    static let contentType = UTType(filenameExtension: "gpx") ?? .xml
    static var readableContentTypes: [UTType] { [contentType] }

    let data: Data
    let exportedCount: Int
    let skippedCount: Int
    let timeRange: String
    let startDate: Date?
    let endDate: Date?

    init(images: [ImageData], timeZone: TimeZone, segmentGap: TimeInterval = 300) {
        let points = images.compactMap { image -> Point? in
            guard let coordinate = image.metadata.location,
                  image.metadata.canDisplayAsWGS84,
                  let date = image.metadata.parsedDate(timeZone: timeZone) else { return nil }
            return Point(date: date, latitude: coordinate.latitude, longitude: coordinate.longitude,
                         elevation: image.metadata.elevation, name: image.name)
        }.sorted { $0.date < $1.date }

        exportedCount = points.count
        skippedCount = images.count - points.count
        let firstDate = points.first?.date
        let lastDate = points.last?.date
        startDate = firstDate
        endDate = lastDate
        let rangeFormatter = DateFormatter()
        rangeFormatter.locale = L10n.locale
        rangeFormatter.setLocalizedDateFormatFromTemplate("yyyyMMddHHmmss")
        rangeFormatter.timeZone = timeZone
        if let firstDate, let lastDate {
            timeRange = "\(rangeFormatter.string(from: firstDate)) – \(rangeFormatter.string(from: lastDate))"
        } else {
            timeRange = L10n.text("无有效时间")
        }
        data = Data(Self.xml(points: points, segmentGap: segmentGap).utf8)
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        exportedCount = 0
        skippedCount = 0
        timeRange = L10n.text("无有效时间")
        startDate = nil
        endDate = nil
    }

    init(data: Data) {
        self.data = data
        exportedCount = 0
        skippedCount = 0
        timeRange = L10n.text("无有效时间")
        startDate = nil
        endDate = nil
    }

    func suggestedFilename(timeZone: TimeZone, createdAt: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let start = startDate.map(formatter.string(from:)) ?? L10n.text("未知时间")
        let end: String
        if let startDate, let endDate {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            formatter.dateFormat = calendar.isDate(startDate, inSameDayAs: endDate) ? "HHmm" : "yyyyMMdd-HHmm"
            end = formatter.string(from: endDate)
        } else { end = L10n.text("未知时间") }
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return L10n.text("照片轨迹_生成%1$@_%2$@点_%3$@-%4$@.gpx", formatter.string(from: createdAt), exportedCount, start, end)
    }

    nonisolated static var generatedDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "PhotoTrail/GeneratedTracks", directoryHint: .isDirectory)
    }
    nonisolated static var legacyDirectory: URL {
        URL.cachesDirectory.appending(path: "PhotoTrail/GeneratedTracks", directoryHint: .isDirectory)
    }

    func saveGenerated(timeZone: TimeZone, createdAt: Date = .now) throws -> URL {
        try Self.store(data, name: suggestedFilename(timeZone: timeZone, createdAt: createdAt), in: Self.generatedDirectory)
    }

    nonisolated static func store(_ data: Data, name: String, in directory: URL, reuseIdentical: Bool = false, excluding occupied: Set<String> = []) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                    appropriateFor: directory, create: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let staging = temporary.appendingPathComponent("track.gpx")
        try data.write(to: staging)
        var suffix = 1
        while true {
            let candidate = suffix == 1 ? name : "\((name as NSString).deletingPathExtension)-\(suffix).gpx"
            let url = directory.appendingPathComponent(candidate)
            if occupied.contains(url.standardizedFileURL.path) { suffix += 1; continue }
            if renamex_np(staging.path, url.path, UInt32(RENAME_EXCL)) == 0 { return url }
            guard errno == EEXIST else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            if reuseIdentical, (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
               try Data(contentsOf: url) == data { return url }
            suffix += 1
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }

    private struct Point {
        let date: Date
        let latitude: Double
        let longitude: Double
        let elevation: Double?
        let name: String
    }

    private static func xml(points: [Point], segmentGap: TimeInterval) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var body = ""
        var previous: Date?
        for point in points {
            if previous.map({ point.date.timeIntervalSince($0) > segmentGap }) ?? true {
                if previous != nil { body += "    </trkseg>\n" }
                body += "    <trkseg>\n"
            }
            let latitude = String(format: "%.8f", locale: Locale(identifier: "en_US_POSIX"), point.latitude)
            let longitude = String(format: "%.8f", locale: Locale(identifier: "en_US_POSIX"), point.longitude)
            body += "      <trkpt lat=\"\(latitude)\" lon=\"\(longitude)\">\n"
            if let elevation = point.elevation {
                body += "        <ele>\(elevation)</ele>\n"
            }
            body += "        <time>\(formatter.string(from: point.date))</time>\n"
            body += "        <name>\(escape(point.name))</name>\n"
            body += "      </trkpt>\n"
            previous = point.date
        }
        if previous != nil { body += "    </trkseg>\n" }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="PhotoTrail" xmlns="http://www.topografix.com/GPX/1/1">
          <trk>
            <name>PhotoTrail Photos</name>
        \(body)  </trk>
        </gpx>

        """
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
