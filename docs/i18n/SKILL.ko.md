[简体中文](SKILL.zh-Hans.md) · [English](SKILL.en.md) · [繁體中文](SKILL.zh-Hant.md) · [日本語](SKILL.ja.md) · **한국어** · [Español](SKILL.es.md) · [Português do Brasil](SKILL.pt-BR.md)

# PhotoTrail Skill 안내

위치가 있는 사진에서 GPX를 만들거나 GPX를 이용해 위치가 기록된 JPEG/HEIC 사본과 JSON 보고서를 생성합니다. Mac 앱은 필요 없습니다. Python 3.11 이상, ExifTool, 로컬 파일 접근과 명령 실행이 가능한 agent가 필요합니다. macOS에서 검증했습니다.

## 설치

동일한 커밋의 skill 폴더 전체를 가져와 클라이언트의 skills 폴더에 phototrail이라는 이름으로 복사합니다. 라이선스, 스크립트, 테스트와 설명을 보존하세요. 다른 커밋의 파일을 섞거나 허가 없이 기존 설치를 덮어쓰지 마세요.

[PhotoTrail / skill](https://github.com/LittleSixNine/PhotoTrail/tree/phototrail/skill) · [ExifTool](https://exiftool.org/install.html)

## 확인 및 읽기 전용 미리보기

예시 경로와 카메라 시간대를 바꾸세요. 출력 폴더는 원본 사진 폴더 밖에 있어야 하며 아직 존재하지 않아야 합니다. 부모 폴더는 미리 있어야 합니다. 미리보기는 파일을 쓰지 않습니다. 쓰기 허가를 받은 뒤에만 --dry-run을 제거하세요.

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

## 데이터와 결과

누락된 시간을 추측하거나 경로 단절을 넘어 보간하지 않습니다. 충돌 및 지원하지 않는 형식은 건너뜁니다. 기존 GPS는 기본적으로 유지합니다. RAW/XMP 쓰기와 심볼릭 링크는 지원하지 않습니다. 전후 원본 해시를 확인하고 사본을 다시 읽어 검증하며 실패한 사본은 삭제합니다. 사본의 전체 EXIF GPS 그룹이 교체되며 기존 GPS 시간과 방향은 유지되지 않습니다.

JSON 키, 상태값, 오류 코드와 명령 인수는 언어에 따라 바뀌지 않습니다. 보고서에는 로컬 경로와 위치가 있으므로 공개 문제 페이지에 올리지 마세요. 종료 코드 0은 완료, 3은 건너뜀 또는 실패, 2는 입력·환경 오류, 130은 취소입니다. 정상 취소는 성공 항목과 보고서를 유지하며 전체 롤백하지 않습니다.

전체 매개변수와 제한은 영어 안내 또는 원래 설치 안내를 참고하세요.

[English: full reference](SKILL.en.md) · [简体中文：完整安装说明](../../skill/INSTALL.md)
