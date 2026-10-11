> 2026-10-11: The six-component date-page offset now skips confirmed missing timestamps, labels each skip, and disables adding date drafts when all timestamps are missing. Invalid values, read failures and source changes still reject the preview. Implemented and locally verified; pending user acceptance.

> The five date-page modes now use the pinned Swift file for asynchronous previews and qualified drafts, pending user acceptance. Build the host first using [these instructions](../../DateHost/README.md). Other date entry points retain C#; clean deployment and distribution remain unverified.

# PhotoTrail Windows

### Windows development status

The local Windows test build supports 27 common XMP fields, copy-only saving, CSV/XMP exchange, batch dates including filename capture, JPEG/PNG previews and embedded JPEG previews in DNG, maps/tracks and recoverable renaming. Appearance preferences survive restart. OpenFreeMap with MapLibre is the default; Google requires your own key and real API validation remains pending. Full fields, UI translations, more formats and other computers remain unfinished. No formal release. See the [Windows development guide](../../README.md).

Recent track paths are merged between instances in the same Windows session.

GPS clipboard copies coordinates from one photo; preview them for selected targets before adding a GPS draft and saving copies. Altitude, measurement time and regions are excluded.

Camera maker, model, lens and lens serial number are editable as XMP. Existing EXIF equipment fields remain intact; serial numbers preserve leading zeros.

Digitized, created and modified XMP dates are editable independently, using the same strict date format. Batch dates continue to change capture time only.

Seven XMP exposure fields are editable with validated numbers or fractions. Drafts normalize numbers; original EXIF exposure fields remain intact. There are now 27 manual fields.

## 2026-10-11 · Settings and list preferences

Metadata text size and spacing are independent three-level local preferences (default 0). Text changes by ±2pt, converted to ±8/3 WPF DIP; vertical padding is 2/6/10 and minimum row height 30/40/48. Changes apply immediately. Full tag names default on; when off, the source family remains visible and tooltips, accessibility, raw-field search and copying keep the full name. Metadata keys and write scope do not change.

The photo list defaults to filename ascending and offers name, capture time and import order in either direction. Ordered comparators persist as name/captured/import plus descending; unknown entries are skipped and an empty valid sequence falls back to name ascending. Stable ties and selected identities are preserved. List order is separate from rename processing order and frozen plans.

Recent map searches default on, trim whitespace, deduplicate case-insensitively for the current culture, move reused terms to the front and retain at most three. Turning recording off hides history and stops additions without deleting it; re-enabling restores it. Clear removes only search history. Resetting display, sorting and recording defaults retains history, keys, provider and appearance. Choosing history fills the query without networking. Explicit place search uses the existing authorized Google provider and only previews results.

Implemented and targeted checks passed; user acceptance is pending. Live Google search, other display scales and clean deployment remain unverified.

2026-10-11: Rename processing now supports input order, lexical/native natural names, capture/create/modify time, extension, folder, size, camera make/model, city, rating, a metadata tag and manual order. Associated JPG/RAW/XMP files stay grouped under the leader; missing values remain last in either direction, ties are stable, numbers/dates compare by value and mixed metadata by numeric/text category. Sort first, filter groups by any matching member, then number included groups continuously. Filters cover name/path, type, folder, camera, inclusive date bounds, GPS and tag presence; failed reads are not missing fields.

Use the native group list to move one or several groups before a target or to the blank end, or enter an explicit visible position. Filtered moves fill only visible slots; hidden groups stay in place. Alt+Up/Down moves and Ctrl+Z undoes the last move. Order is session-only, appends new groups and preserves identity across rename, partial execution and recovery. Result display sorting/filtering changes neither numbering nor execution scope; moving is restricted to idle processing order with all results visible. Processing changes invalidate the frozen plan. Existing no-overwrite, draft, source hash, cancellation and journal recovery protection remains; newly appearing companions reject execution.

Old Windows version-1 schemes remain readable; optional sort, descending and metadataSortTag are added without filters or manual IDs. There is no default city scheme library to migrate. Photo list sorting remains independent. Implemented and targeted checks passed, including real single/multiple/filtered/end mouse drops and keyboard moves; user acceptance pending. Other DPI, all formats, large workloads and clean deployment remain unverified; prior limitations remain.


## 2026-10-11

Date component replacement and six-component offset skip confirmed missing dates per photo. Unchanged values and zero offsets do not enable Apply because of existing drafts. Invalid parameters, types and changed sources across the entire selection reject the batch. Implemented and verified; awaiting user acceptance.
