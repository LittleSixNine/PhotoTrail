import Coords
import Foundation

/// Movie-level metadata and the first video track in file order. Reading never grants edit access.
public struct QuickTimeVideoInfo: Equatable, Sendable {
    public let duration: Double?
    public let width: Int?
    public let height: Int?
    public let codec: String?
    public let frameRate: Double?
    public let model: String?
    public let hasContentIdentifier: Bool
    public let location: Coords?
    let userDataLocation: Bool
    let altitude: Double?
    public let creationDate: String?
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
        width = (tags[header + "ImageWidth"] as? NSNumber)?.intValue
        height = (tags[header + "ImageHeight"] as? NSNumber)?.intValue
        codec = tags[samples + "-VisualSampleDesc:CompressorID"] as? String
        frameRate = (tags[samples + ":VideoFrameRate"] as? NSNumber)?.doubleValue
        duration = (tags["QuickTime:MOV-Movie-MovieHeader:Duration"] as? NSNumber)?.doubleValue
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
    }

    private static func date(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty, !text.hasPrefix("0000:") else { return nil }
        return text
    }
}

public extension Exiftool {
    func quickTimeVideoInfo(from url: URL) throws -> QuickTimeVideoInfo {
        guard QuickTimeVideoInfo.acceptsExtension(url) else { throw ExiftoolError.invalidTagOutput }
        let data = try run(["-j", "-G1:5", "-s", "-a", "-n", "-api", "LargeFileSupport=1", "-api", "QuickTimeUTC=0", "-FileType",
                            "-HandlerType", "-ImageWidth", "-ImageHeight", "-CompressorID", "-VideoFrameRate",
                            "-Duration", "-Model", "-ContentIdentifier", "-GPSCoordinates", "-CreationDate", "-CreateDate", url.path])
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
    func updateMovieLocation(_ change: MetadataTagChange, in url: URL) throws -> [MetadataTag: MetadataTagValue] {
        let before = try quickTimeVideoInfo(from: url)
        let value: String
        switch change {
        case .set(.text(let text)):
            guard let p = CaptureLocationField.parse(text) else { throw ExiftoolError.invalidTagValue(tag: "GPSPosition") }
            value = String(format: "%+011.7f%+012.7f", p.latitude, p.longitude)
                + (before.altitude.map { String(format: "%+.3f", $0) } ?? "") + "/"
        case .remove: value = ""
        default: throw ExiftoolError.invalidTagValue(tag: "GPSPosition")
        }
        var args = ["-api", "LargeFileSupport=1", "-overwrite_original_in_place", "-Keys:GPSCoordinates=" + value]
        if before.userDataLocation { args.append("-UserData:GPSCoordinates=" + value) }
        do { try run(args + [url.path]) } catch { throw MetadataTagUpdateError.writeFailed(underlying: error) }
        let tags: [MetadataTag: MetadataTagValue]
        do { tags = try metadataTags([.captureLocation], from: url) }
        catch { throw MetadataTagUpdateError.readbackFailed(underlying: error) }
        switch change {
        case .set(let expected) where MetadataTag.captureLocation.matches(tags[.captureLocation], expected): return tags
        case .remove where tags.isEmpty: return tags
        default: throw MetadataTagUpdateError.readbackMismatch(tag: .captureLocation)
        }
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
