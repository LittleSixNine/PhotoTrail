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
        let firstVersion = MetadataInspectionFileVersion.read(first.metadataInspectionURL)
        let secondVersion = MetadataInspectionFileVersion.read(second.metadataInspectionURL)
        let readings = [(image: first, value: MetadataCreatorValue.names(["Alice"]),
                         version: firstVersion),
                        (image: second, value: MetadataCreatorValue.absent,
                         version: secondVersion)]

        let plan = try MetadataCreatorEditPlan.prepare(
            readings, action: .fillMissing(["Bob"]))
        #expect(plan.items.map(\.id) == [first.id, second.id])
        #expect(plan.items[0].change == nil)
        #expect(plan.items[1].change == .set(.list(["Bob"])))
        #expect(plan.items[1].target == second.metadataInspectionURL)
        #expect(plan.items[1].version == secondVersion)

        try Data("changed sidecar".utf8).write(to: second.metadataInspectionURL!)
        #expect(throws: MetadataCreatorPlanError.self) {
            try MetadataCreatorEditPlan.prepare(readings, action: .set(["Bob"]))
        }
        let duplicate = [(image: first, value: MetadataCreatorValue.absent,
                          version: firstVersion),
                         (image: first, value: MetadataCreatorValue.absent,
                          version: firstVersion)]
        #expect(throws: MetadataCreatorPlanError.self) {
            try MetadataCreatorEditPlan.prepare(duplicate, action: .set(["Bob"]))
        }
        let firstSidecar = try #require(first.metadataInspectionURL)
        let secondSidecar = try #require(second.metadataInspectionURL)
        try FileManager.default.removeItem(at: secondSidecar)
        try FileManager.default.linkItem(at: firstSidecar, to: secondSidecar)
        #expect(throws: MetadataCreatorPlanError.self) {
            try MetadataCreatorEditPlan.prepare(
                [(image: first, value: .absent,
                  version: MetadataInspectionFileVersion.read(firstSidecar)),
                 (image: second, value: .absent,
                  version: MetadataInspectionFileVersion.read(secondSidecar))],
                action: .set(["Bob"]))
        }
        let copy = ImageData(metadata: Metadata(source: .copy), name: "copy")
        #expect(throws: MetadataCreatorPlanError.self) {
            try MetadataCreatorEditPlan.prepare(
                [(image: copy, value: .absent, version: .unavailable)],
                action: .set(["Bob"]))
        }
        let rawInline = ImageData(metadata: Metadata(source: .image(firstURL)),
                                  name: "first.dng")
        #expect(throws: MetadataCreatorPlanError.self) {
            try MetadataCreatorEditPlan.prepare(
                [(image: rawInline, value: .absent,
                  version: MetadataInspectionFileVersion.read(firstURL))],
                action: .set(["Bob"]))
        }
    }
}
