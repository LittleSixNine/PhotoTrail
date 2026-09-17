import AppKit
import ImageData
import Imagetool
import Metadata
import Phototool
import SwiftUI
import UDF

@MainActor
enum SaveHelper {
    enum SaveStatus {
        case saveOK                     // All changes saved
        case saveError                  // Save issue, tell user
        case saveErrorSupressWarning    // Save issue, user knows
    }

    @discardableResult
    static func requestSave(_ store: Store<GeoTagState, GeoTagEvent>,
                            confirm: ((SaveTargets) -> Bool)? = nil) -> Bool {
        guard !store.saveInProgress, store.unsavedChanges else { return false }
        let targets = SaveTargets(images: store.imageData)
        if targets.total > 0,
           UserDefaults.standard.bool(forKey: SettingsPreferences.showSaveSummaryKey),
           !(confirm?(targets) ?? confirmSave(targets, backupURL: store.backupURL)) {
            return false
        }
        store.send(.saveRequest, undoable: false) { save(store) }
        store.discardAllUndo()
        return true
    }

    private static func confirmSave(_ targets: SaveTargets, backupURL: URL?) -> Bool {
        let localCount = targets.files.count + targets.xmp.count
        let backupMessage: String
        if localCount == 0 {
            backupMessage = "本次不写入本地文件；备份设置不适用。"
        } else if UserDefaults.standard.bool(forKey: GeoTagApp.doNotBackupKey) {
            backupMessage = "本地文件备份：已关闭。"
        } else if backupURL != nil {
            backupMessage = "本地文件备份：已开启；照片图库项目不在备份范围内。"
        } else {
            backupMessage = "尚未设置备份文件夹，本地照片和 XMP 将无法保存；照片图库仍可能更新。"
        }
        let sidecarMessage = targets.files.isEmpty ||
            !UserDefaults.standard.bool(forKey: SettingsView.createSidecarFilesKey)
            ? "" : "\n本地照片另会尝试创建 XMP 附属文件。"

        let alert = NSAlert()
        alert.messageText = "保存 \(targets.total) 项修改？"
        alert.informativeText = """
            本地照片：\(targets.files.count) 项
            已导入的 XMP：\(targets.xmp.count) 项
            照片图库：\(targets.library.count) 项

            \(backupMessage)\(sidecarMessage)
            """
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }

    @discardableResult
    static func save(_ store: Store<GeoTagState, GeoTagEvent>) -> Task<Void, Never> {
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
        // Do the save in the background, report when done.
        let task = Task {
            async let libUpdated = saveToLibrary(store, libraryImages)
            async let imgUpdated = saveToImage(store, fileImages)
            async let xmpUpdated = saveToImage(store, xmpImages, xmp: true)

            let status = await [libUpdated, imgUpdated, xmpUpdated]

            let sendStatus: SaveStatus =
                if status.allSatisfy({ $0 == .saveOK }) {
                    .saveOK
                } else if status.contains(.saveErrorSupressWarning) {
                    .saveErrorSupressWarning
                } else {
                    .saveError
                }
            store.send(.saveComplete(sendStatus), undoable: false)
        }
        return task
    }

    static func saveToLibrary(_ store: Store<GeoTagState, GeoTagEvent>,
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

    static func saveToImage(_ store: Store<GeoTagState, GeoTagEvent>,
                            _ info: [ImageData.ID: Metadata],
                            xmp: Bool = false) async -> SaveStatus {
        @AppStorage(GeoTagApp.doNotBackupKey) var doNotBackup = false
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

    // Update the items in the info dictionary in a task group

    // swiftlint:disable:next function_parameter_count
    nonisolated static func saveToImageTasks(_ store: Store<GeoTagState, GeoTagEvent>,
                                             _ info: [ImageData.ID: Metadata],
                                             _ createSidecarFiles: Bool,
                                             _ backupURL: URL?,
                                             _ timeZone: TimeZone?,
                                             _ tagFiles: Bool,
                                             _ tagName: String) async -> SaveStatus {
        struct TaskInfo {
            let id: ImageData.ID
            let metadata: Metadata
            let sidecarCreated: Bool
            let status: Bool
        }

        var taskInfos: [TaskInfo] = []
        var saveStatus: SaveStatus = .saveOK

        func buildTaskInfo(id: ImageData.ID) async -> TaskInfo {
            let metadata = info[id]!
            guard case .image(let imageURL) = metadata.source else {
                return TaskInfo(id: id, metadata: metadata,
                                sidecarCreated: false, status: false)
            }

            var sidecarCreated = false
            do {
                let sandbox = try Sandbox(for: imageURL)
                if createSidecarFiles {
                    try sandbox.makeSidecarFile()
                    sidecarCreated = true
                }
                if let backupURL {
                    try await sandbox.makeBackupFile(backupFolder: backupURL)
                }
                try await sandbox.saveChanges(from: metadata,
                                              timeZone: timeZone)
                if tagFiles {
                    try await sandbox.setTag(name: tagName)
                }
                return TaskInfo(id: id, metadata: metadata,
                                sidecarCreated: sidecarCreated,
                                status: true)
            } catch {
                return TaskInfo(id: id, metadata: metadata,
                                sidecarCreated: sidecarCreated,
                                status: false)
            }
        }

        await withTaskGroup(of: TaskInfo.self) { group in
            let ids = Array(info.keys)
            var limit = min(ids.count, GeoTagApp.maxConcurrentTasks)
            for ix in 0..<limit {
                group.addTask { return await buildTaskInfo(id: ids[ix]) }
            }

            for await taskInfo in group {
                taskInfos.append(taskInfo)
                await MainActor.run { store.send(.saveProgress(1), undoable: false) }
                if limit < ids.count {
                    let id = ids[limit]
                    limit += 1
                    group.addTask { return await buildTaskInfo(id: id) }
                }
            }
        }
        // Update state from the created TaskInfo on MainActor
        await MainActor.run {
            for taskInfo in taskInfos {
                if taskInfo.sidecarCreated {
                    store.send(.sidecarCreated(taskInfo.id), undoable: false)
                }
                if taskInfo.status {
                    store.send(.imageSaved(taskInfo.id, taskInfo.metadata),
                               undoable: false)
                } else {
                    saveStatus = .saveError
                }
            }
        }
        return saveStatus
    }

    // swiftlint:disable:next function_parameter_count
    nonisolated static func saveToXmpTasks(_ store: Store<GeoTagState, GeoTagEvent>,
                                           _ info: [ImageData.ID: Metadata],
                                           _ backupURL: URL?,
                                           _ timeZone: TimeZone?,
                                           _ tagFiles: Bool,
                                           _ tagName: String) async -> SaveStatus {
        struct TaskInfo {
            let id: ImageData.ID
            let metadata: Metadata
            let status: Bool
        }

        var taskInfos: [TaskInfo] = []
        var saveStatus: SaveStatus = .saveOK

        func buildTaskInfo(id: ImageData.ID) async -> TaskInfo {
            let metadata = info[id]!
            guard case .xmp(let imageURL) = metadata.source else {
                return TaskInfo(id: id, metadata: metadata,
                                status: false)
            }

            do {
                let sandbox = try Sandbox(for: imageURL)
                if let backupURL {
                    try await sandbox.makeSidecarBackup(backupURL)
                }
                try await sandbox.saveChanges(from: metadata,
                                              timeZone: timeZone)
                if tagFiles {
                    try await sandbox.setTag(name: tagName)
                }
                return TaskInfo(id: id, metadata: metadata,
                                status: true)
            } catch {
                return TaskInfo(id: id, metadata: metadata,
                                status: false)
            }
        }

        await withTaskGroup(of: TaskInfo.self) { group in
            let ids = Array(info.keys)
            var limit = min(ids.count, GeoTagApp.maxConcurrentTasks)
            for ix in 0..<limit {
                group.addTask { return await buildTaskInfo(id: ids[ix]) }
            }

            for await taskInfo in group {
                taskInfos.append(taskInfo)
                await MainActor.run { store.send(.saveProgress(1), undoable: false) }
                if limit < ids.count {
                    let id = ids[limit]
                    limit += 1
                    group.addTask { return await buildTaskInfo(id: id) }
                }
            }
        }


        // Update state from the created TaskInfo on MainActor
        await MainActor.run {
            for taskInfo in taskInfos {
                if taskInfo.status {
                    store.send(.imageSaved(taskInfo.id, taskInfo.metadata),
                               undoable: false)
                } else {
                    saveStatus = .saveError
                }
            }
        }
        return saveStatus
    }
}
