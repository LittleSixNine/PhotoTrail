# PhotoTrail skill 安装与分发

版本：0.1.0。本文件可直接作为面向 agent 的安装入口，也可用于后续独立网页。当前通过 GitHub 仓库分发源码，尚未发布单独的 skill ZIP 下载。

## 能力与环境

- 有定位的照片 → GPX。
- 照片 + GPX → 写入定位的 JPEG/HEIC 副本与 JSON 报告。
- Python 3.11 或更新版本、PATH 中可调用的 ExifTool；没有第三方 Python 依赖。
- 已验证环境：macOS、Python 3.12、ExifTool 13.42。其他操作系统尚未验收。
- Python 使用系统时区数据库；缺失时可使用明确的 `+08:00` 等固定偏移。
- agent 必须能运行本地程序、读取用户指定文件；仅能浏览网页的 agent 无法完成这两个流程。

依赖安装采用用户当前环境的标准方式；不要未经授权改动系统或自动运行远端安装脚本。
ExifTool 安装说明：https://exiftool.org/install.html 。本包不捆绑 ExifTool。

## 安装

1. 从 [PhotoTrail 仓库的 phototrail 分支](https://github.com/LittleSixNine/PhotoTrail/tree/phototrail/skill)取得完整 `skill/` 目录。可将仓库克隆到临时目录后仅复制 `skill/`，安装后不需要保留其余源码；记录获取时的提交号，避免混用不同提交的文件。未来若提供固定版本 ZIP，则下载对应校验文件并核对 SHA-256。
2. 压缩包根目录是 `phototrail/`。把这个完整目录放入目标客户端支持的 skill 目录；从源码安装时，将 `skill/` 复制并命名为 `phototrail/`，使目录名与 SKILL.md 的 name 一致。
3. 不覆盖已有同名安装，除非用户授权更新。保留 LICENSE、脚本、测试及说明。
4. 按客户端要求刷新或重新加载 skills。安装路径、自动发现方式由客户端决定，本文不硬编码通用路径。
5. 执行下列环境检查，成功后再使用照片工作流。

```sh
python3 -B "/absolute/path/phototrail/scripts/phototrail.py" check
```

不需要 PhotoTrail App、Xcode 或仓库中的其他代码。程序不读取 App 收藏、轨迹缓存、钥匙串或 Photos 图库。

## 调用参考

通用输入：`--photos` 后面是一个或多个文件或目录。目录不递归、不含隐藏文件；候选扩展名包含 JPEG、HEIC、PNG、TIFF 及常见 RAW/XMP，实际不支持的项目会报告原因。显式文件不按扩展名推断真实格式。

```sh
# 照片生成 GPX；输出文件不能已存在
python3 -B "/absolute/path/phototrail/scripts/phototrail.py" export-gpx \
  --photos "/absolute/photos" \
  --timezone Asia/Shanghai --output "/absolute/output/photos.gpx"

# 只读匹配预览；输出目录不能已存在
python3 -B "/absolute/path/phototrail/scripts/phototrail.py" geotag \
  --photos "/absolute/photos" --gpx "/absolute/track.gpx" \
  --timezone Asia/Shanghai --time-offset-seconds 120 \
  --output "/absolute/new-output" --dry-run
```

授权范围明确后去掉 `--dry-run` 执行。预览不会创建输出目录，实际执行重新读取照片与轨迹，结果可能因输入变化而改变。

| 参数 | 含义 |
|---|---|
| `--timezone` | EXIF 缺少偏移时的时区；不覆盖已有 EXIF 偏移 |
| `--assume-wgs84` | 仅用于 GPX 导出，明确确认缺少基准标签的照片为 WGS84 |
| `--segment-gap` | 照片导出 GPX 的分段间隔，默认 300 秒 |
| `--time-offset-seconds` | 匹配时加到相机时间上的偏移，默认 0；不改照片时间 |
| `--max-gap-seconds` | 允许插值的相邻轨迹点最大间隔，默认 7200 秒 |
| `--overwrite-existing` | 在副本中替换已有 GPS，默认关闭 |
| `--dry-run` | 只读预览匹配，不写文件 |

照片时间只采用 EXIF DateTimeOriginal，不猜测缺少的拍摄时间。夏令时导致歧义或不存在的本地时间会跳过，需要明确固定 UTC 偏移。
GPX 接受 UTF-8、GPX 1.0/1.1 的 trk/trkseg/trkpt；不把 route/waypoint 或缺少时区的记录当成定时轨迹。

输出目录必须位于源照片目录之外，其父目录已存在。照片副本按原文件名输出；跨输入目录出现重复文件名时拒绝执行。符号链接及包含符号链接的路径不支持，应使用实际路径。

写入前后检查源照片 SHA-256，副本回读核对经纬度、海拔和原时间字段。照片副本中整个 EXIF GPS 组被新结果替换；旧 GPS 时间、方向等不保留。不存在回读通过之外的完整图像质量或全格式兼容性保证。

## JSON 与错误

所有处理结果输出 JSON；实际 geotag 还保存 `phototrail-report.json`。常见 code：

- `missing_time` / `invalid_time` / `missing_timezone` / `ambiguous_time`：时间缺失、无效或歧义。
- `unknown_datum` / `unsupported_datum` / `missing_coordinates`：不能确认有效 WGS84 定位。
- `already_located`：默认保留原 GPS，未生成对应副本。
- `ambiguous` / `unmatched`：轨迹冲突或不在允许匹配的区间。
- `unsupported_format` / `sidecar_present`：不支持此格式或 sidecar 写入。
- `unsupported_xmp_gps`：存在内嵌 XMP GPS，本版不调和 EXIF 与 XMP 两套定位，跳过处理。
- `source_changed` / `verification_failed` / `exiftool_error`：源变化、回读不符或 ExifTool 失败；不保留失败副本。

退出码 0 为全部完成，3 为存在跳过或失败，2 为输入或环境错误，130 为取消。正常取消写入时保留成功项目并输出报告，不执行整批回滚。强制杀进程或设备断电不保证报告完成。

报告包括本地路径、定位及轨迹来源，不应随安装问题报告上传到公共页面。

## 验证与来源

在任意位置执行：

```sh
python3 -B -m unittest discover -s "/absolute/path/phototrail/tests" -v
```

测试图是本次生成的纯色 JPEG/HEIC，不含私人照片。测试在临时目录内写入，并要求 ExifTool 实际参与 JPEG/HEIC 写入和回读。包括脱离源码仓库安装运行的验证。

算法移植参考 PhotoTrail commit `c45635410125916c0846d44c9c4ef8e5b8aba698` 中的 GpxTrackLog/GpxSearch、LocationHelper、PhotoGPXDocument、PhotoCopyExporter。保留根项目 MIT 许可证于 LICENSE。

独立实现的明确差异：无效 GPX 点会断开插值连续性；未标明 GPS 基准必须显式假定；1 米冲突阈值使用球面距离近似，未复制 CoreLocation 的内部测距实现。因此边界数值不承诺与 App 完全相同。

## 后续网页发布

页面发布时提供固定版本 ZIP、对应校验值，以及本文件的安装与使用说明。按实际托管地址添加下载链接，不把尚未发布的 URL 写成可用地址。

这是静态安装页面，不上传照片，不提供在线处理后端。新增特定 agent 安装说明时，应核对其当前官方文档；不需要为每个 agent 维护不同处理代码。
