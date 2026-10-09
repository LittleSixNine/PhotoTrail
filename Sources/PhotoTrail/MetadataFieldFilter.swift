import Foundation
import Exiftool

enum MetadataFieldFilter {
    static let commonTags: Set<String> = [
        "File:FileName", "File:FilePath",
        "Composite:SubSecDateTimeOriginal", "Composite:SubSecCreateDate", "Composite:SubSecModifyDate",
        "IPTC:DateCreated", "IPTC:TimeCreated",
        "XMP-xmp:CreateDate", "XMP-xmp:ModifyDate", "XMP-exif:DateTimeOriginal", "XMP-exif:DateTimeDigitized",
        "IFD0:Make", "IFD0:Model",
        "ExifIFD:ISO", "ExifIFD:FNumber", "ExifIFD:ShutterSpeedValue",
        "ExifIFD:FocalLength", "ExifIFD:ExposureCompensation",
        "EXIF:GPSLatitude", "EXIF:GPSLatitudeRef", "EXIF:GPSLongitude", "EXIF:GPSLongitudeRef",
        "EXIF:GPSDateStamp", "EXIF:GPSTimeStamp"
    ]

    static let commonFieldsKey = "PhotoTrailMetadataCommonFields.v1"
    static let configurableTags: [String] = {
        var seen: Set<String> = []
        return (MetadataDisplaySection.standard.flatMap(\.tags).map { mappedTag($0)?.rawValue ?? $0 }
                + MetadataTag.allCases.map(\.rawValue)).filter { seen.insert($0).inserted }
    }()

    static func commonTags(from data: Data) -> Set<String> {
        guard let tags = try? JSONDecoder().decode([String].self, from: data) else { return commonTags }
        return Set(tags).intersection(configurableTags)
    }

    static func mappedTag(_ tag: String) -> MetadataTag? {
        if tag == "EXIF:DateTimeOriginal" { return .captureDate }
        if tag == "EXIF:CreateDate" { return .exifCreateDate }
        if tag == "EXIF:ModifyDate" { return .exifModifyDate }
        if tag == "XMP:Subject" { return .subject }
        if tag == "File:FileCreateDate" { return .fileCreateDate }
        if tag == "File:FileModifyDate" { return .fileModifyDate }
        if tag == "XMP:CreateDate" { return .sidecarDate }
        if tag == "XMP:ModifyDate" { return .dateModified }
        if tag == "XMP:Lens" { return .lens }
        if tag == "XMP:FocalLength" { return .focalLength }
        return MetadataTag.allCases.first { writable in
            !writable.supportsSidecar && tag.split(separator: ":").last == writable.rawValue.split(separator: ":").last
                && (tag.hasPrefix("EXIF:") ? writable.rawValue.hasPrefix("IFD0:") || writable.rawValue.hasPrefix("ExifIFD:")
                    : tag.hasPrefix("IPTC:") && writable.rawValue.hasPrefix("IPTC:"))
        }
    }

    static func displayName(_ tag: String) -> String {
        let name = tag.split(separator: ":").last.map(String.init) ?? tag
        let labels: [String: String] = [
            "FileName": "Metadata field: FileName",
            "FilePath": "Metadata field: FilePath",
            "MDItemUserTags": "Metadata field: MDItemUserTags",
            "Artist": "Metadata field: Artist",
            "By-line": "Metadata field: By-line",
            "By-lineTitle": "Metadata field: By-lineTitle",
            "Contact": "Metadata field: Contact",
            "ImageDescription": "Metadata field: ImageDescription",
            "Copyright": "Metadata field: Copyright",
            "Software": "Metadata field: Software",
            "UserComment": "Metadata field: UserComment",
            "Headline": "Metadata field: Headline",
            "Caption-Abstract": "Metadata field: Caption-Abstract",
            "ObjectName": "Metadata field: ObjectName",
            "Keywords": "Metadata field: Keywords",
            "Subject": "Metadata field: Subject",
            "Keyword": "Metadata field: Keyword",
            "FileCreateDate": "Metadata field: FileCreateDate",
            "FileModifyDate": "Metadata field: FileModifyDate",
            "DateTimeOriginal": "Metadata field: DateTimeOriginal",
            "CreateDate": "Metadata field: CreateDate",
            "ModifyDate": "Metadata field: ModifyDate",
            "DateCreated": "Metadata field: DateCreated",
            "TimeCreated": "Metadata field: TimeCreated",
            "Make": "Metadata field: Make",
            "Model": "Metadata field: Model",
            "SerialNumber": "Metadata field: SerialNumber",
            "ISO": "Metadata field: ISO",
            "FNumber": "Metadata field: FNumber",
            "ApertureValue": "Metadata field: ApertureValue",
            "ShutterSpeedValue": "Metadata field: ShutterSpeedValue",
            "FocalLength": "Metadata field: FocalLength",
            "FocalLengthIn35mmFormat": "Metadata field: FocalLengthIn35mmFormat",
            "ExposureCompensation": "Metadata field: ExposureCompensation",
            "Flash": "Metadata field: Flash",
            "ColorSpace": "Metadata field: ColorSpace",
            "MaxApertureValue": "Metadata field: MaxApertureValue",
            "ExposureMode": "Metadata field: ExposureMode",
            "ExposureProgram": "Metadata field: ExposureProgram",
            "ExposureTime": "Metadata field: ExposureTime",
            "MeteringMode": "Metadata field: MeteringMode",
            "WhiteBalance": "Metadata field: WhiteBalance",
            "Saturation": "Metadata field: Saturation",
            "Sharpness": "Metadata field: Sharpness",
            "LensMake": "Metadata field: LensMake",
            "Lens": "Metadata field: Lens",
            "LensModel": "Metadata field: LensModel",
            "LensSerialNumber": "Metadata field: LensSerialNumber",
            "LensInfo": "Metadata field: LensInfo",
            "Orientation": "Metadata field: Orientation",
            "ImageWidth": "Metadata field: ImageWidth",
            "ImageHeight": "Metadata field: ImageHeight",
            "ExifImageWidth": "Metadata field: ExifImageWidth",
            "ExifImageHeight": "Metadata field: ExifImageHeight",
            "XResolution": "Metadata field: XResolution",
            "YResolution": "Metadata field: YResolution",
            "GPSLatitude": "Metadata field: GPSLatitude",
            "GPSLatitudeRef": "Metadata field: GPSLatitudeRef",
            "GPSLongitude": "Metadata field: GPSLongitude",
            "GPSLongitudeRef": "Metadata field: GPSLongitudeRef",
            "GPSAltitude": "Metadata field: GPSAltitude",
            "GPSAltitudeRef": "Metadata field: GPSAltitudeRef",
            "GPSDateStamp": "Metadata field: GPSDateStamp",
            "GPSTimeStamp": "Metadata field: GPSTimeStamp",
            "City": "Metadata field: City",
            "Province-State": "Metadata field: Province-State",
            "Sub-location": "Metadata field: Sub-location",
            "Country-PrimaryLocationName": "Metadata field: Country-PrimaryLocationName",
            "Country-PrimaryLocationCode": "Metadata field: Country-PrimaryLocationCode"
        ]
        let label = labels[name].map { L10n.text($0) } ?? name
        return name.contains("Date") || name.contains("Time")
            ? MetadataFieldSourceLabel.label(label, tag: tag) : label
    }

    static func matches(query: String, presentOnly: Bool, editedOnly: Bool,
                        commonOnly: Bool = false, isCommon: Bool = true,
                        names: [String], hasEdits: @autoclosure () -> Bool,
                        values: () -> [String?]) -> Bool {
        if commonOnly && !isCommon && query.isEmpty && !editedOnly { return false }
        if editedOnly && !hasEdits() { return false }
        let nameMatches = query.isEmpty || names.contains { $0.localizedCaseInsensitiveContains(query) }
        if !presentOnly && nameMatches { return true }
        let fieldValues = values()
        if presentOnly && !fieldValues.contains(where: { $0 != nil }) { return false }
        return nameMatches || fieldValues.contains { $0?.localizedCaseInsensitiveContains(query) == true }
    }
}

enum MetadataFieldSourceLabel {
    static func protocolName(_ tag: String) -> String? {
        let canonical = tag.split(separator: "/").last.map(String.init) ?? tag
        let family = canonical.split(separator: ":").first.map(String.init) ?? ""
        if family.hasPrefix("XMP") { return "XMP" }
        if family == "IPTC" { return "IPTC" }
        if ["EXIF", "IFD0", "IFD1", "ExifIFD", "Composite", "GPS"].contains(family) { return "EXIF" }
        if ["File", "System"].contains(family) { return L10n.text("文件系统") }
        return nil
    }
    static func label(_ label: String, tag: String) -> String {
        guard let source = protocolName(tag), !label.contains(source) else { return label }
        return label + "（" + source + "）"
    }
}
