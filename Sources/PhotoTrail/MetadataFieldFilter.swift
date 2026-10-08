import Foundation

enum MetadataFieldFilter {
    static let commonTags: Set<String> = [
        "IFD0:Make", "IFD0:Model", "IFD0:Artist", "IFD0:Copyright", "IFD0:ImageDescription",
        "Composite:SubSecDateTimeOriginal", "Composite:SubSecCreateDate", "Composite:SubSecModifyDate",
        "XMP-tiff:Make", "XMP-tiff:Model", "XMP-dc:Creator", "XMP-dc:Title-x-default",
        "XMP-dc:Description-x-default", "XMP-dc:Rights-x-default", "XMP-dc:Subject",
        "XMP-xmp:CreateDate", "XMP-xmp:ModifyDate", "XMP-exif:DateTimeOriginal", "XMP-exif:DateTimeDigitized", "IPTC:Keywords"
    ]

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
