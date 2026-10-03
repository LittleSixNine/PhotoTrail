# 设备机型选项 / Device choices

核查日期：2026-10-04。首批 32 个品牌、190 个 Make/Model 组合，覆盖主要相机和手机系列，并保留少量常见上一代设备。不是所有地区、固件和机型的完整在售清单。

编辑 EXIF 或 XMP 的设备制造商、型号时，可先选择品牌，再搜索商品名或型号编号、选择机型；写入的是对应的元数据值。选项只填入当前字段，下方文本框始终支持自定义。仍需预览、加入草稿，再手动保存。选择型号不会偷偷改写制造商或厂商私有信息。

商品名与元数据值经常不同，例如索尼 α7 IV 的 Model 为 `ILCE-7M4`，佳能 EOS R5 Mark II 的样本值为 `Canon EOS R5m2`。同一商品也可能有地区／固件／处理软件产生的大小写或型号变体；目录保留已核实的不同组合，不保证能模拟该设备的完整文件特征。

## 来源与维护

应用内置的 [MetadataDevices.json](../Sources/PhotoTrail/MetadataDevices.json) 为每个选项保留来源 URL，仅保存商品名、Make、Model。品牌／机型可离线使用，不会查询或上传照片。

厂商官网用于核对产品名称与当前系列；真正的 Make/Model 以 [ExifTool 官方样本](https://exiftool.org/sample_images.html)、[RAW 样本库](https://raw.pixls.us/)、摄影者公开照片的 EXIF 及评测者原始样片为依据。只提取这些事实，不分发来源照片。监管型号或商品名不能直接当作 EXIF 值。没有找到可靠样本的新机型暂不预填，可直接输入自定义值。相机范围还补充了松下、宾得、适马、OM SYSTEM 与 GoPro；手机包含主要中国及国际品牌。

| 品牌 / Brand | 已核实组合 / Verified pairs |
| --- | ---: |
| Sony | 20 |
| Nikon | 16 |
| Canon | 15 |
| Hasselblad | 4 |
| Leica | 9 |
| Olympus | 4 |
| OM SYSTEM | 6 |
| Fujifilm | 13 |
| Ricoh | 3 |
| DJI | 9 |
| Insta360 | 9 |
| Panasonic | 12 |
| Pentax | 4 |
| Sigma | 3 |
| GoPro | 3 |
| Apple | 10 |
| Samsung | 4 |
| Google | 9 |
| Huawei | 1 |
| Honor | 3 |
| Xiaomi | 10 |
| OPPO | 4 |
| OnePlus | 1 |
| vivo | 5 |
| iQOO | 2 |
| realme | 2 |
| Nothing | 3 |
| Motorola | 2 |
| ASUS | 1 |
| Sony Xperia | 1 |
| ZTE | 1 |
| Meizu | 1 |

## English

Checked on 2026-10-04: 190 verified Make/Model pairs across 32 brands, covering major camera and phone families plus some common earlier models. This is a curated first batch, not an exhaustive worldwide sales or firmware database.

Choose a brand, search a retail name or metadata model code, then select a device. Only the field currently being edited is filled; custom text remains available. Preview and explicit saving still apply. Product names, regulatory model numbers and actual EXIF strings are not interchangeable. Each bundled entry links to its sample source; no source photographs are bundled and no photo data is sent online. Models without reliable samples remain available through custom input.
