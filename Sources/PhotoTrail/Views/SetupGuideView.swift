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
    @AppStorage(L10n.languageKey) private var language = L10n.language.rawValue

    private var backupReady: Bool { doNotBackup || store.backupURL != nil }
    private var pageTitles: [String] { [L10n.text("选择语言"), L10n.text("保护原始照片"), L10n.text("选择地图服务"), L10n.text("准备开始")] }
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(L10n.text("欢迎使用 PhotoTrail")).font(.headline).foregroundStyle(.secondary)
                Spacer()
                Text(L10n.text("第 %1$@ 步，共 4 步", page + 1)).font(.caption).foregroundStyle(.secondary)
            }
            Text(pageTitles[page]).font(.largeTitle.bold()).accessibilityIdentifier("setupTitle")
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch page {
                    case 0: languagePage
                    case 1: backupPage
                    case 2: mapPage
                    default: readyPage
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.background(SubtleScrollbars())
            Divider()
            HStack {
                if page > 0 {
                    Button(L10n.text("上一步")) { page -= 1 }.accessibilityIdentifier("setupBack")
                }
                Spacer()
                if page < 3 {
                    Button(L10n.text("下一步")) {
                        if page == 0, let selected = AppLanguage(rawValue: language) { L10n.select(selected) }
                        page += 1
                    }
                        .accessibilityIdentifier("setupNext")
                        .buttonStyle(.borderedProminent)
                        .disabled(page == 1 && !backupReady)
                } else {
                    Button(L10n.text("开始使用")) {
                        completed = true
                        onFinish()
                    }.buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("setupFinish")
                        .disabled(!backupReady)
                }
            }
        }.padding(28).frame(width: 640, height: 560)
            .interactiveDismissDisabled()
            .onAppear { backupURL = store.backupURL }
            .onChange(of: language) {
                if let selected = AppLanguage(rawValue: language) {
                    L10n.select(selected)
                    provider = selected.defaultMapProvider
                }
            }
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

    private var languagePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            AppLanguagePicker()
            Text(L10n.text("选择应用使用的语言。简体中文默认使用高德地图，其他语言默认使用 Apple 地图；下一步仍可自行选择地图。"))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(L10n.text("系统菜单及权限提示将在下次启动时使用所选语言。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var backupPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("保存定位修改前，先为原照片留一份备份。"))
                .foregroundStyle(.secondary)
            Toggle(L10n.text("保存修改前备份原照片（推荐）"), isOn: Binding(
                get: { !doNotBackup }, set: { doNotBackup = !$0 }))
            if !doNotBackup {
                PathView(url: $backupURL).frame(height: 28)
                Text(backupReady ? L10n.text("备份文件夹已设置。") : L10n.text("请选择备份文件夹；也可关闭备份后继续。"))
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text(L10n.text("已关闭备份，保存时将直接更新照片文件。"))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Text(L10n.text("以后可在设置中调整备份方式。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var mapPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker(L10n.text("默认地图"), selection: $provider) {
                Text(L10n.text("高德地图（GCJ-02）· 中国大陆拍摄优先")).tag("amap")
                Text(L10n.text("苹果地图（WGS-84）· 海外拍摄优先")).tag("apple")
            }
            .accessibilityIdentifier("setupMapPicker")
            if provider == "amap" {
                Text(L10n.text("填写你自己的 Web 端 JS API Key 和安全密钥，也可以稍后在地图设置中填写。"))
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button(L10n.text("设置高德密钥…")) { mapSettings = true }
                    Text(workspace.credentials == nil ? L10n.text("可稍后设置") : L10n.text("已填写"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(L10n.text("苹果地图无需填写高德密钥；以后可在详情页切换地图来源。"))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Divider()
            Text(L10n.text("高德服务与费用")).font(.headline)
            Text(L10n.text(
                """
                    使用高德地图及相关坐标转换功能，需由你自行申请并填写高德开发者密钥。超出账号免费额度或使用付费服务时，可能产生费用（但个人用户很难使用超过每月免费额度），由高德向你的开发者账号计费。相关付费操作在高德\
                    开放平台完成，本软件完全免费，不收取或代收任何费用。\n\n高德开发者密钥保存在本机的 macOS 钥匙串中，不以明文写入配置文件，也不会上传至本软件开发者的服务器。调用高德服务时，密钥仅用于向高德进\
                    行身份验证。
                    """))
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var readyPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("设置已就绪，可以开始为照片添加位置。"))
                .foregroundStyle(.secondary)
            LabeledContent(L10n.text("照片备份"), value: doNotBackup ? L10n.text("已关闭") : L10n.text("已开启"))
            if !doNotBackup, let backupURL = store.backupURL {
                Text(backupURL.path).font(.caption).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            LabeledContent(L10n.text("默认地图"), value: provider == "amap" ? L10n.text("高德地图（GCJ-02）") : L10n.text("苹果地图（WGS-84）"))
            if provider == "amap" {
                LabeledContent(L10n.text("高德密钥"), value: workspace.credentials == nil ? L10n.text("稍后填写") : L10n.text("已填写"))
            }
            Divider()
            AutomaticUpdateChecksToggle()
            AutomaticUpdateDownloadsToggle()
            Text(L10n.text("开启自动下载后，发现新版时会下载 DMG。下次启动时点击打开安装镜像；打开后请先退出 PhotoTrail，再将它拖到“应用程序”文件夹完成更新。可随时在菜单或设置中调整。"))
                .font(.callout).foregroundStyle(.secondary)
            Divider()
            Text(L10n.text("导入照片 → 查看或设置位置 → 检查后保存"))
                .font(.headline)
            Text(L10n.text("设置照片位置后仍需手动保存。备份和地图设置以后都可以调整。"))
                .font(.callout).foregroundStyle(.secondary)
        }
    }

}
