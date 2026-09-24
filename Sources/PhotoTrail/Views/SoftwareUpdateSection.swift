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
            AutomaticUpdateDownloadsToggle()
            Text("开启自动下载后，PhotoTrail 会在发现新版时下载 DMG。下次启动时点击打开安装镜像；打开后请先退出 PhotoTrail，再拖到“应用程序”文件夹完成更新。")
                .font(.footnote).foregroundStyle(.secondary)
            if !updates.status.isEmpty {
                Text(updates.status).font(.footnote).foregroundStyle(.secondary)
            }
            if let version = updates.downloadedVersion {
                Button("打开 PhotoTrail \(version) 安装镜像", action: updates.openDownloadedUpdate)
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

struct AutomaticUpdateDownloadsToggle: View {
    @ObservedObject private var updates = SoftwareUpdate.shared

    var body: some View {
        Toggle("自动下载更新", isOn: Binding(get: { updates.automaticDownloads },
                                          set: updates.setAutomaticDownloads))
    }
}
