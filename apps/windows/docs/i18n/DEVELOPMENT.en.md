## R04c focused validation

Use the existing .NET 10 Release win-x64 framework-dependent build and pinned Swift host. UiChecks runs production WPF: --r04c-checks, --r04c-restart and --r04c-scale (1/20/100). Count assertions separately from import observations and distinguish final candidate from early builds. Isolate all synthetic inputs, preferences, history, backups and outputs. The attribute-readback-fault.py wrapper requires existing Python and explicit PHOTOTRAIL_R04C_TEST_PYTHON, PHOTOTRAIL_R04C_FAULT_TOOL, PHOTOTRAIL_R04C_FAULT_TARGET and PHOTOTRAIL_R04C_FAULT_MARKER; it changes only the owned synthetic target after commit, then invokes the real existing ExifTool. Never point it at user photos or historical materials. Restart reuses the same inputs/history. Verify actual FILETIME, raw APEX/IIM, unchanged pixels, source attributes, mixed and time-only restore, v1 compatibility and affected regressions. SDK-free deployment, notices and SwiftPM 14001 remain open. [Contract](../NUMERIC-TIME.md).

> R04b checks: UiChecks `--r04b-checks` / `--r04b-scale`, using isolated approved temporary copies and history only. Preserve raw IIM records and Photoshop resources; verify final EXE controls, ExifTool readback and pixels separately. Reuse the pinned date host and runtime. [Scope](../IPTC-FIELDS.md).

## 2026-10-13 · R03b

R03b reuses ExifTool, PhotoDocument, MetadataCopy and the unchanged date-core-v2 host without new dependencies. UiChecks adds --inplace-checks, --inplace-scale, --inplace-fault-checks and --inplace-restart-checks. Fault runs use a separate source copy; production code contains no injection hooks. A transactional same-byte write acquires the local NTFS isolation lock; the transactional handle rechecks identity and SHA before MoveFileTransacted commits the stage. Microsoft discourages TxF and may remove it in future Windows versions; unavailable transactions reject saving with no unprotected fallback. Only tested fixed local NTFS with ordinary inherited permissions is enabled. Custom ACLs, alternate streams, hard links, reparse points, network volumes, EFS/compressed/sparse targets are refused. Concurrent ACL changes, real power loss and disk exhaustion remain unverified. Durable byte backups and JSONL phase records use Flush(true); no cross-file power-loss atomicity is claimed. Restore preserves the current version and requires real readback and UI adoption. PHOTOTRAIL_INPLACE_HISTORY isolates test records; the default is LocalAppData/PhotoTrail/Windows/InplaceHistory. Record actual final-candidate phase times and process counts at 1/20/100 items; do not adopt Mac concurrency constants.

[Microsoft TxF documentation](https://learn.microsoft.com/en-us/windows/win32/fileio/transactional-ntfs-portal) · [Programming considerations](https://learn.microsoft.com/en-us/windows/win32/fileio/programming-considerations-for-transacted-fileio-)

## R03a save validation

SavePlan and MainWindow.Save reuse existing XMP/copy and date-core-v2 protection. UiChecks `--save-target-checks` covers real targets, field scopes, complete packets, races, failures and production WPF events; `--save-target-scale` measures 1/20/100 files and Dispatcher delays. Each test uses temporary copies and isolated preferences. Fault-injected evidence and the unchanged native candidate flow have separate attribution. The selected-copy action now prepares a summary; checks must confirm ExecuteSavePlan explicitly. Do not substitute an earlier build for final candidate evidence. No in-place saving, SDK installation or system changes.

## 2026-10-13 · Inspector R02 validation

Keep the existing G1 editing/date/save read. A separate JSON `-G1:4 -a -u -s -n` display read preserves families and copy identities with strict SourceFile/count checks. Each batch of at most32 photos has one ordinary and one display ExifTool request (at most64 physical sources). Getters never start ExifTool or DateHost. See the [ExifTool reference](https://exiftool.org/exiftool_pod2.html).

Use Windows.Tests `--inspector-checks`, `--inspector-read-checks` (synthetic response faults only) and the existing `--settings-checks`. Production UiChecks flags: `--inspector-flow-checks`, `--inspector-late-checks`, `--inspector-empty-restart-checks`, `--inspector-scale-checks`; all fixtures/preferences/history/output/WebView locations must be isolated. Scale counts are1/20/100 via PHOTOTRAIL_R02_COUNT. Record actual import/reread durations, ExifTool and DateHost requests, Dispatcher sampling scope and exact production DLL identity. A test hook is distinct from native user input. Release win-x64 remains .NET10 framework-dependent and embeds the public commit; retain the accepted v2 DateHost/runtime bytes. SDK-free deployment, licenses/NOTICE and SwiftPM/14001 remain open.

## 2026-10-13: exact shared projection v2

Historical dates now use the pinned shared date-core-v2 projection for photo sorting, rename date sorting/filtering and photo-to-track time conversion. Integer seconds and nanoseconds preserve precision and original date text. Track matching requires an explicit offset, 100 ns representability and platform range; it never invents UTC or rounds. This development candidate awaits acceptance. No-Swift-SDK deployment, runtime licensing/NOTICE and Windows SwiftPM/14001 remain unresolved; not for formal distribution.

The pinned source is a0299e6f6c956f66ace2b85449b54db5e2eeeee4; full SHA-256 is 15e1f395ac379552b4c43892f6d70321e3c2f0fd6e0dc9d8ccadacc7bb607dc8. Build.ps1 verifies complete Git bytes with the existing 6.4.0 toolchain. Caller/ProjectionChecks covers 38 projection and 35 legacy vectors, strict typed responses and mismatch/cancellation boundaries. UiChecks --projection-workflow-checks exercises the production paths on isolated synthetic XMP/GPX. Date-page calculation adds one grouped project request before commit; getters never start a host. Keep all preferences and output isolated. Event checks and native input have separate provenance.

## 2026-10-12 Rename scheme checks

DateHost/UiChecks adds `--scheme-model-checks` and `--scheme-library-checks`. Isolate `PHOTOTRAIL_RENAME_SCHEMES` as well as existing preferences, journal and WebView paths; use synthetic copies only. Checks cover the local library, strict versioned JSON, stale-state conflicts and production WPF template/freeze/execute/restore behavior. Native management, system dialogs and restart evidence are recorded separately with build identity. Reuse the pinned DateHost binary; do not rebuild Swift. Run relevant date/undo, batch-track and rename recovery regressions without the unrelated historical suite. Mac scheme interchange is unsupported.

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


## Targeted batch missing-value checks (2026-10-11)

Run PhotoTrail.Windows.Tests with --batch-missing-checks. PHOTOTRAIL_TEST_OUTPUT/mac-fixtures contains the three reviewed Mac XMP inputs a.xmp, missing.xmp and c.xmp; each run uses fresh output. Run DateHost/UiChecks with "isolated three-XMP directory --batch-missing-checks" for production WPF, copy save/readback, complete selection guards and settings/rename regression. Keep the pinned DateHost and existing ExifTool; isolate preference, history and WebView2 directories. Native mouse verification is recorded separately. This does not repeat compute-phase timing, historical suites or clean deployment.


## Targeted track adjustment checks (2026-10-11)

Run PhotoTrail.Windows.Tests with --track-adjustment-checks and isolated PHOTOTRAIL_TEST_OUTPUT; set PHOTOTRAIL_TRACK_CONTRACT_FIXTURE to the fixed 73c0640 settings-track-rename-v1.json obtained through Git objects. Coverage includes math/precision/bounds, untimed points, segments, snapshot corruption and failed persistence, source guards, GPX/KML/KMZ exports and cancellation observed after temporary bytes were written.

Run DateHost/UiChecks with "isolated fixture directory --track-adjustment-checks", then a fresh process with --track-restore-checks. Inputs are three synthetic XMPs and a two-segment GPX with four points, one untimed. The production Windows Google page uses a local SDK substitute for deterministic message/cache/framing verification; native mouse and existing OpenFreeMap loading are recorded separately. Isolate PHOTOTRAIL_TRACK_HISTORY, preferences, histories and WebView2; snapshots append .adjustments-v1.json to the history path. Reuse the pinned DateHost. Raw materials/logs/cache/binaries stay local; no full historical suite, performance benchmark or clean deployment.

## Windows batch Apply checks (2026-10-11)

The production WPF checker now has `--batch-direct-checks`, `--batch-late-checks`, `--batch-cancel-checks`, `--batch-performance-checks` (optional `--offset`), `--field-performance-checks`, and `--track-late-failure-checks`. Use isolated synthetic inputs/preferences. The old offset/missing GUI aliases now exercise direct Apply; preview-only GUI checks were retired, while date kernel/adapter checks remain. Separate calculation, final all-source SHA/sidecar verification, UI commit and refresh; count ExifTool/DateHost requests. ApplicationIdle/25ms polling includes observation overhead, not native first-frame latency. Retain cancellation/child-process evidence, copy-save readback and source hashes; full logs/530 inputs stay local. No shared core, protocol or dependency changes.

## Selected-photo track matching checks (2026-10-11)

UiChecks: `--track-batch-checks`, `--track-batch-performance`, `--track-batch-cancel`. Use isolated settings and synthetic copies. Measure matching, both full-source checks, atomic draft commit, synchronous row refresh and separately observed end-to-end latency. Three 530-photo rounds use two 500-point loaded tracks; cancellation uses a real legal 100,000-point GPX after at least one photo completed, before the batch completes. Keep deterministic WPF continuation checks separate from native mouse evidence. No global cache, new matching algorithm, DateHost protocol change, or full historical suite.

## Focused ordered-preset checks

From apps/windows, run `dotnet run --project PhotoTrail.Windows.Tests -- --preset-checks` for ordered operations, current values, type/JSON boundaries and legacy/new fixtures. The existing DateHost/UiChecks harness adds `--ordered-preset-checks` and `--ordered-copy-checks` for production WPF terminal validation, scale measurements, explicit copy saving and ExifTool readback. Supply isolated evidence output and synthetic inputs; profiles, images and full logs stay local. UiChecks does not rebuild the fixed DateHost binary. Record native mouse/keyboard and system dialogs separately from model/WPF event checks.

## Metadata preset library checks

Run `PhotoTrail.Windows.Tests -- --preset-library-checks` and the affected `--preset-checks`. Production UiChecks accepts `--preset-library-checks`, `--library-restore-checks`, `--library-terminal-checks`; `--ordered-copy-checks` now saves and explicitly loads from the library before apply/undo/copy/readback. Always isolate PHOTOTRAIL_METADATA_PRESETS plus existing preference/history/WebView paths and provide native ExifTool. Test corruption and failures only on disposable files. Record native dialogs and two actual processes separately; record the exact candidate DLL SHA. Reuse the fixed DateHost. No performance, map, compute-cancel or deployment rerun.

## Windows R01a: pinned shared date source

The Windows source lock and production expected identity pin commit 63fb9404ec5f0862df90a000f5dd1c4b81509900, Packages/PhotoTrailDateCore/Sources/PhotoTrailDateCore/MetadataDateEdit.swift, SHA-256 593fa443f634234b81308143d96b0e6bc0373782734d6ba85a69b90c4d153ccc. The original bytes, toolchain 6.4.0, date-isolated-v1 and five date modes remain unchanged. Other date entrances are outside R01a. Build.ps1 still exports the fixed Git object, verifies SHA, embeds the complete identity and copies the existing runtime directory. Both old/new host mismatches must reject without publishing partial drafts.

See the [Windows R01a check instructions](../DEVELOPMENT.md#r01a--正式日期来源接入) for shared fixtures (19 expected / 16 observed), protocol checks, real computation cancellation, production WPF copy chains and 1/20/100 phase measurements. Export the pure package from the exact Git object for SwiftPM testing; compiler/runtime failures remain failures, and direct-source checks are not a package-test pass. Keep preference/library/evidence paths isolated and use only public/synthetic copies. A reduced process PATH is supplemental isolation, never proof of a Windows machine without Swift SDK. Runtime/license and clean-deployment gaps remain explicit; no installer, release, protocol upgrade or other date migration is included.

## R01b existing date entries

The four existing XMP date targets, CSV, field clipboard, XMP import/draft export, fixed presets and field-copy receivers now consume the pinned shared normalize operation asynchronously, batched per request. Sync SetDraft refuses nonempty dates; use SetDraftAsync. Structural decoding does not authorize date writes. Intermediate receiver values and fixed no-op parameters are validated before atomic draft publication; copy save revalidates frozen dates.

Historical shared-valid values before 1582-10-15 can be written and used for rename names, but sorting/filtering/track time projections remain incomplete because the unchanged wire exposes no shared calendar/epoch projection. Modern projections follow shared validation; missing offsets are not UTC and sub-tick fractions are not rounded for matching. No independent metadata calendar fallback remains. SDK-free deployment, runtime redistribution clearance and SwiftPM tests remain unresolved. R01b awaits user acceptance.

## R04a metadata validation

`DateHost/UiChecks --r04a-checks` exercises production WPF controls and isolated synthetic copies. `--r04a-scale` uses `PHOTOTRAIL_R02_COUNT` (1/20/100) and records edit/projection, representative JPEG copies, process requests and Dispatcher gaps. Redirect all preference/history environment variables to the test folder. JSONQ preserves string identifiers; UTF-8 values and UserComment encoding require actual readback. Grouped EXIF dates verify all nine component tags; EXIF relocation compares thumbnail payload and JPEG pixels. Full logs and failed draft snapshots stay local. The pinned shared source and DateHost binaries remain unchanged; deployment, NOTICE and SwiftPM gates remain open.
