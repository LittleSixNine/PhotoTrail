import SwiftUI
import UDF

struct SetupGuideView: View {
    static let completedKey = "PhotoTrailSetupCompleted"
    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) private var store
    @Environment(LocationWorkspace.self) private var workspace
    @AppStorage(Self.completedKey) private var completed = false
    @AppStorage(PhotoTrailApp.doNotBackupKey) private var doNotBackup = false
    @AppStorage("PhotoTrailMapProvider") private var provider = "amap"
    @State private var backupURL: URL?
    @State private var mapSettings = false
    @State private var page = 0

    private var backupReady: Bool { doNotBackup || store.backupURL != nil }
    private let pageTitles = ["保护原始照片", "选择地图服务", "准备开始"]
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("欢迎使用 PhotoTrail").font(.headline).foregroundStyle(.secondary)
                Spacer()
                Text("第 \(page + 1) 步，共 3 步").font(.caption).foregroundStyle(.secondary)
            }
            Text(pageTitles[page]).font(.largeTitle.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch page {
                    case 0: backupPage
                    case 1: mapPage
                    default: readyPage
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                if page > 0 {
                    Button("上一步") { page -= 1 }
                }
                Spacer()
                if page < 2 {
                    Button("下一步") { page += 1 }
                        .buttonStyle(.borderedProminent)
                        .disabled(page == 0 && !backupReady)
                } else {
                    Button("开始使用") {
                        completed = true
                        onFinish()
                    }.buttonStyle(.borderedProminent)
                        .disabled(!backupReady)
                }
            }
        }.padding(28).frame(width: 550, height: 480)
            .interactiveDismissDisabled()
            .onAppear { backupURL = store.backupURL }
            .onChange(of: backupURL) {
                store.send(.backupURLChanged(backupURL), undoable: false)
            }
            .sheet(isPresented: $mapSettings) {
                AMapSettingsView(initialCredentials: workspace.credentials) { credentials in
                    workspace.credentials = credentials
                    workspace.reload()
                }
            }
    }

    private var backupPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("保存定位修改前，先为原照片留一份备份。")
                .foregroundStyle(.secondary)
            Toggle("保存修改前备份原照片（推荐）", isOn: Binding(
                get: { !doNotBackup }, set: { doNotBackup = !$0 }))
            if !doNotBackup {
                PathView(url: $backupURL).frame(height: 28)
                Text(backupReady ? "备份文件夹已设置。" : "请选择备份文件夹；也可关闭备份后继续。")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text("已关闭备份，保存时将直接更新照片文件。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Text("以后可在设置中调整备份方式。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var mapPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("默认地图", selection: $provider) {
                Text("高德地图（GCJ-02）· 中国大陆拍摄优先").tag("amap")
                Text("苹果地图（WGS-84）· 海外拍摄优先").tag("apple")
            }
            if provider == "amap" {
                Text("填写你自己的 Web 端 JS API Key 和安全密钥，也可以稍后在地图设置中填写。")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("设置高德密钥…") { mapSettings = true }
                    Text(workspace.credentials == nil ? "可稍后设置" : "已填写")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("苹果地图无需填写高德密钥；以后可在详情页切换地图来源。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Divider()
            Text("高德服务与费用").font(.headline)
            Text("""
                使用高德地图及相关坐标转换功能，需由你自行申请并填写高德开发者密钥。超出账号免费额度或使用付费服务时，可能产生费用（但个人用户很难使用超过每月免费额度），由高德向你的开发者账号计费。相关付费操作在高德开放平台完成，本软件完全免费，不收取或代收任何费用。

                高德开发者密钥保存在本机的 macOS 钥匙串中，不以明文写入配置文件，也不会上传至本软件开发者的服务器。调用高德服务时，密钥仅用于向高德进行身份验证。
                """)
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var readyPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("设置已就绪，可以开始为照片添加位置。")
                .foregroundStyle(.secondary)
            LabeledContent("照片备份", value: doNotBackup ? "已关闭" : "已开启")
            if !doNotBackup, let backupURL = store.backupURL {
                Text(backupURL.path).font(.caption).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            LabeledContent("默认地图", value: provider == "amap" ? "高德地图（GCJ-02）" : "苹果地图（WGS-84）")
            if provider == "amap" {
                LabeledContent("高德密钥", value: workspace.credentials == nil ? "稍后填写" : "已填写")
            }
            Divider()
            Text("导入照片 → 查看或设置位置 → 检查后保存")
                .font(.headline)
            Text("设置照片位置后仍需手动保存。备份和地图设置以后都可以调整。")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

}
