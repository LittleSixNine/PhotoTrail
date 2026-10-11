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
