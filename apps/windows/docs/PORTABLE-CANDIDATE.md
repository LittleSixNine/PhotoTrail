WIN-LAUNCH-CLOSEOUT-20261019：音乐相关功能本次Windows首发暂缓；整份方案保留但不可用，包括已禁用的音乐规则。 动作72—77和音乐专属模板token不提供；旧配置不被删改，拒绝导入／导出／冻结／执行不消费计数，已有记录仍可恢复。照片作者、版权、普通精确元数据和通用照片模板保持。 PRE-REL-MAC-REV-01（ARTIST／artist差额）已确认延期，非首发门；不是FIXED，Mac不改。词性32等其余发行门不因此延期。

## Pre-release review (2026-10-19)

Run `packaging/Test-PortableCandidate.ps1` from PowerShell x64 before workflow testing; it only reads existing files and runtime registrations and writes a new report. Retain its fixed runtime lock beside the script. A failed prerequisite must be resolved through an approved environment, not by mixing DLLs. A successful result is local preflight only.

Portable is the review candidate shape, not a decided production installer. Installer choices remain: separate-folder portable extraction (no uninstall registration), or a per-user installer with explicit settings/backup retention and upgrade rollback tests. No installation, signing or live update source is enabled by this package.

# Windows x64 portable development candidate

The existing version remains 0.5.10-win.m5. Batch, exact source commit and EXE/DLL/DateHost SHA256 identify each candidate. No installer, signature, release or update channel is approved by this development package.

Use a separate extracted folder and test copies of photos. Prerequisites are Windows 11 x64, .NET 10 Windows Desktop Runtime and WebView2 Evergreen Runtime. The complete existing ExifTool folder and the fixed 38-file DateHost combination must remain beside the application. Do not mix DateHost files between candidates. Missing date host or protocol/source mismatch must fail explicitly; no alternate date core is used.

A development machine with a restricted PATH is only a supplemental isolation check. Clean deployment requires an authorized Windows 11 x64 machine without SDKs: verify application launch, photo import/preview, date edit, explicit save/copy readback, mandatory backup/restore, rename/record restore and offline/online map/track behavior. Missing prerequisites must be diagnosed before declaring deployment passed. Do not install software into a user's daily environment to manufacture this result.

Keep existing preferences, backups, unknown journals and old candidates during manual upgrades. Extract a new version into a new directory. Close the previous instance normally after checking drafts and unapplied input. Do not delete user data during an uninstall rehearsal. First-use, upgrade and uninstall remain unverified until tested on an approved isolated installation chain.

The proposed update direction is manual installation, no automatic downloads. Any future release selector must filter Windows/x64 assets, reject macOS DMG assets, reject equal/older versions, and verify declared byte length and SHA256 before use. There is currently no approved release feed or installer to exercise; these are acceptance requirements, not a claimed implementation. Never use a repository-wide Latest link as a platform selector.

Redistribution remains gated by [the dependency inventory](../THIRD-PARTY-NOTICES.md), clean deployment and SwiftPM/14001. No unknown installer or certificate was acquired. TxF remains required for qualified in-place writes; if the OS cannot provide it, writes fail with backups/drafts retained. [Microsoft TxF guidance](https://learn.microsoft.com/windows/win32/api/winbase/nf-winbase-movefiletransactedw) warns that the API may be unavailable in future Windows versions.
