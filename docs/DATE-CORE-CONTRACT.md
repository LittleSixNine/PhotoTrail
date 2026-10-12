# Shared date core contract

## Source and API

`Packages/PhotoTrailDateCore/Sources/PhotoTrailDateCore/MetadataDateEdit.swift` is the unique production implementation extracted unchanged from ImageData. Current full-source SHA-256: `15e1f395ac379552b4c43892f6d70321e3c2f0fd6e0dc9d8ccadacc7bb607dc8` (177 physical lines). The original 146-line / 7533-byte algorithm prefix is unchanged, with SHA-256 `593fa443f634234b81308143d96b0e6bc0373782734d6ba85a69b90c4d153ccc`. Projection is appended; consumers must hash the complete file. Consumers must pin an exact source commit, this path and this SHA; the SHA alone does not identify a compatible host build.

The existing public API remains `MetadataDate` and `MetadataDateError` (`invalidDate`, `missingDate`, `invalidSequence`): text initialization, `date`, `fraction`, `offset`, `displayTimeZone`, `text`, `shifting`, `offsetting`, `addingCalendarDays`, `replacing`, `sequence`, and `distribute`. ImageData exposes the two names through public typealiases. Current Mac callers and source imports are unchanged; independently compiled binaries must be rebuilt.

No-offset metadata remains a wall-clock value; the internal Foundation calculation does not assign a UTC meaning to that metadata. Fractional seconds and explicit offset text are preserved. Existing year/month validity, six-unit order, overflow rejection, historical calendar, sequence and rounded distribution behavior are unchanged. File reading/writing, missing-source classification, parameter validation, draft revisions and UI remain caller responsibilities. The package has Foundation only, no Apple business/UI or external dependencies. A successful Mac test is not proof of Windows Foundation compatibility.

## Previous v1 Windows transport (retained baseline)

The existing `date-isolated-v1` identifier and wire DTOs are retained. This document records the already implemented boundary; it does not introduce another protocol, service, cache or C ABI. Windows owns DateHost and the C# process adapter under `apps/windows/`.

One batch uses one process. Input is complete UTF-8 JSON without BOM on stdin, closed after writing; stdout is one complete JSON response. Requests contain `version`, `id`, and `items`; results retain `version`, the compiled `source` triple (`commit`, `path`, `sha256`), request `id`, ordered `results`, `computeMs`, and optional `jobError`. Business errors retain scope/code and are distinct from parameters, transport and process failures. Unknown root/item members, invalid integer tokens, invalid/duplicate IDs, missing/extra/reordered results and source/version mismatches are rejected by the existing boundary. Read failure is not missing data; transport failure must not publish a partial result or invoke an independent fallback algorithm.

Existing host operations are `normalize`, `offset`, `shift`, `calendarDays`, `replace`, `replaceAtomic`, `sequence`, and `distribute`. `replaceAtomic` remains a host adapter operation constructing one final text and validating it with the core; no new core method is introduced. Complete input is not trimmed and rejects CR/LF. Default adapter limits remain 30 seconds per process, 3000 results, 1 MiB each for request/response and 64 KiB diagnostics. These are existing Windows adapter limits, not package-wide product limits. Global sequence/distribution cannot be paged into independent jobs.

R01a retains the accepted five Windows date-page modes only: six-component offset, sequence, atomic component replacement, distribution, and validation after filename extraction. Other field, preset, exchange and rename date entrances remain a later migration. Clear and confirmed-missing semantics stay in the current caller layer.

## Shared fixtures and platform observations

`Packages/PhotoTrailDateCore/Tests/PhotoTrailDateCoreTests/Fixtures/date-core-v1.json` contains 35 synthetic vectors derived from the accepted Windows compatibility record: 19 established `expected` values and 16 historical `observed` values, checked on Mac during extraction. Parameters are strings used by the fixture runner; this is a test schema, not a wire request schema. Operation `parse` maps to host `normalize`, while fixture `sequence.stepSeconds` maps to host `sequence.seconds`.

Windows must rerun the same vectors against its Foundation/toolchain and record actual results separately. A mismatch requires a precise input/output/platform report and preserving the old usable combination; it does not authorize changing the algorithm or converting an observation into a new product decision. Supplemental pure-package tests cover APIs not represented by the original fixture, including offsets and distribution.

## Previous v1 upgrade and compatibility

The old accepted Windows combination pins source commit `3593051e21e3af2c060a061aeaa888dee24c3bb4`, old path `Packages/ImageData/Sources/ImageData/MetadataDateEdit.swift`, the same algorithm SHA, and host binary SHA `919c9f5bf48723ccb9125e879b57d3a3246e8df79572f4d2d8391b7c5d2c057e`.

For R01a, use the exact extraction commit supplied in the handoff and the new source path. Never pin the ImageData typealias file. Fetch the exact Git object, export original bytes, check SHA, generate the new host identity, build the host, and update the production adapter's expected identity together. Preserve the old candidate. New lock/adapter with old host and old lock/adapter with new host must both fail closed. A rebuilt host binary can have a different SHA although the algorithm bytes are identical; record both identities independently.

Mac extraction verification and Windows acceptance are separate states. At extraction delivery the new Windows host/runtime combination remains unverified. Windows must establish pure-package compatibility, all five production date modes, cancellation/late-result and draft/save protection, packaged runtime identity, runtime-file/license correspondence and an environment without Swift development tools before declaring its R01a combination accepted. Do not remove system SDKs to simulate a clean machine; a reduced PATH is only an isolation check, not a clean deployment result. Keep actual missing-environment or license checks explicitly pending.

## Approved exact projection API

`MetadataDate.projection()` returns `MetadataDateProjection` with `kind: MetadataDateProjectionKind` (`wall`, `instant`), `seconds: Int64`, `nanoseconds: Int32`, and `offsetMinutes: Int?`. Types are immutable; only the core method constructs a valid projection. The method uses the existing Foundation Date, requires its whole seconds since 1970 to be exactly representable as Int64, and parses the original fractional digits as integer nanoseconds, padding on the right to nine. It does not add fractional seconds to a Double, round/truncate, or introduce another calendar. New failure `MetadataDateProjectionError.unrepresentable` does not change the three existing MetadataDateError cases.

`instant` means an explicit offset was present, including Z / +00:00 / -00:00; offsetMinutes is the fixed offset in -840...840. `wall` means no offset was supplied and offsetMinutes is absent. Wall seconds use the existing Foundation calendar and 1970-01-01 00:00:00 as a nominal numerical coordinate, never an absolute UTC instant. Consumers retain the time domain. They must not assign a timezone to wall metadata for matching. Existing sorting policy is retained; this API does not invent cross-domain product rules.

The pair represents `seconds + nanoseconds / 1,000,000,000`, where nanoseconds is 0...999999999 even for negative dates: 1969:12:31 23:59:59.123456789Z is (-1, 123456789). Fraction text/length and offset spelling remain independent original metadata. Equal values with .1 and .100000000 have equal projections without rewriting either text. Historical calendar coordinates are taken from the existing core Date; .NET must not reinterpret historical input year/month/day.

`Fixtures/date-projection-v2.json` is a public synthetic fixture with format `phototrail-date-projection-fixture`, version 2, referenceSource/referenceSha256/referencePlatform, and 38 entries with either expected projection or invalidDate. The 31 valid projection references were extracted using the unchanged 63fb9404 core Date; seven invalid inputs preserve its rejection. Negative epoch, equivalent offsets, nine-digit fractions and the 1582 cutover also have independent arithmetic assertions. Historical values must be checked against Windows Foundation, not silently changed on platform mismatch. The older 35 vectors are unchanged, including their expected/observed distinction.

## Approved v2 wire contract (Windows implementation pending)

The new host/adapter version is `date-core-v2`. Existing operation names/calculations and resource limits remain; add `project`, which accepts only id/op/text item members. Full input still rejects CR/LF, is not trimmed and follows the existing byte limit. A project operation parses the text once with MetadataDate and calls projection(). Its successful result is:

```json
{"id":"d1","projection":{"text":"1970:01:01 00:00:00.123456789Z","kind":"instant","seconds":0,"nanoseconds":123456789,"offsetMinutes":0}}
```

The text is the exact validated request input, not reformatted metadata. Wall projection omits offsetMinutes; instant requires it. The projection object has only text/kind/seconds/nanoseconds/offsetMinutes. Seconds uses signed Int64 integer JSON; nanoseconds is an integer 0...999999999; offsetMinutes is an integer in -840...840, equal to the explicit input offset (zero for Z / +00 / -00). Input fraction must agree with nanoseconds. Unknown/missing fields, duplicate properties, non-integer tokens (including decimal/exponent), wrong domains or offset presence/range, unexpected text, and request/result/source mismatches fail closed.

For project, exactly one of projection or error is present and values is absent. For all previous operations, exactly one of values or error is present and projection is absent; previous result cost/order rules remain. Projection failure returns business/projectionUnrepresentable, distinct from business/invalidDate for invalid input. Root version/id/source/results/computeMs/jobError structure is unchanged. Clear/source-state handling remains in the caller, never a project on empty text.

One project item costs one logical result. Existing 30-second, 3000-result, 1-MiB input/output and 64-KiB diagnostic limits remain. Independent project items can use existing resource batching; no partial aggregate result may be applied. Sequence/distribute remain global, not paged. New fields are not encoded into date strings or silently accepted by a v1 adapter.

The v2 source identity pins the new exact extraction commit, the same single source path, and its new complete-file SHA. All Windows callers must use the new version and identity together. The old v1 executable/candidate remains a complete separate combination. v1 client/new host, v2 client/old host, and same-version wrong-source combinations must fail, with no automatic negotiation or fallback. Source commits are supplied in the handoff; this document never refers to its own future commit.

Windows should replace appropriate normalize batches with project to combine validation and projection in one process. Existing date-calculation operations still return values. Their new derived coordinates can use one grouped project pass within the same frozen request before commit; never launch a process per getter/field/photo. Bind exact text/projection to the existing request/source/revision protection and retain original text. Mac existing callers do not consume the new API.

Windows sorting/filtering uses exact pairs (or an exact decimal equivalent) and retains modern ordering, stable ties and missing-value rules. Only instant projects to track time: construct platform time from shared seconds, then add integer ticks only when nanoseconds is divisible by 100 and the final time is within platform range. Otherwise report precision/range insufficiency without rounding, changing the original text or treating it as an invalid date. Track ISO parsing, interpolation and match algorithms are unchanged.

The R01b development combination at ec3e61e7af9bb1d43bca2879ec9f0c736d7735b6 was accepted only for completed scope. Historical derived-time coverage, no-Swift-SDK deployment, complete redistribution evidence and the failed Windows SwiftPM pure-package run remain separate pending items. This Mac source/contract delivery does not validate a new Windows v2 host, Foundation result, candidate or deployment.
