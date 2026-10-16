# WIN-M6 收尾 r3：两项定向补修

只修P2-02日期边界说明截断、P2-06重命名程序状态漏翻译，不改变日期解析、筛选、重命名模型、日志、文件名、元数据、写入或恢复契约。Mac目标仍为0.5.10/build1970、cbeccc015c416c6a82d02645eeb6ccfadb8cef99。

## 改动与归属

- `PhotoTrail.Windows/MainWindow.xaml:690`：原日期说明命名为RenameDateBoundaryNotice并启用Wrap，沿现有任务窗ScrollViewer滚动。没有改两列表单、输入框尺寸、最小窗口或日期值。
- `PhotoTrail.Windows/MainWindow.RenameUi.cs:76`：结果Status列复用既有LocalizedDisplay；`Resources/LocalizedStrings.json`只补四个程序状态的七语言资源。原始Status／State与序列化值不变，恢复作为逆向更名仍显示“已更名”的相应译文，不虚构新增模型状态。
- `DateHost/UiChecks/ParityM6R3Checks.cs`及Program入口：最终DLL真实模态表单布局、尾句可见区域、正反焦点和七语言实际DataGrid单元格检查；未执行／待恢复用明确标记的仅呈现合成行，不制造写入故障。
- `DateHost/UiChecks/ParityM6CloseoutChecks.cs`：既有筛选检查保留并补借入窗口关闭后有效／非法输入保留两条。DateHost生产Host／运行库38文件不变。

## 最终候选与定向验证

生产提交3145147e62fd9fcda0d80d7c31d0591da1e83313；最终r3 DLL SHA256：70f30903f082083feac8c0a74111dd7e3e21ce82dd16e6ecd12c0d59f01dfd7e。Release win-x64/.NET10框架依赖，614文件完整候选本机独立保留；沿用原正式版本0.5.10-win.m5／WIN-M5标题，按批次、提交和SHA区分。

| 最终DLL实际运行 | 断言 |
|---|---:|
| r3七语言定向检查：中文简／繁、日、韩、西、葡各46，英文52 | 328 |
| 原收尾受影响回归 | 41 |
| 重命名回归 | 31 |
| 日期筛选／正反焦点／关闭输入保留 | 17 |
| 合计10套 | 417 |

没有把旧筛选15与新17叠加；没有继承r2的13套456或更旧1235。生产构建与检查工具构建均0警告0错误，检查载入上述同一生产DLL。

14张最终r3原生新图：中文／西语默认与大字号、正常与约446宽任务窗共8图；英文真实预览→明确执行→选本次记录→恢复4图；未保存错误参数退出提示→取消后输入保留2图。3张合成JPEG执行与恢复后独立名称、SHA、创建／写入时间、属性、可读ACL保持，2条未用GPX保持。未使用旧unknown或持续计数槽。工具给模态窗发键受父窗激活限制，原生Tab未验；WPF实际Traversal另行通过。

## 保留限制

P2-01/03/04/05按Mac反馈限定关闭；P2-02/06补修开发完成，待Mac复审／用户验收。r2的46图、两条安全链、ExifTool／像素回读与456断言保留原构建归属，本次没有重跑完整旧矩阵。实际200%DPI；100/150DPI、读屏／高对比、多屏、干净部署未验；服务许可/D06、词性／音乐、格式／深路径／TxF、真实互导与历史恢复unknown等原限制不变。Mac没有独立运行WPF；没有合并、PR、标签、发布或恢复自动化。
