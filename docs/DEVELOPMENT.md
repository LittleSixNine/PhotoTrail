# PhotoTrail 开发说明

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
make test-map   # 高德网页桥接测试
make test-unit  # 应用逻辑单元测试，不运行界面操作
make test-packages # 各本地 Swift 包的测试
make test      # 上述三项
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

使用 URLSession 读取 GitHub 公开 Releases/latest 接口，无需令牌或额外更新框架。版本按数字分段比较，发现新版后由用户打开发布页下载 DMG、手动替换。发布流程无需 appcast.xml 或额外签名密钥；仍保留现有沙盒及 Hardened Runtime 配置。`PHOTOTRAIL_OFFLINE_TESTS=1` 禁止联网检查。
