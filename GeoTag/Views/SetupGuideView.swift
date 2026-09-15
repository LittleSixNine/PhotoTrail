import SwiftUI
import UDF

struct SetupGuideView: View {
    static let completedKey = "GeoTagCNSetupCompleted"
    @Environment(Store<GeoTagState, GeoTagEvent>.self) private var store
    @Environment(LocationWorkspace.self) private var workspace
    @AppStorage(Self.completedKey) private var completed = false
    @AppStorage(GeoTagApp.doNotBackupKey) private var doNotBackup = false
    @AppStorage("GeoTagCNMapProvider") private var provider = "amap"
    @State private var backupURL: URL?
    @State private var mapSettings = false
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("欢迎使用 GeoTag CN").font(.largeTitle.bold())
            Text("先确认照片备份和地图设置，之后可随时调整。")
                .foregroundStyle(.secondary)
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("保存修改前备份原照片（推荐）", isOn: Binding(
                        get: { !doNotBackup }, set: { doNotBackup = !$0 }))
                    Text("备份能在误操作或保存异常时帮助找回原文件。")
                        .font(.callout).foregroundStyle(.secondary)
                    if !doNotBackup {
                        PathView(url: $backupURL).frame(height: 28)
                        if backupURL == nil {
                            Text("请选择备份文件夹；也可关闭备份后继续。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("已关闭备份，保存时将直接更新照片文件。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
            } label: { Label("照片备份", systemImage: "externaldrive") }
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("默认地图", selection: $provider) {
                        Text("高德地图（中国大陆拍摄优先）").tag("amap")
                        Text("苹果地图（海外拍摄优先）").tag("apple")
                    }
                    if provider == "amap" {
                        Text("高德地图需要你自己的 Web 端 JS API Key 和安全密钥。地图坐标会转换为 WGS84 后保存到照片。")
                            .font(.callout).foregroundStyle(.secondary)
                        HStack {
                            Button("设置高德密钥…") { mapSettings = true }
                            Text(workspace.credentials == nil ? "可稍后设置" : "已填写")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("苹果地图无需填写高德密钥。")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
            } label: { Label("地图", systemImage: "map") }
            HStack {
                Text("以后可在设置中调整备份，在详情页调整地图。")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("开始使用") {
                    completed = true
                    onFinish()
                }.buttonStyle(.borderedProminent)
                    .disabled(!doNotBackup && store.backupURL == nil)
            }
        }.padding(28).frame(width: 550)
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
}
