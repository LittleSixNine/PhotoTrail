[简体中文](SKILL.zh-Hans.md) · [English](SKILL.en.md) · **繁體中文** · [日本語](SKILL.ja.md) · [한국어](SKILL.ko.md) · [Español](SKILL.es.md) · [Português do Brasil](SKILL.pt-BR.md)

# PhotoTrail Skill 使用指南

獨立工具可從有定位的照片生成 GPX，或用 GPX 為 JPEG/HEIC 副本寫入定位並生成 JSON 報告。無需 Mac App；需要 Python 3.11+、ExifTool，以及能夠訪問本地文件並運行命令的 agent。當前已驗證 macOS。

## 安裝

從同一次提交取得完整 skill 目錄，複製為客戶端支持的 skills 目錄中的 phototrail 文件夾，保留許可證、腳本、測試和說明。不要混用不同提交的文件，也不要未經授權覆蓋現有安裝。

[PhotoTrail / skill](https://github.com/LittleSixNine/PhotoTrail/tree/phototrail/skill) · [ExifTool](https://exiftool.org/install.html)

## 檢查與只讀預覽

把示例路徑和相機時區替換為實際值。輸出目錄必須位於源照片目錄之外且尚不存在，其父目錄必須已存在。預覽不寫文件；明確授權寫入後才能移除 --dry-run。

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

## 數據與結果

不猜測缺失時間，不跨軌跡斷點插值，衝突或不支持格式會跳過。默認保留已有 GPS；不支持 RAW/XMP 寫入或符號鏈接。源文件哈希在寫入前後核對，副本回讀驗證；失敗副本刪除。副本整個 EXIF GPS 組會被替換，不保留舊 GPS 時間和方向。

JSON 鍵、狀態值、錯誤碼和命令參數保持不變。報告包含本地路徑和定位，請勿上傳公共問題頁面。退出碼 0 表示完成，3 表示有跳過或失敗，2 表示輸入或環境錯誤，130 表示取消。正常取消保留成功項目並寫報告；不執行整批回滾。

完整參數與邊界見原始安裝說明；英文詳解也可查閱。

[English: full reference](SKILL.en.md) · [簡體中文：完整安裝說明](../../skill/INSTALL.md)
