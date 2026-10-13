## 2026-10-13 · Source inspector R02

Common/full views share the metadata model. Configure the fixed 24 defaults by name or technical tag; an explicitly empty list remains empty after restart. The full search and copy retain source roles, namespaces and duplicate identities. Reference rows remain visible when missing, while unread, failed and stale snapshots are marked. Manual reread prepares snapshots in the background, skips drafts or unapplied input, checks identities/revisions/sources before committing, and retains the old snapshot on cancellation or failure. Counts distinguish physical source instances from net draft fields (GPS is one logical field). Explicit copies retain original-session drafts; reread copies have a fresh baseline. Existing XMP write permissions and date-core-v2 remain in force. v2 was accepted as the agent delivery; R02 awaits acceptance. SDK-free deployment, runtime licenses/NOTICE and SwiftPM/14001 remain open. The approved Apple Photos, Apple Maps and Finder-tag platform exceptions do not exempt other Windows features.

> 2026-10-13 · Historical dates now use the pinned shared date-core-v2 projection for photo sorting, rename date sorting/filtering and photo-to-track time conversion. Integer seconds and nanoseconds preserve precision and original date text. Track matching requires an explicit offset, 100 ns representability and platform range; it never invents UTC or rounds. This development candidate awaits acceptance. No-Swift-SDK deployment, runtime licensing/NOTICE and Windows SwiftPM/14001 remain unresolved; not for formal distribution.

> R01b date entries use shared validation. Historical sorting/track projections remain incomplete. R01a development results are accepted; R01b awaits acceptance. Deployment, runtime licensing and SwiftPM limitations remain.

> 2026-10-12: The local metadata preset library supports save-new, update, copy, rename, confirmed deletion and single-preset JSON import/export. Selection loads the editor; Apply is still explicit. Copy/rename/export use the saved content and preserve unsaved edits. Switching and reloading protect pending parameters and offer save/discard/cancel for edited chains; closing defaults to keep editing. Restart restores only the list, with no active preset or unsaved drafts. Empty libraries stay empty; no automatic migration or templates. Library: UTF-8, 1MiB/256 entries; single JSON remains v1, 128KiB/27 operations. Same-session stale writes are refused using a Local mutex and SHA; cross-session/non-cooperating writers are not globally transactional. Implemented and locally verified, awaiting user acceptance. Previous ordered presets were accepted based on Windows agent results. [Format / 用法](../METADATA-PRESETS.md).

> 2026-10-12: Rename schemes now form a persistent local library: create, update, save as, rename, delete, JSON import/export and five initial templates. Examples are independent; unsaved changes offer Save/Discard/Cancel. Restart restores the last saved scheme; an empty library stays empty. Saving schemes never renames photos. Old Windows rules remain readable; new rules require version 2, without Mac interchange. Implemented and verified; awaiting user acceptance. The preceding batch track matching was accepted based on Windows agent validation; earlier limitations remain.

> 2026-10-11: Selected-photo track matching keeps Calculate results → Apply results review. Fill missing locations is the default; advanced options explicitly overwrite existing locations or use only the current loaded track. Each photo uses its effective capture time, including drafts; missing zones and unrepresentable sub-100ns precision are rejected without guessing. Tracks match independently; ambiguity is not resolved by import order. Filtering unsuccessful results changes viewing only. Applying changes successful photos with net changes and supports one batch undo, preserving earlier drafts. All selected photo and participating track sources are checked before committing. CSV Apply only adds drafts; explicit copy save writes files without overwriting. Implemented and verified; awaiting user acceptance. Earlier track and direct-apply batches were accepted based on Windows agent validation; remaining limitations stay open.

> 2026-10-11: Metadata date modes, CSV and ordinary fields now use one Apply to pending drafts. Preset/XMP loading only fills parameters; saving a preset does not save photos. Undo Last Apply restores the complete pre-batch drafts, keeping earlier edits; save/reload expires it. Final all-selection source checks and copy-only saving remain. Implemented and verified; both this batch and tracks await user acceptance. Older notes below retain their historical state.

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


## 2026-10-11

The map page previews/applies signed time and east/north track offsets, undoes the last session adjustment and explicitly reloads the original. Effective/original snapshots persist locally across restarts; changed or missing sources reject matching and further adjustment. GPX export creates a new file and verifies readback, without changing sources or automatically writing photos. Segments, untimed points and elevations remain; time precision is 100ns. Source styles/extensions are not retained. Implemented and verified; awaiting user acceptance.

## Ordered metadata presets

The preset tab composes, edits, deletes and reorders operations for the existing 27 writable XMP fields, with JSON save/load. Loading only fills the chain; apply once to selected drafts, undo the last application, then explicitly save copies. Set, clear, fill missing, text/keyword operations and per-photo field copying are supported. Text append repeats on each application; date algorithms and unknown actions are rejected as a whole. Only a Mac v1 subset is supported, not full interchange.
