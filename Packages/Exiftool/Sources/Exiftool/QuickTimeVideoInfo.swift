import Coords
import Foundation

/// Movie-level metadata and the first video track in file order. Reading never grants edit access.
public struct QuickTimeVideoInfo: Equatable, Sendable {
    public let duration: Double?
    public let width: Int?
    public let height: Int?
    public let codec: String?
    public let frameRate: Double?
    public private(set) var model: String?
    public let hasContentIdentifier: Bool
    public private(set) var location: Coords?
    let userDataLocation: Bool
    let altitude: Double?
    let alternateLanguages: [MetadataTag: [String: String]]
    public var localizedFields: Set<MetadataTag> { Set(alternateLanguages.keys) }
    let nativeLists: Set<MetadataTag>
    public private(set) var editableValues: [MetadataTag: MetadataTagValue]
    public private(set) var creationDate: String?
    /// Some cameras encode a local clock in the UTC movie header. Keep this separate from capture time.
    public let containerDate: String?

    public var zonedCreationDate: String? {
        guard let creationDate,
              creationDate.range(of: #"(?:Z|[+-]\d{2}:\d{2})$"#, options: .regularExpression) != nil else { return nil }
        return creationDate
    }

    public static func acceptsExtension(_ url: URL) -> Bool {
        ["mov", "mp4"].contains(url.pathExtension.lowercased())
    }

    init(tags: [String: Any]) throws {
        guard let type = tags["File:MOV:FileType"] as? String, ["MOV", "MP4"].contains(type) else {
            throw Exiftool.ExiftoolError.invalidTagOutput
        }
        // Group 5 identifies the movie or track atom. Track group numbers follow file order.
        let videoTracks = tags.compactMap { key, value -> Int? in
            let suffix = ":MOV-Movie-Track-Media-Handler:HandlerType"
            guard key.hasPrefix("Track"), key.hasSuffix(suffix), value as? String == "vide" else { return nil }
            return Int(key.dropFirst(5).dropLast(suffix.count))
        }
        guard let track = videoTracks.min() else { throw Exiftool.ExiftoolError.invalidTagOutput }
        let header = "Track\(track):MOV-Movie-Track-TrackHeader:"
        let samples = "Track\(track):MOV-Movie-Track-Media-MediaInfo-SampleTable"
        let keys = "Keys:MOV-Movie-Meta-Keys:"
        width = (tags[header + "ImageWidth"] as? String).flatMap(Int.init)
        height = (tags[header + "ImageHeight"] as? String).flatMap(Int.init)
        codec = tags[samples + "-VisualSampleDesc:CompressorID"] as? String
        frameRate = (tags[samples + ":VideoFrameRate"] as? String).flatMap(Double.init)
        duration = (tags["QuickTime:MOV-Movie-MovieHeader:Duration"] as? String).flatMap(Double.init)
        model = tags[keys + "Model"] as? String
        hasContentIdentifier = tags[keys + "ContentIdentifier"] != nil
        creationDate = Self.date(tags[keys + "CreationDate"])
        containerDate = Self.date(tags["QuickTime:MOV-Movie-MovieHeader:CreateDate"])
        userDataLocation = tags["UserData:MOV-Movie-UserData:GPSCoordinates"] != nil
        let coordinate = (tags[keys + "GPSCoordinates"] ?? tags["UserData:MOV-Movie-UserData:GPSCoordinates"]) as? String
        let parts = coordinate?.split(whereSeparator: \.isWhitespace) ?? []
        altitude = parts.count > 2 ? Double(parts[2]) : nil
        if parts.count >= 2, let latitude = Double(parts[0]), let longitude = Double(parts[1]) {
            location = Coords.ifValid(latitude: latitude, longitude: longitude)
        } else {
            location = nil
        }
        var localized = [MetadataTag: [String: String]](), native = Set<MetadataTag>()
        var values = [MetadataTag: MetadataTagValue]()
        for tag in MetadataTag.allCases {
            guard let field = tag.movieField else { continue }
            let nativeName = tag.nativeMovieList ?? String(field.split(separator: ":").last!)
            let prefix = keys + nativeName + "-"
            for (key, raw) in tags where key.hasPrefix(prefix) {
                guard let text = raw as? String else { throw Exiftool.ExiftoolError.invalidTagOutput }
                localized[tag, default: [:]]["Keys:" + nativeName + "-" + key.dropFirst(prefix.count)] = text
            }
            if tag.nativeMovieList != nil, tags[keys + nativeName] != nil { native.insert(tag) }
            if tag == .captureLocation {
                values[tag] = location.map { .text(CaptureLocationField.text($0)) }
            } else if tag == .creator || tag == .subject {
                let suffix = ":" + String(field.split(separator: ":").last!)
                let raw = tags.first { $0.key.hasPrefix("XMP-dc:MOV-") && !$0.key.contains("-Track-") && $0.key.hasSuffix(suffix) }?.value
                if let list = raw as? [String] { values[tag] = .list(list) }
                else if let text = raw as? String { values[tag] = .list([text]) }
                else if let text = tags[keys + nativeName] as? String { values[tag] = .list([text]) }
            } else if let name = field.split(separator: ":").last,
                      let text = tags[keys + name] as? String {
                values[tag] = .text(text)
            }
        }
        alternateLanguages = localized
        nativeLists = native
        editableValues = values
    }

    public mutating func applySavedChanges(_ changes: [MetadataTag: MetadataTagChange]) {
        for (tag, change) in changes where tag.supportsMovieEditing {
            switch change {
            case .remove: editableValues[tag] = nil
            case .set(let value): editableValues[tag] = value
            }
            if tag == .captureLocation { location = change.coordinate }
            if tag == .model || tag == .captureDate {
                let text: String?
                if case .set(.text(let saved)) = change { text = saved } else { text = nil }
                if tag == .model { model = text } else { creationDate = text }
            }
        }
    }

    private static func date(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty, !text.hasPrefix("0000:") else { return nil }
        return text
    }
}

public extension Exiftool {
    func quickTimeVideoInfo(from url: URL) throws -> QuickTimeVideoInfo {
        guard QuickTimeVideoInfo.acceptsExtension(url) else { throw ExiftoolError.invalidTagOutput }
        let data = try run(["-j", "-G1:5", "-s", "-a", "-n", "-api", "LargeFileSupport=1", "-api", "QuickTimeUTC=0", "-api", "StructFormat=JSONQ", "-FileType",
                            "-HandlerType", "-ImageWidth", "-ImageHeight", "-CompressorID", "-VideoFrameRate",
                            "-Duration", "-Keys:Title*", "-Keys:Description*", "-Keys:Copyright*", "-Keys:Make*", "-Keys:Author*", "-Keys:Keywords*", "-XMP-dc:Creator", "-XMP-dc:Subject",
                            "-Keys:Model*", "-ContentIdentifier", "-GPSCoordinates", "-Keys:CreationDate*", "-CreateDate", url.path])
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let row = rows.first else { throw ExiftoolError.invalidTagOutput }
        return try QuickTimeVideoInfo(tags: row)
    }
}

public enum CaptureLocationField {
    public static func parse(_ text: String) -> Coords? {
        let parts = text.split { $0 == "," || $0.isWhitespace }
        guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]) else { return nil }
        return Coords.ifValid(latitude: lat, longitude: lon)
    }

    public static func text(_ point: Coords) -> String {
        "\(point.latitude) \(point.longitude)"
    }

    static func photoArguments(_ change: MetadataTagChange, xmp: Bool) throws -> [String] {
        let prefix = xmp ? "-XMP-exif:" : "-GPS:"
        switch change {
        case .remove:
            var tags = ["GPSLatitude", "GPSLongitude"]
            if !xmp { tags += ["GPSLatitudeRef", "GPSLongitudeRef"] }
            return tags.map { prefix + $0 + "=" }
        case .set(.text(let value)):
            guard let p = parse(value) else { throw Exiftool.ExiftoolError.invalidTagValue(tag: "GPSPosition") }
            if xmp {
                return [prefix + "GPSLatitude=\(p.latitude)", prefix + "GPSLongitude=\(p.longitude)", prefix + "GPSMapDatum=WGS-84"]
            }
            return [prefix + "GPSLatitude=\(abs(p.latitude))", prefix + "GPSLongitude=\(abs(p.longitude))",
                    prefix + "GPSLatitudeRef=" + (p.latitude < 0 ? "S" : "N"),
                    prefix + "GPSLongitudeRef=" + (p.longitude < 0 ? "W" : "E"), prefix + "GPSMapDatum=WGS-84"]
        default: throw Exiftool.ExiftoolError.invalidTagValue(tag: "GPSPosition")
        }
    }
}

extension Exiftool {
    private func movieLocationArguments(_ change: MetadataTagChange, before: QuickTimeVideoInfo) throws -> [String] {
        let value: String
        switch change {
        case .set(.text(let text)):
            guard let p = CaptureLocationField.parse(text) else { throw ExiftoolError.invalidTagValue(tag: "GPSPosition") }
            value = String(format: "%+011.7f%+012.7f", p.latitude, p.longitude)
                + (before.altitude.map { String(format: "%+.3f", $0) } ?? "") + "/"
        case .remove: value = ""
        default: throw ExiftoolError.invalidTagValue(tag: "GPSPosition")
        }
        var args = ["-Keys:GPSCoordinates=" + value]
        if before.userDataLocation { args.append("-UserData:GPSCoordinates=" + value) }
        return args
    }

    func updateMovieMetadata(_ changes: [MetadataTag: MetadataTagChange], in url: URL) throws -> [MetadataTag: MetadataTagValue] {
        guard !changes.isEmpty else { return [:] }
        let before = try quickTimeVideoInfo(from: url)
        var args = ["-api", "LargeFileSupport=1", "-overwrite_original_in_place"]
        var record: [String: Any] = ["SourceFile": "*"]
        for (tag, change) in changes {
            guard let field = tag.movieField else { throw ExiftoolError.invalidTagValue(tag: tag.rawValue) }
            if tag == .captureLocation {
                args += try movieLocationArguments(change, before: before)
                continue
            }
            // An unqualified QuickTime write replaces all languages. Include every existing
            // alternate explicitly and verify it after writing, alongside the requested value.
            if let alternatives = before.alternateLanguages[tag] {
                for (key, value) in alternatives { record[key] = value }
            }
            switch change {
            case .remove:
                guard !before.localizedFields.contains(tag) else { throw ExiftoolError.invalidTagValue(tag: field) }
                args.append("-" + field + "=")
                if let native = tag.nativeMovieList, before.nativeLists.contains(tag) { args.append("-Keys:" + native + "=") }
            case .set(.list(let list)) where tag.isList && !list.isEmpty && list.allSatisfy({ !$0.isEmpty }):
                record[field] = list
                if let name = tag.nativeMovieList, before.nativeLists.contains(tag) {
                    record["Keys:" + name] = tag == .creator ? list[0] : list.joined(separator: ", ")
                }
            case .set(.text(let text)) where !tag.isList && !text.isEmpty:
                if tag == .captureDate {
                    guard Self.hasMovieTimeZone(text), (try? MetadataFileTime.parse(text)) != nil else { throw ExiftoolError.invalidTagValue(tag: field) }
                }
                record[field] = text
            default: throw ExiftoolError.invalidTagValue(tag: field)
            }
        }
        let input = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: input) }
        if record.count > 1 {
            try JSONSerialization.data(withJSONObject: [record]).write(to: input, options: .atomic)
            args.append("-json=" + input.path)
        }
        do { try run(args + [url.path]) } catch { throw MetadataTagUpdateError.writeFailed(underlying: error) }
        let values: [MetadataTag: MetadataTagValue]
        let after: QuickTimeVideoInfo
        do { after = try quickTimeVideoInfo(from: url) }
        catch { throw MetadataTagUpdateError.readbackFailed(underlying: error) }
        values = after.editableValues.filter { changes[$0.key] != nil }
        for (tag, change) in changes {
            guard before.alternateLanguages[tag] == after.alternateLanguages[tag] else { throw MetadataTagUpdateError.readbackMismatch(tag: tag) }
            switch change {
            case .set(let expected) where !tag.matches(values[tag], expected): throw MetadataTagUpdateError.readbackMismatch(tag: tag)
            case .remove where values[tag] != nil: throw MetadataTagUpdateError.readbackMismatch(tag: tag)
            default: break
            }
        }
        return values
    }

    private static func hasMovieTimeZone(_ text: String) -> Bool {
        text.range(of: #"^\d{4}:\d{2}:\d{2} \d{2}:\d{2}:\d{2}(?:\.\d{1,9})?(?:Z|[+-](?:(?:0\d|1[0-3]):[0-5]\d|14:00))$"#, options: .regularExpression) != nil
    }
}

public extension MetadataTagChange {
    var coordinate: Coords? {
        guard case .set(.text(let text)) = self else { return nil }
        return CaptureLocationField.parse(text)
    }
}

public struct VideoTrackPoint: Sendable {
    public let seconds: Double
    public let location: Coords
    public let gpsDate: String?
}

public extension Exiftool {
    /// One point per explicitly timed sample. Additional fixes in a packet do not have individual playback times.
    func timedVideoLocations(from url: URL) throws -> [VideoTrackPoint] {
        guard QuickTimeVideoInfo.acceptsExtension(url) else { throw ExiftoolError.invalidTagOutput }
        let data = try run(["-api", "LargeFileSupport=1", "-ee", "-j", "-s", "-n", "-G3", "-SampleTime", "-GPSLatitude",
                            "-GPSLongitude", "-GPSDateTime", "-GPSMeasureMode", url.path])
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]], let row = rows.first else {
            throw ExiftoolError.invalidTagOutput
        }
        let suffix = ":SampleTime"
        return row.compactMap { key, value -> VideoTrackPoint? in
            guard key.hasPrefix("Doc"), key.hasSuffix(suffix), let seconds = value as? Double,
                  seconds.isFinite, seconds >= 0 else { return nil }
            let prefix = String(key.dropLast(suffix.count)) + ":"
            guard let lat = row[prefix + "GPSLatitude"] as? Double, let lon = row[prefix + "GPSLongitude"] as? Double,
                  let point = Coords.ifValid(latitude: lat, longitude: lon) else { return nil }
            if let fix = row[prefix + "GPSMeasureMode"] as? Int, fix < 2 { return nil }
            return VideoTrackPoint(seconds: seconds, location: point, gpsDate: row[prefix + "GPSDateTime"] as? String)
        }.sorted { $0.seconds < $1.seconds }
    }
}


public extension MetadataTag {
    fileprivate var nativeMovieList: String? {
        switch self {
        case .creator: "Author"
        case .subject: "Keywords"
        default: nil
        }
    }

    var movieField: String? {
        switch self {
        case .captureLocation: "Keys:GPSCoordinates"
        case .captureDate: "Keys:CreationDate"
        case .titleDefault: "Keys:Title"
        case .descriptionDefault: "Keys:Description"
        case .rightsDefault: "Keys:Copyright"
        case .make: "Keys:Make"
        case .model: "Keys:Model"
        case .creator, .subject: rawValue
        default: nil
        }
    }

    var supportsMovieEditing: Bool { movieField != nil }
}
