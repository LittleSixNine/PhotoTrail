import SwiftUI
import UDF

struct RemoveBackupsAlert: ViewModifier {
    @Environment(Store<GeoTagState, GeoTagEvent>.self) var store
    @State private var removeBackups = false

    func body(content: Content) -> some View {
        content
            .alert("Delete old backup files?", isPresented: $removeBackups) {
                Button("Delete", role: .destructive) {
                    store.send(.removeOldFiles, undoable: false)
                }
                Button("Cancel", role: .cancel) {}
                    .keyboardShortcut(.defaultAction)
            } message: {
                Text("""
                    备份文件夹：
                    \(store.backupURL?.path ?? "未知")

                    当前占用 \(store.folderSize / 1_000_000) MB。
                    其中 \(store.oldFiles.count) 个备份已超过 7 天，占用 \(store.deletedSize / 1_000_000) MB。
                    是否删除这些旧备份？
                    """)
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
