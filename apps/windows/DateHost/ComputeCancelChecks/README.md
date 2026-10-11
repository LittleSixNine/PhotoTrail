# Real DateHost computation cancellation checks

This separate WPF check executable compiles the existing production window and source files. `Prepare.ps1` creates a local copy of `DateAdapter.cs` with exactly two passive observation points: the existing `CALC_STARTED:first_item_computed` stderr marker and child exit. Production source, the pinned Swift file, the host executable and wire format remain unchanged. Generated code and binaries are ignored.

```powershell
pwsh -NoProfile -File DateHost/ComputeCancelChecks/Prepare.ps1
dotnet build DateHost/ComputeCancelChecks
dotnet DateHost/ComputeCancelChecks/bin/Debug/net10.0-windows/ComputeCancelChecks.dll <separate-evidence-folder> --adapter
```

Build or reuse the original pinned host in `DateHost/bin` first; keep its full runtime directory. The adapter check sends 3000 independent six-component offsets, cancels immediately on the real marker while stdout is incomplete and the child is alive, checks zero accepted/published results and child cleanup, then verifies a new request. A complete identical legal batch measures the natural computation window. No fake host, sleeping host, queue cancellation or global sequence marker substitutes for this stage proof.

For the WPF check, configure the existing `PHOTOTRAIL_EXIFTOOL`, an isolated `PHOTOTRAIL_THEME_FILE` and `WEBVIEW2_USER_DATA_FOLDER`. Start with one `seed.xmp` in a new evidence folder: XMP-exif:DateTimeOriginal `2024-01-01T00:00:00.123456789-00:00`. Run the same command with `--auto` instead of `--adapter`. It imports the seed through production code, then creates 3000 identical synthetic physical copies and selected rows (not 3000 UI imports), with two existing drafts.

The real marker triggers the actual production cancel button's `Click` event. This is a test event on real WPF controls, **not mouse or user input**. A new preview begins before the canceled request finishes. Phase evidence includes live PID, stdout completion, cancellation, request count 1→2→1→0, child exit, preserved drafts/sources and the correct new result. Observation polling does not pace the host. No save or write to originals occurs.

Without `--auto`, use the actual preview/cancel controls with Computer Use. A click after the child finishes is explicitly recorded as entry validation, not computation-stage proof. Keep these two evidence categories separate; the natural 3000-item window may be shorter than a screenshot round trip. No production test build is packaged or substituted for an accepted candidate.

All inputs must be disposable synthetic files in a new directory. Full phase logs, generated sources and outputs stay local. User acceptance, clean deployment, full historical regression and real-photo throughput are separate tasks.
