import Exiftool
import Foundation
import ImageData
import Metadata

// Legacy location writes always include XMP region fields; preserve their independent source values.
struct RegionSaveSnapshot: Sendable {
    let writing: Metadata
    let published: Metadata
    private let target: URL
    private let version: MetadataInspectionFileVersion

    init(_ snapshot: Metadata, original: Metadata?) throws {
        let imageURL: URL
        switch snapshot.source {
        case .image(let url), .xmp(let url): imageURL = url
        case .photos, .copy: throw MetadataInspectionError.sourceChanged
        }
        if case .xmp = snapshot.source {
            target = imageURL.deletingPathExtension().appendingPathExtension("xmp")
        } else {
            target = imageURL
        }
        version = MetadataInspectionFileVersion.read(target)
        guard case .file = version else { throw MetadataInspectionError.sourceChanged }
        var writing = snapshot
        var published = snapshot
        // Clearing a previously present location intentionally clears its associated regions.
        if snapshot.location != nil || original?.location == nil {
            let fields: [(WritableKeyPath<Metadata, String?>, String, String)] = [
                (\.city, "XMP-photoshop:City", "IPTC:City"),
                (\.state, "XMP-photoshop:State", "IPTC:Province-State"),
                (\.sublocation, "XMP-iptcCore:Location", "IPTC:Sub-location"),
                (\.country, "XMP-photoshop:Country", "IPTC:Country-PrimaryLocationName"),
                (\.countryCode, "XMP-iptcCore:CountryCode", "IPTC:Country-PrimaryLocationCode")
            ]
            let values = try Exiftool.helper.inspectionTags(from: target)
            for (field, xmpTag, iptcTag) in fields {
                let xmp = try Self.regionValue(xmpTag, in: values).flatMap { Self.nonblank($0) ? $0 : nil }
                let iptc = try Self.regionValue(iptcTag, in: values).flatMap { Self.nonblank($0) ? $0 : nil }
                if let existing = iptc ?? xmp,
                   !Self.nonblank(original?[keyPath: field]) || !Self.nonblank(snapshot[keyPath: field]) {
                    published[keyPath: field] = existing
                }
                if let xmp { writing[keyPath: field] = xmp }
                else { writing[keyPath: field] = published[keyPath: field] }
            }
        }
        self.writing = writing
        self.published = published
        try validate()
    }

    func validate() throws {
        guard MetadataInspectionFileVersion.read(target) == version else {
            throw MetadataInspectionError.sourceChanged
        }
    }

    static func regionValue(_ tag: String, in values: [String: String]) throws -> String? {
        let wanted = tag.split(separator: ":")
        guard wanted.count == 2 else { throw Exiftool.ExiftoolError.invalidTagOutput }
        var matches = Set<String>()
        for (key, value) in values {
            let parts = key.split(separator: ":")
            guard parts.count >= 2, parts.first == wanted[0], parts.last == wanted[1],
                  parts.dropFirst().dropLast().allSatisfy({ part in
                      part.hasPrefix("Copy") && !part.dropFirst(4).isEmpty && part.dropFirst(4).allSatisfy(\.isNumber)
                  }) else { continue }
            matches.insert(value)
        }
        guard matches.count <= 1 else { throw Exiftool.ExiftoolError.invalidTagOutput }
        return matches.first
    }

    private static func nonblank(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}
