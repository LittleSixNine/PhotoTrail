# WIN-M6 cumulative qualification

The final development candidate qualifies the exact WIN-M5 s17 production binaries, built from commit `4329eac3235795f660de4a1a159796c01f30d207`. Its displayed version remains `0.5.10-win.m5`; M6 names the cumulative qualification stage, not a rebuilt or released application. No production source changes were needed in M6.

The new `UiChecks --m6-checks` exercises the production WPF dispatcher and real controls: three synthetic JPEGs, two-field direct application, shared selection and drafts across metadata/map/rename/settings, one-step undo, explicit copy-plan cancellation and confirmation, copy reload, retained drafts, expired pre-save undo, session cleanup without deleting copies, two-action rename preview, frozen-plan invalidation, explicit rename and journal restore. Source SHA, 100-ns creation/write times, attributes and ACL must match after restoration. Test inputs and all preferences/history/output directories must be isolated.

Run the checker against the exact candidate DLL rather than treating an ordinary project-reference build as candidate evidence. M6 adds 35 passing assertions to the 1200 assertions and four observations already run against that same production DLL in M5. Counts are evidence, not a product completion percentage. Independent ExifTool and decoded-pixel/non-target metadata comparisons validate the three copies separately.

Native cumulative testing includes multi-field/multi-photo application, retained drafts while navigating, explicit rename refusal with drafts, copy-plan cancellation, confirmation into an isolated output directory, session cleanup with copies retained, narrow metadata/photo/rename views, and restart of the last workspace and selected scheme. Native screenshots and automated WPF assertions are recorded separately.

Actual environment: Windows 10.0.26200.0, .NET 10.0.12, WebView2 155.0.4283.45, ExifTool 13.59, 200% DPI. Default client size is 1180×700.5 DIP; the 720×480 outer minimum gives a 707×444.5 DIP client area. The narrow photo/inspector switch and local field scrolling keep search and editing reachable. Wide-window inspection is supplemental, not the default-window acceptance strategy.

100%/150% DPI, multiple monitors, Narrator/high contrast and clean no-SDK deployment remain unverified. Existing service/license, runtime NOTICE/SwiftPM 14001, format, cross-platform exchange and historical recovery unknown limitations remain. Map adoption still uses the Windows explicit preview/apply/write contract. The development candidate is not approved for distribution or user-accepted M2–M6. M1 acceptance remains limited to its original scope.

Stop after M6 delivery. No mainline merge, PR, tag, release, installer, automation or later stage is implied.
