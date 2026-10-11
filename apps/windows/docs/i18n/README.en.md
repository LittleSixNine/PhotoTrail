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
