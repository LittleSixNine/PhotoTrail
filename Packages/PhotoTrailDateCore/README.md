# PhotoTrailDateCore

The single shared implementation of `MetadataDate` and `MetadataDateError`, using Foundation only. It has no Apple UI, photo I/O, process, or third-party dependencies. Swift tools 6.2 or newer are required to build the package; supported runtime combinations must be verified on each platform.

The algorithm was moved byte-for-byte from ImageData. ImageData retains public typealiases, so existing Mac source callers continue to use `import ImageData`. This changes module ownership, not date calculations or photo saving. This is source compatibility, not a promise of binary compatibility for separately compiled ImageData clients.

Run `swift test --package-path Packages/PhotoTrailDateCore` from the repository root. The tests cover parsing, replacement, six-component offsets, calendar days, sequence and distribution through existing compatibility vectors and boundary cases. The fixture has 19 established expectations and 16 explicitly labeled historical observations; observations must not be silently promoted to new cross-platform behavior requirements.

Windows DateHost continues to export this source file from an exact Git object and verify its SHA-256 before compiling it with the existing host. It does not need ImageData or the entire package dependency graph. The algorithm SHA-256 is `593fa443f634234b81308143d96b0e6bc0373782734d6ba85a69b90c4d153ccc`; the source commit and path must also match the host and adapter identities.

See [the shared contract](../../docs/DATE-CORE-CONTRACT.md) for API, protocol and upgrade boundaries. Windows runtime/deployment validation is independent of Mac test results.
