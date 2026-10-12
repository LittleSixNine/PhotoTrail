# PhotoTrailDateCore

The single shared implementation of `MetadataDate` and `MetadataDateError`, using Foundation only. It has no Apple UI, photo I/O, process, or third-party dependencies. Swift tools 6.2 or newer are required to build the package; supported runtime combinations must be verified on each platform.

The algorithm was moved byte-for-byte from ImageData. ImageData retains public typealiases, so existing Mac source callers continue to use `import ImageData`. This changes module ownership, not date calculations or photo saving. This is source compatibility, not a promise of binary compatibility for separately compiled ImageData clients.

Run `swift test --package-path Packages/PhotoTrailDateCore` from the repository root. The tests cover parsing, replacement, six-component offsets, calendar days, sequence and distribution through existing compatibility vectors and boundary cases. The fixture has 19 established expectations and 16 explicitly labeled historical observations; observations must not be silently promoted to new cross-platform behavior requirements.

Windows DateHost continues to export this source file from an exact Git object and verify its SHA-256 before compiling it with the existing host. It does not need ImageData or the entire package dependency graph. The current full source SHA-256 is `15e1f395ac379552b4c43892f6d70321e3c2f0fd6e0dc9d8ccadacc7bb607dc8`; the source commit and path must also match the host and adapter identities.

See [the shared contract](../../docs/DATE-CORE-CONTRACT.md) for API, protocol and upgrade boundaries. Windows runtime/deployment validation is independent of Mac test results.

## Exact date projection

`try MetadataDate(text).projection()` returns a read-only `MetadataDateProjection`: `kind` (`wall` or `instant`), `seconds: Int64`, `nanoseconds: Int32`, and optional `offsetMinutes`. Its numeric basis is 1970-01-01 00:00:00 under the existing Foundation calendar. Explicit offsets (including Z and -00:00) produce an instant; no offset produces a nominal wall-clock coordinate, never UTC. Fractional digits are padded to nine and converted to an integer separately from Foundation's whole-second Date. No fractional timestamp is converted to Double. Projection failure is `MetadataDateProjectionError.unrepresentable`, separate from existing date errors.

The original 146-line, 7533-byte source prefix is unchanged (SHA-256 `593fa443f634234b81308143d96b0e6bc0373782734d6ba85a69b90c4d153ccc`); the appended API changes the full source hash. Existing Mac callers do not call the new API. The 38 projection vectors (31 valid, 7 invalid) come from the unchanged previous core and have explicit reference identity/platform. Historical projections require independent Windows verification. The existing 35 date vectors retain their expected/observed distinction.

The approved Windows transport extension is specified as `date-core-v2` in the shared contract. At this Mac source delivery its Windows host/adapter implementation is still pending; no claim of v2 deployment or Windows acceptance is made.
