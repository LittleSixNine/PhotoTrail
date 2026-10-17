# Windows x64 portable development candidate

The existing version remains 0.5.10-win.m5. Batch, exact source commit and EXE/DLL/DateHost SHA256 identify each candidate. No installer, signature, release or update channel is approved by this development package.

Use a separate extracted folder and test copies of photos. Prerequisites are Windows 11 x64, .NET 10 Windows Desktop Runtime and WebView2 Evergreen Runtime. The complete existing ExifTool folder and the fixed 38-file DateHost combination must remain beside the application. Do not mix DateHost files between candidates. Missing date host or protocol/source mismatch must fail explicitly; no alternate date core is used.

A development machine with a restricted PATH is only a supplemental isolation check. Clean deployment requires an authorized Windows 11 x64 machine without SDKs: verify application launch, photo import/preview, date edit, explicit save/copy readback, mandatory backup/restore, rename/record restore and offline/online map/track behavior. Missing prerequisites must be diagnosed before declaring deployment passed. Do not install software into a user's daily environment to manufacture this result.

Keep existing preferences, backups, unknown journals and old candidates during manual upgrades. Extract a new version into a new directory. Close the previous instance normally after checking drafts and unapplied input. Do not delete user data during an uninstall rehearsal. First-use, upgrade and uninstall remain unverified until tested on an approved isolated installation chain.

The proposed update direction is manual installation, no automatic downloads. Any future release selector must filter Windows/x64 assets, reject macOS DMG assets, reject equal/older versions, and verify declared byte length and SHA256 before use. There is currently no approved release feed or installer to exercise; these are acceptance requirements, not a claimed implementation. Never use a repository-wide Latest link as a platform selector.

Redistribution remains gated by [the dependency inventory](../THIRD-PARTY-NOTICES.md), clean deployment and SwiftPM/14001. No unknown installer or certificate was acquired. TxF remains required for qualified in-place writes; if the OS cannot provide it, writes fail with backups/drafts retained. [Microsoft TxF guidance](https://learn.microsoft.com/windows/win32/api/winbase/nf-winbase-movefiletransactedw) warns that the API may be unavailable in future Windows versions.
