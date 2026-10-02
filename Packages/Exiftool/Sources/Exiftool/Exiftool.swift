import Coords
import Metadata
import OSLog
import SwiftUI

public struct Exiftool: Sendable {
    // singleton instance of this class
    public static let helper = Exiftool()

    public enum ExiftoolError: Error {
        case runFailed(code: Int)
        case invalidTagValue(tag: String)
        case invalidTagOutput
        case unsupportedIPTCEncoding
    }

    // URL of the embedded version of ExifTool
    var url: URL

    let dateFormatter = DateFormatter()

    // Build the url needed to access to the embedded version of ExifTool

    private init() {
        if let exiftoolUrl = Bundle.module.url(
            forResource: "ExifToolCommand",
            withExtension: nil) {
            url = exiftoolUrl.appendingPathComponent("exiftool")
        } else {
            fatalError("The Application Bundle is corrupt.")
        }
    }
}

public enum MetadataTag: String, CaseIterable, Codable, Sendable {
    case creator = "XMP-dc:Creator"
    case titleDefault = "XMP-dc:Title-x-default"
    case descriptionDefault = "XMP-dc:Description-x-default"
    case rightsDefault = "XMP-dc:Rights-x-default"
    case subject = "XMP-dc:Subject"
    case captureDate = "Composite:SubSecDateTimeOriginal"
    case sidecarDate = "XMP-xmp:CreateDate"
    case dateOriginal = "XMP-exif:DateTimeOriginal"
    case dateDigitized = "XMP-exif:DateTimeDigitized"
    case dateModified = "XMP-xmp:ModifyDate"
    case make = "XMP-tiff:Make"
    case model = "XMP-tiff:Model"
    case lens = "XMP-aux:Lens"
    case exposureTime = "XMP-exif:ExposureTime"
    case fNumber = "XMP-exif:FNumber"
    case iso = "XMP-exif:ISO"
    case focalLength = "XMP-exif:FocalLength"
    case exposureBias = "XMP-exif:ExposureCompensation"
    case exposureProgram = "XMP-exif:ExposureProgram"
    case whiteBalance = "XMP-exif:WhiteBalance"

    case exifArtist = "IFD0:Artist"
    case exifDescription = "IFD0:ImageDescription"
    case exifCopyright = "IFD0:Copyright"
    case exifSoftware = "IFD0:Software"
    case exifComment = "ExifIFD:UserComment"
    case iptcByline = "IPTC:By-line"
    case iptcBylineTitle = "IPTC:By-lineTitle"
    case iptcContact = "IPTC:Contact"
    case iptcHeadline = "IPTC:Headline"
    case iptcCaption = "IPTC:Caption-Abstract"
    case iptcObjectName = "IPTC:ObjectName"
    case iptcKeywords = "IPTC:Keywords"
    case iptcCity = "IPTC:City"
    case iptcProvince = "IPTC:Province-State"
    case iptcLocation = "IPTC:Sub-location"
    case iptcCountry = "IPTC:Country-PrimaryLocationName"
    case iptcCountryCode = "IPTC:Country-PrimaryLocationCode"

    case exifMake = "IFD0:Make"
    case exifModel = "IFD0:Model"
    case exifSerial = "ExifIFD:SerialNumber"
    case exifLensMake = "ExifIFD:LensMake"
    case exifLensModel = "ExifIFD:LensModel"
    case exifLensSerial = "ExifIFD:LensSerialNumber"
    case exifExposureTime = "ExifIFD:ExposureTime"
    case exifFNumber = "ExifIFD:FNumber"
    case exifISO = "ExifIFD:ISO"
    case exifAperture = "ExifIFD:ApertureValue"
    case exifShutter = "ExifIFD:ShutterSpeedValue"
    case exifFocalLength = "ExifIFD:FocalLength"
    case exifFocal35 = "ExifIFD:FocalLengthIn35mmFormat"
    case exifExposureBias = "ExifIFD:ExposureCompensation"
    case exifFlash = "ExifIFD:Flash"
    case exifColorSpace = "ExifIFD:ColorSpace"
    case exifMaxAperture = "ExifIFD:MaxApertureValue"
    case exifExposureMode = "ExifIFD:ExposureMode"
    case exifExposureProgram = "ExifIFD:ExposureProgram"
    case exifMeteringMode = "ExifIFD:MeteringMode"
    case exifWhiteBalance = "ExifIFD:WhiteBalance"
    case exifSaturation = "ExifIFD:Saturation"
    case exifSharpness = "ExifIFD:Sharpness"
    case exifCreateDate = "Composite:SubSecCreateDate"
    case exifModifyDate = "Composite:SubSecModifyDate"

    public var isList: Bool { [.creator, .subject, .iptcByline, .iptcBylineTitle, .iptcContact, .iptcKeywords].contains(self) }
    public var supportsSidecar: Bool { rawValue.hasPrefix("XMP-") }

    public var isDate: Bool { [.captureDate, .sidecarDate, .dateOriginal, .dateDigitized, .dateModified, .exifCreateDate, .exifModifyDate].contains(self) }

    public var numericRange: ClosedRange<Double>? {
        switch self {
        case .exposureTime, .exifExposureTime, .exifShutter: 0.000001...86400
        case .fNumber, .exifFNumber: 0.1...128
        case .exifAperture, .exifMaxAperture: 1...128
        case .iso: 1...1_000_000
        case .exifISO: 1...65535
        case .focalLength, .exifFocalLength: 0.1...10000
        case .exifFocal35: 0...65535
        case .exposureBias, .exifExposureBias: -100...100
        case .exposureProgram, .exifExposureProgram: 0...8
        case .whiteBalance, .exifWhiteBalance: 0...1
        case .exifExposureMode, .exifSaturation, .exifSharpness: 0...2
        case .exifFlash: 0...127
        case .exifMeteringMode: 0...255
        case .exifColorSpace: 1...65535
        default: nil
        }
    }

    public func matches(_ actual: MetadataTagValue?, _ expected: MetadataTagValue) -> Bool {
        if numericRange != nil, case .text(let left) = actual, case .text(let right) = expected,
           let actual = Double(left), let expected = Double(right) {
            // EXIF APEX fields store a rational logarithm; conversion back to seconds/f-number has bounded rounding.
            let tolerance = [.exifAperture, .exifMaxAperture, .exifShutter].contains(self) ? 1e-6 : 1e-9
            return actual.isFinite && abs(actual - expected) <= max(1e-12, abs(expected) * tolerance)
        }
        if isDate, case .text(let left) = actual, case .text(let right) = expected {
            return left.replacingOccurrences(of: "Z", with: "+00:00") == right.replacingOccurrences(of: "Z", with: "+00:00")
        }
        return actual == expected
    }

    public var maxUTF8Length: Int? {
        switch self {
        case .iptcByline, .iptcBylineTitle, .iptcCity, .iptcProvince, .iptcLocation: 32
        case .iptcKeywords, .iptcObjectName, .iptcCountry: 64
        case .iptcContact: 128
        case .iptcHeadline: 256
        case .iptcCaption: 2000
        case .iptcCountryCode: 3
        default: nil
        }
    }

    public func checkedText(_ text: String) throws -> String {
        guard !text.isEmpty else { throw Exiftool.ExiftoolError.invalidTagValue(tag: rawValue) }
        if let limit = maxUTF8Length, text.utf8.count > limit { throw Exiftool.ExiftoolError.invalidTagValue(tag: rawValue) }
        if self == .iptcCountryCode && (text.utf8.count != 3 || !text.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) })) {
            throw Exiftool.ExiftoolError.invalidTagValue(tag: rawValue)
        }
        guard let range = numericRange else { return text }
        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        let value: Double
        if parts.count == 2, let numerator = Double(parts[0]), let denominator = Double(parts[1]), denominator != 0 {
            value = numerator / denominator
        } else if let number = Double(text), parts.count == 1 { value = number }
        else { throw Exiftool.ExiftoolError.invalidTagValue(tag: rawValue) }
        let integerTags: Set<MetadataTag> = [.iso, .exifISO, .exifFocal35, .exposureProgram, .exifExposureProgram,
                                             .whiteBalance, .exifWhiteBalance, .exifExposureMode, .exifSaturation,
                                             .exifSharpness, .exifFlash, .exifMeteringMode, .exifColorSpace]
        guard value.isFinite, range.contains(value), !integerTags.contains(self) || value.rounded() == value else {
            throw Exiftool.ExiftoolError.invalidTagValue(tag: rawValue)
        }
        if self == .exifColorSpace && ![1.0, 65535.0].contains(value) { throw Exiftool.ExiftoolError.invalidTagValue(tag: rawValue) }
        if self == .exifMeteringMode && ![0.0, 1, 2, 3, 4, 5, 6, 255].contains(value) { throw Exiftool.ExiftoolError.invalidTagValue(tag: rawValue) }
        return value.rounded() == value ? String(format: "%.0f", value) : String(value)
    }
}

public enum MetadataTagValue: Equatable, Codable, Sendable {
    case text(String)
    case list([String])

    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.text(let left), .text(let right)): left.utf8.elementsEqual(right.utf8)
        case (.list(let left), .list(let right)):
            left.count == right.count && zip(left, right).allSatisfy { $0.0.utf8.elementsEqual($0.1.utf8) }
        default: false
        }
    }
}

public enum LegacyCreatorTag: String, Sendable {
    case exifArtist = "IFD0:Artist"
    case iptcByline = "IPTC:By-line"
}

public enum MetadataTagChange: Equatable, Codable, Sendable {
    case set(MetadataTagValue)
    case remove
}

public enum MetadataTagUpdateError: Error {
    case writeFailed(underlying: any Error)
    case readbackFailed(underlying: any Error)
    case readbackMismatch(tag: MetadataTag)

    // ExifTool may have changed part or all of the file before any process
    // error is reported, so every failure after the write starts is unknown
    // until the requested tags are read again.
    public var resultIsUnknown: Bool { true }
}

private enum MetadataReadValue: Decodable {
    case text(String), list([String]), number(Double), null
    init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let string = try? value.decode(String.self) { self = .text(string) }
        else if let list = try? value.decode([String].self) { self = .list(list) }
        else { self = .number(try value.decode(Double.self)) }
    }
}

private enum MetadataTagValueKind: Equatable {
    case text
    case list
}

private extension MetadataTag {
    var valueKind: MetadataTagValueKind {
        switch self {
        case .creator, .subject, .iptcByline, .iptcBylineTitle, .iptcContact, .iptcKeywords: .list
        default: .text
        }
    }

    var readName: String {
        switch self {
        case .titleDefault: "XMP-dc:Title"
        case .descriptionDefault: "XMP-dc:Description"
        case .rightsDefault: "XMP-dc:Rights"
        case .exifCreateDate: "Composite:SubSecCreateDate"
        case .exifModifyDate: "Composite:SubSecModifyDate"
        default: rawValue
        }
    }
}

// Define a logger for the package

extension Exiftool {
    static let logger =
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "ExiftoolTest",
               category: "ExifTool")
}

// Keep descriptive-tag reads separate from the existing date/location update.
// Only the explicit MetadataTag whitelist is writable; sources remain independent.

extension Exiftool {
    public func xmpData(from image: URL) throws -> Data {
        try run(["-tagsfromfile", image.path, "-all:all", "-o", "-.xmp"])
    }

    // Inspect every available family, including MakerNotes and container metadata, without granting write access.
    public func inspectionTags(from image: URL, additional: Bool = true) throws -> [String: String] {
        let requested = additional ? []
            : MetadataDisplaySection.standard.flatMap(\.tags)
                .filter { !["File:FilePath", "File:MDItemUserTags"].contains($0) }.map { "-" + $0 }
        let data = try run(["-j", "-G0:1:4", "-s", "-a"] + requested + [image.path])
        guard let entries = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let entry = entries.first else { throw ExiftoolError.invalidTagOutput }
        var result: [String: String] = [:]
        for (sourceTag, value) in entry where sourceTag != "SourceFile" {
            let tag = Self.inspectionKey(sourceTag)
            if let text = value as? String { result[tag] = text }
            else if let number = value as? NSNumber { result[tag] = number.stringValue }
            else if JSONSerialization.isValidJSONObject(value) {
                result[tag] = String(data: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
                                     encoding: .utf8)
            }
        }
        result["File:FilePath"] = image.path
        if let resource = try? image.resourceValues(forKeys: [.creationDateKey, .tagNamesKey]) {
            if let date = resource.creationDate {
                result["File:FileCreateDate"] = ISO8601DateFormatter().string(from: date)
            }
            if let tags = resource.tagNames { result["File:MDItemUserTags"] = tags.joined(separator: ", ") }
        }
        return result
    }

    // Family 0 identifies derived values even when family 1 inherits a camera namespace.
    // Keep family 1 and copy identifiers for physical fields, and Composite for derived fields.
    static func inspectionKey(_ tag: String) -> String {
        let parts = tag.split(separator: ":")
        guard parts.count > 2, parts[0] != "Composite", !parts[1].hasPrefix("Copy") else { return tag }
        return parts.dropFirst().joined(separator: ":")
    }

    // Read compatibility fields without adding them to the editable whitelist.
    public func legacyCreatorTags(from image: URL) throws -> [LegacyCreatorTag: [String]] {
        let data = try run(["-j", "-G1", "-EXIF:Artist", "-IPTC:By-line", image.path])
        guard let entries = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let entry = entries.first else {
            throw ExiftoolError.invalidTagOutput
        }
        var result: [LegacyCreatorTag: [String]] = [:]
        for tag in [LegacyCreatorTag.exifArtist, .iptcByline] {
            switch entry[tag.rawValue] {
            case nil:
                continue
            case let value as String:
                result[tag] = [value]
            case let values as [String]:
                result[tag] = values
            default:
                throw ExiftoolError.invalidTagOutput
            }
        }
        return result
    }

    public func metadataTags(_ tags: Set<MetadataTag>,
                             from image: URL) throws -> [MetadataTag: MetadataTagValue] {
        guard !tags.isEmpty else { return [:] }
        let sortedTags = tags.sorted { $0.rawValue < $1.rawValue }
        var args = ["-j", "-G1", "-n", "-api", "StructFormat=JSONQ"]
        args += sortedTags.map { "-\($0.readName)" }
        let dateFallbacks: [MetadataTag: String] = [.captureDate: "ExifIFD:DateTimeOriginal", .exifCreateDate: "ExifIFD:CreateDate", .exifModifyDate: "IFD0:ModifyDate"]
        args += sortedTags.compactMap { dateFallbacks[$0].map { "-" + $0 } }
        args.append(image.path)
        let data = try run(args)
        // Typed decoding validates the requested value kinds without lossy string conversions.
        let entries = try JSONDecoder().decode([[String: MetadataReadValue]].self, from: data)
        guard let entry = entries.first else { throw ExiftoolError.invalidTagOutput }
        var result: [MetadataTag: MetadataTagValue] = [:]
        for tag in sortedTags {
            switch (tag.valueKind, entry[tag.readName] ?? dateFallbacks[tag].flatMap { entry[$0] }) {
            case (.text, .text(let value)): result[tag] = .text(value)
            case (.text, .number(let value)) where tag.numericRange != nil:
                result[tag] = .text(value.rounded() == value ? String(format: "%.0f", value) : String(value))
            case (.list, .text(let value)): result[tag] = .list([value])
            case (.list, .list(let values)): result[tag] = .list(values)
            case (_, nil), (_, .null): continue
            default: throw ExiftoolError.invalidTagOutput
            }
        }
        return result
    }

    /// Existing IPTC with an unspecified legacy encoding is never silently recoded.
    /// New IPTC gets an explicit UTF-8 declaration; UTF-8 IPTC keeps its declaration.
    public func needsIPTCUTF8Declaration(image: URL, changes: [MetadataTag: MetadataTagChange]) throws -> Bool {
        let sets = changes.filter { tag, change in
            if case .set = change { return tag.rawValue.hasPrefix("IPTC:") }; return false
        }
        guard !sets.isEmpty else { return false }
        let data = try run(["-j", "-G1", "-IPTC:all", image.path])
        let entries = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        guard let entry = entries?.first else { throw ExiftoolError.invalidTagOutput }
        let existing = entry.filter { $0.key.hasPrefix("IPTC:") }
        guard existing.isEmpty || entry["IPTC:CodedCharacterSet"] as? String == "UTF8" else {
            throw ExiftoolError.unsupportedIPTCEncoding
        }
        return existing.isEmpty
    }

    public func update(
        image: URL,
        changes: [MetadataTag: MetadataTagChange]
    ) throws -> [MetadataTag: MetadataTagValue] {
        try update(
            image: image,
            changes: changes,
            write: { try run($0) },
            readback: { tags, image in try metadataTags(tags, from: image) })
    }

    func update(
        image: URL,
        changes: [MetadataTag: MetadataTagChange],
        write: ([String]) throws -> Void,
        readback: (Set<MetadataTag>, URL) throws -> [MetadataTag: MetadataTagValue]
    ) throws -> [MetadataTag: MetadataTagValue] {
        guard !changes.isEmpty else { return [:] }
        if image.pathExtension.lowercased() == "xmp", let tag = changes.keys.first(where: { !$0.supportsSidecar }) {
            throw ExiftoolError.invalidTagValue(tag: tag.rawValue)
        }
        let sortedChanges = changes.sorted { $0.key.rawValue < $1.key.rawValue }
        // Foundation Process normalizes non-ASCII argv on macOS. Keep values in
        // ExifTool's native UTF-8 JSON input to preserve exact Unicode and newlines.
        var record: [String: Any] = ["SourceFile": "*"]
        var args = ["-q", "-n", "-overwrite_original_in_place"]
        if try needsIPTCUTF8Declaration(image: image, changes: changes) {
            args.append("-IPTC:CodedCharacterSet=UTF8")
        }
        for (tag, change) in sortedChanges {
            switch change {
            case .set(.text(let value)):
                guard tag.valueKind == .text else { throw ExiftoolError.invalidTagValue(tag: tag.rawValue) }
                record[tag.rawValue] = try tag.checkedText(value)
            case .set(.list(let values)):
                guard tag.valueKind == .list, !values.isEmpty, values.allSatisfy({ !$0.isEmpty }) else {
                    throw ExiftoolError.invalidTagValue(tag: tag.rawValue)
                }
                record[tag.rawValue] = try values.map(tag.checkedText)
            case .remove: args.append("-\(tag.rawValue)=")
            }
        }
        let input = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: input) }
        if record.count > 1 {
            try JSONSerialization.data(withJSONObject: [record], options: [.sortedKeys]).write(to: input, options: .atomic)
            args.append("-json=\(input.path)")
        }
        args.append(image.path)
        do {
            try write(args)
        } catch {
            throw MetadataTagUpdateError.writeFailed(underlying: error)
        }

        let values: [MetadataTag: MetadataTagValue]
        do {
            values = try readback(Set(changes.keys), image)
        } catch {
            throw MetadataTagUpdateError.readbackFailed(underlying: error)
        }
        for (tag, change) in changes {
            switch change {
            case .set(let value) where !tag.matches(values[tag], value):
                throw MetadataTagUpdateError.readbackMismatch(tag: tag)
            case .remove where values[tag] != nil:
                throw MetadataTagUpdateError.readbackMismatch(tag: tag)
            default:
                break
            }
        }
        return values
    }
}

// Run the embedded exiftool to get its version. Used
// when testing to verify the embedded program can be
// accessed

extension Exiftool {
    public func version() throws -> String? {
        let data = try run(["-ver"])
        if data.count > 0,
            let string = String(data: data, encoding: String.Encoding.utf8) {
            return string
        }
        return nil
    }
}

// known file types as reported by exiftool. These are the types
// that core graphics can read (usually) and exiftool can write.

extension Exiftool {
    // Last updated to match ExifTool version 12.45

    static private let writableTypes: Set = [
        "360", "3G2", "3GP", "AAX", "AI", "ARQ", "ARW", "AVIF",
        "CR2", "CR3", "CRM", "CRW", "CS1", "DCP", "DNG", "DR4",
        "DVB", "EPS", "ERF", "EXIF", "EXV", "F4A/V", "FFF", "FLIF",
        "GIF", "GLV", "GPR", "HDP", "HEIC", "HEIF", "ICC", "IIQ",
        "IND", "INSP", "JNG", "JP2", "JPEG", "JXL", "LRV", "M4A/V",
        "MEF", "MIE", "MNG", "MOS", "MOV", "MP4", "MPO", "MQV",
        "MRW", "NEF", "NKSC", "NRW", "ORF", "ORI", "PBM", "PDF",
        "PEF", "PGM", "PNG", "PPM", "PS", "PSB", "PSD", "QTIF",
        "RAF", "RAW", "RW2", "RWL", "SR2", "SRW", "THM", "TIFF",
        "VRD", "WDP", "WEBP", "X3F", "XMP"
    ]

    // Return true if the given URL is a known file type.

    public func fileTypeIsWritable(for file: URL) -> Bool {
        let args = [
            "-m", "-q", "-S", "-fast3", "-FileType", file.path
        ]
        // first, believe the file extension
        let ext = file.pathExtension.uppercased()
        if Self.writableTypes.contains(ext) { return true }

        // Ask exiftool what it thinks the type might be and see if
        // it is in the table.
        do {
            let data = try run(args)
            if data.count > 0,
                let str = String(data: data,
                                 encoding: String.Encoding.utf8) {
                let trimmed = str.trimmingCharacters(
                    in: CharacterSet.whitespacesAndNewlines)
                let strparts = trimmed.components(
                    separatedBy: CharacterSet.whitespaces)
                if let filetype = strparts.last {
                    return Self.writableTypes.contains(filetype)
                }
            }
        } catch {
            Self.logger.error(
                "\(#function, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        return false
    }
}

// Use exiftool to create a sidecar file from an image file.
// The sidecar file will be in the same location as the image
// file.

extension Exiftool {
    public func makeSidecar(from imageURL: URL) throws {
        let sidecarURL = imageURL.deletingPathExtension()
            .appendingPathExtension(Metadata.xmpExtension)
        let args = [
            "-tagsfromfile", imageURL.path, sidecarURL.path
        ]
        do {
            // ignore any returned output
            try run(args)
        } catch {
            Self.logger.error(
                "\(#function, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}

// use exiftool to read the contents of a sidecar file and extract
// the metadata needed to create and return an Metadata struct.
// Used as Apple's ImageIO functions can not extract metadata from XMP
// sidecar files.

extension Exiftool {

    // swiftlint:disable cyclomatic_complexity
    public func metadata(from xmp: URL?, primaryURL: URL) -> Metadata {
        let url: URL
        var metadata: Metadata
        if let xmp {
            url = xmp
            metadata = Metadata(source: .xmp(primaryURL))
        } else {
            url = primaryURL
            metadata = Metadata(source: .image(primaryURL))
        }
        let args = [
            "-args", "-c", "%.15f", "-createdate",
            "-gpsstatus", "-gpslatitude", "-gpslongitude",
            "-gpsaltitude", "-gpsmapdatum", "-gpsprocessingmethod", "-xmp:city", "-xmp:state",
            "-xmp:country", "-xmp:countrycode", url.path
        ]

        do {
            let data = try run(args)
            if data.count > 0,
                let str = String(data: data,
                                 encoding: String.Encoding.utf8) {
                var gpsStatus = true
                var lat: Double?
                var lon: Double?
                var ele: Double?
                let strings = str.split(separator: "\n")

                for entry in strings {
                    let key = entry.prefix { $0 != "=" }
                    var value = entry.dropFirst(key.count)
                    if !value.isEmpty {
                        value = value.dropFirst(1)
                    }
                    switch key {
                    case "-CreateDate":
                        // Preserve the explicit offset and subsecond precision.
                        metadata.dateTimeCreated = String(value)
                    case "-GPSStatus":
                        if value.hasSuffix("Void") {
                            gpsStatus = false
                        }
                    case "-GPSLatitude":
                        let parts = value.split(separator: " ")
                        if var latValue = Double(parts[0]),
                           parts.count == 2 {
                            if parts[1] == "S" {
                                latValue = -latValue
                            }
                            lat = latValue
                        }
                    case "-GPSLongitude":
                        let parts = value.split(separator: " ")
                        if var lonValue = Double(parts[0]),
                           parts.count == 2 {
                            if parts[1] == "W" {
                                lonValue = -lonValue
                            }
                            lon = lonValue
                        }
                    case "-GPSAltitude":
                        let parts = value.split(separator: " ")
                        if let eleValue = Double(parts[0]),
                           parts.count >= 3 {
                            ele = parts[2] == "Above" ? eleValue : -eleValue
                        }
                    case "-GPSMapDatum":
                        metadata.gpsMapDatum = String(value)
                    case "-GPSProcessingMethod":
                        metadata.gpsProcessingMethod = String(value)
                    case "-City":
                        metadata.city = String(value)
                    case "-State":
                        metadata.state = String(value)
                    case "-Country":
                        metadata.country = String(value)
                    case "-CountryCode":
                        metadata.countryCode = String(value)
                    default:
                        break
                    }
                }
                if gpsStatus, let lat, let lon {
                    metadata.location =
                        Coords.ifValid(latitude: lat,
                                       longitude: lon)
                    metadata.elevation = ele
                }
            }
        } catch {
            Self.logger.error(
                "\(#function, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        return metadata
    }
    // swiftlint:enable cyclomatic_complexity
}

extension Exiftool {

    // Use the embedded copy of exiftool to update the geolocation metadata
    // in the file referenced by the given URL

    public func update(image: URL,
                       from metadata: Metadata,
                       timeZone: TimeZone?) async throws {
        // ExifTool argument names
        var latArg = "-GPSLatitude="
        var lonArg = "-GPSLongitude="
        var latRefArg = "-GPSLatitudeRef="
        var lonRefArg = "-GPSLongitudeRef="
        var eleArg = "-GPSaltitude="
        var eleRefArg = "-GPSaltitudeRef="
        var cityArg = "-xmp:city="
        var stateArg = "-xmp:state="
        var countryArg = "-xmp:country="
        var countryCodeArg = "-xmp:countryCode="

        // ExifTool GSPDateTime arg storage
        var gpsDArg = "-GPSDateStamp="  // for non XMP files
        var gpsTArg = "-GPSTimeStamp="  // for non XMP files
        var gpsDTArg = "-GPSDateTime="  // for XMP files

        let usingSidecar = image.pathExtension.lowercased() == Metadata.xmpExtension

        // Build ExifTool latitude, longitude, and elevation argument values
        if let location = metadata.location {
            latArg += "\(location.latitude)"
            latRefArg += "\(location.latitude)"
            lonArg += "\(location.longitude)"
            lonRefArg += "\(location.longitude)"
            if let ele = metadata.elevation {
                if ele >= 0 {
                    eleArg += "\(ele)"
                    eleRefArg += "0"
                } else {
                    eleArg += "\(-ele)"
                    eleRefArg += "1"
                }
            }
            cityArg += metadata.city ?? ""
            stateArg += metadata.state ?? ""
            countryArg += metadata.country ?? ""
            countryCodeArg += metadata.countryCode ?? ""
        }

        // build exiftool arguments array
        var args = [
            "-q", "-m", "-overwrite_original_in_place",
            cityArg, stateArg,
            countryArg, countryCodeArg
        ]

        if !metadata.preserveGPSOnSave {
            args += [latArg, latRefArg, lonArg, lonRefArg, eleArg, eleRefArg,
                     "-GPSMapDatum=" + (metadata.gpsMapDatum ?? ""),
                     "-GPSProcessingMethod=" + (metadata.gpsProcessingMethod ?? ""),
                     "-gpsstatus="]
        }

        // add args to update date/time if present
        if let dateTimeCreated = metadata.dateTimeCreated {
            let dtoArg = "-datetimeoriginal=" + dateTimeCreated
            let cdArg = "-createdate=" + dateTimeCreated
            args += [dtoArg, cdArg]
            // and update the file modification date if requested
            @AppStorage(Self.updateFileModificationTimesKey)
            var updateFileModificationTimes = false
            if updateFileModificationTimes {
                let fmd = "-filemodifydate=" + dateTimeCreated
                args += [fmd]
                // note: do not use -filemodifydate<datetimecreated as
                // that will use the current date which might be
                // different than that updated above.
            }
        }

        // user option to update file modify time

        // user option to update GPS timestamp
        @AppStorage(Self.updateGPSTimestampsKey)
        var updateGPSTimestamps = false

        if updateGPSTimestamps,
            let gpsTimestamp = gpsTimestamp(for: metadata.dateTimeCreated,
                                            in: timeZone) {

            // args vary depending upon saving to an image file or a gpx file
            if usingSidecar {
                gpsDTArg += gpsTimestamp
                args += [gpsDTArg]
            } else {
                let dtargs = gpsTimestamp.split(separator: " ")
                gpsDArg += dtargs[0]
                gpsTArg += dtargs[1]
                args += [gpsDArg, gpsTArg]
            }
        }

        args.append(image.path)

        try run(args)
    }

    // convert the dateTimeCreated string to a string with time zone to
    // update GPS timestamp fields.  Return nil if there is
    // no timestamp or formatting failed.

    func gpsTimestamp(for dateTime: String?,
                      in timeZone: TimeZone?) -> String? {
        if let dateTime {
            dateFormatter.dateFormat = Metadata.dateFormat
            dateFormatter.timeZone = timeZone
            if let date = dateFormatter.date(from: dateTime) {
                dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
                return dateFormatter.string(from: date) + "Z"
            }
        }
        return nil
    }
}

// Test support functions. Extract the GPS Timestamp if present
extension Exiftool {
    public func getGPSTimestamp(for url: URL) async throws -> String? {
        var args = [
            "-q", "-m", "-s3", "-GPSDateTime"
        ]
        args += [url.path]
        let data = try run(args)
        if data.count > 0 {
            let string = String(data: data, encoding: String.Encoding.utf8)
            return string
        }
        return nil
    }
}

// Common code to call Exiftool with given arguments
// returns any data read; might be zero sized

extension Exiftool {
    private final class ProcessOutput: @unchecked Sendable {
        private let lock = NSLock()
        private var stdout = Data()
        private var stderr = Data()

        func setStdout(_ data: Data) {
            lock.withLock { stdout = data }
        }

        func setStderr(_ data: Data) {
            lock.withLock { stderr = data }
        }

        func data() -> (stdout: Data, stderr: Data) {
            lock.withLock { (stdout, stderr) }
        }
    }

    @discardableResult
    func run(_ args: [String]) throws -> Data {
        #if LOG_ARGS
        Self.logger.info("\(args, privacy: .public)")
        #endif
        let exiftool = Process()
        let pipe = Pipe()
        let err = Pipe()
        exiftool.standardOutput = pipe
        exiftool.standardError = err
        exiftool.executableURL = url
        exiftool.arguments = args
        try exiftool.run()

        let output = ProcessOutput()
        let stderrFinished = DispatchSemaphore(value: 0)
        // A dedicated reader must progress even when every cooperative worker is
        // blocked in run(). Both pipes are drained before waiting for the result.
        Thread.detachNewThread {
            output.setStderr(err.fileHandleForReading.readDataToEndOfFile())
            stderrFinished.signal()
        }
        output.setStdout(pipe.fileHandleForReading.readDataToEndOfFile())
        exiftool.waitUntilExit()
        stderrFinished.wait()
        let data = output.data()
        log(data.stderr)
        let status = Int(exiftool.terminationStatus)
        if exiftool.terminationStatus != 0 {
            throw ExiftoolError.runFailed(code: status)
        }
        return data.stdout
    }

    // Write stderr data to the log.

    private func log(_ data: Data) {
        if data.count > 0,
            let string = String(data: data, encoding: String.Encoding.utf8) {
            Self.logger.warning("stderr: \(string, privacy: .public)")
        }
    }
}

// Exiftool update defaults keys

extension Exiftool {
    public static let updateFileModificationTimesKey = "UpdateFileModificationTimes"
    public static let updateGPSTimestampsKey = "UpdateGPSTimestamps"
}
