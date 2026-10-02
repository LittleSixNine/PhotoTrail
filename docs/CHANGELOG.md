# 开发历史 / Development history

此处记录源码开发节点，不等于已发布版本。发布版本见 [GitHub Releases](https://github.com/LittleSixNine/PhotoTrail/releases)。行为契约见 [BEHAVIOR.md](BEHAVIOR.md)，构建与检查见 [DEVELOPMENT.md](DEVELOPMENT.md)。

These are source development milestones, not release announcements. The metadata editor remains on `feature/metadata-editor`; the Rename page is a placeholder.

## 2026-10-03 · 元数据编辑工作台与完整读取

- 列表页常驻可调宽元数据右栏，11 组参考目录及独立分来源编辑字段；整行点击、分组卡片、字段管理、搜索与筛选。普通／日期编辑窗口扩大，日期支持年月日时分秒偏移。
- 开放 62 项受控写入标签；标题、说明、作者、版权、关键词、日期、相机／镜头、曝光／枚举、预设、比较、CSV／XMP 交换复用预览、草稿、撤销和手动保存。JPEG 与已有 XMP 支持新字段，其他格式维持明确边界。
- 导入后后台缓存完整可识别元数据，选中图片优先；增加读取进度和逐张状态。补齐 MakerNotes、ICC、Photoshop、容器和派生信息，保留同名来源／副本，原标签排除文件属性、引擎信息及派生项。
- 左侧移除拍摄时间、定位和轨迹列，增加原标签和待保存字段计数；保留拍摄时间排序、匹配筛选、原有列表布局和操作。
- 日期统一显示完整日期时间、时区和明确亚秒；光圈与快门使用摄影常用表示；修复地图侧栏滚动条出现／消失时的宽度反馈。
- 顶部为元数据编辑、地图定位及重命名。重命名仍为“待构建”，未实现文件改名，也未自动接入当前写入前备份。

新增可识别信息以只读展示为主，不因读取范围扩大而自动开放写入。未知来源、文件变化、备份失败或保存结果未知仍保留安全拦截。

## 2026-09-26 · v0.4.0

完成七种语言、首次语言选择及默认地图设置；采用手动 DMG 安装更新。

## 2026-09-24 · v0.3.11

统一照片导入范围、忽略非图片文件并保留 GPX；加入默认关闭的更新下载和下次启动手动安装提示。

更早节点可通过 Git 历史及 Release 查询；私人照片、验证输出和交接文档不进入此仓库。
