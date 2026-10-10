# Windows日期页宿主

仅Windows日期页的偏移、序列、原子组件替换、均分、文件名提取后校验使用此宿主。其他日期入口保留既有C#路径。Mac不需改代码；这不是共同正式协议或正式分发包。

## 固定来源与构建

source-lock.json固定公开Git对象3593051e21e3af2c060a061aeaa888dee24c3bb4中的Packages/ImageData/Sources/ImageData/MetadataDateEdit.swift，SHA256为593fa443f634234b81308143d96b0e6bc0373782734d6ba85a69b90c4d153ccc。

在apps/windows、使用PowerShell7和**已有**Swift6.4.0 Windows x64工具链、MSVC/Windows SDK、.NET10 SDK：

```powershell
pwsh -NoProfile -File DateHost/Build.ps1 -SwiftRoot 'C:\BuildTools\PhotoTrailSwift64'
dotnet build PhotoTrail.Windows
```

SwiftRoot按已有安装位置指定。脚本只从公开仓库固定对象按原始字节导出到DateHost/.cache并核对hash，生成构建身份，编译候选加Host/Host.swift；不编译整个ImageData，不依赖私有目录、移动HEAD或工作树候选。缺对象/hash错误就失败，不自动fetch、安装或回退。生成DateHost/bin后WPF构建会复制宿主和运行库到应用输出的DateHost目录。缓存、二进制和结果不进Git；原候选没有修改。

## Windows适配协议

一批一个进程，UTF-8无BOM stdin完整JSON后关闭，stdout一个完整JSON响应，stderr仅非敏感诊断。版本date-isolated-v1沿用实验协议，未升级为共同接口。

请求`{version,id,items:[{id,op,text,...}]}`；返回`{version,source:{commit,path,sha256},id,results:[{id,values或error:{scope,code}}],computeMs,jobError可选}`。source来自校验后的编译配置，C#核对固定身份/版本/请求ID/结果数量与顺序；拒绝缺项、重复、多项、坏响应。根和item未知成员均拒绝。

normalize、offset（六单位）、shift（固定秒）、calendarDays（地区日历天）、replace、replaceAtomic、sequence、distribute可用于协议检查；UI只接入本轮五模式，不新增日历天入口。原子替换仅构造一次最终完整文本并由候选验证，保留未指定组件/亚秒/偏移。完整日期文本拒绝CR/LF且不Trim；候选采用历史历法：1582-10-05至14拒绝，10月4日+86400秒到15日，1500闰日可接受。无偏移保持墙上时间，文本不经C#DateTime/epoch/Double转换。

传输整数为Int64且拒绝小数、指数或溢出；UI原int/long输入范围和偏移边界保持不变。本端默认每进程30秒、3000结果、请求/响应各1MiB、诊断64KiB；这是适配资源限制，不是共同产品规则。独立项可分批，完整汇总与revision核对后才返回；任一传输失败不发布部分结果。序列/均分一项全局生成，不分页；超限拒绝。业务invalidDate/invalidSequence/missingDate与参数、资源、版本、进程故障分别返回；明确读取失败不当作missingDate。无旧算法回退。

## 检查

```powershell
# 168条隔离断言（既有167 + item未知成员拒绝），全部合成输入。
New-Item -ItemType Directory -Force DateHost/evidence | Out-Null
dotnet DateHost/caller-bin/Caller.dll (Resolve-Path DateHost).Path
# 原C#日期路径保持；已配置ExifTool及私有输出后验证五模式草稿/副本。
dotnet run --project PhotoTrail.Windows.Tests -- --date-checks
dotnet run --project PhotoTrail.Windows.Tests -- --date-page-checks
```

UiChecks使用实际生产MainWindow、真实控件、Dispatcher与事件，不替换UI逻辑；仅合成XMP。PHOTOTRAIL_EXIFTOOL指已有完整工具，PHOTOTRAIL_DATE_CHECKER指本目录caller-bin，PHOTOTRAIL_THEME_FILE/WEBVIEW2_USER_DATA_FOLDER指独立测试位置。运行`dotnet run --project DateHost/UiChecks -- 合成目录`：目录初始只含四个20240229_123456-编号.xmp文件（来源日期2024:02:29 12:34:56，分别带.123456789Z、.1+00:00、.123-00:00、无后缀），无既有输出；自行生成副本/压力文件/结果，并关闭窗口。它临时替换自身输出目录宿主以测试缺失/损坏/超时，在finally恢复；不能指向用户正在运行的应用输出。

真实WPF检查结果和完整日志留私有目录。1/100/3000压力选择使用真实选择控件及从已验证合成源复制文件构造的测试记录，未宣称3000逐文件UI导入或副本保存性能。干净部署、运行库许可和分发继续待验；不新增系统安装。
