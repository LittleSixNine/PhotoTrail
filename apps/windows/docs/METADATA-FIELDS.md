# 元数据字段、来源与成组日期 · R04a

R04a 已由用户接受 Windows 代理交付，当前 R04b 增量见 [IPTC 支持与编码](IPTC-FIELDS.md)。R03b 已由用户接受 Windows 代理交付；保留原风险和未验项目。固定产品参考为 Mac `73c0640bca4d1a2919aa3a466487a5cb20c7f28d`，固定日期组合仍为 `a0299e6f6c956f66ace2b85449b54db5e2eeeee4`／date-core-v2／Swift 6.4.0。

## 字段与输入

XMP Creator／Subject 使用列表，每行一项；一个元素内部有换行或以 `[` 开头时使用 JSON 字符串数组，例如 `["a,b","line1\nline2"]`。逗号不分隔元素。载入只展示，不自动勾选或改变原值。Title／Description／Rights 只改 x-default，保留其他语言。评分、曝光程序和白平衡有可输入原始值的下拉控件，未知值显示原文；设置仍按原范围校验。设备、镜头支持精确来源和自定义文字，没有联网机型目录。

新增 EXIF 文字仅包含 `IFD0:Artist`、`ImageDescription`、`Copyright`、`Software` 与 `ExifIFD:UserComment`。设备仅包含 `IFD0:Make`、`Model` 与 `ExifIFD:SerialNumber`、`LensMake`、`LensModel`、`LensSerialNumber`。它们与 XMP 同义字段独立，设置或清除不会同步另一来源。读取用 ExifTool JSONQ 保留数字形文字；新文字通过 UTF-8 值文件传递，UserComment 使用 ExifTool Unicode 编码并实际回读。保留现有每值 8192 字符、合法 UTF-8、无 NUL 的边界；非法或工具无法完整回读的文字拒绝交付，不截断。

检查器显示来源、完整技术标签、缺失／混合／未读／失败或过期状态。编辑区显示真实来源资格，混合值不自动应用；勾选并留空是明确清除。真正重复同 family 实例不可编辑，CopyN 参考行仍只读；不同 family 的同名 EXIF／XMP 字段不会相互授权或同步。来源读取失败不当作缺失。

## 主时间及三组 EXIF 日期

|逻辑目标|主时间|亚秒|UTC 偏移|
|---|---|---|---|
|Composite:SubSecDateTimeOriginal|ExifIFD:DateTimeOriginal|ExifIFD:SubSecTimeOriginal|ExifIFD:OffsetTimeOriginal|
|Composite:SubSecCreateDate|ExifIFD:CreateDate|ExifIFD:SubSecTimeDigitized|ExifIFD:OffsetTimeDigitized|
|Composite:SubSecModifyDate|IFD0:ModifyDate|ExifIFD:SubSecTime|ExifIFD:OffsetTime|

每组是一个逻辑草稿；底层组件不作为任意可写标签开放。日期格式为 `yyyy:MM:dd HH:mm:ss`，可附小数秒及 `Z`／`±hh:mm`。日期页可明确选择主时间、三组EXIF或四个XMP日期；不适用来源整批拒绝。所有设置、日期页五模式、CSV、剪贴板和固定日期预设均经固定 Swift v2 校验，不用 C# DateTime 改历法或舍入纳秒。读值先用组合标签，再用对应主标签及伴随组件。无亚秒／偏移的新值显式移除旧伴随标签，清除删除整组；`Z` 在 EXIF 偏移标签中存为等价 `+00:00`，不补缺失时区。

无旁车 JPEG 的主时间为 EXIF 拍摄组合；已有旁车、明确新旁车编辑及独立 XMP 的主时间为 `XMP-xmp:CreateDate`。其余三个 XMP 日期、EXIF 数字化／修改时间各自独立。主日期草稿即时投影到列表排序、地图时间、轨迹匹配和重命名日期排序／筛选／名称。清除或旁车主时间缺失后不回退其他 XMP 日期或原图旧日期，保存重开也保持缺失。配对重命名成员消费同一主时间。其他格式保留原来源规则，不扩大为全格式 EXIF 写入。

无偏移、亚 100ns 精度或超出平台时刻范围时，轨迹消费者按现有限制拒绝无损适配，不猜 UTC、不舍入。日期读取和投影缓存只在异步入口准备，逐 getter 不启动进程。本批不增加照片 GPX 导出、复合日期动作或跨来源复制编排。

## 格式与保存支持

|实际来源|可读|本批可编辑|图内副本|旁车副本|新旁车|原位|
|---|---|---|---|---|---|---|
|JPEG 无旁车|EXIF／XMP 独立来源|既有 XMP＋新增精确 EXIF／三日期组|JPEG|无|明确切换后仅 XMP|已验 JPEG，强制备份|
|JPEG＋已有 XMP|原图 EXIF、实际旁车 XMP|仅旁车 XMP，EXIF 参考只读|原图不改|图像＋XMP 副本|拒绝已有目标|实际 XMP；原图 SHA 保持|
|DNG 无旁车|保持读取|仅明确新旁车的 XMP|拒绝|无|既有 R03a 资格|拒绝图内|
|DNG＋已有 XMP|原图及旁车|仅 XMP|原图不改|图像＋XMP 副本|拒绝已有目标|既有 R03b XMP 目标|
|独立 XMP|XMP|仅 XMP|不适用|独立 XMP 副本|拒绝为自身建旁车|该 XMP|
|其他现有可读来源|保持原资格|既有旁车支持范围|不扩大|保持已验／未验归属|不扩大|不扩大|

默认副本、旧所选 Ctrl+S、全库／工作区字段范围不变。EXIF 草稿绑定图内目标，不能切到新旁车；混合不适用来源的操作整批拒绝，不部分导入。冻结摘要列出逻辑日期及其三个实际组件。副本成功保留原会话草稿；原位经过强制完整备份、同卷暂存、真实目标回读、持久阶段、UI 接纳和按记录恢复。恢复版本 1 及旧 JSON 继续可读；未知 JSON 版本、标签或非法值拒绝，CSV 未开放标签整批拒绝。XMP 导入只合并已存在的开放 XMP 字段，不导入 EXIF；未支持 XML 字段明确列为忽略。

新 EXIF 写入会重建 EXIF 布局，缩略图偏移可变化；必须比较缩略图实际字节、主图像素、完整读取的全部已有非目标来源实例（含重复 family 与未知标签）及 XMP 其他语言，不能把指针重定位当作内容变化，也不能以此略过内容保护。旁车写入仍核对原图完整 SHA。保存后只清已证明字段，残余草稿复核旧基准；旧撤销和冻结证明失效。

## 未开放与限制

EXIF 数值／枚举、方向／分辨率、IPTC 时间及文件系统时间留 R04c；IPTC 十二项文字／列表与编码见本批支持表；MakerNotes 和非白名单只读。现有五个 XMP 地区字段与 GPS 能力保留，不称为 IPTC。

GPS 清空回退缺口继续拒绝；TxF 不可用时安全拒绝，无未保护替换回退。原历史损坏／未知／未完成记录仍阻止盲写，不因新字段变为零事务。无 SDK 部署、许可 NOTICE、SwiftPM 14001 三门及真实断电／耗尽、广泛外部软件、并发 ACL、DPI／语言／辅助技术等原未验保留。R03b r2 的 3.82 秒 Dispatcher 间隔不改标为 R04a 实测；R04a 性能另附候选证据。
