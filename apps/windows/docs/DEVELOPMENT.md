R09b checks: SourceTests `--r09b-location-checks`, UiChecks `--r09b-checks`; manual synthetic values only, D06 online persistence BLOCKED. Tests use their own GPS and source guards; final EXE/copy readback is separate.

R09a checks: SourceTests `--r09a-map-checks`; UiChecks `--r09a-checks`; `node PhotoTrail.Windows.Tests/map-workspace-checks.cjs` executes actual map scripts with local API mocks, no service. Isolate PHOTOTRAIL_MAP_WORKSPACE and all existing test preferences.

R08b：SourceTests `--r08b-sequence-checks`、UiChecks `--r08b-checks`；后者使用生产窗口及隔离计数/方案。候选检查必须绑定最终发布DLL，原生EXE另行观察。

## R08b 高级序列与方案（2026-10-15）

重命名参数规则新增 number-set/begin/end/before/after/position、roman-*、alphabet-*、number-change/remove 与 name-list。JSON每行一条，使用明确动作名；支持64位起点/步长、宽度、前后缀、每实际目录编号。数字运算溢出、除零、字母范围外或Roman非1—3999整次拒绝。Counter=1—10仅用于正向非负数字规则；当前值独立本地保存，预览/取消不推进，完整执行和文件核对后推进，恢复文件不自动回退编号。

持续计数执行前持久写入.pending，跨Windows会话文件锁阻止并发；失败/断电保留未知记录，关联文件禁止继续写入。只允许符合完整范围的显式恢复清除已核对记录，不自动重用未知编号。独立测试可用PHOTOTRAIL_RENAME_COUNTERS隔离计数文件。原事务和草稿保护保持。

冲突可阻止或给整配对组追加数字/字母后缀，支持直接/下划线/短横线/括号，数字最小2—5位且超宽保留完整值。冻结扫描真实目录，执行仍由原生句柄进行不可覆盖更名及来源/属性复核。

本地库v2、Windows方案/规则v3明确保存参数和任务设置；旧规则v1/v2仍读取，旧默认冲突策略保持。Mac v1仅显式转换1—16、24—27、38、46—65、97动作，要求默认词性/日期/筛选/配对配置；不复制当前计数值。其他动作、非默认筛选和自然/日期/元数据排序整方案拒绝。这里的映射由固定源码和合成样本验证，未完成Mac实际互导或全Unicode等价验证。

R07定向验证：UiChecks `--r07-checks`（1/20/21/100比较、全部CSV应用／撤销、共享日期逐行拒绝、XMP与JPEG／旁车回读、真实来源失联重读）；Tests `--csv-checks`、`--xmp-checks`。所有输出用独立副本及隔离偏好。CSV路径越界按本批授权比Mac行跳过更严格，不能放松身份门；跨平台映射只有明确授权的合成试验，不是隐式互导。

R06b定向验证：UiChecks `--r06b-checks`／`--r06b-scale`（1/20/100），Tests `--preview-checks`。使用独立合成副本、隔离偏好与历史；正式候选最终DLL和原生EXE结果分别记录。沿用固定DateHost，不重建Swift。

## R06a定向检查

沿已有.NET10／WPF与ExifTool依赖，运行DateHost/UiChecks的`--r06a-checks`及`--r06a-scale`；使用短独立合成目录、隔离配置和历史。最终EXE／DLL与源模型归属分开，复制已验DateHost，不重建Swift。记录枚举（含有界背压）、元数据、接纳／刷新、首图、冷／热及当前图耗时，实际请求／并发／缓存预算和Dispatcher间隔；不把单次样本当中位数。

> 2026-10-14 · R05复用原DateHost38文件组合；不重建Swift、修改共享源或安装环境。新增UiChecks --r05-checks/--r05-restart/--r05-scale，使用隔离短路径合成材料、显式设置/历史目录，最终候选DLL/EXE与早期构建分别记录。单次1/20/100全链阶段及代表副本保存独立测量，不混旧性能。见[契约](DATE-PRESETS.md)。

## R04c 定向验证

沿既有 .NET10／Release win-x64框架依赖构建，不重建固定Swift宿主。UiChecks使用生产WPF与同一生产程序集：`--r04c-checks`、`--r04c-restart`、`--r04c-scale`（PHOTOTRAIL_R02_COUNT=1／20／100）；断言与导入观察分列，最终候选与早期构建分别记录。所有输入、备份／历史、偏好和输出须隔离。

故障验证只用于合成JPEG：设置PHOTOTRAIL_R04C_TEST_PYTHON为已有Python，PHOTOTRAIL_R04C_FAULT_TOOL指向UiChecks/attribute-readback-fault.py，PHOTOTRAIL_R04C_FAULT_TARGET及PHOTOTRAIL_R04C_FAULT_MARKER分别为本测试目标／唯一标记，PHOTOTRAIL_EXIFTOOL为现有完整工具。包装器仅在本夹具提交到2023-01-01 UTC后故意改修改时间10秒，再实际调用工具；验证真实属性回读不匹配的unknown与重启保护。不得设置为用户照片、旧备份或日用实例。重启沿原测试目录且不重建输入／清理记录。

[WindowsFILETIME精度／零值哨兵／v1与v2契约](NUMERIC-TIME.md)；API及历法边界、APEX底层与实际IIM字节、取消、副本／原位／恢复、属性外部变化、CSV／剪贴板／固定预设和受影响回归分别核验。无SDK部署／许可NOTICE／SwiftPM14001仍未闭合。

> R04b 验证入口：UiChecks `--r04b-checks`／`--r04b-scale`，仅隔离获准临时副本、独立备份／历史。原始 IIM 记录及 Photoshop 资源保护不替代独立 ExifTool、像素、生产控件与最终 EXE 原生证据。日期宿主不重建，工具与运行库复用；[支持边界](IPTC-FIELDS.md)。

## 2026-10-13 · R03b

R03b复用既有ExifTool／PhotoDocument／MetadataCopy及原日期宿主；无新增依赖。UiChecks增加 --inplace-checks、--inplace-scale、--inplace-fault-checks、--inplace-restart-checks；故障检查必须使用隔离副本构建，生产源没有注入入口。事务内同字节写取得NTFS隔离锁，句柄中重新验证身份／SHA，再MoveFileTransacted提交。TxF为微软不推荐且未来可能不可用的API；不可用时拒绝写回，没有关闭保护的回退。只支持已实测固定本地NTFS普通继承ACL；自定义ACL、ADS、硬链接、重解析点、网络卷、EFS／压缩／稀疏边界拒绝。并发ACL变化、真实断电／磁盘耗尽未验；不宣称跨日志与目标的断电原子性。备份及JSONL阶段记录Flush(true)，恢复先保留当前版本，实际回读与UI接纳后才完成。测试隔离环境使用PHOTOTRAIL_INPLACE_HISTORY；日用默认LocalAppData/PhotoTrail/Windows/InplaceHistory。1／20／100按原样候选记录备份／暂存／提交／回读／界面接纳／恢复阶段与请求数，不套用Mac并发常量。

[Microsoft TxF documentation](https://learn.microsoft.com/en-us/windows/win32/fileio/transactional-ntfs-portal) · [Programming considerations](https://learn.microsoft.com/en-us/windows/win32/fileio/programming-considerations-for-transacted-fileio-)

## R03a 保存验证

生产保存计划位于 `PhotoTrail.Windows/SavePlan.cs` 与 `MainWindow.Save.cs`，复用 MetadataXmp／MetadataCopy／PhotoDocument 和 date-core-v2；不增加 SDK／组件／系统环境要求。UiChecks 的 `--save-target-checks` 使用独立临时副本覆盖模式、范围、真实配对、完整XMP、竞态、锁、权限失败、创建后取消／回读故障、revision及生产WPF链；`--save-target-scale` 观测1／20／100张请求数、阶段耗时和Dispatcher间隔。临时权限注入只改任务目录并finally恢复；注入证据与无钩子的原生候选流程分别归属。最终候选检查需逐字节使用候选生产DLL，不以早期构建代替。

旧副本入口现在先摘要再显式确认，因此生产交互检查中的 SaveCopies 之后须检查摘要，再执行 ExecuteSavePlan；不能跳过摘要或据旧单事件测试断言假失败。无关历史全套不机械重跑。

## 2026-10-13 · 检查器 R02 的读取与验证

生产编辑／日期／保存仍使用原 `-G1` 键；展示另用 `-j -G1:4 -a -u -s -n`，保留来源角色、家族及Copy身份，严格核对SourceFile和批量数量。每32张最多64个物理来源各用一次普通读取与一次展示读取，日期文本仍整批进入v2；getter和计数不启动工具。参数依据[ExifTool官方文档](https://exiftool.org/exiftool_pod2.html)。

模型入口：`dotnet run --project apps/windows/PhotoTrail.Windows.Tests -c Release -- --inspector-checks`；`--inspector-read-checks`仅合成工具响应身份故障；既有`--settings-checks`覆盖受影响设置回归。生产WPF入口位于`DateHost/UiChecks`，使用`--inspector-flow-checks`、`--inspector-late-checks`、`--inspector-empty-restart-checks`和`--inspector-scale-checks`，输入应是四种来源的合成副本，所有偏好／历史／库／输出／WebView目录隔离。Scale使用`PHOTOTRAIL_R02_COUNT=1/20/100`；记录普通／展示ExifTool请求、日期宿主请求、实际导入／刷新耗时和Dispatcher观测范围。重启检查复用同一隔离设置文件。测试钩子、早期构建、最终候选和原生输入证据分别记录，断言数不替代场景归属。

候选仍为Release win-x64、.NET 10框架依赖形式，内嵌确切公开提交。DateHost及运行库从已验收v2组合按原字节复用，逐文件核对，不重编共享源或改变来源锁／协议。SDK部署、许可／NOTICE和SwiftPM／14001不因此销项。

## 2026-10-13 · date-core-v2 投影接入

来源锁为 a0299e6f6c956f66ace2b85449b54db5e2eeeee4，MetadataDateEdit.swift 完整SHA 15e1f395ac379552b4c43892f6d70321e3c2f0fd6e0dc9d8ccadacc7bb607dc8（177行）。原146行算法前缀SHA593fa443…不是完整新源SHA。工具链保持6.4.0。Build.ps1固定Git原字节→完整SHA→BuildIdentity→真实Host→运行库复制，不从工作树或私有副本回退。

Checks/ProjectionChecks.cs与原Caller共同覆盖固定38投影和35旧日期向量、project独占形态、整数词法、原文／偏移／纳秒一致、未知／重复字段、版本及来源错配、资源、取消与子进程收尾。运行前从固定公开对象导出date-projection-v2.json到DateHost/evidence，PHOTOTRAIL_DATE_CORE_FIXTURE指向原date-core-v1.json；PHOTOTRAIL_PROJECTION_OLD_HOST仅检查旧R01b真实宿主。生成fixture和结果不入Git。

UiChecks --projection-workflow-checks使用8份合成XMP和历史GPX，实际生产窗口检查双向排序缺失置后、1ns稳定排序、编辑／撤销刷新、历史边界筛选／冻结／不覆盖改名与恢复、共享instant轨迹预览／应用／撤销／副本回读和三种平台拒绝。复用R01b入口／五模式／保护／库／迟到；ComputeCancelChecks --auto --r01b-csv现实际走project，两个被动观测点证明首项已算、进程存活且stdout未完成。全部偏好、库、历史、WebView和输出必须隔离。事件检查不是原生鼠标或用户验收。

日期验证批次改为project同批校验和投影，证明绑定精确原文和现有请求快照；getter不启动宿主。日期页五模式返回values后，在同一冻结任务提交前对变化值补一次去重project；阶段计时包含两类请求。不新增缓存／服务／依赖，不改轨迹ISO解析或插值。三项部署门仍未闭合，旧段落按发生时点保留。

## 2026-10-12 方案库定向检查（任务20261011）

DateHost/UiChecks增加`--scheme-model-checks`及`--scheme-library-checks`，分别检查初始化、严格格式／原子保存／旧状态冲突，以及真实生产WPF五模板、JPG/RAW/XMP配对、示例编辑、当前日期草稿、冻结执行恢复。运行时必须隔离`PHOTOTRAIL_RENAME_SCHEMES`，同时隔离既有偏好、执行记录与WebView；仅使用合成副本。方案JSON及旧规则兼容见[格式](RENAME-SCHEMES.md)。DateHost复用固定二进制，不重编Swift。

原生管理及系统导入／导出、重启和双实例检查与Dispatcher检查分开记录构建身份。复用日期直接应用／撤销、批量轨迹匹配和重命名排序／部分失败／恢复相称回归；不运行无关历史全套、干净部署或性能基准。

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

## 2026-10-11 · 缺失时间偏移定向检查

配置既有PHOTOTRAIL_EXIFTOOL和独立PHOTOTRAIL_TEST_OUTPUT后运行：

```powershell
dotnet run --project PhotoTrail.Windows.Tests -- --offset-skip-checks
```

仅合成XMP与副本：混合/中间缺失、全部缺失、六组件顺序、草稿优先和清除、非法日期/类型、读取失败、来源变化、失效和取消，以及副本回读/原件哈希。WPF控件定向入口为DateHost/UiChecks，参数“合成目录 --offset-skip-checks”；目录初始仅三份sample-0/1/2.xmp，中间缺失，两侧分别带九位亚秒-00:00和一位亚秒+08:00。它验证生产控件、草稿及保存链，不执行其他历史模式或压力/宿主替换检查。Computer Use实际点击观察及用户验收分别记录；不以自动检查代替用户验收。

## 2026-10-11 · 真实宿主计算中取消验证

定向入口：[ComputeCancelChecks](../DateHost/ComputeCancelChecks/README.md)。独立检查工程仅增加真实stderr计算标记、stdout任务状态与进程收尾观测；生产源码、固定Swift候选、宿主和协议不变。合法3000条独立六组件偏移使用真实首项计算完成标记，不能用全局序列的事后标记代替。适配器立即取消和实际WPF按钮Click事件取消分别验证；后者由标记触发，是真实控件事件，不是鼠标或用户亲自操作。新预览在旧请求收尾前启动，验证无部分草稿、失效按钮、旧结果不覆盖新结果、草稿/源保护和进程退出。

Computer Use鼠标操作另记；若截图往返后才取消，明确不计计算阶段通过。不重跑全部历史检查，不打包新候选或扩展干净部署。原始证据仅本机，用户接受状态由独立Windows交接记录维护。

## 设置偏好定向检查

在apps/windows运行 `dotnet run --project PhotoTrail.Windows.Tests -- --settings-checks` 与 `node PhotoTrail.Windows.Tests/google-page-checks.cjs`。前者覆盖默认、独立设置、损坏／未知比较器回退和历史边界；后者使用本地SDK替身检查生产Google页面消息，不调用真实服务。

DateHost/UiChecks的定向参数为“合成目录 --settings-checks”及“同目录 --settings-restore-checks”；仅使用合成XMP、PNG与副本，验证生产WPF控件、排序选择／冻结计划、日期草稿、副本回读和源保护。设置独立PHOTOTRAIL_SETTINGS_FILE、PHOTOTRAIL_SEARCH_HISTORY_FILE、PHOTOTRAIL_THEME_FILE及WEBVIEW2_USER_DATA_FOLDER，避免写入日常偏好。检查工程的Google页面替身仅位于自身输出并恢复，不改变候选页面。模型与控件检查、Computer Use操作及用户验收分别记录。

本机偏好位于LocalApplicationData/PhotoTrail/Windows的settings-v1.json与map-searches-v1.json；有界读取、原子替换，不含密钥。损坏设置回退默认，损坏历史保留并提示。多个独立应用实例同时保存设置时最后写入者优先；本批不提供跨实例合并。

## 重命名顺序与筛选定向检查

在apps/windows运行 `dotnet run --project PhotoTrail.Windows.Tests -- --rename-order-checks`；可设PHOTOTRAIL_RENAME_CONTRACT_FIXTURE为已核对的固定settings-track-rename-v1.json，复用三项重命名共同合成案例。`--rename-preset-checks`及`--rename-execution-checks`复用旧方案与执行／日志／取消／冲突／恢复边界。

DateHost/UiChecks参数“独立样本目录 --rename-order-checks”运行生产WPF组、筛选、编号、冻结、执行／回读／恢复和设置／日期草稿回归。样本为a/b/c/d.jpg及各自XMP，另有a.dng副本；a/c/d旁车有标题，b旁车无标题，RAW设备与JPEG不同。新增非法b.nef仅检查内容类型拒绝；e.xmp在嵌套目录用于追加检查。仅使用可丢弃样本。取消和并发目标冲突由真实RenameExecutor进度触发，实际输出送入生产上下文重读及恢复入口，单独记录，不能称为鼠标执行中取消。鼠标拖放、放下回调及实际顺序和Alt／Ctrl快捷键另由Computer Use核对，模型断言不替代。

设PHOTOTRAIL_RENAME_HISTORY隔离执行记录，同时隔离既有PHOTOTRAIL_SETTINGS_FILE、PHOTOTRAIL_SEARCH_HISTORY_FILE、PHOTOTRAIL_THEME_FILE与WEBVIEW2_USER_DATA_FOLDER；ExifTool仍用现有原生完整目录。复用固定DateHost，不编译共享Swift。原始日志、照片、执行记录、缓存及二进制留本机，不纳入公开源码。NU1900资料读取告警、其他DPI／性能与干净部署继续单独记录。


## 批量缺值定向检查（2026-10-11）

`dotnet run --project PhotoTrail.Windows.Tests -- --batch-missing-checks`复用Mode0检查并覆盖Mode2参数、类型、净变化、草稿、来源、重复目标、序列和均分位置。PHOTOTRAIL_TEST_OUTPUT下mac-fixtures/a.xmp、missing.xmp、c.xmp按确切Mac返还包读取；哈希／对应预期在私有交接，不上传私人素材。输出每次新建，拒绝覆盖副本。

`DateHost/UiChecks`参数“独立三XMP目录 --batch-missing-checks”操作生产WPF预览、应用及保存入口，检查全选择保护、参数／选择／草稿变化、内存类型变化、取消与新请求、设置持久化和重命名冻结身份。另由Computer Use鼠标操作混合／全部缺失／同值按钮提示；不能把检查计数当作计算阶段取消证明。复用固定DateHost和完整ExifTool，隔离已有偏好／缓存／重命名记录变量。没有重跑全部历史检查、计算阶段时机或干净部署。


## 轨迹调整定向检查（2026-10-11）

`dotnet run --project PhotoTrail.Windows.Tests -- --track-adjustment-checks`检查批准公式与边界、亚秒、无时间、分段、快照兼容／损坏／保存失败、来源保护、GPX/KML/KMZ另存回读；另有临时文件实际写入字节后的取消清理证明，不是性能基准。PHOTOTRAIL_TEST_OUTPUT须为独立输出目录，PHOTOTRAIL_TRACK_CONTRACT_FIXTURE指向从固定公开73c0640bca4d1a2919aa3a466487a5cb20c7f28d按Git对象取得的docs/fixtures/settings-track-rename-v1.json；不合并Mac分支。

DateHost/UiChecks参数“独立样本目录 --track-adjustment-checks”操作生产WPF：三合成XMP与source.gpx（2段、3+1点、一个无时间点），进行预览／应用／地图消息／匹配、撤销／恢复、GPX导出、实际持久化替换失败和来源失联，复用日期、设置和重命名冻结。地图采用既有Google页面的本地SDK替代，仅测试生产消息和缓存／取景控制，不宣称在线Google通过。再次启动同目录加--track-restore-checks验证启动恢复、重新导入保持调整、显式恢复与会话撤销不跨进程。

PHOTOTRAIL_TRACK_HISTORY隔离旧路径历史；快照位于同一路径加.adjustments-v1.json。同时隔离已有设置、搜索历史、外观、重命名记录及WebView目录。DateHost二进制复用，不编译Swift或改日期协议。Computer Use鼠标及现有OpenFreeMap真实加载单独验证；截图显示于对话，不以模型断言代替。完整日志、轨迹／照片、缓存和二进制仅本机。未重跑全部历史、性能或干净部署。

## 2026-10-11 批量直接应用定向检查

`DateHost/UiChecks`构建后使用独立合成输入与隔离偏好：`--batch-direct-checks`（3个带日期／缺失／带日期XMP，文件名含日期捕获）、`--batch-late-checks`、`--batch-cancel-checks`（530张，旧日期草稿由检查器构造）、`--batch-performance-checks`（1/100/530，530三轮；可加`--offset`）、`--field-performance-checks`（普通字段及CSV）。`--offset-skip-checks`／`--batch-missing-checks`已改为一次应用的缺值检查；旧逐照片预览GUI检查退役，日期核心／适配边界检查仍保留。`--track-late-failure-checks`检查实际来源失败不清后来定位。

性能以Stopwatch分计算、终态全源复核、UI提交／刷新，并记录ExifTool／DateHost请求数；Dispatcher ApplicationIdle与25ms轮询是观察成本，不能冒充鼠标点击到首帧。源码保留内部阶段计时及既有宿主诊断，不更改协议。比较基线仅加计时，完整日志及530输入留本机，公开不写私人路径／数据。核对1/100/530源SHA、显式小副本保存回读；不以断言数量代替实际宿主计算开始／子进程存活／请求收尾证据。

## 2026-10-11 多照片轨迹匹配定向检查

现有DateHost/UiChecks入口新增 `--track-batch-checks`（三张合成XMP及两条一致轨迹）、`--track-batch-performance`（530张独立JPEG副本、两条500点轨迹；1/100各一轮、530三轮）、`--track-batch-cancel`（530张、10万点合法真实GPX）。隔离既有PHOTOTRAIL偏好及WebView路径；ExifTool仅导入／保存需要，匹配阶段不调用ExifTool或DateHost。保留单后台请求内不可变轨迹快照，不跨请求缓存、不重写匹配算法。

Stopwatch记录匹配、预览全来源复核、应用全来源复核、UI草稿提交与同步列表刷新；端到端计时包含25ms检查轮询及Dispatcher ApplicationIdle观察，不等于鼠标到首帧。取消检查记录真实worker开始／取消／结束与已完成数量，取消发生在一张已完成且整批未完成时；不是启动前取消、假轨迹或延时。迟到检查仅持有真实来源复核的UI续体，保留生产读锁，用另一有效轨迹建立新请求；与原生鼠标证据分开。

复用既有轨迹调整检查和单张迟到失败检查，覆盖日期直接应用、最近一次撤销、设置与重命名冻结身份；不跑历史全套。原生操作验证计算→成功地图查看→未成功复核→应用→撤销，实际OpenFreeMap加载单列；Google在线条件不作通过。完整日志、规模输入和二进制留本机，上传仅审查后的摘要与纯合成小样。

## 有序预设定向验证

在apps/windows目录运行 `dotnet run --project PhotoTrail.Windows.Tests -- --preset-checks`：覆盖有序重复目标、当前值、类型、JSON以及静态新旧fixture往返。`DateHost/UiChecks`的 `--ordered-preset-checks` 与 `--ordered-copy-checks` 分别在真实生产WPF控件／Dispatcher上验证整批终态与规模、显式副本保存和ExifTool回读；必须提供独立证据输出及合成输入，配置、照片副本和完整日志仅保留本机。测试检查程序位于DateHost/UiChecks，不重编固定DateHost宿主。原生鼠标／键盘与系统文件对话框另行记录，不能以模型或WPF事件检查替代。

## 元数据预设库定向检查

模型：`dotnet run --project PhotoTrail.Windows.Tests -- --preset-library-checks`；受影响JSON／动作回归为 `--preset-checks`。生产 `DateHost/UiChecks` 新增 `--preset-library-checks`、`--library-restore-checks`（同库新进程）及 `--library-terminal-checks`（三合成XMP）。`--ordered-copy-checks`现从独立库保存／载入，再应用、撤销、保存JPEG／已有RAW旁车／XMP副本并回读。恢复工程的输出目录须无可导入照片；ExifTool须完整配置。

所有检查必须设置独立 `PHOTOTRAIL_METADATA_PRESETS`，同时隔离已有重命名库、设置、搜索／轨迹历史、外观、执行记录及WebView路径。库文件上限1MiB／256项，单条仍128KiB／27操作。损坏／写失败在受控路径验证，不接触用户库。真实双进程和原生确认／系统对话框另记录，不能以模型模拟替代。最终候选DLL的生产检查记录实际SHA；固定DateHost复用，不编译Swift。未重跑性能、日期计算阶段取消、地图或部署。

## R01a · 正式日期来源接入

固定算法来源改为公开63fb9404ec5f0862df90a000f5dd1c4b81509900的Packages/PhotoTrailDateCore/Sources/PhotoTrailDateCore/MetadataDateEdit.swift，原字节SHA593fa443f634234b81308143d96b0e6bc0373782734d6ba85a69b90c4d153ccc保持。只同步锁与生产Source期望，不迁移其他日期入口，不改date-isolated-v1或工具链6.4.0。Build.ps1保持原固定Git导出／SHA校验／嵌入身份链。缺对象、旧类型别名路径及错误SHA必须拒绝；新旧宿主与期望两向错配必须拒绝，不按SHA相同放行。

共同35向量由[固定Mac来源fixture](https://github.com/LittleSixNine/PhotoTrail/blob/63fb9404ec5f0862df90a000f5dd1c4b81509900/Packages/PhotoTrailDateCore/Tests/PhotoTrailDateCoreTests/Fixtures/date-core-v1.json)取得，只给检查器设置PHOTOTRAIL_DATE_CORE_FIXTURE；PHOTOTRAIL_DATE_CORE_OLD_HOST只在检查中指旧宿主。19预期／16观察分别记录；不把fixture当传输请求，不改历史兼容向量。运行现有Caller后保存具体结果和构建SHA。纯包测试从同一Git对象完整导出到独立目录再swift test；SwiftPM或环境错误须原样记录，直接单文件检查不等于纯包通过。

生产UiChecks新增--date-core-copy-checks（四输入：JPEG、已有DNG旁车、XMP及旁车本身，选择前三目标排除DNG旁车的重复目的）、--date-core-scale-checks（PHOTOTRAIL_R01_COUNT=1/20/100，读取沿32文件批次）、--date-core-mismatch-checks（PHOTOTRAIL_R01_WRONG_HOST指另一个真实来源宿主，仅暂换检查器自身输出后恢复）。五模式应用／统计／完整撤销／再应用／显式副本／ExifTool回读、源与旁车／像素／其他语言保护均记录。1/20/100阶段读取测量是独立等规模ExifTool重读，应用／来源复核／提交／保存／核对各自计时，不冒称端到端鼠标响应或Mac性能门槛。

ComputeCancelChecks复用真实标记与两个被动观测点，改用现有直接应用／取消按钮；先证明进程存活且完整stdout未到达，再取消、终态保留完整草稿、新请求和完整撤销。迟到／选择／草稿／来源／保存进行中失效沿现有--batch-direct-checks与--batch-late-checks，不恢复退役预览UI。旧整批检查把自身测试链保存到隔离库后退出，生产退出保护保持。

所有偏好、库、轨迹／重命名记录、WebView目录及输出必须隔离；只用公开固定对象／合成副本。不替换旧已验收入口。框架依赖.NET10 Desktop与WebView2，包内DateHost运行库须逐文件核对来源／版本／SHA及许可。移除进程PATH仅补充隔离，不代替真实无Swift SDK机器；缺环境／许可／漏洞资料记未验，不能写完整验收或正式发布。

## R01b · 现有日期入口共享验证

四个既有XMP日期字段（DateTimeOriginal、DateTimeDigitized、CreateDate、ModifyDate）的设置、CSV、字段剪贴板、XMP导入与含草稿导出、固定日期设置／补空及自身字段复制均先批量调用固定共享核心normalize。日期参数不Trim、不补UTC，1～9位分数秒及Z／显式偏移（含-00:00）保持原文本。清除不送normalize；未触及的无效原值保持，无关标题等编辑不被阻止。GPSDateTime仍只支持清除。

共享核心采用已有历史历法，1582-10-05至14拒绝，1500-02-29可接受。date-set／date-prefix仅从已验证文本取到秒生成名称，不回写原日期。照片和重命名排序、轨迹匹配均消费请求内校验结果；无偏移不成为绝对时刻，亚100ns精度不舍入为匹配时刻。

**未完成：**当前date-isolated-v1不返回历史历法时间投影。1582-10-15以前的共享合法日期可设置、保存及生成名称，但照片日期排序、重命名日期排序／筛选和轨迹匹配投影不支持；不得当作无效日期或用旧C#历法回退。最小共同接口需由共享核心提供历法投影、偏移存在性及整数秒／纳秒。本批不修改协议。现代日期在共享校验后使用平台时间表示适配。

启动只恢复预设库列表。含共享规则拒绝日期的旧记录保留；实际载入、应用及保存新日期参数拒绝且保持旧编辑／库。操作链每个实际日期接收值（包括随后被覆盖的中间值）都参加验证，固定非法补空参数不因无净变化跳过。

整个请求计算、校验、全部来源与旁车／草稿revision／选择／参数／任务状态复核通过后一次发布；任一宿主或协议失败无部分草稿，无独立算法回退。副本保存先整批校验日期草稿，后按既有逐文件结果执行。公开API日期设置改用SetDraftAsync；同步SetDraft只接受清除及非日期，预设日期用ApplyAsync，结构Decode／ValidateChanges不代替共享合法性。

R01b已实现上述范围并定向验证，待用户验收；历史投影未完成。无SDK环境部署未验、运行库再分发许可不足、Windows SwiftPM包测试失败仍保留，候选不是正式分发包。不增加计算型日期预设、EXIF/IPTC或文件时间写入。

验证：模型 --date-checks、--rename-order-checks；真实生产WPF --r01b-entry-checks、--r01b-protection-checks、--r01b-library-checks、--r01b-rename-checks、--r01b-fault-checks、--r01b-scale-checks，日期页 --date-core-copy-checks，迟到 --batch-late-checks（PHOTOTRAIL_R01B_LATE=1检查新入口）；ComputeCancelChecks --auto --r01b-csv使用两处被动阶段观测。原样候选DLL与专用检查构建归属必须分开。

## R04a 字段与日期验证入口

`DateHost/UiChecks` 新增 `--r04a-checks` 与 `--r04a-scale`；使用现有生产WPF控件和独立合成目录，须设置全部本机偏好及原位／改名历史环境变量到测试目录。规模入口读取 `PHOTOTRAIL_R02_COUNT` 为1、20、100，记录编辑／投影、代表JPEG副本、ExifTool／DateHost请求和最大Dispatcher间隔。ExifTool读取使用JSONQ和明确UTF-8，不把数字形序列号转换成数值；EXIF布局改变需比较缩略图实际载荷。三组日期实际九标签逐项回读；冻结摘要列出组件。测试失败快照与完整日志留来源机，不进入Git。固定共享源及DateHost38文件组合不变，不安装SDK或修改全局环境。


R08a：Tests --r08a-rule-checks与UiChecks --r08a-checks分别验证规则/属性模型和实际WPF。最终候选需绑定最终DLL并原生验证；Unicode16来源及包内Unicode-LICENSE.txt不代替R14全许可门。
