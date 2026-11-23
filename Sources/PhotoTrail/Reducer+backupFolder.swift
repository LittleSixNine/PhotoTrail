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
        state.backupScanID = UUID()
        state.oldFiles = []
        state.folderSize = 0
        state.deletedSize = 0
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
            state.backupURL = nil
            checkBackupFolderSize(&state)
        }
    }
}
