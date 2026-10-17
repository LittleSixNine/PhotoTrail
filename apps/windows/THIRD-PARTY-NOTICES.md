# Windows development candidate dependency review

This candidate is for local development review. Redistribution clearance remains incomplete; this document is not a substitute for each component's license.

| Component | Exact input / license evidence | Distribution status |
|---|---|---|
| PhotoTrail | repository LICENSE | Project license applies |
| Device catalogue | PhotoTrail cbeccc015c416c6a82d02645eeb6ccfadb8cef99, MetadataDevices.json, copied unchanged | Source provenance retained in entries |
| WebView2 SDK | NuGet Microsoft.Web.WebView2 1.0.4258.31; licenses/WebView2-1.0.4258.31/LICENSE.txt and NOTICE.txt | Exact package notices included |
| WebView2 Evergreen Runtime | System prerequisite, not bundled | [Microsoft distribution guide](https://learn.microsoft.com/microsoft-edge/webview2/concepts/distribution) |
| MapLibre | Existing bundled Web/vendor/LICENSE.txt | Preserve original notice |
| Unicode | Unicode-LICENSE.txt, Unicode License V3 | Preserve original notice |
| ExifTool / bundled Perl | Existing tools/exiftool/exiftool_files/LICENSE and Licenses_Strawberry_Perl.zip | Keep complete existing tool distribution; [ExifTool license](https://exiftool.org/forum/index.php?topic=4002.0) |
| .NET 10 Windows Desktop Runtime | System prerequisite, not bundled | [Runtime licensing](https://github.com/dotnet/runtime/blob/main/LICENSE.TXT) |
| Swift 6.4 / Foundation / ICU / dispatch / Blocks | Fixed DateHost runtime combination | BLOCKED: binary-by-binary upstream notices and redistributable provenance still require verification |
| Microsoft C/C++ runtime DLLs | Existing fixed DateHost combination | BLOCKED: exact redistributable provenance and applicable distribution terms still require verification |

Swift is generally published under Apache 2.0 with Runtime Library Exception ([Swift](https://www.swift.org/about/)); that alone does not establish the license inventory of all DLLs in this particular candidate. No runtime DLLs were replaced to close this gate. Vulnerability assessment is unknown unless a separate report identifies a successful database query, exact package/version coverage and date.
