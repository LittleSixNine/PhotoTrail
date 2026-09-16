---
name: phototrail
description: 从本地有定位的照片生成 GPX，或按 GPX 和拍摄时间给 JPEG、HEIC 照片补定位并导出副本。适用于照片轨迹导出、GPX 地理标记和相机时间偏移匹配；不提供地图搜索、Photos 图库或 RAW/XMP 写入。
license: MIT; see LICENSE
metadata:
  version: "0.1.0"
  runtime: "Python 3.11+ and ExifTool; macOS verified"
---

# PhotoTrail

本地执行两个工作流，不上传照片。用本 skill 所在目录下的 `scripts/phototrail.py`；不需要安装 PhotoTrail App。

## 准备

1. 读取用户指定的照片、GPX 范围和输出要求，不自行扩展目录范围。
2. 执行 `python3 -B "<skill目录>/scripts/phototrail.py" check`。缺少依赖时读取 [INSTALL.md](INSTALL.md)，不要临时另写照片处理程序。
3. `--photos` 接受一个或多个文件/目录；目录只读取第一层的照片候选文件。路径作为独立参数传递并正确引用。
4. 照片没有 EXIF 时间偏移时，需要 `--timezone`，例如 `Asia/Shanghai` 或 `+08:00`；不要根据机器时区或文件修改时间猜测。已存在的 EXIF 时间偏移优先于这个后备参数。

## 照片生成 GPX

```sh
python3 -B "<skill目录>/scripts/phototrail.py" export-gpx \
  --photos "/absolute/photos" --timezone Asia/Shanghai \
  --output "/absolute/output/photos.gpx"
```

仅使用有效定位及 `DateTimeOriginal`。缺少 GPSMapDatum 时默认跳过；用户确认未标明基准的照片坐标确实为 WGS84 后，才加 `--assume-wgs84`。此选项不允许使用明确标为其他坐标系的照片。

输出必须是不存在的新文件，父目录已存在。默认时间相隔超过 300 秒分段，可用 `--segment-gap` 调整。没有有效点时不生成空 GPX。照片导出的点线不是连续记录的真实行走路线。

## GPX 补定位并导出副本

```sh
python3 -B "<skill目录>/scripts/phototrail.py" geotag \
  --photos "/absolute/photos" --gpx "/absolute/trip.gpx" \
  --timezone Asia/Shanghai --time-offset-seconds 120 \
  --output "/absolute/new-output" --dry-run
```

这是只读预览。用户需求已明确授权生成副本时，检查结果后去掉 `--dry-run` 执行；不机械重复确认。没有授权或时区、偏移、范围不明确时，只询问影响结果的缺失信息。

- 时间偏移是加到相机时间上的秒数：相机慢两分钟填 `120`，快两分钟填 `-120`。只影响匹配，不改写照片时间。
- `--gpx` 可接多个文件。冲突不自动选轨迹，要求用户明确来源后重试。
- `--max-gap-seconds` 默认 `7200`；只在同一轨迹段内插值，不向外推算。不要把插值结果描述成实测定位或精度保证。
- 已有 GPS 默认跳过；仅明确要求替换时加 `--overwrite-existing`，也只改变输出副本。
- 输出必须是源照片目录之外、尚不存在的新目录；父目录已存在。不同输入目录有同名照片时分批输出。
- 只写 JPEG、HEIC；RAW/XMP、带同名 XMP sidecar 或内嵌 XMP GPS 的照片不在本版写入范围内，避免两套定位信息不一致。
- 写入副本时替换原 EXIF GPS 组，避免残留旧 GPS 时间、方向或海拔；照片拍摄时间保持不变。

## 结果解释

命令在标准输出返回 JSON。`results` 含逐文件状态、`code`、原因和输出路径，匹配结果还含轨迹来源、插值方法及时间距离。实际补定位输出目录包含 `phototrail-report.json`。

退出码：`0` 全部完成（预览则全部可处理）；`3` 有跳过或失败，需要阅读逐文件结果；`2` 输入/依赖错误；`130` 取消。不要将退出码 `3` 误报成全部失败或全部成功。

向用户说明写入或导出的数量、跳过和失败原因、结果位置。`--dry-run` 不能表述成已写入。取消后保留已成功的副本，并报告未完成项；没有整批自动回滚承诺。

报告包含照片路径和坐标，仅保存在用户指定的本地位置。安装不意味着可以上传、发布这些内容。
