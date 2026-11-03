[简体中文](../../README.md) · **English** · [繁體中文](../../docs/i18n/README.zh-Hant.md) · [日本語](../../docs/i18n/README.ja.md) · [한국어](../../docs/i18n/README.ko.md) · [Español](../../docs/i18n/README.es.md) · [Português do Brasil](../../docs/i18n/README.pt-BR.md)

<p align="center"><img src="../images/phototrail-icon.png" width="160" alt="PhotoTrail icon"></p>

# PhotoTrail

Give your photos a sense of place.

PhotoTrail is a free macOS tool for organizing photos. Add locations to camera shots, correct dates and credits, then turn scattered file names into a clear sequence. Import once and use all three workflows together—or just the one you need.

| Your goal | What PhotoTrail offers |
| --- | --- |
| Recover locations | Match a trip track; review and adjust on a map |
| Complete photo details | Correct dates; add authors, copyright and keywords |
| Organize file names | Combine dates, places and sequences; keep related files together |

## Preview

![Photo preview, map and track sidebar](../screenshots/photo-detail.png)

![Metadata editor: photo list, common fields and batch presets](../screenshots/metadata-editor.png)

![Batch renaming: rules and file name previews](../screenshots/batch-rename.png)

## Three ways to organize your photos

### 1. Track matching and map locations

**Keep a record of the journey, even without a GPS camera.**

- **Locate photos from a track:** import timestamped GPX, KML or KMZ, match capture times and preview before applying.
- **Adjust on a map:** use Apple Maps or AMap, search and favorite places, drag markers or set one location for several photos.
- **Turn photos into a track:** generate GPX from geotagged photos, or export geotagged photo copies with a verification report.

Locations can also fill region details such as state and city. Untimed routes are view-only; matching stays within recorded segments and their time coverage.

### 2. Metadata viewing and editing

**Bring dates, credits and copyright into order.**

- **Build once, use from the main view:** edit batch operations in place, with before-and-after comparisons collapsed by default. Save rules as a preset, adjust its parameters in the main view, and apply to every imported photo. Only “Update preset” saves those parameter changes.
- **Find and edit:** search EXIF, IPTC, XMP and other information by name, tag or value; edit common fields in place.
- **Start with a preset:** add an hour, recover capture dates from file names, align date fields (including file creation and modification times) or fill missing author and copyright details.
- **Build a repeatable workflow:** arrange assignments, field copies and time adjustments, then save a preset. Describe filename dates with `YYYY`, `MM`, `DD` and similar tokens—no regular expressions needed.

Edit JPEG, HEIC/HEIF, PNG, TIFF, WebP, AVIF, GIF, PSD/PSB, JPEG 2000 (JP2), JPEG XL, supported RAW and existing XMP individually or in batches. Writable fields vary by format; additional static images can be imported for inspection. See [format support](../FORMATS.md) (Chinese).

### 3. Batch renaming

**Replace camera numbers with names you can recognize.**

- **Handle missing fields:** skip the affected rule and keep the other results by default, or choose to keep the original name in Rename Settings.
- **Name files your way:** combine capture dates, places, devices, text and sequences; drag rules into order.
- **Preview first:** check old names, new names and conflicts for all photos or just a selection.
- **Keep related files together:** handle associated JPG, RAW and XMP files; save schemes and restore previous names from execution records when files are unchanged.

Save pending photo edits before renaming. ExFAT-compatible renaming is supported; folder access and space requirements are covered in the [detailed guide](../BEHAVIOR.md).

## Saving changes

**Preview first. Write when ready.** Browsing, editing and applying presets do not immediately change files; undo is available before saving.

By default, Save All Metadata (⌘S) saves location and field edits together, regardless of selection or filters. Settings can limit saving to the current tab. Local saves follow backup settings and verify results by reading them back, without recompressing pixels. Failed saves retain pending edits.

Apple Photos uses the system interface for location and date updates, with different editing and backup limits. JPG + RAW pairs can share location writes; other metadata is not copied automatically.

## Getting started

1. **Import photos:** open or drag in files; check capture times and the camera time zone.
2. **Add locations:** preview track matches or choose a point on the map.
3. **Complete details:** edit common fields or apply a batch preset.
4. **Save:** review changes and write them; preview and run renaming afterward if needed.

Each workflow works independently. Removing photos from the list does not delete files; exporting copies does not overwrite originals.

## Large photo sets and caching

Import shows progress and estimated time remaining; thumbnails load on demand. Settings, favorites and track caches persist. Thumbnail and metadata-read caches rebuild on the next launch.

## Languages

Supports Simplified Chinese, English, Traditional Chinese, Japanese, Korean, Spanish and Brazilian Portuguese. Change the language in Settings, save your work and reopen the app to apply it.

Initial setup defaults to AMap for Simplified Chinese and Apple Maps for other languages; you can choose either. Interface language does not alter photo times. Map language depends on the provider.

## Download and installation

[Download the latest release](https://github.com/LittleSixNine/PhotoTrail/releases/latest) · [Release history](https://github.com/LittleSixNine/PhotoTrail/releases)

Requires **macOS 14 or later**, on Apple silicon or Intel. Open the DMG, quit PhotoTrail, then drag the app to Applications.

PhotoTrail is free. Current packages have not completed Developer ID signing or Apple notarization, so macOS may block the first launch. Automatic update downloads are off by default; installation is manual.

## AMap service and charges

AMap requires your own Web JS API Key and securityJsCode, stored in the local macOS Keychain. Apple Maps needs no AMap credentials.

AMap bills your developer account for paid services or usage beyond its free allowance. PhotoTrail is free and does not collect map-service fees.

## Coordinates and privacy

- **Photo files stay local.** AMap receives search terms and map-related coordinates. Displaying an uncached track or refreshing its conversion also sends the required track coordinates.
- **Map and photo coordinates are kept distinct.** Confirmed AMap locations are checked and converted to WGS84; new points are limited to validated mainland China locations. Photos without a declared coordinate system are only displayed provisionally as WGS84, not rewritten.
- **Source tracks stay intact.** Map conversion does not change them; time matching uses original WGS84 data. Coordinate checks cannot guarantee the accuracy of GPS readings or selected points.

## Project origins

PhotoTrail began with geotagging camera photos and film scans, then grew to cover metadata and file names. Some photo-processing capabilities derive from [marchyman/GeoTag](https://github.com/marchyman/GeoTag).

## Agent Skill

Use an agent without opening the Mac app. The independent [PhotoTrail Skill](../../skill/) generates GPX from photos or geotags photos from GPX, producing JPEG/HEIC copies and a report while preserving originals.

### Installation

Send this to an agent that can access local files and run commands:

> Read https://raw.githubusercontent.com/LittleSixNine/PhotoTrail/phototrail/skill/INSTALL.md , install the PhotoTrail Skill as instructed, and check the runtime environment.

Requires **Python 3.11+ and ExifTool**; verified on macOS. The Skill does not access map search or Apple Photos, and does not currently write RAW/XMP. See the [English guide](SKILL.en.md) and [parameter reference](../../skill/SKILL.md).

## Development

Requires full Xcode (Swift 6.3+, macOS 26 SDK+), XcodeGen and SwiftLint. See the [English development guide](DEVELOPMENT.en.md) for build, test and configuration instructions, and [behavior and limits](../BEHAVIOR.md) for detailed rules.

## Acknowledgments and license

Thanks to [GeoTag](https://github.com/marchyman/GeoTag) author Marco S Hyman and projects including [ExifTool](https://exiftool.org/).

Personal and professional use and free redistribution are allowed. Charging for distribution or software access requires written permission. See the [license](../../LICENSE), its [English reference translation](LICENSE.en.md) and [third-party notices](../../THIRD_PARTY_NOTICES.md). PhotoTrail is an independent derivative project, not officially affiliated with Apple or AMap.
