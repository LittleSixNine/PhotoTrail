import Foundation
import Metadata
import Testing
@testable import Exiftool

struct MetadataTagTests {
    @Test func captureDateWritesAndClearsItsPrecisionGroupOnly() throws {
        let fixture = try #require(Bundle.module.url(forResource: "alldata", withExtension: "jpg"))
        let folder = try makeTestFolder(andCopy: fixture)
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = folder.appending(component: fixture.lastPathComponent)
        let before = try textValue("ImageDataMD5", from: image)
        let date = "2024:02:29 23:59:59.123456+08:00"
        let changed = try Exiftool.helper.update(image: image, changes: [.captureDate: .set(.text(date)), .titleDefault: .remove])
        #expect(changed[.captureDate] == .text(date))
        #expect(try textValue("ExifIFD:SubSecTimeOriginal", from: image) == "123456")
        #expect(try textValue("ExifIFD:OffsetTimeOriginal", from: image) == "+08:00")
        let plain = "2024:03:01 00:00:00"
        #expect(try Exiftool.helper.update(image: image, changes: [.captureDate: .set(.text(plain))])[.captureDate] == .text(plain))
        _ = try Exiftool.helper.update(image: image, changes: [.captureDate: .remove])
        #expect(try textValue("ExifIFD:DateTimeOriginal", from: image) == nil)
        #expect(try textValue("ExifIFD:SubSecTimeOriginal", from: image) == nil)
        #expect(try textValue("ExifIFD:OffsetTimeOriginal", from: image) == nil)
        #expect(try textValue("ImageDataMD5", from: image) == before)
    }

    @Test(.timeLimit(.minutes(1)))
    func concurrentProcessReadersCannotStarveCooperativeWorkers() async throws {
        try await withThrowingTaskGroup(of: String?.self) { group in
            for _ in 0..<16 { group.addTask { try Exiftool.helper.version() } }
            for try await version in group { #expect(version?.isEmpty == false) }
        }
    }

    @Test(arguments: [("alldata", "jpg"), ("262M1559", "xmp"), ("IMG_5654", "HEIC")])
    func advancedFieldsRoundTripPreservesProtectedPayload(name: String, ext: String) throws {
        let fixture = try #require(Bundle.module.url(forResource: name, withExtension: ext))
        let folder = try makeTestFolder(andCopy: fixture)
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = folder.appending(component: fixture.lastPathComponent)
        try Exiftool.helper.run(["-q", "-overwrite_original_in_place", "-XMP-xmp:Rating=4",
                                 "-XMP-dc:Title-fr=bonjour", "-XMP-lr:HierarchicalSubject=keep|tree", image.path])
        let unrelatedBefore = try Exiftool.helper.run(["-j", "-G1", "-XMP-xmp:Rating", "-XMP-dc:Title-fr",
                                                       "-XMP-lr:HierarchicalSubject", image.path])
        let before = try protectedMetadata(from: image)
        let payload = try textValue("ImageDataMD5", from: image)
        if ext != "xmp" { #expect(payload != nil) }
        let changes: [MetadataTag: MetadataTagChange] = [
            .titleDefault: .set(.text("123")), .creator: .set(.list(["42", "é", "e\u{301}"])),
            .dateOriginal: .set(.text("2024:02:29 23:59:59.123456+08:00")),
            .dateDigitized: .set(.text("2024:02:29 23:59:59")),
            .dateModified: .set(.text("2024:02:29 23:59:59Z")),
            .make: .set(.text("Olympus")), .model: .set(.text("35EC")), .lens: .set(.text("E. Zuiko 42 mm f/2.8")),
            .exposureTime: .set(.text("0.008")), .fNumber: .set(.text("2.8")), .iso: .set(.text("400")),
            .focalLength: .set(.text("42")), .exposureBias: .set(.text("-0.5")),
            .exposureProgram: .set(.text("3")), .whiteBalance: .set(.text("1"))
        ]
        let readback = try Exiftool.helper.update(image: image, changes: changes)
        #expect(readback.count == changes.count)
        #expect(try protectedMetadata(from: image) == before)
        #expect(try Exiftool.helper.run(["-j", "-G1", "-XMP-xmp:Rating", "-XMP-dc:Title-fr",
                                        "-XMP-lr:HierarchicalSubject", image.path]) == unrelatedBefore)
        if let payload { #expect(try textValue("ImageDataMD5", from: image) == payload) }
        let exported = try Exiftool.helper.xmpData(from: image)
        let exportURL = folder.appending(component: "export.xmp")
        try exported.write(to: exportURL)
        #expect(try Exiftool.helper.metadataTags(Set(changes.keys), from: exportURL) == readback)
        _ = try Exiftool.helper.update(image: image, changes: Dictionary(uniqueKeysWithValues: changes.keys.map { ($0, .remove) }))
        #expect(try Exiftool.helper.metadataTags(Set(changes.keys), from: image).isEmpty)
        #expect(try protectedMetadata(from: image) == before)
    }

    @Test func legacyCreatorReadKeepsSourcesSeparateAndDoesNotWrite() throws {
        let fixture = try #require(
            Bundle.module.url(forResource: "alldata", withExtension: "jpg"))
        let folder = try makeTestFolder(andCopy: fixture)
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = folder.appending(component: fixture.lastPathComponent)
        try Exiftool.helper.run([
            "-q", "-overwrite_original_in_place",
            "-EXIF:Artist=EXIF Alice", "-IPTC:By-line=IPTC Bob", image.path
        ])
        let beforeRead = try Data(contentsOf: image)

        let values = try Exiftool.helper.legacyCreatorTags(from: image)

        #expect(values[.exifArtist] == ["EXIF Alice"])
        #expect(values[.iptcByline] == ["IPTC Bob"])
        #expect(try Exiftool.helper.metadataTags([.creator], from: image)[.creator]
                == .list(["Marco S Hyman"]))
        #expect(try Data(contentsOf: image) == beforeRead)
    }

    func protectedMetadata(from image: URL) throws -> Data {
        try Exiftool.helper.run([
            "-j", "-G1", "-n", "-EXIF:All", "-ICC_Profile:All",
            "-MakerNotes:All", image.path
        ])
    }

    func textValue(_ tag: String, from image: URL) throws -> String? {
        let data = try Exiftool.helper.run(["-s3", "-\(tag)", image.path])
        guard var value = String(data: data, encoding: .utf8), !value.isEmpty else {
            return nil
        }
        if value.last == "\n" { value.removeLast() }
        return value.isEmpty ? nil : value
    }

    @Test func creatorSetReadbackAndRemovalAffectOnlyRequestedTag() async throws {
        let image = try #require(
            Bundle.module.url(forResource: "262M1559", withExtension: "DNG"))
        let xmp = try #require(
            Bundle.module.url(forResource: "262M1559", withExtension: "xmp"))
        let folder = try makeTestFolder(andCopy: image)
        defer { try? FileManager.default.removeItem(at: folder) }
        let imageCopy = folder.appending(component: image.lastPathComponent)
        let xmpCopy = folder.appending(component: xmp.lastPathComponent)
        try FileManager.default.copyItem(at: xmp, to: xmpCopy)
        let metadataBefore = Exiftool.helper.metadata(from: xmpCopy,
                                                      primaryURL: imageCopy)
        let creators = ["六九，摄影师\n第二行", "Alice \"A\""]

        let setReadback = try Exiftool.helper.update(
            image: xmpCopy, changes: [.creator: .set(.list(creators))])

        #expect(setReadback[.creator] == .list(creators))
        #expect(Exiftool.helper.metadata(from: xmpCopy,
                                        primaryURL: imageCopy) == metadataBefore)

        let removeReadback = try Exiftool.helper.update(
            image: xmpCopy, changes: [.creator: .remove])

        #expect(removeReadback[.creator] == nil)
        #expect(Exiftool.helper.metadata(from: xmpCopy,
                                        primaryURL: imageCopy) == metadataBefore)
    }

    @Test func tagsRejectInvalidValues() throws {
        let xmp = try #require(
            Bundle.module.url(forResource: "262M1559", withExtension: "xmp"))
        #expect(throws: Exiftool.ExiftoolError.self) {
            try Exiftool.helper.update(image: xmp,
                                       changes: [.creator: .set(.list([]))])
        }
        #expect(throws: Exiftool.ExiftoolError.self) {
            try Exiftool.helper.update(
                image: xmp, changes: [.descriptionDefault: .set(.text(""))])
        }
        #expect(throws: Exiftool.ExiftoolError.self) {
            try Exiftool.helper.update(
                image: xmp, changes: [.creator: .set(.text("Alice"))])
        }
    }

    @Test func updateClassifiesWriteAndReadbackFailures() throws {
        enum ControlledFailure: Error { case write, readback }
        let fixture = try #require(
            Bundle.module.url(forResource: "262M1559", withExtension: "xmp"))
        let folder = try makeTestFolder(andCopy: fixture)
        defer { try? FileManager.default.removeItem(at: folder) }
        let xmp = folder.appending(component: fixture.lastPathComponent)

        do {
            _ = try Exiftool.helper.update(
                image: xmp,
                changes: [.creator: .set(.list(["Alice"]))],
                write: { _ in throw ControlledFailure.write },
                readback: { _, _ in [:] })
            Issue.record("Expected write failure")
        } catch let error as MetadataTagUpdateError {
            guard case .writeFailed = error else {
                Issue.record("Expected write failure, got \(error)")
                return
            }
            #expect(error.resultIsUnknown)
        }

        do {
            _ = try Exiftool.helper.update(
                image: xmp,
                changes: [.creator: .set(.list(["Alice"]))],
                write: { _ in },
                readback: { _, _ in [.creator: .list(["Bob"])] })
            Issue.record("Expected readback mismatch")
        } catch let error as MetadataTagUpdateError {
            guard case .readbackMismatch(tag: .creator) = error else {
                Issue.record("Expected creator mismatch, got \(error)")
                return
            }
            #expect(error.resultIsUnknown)
        }

        let finalSubjects = ["existing", "appended"]

        do {
            _ = try Exiftool.helper.update(
                image: xmp,
                changes: [.subject: .set(.list(finalSubjects))],
                write: { try Exiftool.helper.run($0) },
                readback: { _, _ in throw ControlledFailure.readback })
            Issue.record("Expected readback failure")
        } catch let error as MetadataTagUpdateError {
            guard case .readbackFailed = error else {
                Issue.record("Expected readback failure, got \(error)")
                return
            }
            #expect(error.resultIsUnknown)
        }

        // Reconcile the absolute final value after an unknown result. Do not
        // replay the relative append that produced it.
        let reconciled = try Exiftool.helper.metadataTags([.subject], from: xmp)
        #expect(reconciled[.subject] == .list(finalSubjects))
    }

    @Test func defaultLanguageTextPreservesOtherLanguagesAndSubjectRoundTrips() throws {
        let image = try #require(
            Bundle.module.url(forResource: "262M1559", withExtension: "DNG"))
        let xmp = try #require(
            Bundle.module.url(forResource: "262M1559", withExtension: "xmp"))
        let folder = try makeTestFolder(andCopy: image)
        defer { try? FileManager.default.removeItem(at: folder) }
        let xmpCopy = folder.appending(component: xmp.lastPathComponent)
        try FileManager.default.copyItem(at: xmp, to: xmpCopy)
        let imageCopy = folder.appending(component: image.lastPathComponent)
        let imageBytesBefore = try Data(contentsOf: imageCopy)
        let protectedBefore = try protectedMetadata(from: imageCopy)
        try Exiftool.helper.run([
            "-q", "-overwrite_original_in_place",
            "-XMP-dc:Title-x-default=Original title",
            "-XMP-dc:Title-zh-CN=原始标题",
            "-XMP-dc:Description-x-default=Original default",
            "-XMP-dc:Description-zh-CN=原始中文",
            "-XMP-dc:Description-en-US=Original English",
            "-XMP-dc:Rights-x-default=Original rights",
            "-XMP-dc:Rights-zh-CN=原始版权",
            xmpCopy.path
        ])
        let creatorBefore = try Exiftool.helper
            .metadataTags([.creator], from: xmpCopy)[.creator]
        let chineseBefore = try textValue("XMP-dc:Description-zh-CN",
                                          from: xmpCopy)
        let englishBefore = try textValue("XMP-dc:Description-en-US",
                                          from: xmpCopy)
        let titleChineseBefore = try textValue("XMP-dc:Title-zh-CN", from: xmpCopy)
        let rightsChineseBefore = try textValue("XMP-dc:Rights-zh-CN", from: xmpCopy)
        let title = "新标题"
        let description = "更新，含逗号\n第二行"
        let rights = "© 2026 六九"
        let subjects = ["Travel", "travel", "北京", "é", "e\u{301}",
                        "comma,word", "line\nbreak"]

        let setReadback = try Exiftool.helper.update(image: xmpCopy,
            changes: [
                .titleDefault: .set(.text(title)),
                .descriptionDefault: .set(.text(description)),
                .rightsDefault: .set(.text(rights)),
                .subject: .set(.list(subjects))
            ])

        #expect(setReadback[.titleDefault] == .text(title))
        #expect(setReadback[.descriptionDefault] == .text(description))
        #expect(setReadback[.rightsDefault] == .text(rights))
        #expect(setReadback[.subject] == .list(subjects))
        #expect(try textValue("XMP-dc:Title-zh-CN", from: xmpCopy) == titleChineseBefore)
        #expect(try textValue("XMP-dc:Description-zh-CN", from: xmpCopy) == chineseBefore)
        #expect(try textValue("XMP-dc:Description-en-US", from: xmpCopy) == englishBefore)
        #expect(try textValue("XMP-dc:Rights-zh-CN", from: xmpCopy) == rightsChineseBefore)
        #expect(try Exiftool.helper.metadataTags([.creator], from: xmpCopy)[.creator] == creatorBefore)
        #expect(try Data(contentsOf: imageCopy) == imageBytesBefore)
        #expect(try protectedMetadata(from: imageCopy) == protectedBefore)

        let removeReadback = try Exiftool.helper.update(image: xmpCopy,
            changes: [
                .titleDefault: .remove,
                .descriptionDefault: .remove,
                .rightsDefault: .remove,
                .subject: .remove
            ])

        #expect(removeReadback[.titleDefault] == nil)
        #expect(removeReadback[.descriptionDefault] == nil)
        #expect(removeReadback[.rightsDefault] == nil)
        #expect(removeReadback[.subject] == nil)
        #expect(try textValue("XMP-dc:Title-zh-CN", from: xmpCopy) == titleChineseBefore)
        #expect(try textValue("XMP-dc:Description-zh-CN", from: xmpCopy) == chineseBefore)
        #expect(try textValue("XMP-dc:Description-en-US", from: xmpCopy) == englishBefore)
        #expect(try textValue("XMP-dc:Rights-zh-CN", from: xmpCopy) == rightsChineseBefore)
        #expect(try Exiftool.helper.metadataTags([.creator], from: xmpCopy)[.creator] == creatorBefore)
        #expect(try Data(contentsOf: imageCopy) == imageBytesBefore)
        #expect(try protectedMetadata(from: imageCopy) == protectedBefore)
    }

    @Test(arguments: [
        ("alldata", "jpg"),
        ("IMG_5654", "HEIC")
    ])
    func editableTagsRoundTripInImageFile(name: String,
                                          extension ext: String) throws {
        let fixture = try #require(
            Bundle.module.url(forResource: name, withExtension: ext))
        let folder = try makeTestFolder(andCopy: fixture)
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = folder.appending(component: fixture.lastPathComponent)
        let protectedBefore = try protectedMetadata(from: image)
        let metadataBefore = Exiftool.helper.metadata(from: nil,
                                                      primaryURL: image)
        let creators = ["六九，摄影师\n第二行", "Alice \"A\""]
        let description = "说明，第二行\n包含中文"
        let subjects = ["Travel", "北京", "comma,word", "line\nbreak"]

        let setReadback = try Exiftool.helper.update(
            image: image, changes: [
                .creator: .set(.list(creators)),
                .descriptionDefault: .set(.text(description)),
                .subject: .set(.list(subjects))
            ])

        #expect(setReadback[.creator] == .list(creators))
        #expect(setReadback[.descriptionDefault] == .text(description))
        #expect(setReadback[.subject] == .list(subjects))
        #expect(try protectedMetadata(from: image) == protectedBefore)
        #expect(Exiftool.helper.metadata(from: nil,
                                        primaryURL: image) == metadataBefore)

        let removeReadback = try Exiftool.helper.update(
            image: image, changes: [
                .creator: .remove,
                .descriptionDefault: .remove,
                .subject: .remove
            ])

        #expect(removeReadback[.creator] == nil)
        #expect(removeReadback[.descriptionDefault] == nil)
        #expect(removeReadback[.subject] == nil)
        #expect(try protectedMetadata(from: image) == protectedBefore)
        #expect(Exiftool.helper.metadata(from: nil,
                                        primaryURL: image) == metadataBefore)
    }
}

extension MetadataTagTests {
    @Test func nativeCameraTypesDatesAndEnumsPreserveOtherSources() throws {
        let fixture = try #require(Bundle.module.url(forResource: "alldata", withExtension: "jpg"))
        let folder = try makeTestFolder(andCopy: fixture)
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = folder.appending(component: fixture.lastPathComponent)
        let payload = try textValue("ImageDataMD5", from: image)
        let xmp = try Exiftool.helper.metadataTags(Set(MetadataTag.allCases.filter(\.supportsSidecar)), from: image)
        let originalDate = try Exiftool.helper.metadataTags([.captureDate], from: image)
        let changes: [MetadataTag: MetadataTagChange] = [
            .exifMake: .set(.text("Olympus")), .exifModel: .set(.text("35EC")), .exifSerial: .set(.text("123")),
            .exifLensMake: .set(.text("Olympus")), .exifLensModel: .set(.text("42mm")), .exifLensSerial: .set(.text("456")),
            .exifExposureTime: .set(.text("0.008")), .exifFNumber: .set(.text("2.8")), .exifISO: .set(.text("400")),
            .exifAperture: .set(.text("2.8")), .exifShutter: .set(.text("0.008")), .exifFocalLength: .set(.text("42")),
            .exifFocal35: .set(.text("42")), .exifExposureBias: .set(.text("-0.5")), .exifFlash: .set(.text("0")),
            .exifColorSpace: .set(.text("65535")), .exifMaxAperture: .set(.text("2.8")), .exifExposureMode: .set(.text("2")),
            .exifExposureProgram: .set(.text("3")), .exifMeteringMode: .set(.text("5")), .exifWhiteBalance: .set(.text("1")),
            .exifSaturation: .set(.text("1")), .exifSharpness: .set(.text("2")),
            .exifCreateDate: .set(.text("2024:02:29 23:59:59.123456+08:00")),
            .exifModifyDate: .set(.text("2024:03:01 00:00:00.123456Z"))
        ]
        #expect(try Exiftool.helper.update(image: image, changes: changes).count == changes.count)
        #expect(try Exiftool.helper.metadataTags(Set(MetadataTag.allCases.filter(\.supportsSidecar)), from: image) == xmp)
        #expect(try Exiftool.helper.metadataTags([.captureDate], from: image) == originalDate)
        #expect(try textValue("ImageDataMD5", from: image) == payload)
        _ = try Exiftool.helper.update(image: image, changes: Dictionary(uniqueKeysWithValues: changes.keys.map { ($0, .remove) }))
        #expect(try Exiftool.helper.metadataTags(Set(changes.keys), from: image).isEmpty)
        #expect(throws: Exiftool.ExiftoolError.self) { try MetadataTag.exifColorSpace.checkedText("2") }
        #expect(throws: Exiftool.ExiftoolError.self) { try MetadataTag.exifISO.checkedText("65536") }
        #expect(throws: Exiftool.ExiftoolError.self) { try MetadataTag.exifMeteringMode.checkedText("7") }
    }

    @Test func nativeTextSourcesRemainIndependentAndPreservePixels() throws {
        let fixture = try #require(Bundle.module.url(forResource: "alldata", withExtension: "jpg"))
        let folder = try makeTestFolder(andCopy: fixture)
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = folder.appending(component: fixture.lastPathComponent)
        try Exiftool.helper.run(["-q", "-overwrite_original_in_place", "-IPTC:all=", image.path])
        let payload = try textValue("ImageDataMD5", from: image)
        let xmp = try Exiftool.helper.metadataTags([.creator, .subject, .titleDefault], from: image)
        let changes: [MetadataTag: MetadataTagChange] = [
            .exifArtist: .set(.text("六九，EXIF作者")), .exifDescription: .set(.text("EXIF说明\n第二行")),
            .exifCopyright: .set(.text("© 六九")), .exifSoftware: .set(.text("PhotoTrail")),
            .exifComment: .set(.text("中文注释")), .iptcByline: .set(.list(["作者甲", "作者乙"])),
            .iptcBylineTitle: .set(.list(["摄影师", "编辑"])), .iptcContact: .set(.list(["hello@example.com", "second@example.com"])),
            .iptcHeadline: .set(.text("IPTC标题")), .iptcCaption: .set(.text("IPTC说明")),
            .iptcObjectName: .set(.text("对象")), .iptcKeywords: .set(.list(["旅行", "夜景"])),
            .iptcCity: .set(.text("北京")), .iptcProvince: .set(.text("北京")),
            .iptcLocation: .set(.text("街道")), .iptcCountry: .set(.text("中国")),
            .iptcCountryCode: .set(.text("CHN"))
        ]
        #expect(try Exiftool.helper.update(image: image, changes: changes).count == changes.count)
        #expect(try Exiftool.helper.metadataTags([.creator, .subject, .titleDefault], from: image) == xmp)
        #expect(try textValue("ImageDataMD5", from: image) == payload)
        _ = try Exiftool.helper.update(image: image, changes: Dictionary(uniqueKeysWithValues: changes.keys.map { ($0, .remove) }))
        #expect(try Exiftool.helper.metadataTags(Set(changes.keys), from: image).isEmpty)
        try Exiftool.helper.run(["-q", "-overwrite_original_in_place", "-IPTC:all=", "-IPTC:Headline=legacy", image.path])
        let legacyBefore = try Data(contentsOf: image)
        #expect(throws: Exiftool.ExiftoolError.self) {
            try Exiftool.helper.update(image: image, changes: [.iptcHeadline: .set(.text("新标题"))])
        }
        #expect(try Data(contentsOf: image) == legacyBefore)
        #expect(throws: Exiftool.ExiftoolError.self) { try MetadataTag.iptcByline.checkedText(String(repeating: "中", count: 11)) }
        #expect(throws: Exiftool.ExiftoolError.self) { try MetadataTag.iptcCountryCode.checkedText("CN") }
        let sidecar = folder.appending(component: "empty.xmp")
        try Data("<x:xmpmeta xmlns:x=\"adobe:ns:meta/\"/>".utf8).write(to: sidecar)
        let before = try Data(contentsOf: sidecar)
        #expect(throws: Exiftool.ExiftoolError.self) {
            try Exiftool.helper.update(image: sidecar, changes: [.exifArtist: .set(.text("wrong"))])
        }
        #expect(try Data(contentsOf: sidecar) == before)
    }

}
