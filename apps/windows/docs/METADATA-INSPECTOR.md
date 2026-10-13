# Windows 来源检查器 R02

固定产品目录参考公开73c0640bca4d1a2919aa3a466487a5cb20c7f28d的MetadataFieldFilter与MetadataDisplaySection。11组73个参考字段用于展示，另列实际附加字段；不能据此授予写入权限。默认常用24项逐项映射如下，保留无值参考行。完整技术标签包括工具返回的Copy标识；家族／副本和未知字段只读。只有精确命中原27项表单、且为该照片当前有效XMP来源的无Copy标签提供既有编辑入口。

| 规范标签 | Windows实际展示来源 | 权限 |
| --- | --- | --- |
| `File:FileName` | System:FileName；各角色分别显示 | 只读 |
| `File:FilePath` | 应用添加各物理来源完整路径；不计原标签 | 只读 |
| `Composite:SubSecDateTimeOriginal` | Composite:SubSecDateTimeOriginal | 只读 |
| `Composite:SubSecCreateDate` | Composite:SubSecCreateDate | 只读 |
| `Composite:SubSecModifyDate` | Composite:SubSecModifyDate | 只读 |
| `IPTC:DateCreated` | IPTC:DateCreated | 只读 |
| `IPTC:TimeCreated` | IPTC:TimeCreated | 只读 |
| `XMP-xmp:CreateDate` | 同命名空间，按原图／旁车／独立XMP区分 | 精确无Copy有效来源可进入既有XMP编辑；其余只读 |
| `XMP-xmp:ModifyDate` | 同命名空间，按来源角色区分 | 精确无Copy有效来源可进入既有XMP编辑；其余只读 |
| `XMP-exif:DateTimeOriginal` | 同命名空间，按来源角色及Copy身份区分 | 精确无Copy有效来源可进入既有XMP编辑；其余只读 |
| `XMP-exif:DateTimeDigitized` | 同命名空间，按来源角色区分 | 精确无Copy有效来源可进入既有XMP编辑；其余只读 |
| `IFD0:Make` | IFD0:Make，不合并XMP-tiff:Make | 只读 |
| `IFD0:Model` | IFD0:Model | 只读 |
| `ExifIFD:ISO` | ExifIFD:ISO | 只读 |
| `ExifIFD:FNumber` | ExifIFD:FNumber | 只读 |
| `ExifIFD:ShutterSpeedValue` | ExifIFD:ShutterSpeedValue | 只读 |
| `ExifIFD:FocalLength` | ExifIFD:FocalLength | 只读 |
| `ExifIFD:ExposureCompensation` | ExifIFD:ExposureCompensation | 只读 |
| `EXIF:GPSLatitude` | GPS:GPSLatitude | 只读 |
| `EXIF:GPSLatitudeRef` | GPS:GPSLatitudeRef | 只读 |
| `EXIF:GPSLongitude` | GPS:GPSLongitude | 只读 |
| `EXIF:GPSLongitudeRef` | GPS:GPSLongitudeRef | 只读 |
| `EXIF:GPSDateStamp` | GPS:GPSDateStamp | 只读 |
| `EXIF:GPSTimeStamp` | GPS:GPSTimeStamp | 只读 |

常用选择为显示过滤；完整搜索仍覆盖当前全部已读字段。设置支持名称和技术标签搜索、勾选、空选择及恢复默认。未知附加字段可以配置展示，但始终保持其原权限。有效空数组保存为空；缺失、无效版本、损坏JSON或非法配置结构回退默认，不自动改写原配置。来源角色及命名空间、Copy身份分别保留。原始快照不被草稿覆盖。

手动重读默认跳过有草稿照片；存在未应用表单输入时本次所选全部跳过，并保留输入。背景准备后复核请求、选择、原照片对象、草稿revision、输入、源SHA及旁车关系，用只读句柄保护接纳的源。保存／更名／恢复忙碌或需恢复的事务状态禁止刷新。失败保留旧快照并标记过期；取消或迟到结果不接纳。不把新源SHA套到旧草稿，外部变化仍由原保存链拒绝。来源稳定的无草稿照片可以接纳新增／消失旁车后的新关系。成功更新使日期、重命名预览、地图／轨迹匹配失效并重新按v2证明派生。

单张列表、所选及全库的原标签数为已读物理来源实例数，排除文件／工具技术信息与Composite派生字段；重复副本分别计数，列表元素不拆成实例。未读为未知，部分已读总数同时标明未读量；失败重读保留旧计数并注明过期。净草稿仅当前相对保存基准的变化，来源重复不重复计入；每个完整日期字段计一项，GPS组合计一项。原字段改回、完整撤销或清空移除净变化。显式副本保存保留原照片会话草稿，新副本回读是新基准；不改变原保存范围。

多照片逐字段比较、原位保存／新旁车、新EXIF/IPTC写入继续由后续独立路线图批次处理。Apple Photos／Apple地图／Finder标签本体沿已批准平台例外处理，目录缺值不把Finder标签重新记为待决定；其余平台资源与功能保留原边界。
