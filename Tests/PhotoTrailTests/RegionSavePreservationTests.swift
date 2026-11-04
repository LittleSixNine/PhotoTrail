import Coords
@testable import Exiftool
import Foundation
import ImageData
import Imagetool
import Metadata
import Testing
import UDF
@testable import PhotoTrail

@Suite(.serialized) @MainActor struct RegionSavePreservationTests {
    private let regionTags = ["XMP-photoshop:City", "XMP-photoshop:State", "XMP-iptcCore:Location",
                              "XMP-photoshop:Country", "XMP-iptcCore:CountryCode"]
    private let regionValues = ["已有城市", "Existing State", "Existing District", "Existing Country", "XX"]

    private func readRegions(_ url: URL) throws -> [String: String] {
        let tags = regionTags + ["IPTC:City", "IPTC:Province-State", "IPTC:Sub-location",
                                 "IPTC:Country-PrimaryLocationName", "IPTC:Country-PrimaryLocationCode"]
        let data = try Exiftool.helper.run(["-j", "-G1", "-s", "-a"] + tags.map { "-" + $0 } + [url.path])
        let rows = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        return try #require(rows.first).compactMapValues { $0 as? String }
    }

    private func fixture(conflict: Bool = false) throws -> (URL, URL, Store<PhotoTrailState, PhotoTrailEvent>) {
        let source = try #require(PhotoTrailState(forPreview: true).imageData.compactMap { image -> URL? in
            guard case .image(let url) = image.metadata.source,
                  url.pathExtension.lowercased() == "jpg" else { return nil }
            return url
        }.first)
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("region-preservation.jpg")
        try FileManager.default.copyItem(at: source, to: url)
        var arguments = ["-overwrite_original", "-GPS:all=", "-XMP-exif:GPSLatitude=", "-XMP-exif:GPSLongitude=",
                         "-IPTC:City=", "-IPTC:Province-State=", "-IPTC:Sub-location=",
                         "-IPTC:Country-PrimaryLocationName=", "-IPTC:Country-PrimaryLocationCode="]
        arguments += zip(regionTags, regionValues).map { "-\($0.0)=\($0.1)" }
        if conflict { arguments += ["-IPTC:CodedCharacterSet=UTF8", "-IPTC:City=IPTC City"] }
        _ = try Exiftool.helper.run(arguments + [url.path])
        let metadata = Imagetool.metadata(from: url)
        let initialRegions = try readRegions(url)
        for (tag, value) in zip(regionTags, regionValues) { #expect(initialRegions[tag] == value) }
        #expect(initialRegions["IPTC:City"] == (conflict ? "IPTC City" : nil))
        #expect(metadata.location == nil)
        var state = PhotoTrailState()
        state.imageData = [ImageData(metadata: metadata, name: url.lastPathComponent)]
        state.selection = [state.imageData[0].id]
        state.backupURL = folder.appendingPathComponent("backup")
        try FileManager.default.createDirectory(at: state.backupURL!, withIntermediateDirectories: true)
        return (folder, url, Store(initialState: state, reduce: PhotoTrailReducer(), undoEnabled: true))
    }

    private func settings() -> () -> Void {
        let keys = [SettingsPreferences.writeRegionKey, SettingsView.createSidecarFilesKey,
                    SettingsView.addTagsKey, PhotoTrailApp.doNotBackupKey,
                    Exiftool.updateGPSTimestampsKey, Exiftool.updateFileModificationTimesKey]
        let old = keys.map { UserDefaults.standard.object(forKey: $0) }
        for key in keys { UserDefaults.standard.set(false, forKey: key) }
        return {
            for (key, value) in zip(keys, old) {
                if let value { UserDefaults.standard.set(value, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
    }

    @Test func regionReadsRecognizeCopyInstancesWithoutMixingNamespacesAndRejectAmbiguity() throws {
        let values = ["XMP-photoshop:Copy1:City": "XMP City", "XMP-photoshop:City": "XMP City",
                      "IPTC:Copy2:City": "IPTC City", "Other:City": "Other City"]
        #expect(try RegionSaveSnapshot.regionValue("XMP-photoshop:City", in: values) == "XMP City")
        #expect(try RegionSaveSnapshot.regionValue("IPTC:City", in: values) == "IPTC City")
        var conflicting = values
        conflicting["XMP-photoshop:Copy3:City"] = "Different XMP City"
        #expect(throws: (any Error).self) {
            try RegionSaveSnapshot.regionValue("XMP-photoshop:City", in: conflicting)
        }
    }

    @Test(arguments: [false, true], [false, true])
    func trackSavePreservesXMPOnlyRegionsAndIndependentIPTCConflict(conflict: Bool, combined: Bool) async throws {
        let restore = settings()
        defer { restore() }
        let (folder, url, store) = try fixture(conflict: conflict)
        defer { try? FileManager.default.removeItem(at: folder) }
        let id = store.imageData[0].id
        let before = try Data(contentsOf: url)
        let pixels = try Exiftool.helper.run(["-s3", "-ImageDataMD5", url.path])
        if combined {
            let snapshot = try MetadataInspectionSnapshot.read([.creator], from: url)
            let plan = try MetadataCreatorEditPlan.prepare([(store[id], snapshot)], action: .set(["Draft Author"]))
            store.send(.creatorDraftApplied(plan.items))
        }
        store.send(.locationFromTrack([.init(id: id, timestamp: 0,
            coords: Coords(latitude: 31.2, longitude: 121.5), elevation: nil)]), undoable: false)
        store.send(.applyTrackMatches)
        let workspace = LocationWorkspace(favoritesURL: folder.appendingPathComponent("favorites.json"))
        await store.send(.saveRequest) { await SaveHelper.save(store, workspace: workspace).value }
        #expect(store.saveFailures.isEmpty)
        #expect(!store.unsavedChanges)
        let fields = try readRegions(url)
        for (tag, value) in zip(regionTags, regionValues) { #expect(fields[tag] == value) }
        #expect(fields["IPTC:City"] == (conflict ? "IPTC City" : nil))
        #expect(store[id].metadata.city == (conflict ? "IPTC City" : "已有城市"))
        #expect(store[id].metadata.location == Coords(latitude: 31.2, longitude: 121.5))
        #expect(try Exiftool.helper.run(["-s3", "-ImageDataMD5", url.path]) == pixels)
        let backups = try FileManager.default.contentsOfDirectory(at: store.backupURL!, includingPropertiesForKeys: nil)
        #expect(backups.count == 1)
        #expect(try Data(contentsOf: #require(backups.first)) == before)
        if combined {
            #expect(try Exiftool.helper.metadataTags([.creator], from: url)[.creator] == .list(["Draft Author"]))
        }
    }

    @Test(arguments: [false, true])
    func existingAndNewSidecarsKeepTheirRegions(existingSidecar: Bool) async throws {
        let restore = settings()
        defer { restore() }
        let (folder, url, initial) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let imageBytes = try Data(contentsOf: url)
        let sidecar = url.deletingPathExtension().appendingPathExtension("xmp")
        var state = initial.state
        if existingSidecar {
            let sandbox = try Sandbox(for: url)
            defer { sandbox.removeSandboxFolder() }
            try sandbox.makeSidecarFile()
            state.imageData = [ImageData(from: url)]
            state.selection = [state.imageData[0].id]
        } else {
            UserDefaults.standard.set(true, forKey: SettingsView.createSidecarFilesKey)
        }
        let store = Store(initialState: state, reduce: PhotoTrailReducer())
        let id = store.imageData[0].id
        store.send(.confirmedWGS84Location(Coords(latitude: 32.2, longitude: 122.5)))
        await store.send(.saveRequest) { await SaveHelper.save(store).value }
        #expect(store.saveFailures.isEmpty)
        #expect(!store.unsavedChanges)
        #expect(try Data(contentsOf: url) == imageBytes)
        let fields = try readRegions(sidecar)
        for (tag, value) in zip(regionTags, regionValues) { #expect(fields[tag] == value) }
        #expect(Exiftool.helper.metadata(from: sidecar, primaryURL: url).location
            == Coords(latitude: 32.2, longitude: 122.5))
        if case .xmp = store[id].metadata.source { } else { Issue.record("Expected sidecar source after saving") }
    }

    @Test func noGPSDateSaveCreatingSidecarPreservesRegionsAndKeepsGPSAbsent() async throws {
        let restore = settings()
        defer { restore() }
        let (folder, url, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        try #require(FileManager.default.fileExists(atPath: url.path))
        let imageBytes = try Data(contentsOf: url)
        let originalDate = try Exiftool.helper.metadataTags([.captureDate], from: url)[.captureDate]
        let id = store.imageData[0].id
        UserDefaults.standard.set(true, forKey: SettingsView.createSidecarFilesKey)
        store.send(.newTimestamp(Date(timeIntervalSince1970: 0), 3_600))
        try #require(store[id].hasPendingChanges)
        try #require(store[id].metadata.dateTimeCreated != store[id].original?.dateTimeCreated)
        let expectedDate = try #require(store[id].metadata.parsedDate(timeZone: store.timeZone))
        await store.send(.saveRequest) { await SaveHelper.save(store).value }
        try #require(store.saveTotal == 1 && store.saveCompleted == 1)
        #expect(store.saveFailures.isEmpty)
        #expect(!store.unsavedChanges)
        #expect(try Data(contentsOf: url) == imageBytes)
        #expect(try Exiftool.helper.metadataTags([.captureDate], from: url)[.captureDate] == originalDate)
        let sidecar = url.deletingPathExtension().appendingPathExtension("xmp")
        try #require(FileManager.default.fileExists(atPath: sidecar.path))
        let saved = Exiftool.helper.metadata(from: sidecar, primaryURL: url)
        #expect(saved.location == nil)
        #expect(saved.parsedDate(timeZone: store.timeZone) == expectedDate)
        let fields = try readRegions(sidecar)
        for (tag, value) in zip(regionTags, regionValues) { #expect(fields[tag] == value) }
    }

    @Test func explicitlyClearingLocationStillClearsItsRegions() async throws {
        let restore = settings()
        defer { restore() }
        let (folder, url, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        store.send(.confirmedWGS84Location(Coords(latitude: 31.2, longitude: 121.5)))
        await store.send(.saveRequest) { await SaveHelper.save(store).value }
        #expect(store.saveFailures.isEmpty)
        store.send(.deleteRequest)
        await store.send(.saveRequest) { await SaveHelper.save(store).value }
        #expect(store.saveFailures.isEmpty)
        #expect(!store.unsavedChanges)
        #expect(Imagetool.metadata(from: url).location == nil)
        let fields = try readRegions(url)
        for tag in regionTags { #expect(fields[tag] == nil) }
    }

    @Test func noLocationDateSavePreservesExistingRegionsAndKeepsGPSAbsent() async throws {
        let restore = settings()
        defer { restore() }
        let (folder, url, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        try #require(FileManager.default.fileExists(atPath: url.path))
        let originalDate = try Exiftool.helper.metadataTags([.captureDate], from: url)[.captureDate]
        let id = store.imageData[0].id
        store.send(.newTimestamp(Date(timeIntervalSince1970: 0), 3_600))
        try #require(store[id].hasPendingChanges)
        try #require(store[id].metadata.dateTimeCreated != store[id].original?.dateTimeCreated)
        let expectedDate = try #require(store[id].metadata.parsedDate(timeZone: store.timeZone))
        await store.send(.saveRequest) { await SaveHelper.save(store).value }
        try #require(store.saveTotal == 1 && store.saveCompleted == 1)
        #expect(!store.unsavedChanges)
        #expect(store.saveFailures.isEmpty)
        let saved = Imagetool.metadata(from: url)
        #expect(saved.location == nil)
        #expect(saved.parsedDate(timeZone: store.timeZone) == expectedDate)
        #expect(try Exiftool.helper.metadataTags([.captureDate], from: url)[.captureDate] != originalDate)
        let fields = try readRegions(url)
        for (tag, value) in zip(regionTags, regionValues) { #expect(fields[tag] == value) }
    }
}
