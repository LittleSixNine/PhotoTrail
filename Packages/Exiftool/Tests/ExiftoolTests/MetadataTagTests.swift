import Foundation
import Metadata
import Testing
@testable import Exiftool

struct MetadataTagTests {
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
            image: xmpCopy, changes: [.creator: .set(creators)])

        #expect(setReadback[.creator] == creators)
        #expect(Exiftool.helper.metadata(from: xmpCopy,
                                        primaryURL: imageCopy) == metadataBefore)

        let removeReadback = try Exiftool.helper.update(
            image: xmpCopy, changes: [.creator: .remove])

        #expect(removeReadback[.creator] == nil)
        #expect(Exiftool.helper.metadata(from: xmpCopy,
                                        primaryURL: imageCopy) == metadataBefore)
    }

    @Test func creatorRejectsAmbiguousEmptySet() throws {
        let xmp = try #require(
            Bundle.module.url(forResource: "262M1559", withExtension: "xmp"))
        #expect(throws: Exiftool.ExiftoolError.self) {
            try Exiftool.helper.update(image: xmp,
                                       changes: [.creator: .set([])])
        }
    }
}
