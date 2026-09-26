[简体中文](../../README.md) · **English** · [繁體中文](../../docs/i18n/README.zh-Hant.md) · [日本語](../../docs/i18n/README.ja.md) · [한국어](../../docs/i18n/README.ko.md) · [Español](../../docs/i18n/README.es.md) · [Português do Brasil](../../docs/i18n/README.pt-BR.md)

<p align="center"><img src="../images/phototrail-icon.png" width="160" alt="PhotoTrail icon"></p>

# PhotoTrail

Add and edit photo locations on macOS.

PhotoTrail is a macOS photo geotagging tool derived in part from [GeoTag](https://github.com/marchyman/GeoTag). It combines Apple Maps and AMap, GPX tracks, photo thumbnail markers, favorite places, and explicit control over saving metadata.

## Languages

The app supports Simplified Chinese, English, Traditional Chinese, Japanese, Korean, Spanish, and Brazilian Portuguese. Choose a language in the first step of setup. Simplified Chinese defaults to AMap; every other language defaults to Apple Maps. You can choose a different map in the map setup step. Existing users keep their selected map.

Change the app language in Settings later. Save your work and reopen PhotoTrail to apply the language to every window and system prompt. Interface language does not change the camera time zone or photo timestamps.

## Preview

![PhotoTrail language setup](../screenshots/en/setup.png)

## Features

- **Map geotagging:** choose a location on Apple Maps or AMap. AMap locations are checked and converted to WGS84 before application.
- **Place search and favorites:** preview a search result before applying it. Save places with names and notes; preview, edit, delete, or apply a favorite.
- **Photo list and map workspace:** filter by location or unsaved state, and sort by import order, capture time, or file name. The photo strip has its own filters, sorting, and a button to return to the current photo.
- **Batch editing and undo:** select photos with Command or Shift, apply one location, or copy, paste, and clear locations. Undo or redo before saving. Removing photos from the list does not delete their files.
- **Conservative GPX matching:** preview matches before application in the photo list. Interpolation stays within a track segment and recorded coverage; conflicting tracks are not silently resolved. The track sidebar can fill missing locations or replace locations for selected photos.
- **Tracks from photos:** create a GPX track using located photos and their capture times. The camera time zone determines UTC output; long gaps create separate segments. Generated tracks are cached locally and can be exported.
- **Track history:** show or hide tracks, view their extent, refresh them, and reuse local conversion caches. Matching always uses original WGS84 track data.
- **Photo markers:** Apple Maps and AMap show local thumbnails of located photos. Show all photos or only the selection, select and drag individual markers, and use edge indicators for selected photos outside the map.
- **Appearance and settings:** light, dark, or system appearance; eleven AMap styles; startup map view; photo backup preferences; optional save summaries.
- **JPG + RAW pairs:** matching files are shown together and both receive location changes when saved.
- **Geotagged copies and reports:** export to a new folder outside the source directory, verify written coordinates, check that source hashes are unchanged, and produce a local JSON report.
- **Metadata editing:** edit capture time and supported metadata with backups and explicit saving. Local files use the bundled ExifTool without recompressing image pixels. Items in Apple Photos use the system Photos interface.

## Download and requirements

Get the latest available package and release notes from [GitHub Releases](https://github.com/LittleSixNine/PhotoTrail/releases). The repository may contain changes not yet included in a released package; check the release notes for language availability.

Requires **macOS 26 or later**. Packages support Apple silicon and Intel Macs. Current distribution uses an ad-hoc signature and has not completed Developer ID signing or Apple notarization, so macOS may block the first launch.

PhotoTrail is free to use. Downloading updates automatically is a separate option and is off by default. Installation is manual: open the downloaded DMG, quit PhotoTrail, then drag the app to Applications.

## Getting started

1. Complete setup: language, photo backups, map service, then confirmation. The language selection immediately translates setup. Some system menus and permission prompts require reopening the app.
2. Open local photos, drag files or folders into the window, or choose items from Photos. Non-image files are skipped; GPX files are imported as tracks.
3. For AMap, supply your own **Web JS API Key** and **securityJsCode** in the AMap settings. You can do this later, or use Apple Maps without an AMap key.
4. Select photos and choose a place on the map, preview a search result, or apply a favorite. Applying a location creates an unsaved change; it does not immediately write the file.
5. Check the result and save. Changes can be undone before saving. Closing with unsaved changes prompts you to continue editing or discard them.

For GPX matching, check the camera time zone first, import the track, select photos, preview matches, and apply the reliable results. Match history is kept for the current session only. The map sidebar offers direct matching for selected photos. Importing or showing a track alone does not geotag photos.

Creating a GPX file or exporting geotagged copies does not overwrite the original photos. Backups of local files do not cover items in the Photos library. Photos-library updates and exported-file metadata are different operations; do not assume all export paths behave identically.

## Maps and privacy

AMap locations are converted to WGS84 before application. Changes are written to photos only when you save. Photos taken in mainland China can also have their locations edited correctly.

- Existing photo coordinates without a declared datum are displayed provisionally as WGS84; this does not rewrite their metadata.
- AMap receives search terms and coordinates needed for map display and validation. Photo files are not uploaded.
- Displaying a track without a valid local cache sends its coordinates to AMap in batches for conversion. The GPX file is not uploaded or modified, and matching continues to use the original WGS84 data.
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
