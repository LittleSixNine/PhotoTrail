# PhotoTrail Windows

## Windows prototype

The independent Windows prototype lives in `apps/windows` and uses .NET 10 WPF, WebView2 and an external ExifTool distribution. From that directory run `dotnet build PhotoTrail.Windows/PhotoTrail.Windows.csproj`. See the [Windows development guide](../../README.md) for tool configuration, launch commands, test environment variables, current scope and licenses. The repository’s existing macOS build instructions remain applicable to the macOS application.

## Current Windows checks

Date checks: --date-checks (92) and --date-copy-checks (24 real ExifTool copy/undo checks). Filename capture uses bounded native non-backtracking regular expressions and skips invalid dates. Theme preferences: --theme-checks (34), version 1 with a 4 KiB limit and atomic replacement; detected corrupt files are preserved. PHOTOTRAIL_THEME_FILE may point to an isolated test config. UI mode changes retain hidden date inputs and invalidate old previews. Window.ThemeMode uses the pinned SDK experimental WPF0001 API with a narrowly scoped suppression; verify it again on SDK upgrades. Local 200% light/dark and preference restart tests passed; 150%, narrow windows, high contrast and other machines remain pending.

Map environment creation and control initialization each have a 15-second host wait limit; WaitAsync does not cancel native initialization. Missing-runtime and normal startup paths passed isolated local UI checks; TimeoutException marks the control for replacement on the next retry, reusing browser-exit recovery. UI fault injection and recovery require separate evidence. Fault-test runtime/proxy flags are child-process-only and are not shipped. This change is newer than the r4 candidate.

DNG embedded JPEG previews: --dng-preview-checks (11 real-tool checks) uses existing tool/fixture/output variables; --preview-checks (26) covers the native decoder. Source/preview size limits, source SHA, orientation, no-preview refusal and temporary cleanup are retained. Native process working directories and ASCII output basenames avoid ExifTool output-format tokens in user temporary paths. No RAW development or new decoder package.

Track history: --history-checks now has 38 assertions including four real processes, bounded/corrupt records, lock timeout, abandoned-lock recovery and replacement while a reader finishes its old snapshot. GUI saving runs in the background and awaits the merge. Named mutexes serialize instances in one Windows session; File.Replace preserves the normal Windows file replacement behavior. Restricted sandbox permissions reject replacement, so these checks require normal Windows permissions without ACL/security changes. Multiple UI windows, path aliases and separate sessions remain pending. This increment is newer than r5.

GPS clipboard: --clipboard-checks (47), --gps-clipboard-copy-checks (6 real copies using the existing tool/fixture/output variables), default regression (75). The coordinate-only JSON uses exactly three unique format/latitude/longitude properties, with format PhotoTrail GPS 1. Reject nonfinite/out-of-range coordinates before rounding. UI testing first copies synthetic fixture coordinates, never reads prior user clipboard data. Default-map startup focus and single-target save/undo passed; Google, mixed selections, malformed-text UI and Mac clipboard interoperability remain pending.

Equipment XMP fields reuse --common-fields-checks (55 checks): JPEG and DNG sidecar copies, read-back/clear, original EXIF/pixel/source protection, CSV/preset/clipboard/XMP exchange and length limits. Native copy and undo were verified locally.

--common-fields-checks now runs 82 assertions including additional XMP dates, strict date validation, exact fractions/offsets, JPEG and DNG sidecar round-trips. Existing CSV/preset/clipboard/date checks pass. Native save/read-back/undo was verified; this increment is not yet packaged.

--common-fields-checks now has 212 assertions including exposure ranges, fractions, finite-number/integer checks, normalization and JPEG/DNG sidecar read-back. XMP import accepts numeric JSON only for approved numeric tags. CSV47/preset30/clipboard47/XMP23 regression checks and native seven-field copy/read-back/undo passed locally.

## Pinned Swift host for the date page

Run DateHost/Build.ps1 before building WPF. See [host instructions](../../DateHost/README.md) for existing tool prerequisites, raw Git-object export and SHA verification. Production does not depend on a private experiment or moving HEAD. Local checks passed: 168 isolated assertions, 92 legacy C# date assertions, 67 production draft/copy assertions and 99 real WPF control interactions. These counts are not feature counts. UiChecks runs the actual MainWindow against synthetic XMP and restores its own temporary host fixture. Clean deployment, licensing and distribution remain pending.

## 2026-10-11 · Targeted missing-time offset checks

With the existing PHOTOTRAIL_EXIFTOOL and a separate PHOTOTRAIL_TEST_OUTPUT configured, run `dotnet run --project PhotoTrail.Windows.Tests -- --offset-skip-checks`. The checks use synthetic XMP files and copies, covering mixed/all-missing selections, six-component order, existing/cleared drafts, invalid values and types, read failures, source changes, invalidation, cancellation and copy readback/source hashes. For production WPF controls, run DateHost/UiChecks with `synthetic-folder --offset-skip-checks`: start with three sample-0/1/2.xmp files, the middle timestamp absent, the other timestamps carrying nine fractional digits with -00:00 and one digit with +08:00. User acceptance and Computer Use observations are recorded separately; clean deployment and full historical checks are outside this task.

## Real computation cancellation (2026-10-11)

See [ComputeCancelChecks](../../DateHost/ComputeCancelChecks/README.md). It uses the original host, 3000 independent six-component offsets, the existing first-item-computed stderr marker, incomplete stdout and a live child. Marker-triggered real WPF Button.Click events and Computer Use mouse input are recorded separately. Production sources and the accepted candidate are unchanged. Generated observations stay in the separate check executable; no pacing, fake host or protocol changes. A click after computation completes is not computation-stage evidence.

Targeted settings checks: dotnet run --project PhotoTrail.Windows.Tests -- --settings-checks; node PhotoTrail.Windows.Tests/google-page-checks.cjs. DateHost/UiChecks accepts a synthetic fixture directory followed by --settings-checks or --settings-restore-checks. Isolate PHOTOTRAIL_SETTINGS_FILE, PHOTOTRAIL_SEARCH_HISTORY_FILE, PHOTOTRAIL_THEME_FILE and WEBVIEW2_USER_DATA_FOLDER. Local SDK substitutes exercise production page messages without Google network calls; they do not replace candidate pages. Preferences use bounded JSON reads and atomic local replacement; concurrent instances use last-writer-wins. Native UI observation and user acceptance are separate.

Rename targeted checks: --rename-order-checks, --rename-preset-checks and --rename-execution-checks in PhotoTrail.Windows.Tests. Set PHOTOTRAIL_RENAME_CONTRACT_FIXTURE to the verified fixed contract JSON for common fixtures. DateHost/UiChecks accepts a disposable nine-file JPG/DNG/XMP fixture directory followed by --rename-order-checks. Isolate PHOTOTRAIL_RENAME_HISTORY and preference/WebView paths. Real executor progress triggers partial cancellation/collision and its actual output exercises production context mapping/recovery; it does not establish mouse timing. Computer Use independently verifies actual drops and keyboard shortcuts. No shared Swift rebuild or deployment/performance expansion.
