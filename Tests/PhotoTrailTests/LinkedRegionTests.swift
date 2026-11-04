import Coords
import Foundation
@testable import ImageData
import Metadata
import Testing
import UDF
@testable import PhotoTrail

@MainActor private final class RegionLookupGate {
    private var waiting: CheckedContinuation<Place, Error>?
    private var started: CheckedContinuation<Void, Never>?
    private(set) var points: [MapCoordinate] = []

    func lookup(_ point: MapCoordinate, _ provider: String) async throws -> Place {
        points.append(point)
        started?.resume()
        started = nil
        return try await withCheckedThrowingContinuation { waiting = $0 }
    }

    func waitForStart() async {
        if points.isEmpty { await withCheckedContinuation { started = $0 } }
    }

    func finish(_ result: Result<Place, Error>) {
        waiting?.resume(with: result)
        waiting = nil
    }
}

@MainActor struct LinkedRegionTests {
    private let newLocation = Coords(latitude: 31.2, longitude: 121.5)

    // swiftlint:disable:next large_tuple
    private func fixture(_ count: Int = 1) throws -> (URL, PhotoTrailState, LocationWorkspace) {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var state = PhotoTrailState()
        state.imageData = try (0..<count).map { index in
            let url = folder.appendingPathComponent("synthetic-\(index).jpg")
            try Data("unchanged photo \(index)".utf8).write(to: url)
            let sidecar = url.deletingPathExtension().appendingPathExtension("xmp")
            try Data("unchanged sidecar \(index)".utf8).write(to: sidecar)
            var metadata = Metadata(source: .xmp(url))
            metadata.location = Coords(latitude: 30, longitude: 120)
            metadata.city = "已有城市"
            return ImageData(metadata: metadata, name: url.lastPathComponent)
        }
        state.selection = [state.imageData[0].id]
        return (folder, state, LocationWorkspace(favoritesURL: folder.appendingPathComponent("favorites.json")))
    }

    private func place(_ point: MapCoordinate) -> Place {
        Place(name: "", city: "查询城市", state: "查询省份", country: "中国", countryCode: "CN",
              coordinate: Coordinate(latitude: point.latitude, longitude: point.longitude), sublocation: "查询区县")
    }

    private func draft(_ image: ImageData) throws -> MetadataCreatorEditPlan {
        let target = try #require(image.metadataInspectionURL)
        let snapshot = MetadataInspectionSnapshot(url: target, requestedTags: [.creator], values: [:],
                                                  version: MetadataInspectionFileVersion.read(target))
        return try MetadataCreatorEditPlan.prepare([(image, snapshot)], action: .set(["未保存作者"]))
    }

    @Test func unboundWorkspaceStartsOffAndMakesNoLinkedRequest() async throws {
        let (folder, state, workspace) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = Store(initialState: state, reduce: PhotoTrailReducer())
        var calls = 0
        #expect(!workspace.fillRegionsOnLocationChange)
        store.send(.confirmedWGS84Location(newLocation))
        let task = LocationHelper.scheduleLinkedRegions(store, workspace: workspace, ids: state.selection) { point, _ in
            calls += 1
            return place(point)
        }
        #expect(task == nil)
        #expect(calls == 0)
        #expect(store[state.imageData[0].id].metadata.state == nil)
        #expect(store[state.imageData[0].id].metadata.location == newLocation)
    }

    @Test func enabledFillPreservesTextStagesOnlyAndCanBeUndone() async throws {
        let (folder, state, workspace) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = state.imageData[0]
        let source = try #require(image.metadataCreatorImageURL)
        let sidecar = try #require(image.metadataInspectionURL)
        let sourceBytes = try Data(contentsOf: source)
        let sidecarBytes = try Data(contentsOf: sidecar)
        let store = Store(initialState: state, reduce: PhotoTrailReducer(), undoEnabled: true)
        workspace.fillRegionsOnLocationChange = true
        store.send(.confirmedWGS84Location(newLocation))
        let positioned = store[image.id].metadata
        let task = try #require(LocationHelper.scheduleLinkedRegions(
            store, workspace: workspace, ids: [image.id]) { point, _ in
            place(point)
        })
        await task.value
        #expect(store[image.id].metadata.city == "已有城市")
        #expect(store[image.id].metadata.state == "查询省份")
        #expect(store[image.id].metadata.sublocation == "查询区县")
        #expect(store[image.id].metadata.country == "中国")
        #expect(store[image.id].metadata.countryCode == "CN")
        #expect(store[image.id].metadata.location == newLocation)
        #expect(workspace.status == L10n.text("地区信息已暂存：%1$@ 张", 1))
        #expect(store.unsavedChanges)
        #expect(try Data(contentsOf: source) == sourceBytes)
        #expect(try Data(contentsOf: sidecar) == sidecarBytes)
        store.undo()
        #expect(store[image.id].metadata == positioned)
        store.undo()
        #expect(store[image.id].metadata == image.metadata)
    }

    @Test func selectionChangeCannotRedirectFrozenTargets() async throws {
        let (folder, state, workspace) = try fixture(2)
        defer { try? FileManager.default.removeItem(at: folder) }
        let ids = state.imageData.map(\.id)
        let store = Store(initialState: state, reduce: PhotoTrailReducer())
        workspace.fillRegionsOnLocationChange = true
        store.send(.confirmedWGS84Location(newLocation))
        let gate = RegionLookupGate()
        let task = try #require(LocationHelper.scheduleLinkedRegions(
            store, workspace: workspace, ids: [ids[0]], lookupAddress: gate.lookup))
        store.send(.selectionChanged([ids[1]]), undoable: false)
        await gate.waitForStart()
        gate.finish(.success(place(try #require(gate.points.first))))
        await task.value
        #expect(gate.points == [MapCoordinate(latitude: newLocation.latitude, longitude: newLocation.longitude)])
        #expect(store[ids[0]].metadata.state == "查询省份")
        #expect(store[ids[1]].metadata.state == nil)
        #expect(store[ids[1]].metadata.location == state[ids[1]].metadata.location)
    }

    @Test(arguments: ["coordinate", "metadata", "draft", "undo", "remove", "sidecar", "source",
                      "saving", "import", "off", "offOn", "cancel"])
    func lateResultsRejectChangedState(reason: String) async throws {
        let (folder, state, workspace) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let id = state.imageData[0].id
        let store = Store(initialState: state, reduce: PhotoTrailReducer(), undoEnabled: true)
        workspace.fillRegionsOnLocationChange = true
        store.send(.confirmedWGS84Location(newLocation))
        let gate = RegionLookupGate()
        let task = try #require(LocationHelper.scheduleLinkedRegions(
            store, workspace: workspace, ids: [id], lookupAddress: gate.lookup))
        await gate.waitForStart()
        switch reason {
        case "coordinate": store.send(.confirmedWGS84Location(Coords(latitude: 32, longitude: 122)))
        case "metadata": store.send(.newTimestamp(Date(timeIntervalSince1970: 0), 0))
        case "draft": store.send(.creatorDraftApplied(try draft(store[id]).items))
        case "undo": store.undo()
        case "remove": store.send(.removeImages([id]))
        case "sidecar": try Data("external sidecar change".utf8).write(to: #require(store[id].metadataInspectionURL))
        case "source": try Data("external source change".utf8).write(to: #require(store[id].metadataCreatorImageURL))
        case "saving": store.send(.saveRequest, undoable: false)
        case "import": store.importProgress.begin(.scanning)
        case "off": workspace.fillRegionsOnLocationChange = false
        case "offOn":
            workspace.fillRegionsOnLocationChange = false
            workspace.fillRegionsOnLocationChange = true
        default: task.cancel()
        }
        let before = store.imageData
        gate.finish(.success(place(try #require(gate.points.first))))
        await task.value
        #expect(store.imageData == before)
        #expect(store.imageData.allSatisfy { $0.metadata.state == nil })
    }

    @Test func failedLookupKeepsAppliedLocationAndReportsFailure() async throws {
        let (folder, state, workspace) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let id = state.imageData[0].id
        let store = Store(initialState: state, reduce: PhotoTrailReducer())
        workspace.fillRegionsOnLocationChange = true
        store.send(.confirmedWGS84Location(newLocation))
        let positioned = store[id].metadata
        let task = try #require(LocationHelper.scheduleLinkedRegions(store, workspace: workspace, ids: [id]) { _, _ in
            throw URLError(.notConnectedToInternet)
        })
        await task.value
        #expect(store[id].metadata == positioned)
        #expect(store[id].metadata.location == newLocation)
        #expect(store.unsavedChanges)
        #expect(workspace.status.contains(state.imageData[0].name))
    }

    @Test func existingCreatorDraftIsSkippedAndPreserved() async throws {
        let (folder, state, workspace) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let id = state.imageData[0].id
        let store = Store(initialState: state, reduce: PhotoTrailReducer())
        store.send(.creatorDraftApplied(try draft(store[id]).items))
        workspace.fillRegionsOnLocationChange = true
        store.send(.confirmedWGS84Location(newLocation))
        let before = store[id]
        var calls = 0
        let task = LocationHelper.scheduleLinkedRegions(
            store, workspace: workspace, ids: [id]) { point, _ in
            calls += 1
            return place(point)
        }
        await task?.value
        #expect(task == nil)
        #expect(calls == 0)
        #expect(store[id] == before)
        #expect(store[id].creatorDraft?.changes[.creator] == .set(.list(["未保存作者"])))
    }

    @Test(arguments: [true, false])
    func whitespaceIsMissingWhileCompleteRegionsStartNoTask(whitespace: Bool) async throws {
        let (folder, initial, workspace) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        var state = initial
        let id = state.imageData[0].id
        state[id].metadata.state = whitespace ? " \t\n" : "已有省份"
        state[id].metadata.sublocation = "已有区县"
        state[id].metadata.country = "已有国家"
        state[id].metadata.countryCode = "XX"
        let store = Store(initialState: state, reduce: PhotoTrailReducer())
        workspace.fillRegionsOnLocationChange = true
        workspace.status = "keep status"
        var calls = 0
        let task = LocationHelper.scheduleLinkedRegions(store, workspace: workspace, ids: [id]) { point, _ in
            calls += 1
            return place(point)
        }
        await task?.value
        #expect(calls == (whitespace ? 1 : 0))
        #expect(store[id].metadata.state == (whitespace ? "查询省份" : "已有省份"))
        #expect(store[id].metadata.city == "已有城市")
        #expect(store[id].metadata.sublocation == "已有区县")
        #expect(store[id].metadata.country == "已有国家")
        if !whitespace {
            #expect(task == nil)
            #expect(workspace.status == "keep status")
        }
    }

    @Test func pairedPhotosReceiveTheirOwnMissingFields() async throws {
        let (folder, initial, workspace) = try fixture(2)
        defer { try? FileManager.default.removeItem(at: folder) }
        var state = initial
        let ids = state.imageData.map(\.id)
        state[ids[0]].pairedID = ids[1]
        state[ids[1]].pairedID = ids[0]
        state[ids[1]].metadata.state = "已有省份"
        let store = Store(initialState: state, reduce: PhotoTrailReducer())
        workspace.fillRegionsOnLocationChange = true
        store.send(.confirmedWGS84Location(newLocation))
        let task = try #require(LocationHelper.scheduleLinkedRegions(
            store, workspace: workspace, ids: [ids[0]]) { point, _ in
            place(point)
        })
        await task.value
        #expect(store[ids[0]].metadata.state == "查询省份")
        #expect(store[ids[1]].metadata.state == "已有省份")
        #expect(store[ids[1]].metadata.sublocation == "查询区县")
        #expect(store[ids[1]].metadata.location == newLocation)
    }

    @Test(arguments: ["save", "rename", "import"])
    func busyOperationsCannotStartLinkedLookups(reason: String) throws {
        let (folder, initial, workspace) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        var state = initial
        if reason == "save" { state.saveInProgress = true }
        if reason == "rename" { state.renameInProgress = true }
        if reason == "import" { state.importProgress.begin(.scanning) }
        let store = Store(initialState: state, reduce: PhotoTrailReducer())
        workspace.fillRegionsOnLocationChange = true
        #expect(LocationHelper.scheduleLinkedRegions(store, workspace: workspace, ids: state.selection) == nil)
    }
}
