# 静态图像与元数据格式支持

PhotoTrail 分别判断文件能否导入、元数据能否读取，以及各类字段能否写入。单张编辑、批量规则、预设、CSV 和字段粘贴共用同一份格式规则；选择多种格式时，不支持的字段会跳过并说明原因。

当前显式接收 108 个静态图像后缀，其中 61 个后缀开放受控字段编辑。后缀包含别名，不代表 108 种不同的图像编码；已有 XMP 侧车仍按其自身支持的字段处理。

## 可编辑的字段类型

| 字段类型 | 文件后缀 |
| --- | --- |
| EXIF、传统 IPTC、XMP | ai、ait、arq、arw、cr2、cs1、dng、eps、epsf、erf、fff、gpr、hdp、iiq、insp、jng、jp2、jpe、jpeg、jpf、jpg、jpm、jpx、jxr、mef、mng、mos、mpo、mrw、nef、nrw、orf、ori、pef、png、ps、psb、psd、psdt、raf、raw、rw2、rwl、sr2、srw、thm、tif、tiff、wdp、x3f |
| EXIF、XMP | avif、cr3、flif、heic、heif、hif、jxl、webp |
| XMP | ciff、crw、gif |

只开放应用已有的受控字段，结构、计算和其他保护字段仍为只读。传统 IPTC（IIM）与 XMP 内的 IPTC Core 信息属于不同的数据块；不支持传统 IPTC 的格式，仍可使用其允许的 XMP 字段。

上述可编辑格式继续支持受控文件创建／修改时间。苹果“照片”图库通过系统接口更新定位与日期，其范围与本地文件不同。

## 可导入读取的其他格式

3fr、bmp、bpg、btf、czi、dc3、dcm、dcr、dib、dic、dicm、dpx、exr、fits、fpf、fpx、hdr、j25、j2c、j2k、jpc、kdc、lfp、lfr、lif、mif、miff、mrc、pbm、pcd、pct、pcx、pgf、pgm、pict、pmp、ppm、psp、pspimage、qif、qti、qtif、rwz、seq、srf、svg、xcf。

这些格式的通用字段保持只读。没有 macOS 图像解码器时，仍可通过 ExifTool 读取可用元数据，但缩略图或大图预览可能不可用。单个文件损坏、加密或使用未支持的变体时，读取也可能失败。

QIF／QTI／QTIF 是当前写入后端的明确限制：可导入读取，暂不开放写入。JPEG 2000 也需区分容器：JP2 等容器可编辑，而 J2C／J2K 等编码流保持只读。

文档、电子书、配置和归档文件不属于本次静态图像扩展范围；不会因第三方软件能接收 PDF、ZIP 等文件，就将其当作照片开放。

## 保存与兼容性

- 单文件先按设置备份，再写入并逐字段回读；失败保留待处理修改，结果未知时要求核对磁盘。不会将进程退出成功直接当成字段保存成功。
- 元数据处理保留图像编码数据；GIF 动画、多页 TIFF、PSD／PSB 图层等仍需保留各自容器内容。复杂文件及原厂软件兼容性不能仅凭扩展名保证。
- JPEG XL 的 Brotli 压缩元数据使用随应用构建的 macOS 原生适配器处理，无需用户安装 Perl 模块或命令行工具。
- RAW 子类型有独立限制，例如旧式 Kyocera RAW、Sigma SD9／SD10 X3F 不获写入后端支持。损坏的 IFD／MakerNotes 或不安全的 IPTC 编码也会阻止写入，不强行绕过。

实际边界和数据保护见[功能与数据约定](BEHAVIOR.md)。
