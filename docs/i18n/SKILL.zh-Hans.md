**简体中文** · [English](SKILL.en.md) · [繁體中文](SKILL.zh-Hant.md) · [日本語](SKILL.ja.md) · [한국어](SKILL.ko.md) · [Español](SKILL.es.md) · [Português do Brasil](SKILL.pt-BR.md)

# PhotoTrail Skill 使用指南

独立工具可从有定位的照片生成 GPX，或用 GPX 为 JPEG/HEIC 副本写入定位并生成 JSON 报告。无需 Mac App；需要 Python 3.11+、ExifTool，以及能够访问本地文件并运行命令的 agent。当前已验证 macOS。

## 安装

从同一次提交取得完整 skill 目录，复制为客户端支持的 skills 目录中的 phototrail 文件夹，保留许可证、脚本、测试和说明。不要混用不同提交的文件，也不要未经授权覆盖现有安装。

[PhotoTrail / skill](https://github.com/LittleSixNine/PhotoTrail/tree/phototrail/skill) · [ExifTool](https://exiftool.org/install.html)

## 检查与只读预览

把示例路径和相机时区替换为实际值。输出目录必须位于源照片目录之外且尚不存在，其父目录必须已存在。预览不写文件；明确授权写入后才能移除 --dry-run。

```sh
python3 -B "/absolute/path/phototrail/scripts/phototrail.py" check

python3 -B "/absolute/path/phototrail/scripts/phototrail.py" export-gpx \
  --photos "/absolute/photos" --timezone Asia/Shanghai \
  --output "/absolute/output/photos.gpx"

python3 -B "/absolute/path/phototrail/scripts/phototrail.py" geotag \
  --photos "/absolute/photos" --gpx "/absolute/track.gpx" \
  --timezone Asia/Shanghai --time-offset-seconds 120 \
  --output "/absolute/new-output" --dry-run
```

## 数据与结果

不猜测缺失时间，不跨轨迹断点插值，冲突或不支持格式会跳过。默认保留已有 GPS；不支持 RAW/XMP 写入或符号链接。源文件哈希在写入前后核对，副本回读验证；失败副本删除。副本整个 EXIF GPS 组会被替换，不保留旧 GPS 时间和方向。

JSON 键、状态值、错误码和命令参数保持不变。报告包含本地路径和定位，请勿上传公共问题页面。退出码 0 表示完成，3 表示有跳过或失败，2 表示输入或环境错误，130 表示取消。正常取消保留成功项目并写报告；不执行整批回滚。

完整参数与边界见原始安装说明；英文详解也可查阅。

[English: full reference](SKILL.en.md) · [简体中文：完整安装说明](../../skill/INSTALL.md)
