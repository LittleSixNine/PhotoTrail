import AppKit
import Coords
import Exiftool
import ImageData
import Imagetool
import Metadata
import Phototool
import OSLog
import SwiftUI
import UDF

@MainActor
enum SaveHelper {
    enum SaveStatus {
        case saveOK                     // All changes saved
        case saveError                  // Save issue, tell user
        case saveErrorSupressWarning    // Save issue, user knows
        case saveTagError               // Metadata saved, optional Finder tag failed
    }

    enum FileSaveOutcome: Equatable, Sendable {
        case failed
        case saved
        case savedWithoutTag

        var metadataSaved: Bool { self != .failed }
    }

    nonisolated static func saveThenTag(
        save: () async throws -> Void,
        tag: (() async throws -> Void)?
    ) async -> FileSaveOutcome {
        do {
            try await save()
        } catch {
            return .failed
        }
        guard let tag else { return .saved }
        do {
            try await tag()
            return .saved
        } catch {
            return .savedWithoutTag
        }
    }

    enum MetadataTagSaveStatus: Equatable {
        case saved
        case failed
        case resultUnknown
    }

    nonisolated static func saveMetadataTags(
        image: URL,
        changes: [MetadataTag: MetadataTagChange]
    ) -> MetadataTagSaveStatus {
        saveMetadataTags(
            image: image,
            changes: changes,
            update: { try Exiftool.helper.update(image: $0, changes: $1) },
            readback: { try Exiftool.helper.metadataTags($0, from: $1) })
    }

    nonisolated static func saveMetadataTags(
        image: URL,
        changes: [MetadataTag: MetadataTagChange],
        update: (URL, [MetadataTag: MetadataTagChange]) throws -> [MetadataTag: MetadataTagValue],
        readback: (Set<MetadataTag>, URL) throws -> [MetadataTag: MetadataTagValue]
    ) -> MetadataTagSaveStatus {
        do {
            _ = try update(image, changes)
            return .saved
        } catch let error as MetadataTagUpdateError where error.resultIsUnknown {
            guard let values = try? readback(Set(changes.keys), image) else {
                return .resultUnknown
            }
            for (tag, change) in changes {
                switch change {
                case .set(let expected) where !tag.matches(values[tag], expected):
                    return .resultUnknown
                case .remove where values[tag] != nil:
                    return .resultUnknown
                default:
                    break
                }
            }
            return .saved
        } catch {
            return .failed
        }
    }

    @discardableResult
    static func requestSave(_ store: Store<PhotoTrailState, PhotoTrailEvent>,
                            confirm: ((SaveTargets) -> Bool)? = nil,
                            workspace: LocationWorkspace? = nil, forceAll: Bool = false) -> Bool {
        // Finish native inline editing first; invalid input keeps focus and blocks writing an older value.
        if let window = store.mainWindow, !window.makeFirstResponder(nil) { return false }
        guard !store.saveInProgress, store.unsavedChanges else { return false }
        var scope = forceAll ? MetadataSaveScope.all : preferredScope
        var targets = SaveTargets(images: store.imageData, scope: scope)
        guard targets.conflicts.isEmpty else {
            store.send(.creatorSaveConflict, undoable: false)
            return false
        }
        guard targets.total > 0 else { return false }
        let prompt = !forceAll && scope == .all && !UserDefaults.standard.bool(forKey: SettingsPreferences.skipSaveScopePromptKey)
        if let confirm {
            guard confirm(targets) else { return false }
        } else if ProcessInfo.processInfo.environment["PHOTOTRAIL_OFFLINE_TESTS"] != "1",
                  prompt || UserDefaults.standard.bool(forKey: SettingsPreferences.showSaveSummaryKey) {
            guard let chosen = confirmSave(targets, backupURL: store.backupURL, scope: scope,
                                           allowCurrentPage: !forceAll, showScopeOptions: prompt) else { return false }
            scope = chosen
            targets = SaveTargets(images: store.imageData, scope: scope)
            guard targets.conflicts.isEmpty, targets.total > 0 else { return false }
        }
        let event: PhotoTrailEvent = scope == .all ? .saveRequest : .savePageRequest(scope)
        store.send(event, undoable: false) { save(store, workspace: workspace) }
        store.discardAllUndo()
        return true
    }

    @discardableResult
    static func save(_ store: Store<PhotoTrailState, PhotoTrailEvent>, workspace: LocationWorkspace? = nil) -> Task<Void, Never> {
        // capture the data needed to update images
        let libraryImages =
            Dictionary(uniqueKeysWithValues: store.libraryImages.map {
                (store.imageData[$0].id, store.imageData[$0].metadata
                    .forSaving(comparedTo: store.imageData[$0].original))
            })
        let fileImages =
            Dictionary(uniqueKeysWithValues: store.fileImages.map {
                (store.imageData[$0].id, store.imageData[$0].metadata
                    .forSaving(comparedTo: store.imageData[$0].original))
            })
        let xmpImages =
            Dictionary(uniqueKeysWithValues: store.xmpImages.map {
                (store.imageData[$0].id, store.imageData[$0].metadata
                    .forSaving(comparedTo: store.imageData[$0].original))
            })
        let creatorItems = store.creatorImages.compactMap {
            store.imageData[$0].creatorDraft
        }
        // Do the save in the background, report when done.
        let task = Task {
            let resolvedFiles = await resolveAddresses(fileImages, images: store.imageData, workspace: workspace)
            let resolvedXmp = await resolveAddresses(xmpImages, images: store.imageData, workspace: workspace)
            async let libUpdated = saveToLibrary(store, libraryImages)
            async let imgUpdated = saveToImage(store, resolvedFiles)
            async let xmpUpdated = saveToImage(store, resolvedXmp, xmp: true)

            let legacyStatus = await [libUpdated, imgUpdated, xmpUpdated]
            // Do not write a physical target concurrently with the legacy save.
            let creatorStatus = await saveToCreator(store, creatorItems)
            let status = legacyStatus + [creatorStatus]

            let sendStatus: SaveStatus =
                if status.allSatisfy({ $0 == .saveOK }) {
                    .saveOK
                } else if status.contains(.saveError) {
                    .saveError
                } else if status.contains(.saveErrorSupressWarning) {
                    .saveErrorSupressWarning
                } else {
                    .saveTagError
                }
            store.send(.saveComplete(sendStatus), undoable: false)
        }
        return task
    }

    static func resolveAddresses(_ snapshots: [ImageData.ID: Metadata], images: [ImageData],
                                 workspace: LocationWorkspace?) async -> [ImageData.ID: Metadata] {
        guard let workspace else { return snapshots }
        guard UserDefaults.standard.object(forKey: SettingsPreferences.writeRegionKey) as? Bool != false else {
            return snapshots
        }
        let locationChanged = Dictionary(uniqueKeysWithValues: images.map {
            ($0.id, $0.metadata.location != $0.original?.location)
        })
        let provider = UserDefaults.standard.string(forKey: "PhotoTrailMapProvider") ?? "amap"
        var resolved = snapshots
        for (id, snapshot) in snapshots {
            guard let point = snapshot.location, snapshot.canDisplayAsWGS84,
                  locationChanged[id] == true else { continue }
            var metadata = snapshot
            metadata.city = nil
            metadata.state = nil
            metadata.sublocation = nil
            metadata.country = nil
            metadata.countryCode = nil
            do {
                let address = try await workspace.address(at:
                    MapCoordinate(latitude: point.latitude, longitude: point.longitude), provider: provider)
                metadata.city = address.city
                metadata.state = address.state
                metadata.sublocation = address.sublocation
                metadata.country = address.country
                metadata.countryCode = address.countryCode
            } catch {
                logger.notice("Address lookup failed; saving coordinates without region fields for photo ID \(id)")
            }
            resolved[id] = metadata
        }
        return resolved
    }

    static func saveToLibrary(_ store: Store<PhotoTrailState, PhotoTrailEvent>,
                              _ info: [ImageData.ID: Metadata]) async -> SaveStatus {
        var saveStatus: SaveStatus = .saveOK
        for (id, metadata) in info {
            if case .photos(_, let asset) = metadata.source, let asset {
                let timestamp = metadata.date()
                let location = metadata.clLocation(nil)
                let ok = await Phototool.update(timestamp: timestamp,
                                                location: location,
                                                for: asset,
                                                updateLocation: !metadata.preserveGPSOnSave)
                if ok {
                    store.send(.imageSaved(id, metadata), undoable: false)
                } else {
                    saveStatus = .saveError
                }
                store.send(.saveProgress(1), undoable: false)
            }
        }
        return saveStatus
    }

    // pass copy of MainActor related data to a nonisolated function
    // that will perform updates in parallel

    static func saveToImage(_ store: Store<PhotoTrailState, PhotoTrailEvent>,
                            _ info: [ImageData.ID: Metadata],
                            xmp: Bool = false) async -> SaveStatus {
        @AppStorage(PhotoTrailApp.doNotBackupKey) var doNotBackup = false
        @AppStorage(SettingsView.addTagsKey) var addTags = false
        @AppStorage(SettingsView.finderTagKey) var finderTag = "PhotoTrail"
        @AppStorage(SettingsView.createSidecarFilesKey) var createSidecarFiles = false

        // make sure there is something to do
        guard !info.isEmpty else { return .saveOK }

        // make sure backups are disabled or we have a backup folder
        guard doNotBackup || store.backupURL != nil else {
            store.send(.noBackupNotice, undoable: false)
            return .saveErrorSupressWarning
        }
        let backupURL = doNotBackup ? nil : store.backupURL
        let tagName = finderTag.isEmpty ? "PhotoTrail" : finderTag

        // common work done, image vs xmp updates are slightly different
        if xmp {
            return await saveToXmpTasks(store, info, backupURL, store.timeZone,
                                        addTags, tagName)
        }
        return await saveToImageTasks(store, info, createSidecarFiles,
                                      backupURL, store.timeZone,
                                      addTags, tagName)
    }

    struct LocalSaveResult: Equatable, Sendable {
        let id: ImageData.ID
        let metadata: Metadata
        let sidecarCreated: Bool
        let outcome: FileSaveOutcome
    }

    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "PhotoTrail", category: "Save")
    nonisolated private static let signposter = OSSignposter(logger: logger)

    // swiftlint:disable:next function_parameter_count
    nonisolated static func saveToImageTasks(_ store: Store<PhotoTrailState, PhotoTrailEvent>,
                                             _ info: [ImageData.ID: Metadata],
                                             _ createSidecarFiles: Bool,
                                             _ backupURL: URL?,
                                             _ timeZone: TimeZone?,
                                             _ tagFiles: Bool,
                                             _ tagName: String) async -> SaveStatus {
        await saveLocalTasks(store, info, sidecar: false, createSidecar: createSidecarFiles,
                             backup: backupURL, timeZone: timeZone, tagFiles: tagFiles, tagName: tagName)
    }

    // swiftlint:disable:next function_parameter_count
    nonisolated static func saveToXmpTasks(_ store: Store<PhotoTrailState, PhotoTrailEvent>,
                                           _ info: [ImageData.ID: Metadata],
                                           _ backupURL: URL?,
                                           _ timeZone: TimeZone?,
                                           _ tagFiles: Bool,
                                           _ tagName: String) async -> SaveStatus {
        await saveLocalTasks(store, info, sidecar: true, createSidecar: false,
                             backup: backupURL, timeZone: timeZone, tagFiles: tagFiles, tagName: tagName)
    }

    // swiftlint:disable:next function_parameter_count
    nonisolated private static func saveLocalTasks(
        _ store: Store<PhotoTrailState, PhotoTrailEvent>, _ info: [ImageData.ID: Metadata],
        sidecar: Bool, createSidecar: Bool, backup: URL?, timeZone: TimeZone?,
        tagFiles: Bool, tagName: String
    ) async -> SaveStatus {
        let started = ContinuousClock.now
        var failed = 0
        var tagFailed = 0
        var status: SaveStatus = .saveOK
        func buildResult(id: ImageData.ID) async -> LocalSaveResult {
            var metadata = info[id]!
            var created = false
            let imageURL: URL
            switch metadata.source {
            case .image(let url) where !sidecar: imageURL = url
            case .xmp(let url) where sidecar: imageURL = url
            default: return LocalSaveResult(id: id, metadata: metadata, sidecarCreated: false, outcome: .failed)
            }
            let interval = signposter.beginInterval("SaveFile", id: signposter.makeSignpostID())
            defer { signposter.endInterval("SaveFile", interval) }
            do {
                let sandbox = try Sandbox(for: imageURL)
                defer { sandbox.removeSandboxFolder() }
                if let backup {
                    let backupInterval = signposter.beginInterval("Backup", id: signposter.makeSignpostID())
                    defer { signposter.endInterval("Backup", backupInterval) }
                    if sidecar { try await sandbox.makeSidecarBackup(backup) }
                    else { try await sandbox.makeImageBackup(backup) }
                }
                if createSidecar {
                    try sandbox.makeSidecarFile()
                    created = true
                    metadata = metadata.xmp()
                }
                let writeInterval = signposter.beginInterval("WriteMetadata", id: signposter.makeSignpostID())
                let frozenMetadata = metadata
                let outcome = await saveThenTag(
                    save: { try await sandbox.saveChanges(from: frozenMetadata, timeZone: timeZone) },
                    tag: tagFiles ? { try await sandbox.setTag(name: tagName) } : nil)
                signposter.endInterval("WriteMetadata", writeInterval)
                if outcome == .failed { logger.error("Metadata write failed for photo ID \(id)") }
                return LocalSaveResult(id: id, metadata: metadata, sidecarCreated: created, outcome: outcome)
            } catch {
                logger.error("Save preparation failed for photo ID \(id): \(error.localizedDescription, privacy: .private)")
                return LocalSaveResult(id: id, metadata: metadata, sidecarCreated: created, outcome: .failed)
            }
        }
        await withTaskGroup(of: LocalSaveResult.self) { group in
            let ids = Array(info.keys)
            var next = min(ids.count, PhotoTrailApp.maxConcurrentSaves)
            for index in 0..<next { group.addTask { await buildResult(id: ids[index]) } }
            var pending: [LocalSaveResult] = []
            var published = ContinuousClock.now
            for await result in group {
                // Replenish disk work before waiting for any UI publication.
                if next < ids.count {
                    let id = ids[next]
                    next += 1
                    group.addTask { await buildResult(id: id) }
                }
                if result.outcome == .failed { failed += 1; status = .saveError }
                if result.outcome == .savedWithoutTag {
                    tagFailed += 1
                    if status == .saveOK { status = .saveTagError }
                }
                pending.append(result)
                // Bounded batches avoid a main-thread round trip and a whole-state update per file.
                if pending.count >= 32 || published.duration(to: .now) >= .milliseconds(150) {
                    let batch = pending
                    pending.removeAll(keepingCapacity: true)
                    await MainActor.run { store.send(.localSaveBatch(batch), undoable: false) }
                    published = .now
                }
            }
            if !pending.isEmpty {
                let batch = pending
                await MainActor.run { store.send(.localSaveBatch(batch), undoable: false) }
            }
        }
        logger.info("Local save finished: \(info.count) files, \(failed) failed, \(tagFailed) tag failures, wall time \(String(describing: started.duration(to: .now)), privacy: .public)")
        return status
    }

}

extension SaveHelper {
    static func saveToCreator(
        _ store: Store<PhotoTrailState, PhotoTrailEvent>,
        _ items: [MetadataCreatorEditPlan.Item]
    ) async -> SaveStatus {
        @AppStorage(PhotoTrailApp.doNotBackupKey) var doNotBackup = false
        guard !items.isEmpty else { return .saveOK }
        guard doNotBackup || store.backupURL != nil else {
            store.send(.noBackupNotice, undoable: false)
            return .saveErrorSupressWarning
        }
        let backup: MetadataCreatorBackup =
            if doNotBackup { .disabled } else { .folder(store.backupURL!) }
        var status: SaveStatus = .saveOK
        for item in items {
            if store.metadataSaveCancelled { break }
            if store.creatorSaveResults[item.id] == .resultUnknown {
                status = .saveError
                store.send(.saveProgress(1), undoable: false)
                continue
            }
            let result = await item.save(backup: backup)
            store.send(.creatorSaveResult(item.id, result), undoable: false)
            if result == .saved || result == .unchanged {
                store.send(.creatorSaved(item.id), undoable: false)
            } else {
                status = .saveError
            }
            store.send(.saveProgress(1), undoable: false)
        }
        return status
    }
}

extension SaveHelper {
    static var currentPageScope: MetadataSaveScope {
        UserDefaults.standard.string(forKey: SettingsPreferences.lastWorkspaceKey) == "map" ? .map : .metadata
    }

    static var preferredScope: MetadataSaveScope {
        guard UserDefaults.standard.bool(forKey: SettingsPreferences.saveCurrentPageKey),
              UserDefaults.standard.string(forKey: SettingsPreferences.lastWorkspaceKey) != "rename" else { return .all }
        return currentPageScope
    }

    private static func confirmSave(_ targets: SaveTargets, backupURL: URL?, scope: MetadataSaveScope,
                                    allowCurrentPage: Bool, showScopeOptions: Bool) -> MetadataSaveScope? {
        let localCount = targets.files.count + targets.xmp.count + targets.creator.count
        let backupMessage: String
        if localCount == 0 {
            backupMessage = L10n.text("本次不写入本地文件；备份设置不适用。")
        } else if UserDefaults.standard.bool(forKey: PhotoTrailApp.doNotBackupKey) {
            backupMessage = L10n.text("本地文件备份：已关闭。")
        } else if backupURL != nil {
            backupMessage = L10n.text("本地文件备份：已开启；照片图库项目不在备份范围内。")
        } else {
            backupMessage = L10n.text("尚未设置备份文件夹，本地照片和 XMP 将无法保存；照片图库仍可能更新。")
        }
        let sidecarMessage = targets.files.isEmpty ||
            !UserDefaults.standard.bool(forKey: SettingsView.createSidecarFilesKey)
            ? "" : L10n.text("\n本地照片另会尝试创建 XMP 附属文件。")

        let alert = NSAlert()
        alert.messageText = scope == .all ? L10n.text("同时保存两个页面的元数据？") : L10n.text("保存当前页的元数据？")
        alert.informativeText = L10n.text(
            "本地照片：%1$@ 项\n已导入的 XMP：%2$@ 项\n照片图库：%3$@ 项\n\n%4$@%5$@",
            targets.files.count + targets.creatorFiles,
            targets.xmp.count + targets.creator.count - targets.creatorFiles,
            targets.library.count, backupMessage, sidecarMessage)
            + "\n\n" + (scope == .all
                ? L10n.text("保存元数据编辑和地图定位两个页面的全部待保存修改，不限当前页或选中的照片。")
                : L10n.text("只保存当前页的待保存修改，其他页修改保留。"))
        alert.addButton(withTitle: L10n.text("保存"))
        alert.addButton(withTitle: L10n.text("取消"))
        if showScopeOptions {
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = L10n.text("下次不再提示")
            if allowCurrentPage { alert.addButton(withTitle: L10n.text("改为仅保存本页")) }
        }
        let response = alert.runModal()
        guard response != .alertSecondButtonReturn else { return nil }
        if showScopeOptions, alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(true, forKey: SettingsPreferences.skipSaveScopePromptKey)
        }
        if response == .alertThirdButtonReturn {
            UserDefaults.standard.set(true, forKey: SettingsPreferences.saveCurrentPageKey)
            return nil
        }
        return scope
    }

}
