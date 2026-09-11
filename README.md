# PhotoTrail

当前版本：**v0.2** · [更新说明](CHANGELOG.md)

按拍摄时间，为照片补上 GPS。支持已有 GPX 轨迹，也能从带 GPS 的照片生成轨迹；写入只发生在照片副本上。

## 为什么做这个工具

相机通过蓝牙配对手机获取 GPS 时，连接常常不稳定，拍回来的照片会缺少位置信息。胶片相机又无法像手机一样，把 GPS 直接写进照片。

我希望照片能否记录位置，不再取决于拍摄设备。无论是数码相机、手机，还是胶片扫描件，都能借助旅行轨迹和拍摄时间，为照片补上它所在的地方。

## 开始之前

- 准备带时间的 GPX 轨迹，或同一行程中带 GPS 的照片。
- 确认目标照片的拍摄时间和时区正确。胶片扫描件需要先补录真实拍摄时间，不能把扫描时间当成拍摄时间。
- 定位精度取决于轨迹密度和时钟准确度；没有足够记录时，工具会跳过无法判断的位置。

## 安装

需要 Python 3.9+ 和 [ExifTool](https://exiftool.org/)，无需安装 Python 第三方包。目前通过命令行使用。

```bash
# macOS
brew install exiftool
# Ubuntu / Debian
sudo apt-get install libimage-exiftool-perl

git clone https://github.com/LittleSixNine/PhotoTrail.git
cd PhotoTrail
```

## 三步使用

将输入照片和轨迹放在 `local-data/` 中；这个目录已被 Git 忽略。以下示例按中国大陆时区运行，`--timezone 8` 只补充照片中缺失的时区。

**1. 准备轨迹。** 已有 GPX 时，将其放到 `local-data/photo_track.gpx`，跳过提取命令。否则，从带 GPS 的照片生成：

```bash
python3 gps_tools.py extract ./local-data/with-gps/ \
  -o ./local-data/ --single-file --timezone 8
```

**2. 查看预览。** 用浏览器打开生成的 HTML，检查轨迹，并比较不同时间阈值。

```bash
python3 gps_tools.py preview ./local-data/photo_track.gpx \
  -o ./local-data/preview.html
```

**3. 写入副本。** 将待处理照片放在 `local-data/photos/`，结果保存到新的 `geotagged/` 目录，源文件保留不变。

```bash
python3 gps_tools.py geotag ./local-data/photo_track.gpx \
  --photos ./local-data/photos/ --timezone 8 -o ./local-data/geotagged/
```

已有 GPS 的照片和需要检查的推理候选默认跳过。检查预览后，可添加 `--allow-inferred` 采用候选位置。输出目录必须尚不存在；写入报告保存在其中的 `geotag-report.json`。

支持 JPEG、PNG、TIFF、HEIC 和部分 RAW 格式，具体可写性取决于 ExifTool。[完整用法与格式列表](docs/usage.md)

## 轨迹如何处理

面向步行，默认间隔 **不超过 15 秒** 的正常记录直接连线；超过 15 秒、且不超过 60 秒时，才尝试推理。更长的间隔和异常位移不会自动补位置。阈值可调，15 秒仍是待实测标定的初始值。

预览和照片处理均在本地完成。道路贴合仍在开发中，目前只能生成离线请求草稿，尚未接入地图匹配结果。

## 开发与许可

运行测试：`python3 -m unittest discover -s tests -v`。示例、阈值参数和只读定位命令见[使用文档](docs/usage.md)。

代码采用 [MIT License](LICENSE)。ExifTool 适用自身许可证，见[第三方说明](THIRD_PARTY_NOTICES.md)。照片、轨迹及处理报告可能包含私人位置，请保留在本地。
