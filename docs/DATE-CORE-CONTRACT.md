# Shared date core contract

## Source and API

`Packages/PhotoTrailDateCore/Sources/PhotoTrailDateCore/MetadataDateEdit.swift` is the unique production implementation extracted unchanged from ImageData. Algorithm SHA-256: `593fa443f634234b81308143d96b0e6bc0373782734d6ba85a69b90c4d153ccc` (146 physical lines). Consumers must pin an exact source commit, this path and this SHA; the SHA alone does not identify a compatible host build.

The existing public API remains `MetadataDate` and `MetadataDateError` (`invalidDate`, `missingDate`, `invalidSequence`): text initialization, `date`, `fraction`, `offset`, `displayTimeZone`, `text`, `shifting`, `offsetting`, `addingCalendarDays`, `replacing`, `sequence`, and `distribute`. ImageData exposes the two names through public typealiases. Current Mac callers and source imports are unchanged; independently compiled binaries must be rebuilt.

No-offset metadata remains a wall-clock value; the internal Foundation calculation does not assign a UTC meaning to that metadata. Fractional seconds and explicit offset text are preserved. Existing year/month validity, six-unit order, overflow rejection, historical calendar, sequence and rounded distribution behavior are unchanged. File reading/writing, missing-source classification, parameter validation, draft revisions and UI remain caller responsibilities. The package has Foundation only, no Apple business/UI or external dependencies. A successful Mac test is not proof of Windows Foundation compatibility.

## Existing Windows transport

The existing `date-isolated-v1` identifier and wire DTOs are retained. This document records the already implemented boundary; it does not introduce another protocol, service, cache or C ABI. Windows owns DateHost and the C# process adapter under `apps/windows/`.

One batch uses one process. Input is complete UTF-8 JSON without BOM on stdin, closed after writing; stdout is one complete JSON response. Requests contain `version`, `id`, and `items`; results retain `version`, the compiled `source` triple (`commit`, `path`, `sha256`), request `id`, ordered `results`, `computeMs`, and optional `jobError`. Business errors retain scope/code and are distinct from parameters, transport and process failures. Unknown root/item members, invalid integer tokens, invalid/duplicate IDs, missing/extra/reordered results and source/version mismatches are rejected by the existing boundary. Read failure is not missing data; transport failure must not publish a partial result or invoke an independent fallback algorithm.

Existing host operations are `normalize`, `offset`, `shift`, `calendarDays`, `replace`, `replaceAtomic`, `sequence`, and `distribute`. `replaceAtomic` remains a host adapter operation constructing one final text and validating it with the core; no new core method is introduced. Complete input is not trimmed and rejects CR/LF. Default adapter limits remain 30 seconds per process, 3000 results, 1 MiB each for request/response and 64 KiB diagnostics. These are existing Windows adapter limits, not package-wide product limits. Global sequence/distribution cannot be paged into independent jobs.

R01a retains the accepted five Windows date-page modes only: six-component offset, sequence, atomic component replacement, distribution, and validation after filename extraction. Other field, preset, exchange and rename date entrances remain a later migration. Clear and confirmed-missing semantics stay in the current caller layer.

## Shared fixtures and platform observations

`Packages/PhotoTrailDateCore/Tests/PhotoTrailDateCoreTests/Fixtures/date-core-v1.json` contains 35 synthetic vectors derived from the accepted Windows compatibility record: 19 established `expected` values and 16 historical `observed` values, checked on Mac during extraction. Parameters are strings used by the fixture runner; this is a test schema, not a wire request schema. Operation `parse` maps to host `normalize`, while fixture `sequence.stepSeconds` maps to host `sequence.seconds`.

Windows must rerun the same vectors against its Foundation/toolchain and record actual results separately. A mismatch requires a precise input/output/platform report and preserving the old usable combination; it does not authorize changing the algorithm or converting an observation into a new product decision. Supplemental pure-package tests cover APIs not represented by the original fixture, including offsets and distribution.

## Upgrade and compatibility

The old accepted Windows combination pins source commit `3593051e21e3af2c060a061aeaa888dee24c3bb4`, old path `Packages/ImageData/Sources/ImageData/MetadataDateEdit.swift`, the same algorithm SHA, and host binary SHA `919c9f5bf48723ccb9125e879b57d3a3246e8df79572f4d2d8391b7c5d2c057e`.

For R01a, use the exact extraction commit supplied in the handoff and the new source path. Never pin the ImageData typealias file. Fetch the exact Git object, export original bytes, check SHA, generate the new host identity, build the host, and update the production adapter's expected identity together. Preserve the old candidate. New lock/adapter with old host and old lock/adapter with new host must both fail closed. A rebuilt host binary can have a different SHA although the algorithm bytes are identical; record both identities independently.

Mac extraction verification and Windows acceptance are separate states. At extraction delivery the new Windows host/runtime combination remains unverified. Windows must establish pure-package compatibility, all five production date modes, cancellation/late-result and draft/save protection, packaged runtime identity, runtime-file/license correspondence and an environment without Swift development tools before declaring its R01a combination accepted. Do not remove system SDKs to simulate a clean machine; a reduced PATH is only an isolation check, not a clean deployment result. Keep actual missing-environment or license checks explicitly pending.
