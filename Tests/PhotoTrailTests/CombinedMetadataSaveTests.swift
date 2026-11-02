import Coords
@testable import Exiftool
import Foundation
import ImageData
import Imagetool
import Metadata
import Testing
import UDF
@testable import PhotoTrail

@Suite(.serialized) @MainActor
struct CombinedMetadataSaveTests {
    func fixture(sidecar: Bool = false) throws -> (URL, URL, Store<PhotoTrailState, PhotoTrailEvent>) {
        let source = try #require(PhotoTrailState(forPreview: true).imageData.compactMap { image -> URL? in
            guard case .image(let url) = image.metadata.source,
                  url.pathExtension.lowercased() == "jpg" else { return nil }
            return url
        }.first)
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("combined.jpg")
        try FileManager.default.copyItem(at: source, to: url)
        if sidecar {
            let sandbox = try Sandbox(for: url)
            defer { sandbox.removeSandboxFolder() }
            try sandbox.makeSidecarFile()
        }
        let xmp = sidecar ? url.deletingPathExtension().appendingPathExtension("xmp") : nil
        let metadata = sidecar ? Exiftool.helper.metadata(from: xmp, primaryURL: url) : Imagetool.metadata(from: url)
        var state = PhotoTrailState()
        state.imageData = [ImageData(metadata: metadata, name: url.lastPathComponent)]
        state.backupURL = folder.appendingPathComponent("backup")
        try FileManager.default.createDirectory(at: state.backupURL!, withIntermediateDirectories: true)
        return (folder, xmp ?? url, Store(initialState: state, reduce: PhotoTrailReducer(), undoEnabled: true))
    }

    func settings() -> () -> Void {
        let keys = [PhotoTrailApp.doNotBackupKey, SettingsView.addTagsKey,
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

    func addMap(_ store: Store<PhotoTrailState, PhotoTrailEvent>) {
        let id = store.imageData[0].id
        store.send(.selectionChanged([id]))
        store.send(.locationChanged(Coords(latitude: -33.75, longitude: 151.25)))
    }

    func addFields(_ store: Store<PhotoTrailState, PhotoTrailEvent>, target: URL, removeDate: Bool = false) throws {
        let image = store.imageData[0]
        let dateTag: MetadataTag = if case .xmp = image.metadata.source { .sidecarDate } else { .captureDate }
        let snapshot = try MetadataInspectionSnapshot.read(Set(MetadataTag.allCases), from: target)
        let date: MetadataFieldEditAction = removeDate ? .remove : .setText("2026:10:31 21:40:05.123+08:00")
        let plan = try MetadataWorkflowPreview.prepare([(image, snapshot)], operations: [
            MetadataOperation(tag: dateTag, action: date),
            MetadataOperation(tag: .dateOriginal, action: .setText("2024:01:02 03:04:05")),
            MetadataOperation(tag: .creator, action: .replaceAuthors(["Photographer"])),
            MetadataOperation(tag: .descriptionDefault, action: .setText("e\u{301}，🌿"))
        ])
        store.send(.creatorDraftApplied(plan.items))
    }

    @Test(arguments: [false, true])
    func savesBothWithOneOriginalBackupAndPreservesIndependentDates(sidecar: Bool) async throws {
        let restore = settings(); defer { restore() }
        let (folder, target, store) = try fixture(sidecar: sidecar)
        defer { try? FileManager.default.removeItem(at: folder) }
        let before = try Data(contentsOf: target)
        let pixels = sidecar ? nil : try Exiftool.helper.run(["-s3", "-ImageDataMD5", target.path])
        try addFields(store, target: target)
        addMap(store)
        let pending = store.imageData[0]
        #expect(pending.hasLegacyChanges && !pending.hasLegacyDateChanges)
        let targets = SaveTargets(images: store.imageData)
        #expect(targets.conflicts.isEmpty && targets.total == 1 && targets.combined == [0])
        await store.send(.saveRequest) { _ = await SaveHelper.save(store).result }
        #expect(store.saveFailures.isEmpty && !store.unsavedChanges)
        #expect(store.imageData[0].creatorDraft == nil && !store.imageData[0].hasLegacyChanges)
        #expect(store.saveCompleted == 1 && store.saveTotal == 1)
        #expect(store.locationSavedPhotoIDs.contains(pending.id))
        let values = try Exiftool.helper.metadataTags([sidecar ? .sidecarDate : .captureDate, .dateOriginal,
                                                     .creator, .descriptionDefault], from: target)
        #expect(values[sidecar ? .sidecarDate : .captureDate] == .text("2026:10:31 21:40:05.123+08:00"))
        #expect(values[.dateOriginal] == .text("2024:01:02 03:04:05"))
        #expect(values[.descriptionDefault] == .text("e\u{301}，🌿"))
        try Exiftool.helper.verifyMapMetadata(store.imageData[0].metadata, in: target)
        if let pixels { #expect(try Exiftool.helper.run(["-s3", "-ImageDataMD5", target.path]) == pixels) }
        let backups = try FileManager.default.contentsOfDirectory(at: store.backupURL!, includingPropertiesForKeys: nil)
        #expect(backups.count == 1)
        #expect(try Data(contentsOf: #require(backups.first)) == before)
        let reloaded = Exiftool.helper.metadata(from: sidecar ? target : nil,
                                               primaryURL: folder.appendingPathComponent("combined.jpg"))
        #expect(reloaded.location == store.imageData[0].metadata.location)
    }

    @Test func mapFirstCanEditFieldsAndClearedDateStaysCleared() async throws {
        let restore = settings(); defer { restore() }
        let (folder, target, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        addMap(store)
        let image = store.imageData[0]
        let snapshot = try MetadataInspectionSnapshot.read([.creator], from: target)
        #expect(MetadataDraftRequest(readings: [(image, snapshot)]).matches(store.state, checkFiles: true))
        try MetadataQuickEdit.apply(.replaceAuthors(["A"]), tag: .creator,
                                    readings: [(image, snapshot)], store: store)
        #expect(store.imageData[0].creatorDraft != nil)
        try addFields(store, target: target, removeDate: true)
        await store.send(.saveRequest) { _ = await SaveHelper.save(store).result }
        #expect(store.saveFailures.isEmpty && !store.unsavedChanges)
        #expect(try Exiftool.helper.metadataTags([.captureDate], from: target)[.captureDate] == nil)
        #expect(Imagetool.metadata(from: target).dateTimeCreated == nil)
    }

    @Test func staleSourceAndFailedBackupKeepBothDraftsAndDoNotWrite() async throws {
        let restore = settings(); defer { restore() }
        let (folder, target, initial) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        try addFields(initial, target: target); addMap(initial)
        let id = initial.imageData[0].id
        let badBackup = folder.appendingPathComponent("not-a-folder")
        try Data("file".utf8).write(to: badBackup)
        var state = initial.state
        state.backupURL = badBackup
        let store = Store(initialState: state, reduce: PhotoTrailReducer())
        let before = try Data(contentsOf: target)
        await store.send(.saveRequest) { _ = await SaveHelper.save(store).result }
        #expect(store.unsavedChanges && store.imageData[0].creatorDraft != nil && store.imageData[0].hasLegacyChanges)
        #expect(try Data(contentsOf: target) == before)
        _ = try Exiftool.helper.update(image: target, changes: [.titleDefault: .set(.text("External"))])
        let external = try Data(contentsOf: target)
        await store.send(.saveRequest) { _ = await SaveHelper.save(store).result }
        #expect(store.creatorSaveResults[id] == .staleSource)
        #expect(try Data(contentsOf: target) == external)
    }

    @Test func duplicateTargetsAndConflictingLegacyDatesStayBlocked() throws {
        let (folder, target, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        try addFields(store, target: target); addMap(store)
        var other = ImageData(metadata: Imagetool.metadata(from: target), name: "duplicate.jpg")
        other.metadata.location = Coords(latitude: 1, longitude: 2)
        #expect(!SaveTargets(images: store.imageData + [other]).conflicts.isEmpty)
        #expect(!SaveTargets(images: store.imageData, scope: .map).conflicts.isEmpty)
        var image = store.imageData[0]
        image.metadata.dateTimeCreated = "2020:01:01 00:00:00"
        #expect(!SaveTargets(images: [image]).conflicts.isEmpty)
        image.metadata.dateTimeCreated = image.original?.dateTimeCreated
        #expect(!SaveTargets(images: [image]).conflicts.isEmpty)
    }

    @Test func metadataOnlyLeavesLocationPending() async throws {
        let restore = settings(); defer { restore() }
        let (folder, target, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = Exiftool.helper.metadata(from: nil, primaryURL: target)
        try addFields(store, target: target); addMap(store)
        #expect(SaveTargets(images: store.imageData, scope: .metadata).combined.isEmpty)
        await store.send(.savePageRequest(.metadata)) { _ = await SaveHelper.save(store).result }
        #expect(store.imageData[0].creatorDraft == nil && store.imageData[0].hasLegacyChanges && store.unsavedChanges)
        try Exiftool.helper.verifyMapMetadata(original, in: target)
    }

    @Test func mapOnlyPreferenceOffersCombinedSaveWithoutChangingPreference() throws {
        let keys = [SettingsPreferences.saveCurrentPageKey, SettingsPreferences.lastWorkspaceKey,
                    SettingsPreferences.skipSaveScopePromptKey]
        let old = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, old) {
                if let value { UserDefaults.standard.set(value, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
        UserDefaults.standard.set(true, forKey: keys[0])
        UserDefaults.standard.set("map", forKey: keys[1])
        UserDefaults.standard.set(true, forKey: keys[2])
        let (folder, target, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        try addFields(store, target: target); addMap(store)
        var offeredCombined = false
        #expect(!SaveHelper.requestSave(store, confirm: { targets in
            offeredCombined = targets.total == 1 && targets.combined == [0] && targets.conflicts.isEmpty
            return false
        }))
        #expect(offeredCombined && store.unsavedChanges && !store.saveInProgress)
        #expect(UserDefaults.standard.bool(forKey: keys[0]))
    }
}
