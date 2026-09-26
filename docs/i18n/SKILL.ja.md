[简体中文](SKILL.zh-Hans.md) · [English](SKILL.en.md) · [繁體中文](SKILL.zh-Hant.md) · **日本語** · [한국어](SKILL.ko.md) · [Español](SKILL.es.md) · [Português do Brasil](SKILL.pt-BR.md)

# PhotoTrail Skill ガイド

位置付き写真からGPXを作成するか、GPXからJPEG/HEICの位置情報付きコピーとJSONレポートを作成します。Macアプリは不要。Python 3.11以降、ExifTool、ローカルファイル操作とコマンド実行が可能なagentが必要です。macOSで検証済みです。

## インストール

同じコミットからskillディレクトリ全体を取得し、クライアントのskillsディレクトリにphototrailとしてコピーします。ライセンス・スクリプト・テスト・説明を保持してください。異なるコミットを混ぜたり、許可なく既存のインストールを上書きしたりしないでください。

[PhotoTrail / skill](https://github.com/LittleSixNine/PhotoTrail/tree/phototrail/skill) · [ExifTool](https://exiftool.org/install.html)

## 確認と読み取り専用プレビュー

例のパスとカメラのタイムゾーンを置き換えてください。出力先は元の写真フォルダの外で、未作成である必要があります。親フォルダは作成済みにしてください。プレビューは書き込みません。書き込みの許可後にのみ--dry-runを外します。

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

## データと結果

不明な日時を推測せず、軌跡の断点を越えて補間しません。競合や非対応形式はスキップします。既存GPSは既定で保持。RAW/XMPへの書き込みとシンボリックリンクは非対応です。元のハッシュを前後で確認し、コピーを再読み込みで検証、失敗したコピーは削除します。コピーのEXIF GPSグループ全体を置き換え、以前のGPS日時や方向は保持しません。

JSONキー・状態値・エラーコード・コマンド引数は言語で変わりません。レポートにはローカルパスと位置が含まれるため、公開の問題報告に添付しないでください。終了コードは0が完了、3がスキップまたは失敗、2が入力・環境エラー、130がキャンセルです。通常のキャンセルでは成功項目とレポートを保持し、一括ロールバックしません。

詳しい引数と制限は英語ガイドまたは元のインストール説明を参照してください。

[English: full reference](SKILL.en.md) · [简体中文：完整安装说明](../../skill/INSTALL.md)
