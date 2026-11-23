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
    public let location: Coords?
    public let creationDate: String?
    /// Some cameras encode a local clock in the UTC movie header. Keep this separate from capture time.
    public let containerDate: String?

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
        creationDate = Self.date(tags[keys + "CreationDate"])
        containerDate = Self.date(tags["QuickTime:MOV-Movie-MovieHeader:CreateDate"])
        let coordinate = (tags[keys + "GPSCoordinates"] ?? tags["UserData:MOV-Movie-UserData:GPSCoordinates"]) as? String
        let parts = coordinate?.split(whereSeparator: \.isWhitespace) ?? []
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
        let data = try run(["-j", "-G1:5", "-s", "-a", "-n", "-api", "QuickTimeUTC=0", "-FileType",
                            "-HandlerType", "-ImageWidth", "-ImageHeight", "-CompressorID", "-VideoFrameRate",
                            "-Duration", "-Model", "-GPSCoordinates", "-CreationDate", "-CreateDate", url.path])
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let row = rows.first else { throw ExiftoolError.invalidTagOutput }
        return try QuickTimeVideoInfo(tags: row)
    }
}
