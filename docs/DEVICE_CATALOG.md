# 设备机型选项 / Device choices

核查日期：2026-10-04。目录包含 115 个品牌／历史设备分组，7,360 组照片样本中读到的 Make/Model，以及 5,023 项仅核实商品名的选项。历史运营商品牌、不同地区、大小写和处理软件产生的变体单独保留，因此条目数不是独立硬件机型数，也不是完整在售清单。

## 如何选择

品牌和型号并列显示，型号列表可搜索。同一行左右分别是商品名称、元数据型号；直接点击需要的名称即可填入，不另设名称切换开关。选中处有勾，关闭菜单后仍显示当前选择，下方输入框可以继续修改或完全自定义。名称相同的记录只显示一项，当前字段的重复选项合并显示。

标为“仅商品名”的选项来自官方产品名称目录：可以选择该商品名，但没有对应的已核实照片元数据型号。这类选项不提供元数据型号按钮，也不为制造商字段猜测 Make。Android 系统型号、监管编号、商品名和照片中的 EXIF Model 不能自动视为同一个值。

选择只填当前字段，不连带改写其他来源、制造商或厂商私有信息。编辑制造商时只提供实际 Make 值；不能把相机商品名写入 Make。所有操作仍需预览、加入待保存，再手动保存照片。

## 来源与核查

应用内置的 [MetadataDevices.json](../Sources/PhotoTrail/MetadataDevices.json) 可离线使用，不会查询或上传照片。`source` 指向 Make/Model 的照片样本依据，或仅商品名条目的官方名称目录；`nameSource` 若存在，说明商品名的独立对应依据。`productNameOnly: true` 明确表示没有确认的 Make/Model，空字符串不作为可写的元数据候选。

- [ExifTool 官方样本库](https://exiftool.org/sample_images.html)：读取公开样本的实际 Make/Model；归档可能包含经过处理软件修改的照片，不能承诺每个值都是相机出厂直出值。
- [RAW 样本库](https://raw.pixls.us/)和摄影者在 [Wikimedia Commons](https://commons.wikimedia.org/) 发布照片中的实际元数据：只使用读取到的值。分类与照片品牌不符的记录排除；分类标签本身不用于推断元数据型号。
- [Google 官方设备目录](https://storage.googleapis.com/play_public/supported_devices.html)（2026-10-03 更新，[官方说明](https://support.google.com/googleplay/answer/1727131?hl=en)）：核对已读到的手机型号对应商品名，并补充仅商品名选项。不会把目录中的 Android 系统 Model 自动当成 EXIF Model。名称冲突时保留样本型号，不猜商品名。明显的电视、机顶盒、手表等名称已排除；目录仍包含可拍照的平板及历史设备。
- 第一批独立核实的厂商官网、评测原图和摄影者资料继续保留原来源。

解析时去除固定宽度字段的首尾空白，过滤缺少 Make/Model、控制字符、明显改写或通用占位符的记录。理光资料包中的 PENTAX 型号归到宾得；哈苏的 DJI 相机模块归到 DJI；Olympus 与 OM SYSTEM、Sony 与 Xperia 分开。原照片、下载包和研究日志不随应用分发。

## 覆盖限制

商品名覆盖比照片元数据样本覆盖广。Google Play 目录不是全球手机全集，不能覆盖所有中国市场机型、未认证设备和新发布产品；无可靠样本的内部型号仍未预填。FLIR 样本包未能完整取得。不同固件、地区和拍摄／处理软件可能写入不同值；选择预设不能复制整台设备的元数据特征。所有缺项均可使用自定义文本。

| 品牌／分组 | 样本 Make/Model 组合 | 仅商品名 |
| --- | ---: | ---: |
| Sony | 715 | 0 |
| Nikon | 308 | 0 |
| Canon | 721 | 0 |
| Hasselblad | 11 | 0 |
| Leica | 67 | 0 |
| Olympus | 302 | 0 |
| OM SYSTEM | 6 | 0 |
| Fujifilm | 410 | 0 |
| Ricoh | 98 | 0 |
| DJI | 32 | 0 |
| Insta360 | 14 | 0 |
| Panasonic | 474 | 0 |
| Pentax | 156 | 0 |
| Sigma | 24 | 0 |
| GoPro | 24 | 0 |
| Apple | 61 | 0 |
| Samsung | 1049 | 473 |
| Google | 32 | 13 |
| Huawei | 61 | 542 |
| Honor | 17 | 125 |
| Xiaomi | 54 | 182 |
| OPPO | 8 | 628 |
| OnePlus | 11 | 98 |
| vivo | 12 | 668 |
| iQOO | 6 | 79 |
| realme | 5 | 276 |
| Nothing | 12 | 7 |
| Motorola | 78 | 354 |
| ASUS | 11 | 163 |
| Sony Xperia | 36 | 129 |
| ZTE | 19 | 321 |
| Meizu | 5 | 60 |
| Acer | 21 | 0 |
| Agfa | 23 | 0 |
| Aiptek | 12 | 0 |
| BBK | 5 | 0 |
| BenQ | 75 | 0 |
| BlackBerry | 28 | 0 |
| Browning | 2 | 0 |
| Bushnell | 1 | 0 |
| Casio | 169 | 0 |
| Concord | 45 | 0 |
| Creative | 13 | 0 |
| Daisy | 8 | 0 |
| Digilife | 3 | 0 |
| DoCoMo | 74 | 0 |
| DXG | 8 | 0 |
| DxO | 1 | 0 |
| Epson | 33 | 0 |
| Fairphone | 5 | 2 |
| Fly | 8 | 0 |
| Garmin | 2 | 0 |
| Gateway | 5 | 0 |
| GE | 43 | 0 |
| Genius | 7 | 0 |
| Hitachi | 30 | 0 |
| HMD | 4 | 17 |
| HP | 141 | 0 |
| HTC | 118 | 0 |
| Infinix | 2 | 215 |
| Infisense | 1 | 0 |
| JVC | 186 | 0 |
| KDDI | 87 | 0 |
| Kodak | 177 | 0 |
| Konica | 25 | 0 |
| Kyocera | 26 | 0 |
| Lenovo | 11 | 0 |
| LG | 141 | 0 |
| Light | 1 | 0 |
| Logitech | 4 | 0 |
| Lumicron | 6 | 0 |
| Mamiya | 1 | 0 |
| Medion | 18 | 0 |
| Mercury | 6 | 0 |
| Microsoft | 16 | 0 |
| Minolta | 55 | 0 |
| Moultrie | 10 | 0 |
| Mustek | 6 | 0 |
| NEC | 5 | 0 |
| Nintendo | 2 | 0 |
| Nokia | 182 | 89 |
| Noritsu | 7 | 0 |
| ODYS | 10 | 0 |
| OMG | 1 | 0 |
| Oregon | 5 | 0 |
| Packard | 2 | 0 |
| Pantech | 17 | 0 |
| Parrot | 1 | 0 |
| Pentacon | 34 | 0 |
| Polaroid | 70 | 0 |
| Reconyx | 10 | 0 |
| RED | 1 | 0 |
| Rollei | 18 | 0 |
| Sagem | 14 | 0 |
| Sanyo | 73 | 0 |
| SeaLife | 8 | 0 |
| Sharp | 58 | 235 |
| SiPix | 4 | 0 |
| Skanhex | 10 | 0 |
| Sony Ericsson | 148 | 0 |
| Sprint | 1 | 0 |
| Sunplus | 4 | 0 |
| T-Mobile | 6 | 0 |
| Tecno | 4 | 347 |
| Toshiba | 40 | 0 |
| Traveler | 23 | 0 |
| Trust | 13 | 0 |
| UMAX | 2 | 0 |
| Uniden | 1 | 0 |
| VistaQuest | 2 | 0 |
| Vivitar | 63 | 0 |
| Vodafone | 9 | 0 |
| Yakumo | 7 | 0 |
| Yashica | 2 | 0 |
| Zeiss | 1 | 0 |

## English

Checked on 2026-10-04: 115 brand/historical groups, 7,360 observed photo Make/Model pairs and 5,023 additional product-name-only choices. Counts include regional and spelling variants, not just distinct hardware products.

Click either the product name or the observed metadata model in a row. Identical names appear once; the final text remains editable. Product-name-only rows are explicitly marked and never supply an unverified EXIF model or maker. The official Google Play list is used for retail-name evidence; Android system model identifiers are not assumed to be photo metadata. Existing preview, draft, backup and explicit-save checks are unchanged. No source photographs are bundled or uploaded.

Coverage is not exhaustive, especially for new, domestic-market or uncertified phones. The FLIR sample archive could not be retrieved completely. Some public samples have been processed by software, so observed strings are not guaranteed factory defaults. Custom input remains available.
