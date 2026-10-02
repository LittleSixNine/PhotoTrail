import Exiftool
import Foundation
import ImageData
import Imagetool
import Testing
import UDF

@testable import PhotoTrail

@MainActor
struct MetadataCreatorBatchTests {
    @Test func primaryDateUsesExistingTrackDateAndClearsAfterReload() async throws {
        let source = try #require(PhotoTrailState(forPreview: true).imageData.compactMap { image -> URL? in
            guard case .image(let url) = image.metadata.source, url.pathExtension.lowercased() == "jpg" else { return nil }
            return url
        }.first)
        let folder = URL.temporaryDirectory.appending(component: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(component: "date.jpg")
        try FileManager.default.copyItem(at: source, to: url)
        var state = PhotoTrailState()
        let image = ImageData(metadata: Imagetool.metadata(from: url), name: url.lastPathComponent)
        state.imageData = [image]
        state.backupURL = folder.appending(component: "backup", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: state.backupURL!, withIntermediateDirectories: true)
        let store = Store(initialState: state, reduce: PhotoTrailReducer(), undoEnabled: true)
        let value = "2024:02:29 23:59:59.123456+08:00"
        let plan = try MetadataCreatorEditPlan.prepare([(image, MetadataInspectionSnapshot.read([.captureDate], from: url))],
                                                     tag: .captureDate, action: .setText(value))
        store.send(.creatorDraftApplied(plan.items))
        #expect(store.imageData[0].metadata.dateTimeCreated == value)
        #expect(store.imageData[0].metadata.parsedDate() != nil)
        #expect(!store.imageData[0].hasLegacyChanges)
        #expect(SaveTargets(images: store.imageData).conflicts.isEmpty)
        store.undo()
        #expect(store.imageData[0].metadata == image.metadata)
        store.send(.creatorDraftApplied(plan.items))
        await store.send(.saveRequest) { _ = await SaveHelper.save(store).result }
        #expect(!store.unsavedChanges)
        let reloaded = Imagetool.metadata(from: url)
        #expect(reloaded.dateTimeCreated == value)
        let removal = try MetadataCreatorEditPlan.prepare([(store.imageData[0], MetadataInspectionSnapshot.read([.captureDate], from: url))],
                                                        tag: .captureDate, action: .remove)
        store.send(.creatorDraftApplied(removal.items))
        #expect(store.imageData[0].metadata.parsedDate() == nil)
        await store.send(.saveRequest) { _ = await SaveHelper.save(store).result }
        #expect(!store.unsavedChanges)
        #expect(Imagetool.metadata(from: url).parsedDate() == nil)
    }

    @Test(arguments: [1, 20, 100])
    func fiveFieldsShareOneDraftAndSave(count: Int) async throws {
        let backupKey = PhotoTrailApp.doNotBackupKey
        let previousBackup = UserDefaults.standard.object(forKey: backupKey)
        UserDefaults.standard.set(false, forKey: backupKey)
        defer {
            if let previousBackup { UserDefaults.standard.set(previousBackup, forKey: backupKey) }
            else { UserDefaults.standard.removeObject(forKey: backupKey) }
        }
        let source = try #require(PhotoTrailState(forPreview: true).imageData.compactMap { image -> URL? in
            guard case .image(let url) = image.metadata.source,
                  url.pathExtension.lowercased() == "jpg" else { return nil }
            return url
        }.first)
        let folder = URL.temporaryDirectory.appending(component: UUID().uuidString,
                                                       directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let tags: Set<MetadataTag> = [.creator, .titleDefault, .descriptionDefault, .rightsDefault, .subject]
        let urls = (0..<count).map { folder.appending(component: "sample-\($0).jpg") }
        for (index, url) in urls.enumerated() {
            try FileManager.default.copyItem(at: source, to: url)
            let initial: [MetadataTag: MetadataTagChange] = index % 3 == 0
                ? Dictionary(uniqueKeysWithValues: tags.map { ($0, .remove) })
                : [.titleDefault: .set(.text("Original \(index)")), .descriptionDefault: .set(.text("Existing description")),
                   .creator: .set(.list(["Author \(index)"])), .rightsDefault: .set(.text("© Original")), .subject: .set(.list(["Old"]))]
            _ = try Exiftool.helper.update(image: url, changes: initial)
        }
        var state = PhotoTrailState()
        state.imageData = urls.map {
            ImageData(metadata: Exiftool.helper.metadata(from: nil, primaryURL: $0), name: $0.lastPathComponent)
        }
        state.backupURL = folder.appending(component: "backup", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: state.backupURL!, withIntermediateDirectories: true)
        let store = Store(initialState: state, reduce: PhotoTrailReducer(), undoEnabled: true)
        let snapshots = try urls.map { try MetadataInspectionSnapshot.read(tags, from: $0) }
        func readings() -> [(image: ImageData, snapshot: MetadataInspectionSnapshot)] {
            Array(zip(store.imageData, snapshots)).map { (image: $0.0, snapshot: $0.1) }
        }
        let title = try MetadataCreatorEditPlan.prepare(readings(), tag: .titleDefault, action: .setText("标题，🌿"))
        let before = try urls.map { try Data(contentsOf: $0) }
        #expect(!store.unsavedChanges) // Preview and cancellation never write or create drafts.
        store.send(.creatorDraftApplied(title.items))
        store.undo()
        #expect(!store.unsavedChanges)
        store.send(.creatorDraftApplied(title.items))
        for (tag, action) in [(MetadataTag.descriptionDefault, MetadataFieldEditAction.setText("说明\n第二行")),
                              (.rightsDefault, .setText("© 六九")), (.subject, .replaceKeywords(["Travel", "travel", "Travel"]))] {
            store.send(.creatorDraftApplied(try MetadataCreatorEditPlan.prepare(readings(), tag: tag, action: action).items))
        }
        store.send(.creatorDraftApplied(try MetadataCreatorEditPlan.prepare(readings(), action: .set(["六九"])).items))
        store.send(.creatorDraftApplied(try MetadataCreatorEditPlan.prepare(readings(), tag: .subject,
                                                                           action: .appendKeywords(["Travel", "新词"])).items))
        #expect(store.imageData.allSatisfy { $0.creatorDraft?.changes.count == 5 })
        #expect(try urls.map { try Data(contentsOf: $0) } == before)
        await store.send(.saveRequest) { _ = await SaveHelper.save(store).result }
        #expect(!store.unsavedChanges && store.saveCompleted == count,
                Comment(rawValue: "Save outcomes: \(store.creatorSaveResults.filter { $0.value != .saved && $0.value != .unchanged })"))
        #expect(store.imageData.allSatisfy { $0.creatorDraft == nil })
        for (index, url) in urls.enumerated() {
            let values = try Exiftool.helper.metadataTags(tags, from: url)
            #expect(values[.titleDefault] == .text("标题，🌿"))
            #expect(values[.descriptionDefault] == .text("说明\n第二行"))
            #expect(values[.rightsDefault] == .text("© 六九"))
            #expect(values[.creator] == .list(["六九"]))
            #expect(values[.subject] == .list(["Travel", "travel", "新词"]))
            #expect(try Data(contentsOf: state.backupURL!.appending(component: url.lastPathComponent)) == before[index])
        }
    }

    @Test(.timeLimit(.minutes(1))) func cancellingMetadataSaveKeepsRemainingDrafts() async throws {
        let source = try #require(PhotoTrailState(forPreview: true).imageData.compactMap { image -> URL? in
            guard case .image(let url) = image.metadata.source, url.pathExtension.lowercased() == "jpg" else { return nil }
            return url
        }.first)
        let folder = URL.temporaryDirectory.appending(component: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var state = PhotoTrailState()
        var readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)] = []
        for index in 0..<20 {
            let url = folder.appending(component: "cancel-\(index).jpg")
            try FileManager.default.copyItem(at: source, to: url)
            let image = ImageData(metadata: Exiftool.helper.metadata(from: nil, primaryURL: url), name: url.lastPathComponent)
            state.imageData.append(image)
            readings.append((image, try MetadataInspectionSnapshot.read([.titleDefault], from: url)))
        }
        state.backupURL = folder.appending(component: "backup", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: state.backupURL!, withIntermediateDirectories: true)
        let store = Store(initialState: state, reduce: PhotoTrailReducer())
        store.send(.creatorDraftApplied(try MetadataCreatorEditPlan.prepare(readings, tag: .titleDefault, action: .setText("Cancel test")).items))
        let cancel = Task { @MainActor in
            while store.saveInProgress == false || store.saveCompleted == 0 { try await Task.sleep(for: .milliseconds(5)) }
            store.send(.cancelMetadataSave, undoable: false)
        }
        await store.send(.saveRequest) { _ = await SaveHelper.save(store).result }
        cancel.cancel()
        _ = try? await cancel.value
        #expect(store.metadataSaveCancelled && store.unsavedChanges && !store.saveInProgress)
        #expect(store.saveCompleted >= 1 && store.saveCompleted < 20)
        #expect(store.imageData.filter { $0.creatorDraft != nil }.count == 20 - store.saveCompleted)
        for image in store.imageData where image.creatorDraft != nil {
            #expect(try Exiftool.helper.metadataTags([.titleDefault], from: image.metadataInspectionURL!)[.titleDefault] != .text("Cancel test"))
        }
    }

    @Test func partialSaveClearsOnlySuccessfulCreatorDraft() async throws {
        let source = try #require(PhotoTrailState(forPreview: true).imageData.compactMap { image -> URL? in
            guard case .image(let url) = image.metadata.source,
                  url.pathExtension.lowercased() == "jpg" else { return nil }
            return url
        }.first)
        let folder = URL.temporaryDirectory.appending(component: UUID().uuidString,
                                                       directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let urls = ["first.jpg", "second.jpg"].map { folder.appending(component: $0) }
        for url in urls { try FileManager.default.copyItem(at: source, to: url) }
        let images = urls.map {
            ImageData(metadata: Exiftool.helper.metadata(from: nil, primaryURL: $0),
                      name: $0.lastPathComponent)
        }
        let readings = try zip(images, urls).map { image, url in
            (image: image, snapshot: try MetadataInspectionSnapshot.read([.creator], from: url))
        }
        let plan = try MetadataCreatorEditPlan.prepare(readings, action: .set(["Batch author"]))

        var state = PhotoTrailState()
        state.imageData = images
        state.backupURL = folder.appending(component: "backup", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: state.backupURL!, withIntermediateDirectories: true)
        let store = Store(initialState: state, reduce: PhotoTrailReducer(), undoEnabled: true)
        store.send(.creatorDraftApplied(plan.items))
        #expect(SaveTargets(images: store.imageData).creator == [0, 1])

        _ = try Exiftool.helper.update(image: urls[1],
                                      changes: [.creator: .set(.list(["External author"]))])
        await store.send(.saveRequest) {
            _ = await SaveHelper.save(store).result
        }

        #expect(store.saveTotal == 2 && store.saveCompleted == 2)
        #expect(store.creatorSaveResults[images[0].id] == .saved)
        #expect(store.creatorSaveResults[images[1].id] == .staleSource)
        #expect(store[images[0].id].creatorDraft == nil)
        #expect(store[images[1].id].creatorDraft != nil && store.unsavedChanges)
        #expect(try Exiftool.helper.metadataTags([.creator], from: urls[0])[.creator]
                == .list(["Batch author"]))
        #expect(try Exiftool.helper.metadataTags([.creator], from: urls[1])[.creator]
                == .list(["External author"]))
    }
}
