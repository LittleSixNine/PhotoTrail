import Foundation
import SwiftUI

extension PhotoTrailReducer {
    func getBackupURL(_ state: inout PhotoTrailState) {
        @AppStorage(PhotoTrailApp.savedBookmarkKey) var savedBookmark = Data()
        var staleBookmark = false

        let url = try? URL(resolvingBookmarkData: savedBookmark,
                           options: [.withoutUI, .withSecurityScope],
                           bookmarkDataIsStale: &staleBookmark)
        state.backupURL = url
        if !savedBookmark.isEmpty, url == nil {
            Task { @MainActor in OperationFailure.present(L10n.text("备份目录授权已失效，请重新选择备份文件夹。")) }
        }
        if let url, staleBookmark {
            newBackupFolder(&state, url: url)
        }
    }

    func checkBackupFolderSize(_ state: inout PhotoTrailState) {
        guard let url = state.backupURL else { return }

        let propertyKeys: Set = [
            URLResourceKey.totalFileSizeKey,
            .addedToDirectoryDateKey, .isRegularFileKey
        ]
        let fileManager = FileManager.default
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        var failures: [String] = []
        defer {
            if !failures.isEmpty {
                let message = failures.joined(separator: "\n")
                Task { @MainActor in OperationFailure.present(message) }
            }
        }
        guard let urlEnumerator =
            fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: Array(propertyKeys),
                options: [.skipsHiddenFiles],
                errorHandler: { url, error in
                    failures.append(OperationFailure.message(url.lastPathComponent, error: error)); return true
                }) else {
                    failures.append(L10n.text("备份目录授权已失效，请重新选择备份文件夹。")); return
                }
        let cutoff = SettingsPreferences.backupReminderDays.flatMap {
            Calendar.current.date(byAdding: .day, value: -$0, to: Date())
        }

        // starting state
        state.oldFiles = []
        state.folderSize = 0
        state.deletedSize = 0

        // loop through the files accumulating storage requirements and a count
        // of older files
        while let fileUrl = urlEnumerator.nextObject() as? URL {
            guard let resources =
                    try? fileUrl.resourceValues(forKeys: propertyKeys),
                resources.isRegularFile == true,
                let fileSize = resources.totalFileSize else { continue }
            state.folderSize += fileSize
            if let cutoff, let fileDate = resources.addedToDirectoryDate, fileDate < cutoff {
                state.oldFiles.append(fileUrl)
                state.deletedSize += fileSize
            }
        }
    }

    // remove the files listed in the oldFiles array and clear the array

    @discardableResult
    nonisolated func removeFiles(filesToRemove: [URL], from folder: URL?) -> Task<[String], Never> {
        Task {
            guard let folder else { return [] }
            var failures: [String] = []
            _ = folder.startAccessingSecurityScopedResource()
            defer { folder.stopAccessingSecurityScopedResource() }
            let fileManager = FileManager.default
            for url in filesToRemove {
                do {
                    try fileManager.removeItem(at: url)
                } catch {
                    failures.append(OperationFailure.message(url.lastPathComponent, error: error))
                }
            }
            if !failures.isEmpty { await OperationFailure.present(failures.joined(separator: "\n")) }
            return failures
        }
    }

    func newBackupFolder(_ state: inout PhotoTrailState, url: URL?) {
        @AppStorage(PhotoTrailApp.savedBookmarkKey) var savedBookmark = Data()

        if let url {
            do {
                savedBookmark = try url.bookmarkData(options: .withSecurityScope)
                state.backupURL = url
                checkBackupFolderSize(&state)
           } catch {
                state.backupURL = nil
                state.addSheet(
                    type: .unexpectedErrorSheet,
                    error: error.localizedDescription,
                    message: L10n.text("无法保存备份文件夹的访问权限： %1$@", url.path)
                )
            }
        } else {
            savedBookmark = Data()
        }
    }
}
