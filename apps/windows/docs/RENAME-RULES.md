# Windows参数重命名规则

每行一条，保留旧前缀/后缀/替换/设名/大小写/数字规则；新增单行Windows JSON，不直接执行Mac数字动作或完整Mac方案。移动行调整顺序，复制行复制规则，Enabled控制启停。预览与冻结共用计算，显示真实每步名称。

```json
{"Kind":"action","Action":"add-position","Text":"旅行_","Position":1}
{"Kind":"action","Action":"regex-replace","Text":"(IMG)_([0-9]+)","Replacement":"$2_$1"}
{"Kind":"action","Action":"replace-text","Text":"jpg","Replacement":"JPG","Part":"extensionOnly"}
```

共同默认：Enabled=true、Part=stem、Occurrence=all、MatchNumber=1、CaseSensitive=true、Position=0、Length=1、Start=1、Step=1、Padding=3、Text/Replacement/Anchor/Prefix/Suffix为空、SkipMissing=true、FullMatch=false、DateSource=shooting、DateFormat=yyyyMMdd_HHmmss、TimeZone=source、NightHour=0。Part另有entire/dottedExtension/extensionOnly；Occurrence另有first/last/nth。位置和范围按0基扩展字形簇，匹配及捕获也不能切开字形簇。参数文字1024、链32768字符/64条、中间名称4096字符；未知/重复字段、错误类型、未知动作拒绝。

## 本批命名动作

add-begin, add-end, add-before, add-after, add-position, remove-begin, remove-end, remove-text, replace-begin, replace-end, replace-text, move-front, move-end, move-position, move-before, move-after, replace-characters, remove-characters, keep-characters, trim-begin, trim-end, remove-vowels, remove-emoji, drop-begin, drop-end, remove-range, move-range, lower, sentence, title, upper, percent-decode, camel-expand, remove-diacritics, mac9-name, windows-name, truncate, dos83-name, date-set, date-begin, date-end, date-before, date-after, date-position, template-set, template-begin, template-end, template-position, template-before, template-after, size-end, size-begin, size-set, size-before, size-after, size-position, parent-begin, parent-end, parent-before, parent-after, parent-position, path-begin, path-end, path-before, path-after, path-position, regex-replace, regex-rearrange, set, device-set, device-begin, device-end, device-position, device-before, device-after, location-set, location-begin, location-end, location-position, location-before, location-after

添加/移动用Anchor或Position，范围用Position/Length（move-range的Start是移除后的目标位置）；文字匹配用Text/Replacement/Occurrence/MatchNumber/CaseSensitive。设备和地区用精确MetadataField与Prefix/Suffix；尺寸使用真实合法快照的正整数ImageWidth/ImageHeight，Text为空时分隔x。路径动作从父目录反向Position选Length层，Text默认下划线连接，只生成名称文字，不移动目录。

不自动NFC；两种Unicode拼写不强制归并为NTFS组。大小写/标题使用.NET不变文化，与Foundation全量Unicode折叠未证明等价。remove-emoji使用固定Unicode16官方Emoji/Emoji_Presentation（及variation selector/keycap）整字形簇属性，包内附Unicode许可。remove-diacritics仅明确选用时NFD去非间隔重音标记/NFC重组，所有语言Foundation folding等价未验。Apple NaturalLanguage词性分类没有等价实现，明确不支持；音乐输入不在照片接纳范围。模板可使用照片实际已读精确标签。

正则原生.NET：100ms/1024表达式/4096匹配；普通/非捕获组和断言、$0..$99、\U/\L/\u/\l/\E显式替换。ICU属性、\X/\R、quoted literal、特殊/命名组、集合交叉等未映射语法拒绝；非法表达式/替换/超时不降级字面处理。regex-rearrange的FullMatch控制全域匹配；没有命中显示excluded。

模板读取`<XMP-dc:Title>`、`<CameraModel>`、`<IPTCCity>`、`<ParentFolderName>`、`<FileName>`等实际来源。明确家族标签仅精确匹配，非限定标签按稳定家族顺序；地区XMP优先，实际旁车和草稿优先。读取失败/非法类型不能当作缺失。SkipMissing=true时缺标签或日期整组恢复原名并停止后步，中间列显示missingTag/missingDate；false保持本步名称继续，缺锚点显示missingAnchor。

日期shooting使用当前主时间，created/modified使用System快照；now只在显式选择时使用本次读取冻结参考时间，不是缺值回退。所有日期先由固定DateHost验证，源墙钟只摘取授权字段，不用C#重算历法。格式支持yyyy/yy、MM/M、dd/d、HH/H、hh/h、mm/m、ss/s、SS/SSS、a、XXX及单引号字面文字；其余拒绝。显示小数按位截取，不改写原文。XXX须源真实偏移；其冒号仍可能导致最终Windows名称非法。

local或可解析命名时区只对明确instant、100ns可表达、1582-10-15及以后值做.NET原生时区格式投影，再由固定DateHost验证；不猜偏移、不舍入纳秒、不声称完整历史时区等价。NightHour=0..23；小于阈值时按固定DateHost减一天，保留时分秒和精度。拍摄/创建/修改时间模板使用同一证明。

主文件保留计算后的完整名称，其他配对成员共享主体并保留自身扩展名。最终NTFS非法字符/保留名/尾点空格/长度/大小写冲突及不覆盖链保持。冻结同句柄SHA、身份、System创建/修改时间、属性和ACL，执行前再核对、执行后实际回读。新增配对成员、来源/规则/顺序变化、草稿/unknown事务沿原拒绝门。执行记录v2含System证据，v1继续读取；恢复按实际SHA、不覆盖、安全暂存和持久记录。预览不写照片、不消耗计数。
