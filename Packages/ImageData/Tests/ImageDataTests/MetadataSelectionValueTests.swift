import Exiftool
import Foundation
import Metadata
import Testing
@testable import ImageData

struct MetadataSelectionValueTests {
    @Test func sourceRoutesToTheActualMetadataFile() {
        let imageURL = URL(fileURLWithPath: "/tmp/photo.jpg")
        let sidecarURL = URL(fileURLWithPath: "/tmp/photo.xmp")
        let image = ImageData(metadata: Metadata(source: .image(imageURL)), name: "photo.jpg")
        let sidecar = ImageData(metadata: Metadata(source: .xmp(imageURL)), name: "photo.jpg")
        let unavailable = ImageData(metadata: Metadata(source: .copy), name: "copy")

        #expect(image.metadataInspectionURL == imageURL)
        #expect(sidecar.metadataInspectionURL == sidecarURL)
        #expect(sidecar.metadataCreatorImageURL == imageURL)
        #expect(unavailable.metadataInspectionURL == nil)
    }

    @Test func creatorSourcesKeepMissingSeparateFromConflicts() {
        let alice = MetadataTagValue.list(["Alice"])
        let legacy: [LegacyCreatorTag: [String]] = [.exifArtist: ["Alice"],
                                                    .iptcByline: ["Bob"]]
        #expect(MetadataSelectionValue.summarize([[:], legacy], tag: .exifArtist)
                == .mixed(present: 1, total: 2))
        #expect(MetadataSelectionValue.creatorSourcesConflict(xmp: alice,
                                                               legacy: legacy))
        #expect(!MetadataSelectionValue.creatorSourcesConflict(
            xmp: alice, legacy: [.exifArtist: ["Alice"]]))
        #expect(!MetadataSelectionValue.creatorSourcesConflict(xmp: nil, legacy: [:]))
    }

    @Test func selectionKeepsMissingDistinctFromMixedValues() {
        let alice = MetadataTagValue.list(["Alice"])
        let bob = MetadataTagValue.list(["Bob"])
        let tag = MetadataTag.creator

        #expect(MetadataSelectionValue.summarize([], tag: tag) == .unselected)
        #expect(MetadataSelectionValue.summarize([[:], [:]], tag: tag) == .absent)
        #expect(MetadataSelectionValue.summarize([[tag: alice], [tag: alice]], tag: tag)
                == .uniform(alice))
        #expect(MetadataSelectionValue.summarize([[tag: alice], [:]], tag: tag)
                == .mixed(present: 1, total: 2))
        #expect(MetadataSelectionValue.summarize([[tag: alice], [tag: bob]], tag: tag)
                == .mixed(present: 2, total: 2))
    }

    @Test func inspectionVersionChangesWhenTargetChanges() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = directory.appendingPathComponent("image.jpg")

        #expect(MetadataInspectionFileVersion.read(nil) == .unavailable)
        #expect(MetadataInspectionFileVersion.read(image) == .missing)
        try Data("one".utf8).write(to: image)
        let first = MetadataInspectionFileVersion.read(image)
        #expect(first != .missing)
        try Data("another value".utf8).write(to: image)
        #expect(MetadataInspectionFileVersion.read(image) != first)
        try FileManager.default.removeItem(at: image)
        #expect(MetadataInspectionFileVersion.read(image) == .missing)
    }

    @Test func inspectionSnapshotBindsValuesToAnUnchangedFileVersion() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("photo.xmp")
        try Data("before".utf8).write(to: url)
        let expected: [MetadataTag: MetadataTagValue] = [.creator: .list(["Alice"])]

        let snapshot = try MetadataInspectionSnapshot.read([.creator], from: url) { tags, target in
            #expect(tags == [.creator])
            #expect(target == url)
            return expected
        }
        #expect(snapshot.values == expected)
        #expect(snapshot.url == url)
        #expect(snapshot.requestedTags == [.creator])
        #expect(snapshot.version == MetadataInspectionFileVersion.read(url))

        #expect(throws: MetadataInspectionError.self) {
            try MetadataInspectionSnapshot.read([.creator], from: url) { _, _ in
                try Data("changed during read".utf8).write(to: url)
                return expected
            }
        }
        try FileManager.default.removeItem(at: url)
        #expect(throws: MetadataInspectionError.self) {
            try MetadataInspectionSnapshot.read([.creator], from: url) { _, _ in expected }
        }
    }

    @Test func sidecarInspectionTracksSidecarInsteadOfImage() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = directory.appendingPathComponent("photo.jpg")
        let sidecarURL = directory.appendingPathComponent("photo.xmp")
        try Data("image".utf8).write(to: imageURL)
        try Data("first".utf8).write(to: sidecarURL)
        let image = ImageData(metadata: Metadata(source: .xmp(imageURL)), name: "photo.jpg")
        let originalImageVersion = MetadataInspectionFileVersion.read(imageURL)
        let firstSidecarVersion = MetadataInspectionFileVersion.read(image.metadataInspectionURL)
        let firstVersions = image.metadataInspectionVersions

        try Data("second value".utf8).write(to: sidecarURL)

        #expect(image.metadataInspectionURL == sidecarURL)
        #expect(MetadataInspectionFileVersion.read(imageURL) == originalImageVersion)
        #expect(MetadataInspectionFileVersion.read(image.metadataInspectionURL) != firstSidecarVersion)
        let afterSidecarChange = image.metadataInspectionVersions
        #expect(afterSidecarChange != firstVersions)
        try Data("changed image bytes".utf8).write(to: imageURL)
        #expect(image.metadataInspectionVersions != afterSidecarChange)
    }
}
