import Coords
import Foundation
@testable import ImageData
import Metadata
import Testing
@testable import PhotoTrail

@MainActor private final class SaveAddressLookupGate {
    private var waiting: CheckedContinuation<Place, Never>?
    private var started: CheckedContinuation<Void, Never>?
    private var didStart = false

    func lookup(_ point: MapCoordinate, _ provider: String) async -> Place {
        didStart = true
        started?.resume()
        started = nil
        return await withCheckedContinuation { waiting = $0 }
    }

    func waitForStart() async {
        if !didStart { await withCheckedContinuation { started = $0 } }
    }

    func finish(_ place: Place) {
        waiting?.resume(returning: place)
        waiting = nil
    }
}

@MainActor struct SaveAddressTests {
    private func input() -> ImageData {
        var original = Metadata(source: .xmp(URL(fileURLWithPath: "/tmp/synthetic-region-save.jpg")))
        original.location = Coords(latitude: 30, longitude: 120)
        original.city = "已有城市"
        var image = ImageData(metadata: original, name: "synthetic-region-save.jpg")
        image.metadata.location = Coords(latitude: 31.2, longitude: 121.5)
        return image
    }

    private func defaults(_ enabled: Bool) throws -> (UserDefaults, String) {
        let domain = "PhotoTrail.SaveAddressTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defaults.set(enabled, forKey: SettingsPreferences.writeRegionKey)
        defaults.set("amap", forKey: "PhotoTrailMapProvider")
        return (defaults, domain)
    }

    private func cachedWorkspace() -> LocationWorkspace {
        let workspace = LocationWorkspace()
        workspace.regionCache["\(L10n.language.rawValue):amap:31.2:121.5"] = Place(
            name: "", city: "查询城市", state: "查询省份", country: "中国", countryCode: "CN",
            coordinate: Coordinate(latitude: 31.2, longitude: 121.5), sublocation: "查询区县")
        return workspace
    }

    @Test func savedPreferenceOffReturnsOriginalSnapshotWithoutQuery() async throws {
        let image = input()
        let (defaults, domain) = try defaults(false)
        defer { defaults.removePersistentDomain(forName: domain) }
        var failures: [String] = []
        let result = await SaveHelper.resolveAddresses([image.id: image.metadata], images: [image],
            workspace: cachedWorkspace(), onFailure: { failures.append($0) }, defaults: defaults)
        #expect(result[image.id] == image.metadata)
        #expect(failures.isEmpty)
    }

    @Test func enabledSaveUsesCachedAddressOnlyForMissingFields() async throws {
        var image = input()
        image.metadata.country = "已有国家"
        image.metadata.sublocation = " "
        let (defaults, domain) = try defaults(true)
        defer { defaults.removePersistentDomain(forName: domain) }
        let result = await SaveHelper.resolveAddresses([image.id: image.metadata], images: [image],
            workspace: cachedWorkspace(), defaults: defaults)
        let saved = try #require(result[image.id])
        #expect(saved.city == "已有城市")
        #expect(saved.country == "已有国家")
        #expect(saved.sublocation == "查询区县")
        #expect(saved.state == "查询省份")
        #expect(saved.countryCode == "CN")
        #expect(saved.location == image.metadata.location)
        #expect(image.metadata.state == nil)
    }

    @Test func lookupFailureKeepsCoordinatesAndEveryExistingField() async throws {
        let image = input()
        let (defaults, domain) = try defaults(true)
        defer { defaults.removePersistentDomain(forName: domain) }
        var failures: [String] = []
        let result = await SaveHelper.resolveAddresses([image.id: image.metadata], images: [image],
            workspace: LocationWorkspace(), onFailure: { failures.append($0) }, defaults: defaults)
        #expect(result[image.id] == image.metadata)
        #expect(failures.count == 1)
        #expect(failures.first?.contains(image.name) == true)
    }

    @Test(arguments: ["keyOff", "off", "offOn"])
    func disablingDuringLookupRejectsLateRegionsWithoutClearingCache(change: String) async throws {
        let image = input()
        let (defaults, domain) = try defaults(true)
        defer { defaults.removePersistentDomain(forName: domain) }
        let workspace = cachedWorkspace()
        workspace.fillRegionsOnLocationChange = true
        let cache = workspace.regionCache
        let gate = SaveAddressLookupGate()
        var failures: [String] = []
        let task = Task {
            await SaveHelper.resolveAddresses([image.id: image.metadata], images: [image], workspace: workspace,
                onFailure: { failures.append($0) }, defaults: defaults, lookupAddress: gate.lookup)
        }
        await gate.waitForStart()
        defaults.set(false, forKey: SettingsPreferences.writeRegionKey)
        if change != "keyOff" { workspace.fillRegionsOnLocationChange = false }
        if change == "offOn" {
            defaults.set(true, forKey: SettingsPreferences.writeRegionKey)
            workspace.fillRegionsOnLocationChange = true
        }
        gate.finish(Place(name: "", city: "迟到城市", state: "迟到省份", country: "中国", countryCode: "CN",
            coordinate: Coordinate(latitude: 31.2, longitude: 121.5), sublocation: "迟到区县"))
        let result = await task.value
        #expect(result[image.id] == image.metadata)
        #expect(result[image.id]?.location == image.metadata.location)
        #expect(workspace.regionCache == cache)
        #expect(failures.isEmpty)
    }

    @Test(arguments: ["complete", "dateOnly", "unknownDatum", "creatorDraft"])
    func ineligibleSnapshotsArePreservedWithoutQuery(reason: String) async throws {
        var image = input()
        switch reason {
        case "complete":
            image.metadata.state = "已有省份"
            image.metadata.sublocation = "已有区县"
            image.metadata.country = "已有国家"
            image.metadata.countryCode = "XX"
        case "dateOnly":
            image.metadata.location = image.original?.location
            image.metadata.dateTimeCreated = "2026:11:04 12:00:00"
        case "unknownDatum": image.metadata.gpsMapDatum = "GCJ-02"
        default:
            let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let target = folder.appendingPathComponent("draft.xmp")
            try Data("synthetic sidecar".utf8).write(to: target)
            var metadata = Metadata(source: .xmp(target))
            metadata.location = image.metadata.location
            image = ImageData(metadata: metadata, name: "draft.jpg")
            let snapshot = MetadataInspectionSnapshot(url: target, requestedTags: [.creator], values: [:],
                version: MetadataInspectionFileVersion.read(target))
            image.applyMetadataDraft(try #require(MetadataCreatorEditPlan.prepare([(image, snapshot)],
                action: .set(["未保存作者"])).items.first))
            image.metadata.location = Coords(latitude: 32, longitude: 122)
        }
        let (defaults, domain) = try defaults(true)
        defer { defaults.removePersistentDomain(forName: domain) }
        var failures: [String] = []
        let result = await SaveHelper.resolveAddresses([image.id: image.metadata], images: [image],
            workspace: LocationWorkspace(), onFailure: { failures.append($0) }, defaults: defaults)
        #expect(result[image.id] == image.metadata)
        #expect(failures.isEmpty)
        if reason == "creatorDraft" {
            #expect(image.creatorDraft?.changes[.creator] == .set(.list(["未保存作者"])))
        }
    }
}
