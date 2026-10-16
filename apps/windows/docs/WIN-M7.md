# WIN-M7 Windows usability and adaptation

Development candidate, pending user acceptance; not a release or full Mac feature equivalence. The three workspaces and established editing/save/rename/restore contracts are preserved.

This stage adds meaningful photo-row and table automation names, settings Escape/initial/return focus through existing close guards, localized generated preset counts and initial save/empty/GPX reason text. At the existing 720×480 minimum with large text, rename results keep readable height with local vertical scrolling and wrapped order notes; map action labels wrap. Models, file names, raw metadata, serialization, date parsing and write protection are unchanged. No new dependency or shared-core change.

Production `d700c3351e05e07f3113a879ab843d6c05116141`. The final same-DLL run comprises seven language suites of47 checks each and M2/M3/M4/M5/M6/M6-r3 affected regressions (50/31/24/43/35/46),13 suites558 assertions. These inspect actual WPF controls, generated visuals, peers and routed guards; they do not certify audible Narrator. Separate Windows-agent native synthetic paths cover two-field apply/undo/copy/reopen, reorder/parameter/freeze-invalidation/execute/record-restore, real map/location-draft/track/GPX, and settings/keyboard/restart. Old stage counts are not inherited.

Actual environment: Windows10.0.26200, .NET10.0.12, system-aware WPF at200% DPI, single3840×2160 physical display. Default logical client1180×700.5 and minimum outer720×480 were observed. English/Chinese and long Spanish, default/large text and light/dark were covered by distinct scenarios. Actual100%/150%, multi-monitor, audible Narrator, true high contrast and clean deployment remain unverified. UIA does not substitute for a screen reader. Version/title remain0.5.10-win.m5/WIN-M5; stage, production commit and SHA identify this candidate.

Copy saves retain session drafts; undo does not undo disk writes. Restore uses only the selected validated record. Existing service, format, interoperability and historic recovery limitations remain. No M8/R11, merge, release or automation was performed.
