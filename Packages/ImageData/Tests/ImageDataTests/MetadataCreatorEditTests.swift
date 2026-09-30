import Exiftool
import Foundation
import Metadata
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
        #expect(plan.items[0].original == .names(["Alice"]))
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
}
