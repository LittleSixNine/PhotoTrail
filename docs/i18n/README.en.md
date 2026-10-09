[简体中文](../../README.md) · **English** · [繁體中文](../../docs/i18n/README.zh-Hant.md) · [日本語](../../docs/i18n/README.ja.md) · [한국어](../../docs/i18n/README.ko.md) · [Español](../../docs/i18n/README.es.md) · [Português do Brasil](../../docs/i18n/README.pt-BR.md)

<p align="center"><img src="../images/phototrail-icon.png" width="160" alt="PhotoTrail icon"></p>

# PhotoTrail

Organize photo locations, metadata and file names on macOS.

PhotoTrail brings together **track matching, metadata editing and batch renaming**. Add locations from a trip, correct dates and photo details, then apply a consistent naming scheme. Use these workflows together or independently. Some photo-processing capabilities are derived from [GeoTag](https://github.com/marchyman/GeoTag).

| Task | Workflow | Examples |
| --- | --- | --- |
| Add or correct locations | Track matching and maps | Match a trip track, review or adjust locations on a map |
| Complete photo information | Metadata viewing and editing | Correct dates; add credits, keywords and device details |
| Organize file names | Batch renaming | Capture date and sequence; text replacement; paired sidecars |

## Download and requirements

[Download the latest release](https://github.com/LittleSixNine/PhotoTrail/releases/latest) · [Release history](https://github.com/LittleSixNine/PhotoTrail/releases)

Requires **macOS 26 or later**. Packages support Apple silicon and Intel Macs. Current distribution uses an ad-hoc signature and has not completed Developer ID signing or Apple notarization, so macOS may block the first launch.

PhotoTrail is free to use. Downloading updates automatically is a separate option and is off by default. Installation is manual: open the downloaded DMG, quit PhotoTrail, then drag the app to Applications.

## Features

### 1. Track matching and map locations

- **Match photos by time:** import GPX, KML or KMZ with per-point timestamps. Preview matches in the photo list, or use the map sidebar to fill missing locations or explicitly replace existing ones. Matching stays within a recorded segment and its coverage; gaps and conflicting tracks are not silently resolved.
- **Review and adjust on a map:** use Apple Maps or AMap, search, favorite places and photo thumbnail markers. Apply one location to selected photos or drag an individual marker. Confirmed AMap locations are checked and converted to WGS84.
- **Create and export tracks:** generate GPX from located photos and capture times, splitting long gaps into segments. Show, hide, cache and export tracks, or export geotagged photo copies and a verification report to a new folder.

Untimed routes are view-only. Track CSV is not supported; tracks generated from photos export as GPX. KMZ reads root doc.kml or the archive’s only KML, without loading external links or attachments.

Location saves can also write state/province, city, district and the country/code returned by the lookup service. Disable automatic completion in settings or fill missing region fields for already geotagged local photos/XMP from the map tab. Apple Photos still supports only location and date updates through the system interface.

### 2. Metadata viewing and editing

Common and complete fields use the same list and editing controls. Dates identify EXIF, IPTC, XMP or filesystem sources.

- **Inspect and edit fields:** search names, tags or values and browse groups. Titles, descriptions, authors, rights, keywords, dates and devices use suitable editors. See the [device catalog](../DEVICE_CATALOG.md).
- **Batch presets:** arrange assignments, copies and date adjustments; preview before adding pending changes. Create, save, load, delete, import or export JSON presets. Copy one source field to multiple destination fields.
- **Copy and paste fields:** use ⌘C/⌘V or Ctrl+C/Ctrl+V to copy one field’s raw value into multiple writable fields. Edited values appear in orange; saving is still required to write files.
- **Dates and exchange:** choose increase or decrease separately for years, months, days, hours, minutes and seconds. Change a specific date component, set fixed intervals or distribute dates evenly; controlled CSV/XMP exchange and per-photo comparisons remain available.

**Readable fields are not all writable.** Supported JPEG and existing XMP fields depend on source and format. Local JPEG creation and modification times are editable. Structural, calculated and unverified tags remain locked. RAW originals, HEIC and Apple Photos do not expose these new editors; existing date/location tools remain available. See [targets and limits](../BEHAVIOR.md) (Chinese).

### 3. Batch renaming

- **Arrange rules in order:** drag the three-line handle to move the whole card; right-click blank card space to duplicate or delete. Text, dates and sequences use consistent Replace, Add at beginning and Add at end wording.
- **Manage schemes:** five defaults and personal schemes share an editable, deletable list with saving and JSON exchange. Device and city fields have dedicated cards. Editing rules updates the example from the first preview result; it is saved with the scheme. Saved rule cards load collapsed, and unsaved rules do not overwrite a scheme.
- **Review names and conflicts:** the table shows original/final names, related files and conflicts, with an optional intermediate-result column. Numeric conflict suffixes offer 2–5 digits and separator formats. Execution shows central progress and Stop and Restore.

All three tabs share photos and selection, including imports from Rename. The default scope is all imported photos; selected photos are also supported. JPG/RAW/XMP associations remain intact. Removing a photo updates all tabs, supports undo and does not delete the disk file. Photos without local paths cannot be renamed directly. Save pending metadata/location changes first, then review and confirm renaming. Renaming runs separately; execution records restore names only when identity and content match.

### Saving changes

By default, **Save All Metadata** (⌘S) saves pending changes from both tabs, regardless of selection or filters. Its prompt offers confirmation, cancellation, switching to the current tab and hiding future prompts. Choose **Save Current Tab Metadata** in Photos and Saving settings to preserve pending changes from the other tab. Browsing and previews do not write files; local saves follow backup settings, verify results by reading them back and do not recompress pixels. JPG + RAW pairs can share location writes; new fields are not automatically copied to RAW. Apple Photos uses the system interface with a different editing scope.

## Large photo sets and caching

Import estimates the remaining time for the full process; without reliable speed samples it shows that estimation is in progress. Batches of more than 300 photos show a wait notice. Renaming displays global progress and supports stopping and restoring names.

After import and metadata preparation, thumbnails load on demand in the metadata list and location filmstrip, with priority given to the current photo preview. Switching photos and scrolling the filmstrip avoid repeated work. Updates preserve settings, favorites and track caches; thumbnail and metadata-read caches last only for the current session and are rebuilt after reopening.

## Getting started

1. **Import and check:** finish language, backup and map setup, then open or drag in photos. Check capture times and the camera time zone; correct dates in the metadata workspace when necessary.
2. **Add locations:** import GPX/KML/KMZ, select photos, inspect matches and apply reliable results. Without a track, use the map, search or favorites.
3. **Complete photo details:** use common fields for quick edits; switch to complete fields for additional tags and batch tools.
4. **Save together:** review pending changes and click Save All Metadata. AMap requires your own Web JS API Key and securityJsCode; Apple Maps does not require AMap credentials.
5. **Rename files:** choose the scope and rules, check paired files, conflicts and final names, then confirm. Skip this step if names should stay unchanged.

You can use any workflow independently. Generating GPX or exporting geotagged copies does not overwrite the original photos; removing photos from the list does not delete their files. Local-file backups do not cover Photos-library items.

## Languages

The app supports Simplified Chinese, English, Traditional Chinese, Japanese, Korean, Spanish, and Brazilian Portuguese. Choose a language in the first step of setup. Simplified Chinese defaults to AMap; every other language defaults to Apple Maps. You can choose a different map in the map setup step. Existing users keep their selected map.

Change the app language in Settings later. Save your work and reopen PhotoTrail to apply the language to every window and system prompt. Interface language does not change the camera time zone or photo timestamps.

![PhotoTrail language setup](../screenshots/en/setup.png)

## Maps and privacy

AMap locations are converted to WGS84 before application. Changes are written to photos only when you save. Photos taken in mainland China can also have their locations edited correctly.

- Existing photo coordinates without a declared datum are displayed provisionally as WGS84; this does not rewrite their metadata.
- AMap receives search terms and coordinates needed for map display and validation. Photo files are not uploaded.
- Displaying a track without a valid local cache sends its coordinates to AMap in batches for conversion. The track file is not uploaded or modified, and matching continues to use the original WGS84 data.
- AMap keys are stored in the local macOS Keychain. Favorites and track caches stay in the app's local data directory.
- Map labels, search results, and place names depend on the map provider. Seven interface languages do not guarantee seven-language map data.
- Coordinate checks can reduce mistakes from mixing coordinate systems, but cannot verify the original GPS reading or a manually selected point.

## AMap service and charges

You apply for and supply your own AMap developer credentials. Usage beyond your account's free allowance or paid services may incur charges billed by AMap to your developer account. PhotoTrail does not collect those charges. Manage any paid services on AMap's platform. Apple Maps does not require AMap credentials.

## Agent Skill

The independent [PhotoTrail Skill](../../skill/INSTALL.md) works without the Mac app. It can generate GPX from located photos, or match GPX to photos and produce geotagged JPEG/HEIC copies and a report. It requires **Python 3.11+ and ExifTool** and has been verified on macOS. An agent must be able to access local files and run commands; a browser-only chat is insufficient.

See the [English installation and usage guide](SKILL.en.md). Processing is local. The Skill does not access maps, app credentials, or the Photos library, and its current write workflow does not support RAW/XMP. Command names, JSON keys, status values, and error codes remain language-independent.

## Development and acknowledgments

See the [English development guide](DEVELOPMENT.en.md) for building and checks. Source is in `Sources/PhotoTrail/`, local Swift packages in `Packages/`, and tests in `Tests/`.

Thanks to Marco S Hyman for GeoTag and to the ExifTool project. PhotoTrail's original work is covered by the [current license](../../LICENSE); see its [English reference translation](LICENSE.en.md) and [third-party notices](../../THIRD_PARTY_NOTICES.md). Personal and professional use and free redistribution are allowed; charging for software distribution or access requires permission under the applicable license. PhotoTrail is an independent derivative project and is not officially affiliated with Apple or AMap.
