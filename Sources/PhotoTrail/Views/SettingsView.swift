import Coords
import SwiftUI
import UDF

struct SettingsView: View {
    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) private var store
    @AppStorage(PhotoTrailApp.doNotBackupKey) private var doNotBackup = false
    @AppStorage(Self.createSidecarFilesKey) private var createSidecarFiles = false
    @AppStorage(Coords.coordFormatKey) private var coordFormat: CoordFormat = .deg
    @AppStorage(Self.trackWidthKey) private var trackWidth = 0.0
    @AppStorage(Self.trackColorKey) private var trackColor = Color.red
    @AppStorage(Self.extendedTimeKey) private var extendedTime = 120.0
    @AppStorage(Self.updateFileModificationTimesKey) private var updateFileModificationTimes = false
    @AppStorage(Self.updateGPSTimestampsKey) private var updateGPSTimestamps = false
    @AppStorage(Self.addTagsKey) private var addTags = false
    @AppStorage(Self.finderTagKey) private var finderTag = "PhotoTrail"
    @AppStorage(ImageTableView.hideInvalidImagesKey) private var hideInvalidImages = false
    @AppStorage("PhotoTrailMapProvider") private var mapProvider = "amap"
    @AppStorage("PhotoTrailSatellite") private var satellite = false
    @AppStorage(SettingsPreferences.showAllPhotoLocationsKey) private var showAllPhotoLocations = true
    @AppStorage(SettingsPreferences.mapStartupViewKey)
    private var mapStartupView = SettingsPreferences.MapStartupView.device.rawValue
    @AppStorage(SettingsPreferences.doubleClickKey) private var allowDoubleClick = true
    @AppStorage(SettingsPreferences.dragPinKey) private var allowDragPin = true
    @AppStorage(SettingsPreferences.showSaveSummaryKey) private var showSaveSummary = false
    @AppStorage(SettingsPreferences.cameraTimeZoneKey) private var cameraTimeZone = ""
    @AppStorage(SettingsPreferences.photoGPXGapKey) private var photoGPXGap = 5.0
    @AppStorage(SettingsPreferences.pairJPGRAWKey) private var pairJPGRAW = true
    @AppStorage(SettingsPreferences.recursiveImportKey) private var recursiveImport = true
    @AppStorage(SettingsPreferences.automaticRegionKey) private var automaticRegion = true
    @AppStorage(SettingsPreferences.backupReminderKey) private var reminderDays = 7

    @State private var backupURL: URL?
    @State private var showAMapSettings = false
    @State private var credentials: AMapCredentials?
    @State private var gapText = ""
    @State private var trackWidthText = ""
    @State private var extendedTimeText = ""

    var body: some View {
        TabView {
            general.tabItem { Label(L10n.text("通用"), systemImage: "gearshape") }
            map.tabItem { Label(L10n.text("地图"), systemImage: "map") }
            photos.tabItem { Label(L10n.text("照片与保存"), systemImage: "photo") }
            tracks.tabItem { Label(L10n.text("轨迹"), systemImage: "point.3.connected.trianglepath.dotted") }
            storage.tabItem { Label(L10n.text("存储"), systemImage: "externaldrive") }
        }
        .frame(width: 640, height: 560)
        .sheet(isPresented: $showAMapSettings) {
            AMapSettingsView(initialCredentials: credentials) {
                credentials = $0
                NotificationCenter.default.post(name: .photoTrailAMapCredentialsChanged, object: $0)
            }
        }
        .task {
            backupURL = store.backupURL
            if store.backupURL != nil {
                store.send(.backupFolderSizeCheck, undoable: false)
            }
            if ProcessInfo.processInfo.environment["PHOTOTRAIL_OFFLINE_TESTS"] != "1" {
                credentials = try? await Task.detached { try AMapCredentials.load() }.value
            }
            gapText = String(SettingsPreferences.photoGPXGap / 60)
            trackWidthText = String(trackWidth)
            extendedTimeText = String(extendedTime)
        }
        .onChange(of: photoGPXGap) { gapText = String(photoGPXGap) }
        .onChange(of: backupURL) {
            if backupURL != store.backupURL { store.send(.backupURLChanged(backupURL)) }
        }
    }

    private var general: some View {
        settingsPage {
            Section(L10n.text("显示")) {
                AppAppearancePicker()
                Picker(L10n.text("坐标格式"), selection: $coordFormat) {
                    Text(L10n.text("十进制度")).tag(CoordFormat.deg)
                    Text(L10n.text("度分")).tag(CoordFormat.degMin)
                    Text(L10n.text("度分秒")).tag(CoordFormat.degMinSec)
                }
                Toggle(L10n.text("隐藏不可编辑文件"), isOn: $hideInvalidImages)
            }
            Section(L10n.text("语言")) {
                AppLanguagePicker()
                Text(L10n.text("更改语言后，请保存工作并重新打开 PhotoTrail，使所有窗口和系统提示使用新语言。"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section(L10n.text("相机时区")) {
                Picker(L10n.text("新会话默认时区"), selection: $cameraTimeZone) {
                    Text(L10n.text("跟随系统")).tag("")
                    ForEach(TimeZoneName.allCases) { zone in
                        Text("UTC\(zone.rawValue)").tag(zone.timeZone.identifier)
                    }
                }
                Text(L10n.text("仅用于下次新会话；当前批次仍可单独调整。"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            SoftwareUpdateSection()
            Section(L10n.text("反馈")) {
                if let url = Self.feedbackURL {
                    Link(destination: url) {
                        Label(L10n.text("反馈意见"), systemImage: "envelope")
                    }
                    .buttonStyle(.bordered)
                    .help(L10n.text("通过默认邮件应用发送反馈"))
                }
                Text("liujiudexiaohao@gmail.com")
                    .font(.footnote).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Section {
                Button(L10n.text("打开启动设置向导")) {
                    UserDefaults.standard.set(false, forKey: SetupGuideView.completedKey)
                    NSApplication.shared.keyWindow?.close()
                }
            }
        }
    }

    private var map: some View {
        settingsPage {
            Section(L10n.text("地图来源")) {
                Picker(L10n.text("地图"), selection: $mapProvider) {
                    Text(L10n.text("高德地图")).tag("amap")
                    Text(L10n.text("苹果地图")).tag("apple")
                }
                if mapProvider == "amap" { AMapStylePicker() }
                Toggle(L10n.text("卫星视图"), isOn: $satellite)
                Button(L10n.text("高德 API 设置…")) { showAMapSettings = true }
            }
            Section(L10n.text("启动视野")) {
                Picker(L10n.text("打开地图时显示"), selection: $mapStartupView) {
                    ForEach(SettingsPreferences.MapStartupView.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                Text(L10n.text("设备定位不可用时，使用上次视野；没有记录时使用预设位置。"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section(L10n.text("照片标记")) {
                Toggle(L10n.text("在地图上显示所有照片的位置"), isOn: $showAllPhotoLocations)
                Text(L10n.text("关闭后仅显示选中照片的位置。"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section(L10n.text("地图直接编辑")) {
                Toggle(L10n.text("允许双击地图设置照片位置"), isOn: $allowDoubleClick)
                Toggle(L10n.text("允许拖动选中照片的标记修改位置"), isOn: $allowDragPin)
                Text(L10n.text("开启后拖动标记，松手即更新待保存的位置；关闭可避免误触。"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section(L10n.text("地区名称")) {
                Picker(L10n.text("查询方式"), selection: $automaticRegion) {
                    Text(L10n.text("自动查询")).tag(true)
                    Text(L10n.text("手动查询")).tag(false)
                }
                Text(L10n.text("仅控制当前位置的地区名称查询。"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var photos: some View {
        settingsPage {
            Section(L10n.text("导入")) {
                Toggle(L10n.text("导入包含子文件夹"), isOn: $recursiveImport)
                Toggle(L10n.text("将同目录同名 JPG 与 RAW 作为一组处理"), isOn: $pairJPGRAW)
                Text(L10n.text("配对设置从下次导入起生效，已导入照片的分组保持不变。"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section(L10n.text("保存")) {
                Toggle(L10n.text("保存前显示修改摘要"), isOn: $showSaveSummary)
                Toggle(L10n.text("创建 XMP 附属文件"), isOn: $createSidecarFiles)
                Toggle(L10n.text("设置文件修改时间"), isOn: $updateFileModificationTimes)
                Toggle(L10n.text("更新 GPS 日期与时间"), isOn: $updateGPSTimestamps)
                Toggle(L10n.text("给更新的文件添加 Finder 标签"), isOn: $addTags)
                if addTags {
                    TextField(L10n.text("标签名称"), text: $finderTag)
                        .onSubmit {
                            if finderTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                finderTag = "PhotoTrail"
                            }
                        }
                }
            }
        }
    }

    private var tracks: some View {
        settingsPage {
            Section(L10n.text("轨迹显示")) {
                ColorPicker(L10n.text("轨迹颜色"), selection: $trackColor)
                LabeledContent(L10n.text("线宽")) {
                    TextField(L10n.text("线宽"), text: $trackWidthText)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                        .onSubmit {
                            if let value = Double(trackWidthText), value.isFinite, (0...1_000).contains(value) {
                                trackWidth = value
                            } else { trackWidthText = String(trackWidth) }
                        }
                }
                Text(L10n.text("设为 0 时使用默认线宽。"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section(L10n.text("轨迹匹配")) {
                LabeledContent(L10n.text("最大匹配点间隔")) {
                    HStack(spacing: 8) {
                        TextField(L10n.text("最大点间隔"), text: $extendedTimeText)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                            .onSubmit {
                                if let value = Double(extendedTimeText), value.isFinite, (0...1_000_000).contains(value), value > 0 {
                                    extendedTime = value
                                } else { extendedTimeText = String(extendedTime) }
                            }
                        Text(L10n.text("分钟")).foregroundStyle(.secondary)
                    }
                }
            }
            Section(L10n.text("从照片生成 GPX")) {
                Picker(L10n.text("默认断段间隔"), selection: $photoGPXGap) {
                    ForEach([5.0, 15.0, 30.0, 60.0], id: \.self) { value in
                        Text(L10n.text("%1$@ 分钟", Int(value))).tag(value)
                    }
                    if ![5.0, 15.0, 30.0, 60.0].contains(photoGPXGap) {
                        Text(L10n.text("自定义")).tag(photoGPXGap)
                    }
                }
                LabeledContent(L10n.text("自定义断段间隔")) {
                    HStack(spacing: 8) {
                        TextField(L10n.text("自定义分钟数"), text: $gapText)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                            .onSubmit {
                                if let value = Double(gapText), value.isFinite, (0...1_000_000).contains(value), value > 0 {
                                    photoGPXGap = value
                                } else { gapText = String(photoGPXGap) }
                            }
                        Text(L10n.text("分钟")).foregroundStyle(.secondary)
                    }
                }
                Text(L10n.text("生成时可临时调整，不改变默认值。"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var storage: some View {
        settingsPage {
            Section(L10n.text("照片备份")) {
                Toggle(L10n.text("修改前备份照片"), isOn: Binding(
                    get: { !doNotBackup }, set: { doNotBackup = !$0 }))
                if !doNotBackup {
                    PathView(url: $backupURL)
                        .accessibilityIdentifier(TestIDs.SettingsView.pathViewID)
                }
                Picker(L10n.text("旧备份清理提醒"), selection: $reminderDays) {
                    Text(L10n.text("7 天")).tag(7)
                    Text(L10n.text("30 天")).tag(30)
                    Text(L10n.text("90 天")).tag(90)
                    Text(L10n.text("不提醒")).tag(0)
                }
                Text(L10n.text("备份占用：%1$@", ByteCountFormatter.string(fromByteCount: Int64(store.folderSize), countStyle: .file)))
                    .foregroundStyle(.secondary)
                Text(L10n.text("仅提醒，删除前仍会再次确认。"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func settingsPage<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            Form { content() }
                .formStyle(.grouped)
                .padding(12)
            HStack {
                Spacer()
                Button(L10n.text("关闭")) { NSApplication.shared.keyWindow?.close() }
                    .accessibilityIdentifier(TestIDs.SettingsView.closeID)
            }
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SubtleScrollbars())
    }
}

extension SettingsView {
    static var feedbackURL: URL? {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? L10n.text("未知")
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? L10n.text("未知")
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "liujiudexiaohao@gmail.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "PhotoTrail Feedback"),
            URLQueryItem(name: "body", value: L10n.text("问题描述或建议：\n\n\nPhotoTrail 版本：%1$@\n构建号：%2$@", version, build))
        ]
        return components.url
    }

    static let createSidecarFilesKey = "CreateSidecarFiles"
    static let trackWidthKey = "TrackWidth"
    static let trackColorKey = "TrackColor"
    static let extendedTimeKey = "ExtendedTime"
    static let updateFileModificationTimesKey = "UpdateFileModificationTimes"
    static let updateGPSTimestampsKey = "UpdateGPSTimestamps"
    static let addTagsKey = "AddTags"
    static let finderTagKey = "FinderTag"

    static func clearAllSettings() {
        let keys = [
            PhotoTrailApp.doNotBackupKey, PhotoTrailApp.savedBookmarkKey, createSidecarFilesKey,
            Coords.coordFormatKey, trackWidthKey, trackColorKey, extendedTimeKey,
            updateFileModificationTimesKey, updateGPSTimestampsKey, addTagsKey,
            finderTagKey, ImageTableView.hideInvalidImagesKey,
            "PhotoTrailMapProvider", "PhotoTrailSatellite", AMapStyleName.preferenceKey,
            AMapStyleName.lightPreferenceKey, AMapStyleName.darkPreferenceKey, AppAppearance.preferenceKey,
            SettingsPreferences.showAllPhotoLocationsKey, SettingsPreferences.mapStartupViewKey,
            SettingsPreferences.showSaveSummaryKey, "PhotoTrailPinScope",
            SettingsPreferences.doubleClickKey,
            SettingsPreferences.dragPinKey, SettingsPreferences.cameraTimeZoneKey,
            SettingsPreferences.photoGPXGapKey, SettingsPreferences.pairJPGRAWKey,
            SettingsPreferences.recursiveImportKey, SettingsPreferences.automaticRegionKey,
            SettingsPreferences.backupReminderKey
        ]
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }
}

extension Color: @retroactive RawRepresentable {
    public init?(rawValue: String) {
        guard let data = Data(base64Encoded: rawValue),
              let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
        else { self = .black; return }
        self = Color(color)
    }

    public var rawValue: String {
        guard let data = try? NSKeyedArchiver.archivedData(
            withRootObject: NSColor(self), requiringSecureCoding: false
        ) else { return "" }
        return data.base64EncodedString()
    }
}

extension Notification.Name {
    static let photoTrailAMapCredentialsChanged = Notification.Name("PhotoTrailAMapCredentialsChanged")
}
