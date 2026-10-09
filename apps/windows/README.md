# PhotoTrail Windows 开发原型

[行为约定](docs/BEHAVIOR.md) · [开发记录](docs/CHANGELOG.md) · [构建入口](docs/DEVELOPMENT.md)

Windows源码及公共文档的提交范围为本目录，Mac共享路径保持不变。当前阶段2本机验收通过，阶段3已接入GPX/KML/KMZ轨迹预览、时间匹配、GPS草稿与安全副本保存；完整Windows功能及不同DPI仍未完成。私人Windows日志与验证记录在私有工作区的独立windows目录保存，不进入本公开仓库。

当前为本地验证工程，尚未交付 Windows 安装包。需要 Windows 11 x64、.NET SDK 10.0.401 或兼容的 .NET 10 SDK，以及 WebView2 Runtime。

```powershell
dotnet build PhotoTrail.Windows/PhotoTrail.Windows.csproj
$env:PHOTOTRAIL_EXIFTOOL = '工具所在目录/ExifTool.exe'
dotnet run --project PhotoTrail.Windows/PhotoTrail.Windows.csproj -- '照片所在目录/sample.jpg'
```

工作目录为本文件所在的 `apps/windows`。ExifTool 必须使用完整 Windows 原生发行目录，保留随附文件；也可放入应用输出目录的 `tools/exiftool/`。开发时还可使用未纳入版本控制的 `bin/.../development-tool.json`，内容为 `{"executable":"ExifTool的绝对路径"}`。不在公开源码写入本机路径或凭据。

导入支持多选、拖入和当前层文件夹。XMP 从同名旁车优先读取，其他原始字段按来源分开显示。JPEG、XMP 可编辑五项 XMP：作者、标题、说明、关键词、拍摄时间；RAW 等图像已有同名旁车时只编辑旁车。其他格式仅读取。标题和说明只改 x-default，作者和关键词每行一项。拍摄时间格式为 `yyyy:MM:dd HH:mm:ss`，可附 `+09:00` 等时区，不支持亚秒。

选择照片，勾选要改的字段并输入，点击“加入草稿”；勾选且留空代表清除。多选的混合值不自动清除。“撤销所选草稿”恢复源文件读数。指定已有输出文件夹，点击“保存所选草稿为副本”；同名文件拒绝覆盖，源文件始终保留，成功副本仍保留源草稿。保存逐张执行，失败不阻止其余项目；取消保留已完成的副本。退出有草稿时提示，任务进行时先取消并等待结束。

默认地图使用本地 MapLibre 6.13.0 与 OpenFreeMap 在线底图。需要网络，不需要密钥；地图支持WGS84选点／轨迹匹配预览，显式加入GPS草稿后可另存副本；不自动写入、不查询地址。Google自备密钥／安全存储／地区解析、拖动定位、重命名、完整字段白名单和安装包仍待开发。

自动检查使用独立的新目录与派生照片：

```powershell
$env:PHOTOTRAIL_EXIFTOOL = '工具所在目录/ExifTool.exe'
$env:PHOTOTRAIL_FIXTURES = '私有样本目录/metadata-editor-g1'
$env:PHOTOTRAIL_TEST_OUTPUT = '私有验证输出目录'
dotnet run --project PhotoTrail.Windows.Tests/PhotoTrail.Windows.Tests.csproj
```

样本入口不随公开源码分发。测试覆盖保存回读、原图与像素不变、非目标字段保留、列表/语言、旁车、外部冲突、失败、取消、进程超时和地图消息边界。真实界面、系统文件对话框、批量交互及不同 DPI 的验收状态单独记录，不能以自动检查通过替代。

## 第三方组件

- MapLibre GL JS 6.13.0：BSD 3-Clause，许可证保留于 `PhotoTrail.Windows/Web/vendor/LICENSE.txt`。
- Microsoft.Web.WebView2 1.0.4258.31：NuGet 包许可证见包内资料及 Microsoft 文档；运行时独立安装。
- ExifTool：外部原生工具，遵循其随附许可；当前公开源码未捆绑二进制。
- OpenFreeMap：使用在线公开样式和图块，地图保留其样式提供的数据来源署名。

## 阶段3轨迹核心检查

源码新增GPX/KML/KMZ读取、轨迹显示和匹配预览，以及GPS副本保存；此前阶段2候选包保留原版本。无需ExifTool运行该检查：

```powershell
# 在 apps/windows 目录运行；可选用仓库自带Mac轨迹样本扩展检查。
$env:PHOTOTRAIL_TRACK_FIXTURES = '../../Packages/GpxTrackLog/Tests/GpxTrackLogTests'
dotnet run --project PhotoTrail.Windows.Tests/PhotoTrail.Windows.Tests.csproj -- --track-checks
```

有样本路径时29项，无样本路径时21项。标准XmlReader流式解析，有界输入并禁止DTD/外部实体；无时间几何保留，但不参与匹配。精确点优先、同段相邻点插值，不跨缺失时间点、不外推；跨日期变更线按最短经度方向插值。不同位置歧义不自动定位；1米门槛采用球面距离近似。KML/KMZ与图层已实现；GPS写入仅经显式草稿后另存副本，原文件保持只读。

KML/KMZ及地图消息检查：`dotnet run --project PhotoTrail.Windows.Tests/PhotoTrail.Windows.Tests.csproj -- --kml-checks`，24项通过。设置ExifTool／元数据样本／私有输出目录后运行默认检查，38项元数据回归＋18项GPS检查通过。命令行可同时提供照片和GPX/KML/KMZ文件，`--map`打开地图页；也可在地图页选择轨迹文件或拖入。匹配时间必须带Z/UTC偏移。GPS草稿和字段草稿共享“保存所选草稿为副本”及撤销入口。

后续开发记录维护于本目录docs/CHANGELOG.md；私人日志在独立private/windows目录。Mac的共享README、docs和源码保持不变。
