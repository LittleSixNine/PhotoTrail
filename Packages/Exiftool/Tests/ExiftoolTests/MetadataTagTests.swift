import Foundation
import Metadata
import Testing
@testable import Exiftool

struct MetadataTagTests {
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

    @Test func defaultDescriptionPreservesLanguagesAndSubjectRoundTrips() throws {
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
            "-XMP-dc:Description-x-default=Original default",
            "-XMP-dc:Description-zh-CN=原始中文",
            "-XMP-dc:Description-en-US=Original English",
            xmpCopy.path
        ])
        let creatorBefore = try Exiftool.helper
            .metadataTags([.creator], from: xmpCopy)[.creator]
        let chineseBefore = try textValue("XMP-dc:Description-zh-CN",
                                          from: xmpCopy)
        let englishBefore = try textValue("XMP-dc:Description-en-US",
                                          from: xmpCopy)
        let description = "更新，含逗号\n第二行"
        let subjects = ["Travel", "travel", "北京", "é", "e\u{301}",
                        "comma,word", "line\nbreak"]

        let setReadback = try Exiftool.helper.update(image: xmpCopy,
            changes: [
                .descriptionDefault: .set(.text(description)),
                .subject: .set(.list(subjects))
            ])

        #expect(setReadback[.descriptionDefault] == .text(description))
        #expect(setReadback[.subject] == .list(subjects))
        #expect(try textValue("XMP-dc:Description-zh-CN", from: xmpCopy) == chineseBefore)
        #expect(try textValue("XMP-dc:Description-en-US", from: xmpCopy) == englishBefore)
        #expect(try Exiftool.helper.metadataTags([.creator], from: xmpCopy)[.creator] == creatorBefore)
        #expect(try Data(contentsOf: imageCopy) == imageBytesBefore)
        #expect(try protectedMetadata(from: imageCopy) == protectedBefore)

        let removeReadback = try Exiftool.helper.update(image: xmpCopy,
            changes: [
                .descriptionDefault: .remove,
                .subject: .remove
            ])

        #expect(removeReadback[.descriptionDefault] == nil)
        #expect(removeReadback[.subject] == nil)
        #expect(try textValue("XMP-dc:Description-zh-CN", from: xmpCopy) == chineseBefore)
        #expect(try textValue("XMP-dc:Description-en-US", from: xmpCopy) == englishBefore)
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
