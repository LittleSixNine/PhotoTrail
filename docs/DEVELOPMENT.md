# PhotoTrail 开发说明

**简体中文** · [English](i18n/DEVELOPMENT.en.md)

## 环境与构建

需要支持 Swift 6.3 或更新版本、macOS 26 或更新 SDK 的完整 Xcode，以及 XcodeGen。安装 SwiftLint 后会在构建时运行代码检查；未安装时构建脚本给出提示。地图脚本测试需要 Node.js 20 或更新版本；可通过 `make test-map NODE=/path/to/node` 指定可执行文件。

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

## macOS 14 兼容构建

主项目与八个本地包部署目标统一为 macOS 14；继续使用新 SDK，不降低 Swift 语言模式。当前 UDF revision `2b129e07e41957dda462838323cb1b0e09b2265c` 声明 macOS 14、Swift 工具链 6.3，构建工具链须同时满足它；项目语言设置仍为 Swift 6.2。复用解析结果，验证时使用 `-disableAutomaticPackageResolution -skipPackageUpdates`，不顺手更新 main。

Debug／Release 都须检查真实二进制的最低系统版本；双架构构建显式设置 `ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO`。编译通过不等于旧系统或 Intel 实机通过。Xcode 中使用自定义 traits 的开发预览需 macOS 15，不影响应用在 14 的运行入口。0.5.8 起支持 macOS 14 及以上。构建与运行验收应分别记录，具体系统／架构测试结果保存在发布验证记录中。

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
| `GpxTrackLog` | GPX／KML／KMZ 读取、统一轨迹数据与时间匹配。KMZ 复用 macOS 的 `/usr/bin/unzip`，不新增外部依赖。 |
| `Metadata` | 统一的照片元数据模型。 |
| `Exiftool` | 随应用提供的 ExifTool 及调用封装。 |
| `Imagetool` | 本地图片读取与元数据操作。 |
| `Phototool` | 系统“照片”图库接口。 |
| `ImageData` | 图片状态及不同元数据来源的整合。 |
| `RunLogView` | 应用内日志查看界面。 |

应用状态管理还使用外部 Swift 包 UDF。包位置集中到 `Packages/` 后，原有模块名及包之间的相对依赖保持一致。

## 测试

字段显示来源解析的规模基准可用 `PHOTOTRAIL_DISPLAY_BENCH_PATH` 指向一张生成的 JPEG，运行 `swift test --package-path Packages/Exiftool --filter MetadataDisplayPerformanceTests`；固定快照按 530 张、73 个字段解析三轮并核对原始字节不变。它测 CPU 解析，不包括 530 次文件读取；实际全选／菜单／窗口首帧须另用同一批 530 张合成副本前后测量，分别记录输入与辅助观察开销。

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


### 元数据工作流定向验证

`swift test --package-path Packages/Exiftool` 验证白名单、默认语言分支、精确 Unicode、日期成组写入、文件系统时间、IPTC 时区规则和保护字段；`swift test --package-path Packages/ImageData` 验证草稿、日期边界、预设与 CSV 往返；App 的 `MetadataCreatorBatchTests` 覆盖 1／20／100 张、取消和主日期保存／重开。全部只使用公开测试资源的临时副本。

千文件验证默认跳过；需要测量时执行 `PHOTOTRAIL_SCALE_TESTS=1 swift test --package-path Packages/ImageData --filter MetadataScaleTests`。输出读取、计划、保存／核对耗时；这是包级测量，不代表 App UI 内存或用户验收。缓存／沙箱受限时可按实际环境指定临时 `CLANG_MODULE_CACHE_PATH` 并使用 `--disable-sandbox`，不要把环境权限失败视为测试通过。

元数据产品形态验收使用独立 Debug 标识 `local.PhotoTrail.MetadataReference…`；该前缀在共享凭据读取入口直接返回空值，避免元数据验证请求日常高德钥匙串。此保护只编译于 Debug，不改变发行 App 的凭据行为或系统钥匙串权限。

## 开发进度与元数据读取入口

源码节点见 [开发历史](CHANGELOG.md)。`MetadataLoadingQueue.swift` 负责窗口级后台预读、选中插队、缓存和进度；`MetadataListInspectorView.swift` 负责显示与类型编辑入口；Exiftool 的 `inspectionTags` 读取所有可识别家族，写入仍受独立白名单约束。`MetadataCreatorEditPlan`、`SaveTargets` 和 `SaveHelper` 负责冻结目标、版本检查、备份及回读。`RenameWorkspaceView` 提供第三页双栏规则与预览；`RenameEngine` 只计算名称，`RenameWorkspace` 冻结输入、计数与来源，`RenameExecutor` 使用独立执行日志、原生不覆盖改名和哈希回读；`ImageData.applyFileRenames` 同步稳定 ID 的名称、来源和撤销基线。规则目录包含文字、日期、序列、设备及定位字段等动作，以及筛选与高级设置，具体支持边界见 [功能与数据约定](BEHAVIOR.md)。


## 浏览性能与会话缓存

`PhotoListProjection.swift` 按照片数据标记缓存列表筛选／计数、照片条排序和元数据面板的所选照片快照；数据变动使用 UUID，避免撤销后不同编辑分支共用旧缓存。日期解析只随该张照片时间或相机时区变化更新。照片条菜单延迟到打开时构建，避免布局期间反复扫描所选照片与读取剪贴板。

元数据列表按 80 点乘屏幕倍率请求小图；定位照片条按显示宽度与倍率选择 160／256／384／512／768／1024 像素档位。小图和 1024 像素大预览分别有 64 MiB 估算预算及 384 项上限，画面持有的图像与正在解码的图像不计入该预算。本地解码最多并发 2 项，当前预览优先于等待中的普通缩略图。缩略图、元数据读取及列表计算缓存均不持久化；正式版标识和轨迹缓存路径继续保留。

`PhotoInteractionTests` 覆盖 2000 张照片连续选择、时间／时区变化、配对、缓存分离和撤销后继续编辑；`MapPhotoPerformanceTests` 覆盖地图分组及滚动容器替换。逻辑检查不等同于实际滚动帧率或真实 RAW／外置盘验收。

地图侧栏使用 `SidebarScrollView`，在创建原生 `NSScrollView` 时就配置固定竖向栏位；外栏继续使用已保存的宽度比例。托管内容显式继承完整 `EnvironmentValues`，并按 clip view 可用宽度测量图片与换行文字，不依赖后装扫描。`SubtleScrollbarTests` 覆盖首轮布局、环境传递、动态高度和滚动位置、宽度相关内容，以及完整 `PhotoDetailPage` 离屏重建后保留已保存比例。离屏检查不代表真实窗口首帧或用户原场景已修复。

`LinkedRegionTests` 覆盖地区联动仅补空值、已有文字与草稿保护、固定目标、迟到结果和忙碌状态；`SaveAddressTests` 覆盖关闭既有开关时不查询、保存时只补缺失字段、失败后保留定位及不符合条件的快照。设置与侧栏共用 `SettingsPreferences.writeRegionKey`（`PhotoTrailWriteRegionWithLocation`，默认 true），不引入第二个持久开关。

### 共享照片集合与预设回归

三页导入统一为 `ContentView` 的导入入口和 `OpenHelper.importFiles`，照片集合／选择在 `PhotoTrailState`；重命名不再保存独立文件 URL 列表。移除复用 `.removeImages` 与撤销，改名／恢复仍通过 `.filesRenamed` 回写共享对象。导入层在保存或改名执行期间拒绝新任务。

`RenameWorkspace` 通过 `PhotoTrailRenameLastPreset.v1` 记录上次方案的已保存规则与设置，恢复时优先读取对应个人预设；处理范围不随预设持久化，启动默认全部照片。`RenamePresetTests` 使用独立 UserDefaults 域，验证重启、更新、改名、删除及不保存规则草稿；`OpenHelperTests` 验证共享导入、去重、移除与撤销，`RenameTests` 验证共享照片改名后的路径回写。`MetadataClipboardTests` 和 `MetadataLoadingQueueTests` 分别覆盖多字段复制及保存刷新边界。逻辑测试不等于完整真实照片、NAS 或 GUI 验收。

## 跨平台行为验收

新增设置、轨迹调整与重命名顺序的稳定需求 ID、默认值、距离算法与非私人合成样本集中在共同契约中。修改相关逻辑时复用应用测试、GPX 包测试及地图／本地化检查；Windows 按 ID 独立记录实现和实机验证，不能把 Mac 通过当成 Windows 验收。 [共同契约](FEATURE-CONTRACT-v1.md)。


## 直接应用定向检查

`MetadataDirectApplyTests` 覆盖 530 张草稿提交／一次撤销、开始计算后的取消、选择／草稿／跳过来源变化与迟到请求隔离；`MetadataDirectApplyValidationTests` 覆盖请求内 IPTC 编码读取复用及版本变化。运行规模基准：`PHOTOTRAIL_DIRECT_APPLY_BENCH=1 swift test --package-path Packages/ImageData --filter MetadataDirectApplyPerformanceTests`；XMP 计算基准使用 `PHOTOTRAIL_DIRECT_XMP_BENCH=1`。基准使用合成临时输入与稳定快照，区分计算、来源复核及应用提交；不代表私人照片耗时或 UI 验收。


`MetadataBatchEditingTests` 验证多字段保持／显式清除、精确值分布与关键词覆盖、范围缩小、整批时间间距的 3 张示例、重复文件名的稳定跳过身份、一次撤销及退出输入保护。`MetadataBatchEditSession` 的输入跨工作区保留，不写入持久预设或照片；`MetadataWorkflowPreview.skipDetails` 仅携带照片 ID、名称、字段与原因，原字符串结果保留兼容。

`MetadataBatchEditingTests` 补充有序逐项计数分区、同字段重复任务／删除、切换选择后单张应用、清空及无效／过期输入保护。`MetadataDraftRequest.requiresSelection` 默认仍为 true；只有单张原位编辑放宽选择／排序检查，保留固定照片、草稿、来源及文件版本校验。

批量项把多接收字段展开为既有 v1 复制动作；逐项统计按照片合并目标结果，优先修改、其次跳过、最后不变。回归覆盖逐照片不同日期、部分目标跳过、预设回读，以及副本立即插入和独立 ID／参数。


`CombinedMetadataSaveTests` 覆盖定位与字段的单次写入／原片备份、JPEG 与已有 XMP、写入及清空拍摄时间、先定位后编辑、保存范围、重复目标、来源变化和备份失败。合并链路仍由 Mac 包适配层处理，不改变共享日期核心或预设协议。

`MetadataWorkflowCardTests` 同时覆盖自定义文件名日期格式的标记校验、顺序和字面字符匹配、预设 v1 往返及格式文本恢复；格式编码仅在 Mac 适配层，不改变共享日期协议。

`MetadataWorkflowCardTests` 覆盖常用预设默认前三项、持久选择、去重及删除名称过滤；`MetadataBatchEditingTests` 覆盖隐藏规则与单字段输入分离时的退出保护。界面卡片、覆盖动画和分隔线稳定性另做原生交互验收，不以逻辑测试代替。

`PhotoListClearTests` 覆盖全列表（含未选项）清空、照片与草稿撤销、轨迹／文件／访问范围保留，以及保存、导入、重命名执行和空列表阻止清空；菜单 ⌘K 与工具栏共用确认流程，原生检查另验三页入口与地区联动控件。


重命名目录授权使用 `RenameWorkspace` 的安全作用域书签；`project.yml` 显式生成 `com.apple.security.files.bookmarks.app-scope` entitlement，与原用户选择读写权限一起使用。目录覆盖按真实路径组件检查，修改权限每次预览／执行重新核对；只把实际输入文件的父目录传给配对与冲突扫描。`RenameTests` 覆盖上级目录持久授权、子目录配对／冲突、只读目录、相似前缀及符号链接越界。自动测试不替代系统目录选择器及跨进程／外置宗卷重挂载实测。


重命名的 ExFAT 兼容分支仅在 `renamex_np(RENAME_EXCL)` 返回 ENOTSUP 后启用：O_EXCL／O_NOFOLLOW 创建目标，fcopyfile 复制数据与属性、同步及 SHA-256／源版本复核后 unlink 原名；不调用存在竞争覆盖风险的普通移动。复制后的 inode 可变化，日志可选 `copyCompatible` 标记支持内容与时间核对，新增可选 `failure` 保留失败原因。创建时间通过原生属性接口设置；ExFAT 小数秒不能保证保留，确认与行为文档必须说明。`RenameTests` 覆盖兼容复制、重名／符号链接、错误持久化、旧日志及弹窗状态；真实宗卷验证仅用独立生成样本，禁止将用户原片作为试验材料。

`MetadataHEICEditingTests` 使用公开合成 HEIC 副本，覆盖单字段赋值／清除、HEIC／HEIF／JPEG 混合批量预设、日期偏移与复制、IPTC 跳过、定位合并、原片备份和像素数据不变；Exiftool 的 HEIC 样本另验证 EXIF／XMP 回读。

### 静态图像格式与 JPEG XL 元数据

`MetadataImageFormat` 集中维护静态图像导入与受控 EXIF／IPTC／XMP 字段资格，完整清单见 [格式支持](FORMATS.md)。导入窗口和拖入路径复用同一清单；没有 ImageIO 解码器时以 ExifTool 读取元数据，不能把读取回退等同于预览解码成功。

Exiftool 包的 `MetadataCodecPlugin` 使用 Xcode 的 clang 编译 `Tools/MetadataBrotli.c`，链接系统 Compression，生成 macOS 14 起可用的 arm64／x86_64 通用辅助资源并做 ad-hoc 签名。插件资源由 SwiftPM 打包；不要手动把构建出的 `.bin` 纳入源码。随包 Perl 适配器只处理临时元数据缓冲，输入／输出均限于 100 MB 内；不依赖 Homebrew、外部 Perl Brotli 模块或额外运行时安装。

`MetadataBrotliTests` 验证压缩 JPEG XL 写入、编码图像数据不变、无效数据及解压边界。`MetadataFormatParityTests` 生成 PNG／TIFF／GIF／BMP 副本，验证字段家族、定位合并、备份、像素及日期清除；设置 `PHOTOTRAIL_FORMAT_FIXTURES=/path/to/public-fixtures` 可补测公开代表样本，`PHOTOTRAIL_FORMAT_OUTPUT` 可保存写后副本供容器／像素核对。App 的 `MetadataFormatImportTests` 覆盖静态图像导入排除项与沙盒内 Brotli 辅助程序执行。测试样本复制、转换和解码工具只用于开发验证，不作为最终用户依赖。


`MetadataDateBatchTests` 覆盖 Mac 日期处理的逐照片来源回退／冲突、缺值、时区、九位亚秒、旧预设识别、原子草稿／撤销、同值／无效粘贴，以及临时 JPEG 副本的 IPTC 保存／备份／回读。界面上的菜单与文本框收起另用独立标识的候选验证，不使用日用会话或原始照片。

`MetadataUnifiedBatchTests` 覆盖统一操作链、仅接收字段补时区、缺时区仅跳过 IPTC、临时参数与显式更新、旧 v1 预设／损坏数据保护，以及全部照片的冻结、非选中项应用和撤销。主界面预设参数与统一侧栏的保存／收起另用独立测试 App 验证。日期补值与时区策略存于 Mac 本地伴随参数；旧 v1 导出遇到这些额外参数时拒绝导出，避免静默丢失。

默认日期规则的定向回归同时验证十个接收字段、IPTC 日期／时间拆分、七语言旧内置规则的一次升级，以及改名、编辑、删除和伴随时区参数的保留；升级失败不更新完成标志。文件时间仍复用 `MetadataFileTimeSaveTests` 的副本保存与回读检查。

`RenameTests` 覆盖缺字段默认跳过单条规则／显式保留原名、旧方案缺省与可选设置往返、关联文件、读取失败及冲突保护，并分别验证两种策略不复用后续编号；`SettingsTrackRenameTests` 回归排序、筛选和工作区集成。
