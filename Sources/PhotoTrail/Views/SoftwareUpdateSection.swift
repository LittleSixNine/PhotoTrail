import SwiftUI

struct CheckForUpdatesButton: View {
    @ObservedObject private var updates = SoftwareUpdate.shared

    var body: some View {
        Button("检查更新…", action: updates.checkForUpdates)
            .disabled(!updates.canCheck)
    }
}

struct SoftwareUpdateSection: View {
    @ObservedObject private var updates = SoftwareUpdate.shared

    var body: some View {
        Section("软件更新") {
            HStack {
                Text("当前版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")")
                Spacer()
                CheckForUpdatesButton().buttonStyle(.bordered)
            }
            AutomaticUpdateChecksToggle()
            Text("发现新版时提醒。下载 DMG 后，将 PhotoTrail 拖入应用程序文件夹完成替换。")
                .font(.footnote).foregroundStyle(.secondary)
            if !updates.status.isEmpty {
                Text(updates.status).font(.footnote).foregroundStyle(.secondary)
            }
            Button(updates.latestRelease == nil ? "查看 GitHub 发布页" : "前往下载新版",
                   action: updates.openRelease)
            if let lastCheck = updates.lastCheck {
                Text("上次检查：\(lastCheck.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

struct AutomaticUpdateChecksToggle: View {
    @ObservedObject private var updates = SoftwareUpdate.shared

    var body: some View {
        Toggle("启动时检查更新", isOn: Binding(get: { updates.automaticChecks },
                                          set: updates.setAutomaticChecks))
    }
}
