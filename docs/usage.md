# 使用文档

[返回 README](../README.md)

详细参数、轨迹规则和进阶命令。以下照片与轨迹路径均为示例；输入文件由使用者自行准备。

## 推理规则

以下是面向步行的可配置初始策略，尚未通过真实行程标定。密集记录仍可能漂移，15 秒不是定位精度保证。

| 条件 | 默认处理 |
| --- | --- |
| 间隔 ≤15 秒，位移 ≤30 米，速度检查通过 | 按照片时间在原始连线上定位，不计算额外曲线、不生成道路请求 |
| 15 秒 < 间隔 ≤60 秒，速度检查通过 | 尝试四点时间参数曲线；上下文不足或曲线过冲时保留线性候选；标为需检查 |
| 60 秒 < 间隔 ≤300 秒 | 待检查，不自动生成中间位置 |
| 间隔 >300 秒，或 GPX 原有分段边界 | 断点，不跨段补线 |
| 短时间内位移过大或速度异常 | 待检查／异常位移，不强制平滑 |
| 至少三个密集点，在相对首点 5 米范围持续 ≥30 秒 | 推测停留，中间时间使用点簇的一个实际观测位置 |

区间还会报告附近采样时间中位数；超过其三倍时提示异常稀疏，但不会绕过硬上限。默认步行速度检查值为 3 米／秒，扣除两端各 10 米的启发式误差余量后判断；这个余量不是设备报告的真实定位精度。

```bash
python3 gps_tools.py analyze ./local-data/track.gpx \
  --infer-after 15 --max-infer-gap 60 --break-after 300 \
  --dense-distance 30 --max-speed 3
```

`infer-after ≤ max-infer-gap ≤ break-after` 必须成立。时间正好等于推理阈值时不进入额外推理。

地图匹配服务通常更适合密集输入，例如 [Mapbox 建议约 5 秒的采样](https://docs.mapbox.com/api/navigation/map-matching/)。这与本工具是否需要补线是不同问题：稀疏区间需要更多判断，却也可能更难匹配道路。不得把“需要推理”当作“可以可靠恢复”。

## 1. 从照片提取 GPX

```bash
python3 gps_tools.py extract ./local-data/with-gps/ -o ./local-data/tracks/ --timezone 8
```

逐张优先使用照片自己的时区。`--timezone` 只用于缺失时区的照片，不覆盖其他照片的有效时区；无法确定时区时报告错误，不把本地时间假装成 UTC。

按**拍摄当地日期**命名文件，轨迹内时间统一存为 UTC。`--single-file` 输出 `photo_track.gpx`。
提取时超过 300 秒的间隔会分为不同 `trkseg`。分析不会重新连接已有分段。
输出 GPX 已存在时拒绝覆盖。无有效 GPS／拍摄时间的记录不进入轨迹，并在总数与有效点数中体现。

## 2. 查看区间分析和离线预览

```bash
mkdir -p ./local-data/reports
python3 gps_tools.py analyze ./local-data/tracks/2026-01-01_track.gpx -o ./local-data/reports/analysis.json
python3 gps_tools.py preview ./local-data/tracks/2026-01-01_track.gpx -o ./local-data/reports/preview.html
```

用浏览器打开 HTML，可比较 5、10、15、30、60 秒阈值，查看区间依据并移动拍摄时间滑块。
预览是离线米制投影示意图，**不加载在线地图、瓦片、CDN 或遥测**。虚线只表示记录之间的缺口；不会为这些区间生成照片坐标。

只接受带时间的 GPX 轨迹点。冲突的重复时间、时间倒退、缺失时区／坐标和重叠轨迹会报错；不会静默排序或跳过错误点后补线。

## 3. 定位照片，先不写入

```bash
# 指定拍摄时刻，必须带时区；可重复使用 --time
python3 gps_tools.py locate ./local-data/track.gpx --time '2026-01-01T10:00:20+08:00'

# 读取整个目标照片目录；结果保存在本地
python3 gps_tools.py locate ./local-data/track.gpx --photos ./local-data/without-gps/ \
  --timezone 8 -o ./local-data/reports/photo-locations.json
```

结果包含坐标、采用方法、原因及 `requires_review`。已有 GPS 的照片跳过。
超出覆盖范围、长断点、异常位移或待检查区间返回“未生成位置”，不会自动外推。
时间与记录点相同则返回原始观测坐标；邻近有异常位移时仍标为需检查。

## 4. 只写入照片副本

```bash
python3 gps_tools.py geotag ./local-data/track.gpx --photos ./local-data/without-gps/ \
  --timezone 8 -o ./local-data/geotagged-copies/
```

输出必须是源目录之外、尚不存在的新目录。保留子目录结构，源照片不修改。
每张副本写入后用 ExifTool 回读验证，结果记录在副本目录的 `geotag-report.json` 中；若没有可写位置，不创建输出目录，报告仍输出到终端。

曲线和稀疏线性候选默认跳过。检查预览后，明确选择采用这些估算位置时才添加 `--allow-inferred`。
即使启用该选项，长断点、异常位移和没有坐标的区间仍不会写入。

支持写入列表：JPG/JPEG、PNG、TIF/TIFF、HEIC、ARW、DNG、NEF、CR2/CR3、RAF；实际可写性还取决于 ExifTool 对具体文件的支持。集成测试使用合成 PNG，未声称已经测试所有 RAW 格式。

## 5. 准备道路匹配请求（不上传）

```bash
python3 gps_tools.py prepare-road-requests ./local-data/track.gpx -o ./local-data/reports/road-requests.json
```

仅为 `infer` 区间创建请求窗口，保留前后最多三个相邻区间的上下文，合并重叠窗口，不跨越待检查区间或断点。
密集轨迹生成零个请求。长窗口按服务的点数上限拆分，并检查秒级时间冲突和距离上限。

草稿采用 [百度轨迹纠偏 API](https://lbsyun.baidu.com/docs/webapi?title=rectify/guide/trackrectify-base) 的步行模式，WGS84 输入，关闭抽稀和中断补偿，不含 API Key，也没有发送动作。
该服务国内返回 GCJ-02；返回数据不能直接交给本地 WGS84 定位或 EXIF 写入。后续接入仍需完成请求授权、真实服务验证、坐标转换误差验证和服务的数据使用条件核对。

## 合成示例与验证

```bash
# 输出目录需尚不存在
python3 examples/synthetic_demo.py ./demo-output/
# 包含合成 GPX、离线 HTML、区间分析和 20 组公式轨迹比较
python3 -m unittest discover -s tests -v
```

合成比较覆盖直行、圆弧、直角转弯和停留，以及 5/10/15/30/60 秒采样。它用于检查算法行为，不代表真实步行准确率，也不能证明 15 秒最优。某些急转弯或未被采样的停留场景中，曲线可能比直线误差更大。

有 ExifTool 时，测试还会生成小型合成图片、写入 GPS 到副本并核对源文件哈希；缺少 ExifTool 时相关集成测试会明确跳过。

## 许可证与数据

项目代码采用 [MIT License](../LICENSE)，作者 LittleSixNine。ExifTool 适用自身许可证，详见 [第三方说明](../THIRD_PARTY_NOTICES.md)。
照片、轨迹、预览、定位报告和道路请求都可能含私人位置，不因项目开源而自动适合公开。
`local-data/` 已被 Git 忽略，适合存放输入文件与处理结果。
