import Coords
import SwiftUI
import UDF

struct SettingsView: View {
    @Environment(Store<GeoTagState, GeoTagEvent>.self) private var store
    @AppStorage(GeoTagApp.doNotBackupKey) private var doNotBackup = false
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
            general.tabItem { Label("通用", systemImage: "gearshape") }
            map.tabItem { Label("地图", systemImage: "map") }
            photos.tabItem { Label("照片与保存", systemImage: "photo") }
            tracks.tabItem { Label("轨迹", systemImage: "point.3.connected.trianglepath.dotted") }
            storage.tabItem { Label("存储", systemImage: "externaldrive") }
        }
        .frame(width: 560, height: 500)
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
            Section("显示") {
                AppAppearancePicker()
                Picker("坐标格式", selection: $coordFormat) {
                    Text("十进制度").tag(CoordFormat.deg)
                    Text("度分").tag(CoordFormat.degMin)
                    Text("度分秒").tag(CoordFormat.degMinSec)
                }
                Toggle("隐藏不可编辑文件", isOn: $hideInvalidImages)
            }
            Section("相机时区") {
                Picker("新会话默认时区", selection: $cameraTimeZone) {
                    Text("跟随系统").tag("")
                    ForEach(TimeZoneName.allCases) { zone in
                        Text("UTC\(zone.rawValue)").tag(zone.timeZone.identifier)
                    }
                }
                Text("仅用于下次新会话；当前批次仍可单独调整。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Button("打开启动设置向导") {
                    UserDefaults.standard.set(false, forKey: SetupGuideView.completedKey)
                    NSApplication.shared.keyWindow?.close()
                }
            }
        }
    }

    private var map: some View {
        settingsPage {
            Section("地图来源") {
                Picker("地图", selection: $mapProvider) {
                    Text("高德地图").tag("amap")
                    Text("苹果地图").tag("apple")
                }
                if mapProvider == "amap" { AMapStylePicker() }
                Toggle("卫星视图", isOn: $satellite)
                Button("高德 API 设置…") { showAMapSettings = true }
            }
            Section("启动视野") {
                Picker("打开地图时显示", selection: $mapStartupView) {
                    ForEach(SettingsPreferences.MapStartupView.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                Text("设备定位不可用时，使用上次视野；没有记录时使用预设位置。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("照片标记") {
                Toggle("在地图上显示所有照片的位置", isOn: $showAllPhotoLocations)
                Text("关闭后仅显示选中照片的位置。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("地图直接编辑") {
                Toggle("允许双击地图设置照片位置", isOn: $allowDoubleClick)
                Toggle("允许拖动选中照片的标记修改位置", isOn: $allowDragPin)
                Text("开启后拖动标记，松手即更新待保存的位置；关闭可避免误触。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("地区名称") {
                Picker("查询方式", selection: $automaticRegion) {
                    Text("自动查询").tag(true)
                    Text("手动查询").tag(false)
                }
                Text("仅控制当前位置的地区名称查询。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var photos: some View {
        settingsPage {
            Section("导入") {
                Toggle("导入包含子文件夹", isOn: $recursiveImport)
                Toggle("将同目录同名 JPG 与 RAW 作为一组处理", isOn: $pairJPGRAW)
                Text("配对设置从下次导入起生效，已导入照片的分组保持不变。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("保存") {
                Toggle("保存前显示修改摘要", isOn: $showSaveSummary)
                Toggle("创建 XMP 附属文件", isOn: $createSidecarFiles)
                Toggle("设置文件修改时间", isOn: $updateFileModificationTimes)
                Toggle("更新 GPS 日期与时间", isOn: $updateGPSTimestamps)
                Toggle("给更新的文件添加 Finder 标签", isOn: $addTags)
                if addTags {
                    TextField("标签名称", text: $finderTag)
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
            Section("轨迹显示") {
                ColorPicker("轨迹颜色", selection: $trackColor)
                HStack {
                    TextField("线宽", text: $trackWidthText)
                        .frame(width: 90)
                        .onSubmit {
                            if let value = Double(trackWidthText), value.isFinite, (0...1_000).contains(value) {
                                trackWidth = value
                            } else { trackWidthText = String(trackWidth) }
                        }
                    Text("线宽，0 使用默认值")
                }
            }
            Section("轨迹匹配") {
                HStack {
                    TextField("最大点间隔", text: $extendedTimeText)
                        .frame(width: 90)
                        .onSubmit {
                            if let value = Double(extendedTimeText), value.isFinite, (0...1_000_000).contains(value), value > 0 {
                                extendedTime = value
                            } else { extendedTimeText = String(extendedTime) }
                        }
                    Text("最大匹配点间隔（分钟）")
                }
            }
            Section("从照片生成 GPX") {
                Picker("默认断段间隔", selection: $photoGPXGap) {
                    ForEach([5.0, 15.0, 30.0, 60.0], id: \.self) { value in
                        Text("\(Int(value)) 分钟").tag(value)
                    }
                    if ![5.0, 15.0, 30.0, 60.0].contains(photoGPXGap) {
                        Text("自定义").tag(photoGPXGap)
                    }
                }
                HStack {
                    TextField("自定义分钟数", text: $gapText)
                        .frame(width: 90)
                        .onSubmit {
                            if let value = Double(gapText), value.isFinite, (0...1_000_000).contains(value), value > 0 {
                                photoGPXGap = value
                            } else { gapText = String(photoGPXGap) }
                        }
                    Text("断段间隔（分钟）")
                }
                Text("生成时可临时调整，不改变默认值。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var storage: some View {
        settingsPage {
            Section("照片备份") {
                Toggle("修改前备份照片", isOn: Binding(
                    get: { !doNotBackup }, set: { doNotBackup = !$0 }))
                if !doNotBackup {
                    PathView(url: $backupURL)
                        .accessibilityIdentifier(TestIDs.SettingsView.pathViewID)
                }
                Picker("旧备份清理提醒", selection: $reminderDays) {
                    Text("7 天").tag(7)
                    Text("30 天").tag(30)
                    Text("90 天").tag(90)
                    Text("不提醒").tag(0)
                }
                Text("备份占用：\(ByteCountFormatter.string(fromByteCount: Int64(store.folderSize), countStyle: .file))")
                    .foregroundStyle(.secondary)
                Text("仅提醒，删除前仍会再次确认。")
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
                Button("关闭") { NSApplication.shared.keyWindow?.close() }
                    .accessibilityIdentifier(TestIDs.SettingsView.closeID)
            }
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension SettingsView {
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
            GeoTagApp.doNotBackupKey, GeoTagApp.savedBookmarkKey, createSidecarFilesKey,
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
