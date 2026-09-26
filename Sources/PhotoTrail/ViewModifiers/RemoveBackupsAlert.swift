import SwiftUI
import UDF

struct RemoveBackupsAlert: ViewModifier {
    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) var store
    @State private var removeBackups = false
    @AppStorage(SettingsPreferences.backupReminderKey) private var reminderDays = 7

    func body(content: Content) -> some View {
        content
            .alert(L10n.text("Delete old backup files?"), isPresented: $removeBackups) {
                Button(L10n.text("Delete"), role: .destructive) {
                    store.send(.removeOldFiles, undoable: false)
                }
                Button(L10n.text("Cancel"), role: .cancel) {}
                    .keyboardShortcut(.defaultAction)
            } message: {
                Text(L10n.text(
                    "备份文件夹：\n%1$@\n\n当前占用 %2$@ MB。\n其中 %3$@ 个备份已超过 %4$@ 天，占用 %5$@ MB。\n是否删除这些旧备份？",
                    store.backupURL?.path ?? L10n.text("未知"), store.folderSize / 1_000_000,
                    store.oldFiles.count, reminderDays, store.deletedSize / 1_000_000))
            }
        .onChange(of: reminderDays) {
            removeBackups = false
            store.send(.backupFolderSizeCheck, undoable: false)
        }
        .onChange(of: store.oldFiles) {
            removeBackups = !store.oldFiles.isEmpty
        }
        .task {
            removeBackups = !store.oldFiles.isEmpty
        }
    }
}

extension View {
    func removeBackupsAlert() -> some View {
        modifier(RemoveBackupsAlert())
    }
}
