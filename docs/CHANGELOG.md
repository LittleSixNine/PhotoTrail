# 开发历史 / Development history

此处记录源码开发节点，不等于已发布版本。发布版本见 [GitHub Releases](https://github.com/LittleSixNine/PhotoTrail/releases)。行为契约见 [BEHAVIOR.md](BEHAVIOR.md)，构建与检查见 [DEVELOPMENT.md](DEVELOPMENT.md)。

Release milestones and source development history are recorded below.

## 2026-10-08 · v0.5.3

- 常用与完整元数据字段统一列表及编辑方式，移除筛选／显示管理菜单；日期标明来源，扩展文件时间与受控 EXIF／IPTC／XMP 编辑。
- 自定义批量预设支持有序编排、预览、保存和 JSON 交换；一个来源可复制至多个字段。精简重复时间操作，保留旧预设兼容；年月日时分秒各行显示单位及增减方向。
- 元数据字段支持 ⌘C／⌘V 与 Ctrl+C／Ctrl+V 的多目标粘贴，完整校验后加入草稿；修改值橙色显示，保存刷新保持已有字段列表。
- 重命名规则整卡拖动排序，统一插入／替换术语；独立设置弹窗说明关联文件及扩展名优先级，冲突后缀增加格式与 2–5 位数字选择。
- 重命名左栏统一预设管理，启动恢复上次方案，默认全部照片；三页共用照片集合及选择，移除可撤销。删除下方重复步骤区，保留列表中的可选中间列。
- 导入显示全部流程的预计剩余时间，超过 300 张显示等待提示；重命名预览显示居中加载反馈，执行提供全局进度与停止恢复。
- 重命名哈希读取及时释放临时块，并复用目录访问书签，减少大批量校验的内存累积。

Version 0.5.3 unifies metadata rows and the three-tab photo collection, add editable batch presets and field copy/paste, improve date controls and rename presets, and update progress and bulk-rename memory handling. Version 0.5.2 below remains a separate release milestone.

## 2026-10-08 · v0.5.2

- 优化大量照片在元数据列表和定位照片条中的选择刷新，复用筛选、排序与所选照片快照，保持日期编辑、撤销及配对规则。
- 定位照片条按显示尺寸加载缩略图，右键菜单在打开时构建；当前照片大预览优先加载，并使用独立的容量受限缓存。
- 显示全部照片时，地图选择更新不再重建整批照片分组；滚动辅助控件复用已找到的原生对象。设置、收藏及轨迹缓存继续沿用，缩略图与元数据读取缓存仍为会话缓存。

Version 0.5.2 improves photo selection in the metadata list and location filmstrip, sizes filmstrip thumbnails for their display area, defers context-menu construction and prioritizes the current preview. All-photo map selection reuses existing grouping. Settings, favorites and track caches remain compatible; thumbnail and metadata-read caches remain session-only.

## 2026-10-08 · v0.5.1

- 优化大量照片的定位与元数据保存、后台读取及列表缩略图加载，减少批量处理期间的界面重复刷新。
- 导入和大批量元数据读取显示准备页，提供阶段进度、失败计数及当前阶段预计剩余时间；元数据读取支持暂停和继续。
- 目录扫描移至后台，保留原有过滤、配对、草稿、备份和文件版本保护。

Version 0.5.1 improves bulk photo saves, metadata reading and thumbnail loading. Import and large metadata batches show a preparation page with stage progress and an estimated remaining time; metadata reading can be paused and resumed. Directory scanning runs in the background while existing draft, backup and file-version protections remain in place.

## 2026-10-05 · v0.5.0

- 发布元数据编辑与文件重命名工作台，包含字段多选、批量复制和赋值、设备选项、规则预览、冲突检查及原名恢复。
- 常用字段采用照片信息、拍摄时间、设备分组的快速编辑表单；完整字段改为紧凑左右布局。统一元数据与定位的写入入口，重命名前提示处理未保存修改。
- 地图左栏采用分层展开和多选照片堆叠预览；轨迹统一支持 GPX、KML、KMZ，缺少逐点时间的路线仅供查看。CSV 轨迹暂缓。

Version 0.5.0 brings metadata editing and file renaming, quick common-field forms, a compact complete-field list, a shared metadata save action, a reorganized map sidebar, and GPX/KML/KMZ import. Untimed routes are view-only; track CSV is not supported.

## 2026-10-04 · 字段批量编辑、设备目录与加载优化

- 元数据行采用原生单选、⌘ 增减与 Shift 连选，双击或箭头打开编辑器；字段选择独立于照片选择。
- 新增按所选字段批量复制来源、统一赋值、粘贴及清除，显示目标与只读排除数量。每张照片使用自己的来源值，保留亚秒、时区及已有草稿，缺失来源跳过。
- 复用预览、可撤销草稿、备份与手动保存路径，补充真实 JPEG 多日期写入和缺失来源测试；文案覆盖七语言。

Metadata rows now support native multiple selection and batch field operations. Copying a source field uses each photo’s own effective value; date precision and pending edits are preserved, while missing sources are skipped. Changes still require preview and manual saving.

- EXIF／XMP 制造商与型号支持按品牌搜索机型，首批 32 品牌、190 个已核实组合，保留自定义；每项有来源，选择只填当前字段。
- 元数据面板复用合并值、标签映射和编辑资格，空查询／名称匹配时跳过不必要的值读取；修复异步预览缓存与当前选择错配。

## 2026-10-03 · 文件重命名工作台

- 第三页接入原生双栏规则与预览，97 个动作入口加筛选和高级设置；支持规则启停／重排、JSON 预设、配对、冲突处理和十个持续计数器。
- 改名先检查目录权限、源身份和元数据草稿；原生不覆盖操作支持交换及循环名称，哈希核对内容，持久日志支持恢复原名。成功后同步照片 ID 对应的路径、名称和缓存。
- 本地普通文件通过独立入口加入，目录仅用于授权；目录改名、递归收集、Finder／Droplet 和第三方预设导入不在当前支持范围。完整边界见 [功能约定](BEHAVIOR.md)。

The third tab now provides a native rules-and-preview workspace with 97 action entries, presets, paired files, persistent counters and journal-based restoration. Rename operations preserve file contents and reject occupied targets; directory renaming and Finder/Droplet integrations are not supported.

## 2026-10-03 · 元数据编辑工作台与完整读取

- 列表页常驻可调宽元数据右栏，11 组参考目录及独立分来源编辑字段；整行点击、分组卡片、字段管理、搜索与筛选。普通／日期编辑窗口扩大，日期支持年月日时分秒偏移。
- 开放 62 项受控写入标签；标题、说明、作者、版权、关键词、日期、相机／镜头、曝光／枚举、预设、比较、CSV／XMP 交换复用预览、草稿、撤销和手动保存。JPEG 与已有 XMP 支持新字段，其他格式维持明确边界。
- 导入后后台缓存完整可识别元数据，选中图片优先；增加读取进度和逐张状态。补齐 MakerNotes、ICC、Photoshop、容器和派生信息，保留同名来源／副本，原标签排除文件属性、引擎信息及派生项。
- 左侧移除拍摄时间、定位和轨迹列，增加原标签和待保存字段计数；保留拍摄时间排序、匹配筛选、原有列表布局和操作。
- 日期统一显示完整日期时间、时区和明确亚秒；光圈与快门使用摄影常用表示；修复地图侧栏滚动条出现／消失时的宽度反馈。
- 顶部为元数据编辑、地图定位及重命名。该节点的重命名仍为“待构建”；后续文件改名使用独立执行日志，见上方节点。

新增可识别信息以只读展示为主，不因读取范围扩大而自动开放写入。未知来源、文件变化、备份失败或保存结果未知仍保留安全拦截。

## 2026-09-26 · v0.4.0

完成七种语言、首次语言选择及默认地图设置；采用手动 DMG 安装更新。

## 2026-09-24 · v0.3.11

统一照片导入范围、忽略非图片文件并保留 GPX；加入默认关闭的更新下载和下次启动手动安装提示。

更早节点可通过 Git 历史及 Release 查询；私人照片、验证输出和交接文档不进入此仓库。
