import Coords
@testable import Exiftool
import Foundation
import ImageData
import Testing
import UDF
@testable import PhotoTrail

private final class VideoTestResources {}

@MainActor struct MixedVideoTests {
    @Test func oldRecipesPreservePhotoOnlySourcesAndTargets() throws {
        for operation in [MetadataOperation(tag: .lens, action: .setText("Prime")),
                          MetadataOperation(tag: .descriptionDefault, action: .copy(.rating)),
                          MetadataOperation(tag: .titleDefault, action: .setText("Event"))] {
            var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(operation)) as? [String: Any])
            json.removeValue(forKey: "photosOnly")
            let decoded = try JSONDecoder().decode(MetadataOperation.self, from: JSONSerialization.data(withJSONObject: json))
            #expect(decoded.supportsMovieEditing == (operation.tag == .titleDefault))
            #expect(try JSONDecoder().decode(MetadataOperation.self, from: JSONEncoder().encode(decoded)) == decoded)
            #expect(operation.supportsMovieEditing)
        }
        #expect(!MetadataOperation(tag: .descriptionDefault, action: .copy(.director)).supportsPhotoEditing)
    }

    @Test func presetScopeCountsFilesOnceAndKeepsBlankTemplatesSelectable() throws {
        let (folder, readings) = try MetadataBatchEditingTests().input([[:]])
        defer { try? FileManager.default.removeItem(at: folder) }
        let photo = try #require(readings.first?.image)
        let source = try #require(Bundle(for: VideoTestResources.self).url(forResource: "tagged", withExtension: "mov"))
        let url = folder.appendingPathComponent("clip.mov")
        try FileManager.default.copyItem(at: source, to: url)
        let movie = ImageData(from: url)
        let photoOnly = MetadataOperation(tag: .lens, action: .setText("35 mm"), photosOnly: true)
        let director = MetadataOperation(tag: .director, action: .setText(""))
        let city = MetadataOperation(tag: .city, action: .setText("杭州"))
        let mixed = [photo, movie]
        let partial = MetadataRuleScope([photoOnly], in: mixed)
        #expect(partial.photos == 1 && partial.videos == 0 && partial.skippedVideos == 1)
        #expect(MetadataRuleScope([photoOnly], in: [movie]).count == 0)
        let template = MetadataRuleScope([director], in: mixed)
        #expect(template.videos == 1 && template.skippedPhotos == 1)
        let combined = MetadataRuleScope([city, director], in: mixed)
        #expect(combined.count == 2 && combined.skipped == 0)
        #expect(MetadataRuleScope([], in: mixed).count == 0)
    }

    @Test func importedMovieCanBeFilteredEditedAndSavedFromBothPages() async throws {
        let bundle = Bundle(for: VideoTestResources.self)
        let fixture = try #require(bundle.url(forResource: "tagged", withExtension: "mov"))
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let backup = folder.appendingPathComponent("backup")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("A.MOV")
        try FileManager.default.copyItem(at: fixture, to: url)
        var state = PhotoTrailState()
        state.backupURL = backup
        let store = Store(initialState: state, reduce: PhotoTrailReducer(), undoEnabled: true)
        await OpenHelper.importFiles(store, urls: [folder], description: "Import").value
        let movie = try #require(store.imageData.first)
        #expect(store.imageData.count == 1 && movie.videoInfo != nil)
        let projection = PhotoListProjection()
        let videos = projection.table(store.state, search: "", hideInvalid: false, filter: .all, unmatchedIDs: nil, media: .videos)
        #expect(videos.ids == [movie.id] && videos.movieCount == 1 && videos.photoCount == 0)
        #expect(projection.table(store.state, search: "", hideInvalid: false, filter: .all, unmatchedIDs: nil, media: .photos).images.isEmpty)
        store.send(.selectionChanged([movie.id]), undoable: false)
        let snapshot = try MetadataInspectionSnapshot.read([.captureLocation, .captureDate, .model, .titleDefault], from: url)
        let preset = try MetadataPreset(name: "Lens", operations: [.init(tag: .lens, action: .setText("A"), photosOnly: true)])
        #expect(try MetadataPresetSession(preset: preset, parameters: Data()).targets(store.imageData).isEmpty)
        let recipe = MetadataWorkflowCard(operations: [.init(tag: .captureLocation, action: .setText("-42.5, 71.25")),
            .init(tag: .captureDate, action: .setText("2026:01:02 03:04:05+08:00")),
            .init(tag: .model, action: .setText("Camera 2")), .init(tag: .titleDefault, action: .setText("First light"))])
        let plan = try MetadataBatchRecipe.prepare([(movie, snapshot)], cards: [recipe])
        store.send(.creatorDraftApplied(plan.preview.items), description: "Location")
        #expect(store[movie.id].metadata.location?.latitude == -42.5)
        store.undo()
        #expect(store[movie.id].metadata.location == movie.metadata.location)
        store.redo()
        await store.send(.savePageRequest(.metadata)) { _ = await SaveHelper.save(store).result }
        #expect(!store[movie.id].hasPendingChanges && store.saveFailures.isEmpty)
        #expect(ImageData(from: url).metadata.location?.latitude == -42.5)
        #expect(store[movie.id].videoInfo?.model == "Camera 2" && store[movie.id].videoInfo?.zonedCreationDate == "2026:01:02 03:04:05+08:00")
        #expect(ImageData(from: url).videoInfo?.editableValues[.titleDefault] == .text("First light"))
        let current = store[movie.id]
        let nextSnapshot = try MetadataInspectionSnapshot.read([.captureLocation, .titleDefault], from: url)
        let nextPlan = try MetadataWorkflowPreview.prepare([(current, nextSnapshot)], operations: [
            .init(tag: .captureLocation, action: .setText("1, 2"))])
        store.send(.creatorDraftApplied(nextPlan.items), description: "Location")
        store.send(.locationForImageChanged(movie.id, Coords(latitude: 40.25, longitude: -70.5)))
        #expect(store[movie.id].creatorDraft == nil && store[movie.id].hasLegacyChanges)
        await store.send(.savePageRequest(.map)) { _ = await SaveHelper.save(store).result }
        #expect(!store[movie.id].hasPendingChanges && store.saveFailures.isEmpty)
        #expect(ImageData(from: url).metadata.location?.longitude == -70.5)
        #expect(!FileManager.default.fileExists(atPath: url.deletingPathExtension().appendingPathExtension("xmp").path))
        let prior = store[movie.id]
        let combinedSnapshot = try MetadataInspectionSnapshot.read([.captureLocation, .titleDefault, .city, .director], from: url)
        let combination = try MetadataWorkflowPreview.prepare([(prior, combinedSnapshot)], operations: [
            .init(tag: .city, action: .setText("杭州")), .init(tag: .director, action: .setText("Chen")),
            .init(tag: .titleDefault, action: .setText("Map and title")), .init(tag: .captureLocation, action: .setText("4, 5"))])
        store.send(.creatorDraftApplied(combination.items), description: "Fields")
        store.send(.locationForImageChanged(movie.id, Coords(latitude: 6, longitude: 7)), description: "Map")
        #expect(store[movie.id].creatorDraft?.changes[.titleDefault] != nil && store[movie.id].creatorDraft?.changes[.captureLocation] == nil)
        await store.send(.savePageRequest(.all)) { _ = await SaveHelper.save(store).result }
        #expect(store.saveFailures.isEmpty && !store[movie.id].hasPendingChanges)
        let combined = try Exiftool.helper.quickTimeVideoInfo(from: url)
        #expect(ImageData(from: url).metadata.city == "杭州" && store[movie.id].metadata.city == "杭州")
        #expect(combined.editableValues[.director] == .text("Chen"))
        #expect(combined.editableValues[.titleDefault] == .text("Map and title") && combined.location?.latitude == 6)
        store.send(.selectionChanged([movie.id]), undoable: false)
        store.send(.deleteRequest, description: "Clear movie point")
        #expect(store[movie.id].metadata.location == nil && store[movie.id].metadata.city == "杭州")
        await store.send(.savePageRequest(.map)) { _ = await SaveHelper.save(store).result }
        let cleared = ImageData(from: url)
        #expect(cleared.metadata.location == nil && cleared.metadata.city == "杭州")
        #expect(store.saveFailures.isEmpty)
    }

    @Test func unselectedLiveCompanionProtectsStillDuringSimpleRename() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try #require(Bundle(for: VideoTestResources.self).url(forResource: "tagged", withExtension: "mov"))
        let stillFixture = try #require(Bundle.main.url(forResource: "L1000051", withExtension: "JPG"))
        let still = root.appendingPathComponent("pair.jpg"), control = root.appendingPathComponent("solo.jpg")
        let movie = root.appendingPathComponent("PAIR.MOV")
        for target in [still, control] { try FileManager.default.copyItem(at: stillFixture, to: target) }
        try FileManager.default.copyItem(at: fixture, to: movie)
        try Exiftool.helper.run(["-overwrite_original", "-Keys:ContentIdentifier=" + UUID().uuidString, movie.path])
        let workspace = RenameWorkspace()
        workspace.rules = [RenameRule(action: 23)]
        workspace.settings = RenameSettings()
        workspace.refresh(images: [still, control].map { ImageData(from: $0) }, selection: [], directoryScopes: [root])
        for _ in 0..<600 where workspace.busy { try await Task.sleep(for: .milliseconds(25)) }
        let rows = try #require(workspace.plan).rows
        #expect(rows.contains { $0.source == still && $0.issues.contains(.livePhoto) && !$0.changes })
        #expect(rows.contains { $0.source == control && !$0.issues.contains(.livePhoto) })
    }

    @Test func movieRenameRespectsRecordedZoneAndProtectsCompanion() throws {
        let folder = URL(fileURLWithPath: "/tmp/PhotoTrail-Rename")
        var input = RenameInput(url: folder.appendingPathComponent("clip.mov"))
        let settings = RenameSettings()
        var rule = RenameRule(action: 40)
        rule.dateSource = .shooting
        let preview = { (file: RenameInput) in try RenameEngine.preview(inputs: [file], rules: [rule], settings: settings, occupied: [:])[0] }
        let missing = try preview(input)
        #expect(!missing.changes && missing.issues.contains(.uncertainVideoTime))
        input.tags["PhotoTrail:MovieCaptureDate"] = "2026:11:23 23:45:00+08:00"
        #expect(RenameEngine.shooting(input, settings: settings)?.offsetRecorded == true)
        input.tags["PhotoTrail:LivePhoto"] = "1"
        let protected = try preview(input)
        #expect(!protected.changes && protected.issues.contains(.livePhoto))
    }
}

extension MixedVideoTests {
    @Test func actualMovieRenameHandlesSameSecondAndRestoresOriginals() async throws {
        let bundle = Bundle(for: VideoTestResources.self)
        let fixture = try #require(bundle.url(forResource: "tagged", withExtension: "mov"))
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sources = ["one.MOV", "two.mov"].map { root.appendingPathComponent($0) }
        for source in sources { try FileManager.default.copyItem(at: fixture, to: source) }
        let workspace = RenameWorkspace()
        workspace.rules = [RenameRule(action: 40)]
        workspace.settings = RenameSettings()
        workspace.refresh(images: sources.map { ImageData(from: $0) }, selection: [], directoryScopes: [root])
        for _ in 0..<600 where workspace.busy { try await Task.sleep(for: .milliseconds(25)) }
        let plan = try #require(workspace.plan)
        #expect(plan.rows.count == 2 && plan.rows.allSatisfy { $0.changes && $0.movieCaptureDate != nil })
        let history = root.appendingPathComponent("history")
        let result = try RenameExecutor.execute(plan, directory: history)
        #expect(result.error == nil && result.mappings.count == 2)
        for (source, target) in result.mappings {
            #expect(source.pathExtension == target.pathExtension)
            #expect(ImageData(from: target).videoInfo?.model == "TestCam")
        }
        var journal = result.journal
        try RenameExecutor.restore(&journal, directory: history)
        let expected = try Data(contentsOf: fixture)
        for source in sources { #expect(try Data(contentsOf: source) == expected) }
    }
}
