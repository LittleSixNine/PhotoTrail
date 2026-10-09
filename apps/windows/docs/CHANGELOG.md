# PhotoTrail Windows

## 2026-10-09 · Windows GPX核心（本地开发）

- 新增Windows本地GPX读取与保守时间匹配核心，复用既有轨迹约定；29项检查含Mac既有样本通过，WPF构建无警告／错误。
- 阶段2三种导入入口经用户实际确认，不可写输出4项检查通过。本机阶段2验收完成；显示缩放及干净机器依赖仍待验。
- GPX核心尚未接入界面；KML/KMZ、地图轨迹图层和GPS草稿写入仍待开发。未更新或发布Windows候选包。

The Windows GPX reader and conservative matcher passed 29 core checks, including existing Mac fixtures. Stage 2 local acceptance passed after user import validation and four unwritable-output checks. GPX UI integration, KML/KMZ and GPS draft writing remain pending. No new Windows package has been released.

## 2026-10-09 · Windows 原型（本地开发）

- 新增独立 WPF／WebView2 工程、OpenFreeMap＋MapLibre 坐标预览、照片读取、五项 XMP 草稿和保存副本入口。
- JPEG 与已有 XMP 旁车保存经过回读、原图哈希及像素载荷核验；失败／取消保留草稿，同名目标拒绝覆盖。
- 本地自动检查 38 项通过，真实界面单张编辑、保存及撤销已验证。批量部分失败、撤销、退出保护和移除已实机验证；文件对话框、拖入、不可写输出及不同 DPI 验收仍待完成；未发布 Windows 安装包。

An independent Windows prototype adds read/import, five-field XMP drafts, verified copy-only saving and map-point preview. 38 automated checks and a single-photo UI save/undo flow passed locally. Batch partial failure, undo, exit protection and removal passed UI validation; file-dialog, drag/drop, unwritable output and DPI checks remain pending; no Windows package has been released.

## 2026-10-09 · 轨迹图层与GPS副本增量

- GPX/KML/KMZ读取、轨迹切换/移除、时间匹配预览及照片标记共享选择已接入Windows界面。
- 位置可加入XMP GPS草稿，经共用入口保存副本；支持经纬度符号、已知海拔和未知海拔清理，原文件/EXIF/IPTC保留。
- 24项KML/KMZ/图层检查、56项元数据/GPS检查通过；独立实机GPS保存回读及标记选择通过，构建无警告/错误。
- 当前增量不改变Mac路径；Google/地区解析、拖动定位、断网/重建和完整阶段验收仍待完成，未正式发布。
