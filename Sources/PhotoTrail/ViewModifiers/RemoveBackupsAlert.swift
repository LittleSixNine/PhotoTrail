import SwiftUI
import Imagetool
import UDF

struct RemoveBackupsAlert: ViewModifier {
    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) var store
    @State private var candidates: [ManagedBackup] = []
    @State private var folder: URL?
    @State private var removeBackups = false
    @AppStorage(SettingsPreferences.backupReminderKey) private var reminderDays = 7

    func body(content: Content) -> some View {
        content
            .alert(L10n.text("Delete old backup files?"), isPresented: $removeBackups) {
                Button(L10n.text("Delete"), role: .destructive) {
                    guard let folder, folder == store.backupURL else { return }
                    let confirmed = candidates
                    Task {
                        let errors = await Task.detached {
                            confirmed.compactMap { backup -> String? in
                                do { try backup.remove(from: folder); return nil }
                                catch { return error.localizedDescription }
                            }
                        }.value
                        if !errors.isEmpty { OperationFailure.present(errors.joined(separator: "\n")) }
                        store.send(.backupFolderSizeCheck, undoable: false)
                    }
                }
                Button(L10n.text("Cancel"), role: .cancel) {}
                    .keyboardShortcut(.defaultAction)
            } message: {
                Text(L10n.text(
                    "备份文件夹：\n%1$@\n\n当前占用 %2$@ MB。\n其中 %3$@ 个备份已超过 %4$@ 天，占用 %5$@ MB。\n是否删除这些旧备份？",
                    store.backupURL?.path ?? L10n.text("未知"), store.folderSize / 1_000_000,
                    candidates.count, reminderDays, candidates.reduce(0) { $0 + $1.bytes } / 1_000_000))
            }
        .onChange(of: reminderDays) {
            removeBackups = false
            store.send(.backupFolderSizeCheck, undoable: false)
        }
        .task(id: store.backupScanID) {
            removeBackups = false
            let token = store.backupScanID
            guard let url = store.backupURL else { return }
            let cutoff = SettingsPreferences.backupReminderDays.flatMap {
                Calendar.current.date(byAdding: .day, value: -$0, to: Date())
            }
            do {
                let work = Task.detached(priority: .utility) { try ManagedBackup.list(in: url) }
                let all = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
                guard !Task.isCancelled, token == store.backupScanID, url == store.backupURL else { return }
                candidates = cutoff.map { date in all.filter { $0.created < date } } ?? []
                folder = url
                store.send(.backupScanFinished(token, candidates, all.reduce(0) { $0 + $1.bytes }), undoable: false)
                removeBackups = !candidates.isEmpty
            } catch {
                if !Task.isCancelled { OperationFailure.present(error.localizedDescription) }
            }
        }
    }
}

extension View {
    func removeBackupsAlert() -> some View {
        modifier(RemoveBackupsAlert())
    }
}
