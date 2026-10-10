# Settings, track adjustment and rename contract v1

These requirements describe the macOS 0.5.9 implementation. They do not assert a Windows implementation. Native controls may differ; data semantics must match.

| ID | Requirement | Defaults and acceptance |
| --- | --- | --- |
| SET-01 | Metadata text size and spacing | Independent -1 / 0 / 1, both 0; changes immediately. Text delta -2 / 0 / +2 pt. |
| SET-02 | Full tag names | true; hiding retains tag family, tooltip, search, copy and write permissions. |
| SET-03 | Photo list sort persistence | name ascending; stable identifiers name / captured / import and ordered descending flags. Invalid entries fall back to name. |
| SET-04 | Recent search recording and clearing | true; off hides and stops recording, preserves old entries; explicit clear erases only entries; retain existing 3-entry cap. |
| TRK-01 | Fixed time offset | Signed seconds, preserves fractional timestamps, intervals, segments and elevation; untimed points stay untimed; wholly untimed tracks reject nonzero offset. Maximum absolute offset 315576000 s; output years 1–9999. |
| TRK-02 | East / north offset | WGS84 per-point spherical destination: R=6371008.8 m, bearing=atan2(east,north), angle=hypot(east,north)/R. Distance <=100000 m; nonzero spatial correction requires input/output abs(latitude)<85 degrees. Normalize longitude to [-180,180). Reject nonfinite/out-of-range input atomically. |
| TRK-03 | Persistence, restore and output | Preserve source files. Store original and effective snapshots, retain on restart/reimport. One undo per session, explicit source reload for reset. Source geometry/time changes require reset before further adjustment. GPX export creates a new file and reads it back; no overwrites or claims of source extension/style preservation. Time-only changes retain coordinate cache; spatial changes invalidate it. Discard stale conversion and matching results. |
| REN-01 | Processing sort/filter vs result display | Processing sort/filter controls numbering. Result display controls neither numbering nor execution validation. Missing values always last; ties stable. Numbers/dates ordered by value, mixed generic metadata values by number/text category; plain text uses lexical comparison. Natural filename sorting follows OS locale, without claiming identical Unicode collation on all OSes. |
| REN-02 | Manual group order | Keep associated JPG/RAW/XMP grouped. Multi-group moves preserve block order. With input filters, fill only visible positions in the complete order; hidden positions unchanged. Session-only, append new groups; remap identities on rename and recovery. Moving to empty target means end. |

[Machine-readable defaults and expected values](fixtures/settings-track-rename-v1.json) are nonprivate inputs. Track coordinate tolerance is 1e-10 degrees and time tolerance 1e-6 seconds. See `Packages/GpxTrackLog/Tests/GpxTrackLogTests/TrackAdjustmentTests.swift` and `Tests/PhotoTrailTests/SettingsTrackRenameTests.swift` for executable macOS checks. A wholly untimed track cannot use the mixed-track untimed-point case alone.

Track history retains archive version 1 and adds optional `originalLog` alongside effective `log`; absent values read as existing unadjusted history. Sort preference `PhotoTrailPhotoSort.v1` uses JSON descriptors; platform storage locations may differ. Do not copy macOS paths/bookmarks into Windows state. Exported rename schemes add optional `metadataSortTag` and new sort identifiers while keeping old schemes readable. Filters and manual file identities are session state, not scheme data.

Windows handoff should record implementation and actual verification for each ID after pulling the authorized source/document changes. macOS tests do not establish Windows compatibility. No shared geographic framework or new dependency is required.
