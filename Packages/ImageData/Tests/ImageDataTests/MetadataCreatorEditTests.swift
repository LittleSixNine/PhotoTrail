import Exiftool
import Testing
@testable import ImageData

struct MetadataCreatorEditTests {
    @Test func creatorActionsProduceOnlyNecessaryAbsoluteChanges() throws {
        let alice = MetadataCreatorValue.names(["Alice"])
        let bob = ["Bob", "六九，摄影师"]

        #expect(try MetadataCreatorEditAction.set(["Alice"]).change(from: alice) == nil)
        #expect(try MetadataCreatorEditAction.set(bob).change(from: alice)
                == .set(.list(bob)))
        #expect(try MetadataCreatorEditAction.fillMissing(bob).change(from: .absent)
                == .set(.list(bob)))
        #expect(try MetadataCreatorEditAction.fillMissing(bob).change(from: alice) == nil)
        #expect(try MetadataCreatorEditAction.remove.change(from: alice) == .remove)
        #expect(try MetadataCreatorEditAction.remove.change(from: .absent) == nil)
        #expect(throws: MetadataCreatorEditError.self) {
            try MetadataCreatorEditAction.set([]).change(from: alice)
        }
        #expect(throws: MetadataCreatorEditError.self) {
            try MetadataCreatorEditAction.fillMissing(["Alice", ""]).change(from: .absent)
        }
    }
}
