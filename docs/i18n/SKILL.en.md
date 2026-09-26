[简体中文](SKILL.zh-Hans.md) · **English** · [繁體中文](SKILL.zh-Hant.md) · [日本語](SKILL.ja.md) · [한국어](SKILL.ko.md) · [Español](SKILL.es.md) · [Português do Brasil](SKILL.pt-BR.md)

# PhotoTrail Skill

The independent Skill creates GPX from located photos, or matches photos to GPX and writes geotagged JPEG/HEIC copies plus a JSON report. The Mac app is not required. Version 0.1.0 is distributed as source; no separate release ZIP is currently available.

Requires **Python 3.11+ and ExifTool** in PATH, with no third-party Python dependencies. Verified on macOS with Python 3.12 and ExifTool 13.42; other systems have not been accepted. The agent needs local file access and command execution. A browser-only chat cannot perform these workflows. Install dependencies through your environment's normal process; see [ExifTool installation](https://exiftool.org/install.html).

## Install and check

Obtain the entire [skill directory](https://github.com/LittleSixNine/PhotoTrail/tree/phototrail/skill) from one repository commit. Copy it as `phototrail/` into your client's supported skills directory and reload skills. Preserve the license, scripts, tests and documentation. Do not overwrite an existing installation without authorization. The installation location depends on the client.

```sh
python3 -B "/absolute/path/phototrail/scripts/phototrail.py" check
```

No Xcode or other repository code is needed. The tool does not read app favorites, track caches, Keychain credentials or the Photos library.

## Workflows

```sh
python3 -B "/absolute/path/phototrail/scripts/phototrail.py" export-gpx \
  --photos "/absolute/photos" \
  --timezone Asia/Shanghai --output "/absolute/output/photos.gpx"

python3 -B "/absolute/path/phototrail/scripts/phototrail.py" geotag \
  --photos "/absolute/photos" --gpx "/absolute/track.gpx" \
  --timezone Asia/Shanghai --time-offset-seconds 120 \
  --output "/absolute/new-output" --dry-run
```

Replace example paths and the camera time zone. `--photos` accepts files or directories. Directory discovery is nonrecursive and excludes hidden files. Candidates include JPEG, HEIC, PNG, TIFF, common RAW and XMP extensions, but unsupported items receive explicit reasons; an explicit file's real format is not assumed from its extension.

Preview is read-only and creates no output directory. After write authorization, remove `--dry-run`; execution rereads inputs, so changed inputs can change results. The output file or directory must not already exist. Put output outside the source photo directory, with its parent already present. Duplicate output names across inputs are rejected. Symbolic links, including links in path components, are unsupported.

| Option | Meaning |
|---|---|
| `--timezone` | Used when EXIF has no UTC offset; does not override an existing offset. |
| `--assume-wgs84` | GPX export only: explicitly accept photos with no datum label as WGS84. |
| `--segment-gap` | GPX segment gap, default 300 seconds. |
| `--time-offset-seconds` | Offset added to camera time for matching, default 0; does not change photo timestamps. |
| `--max-gap-seconds` | Maximum adjacent-point interpolation gap, default 7200 seconds. |
| `--overwrite-existing` | Replace existing GPS in copies, off by default. |
| `--dry-run` | Read-only preview, no file writes. |

Only EXIF DateTimeOriginal is used for capture time. Missing times are not guessed. Ambiguous or nonexistent local times around daylight-saving changes are skipped; supply an explicit fixed UTC offset. System time-zone data is used; if unavailable, use a fixed offset such as `+08:00`.

GPX input accepts UTF-8 GPX 1.0/1.1 `trk/trkseg/trkpt` data. Routes, waypoints and time records without zones are not treated as timed tracks. The write workflow supports JPEG/HEIC copies, not RAW/XMP. Embedded XMP GPS or unsupported sidecars are skipped rather than reconciled.

Source SHA-256 values are checked before and after writing. Copies are reread to verify latitude, longitude, elevation and original time fields. The entire EXIF GPS group in each copy is replaced, so previous GPS time and direction fields are not retained. Readback checks are not a guarantee of complete image quality or compatibility with all formats.

## Results and safety

Commands return JSON; a real geotag run also writes `phototrail-report.json`. Commands, JSON keys, status values and error codes remain language-independent. Common codes cover missing or ambiguous times, unknown datum, existing GPS, conflicting or unmatched tracks, unsupported formats, source changes and failed readback. Failed copies are removed.

Exit codes: 0 means complete; 3 means some items were skipped or failed; 2 indicates input or environment errors; 130 indicates cancellation. Normal cancellation retains successful items and writes a report, without batch rollback. Forced termination or power loss may prevent report completion.

Reports include local paths, locations and track sources. Do not upload them to public issue pages as installation diagnostics.

## Verification and provenance

```sh
python3 -B -m unittest discover -s "/absolute/path/phototrail/tests" -v
```

Tests use generated solid-color JPEG/HEIC fixtures and temporary directories, with actual ExifTool writes and readback. They include operation after installation outside the repository.

The implementation was adapted with reference to PhotoTrail commit `c45635410125916c0846d44c9c4ef8e5b8aba698`. Invalid GPX points break interpolation continuity; unlabeled datums need explicit acceptance; the one-meter conflict threshold uses a spherical distance approximation. Boundary results are not guaranteed to match the app exactly. The independently licensed Skill retains its included license. See the [original installation guide](../../skill/INSTALL.md) for provenance details.
