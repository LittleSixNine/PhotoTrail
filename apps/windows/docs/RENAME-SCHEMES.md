# Windows重命名方案格式与使用

方案管理保存本机配置，绝不执行改名或保存照片。执行仍须检查冲突并冻结，再执行；恢复仍使用实际执行记录。未保存规则／排序／名称／示例可保存、放弃或取消切换，取消保持整个现场。示例仅供说明，不参与生成；新建取首项有效预览，后续刷新不会覆盖编辑。单独改名／示例不改变冻结目标。

## 存储与边界

默认 `%LOCALAPPDATA%/PhotoTrail/Windows/rename-schemes-v1.json`；测试可用 `PHOTOTRAIL_RENAME_SCHEMES` 隔离。根对象为 `format: phototrail-windows-rename-library`、`version: 1`、`initialized: true`、`lastId` 和 `schemes`。每项仅 `id`、`name`、`rules`、`order`、`example`；order仅 `sort`、`descending`、可空 `metadataSortTag`。不含照片路径、输入筛选、手动组身份、冻结计划或执行记录。

严格UTF8，可有UTF8 BOM；不接受UTF16、重复属性、未知属性／版本、重复身份或名称、非法规则。最多1MiB、256项；名称1至100个UTF16代码单元且非空白，示例0至255，均拒绝控制字符和非法Unicode。规则最多32768字符、64条，单条文字至多256字符。名称比较不区分大小写；同名依次加` (2)`等编号。

库及最后身份用已有原子文件保存，成功后才更新内存；损坏记录保持原文件并禁库管理，不重新初始化掩盖错误。首次缺文件仅一次加入默认项；删除全部仍保存initialized空库。重启恢复最后保存项，删除最后项后选首个剩余；空库空规则，未保存编辑／执行资格不恢复。同一Windows会话内Local命名Mutex串行复核旧SHA，旧实例须重新打开处理冲突。跨Windows会话和不合作外部写入不保证全局事务。

## 导入导出兼容

导出 `format: phototrail-windows-rename-scheme`、`version: 2`、`scheme`，包含单项配置。导入总是产生新ID、同名编号，绝不覆盖旧项。旧Windows规则JSON（version1、rules、sortByName及可选sort／descending／metadataSortTag）继续可读。旧编号规则仍追加编号；新增固定规则使用原始规则JSON version2，旧程序会拒绝未知版本。Mac JSON不支持直接互导；不是跨平台通用方案格式。已有Windows方案文件不自动载入、覆盖或改名，没有虚构旧城市方案库迁移。

## 五个初始模板

| 名称 | 规则 | 合成示例 |
| --- | --- | --- |
| 城市＋拍摄时间 | date-set；city-prefix\|_ | 上海市_20261006_171649.jpg |
| 数字编号＋原名 | sequence-prefix\|1\|1\|4\|_ | 0001_DSC_1234.jpg |
| 拍摄时间＋设备型号 | date-set；model-suffix\|_ | 20261006_171649_NIKON D750.jpg |
| 拍摄时间＋原名 | date-prefix\|_ | 20261006_171649_DSC_1234.jpg |
| 自定义前缀＋编号 | set\|请自定义文字_；sequence\|1\|1\|4 | 请自定义文字_0001.jpg |

规则实际用换行分隔，表中分号表示换行；自定义文字直接编辑set行。日期使用逻辑组主照片有效拍摄时间：草稿／明确清除优先，再按已有XMP／内嵌拍摄字段、记录偏移及小数秒读取。仅格式化记录的墙上日期，不猜当前日期、不转本机时区、不更改照片日期。城市XMP-photoshop:City优先IPTC:City；型号XMP-tiff:Model优先IFD0:Model再ExifIFD:Model，XMP旁车和草稿优先。缺失所需字段、读取失败、错误类型及非法日期分别拒绝生成，不虚构替代值。

主照片生成一组名称，JPG／RAW／XMP保持同stem、各自原扩展名；配对及筛选后连续编号沿既有机制。保留Windows非法名、保留名、尾随点空格、长度、大小写冲突和不覆盖保护。已有草稿可以预览，既有冻结前须先处理草稿保护不改变。


R08a新增Windows单行JSON参数规则，详见[规则](RENAME-RULES.md)。此前“扩展名保留”仅适用旧主体规则；主文件可明确变更扩展名，其他配对成员仍保留自身扩展名。不是Mac数字方案兼容。
