import Foundation
import Testing
@testable import Exiftool

struct MetadataDisplaySectionTests {
    @Test(arguments: [("alldata", "jpg"), ("262M1559", "xmp")])
    func standardReadKeepsReferenceValuesWithoutLoadingUnlistedFamilies(name: String, ext: String) throws {
        let image = try #require(Bundle.module.url(forResource: name, withExtension: ext))
        let standard = try Exiftool.helper.inspectionTags(from: image, additional: false)
        let full = try Exiftool.helper.inspectionTags(from: image)
        for tag in MetadataDisplaySection.standard.flatMap(\.tags) {
            #expect(MetadataDisplaySection.value(for: tag, in: standard)
                    == MetadataDisplaySection.value(for: tag, in: full), Comment(rawValue: tag))
        }
        #expect(standard.count < full.count)
        #expect(standard["File:FileType"] == nil)
        #expect(full["File:FileType"] != nil)
    }

    @Test func completeInspectionIncludesFileAndDistinctMetadataSourcesWithoutWriting() throws {
        let image = try #require(Bundle.module.url(forResource: "alldata", withExtension: "jpg"))
        let before = try Data(contentsOf: image)
        let values = try Exiftool.helper.inspectionTags(from: image)
        #expect(MetadataDisplaySection.value(for: "File:FileName", in: values) == "alldata.jpg")
        #expect(MetadataDisplaySection.value(for: "File:FileCreateDate", in: values) != nil)
        #expect(MetadataDisplaySection.value(for: "EXIF:Make", in: values) != nil)
        #expect(MetadataDisplaySection.value(for: "EXIF:Artist", in: values) != nil)
        #expect(MetadataDisplaySection.value(for: "IPTC:By-line", in: values) != nil)
        #expect(values.keys.contains { $0.hasPrefix("ICC_Profile:") })
        #expect(values.keys.contains { $0.hasPrefix("Photoshop:") })
        #expect(values.keys.contains { $0.hasPrefix("Composite:") })
        #expect(values.keys.contains { $0.contains(":Copy1:") })
        #expect(try Data(contentsOf: image) == before)
    }

    @Test func referenceSchemaAndSourceResolutionStayDistinct() {
        let fields = MetadataDisplaySection.standard.flatMap(\.tags)
        #expect(MetadataDisplaySection.standard.count == 11)
        #expect(fields.count == 73)
        #expect(Set(fields).count == 73)
        let values = ["IFD0:Artist": "EXIF", "IPTC:By-line": "IPTC", "XMP-dc:Creator": "XMP",
                      "IFD0:ImageWidth": "4000", "ExifIFD:ExifImageWidth": "3998",
                      "IFD1:ImageWidth": "160", "XMP-dc:Subject": "subject", "XMP-mediapro:Keyword": "keyword"]
        #expect(MetadataDisplaySection.value(for: "EXIF:Artist", in: values) == "EXIF")
        #expect(MetadataDisplaySection.value(for: "IPTC:By-line", in: values) == "IPTC")
        #expect(MetadataDisplaySection.value(for: "XMP:Subject", in: values) == "subject")
        #expect(MetadataDisplaySection.value(for: "XMP:Keyword", in: values) == "keyword")
        #expect(MetadataDisplaySection.value(for: "EXIF:ExifImageWidth", in: values) == "3998")
        #expect(MetadataDisplaySection.value(for: "EXIF:ImageWidth", in: values)?.contains("IFD1:ImageWidth: 160") == true)
        #expect(MetadataDisplaySection.value(for: "EXIF:Make", in: values) == nil)
        #expect(Exiftool.inspectionKey("MakerNotes:Canon:ISO") == "Canon:ISO")
        #expect(Exiftool.inspectionKey("Composite:Copy1:ISO") == "Composite:Copy1:ISO")
        #expect(Exiftool.inspectionKey("EXIF:IFD0:Copy1:Artist") == "IFD0:Copy1:Artist")
        let copies = ["Canon:ISO": "100", "Canon:Copy1:ISO": "200"]
        #expect(MetadataDisplaySection.sourceKeys(for: "Canon:ISO", in: copies).count == 2)
        #expect(MetadataDisplaySection.value(for: "Canon:ISO", in: copies)?.contains("200") == true)
        let sidecar = ["Image/IFD0:Make": "Original", "XMP-tiff:Make": "Sidecar", "Image/XMP-tiff:Make": "Ignore"]
        #expect(MetadataDisplaySection.value(for: "EXIF:Make", in: sidecar) == "Original")
        #expect(MetadataDisplaySection.value(for: "XMP:Make", in: sidecar) == "Sidecar")
        let detailed = ["Image/IFD0:Make": "Original", "Image/File:FileType": "JPEG",
                        "File:FileType": "XMP", "XMP-crs:Exposure2012": "0.5"]
        #expect(MetadataDisplaySection.value(for: "File:FileType", in: detailed) == "JPEG")
        #expect(MetadataDisplaySection.value(for: "File:FileType", in: detailed, exactSource: true) == "XMP")
        #expect(MetadataDisplaySection.value(for: "Image/IFD0:Make", in: detailed, exactSource: true) == "Original")
        #expect(MetadataDisplaySection.value(for: "XMP-crs:Exposure2012", in: detailed, exactSource: true) == "0.5")
    }

    @Test func aggregationPreservesMissingMixedAndExactUnicode() {
        #expect(MetadataDisplaySection.summarize([nil, nil]) == .absent)
        #expect(MetadataDisplaySection.summarize(["", ""]) == .uniform(""))
        #expect(MetadataDisplaySection.summarize(["A", "A"]) == .uniform("A"))
        #expect(MetadataDisplaySection.summarize(["A", nil]) == .mixed(present: 1, total: 2))
        #expect(MetadataDisplaySection.summarize(["é", "e\u{301}"]) == .mixed(present: 2, total: 2))
    }
}
