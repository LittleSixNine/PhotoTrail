import Foundation

public enum MetadataDisplayValue: Equatable, Sendable {
    case absent
    case uniform(String)
    case mixed(present: Int, total: Int)
}

/// Fixed display schema. A displayed field does not grant permission to write it.
public struct MetadataDisplaySection: Sendable {
    public let name: String
    public let tags: [String]

    public static let standard: [Self] = [
        Self(name: "File", tags: [
            "File:FileName", "File:FilePath", "File:MDItemUserTags"
        ]),
        Self(name: "General", tags: [
            "EXIF:Artist", "IPTC:By-line", "IPTC:By-lineTitle",
            "IPTC:Contact"
        ]),
        Self(name: "Information", tags: [
            "EXIF:ImageDescription", "EXIF:Copyright", "EXIF:Software",
            "EXIF:UserComment", "IPTC:Headline", "IPTC:Caption-Abstract",
            "IPTC:ObjectName", "IPTC:Keywords", "XMP:Subject",
            "XMP:Keyword"
        ]),
        Self(name: "Date and Time", tags: [
            "File:FileCreateDate", "File:FileModifyDate", "EXIF:DateTimeOriginal",
            "EXIF:CreateDate", "EXIF:ModifyDate", "IPTC:DateCreated",
            "IPTC:TimeCreated", "XMP:CreateDate", "XMP:ModifyDate"
        ]),
        Self(name: "Camera", tags: [
            "EXIF:Make", "EXIF:Model", "EXIF:SerialNumber"
        ]),
        Self(name: "Camera Settings", tags: [
            "EXIF:ISO", "EXIF:FNumber", "EXIF:ApertureValue",
            "EXIF:ShutterSpeedValue", "EXIF:FocalLength", "EXIF:FocalLengthIn35mmFormat",
            "EXIF:ExposureCompensation", "EXIF:Flash"
        ]),
        Self(name: "Advanced Settings", tags: [
            "EXIF:ColorSpace", "EXIF:MaxApertureValue", "EXIF:ExposureMode",
            "EXIF:ExposureProgram", "EXIF:ExposureTime", "EXIF:MeteringMode",
            "EXIF:WhiteBalance", "EXIF:Saturation", "EXIF:Sharpness"
        ]),
        Self(name: "Lens", tags: [
            "EXIF:LensMake", "EXIF:Lens", "EXIF:LensModel",
            "EXIF:LensSerialNumber", "XMP:Lens", "XMP:LensInfo",
            "XMP:FocalLength"
        ]),
        Self(name: "Dimension And Resolution", tags: [
            "EXIF:Orientation", "EXIF:ImageWidth", "EXIF:ImageHeight",
            "EXIF:ExifImageWidth", "EXIF:ExifImageHeight", "EXIF:XResolution",
            "EXIF:YResolution"
        ]),
        Self(name: "GPS Coordinates", tags: [
            "EXIF:GPSLatitude", "EXIF:GPSLatitudeRef", "EXIF:GPSLongitude",
            "EXIF:GPSLongitudeRef", "EXIF:GPSAltitude", "EXIF:GPSAltitudeRef",
            "EXIF:GPSDateStamp", "EXIF:GPSTimeStamp"
        ]),
        Self(name: "Location Address", tags: [
            "IPTC:City", "IPTC:Province-State", "IPTC:Sub-location",
            "IPTC:Country-PrimaryLocationName", "IPTC:Country-PrimaryLocationCode"
        ])
    ]

    /// Keep EXIF, IPTC and XMP distinct. When an XMP family has multiple
    /// namespaces, show them explicitly instead of picking an arbitrary value.
    public static func value(for tag: String, in values: [String: String], exactSource: Bool = false) -> String? {
        if exactSource { return values[tag] }
        let matches = sourceKeys(for: tag, in: values)
        if matches.count == 1 { return values[matches[0]] }
        if matches.isEmpty { return nil }
        return matches.compactMap { key in values[key].map { "\(key): \($0)" } }.joined(separator: "\n")
    }

    public static func sourceKeys(for tag: String, in values: [String: String]) -> [String] {
        let parts = tag.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return values[tag] == nil ? [] : [tag] }
        let family = String(parts[0])
        let name = String(parts[1])
        let imagePrefix = values.keys.contains { $0.hasPrefix("Image/") } && family != "XMP" ? "Image/" : ""
        return values.keys.filter { key in
            guard key.hasPrefix(imagePrefix) else { return false }
            let canonical = String(key.dropFirst(imagePrefix.count))
            let pieces = canonical.split(separator: ":")
            guard pieces.count >= 2, pieces.last == Substring(name) else { return false }
            let namespace = String(pieces[0])
            switch family {
            case "EXIF": return ["IFD0", "IFD1", "ExifIFD", "GPS", "InteropIFD", "EXIF"].contains(namespace)
            case "XMP": return namespace.hasPrefix("XMP-") || namespace == "XMP"
            case "File": return ["File", "System"].contains(namespace)
            default: return namespace == family
            }
        }.sorted()
    }

    public static func summarize(_ values: [String?]) -> MetadataDisplayValue {
        let present = values.compactMap { $0 }
        guard !present.isEmpty else { return .absent }
        guard present.count == values.count,
              Set(present.map { Data($0.utf8) }).count == 1 else {
            return .mixed(present: present.count, total: values.count)
        }
        return .uniform(present[0])
    }
}
