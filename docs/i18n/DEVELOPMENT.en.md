# Developing PhotoTrail

[简体中文](../DEVELOPMENT.md) · **English**

Use full Xcode with Swift 6.2 and a macOS 26 or newer SDK, plus XcodeGen. SwiftLint runs during builds when installed. Map tests require Node.js 20+. Localization checks use Python 3.

From the repository root:

```sh
make build
make test-localization
make test-map
make test-unit
make test-packages
```

`make test` runs the four check groups. `project.yml` is the source of truth; regenerate the Xcode project after configuration changes. Generated projects and build caches are not versioned. A package can be tested separately with `swift test --package-path Packages/Coords`.

Application tests use `PHOTOTRAIL_OFFLINE_TESTS=1` to avoid private favorites, credentials, update downloads and interactive windows. `make test-unit` uses the separate `local.PhotoTrail.Validation` bundle identifier. Unit tests do not establish visual or live-service acceptance.

## Layout

- `Sources/PhotoTrail/`: app, state, photo operations and SwiftUI views.
- `Sources/PhotoTrail/Views/Maps/`: native maps, AMap web bridge and controls.
- `Sources/PhotoTrail/DevAssets/`: Debug previews and test resources, excluded from Release.
- `Packages/`: coordinates, GPX, metadata, ExifTool, image I/O, Photos library access, image state and log viewer packages.
- `Tests/`: app unit tests and separate UI tests.
- `Resources/`: icons, assets and privacy manifest.
- `scripts/`: build versioning and checks.
- `skill/`: independent Python photo/GPX tool.

State management uses the existing external UDF package. No translation service or additional localization dependency is required at runtime.

## Localization

Supported locales are `zh-Hans`, `en`, `zh-Hant`, `ja`, `ko`, `es`, and `pt-BR`. `Localization.swift` negotiates the system preference, persists an explicit app choice and reads bundled strings. English is the unsupported-language fallback. Portuguese variants use the Brazilian Portuguese translation.

The source catalog is `Sources/PhotoTrail/Localizable.xcstrings`. Keep keys stable. Add every supported translation with translator context when adding user-facing text. Use complete messages with positional placeholders, never sentence fragments assembled around dynamic values. Count labels use neutral wording where possible; if adding grammatical plural forms, use native String Catalog plural variations with numeric arguments.

Permission text lives in each `*.lproj/InfoPlist.strings`. Metadata and RunLogView use their own package resources. AMap receives a JSON-encoded text dictionary at document start. Bridge error codes, protocol keys and accepted service-error codes remain invariant; Swift translates codes only for display. Do not localize persisted enum raw values, coordinate formats on the wire, GPX/XML fields, JSON keys, CLI flags or file extensions.

Language changes update onboarding immediately. Save and reopen the app to apply the choice consistently to system menus, dialogs and cached views. Selecting Simplified Chinese in onboarding selects AMap; the other six languages select Apple Maps. Users can then override the map. Registering first-run defaults and changing language in Settings must not overwrite an existing map choice or camera time zone.

Every README has relative links to all seven languages. Update those guides alongside behavior changes. Screenshots use the isolated app with no private photos or credentials. The license source and third-party notices remain authoritative; translations are reference documents.

`LocalizationUITests` runs the seven-language onboarding and settings checks using an isolated bundle identifier and offline launch mode. The Debug-only `-LOCALIZATIONPREVIEW` argument exposes the UI in offline tests. It does not enable private data reads. UI testing requires an interactive macOS session.

## Identity and data compatibility

The app, module, target and scheme are named PhotoTrail. The default `PHOTOTRAIL_BUNDLE_ID` remains `local.GeoTagCN` to preserve the released sandbox. Legacy identifiers, Keychain service names and cache paths participate in migration; do not remove them during renaming. The web bridge is `photoTrail`. Git tags determine the build version.

Behavior, coordinate handling, saving and privacy contracts are recorded in [BEHAVIOR.md (Chinese)](../BEHAVIOR.md). GeoTag v6.0.2 is the upstream base; see the [license](../../LICENSE) and [third-party notices](../../THIRD_PARTY_NOTICES.md).

## Updates

The app reads GitHub's public latest-release endpoint with URLSession. Automatic DMG downloads are optional and off by default. Downloads must match the release asset name and URL and pass size and SHA-256 checks. The app stores the DMG in its sandbox and offers it on a later launch. Installation remains manual: open the image, quit, then drag to Applications. There is no automatic replacement or additional update framework. Offline tests disable checks and downloads.
