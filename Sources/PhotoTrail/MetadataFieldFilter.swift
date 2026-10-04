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
