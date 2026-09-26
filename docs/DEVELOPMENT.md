# PhotoTrail 开发说明

**简体中文** · [English](i18n/DEVELOPMENT.en.md)

## 环境与构建

需要支持 Swift 6.2、macOS 26 或更新 SDK 的完整 Xcode，以及 XcodeGen。安装 SwiftLint 后会在构建时运行代码检查；未安装时构建脚本给出提示。地图脚本测试需要 Node.js 20 或更新版本；可通过 `make test-map NODE=/path/to/node` 指定可执行文件。

从仓库根目录运行：

```sh
make build
```

等价命令：

```sh
xcodegen generate
xcodebuild -project PhotoTrail.xcodeproj -scheme PhotoTrail \
  -configuration Debug -destination 'platform=macOS' build
```

`project.yml` 是 Xcode 项目的配置源。生成的 `PhotoTrail.xcodeproj` 和 `Build/Generated/` 不纳入版本控制；修改配置后重新运行 XcodeGen。

## 目录与职责

| 路径 | 内容 |
| --- | --- |
| `Sources/PhotoTrail/` | macOS 应用入口、状态与事件、照片操作、地图桥接及 SwiftUI 界面。 |
| `Sources/PhotoTrail/Views/Maps/` | 苹果地图、高德地图、网页桥接与地图控件。 |
| `Sources/PhotoTrail/DevAssets/` | Debug 预览与应用测试使用的图片、轨迹和预览辅助代码；Release 构建排除。 |
| `Packages/` | 应用仍在使用的本地 Swift 包，包内包含各自的测试与测试资源。 |
| `Tests/PhotoTrailTests/` | 应用逻辑单元测试。 |
| `Tests/PhotoTrailUITests/` | 界面测试；通过相对符号链接共享应用的 `TestIDs.swift`。 |
| `Resources/` | 应用图标、资源目录和隐私清单。 |
| `scripts/` | 构建版本、代码检查及地图脚本测试。 |
| `docs/` | 开发说明、功能与数据约定、README 使用的图片。 |
| `skill/` | 可独立安装的 Python 照片与 GPX 工具，不依赖 macOS App。 |

本地包按职责保留模块边界：

| 包 | 用途 |
| --- | --- |
| `Coords` | 坐标表示与转换。 |
| `GpxTrackLog` | GPX 读取、轨迹数据与时间匹配。 |
| `Metadata` | 统一的照片元数据模型。 |
| `Exiftool` | 随应用提供的 ExifTool 及调用封装。 |
| `Imagetool` | 本地图片读取与元数据操作。 |
| `Phototool` | 系统“照片”图库接口。 |
| `ImageData` | 图片状态及不同元数据来源的整合。 |
| `RunLogView` | 应用内日志查看界面。 |

应用状态管理还使用外部 Swift 包 UDF。包位置集中到 `Packages/` 后，原有模块名及包之间的相对依赖保持一致。

## 测试

```sh
make test-localization # 七语言文案、占位符、资源及文档链接
make test-map   # 高德网页桥接测试
make test-unit  # 应用逻辑单元测试，不运行界面操作
make test-packages # 各本地 Swift 包的测试
make test      # 上述四项
```

也可以单独运行某个包的测试，例如 `swift test --package-path Packages/Coords`。

应用单元测试通过 `PHOTOTRAIL_OFFLINE_TESTS=1` 避免读取私人收藏、凭据和加载交互窗口；该环境变量在项目测试方案中设置。`make test-unit` 使用独立的 `local.PhotoTrail.Validation` 标识，避免覆盖日常应用的设置。界面测试需要单独配置交互运行环境，不能把单元测试结果视作界面或在线接口测试结果。

## 应用标识与兼容性

应用、Xcode 项目、构建目标、Scheme 和 Swift 主模块均使用 PhotoTrail 名称。默认本地构建采用 ad-hoc 签名，开发者可通过 Xcode 构建设置覆盖签名配置。

`PHOTOTRAIL_BUNDLE_ID` 默认仍为 `local.GeoTagCN`，用于沿用已发布版本的沙盒。旧的 `GeoTagCN` 偏好、钥匙串服务名和缓存路径仅用于数据迁移，不能随目录重命名而直接删除或替换。地图网页与 Swift 的当前桥接名称为 `photoTrail`。

Git 标签参与版本号计算，具体逻辑见 `scripts/build-version.sh`。重构目录不改变版本标签，也不改变既有用户数据格式。

## 功能约定与来源

地图、照片写入、凭据、隐私、轨迹缓存和界面行为见 [功能与数据约定](BEHAVIOR.md)。

PhotoTrail 基于 GeoTag v6.0.2 派生，仍使用其部分应用基础设施与照片处理模块；来源及许可证见根目录的 [LICENSE](../LICENSE) 和 [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)。

## 软件更新检查

使用 URLSession 读取 GitHub 公开 Releases/latest 接口，无需令牌或额外更新框架。版本按数字分段比较；“自动下载更新”偏好单独保存且默认关闭。启用后只下载命名及地址与版本匹配的 DMG，核对发布资产大小和 SHA-256（优先用 API digest，缺失时读取同一 Release 的 `SHA256SUMS.txt`）。DMG 放在应用沙盒的 Application Support 中；下次启动由用户打开镜像、退出应用并手动拖入“应用程序”文件夹，不执行自动替换。发布流程无需 appcast.xml 或额外签名密钥；仍保留现有沙盒及 Hardened Runtime 配置。`PHOTOTRAIL_OFFLINE_TESTS=1` 禁止联网检查和自动下载。

## 多语言维护

支持 `zh-Hans`、`en`、`zh-Hant`、`ja`、`ko`、`es`、`pt-BR`。未知系统语言回退到英语；葡萄牙语各地区匹配到巴西葡萄牙语。`Localization.swift` 管理应用语言、资源查找和首启地图默认值，不依赖在线翻译服务。

界面文案集中在 `Sources/PhotoTrail/Localizable.xcstrings`，权限提示在各语言的 `InfoPlist.strings`，Metadata 和 RunLogView 使用各自包资源。新增文案须补齐七语言，使用完整语句和位置占位符，不拼接句子；计数优先使用“数量：n”等不依赖单复数的标签，新增需要复数语法的句子时使用原生 String Catalog 复数规则和数值参数。

高德网页在文档开始时接收 JSON 编码的文案。桥接错误码、服务错误白名单、持久化枚举原始值、GPX/XML 与 JSON 字段、坐标协议、扩展名和 Skill 命令参数不随语言变化。README 和 Skill 使用指南提供七语言互链；新增功能时同步对应页面。开发说明提供中英两版，许可英文译文仅供参考，原始许可和第三方授权不变。

引导语言立即切换；系统菜单、权限提示及缓存窗口需要保存工作并重新打开应用。`LocalizationUITests` 提供七语言引导与设置检查；使用独立 bundle ID 和离线模式，Debug 专用 `-LOCALIZATIONPREVIEW` 可在不读取私人数据的情况下展示界面。界面测试需要可交互的 macOS 会话。
