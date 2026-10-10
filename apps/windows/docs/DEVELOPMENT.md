# PhotoTrail Windows

## Windows 原型构建

Windows 开发工程独立位于 `apps/windows`，使用 .NET 10 WPF、WebView2 和外部 ExifTool。在该目录运行 `dotnet build PhotoTrail.Windows/PhotoTrail.Windows.csproj`；配置工具、运行方式、测试环境变量、现阶段范围和许可证见 [Windows 开发说明](../README.md)。此入口不替代仓库原有 macOS 构建流程。

Google存储检查使用WindowsDesktop内置DPAPI，测试工程为net10.0-windows且无需额外NuGet包；设置PHOTOTRAIL_TEST_OUTPUT为独立私有输出目录后运行 `dotnet run --project PhotoTrail.Windows.Tests/PhotoTrail.Windows.Tests.csproj -- --key-checks`，当前17项。检查只使用假密钥，不会调用Google或触碰正式配置文件。

Google替身检查：`dotnet run --project PhotoTrail.Windows.Tests/PhotoTrail.Windows.Tests.csproj -- --google-checks`（25项），`node PhotoTrail.Windows.Tests/google-page-checks.cjs`（17项）；不执行网络。设置原有ExifTool/样本/输出变量后`--region-checks`执行14项真实副本保存检查。Google真实验收需用户自行配置Maps JavaScript/Geocoding API、计费、HTTP来源限制及配额；密钥通过应用界面输入。

设置PHOTOTRAIL_TEST_OUTPUT为私有输出后，重命名检查入口为`--rename-checks`（42项）、`--rename-execution-checks`（25项）、`--rename-bulk-checks`（3000个合成小文件真实更名/恢复，逐项SHA256）。全部在新GUID目录中使用派生或合成文件。Windows句柄更名复用CreateFileW/SetFileInformationByHandle，拒绝覆盖；真实RAW/NAS/断电恢复另验，不能以小文件检查代替。

## CSV验证与候选边界

`dotnet run --project PhotoTrail.Windows.Tests -- --csv-checks`执行47项CSV纯检查；`--csv-copy-checks`使用既有PHOTOTRAIL_EXIFTOOL、PHOTOTRAIL_FIXTURES、PHOTOTRAIL_TEST_OUTPUT环境设置验证8项真实副本行为。CSV只采用.NET自带Microsoft.VisualBasic.FileIO.TextFieldParser，无新包。重命名当前预览44项、执行25项检查。阶段3/4自包含候选含.NET/WindowsDesktop10.0.12与完整ExifTool发行，不含此CSV源码增量；当前机器内置工具启动通过，干净机器/第二台待验。

## 日期检查

`--date-checks`执行40项日期解析/偏移/序列/明确时间检查；`--date-copy-checks`用既有ExifTool/fixture/output变量验证6项真实副本行为。默认元数据回归当前73项PASS。日期处理使用.NET DateTime保留墙钟值，未对无时区值使用本机时区；小数原样保存，轨迹自动填充不丢失亚100ns精度。

## 字段预设检查

`--preset-checks`执行30项结构/值/版本/重复属性/边界检查；`--preset-copy-checks`用现有工具/fixtures/output变量验证7项真实副本行为。预设原子文件导出复用既有UTF8文本落盘实现，无新依赖。真实Mac互导与UI操作须另存证据，不以Windows结构测试代替。

## 字段剪贴板检查

`--clipboard-checks`执行19项纯值/目标/边界校验，不操作系统剪贴板。真实UI须先复制合成测试字段，再粘贴验证；不得从用户原剪贴板读取测试素材。系统剪贴板与完整字段/GPS兼容另列实机证据。

## 批次读取检查与性能

`--batch-checks`当前21项实际/替身读取边界检查（另输出25项地图协议）；`--batch-benchmark 300`或`3000`比较相同316698字节合成JPEG副本。批次32主/64物理文件，SourceFile精确映射、单张回退、版本及配对核验均保留。记录核心/进程工作集，不含WPF/WebView/ExifTool子进程；实际UI压力另验。CLI传文件夹仅展开当前层，可用于实际界面批量导入。

XMP交换核心：按现有ExifTool/fixtures/test-output环境运行测试项目 --xmp-checks（23项真实工具检查）；读取stdout改为原始字节供XMP提取，普通工具响应严格UTF8。官方命令依据：https://exiftool.sourceforge.net/exiftool_pod.html 。

地图ProcessFailed恢复依照Microsoft官方进程说明：https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/process-related-events 。浏览器退出需替换WPF控件，渲染失败重载页面；实机测试用独立WEBVIEW2_USER_DATA_FOLDER，核对父进程与隔离路径后只终止自己的测试进程。不得终止共享缓存或用户浏览器。

日期组件替换接入后--date-checks当前64项，--date-copy-checks12项真实副本/撤销检查；旧40/6项是此前基线。替换仅用DateTime原生日期构造，一次验证最终组合，保留小数秒/时区原文字。

日期均匀分布接入后--date-checks当前79项，--date-copy-checks18项；对齐已有Mac MetadataDate.distribute的最近整秒/起止后缀约定，Windows采用有界整数运算以避免浮点舍入误差。

--preview-checks执行26项原生WPF JPEG/PNG检查，环境只需PHOTOTRAIL_TEST_OUTPUT私有目录；八种非对称像素方向、最长边、冻结/线程间使用、文件锁释放、SHA/格式/损坏/大小边界。GUI取消源生命周期与切换另存实机证据。平台依据：https://learn.microsoft.com/en-us/dotnet/api/system.windows.media.imaging.bitmapimage 及 https://learn.microsoft.com/en-us/dotnet/api/system.windows.media.imaging.transformedbitmap.transform?view=windowsdesktop-10.0 。

## 原生系统主题

使用Window.ThemeMode与WPF自带Fluent主题，无新增依赖。固定.NET10 SDK中的C# ThemeMode调用标记为WPF0001实验API，仅该赋值局部禁用诊断；SDK升级需重验主题切换。外观选择保存本机偏好，地图网页主题独立。参考[官方ThemeMode文档](https://learn.microsoft.com/en-us/dotnet/api/system.windows.window.thememode?view=windowsdesktop-10.0)。本机200%浅色/深色实测，其他DPI、高对比度、窄窗口仍待验。

文件名日期复用MetadataDate与.NET RegexOptions.NonBacktracking/Match.Result，无新依赖；正则1024/模板512/文件名255/批量3000限制，100ms匹配超时。参考[官方非回溯模式说明](https://learn.microsoft.com/en-us/dotnet/standard/base-types/regular-expression-options#nonbacktracking-mode)及[捕获组替换](https://learn.microsoft.com/en-us/dotnet/api/system.text.regularexpressions.match.result?view=net-10.0)。--date-checks现92项，含3000病态回溯输入、无效规则/闰日/缺组/亚秒；--date-copy-checks现24项真实副本与撤销，覆盖新增文件名日期。

外观偏好验证入口--theme-checks，34项；默认%LOCALAPPDATA%/PhotoTrail/Windows/theme.json，测试可设PHOTOTRAIL_THEME_FILE为独立配置路径（不包含密钥）。4KiB/版本/类型限制，原子替换，已检测损坏拒绝覆盖；多个实例采用最后成功保存。实机测试采用私有独立路径，未改用户默认配置或OS外观。

地图初始化：环境CreateAsync与EnsureCoreWebView2Async各限15秒；WaitAsync仅停止宿主等待，不能取消底层原生初始化。TimeoutException标记下一次重试替换控件，复用浏览器退出恢复路径；缺失运行时用WebView2RuntimeNotFoundException提供中文处理说明。实机故障测试仅子进程环境WEBVIEW2_BROWSER_EXECUTABLE_FOLDER指向私有空目录；正常测试清除此变量，不调整系统运行时。短时离线测试仅独立WebView2 profile的WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS使用不可连接本机代理，旗标不写产品代码或分发配置。参考[官方开发旗标](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/webview-features-flags)。

控件重试依据：[EnsureCoreWebView2Async官方约束](https://learn.microsoft.com/en-us/dotnet/api/microsoft.web.webview2.wpf.webview2.ensurecorewebview2async)：原生初始化未失败时，不可在同一控件传入不同环境。超时实机复现仅在独立子进程使用启动等待旗标，不修改产品旗标或系统设置。

DNG预览：设置既有ExifTool/fixtures/test-output变量运行 --dng-preview-checks（11项），复用 --preview-checks（26项）。只提取PreviewImage，ExifTool使用原生工作目录＋随机ASCII输出名，避免-W格式码解释用户临时路径中的百分号；其他调用默认工作目录不变。参考[ExifTool输出参数](https://exiftool.sourceforge.net/exiftool_pod.html)。

轨迹历史合并：--history-checks现38项，包含四个真实检查进程、20项上限、损坏拒绝、5秒锁超时、遗弃Mutex恢复、读者持有旧快照时替换。NamedMutex按规范完整路径/大小写归一哈希分组，同一Windows会话内串行合并；GUI后台保存并await结果，不跨线程更新界面。File.Replace在受限沙箱因权限被拒绝，38项需正常Windows权限运行；不调整ACL或安全设置。实机旧测试轨迹导入/提示/源与历史SHA不变已验。跨Windows会话/别名路径及多窗口同时操作另验。参考[Windows原生替换](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-replacefilew)。

GPS剪贴板检查：--clipboard-checks现47项；既有ExifTool/fixtures/output变量下--gps-clipboard-copy-checks执行6项真实副本/撤销检查；默认回归现75项。JSON仅format/latitude/longitude三个唯一属性，format为PhotoTrail GPS 1，范围在浮点格式化前校验。测试系统剪贴板须先用应用复制自己的测试照片坐标，不读取用户原剪贴板。实机默认地图首开可聚焦预览坐标；Google真实焦点路径/多目标混合/非法文字UI及Mac互导另验。

设备字段复用--common-fields-checks，现55项，覆盖JPEG与DNG旁车副本/回读/清除、原EXIF与像素/源SHA保留、CSV无变化回导、预设/文字剪贴板/XMP交换及超长拒绝；CSV47/预设30/剪贴板47回归通过。

常用字段--common-fields-checks现82项，新增三日期非法闰日/偏移/超长小数秒拒绝、空清除、精确小数秒/时区回读、XMP交换和DNG旁车；已有CSV47/预设30/剪贴板47/日期92检查通过。早期检查因给日期字段粘贴评分3而失败，修正检查范围，保留首次失败证据。

--common-fields-checks现212项，覆盖七曝光字段范围/非有限/零分母/非法整数/分数规范化、JPEG与DNG旁车副本、XMP数值导入与回读舍入容差。既有CSV47/预设30/剪贴板47/XMP23检查通过。首次XMP导入拒绝新曝光JSON数值已复现修复，失败证据保留；实机七项保存与ExifTool独立-n回读通过。

## 2026-10-10 · 可还原源码基线

从已保存的Git基线与源码覆盖层独立还原后，应用/检查工程构建均0警告0错误。本轮通过：默认元数据/GPS75、常用字段212、日期92、CSV47、预设30、剪贴板47、重命名预览44/执行25、轨迹历史38、主题34、预览26、DNG预览11、版本保护12，以及GPX/KML和地图消息检查。本机单照片草稿/副本/回读/撤销已验；只做当前基线检查，不以此宣称全部功能或所有格式通过。未安装Swift，不修改Mac构建入口。

## 日期页Swift宿主构建

先运行DateHost/Build.ps1，再构建WPF；固定Git对象原字节导出/hash校验、既有工具前置和协议见[宿主说明](../DateHost/README.md)。生产不引用私有实验或移动HEAD。168条隔离检查、92条原C#日期回归、67条生产草稿/副本检查、99条真实WPF控件交互检查在本机通过；断言数量不是功能数量。UiChecks引用实际MainWindow，测试自身宿主缺失/损坏/超时并恢复；源码只限Windows。干净机器、许可和正式包仍待验。
