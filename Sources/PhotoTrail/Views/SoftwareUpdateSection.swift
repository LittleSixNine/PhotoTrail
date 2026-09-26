import SwiftUI

struct CheckForUpdatesButton: View {
    @ObservedObject private var updates = SoftwareUpdate.shared

    var body: some View {
        Button(L10n.text("检查更新…"), action: updates.checkForUpdates)
            .disabled(!updates.canCheck)
    }
}

struct SoftwareUpdateSection: View {
    @ObservedObject private var updates = SoftwareUpdate.shared

    var body: some View {
        Section(L10n.text("软件更新")) {
            HStack {
                Text(L10n.text("当前版本 %1$@", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"))
                Spacer()
                CheckForUpdatesButton().buttonStyle(.bordered)
            }
            AutomaticUpdateChecksToggle()
            AutomaticUpdateDownloadsToggle()
            Text(L10n.text("开启自动下载后，PhotoTrail 会在发现新版时下载 DMG。下次启动时点击打开安装镜像；打开后请先退出 PhotoTrail，再拖到“应用程序”文件夹完成更新。"))
                .font(.footnote).foregroundStyle(.secondary)
            if !updates.status.isEmpty {
                Text(updates.status).font(.footnote).foregroundStyle(.secondary)
            }
            if let version = updates.downloadedVersion {
                Button(L10n.text("打开 PhotoTrail %1$@ 安装镜像", version), action: updates.openDownloadedUpdate)
            }
            Button(updates.latestRelease == nil ? L10n.text("查看 GitHub 发布页") : L10n.text("前往下载新版"),
                   action: updates.openRelease)
            if let lastCheck = updates.lastCheck {
                Text(L10n.text("上次检查：%1$@", lastCheck.formatted(.dateTime.year().month().day().hour().minute().locale(L10n.locale))))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

struct AutomaticUpdateChecksToggle: View {
    @ObservedObject private var updates = SoftwareUpdate.shared

    var body: some View {
        Toggle(L10n.text("启动时检查更新"), isOn: Binding(get: { updates.automaticChecks },
                                          set: updates.setAutomaticChecks))
    }
}

struct AutomaticUpdateDownloadsToggle: View {
    @ObservedObject private var updates = SoftwareUpdate.shared

    var body: some View {
        Toggle(L10n.text("自动下载更新"), isOn: Binding(get: { updates.automaticDownloads },
                                          set: updates.setAutomaticDownloads))
    }
}
