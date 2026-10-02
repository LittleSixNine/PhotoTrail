import Exiftool
import Foundation
import Metadata
import Testing
@testable import ImageData

struct MetadataCreatorEditTests {
    @Test func descriptiveActionsKeepExactKeywordIdentity() throws {
        #expect(try MetadataFieldEditAction.setText("标题")
            .change(for: .titleDefault, from: nil) == .set(.text("标题")))
        #expect(try MetadataFieldEditAction.fillMissingText("新说明")
            .change(for: .descriptionDefault, from: .text("原说明")) == nil)
        #expect(try MetadataFieldEditAction.remove
            .change(for: .rightsDefault, from: .text("© A")) == .remove)
        #expect(try MetadataFieldEditAction.remove
            .change(for: .titleDefault, from: nil) == nil)

        let composed = "é"
        let decomposed = "e\u{301}"
        let existing = MetadataTagValue.list(["Travel", decomposed])
        #expect(try MetadataFieldEditAction.appendKeywords(["Travel", composed, "travel"])
            .change(for: .subject, from: existing)
            == .set(.list(["Travel", decomposed, composed, "travel"])))
        #expect(try MetadataFieldEditAction.removeKeywords([composed])
            .change(for: .subject, from: existing) == nil)
        #expect(try MetadataFieldEditAction.removeKeywords([decomposed])
            .change(for: .subject, from: existing) == .set(.list(["Travel"])))
        #expect(try MetadataFieldEditAction.replaceKeywords([])
            .change(for: .subject, from: existing) == .remove)
        #expect(throws: MetadataFieldEditError.self) {
            try MetadataFieldEditAction.appendKeywords([""])
                .change(for: .subject, from: existing)
        }
        #expect(throws: MetadataFieldEditError.self) {
            try MetadataFieldEditAction.setText("title")
                .change(for: .subject, from: existing)
        }
    }

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

    @Test func creatorPlanFreezesSelectionAndRejectsChangedOrSharedTargets() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let firstURL = folder.appendingPathComponent("first.dng")
        let secondURL = folder.appendingPathComponent("second.dng")
        for url in [firstURL, secondURL] {
            try Data("image".utf8).write(to: url)
            try Data("xmp".utf8).write(to: url.deletingPathExtension()
                .appendingPathExtension("xmp"))
        }
        let first = ImageData(metadata: Metadata(source: .xmp(firstURL)), name: "first.dng")
        let second = ImageData(metadata: Metadata(source: .xmp(secondURL)), name: "second.dng")
        let firstSidecar = try #require(first.metadataInspectionURL)
        let secondSidecar = try #require(second.metadataInspectionURL)
        func snapshot(_ url: URL, creator: MetadataTagValue? = nil) throws -> MetadataInspectionSnapshot {
            try MetadataInspectionSnapshot.read([.creator], from: url) { _, _ in
                creator.map { [.creator: $0] } ?? [:]
            }
        }
        let firstSnapshot = try snapshot(firstSidecar, creator: .list(["Alice"]))
        let secondSnapshot = try snapshot(secondSidecar)
        let readings = [(image: first, snapshot: firstSnapshot),
                        (image: second, snapshot: secondSnapshot)]

        let plan = try MetadataCreatorEditPlan.prepare(
            readings, action: .fillMissing(["Bob"]))
        #expect(plan.items.map(\.id) == [first.id, second.id])
        #expect(plan.items[0].change == nil)
        #expect(plan.items[1].change == .set(.list(["Bob"])))
        #expect(plan.items[1].target == second.metadataInspectionURL)
        #expect(plan.items[0].originalValue == .list(["Alice"]))
        #expect(plan.items[1].version == secondSnapshot.version)

        try Data("changed sidecar".utf8).write(to: second.metadataInspectionURL!)
        #expect(throws: MetadataCreatorPlanError.self) {
            try MetadataCreatorEditPlan.prepare(readings, action: .set(["Bob"]))
        }
        #expect(throws: MetadataCreatorPlanError.self) {
            try MetadataCreatorEditPlan.prepare(
                [(image: second, snapshot: firstSnapshot)], action: .set(["Bob"]))
        }
        let duplicate = [(image: first, snapshot: firstSnapshot),
                         (image: first, snapshot: firstSnapshot)]
        #expect(throws: MetadataCreatorPlanError.self) {
            try MetadataCreatorEditPlan.prepare(duplicate, action: .set(["Bob"]))
        }
        try FileManager.default.removeItem(at: secondSidecar)
        try FileManager.default.linkItem(at: firstSidecar, to: secondSidecar)
        let linkedFirst = try snapshot(firstSidecar)
        let linkedSecond = try snapshot(secondSidecar)
        #expect(throws: MetadataCreatorPlanError.self) {
            try MetadataCreatorEditPlan.prepare(
                [(image: first, snapshot: linkedFirst),
                 (image: second, snapshot: linkedSecond)],
                action: .set(["Bob"]))
        }
        let copy = ImageData(metadata: Metadata(source: .copy), name: "copy")
        #expect(throws: MetadataCreatorPlanError.self) {
            try MetadataCreatorEditPlan.prepare(
                [(image: copy, snapshot: linkedFirst)],
                action: .set(["Bob"]))
        }
        let rawInline = ImageData(metadata: Metadata(source: .image(firstURL)),
                                  name: "first.dng")
        #expect(throws: MetadataCreatorPlanError.self) {
            try MetadataCreatorEditPlan.prepare(
                [(image: rawInline, snapshot: linkedFirst)],
                action: .set(["Bob"]))
        }
        let invalid = try snapshot(firstSidecar, creator: .text("wrong type"))
        #expect(throws: MetadataCreatorPlanError.self) {
            try MetadataCreatorEditPlan.prepare(
                [(image: first, snapshot: invalid)], action: .set(["Bob"]))
        }
        let unreadCreator = try MetadataInspectionSnapshot.read([.subject], from: firstSidecar) { _, _ in [:] }
        #expect(throws: MetadataCreatorPlanError.self) {
            try MetadataCreatorEditPlan.prepare(
                [(image: first, snapshot: unreadCreator)], action: .fillMissing(["Bob"]))
        }
    }

    @Test func creatorSaveUsesRealTargetBackupAndRejectsStaleOrUnbackedWrites() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let backup = folder.appendingPathComponent("backup", isDirectory: true)
        try FileManager.default.createDirectory(at: backup,
                                                withIntermediateDirectories: true)
        let jpegFixture = try #require(Bundle.module.url(forResource: "alldata", withExtension: "jpg"))
        let jpeg = folder.appendingPathComponent("alldata.jpg")
        try FileManager.default.copyItem(at: jpegFixture, to: jpeg)
        let jpegBefore = try Data(contentsOf: jpeg)
        let image = ImageData(metadata: Metadata(source: .image(jpeg)), name: "alldata.jpg")
        let snapshot = try MetadataInspectionSnapshot.read([.creator], from: jpeg)
        let names = ["六九，作者", UUID().uuidString]
        let plan = try MetadataCreatorEditPlan.prepare(
            [(image: image, snapshot: snapshot)], action: .set(names))
        let item = try #require(plan.items.first)
        #expect(await item.save(backup: .folder(backup)) == .saved)
        #expect(try Data(contentsOf: backup.appendingPathComponent("alldata.jpg")) == jpegBefore)
        #expect(try Exiftool.helper.metadataTags([.creator], from: jpeg)[.creator] == .list(names))

        let savedSnapshot = try MetadataInspectionSnapshot.read([.creator], from: jpeg)
        let unchanged = try #require(MetadataCreatorEditPlan.prepare(
            [(image: image, snapshot: savedSnapshot)], action: .set(names)).items.first)
        #expect(await unchanged.save(backup: .folder(folder.appendingPathComponent("missing")))
                == .unchanged)
        let next = try #require(MetadataCreatorEditPlan.prepare(
            [(image: image, snapshot: savedSnapshot)], action: .set(["Next"])).items.first)
        let jpegAfter = try Data(contentsOf: jpeg)
        #expect(await next.save(backup: .folder(folder.appendingPathComponent("missing")))
                == .preparationFailed)
        #expect(try Data(contentsOf: jpeg) == jpegAfter)
        _ = try Exiftool.helper.update(image: jpeg,
                                      changes: [.creator: .set(.list(["External"]))])
        #expect(await next.save(backup: .folder(backup)) == .staleSource)

        let dngFixture = try #require(Bundle.module.url(forResource: "262M1559", withExtension: "DNG"))
        let xmpFixture = try #require(Bundle.module.url(forResource: "262M1559", withExtension: "xmp"))
        let dng = folder.appendingPathComponent("262M1559.DNG")
        let xmp = folder.appendingPathComponent("262M1559.xmp")
        try FileManager.default.copyItem(at: dngFixture, to: dng)
        try FileManager.default.copyItem(at: xmpFixture, to: xmp)
        let dngBefore = try Data(contentsOf: dng)
        let xmpBefore = try Data(contentsOf: xmp)
        let sidecarImage = ImageData(metadata: Metadata(source: .xmp(dng)), name: "262M1559.DNG")
        let sidecarSnapshot = try MetadataInspectionSnapshot.read([.creator, .exifArtist, .iptcKeywords], from: xmp)
        #expect(throws: MetadataCreatorPlanError.self) {
            try MetadataCreatorEditPlan.prepare([(image: sidecarImage, snapshot: sidecarSnapshot)], tag: .exifArtist, action: .setText("Wrong source"))
        }
        #expect(throws: MetadataCreatorPlanError.self) {
            try MetadataCreatorEditPlan.prepare([(image: sidecarImage, snapshot: sidecarSnapshot)], tag: .iptcKeywords, action: .replaceKeywords(["Wrong source"]))
        }
        let sidecarPlan = try MetadataCreatorEditPlan.prepare(
            [(image: sidecarImage, snapshot: sidecarSnapshot)], action: .set(names))
        let sidecarItem = try #require(sidecarPlan.items.first)
        #expect(await sidecarItem.save(backup: .folder(backup)) == .saved)
        #expect(try Data(contentsOf: backup.appendingPathComponent("262M1559.xmp")) == xmpBefore)
        #expect(try Data(contentsOf: dng) == dngBefore)
        #expect(try Exiftool.helper.metadataTags([.creator], from: xmp)[.creator] == .list(names))
    }

    @Test func creatorUnknownWriteReconcilesWithoutReplaying() {
        enum ControlledError: Error { case write, read, validation }
        let change = MetadataTagChange.set(.list(["Final"]))
        var writeCount = 0
        var readCount = 0
        let saved = MetadataCreatorEditPlan.Item.write(change: change, update: {
            writeCount += 1
            throw MetadataTagUpdateError.readbackFailed(underlying: ControlledError.write)
        }, readback: {
            readCount += 1
            return .list(["Final"])
        })
        #expect(saved == .saved)
        #expect(writeCount == 1 && readCount == 1)

        let unknown = MetadataCreatorEditPlan.Item.write(change: change, update: {
            throw MetadataTagUpdateError.writeFailed(underlying: ControlledError.write)
        }, readback: { .list(["Third value"]) })
        #expect(unknown == .resultUnknown)
        let unreadable = MetadataCreatorEditPlan.Item.write(change: .remove, update: {
            throw MetadataTagUpdateError.writeFailed(underlying: ControlledError.write)
        }, readback: { throw ControlledError.read })
        #expect(unreadable == .resultUnknown)

        var validationReadCount = 0
        let failed = MetadataCreatorEditPlan.Item.write(change: change, update: {
            throw ControlledError.validation
        }, readback: {
            validationReadCount += 1
            return nil
        })
        #expect(failed == .failed)
        #expect(validationReadCount == 0)
    }
}
