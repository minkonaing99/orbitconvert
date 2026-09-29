# Release notes

## Unreleased - rectangular action panels, 2026-09-29

- Replaced former menu UI with a shared rectangular SwiftUI action panel in the main window and a cursor-positioned AppKit panel. Removed obsolete geometry, drawing, and tests.
- Kept image/PDF conversion, compression, file intake, output safety, settings, and Finder drop target. Added valid Convert and Tools groups plus common batch JPEG/PNG and multi-image PDF actions.
- 46 tests pass on Apple Silicon; x86_64 build passes. Full app line coverage is 49.5%, below the 80% target. Live panel keyboard, signed sandbox, and macOS 14 checks remain open.

## Unreleased - PDF conversion and manual compression, 2026-09-29

- Added PDF detection, image-to-PDF, PDF-to-JPEG/PNG, page extraction, and PDF merge through action buttons.
- Added ImageIO JPEG/PNG optimization and PDFKit native rewrite/embedded-image optimization. Candidates must reopen, pass validation, and be smaller before collision-safe publication. Originals remain untouched.
- Added sequential batch optimization with per-file failures, byte savings display, and native Settings for implemented compression/export preferences.
- No third-party dependencies or external processes. Ghostscript was evaluated but not bundled due AGPL/commercial distribution considerations. PDFKit cannot set an exact compressed-PDF DPI or JPEG quality; Replace Original/Undo and signed sandbox verification remain open.
- 48 automated tests pass; x86_64 build passes. Full app line coverage is 50.2%, below the 80% target, mainly from unautomated SwiftUI/AppKit interaction paths.

## Unreleased - supported Finder drop workflow, 2026-09-29

- Compared Finder Sync, Services/Quick Actions, Share extensions, app-owned drop destinations, menu bar entry, and global NSEvent monitoring against public APIs. Documented the limits in [Finder workflow feasibility](finder-integration.md).
- Added an explicitly opened floating drop target. Finder files dropped there use existing inspection and conversion; the first supported file opens the action panel. Started file-provider loading inside the drop callback.
- Added a panel test. All 29 tests pass on Apple Silicon macOS 27.0, and an x86_64 build passes. Full-app coverage is 53.91%, below the 80% target. Live Finder drag, macOS 14, Intel runtime, and signed sandbox behavior remain unverified.

## Superseded - Phase 6 floating interaction, 2026-09-29

- Added a borderless transparent, nonactivating floating NSPanel. Its content was replaced by the current rectangular action panel.
- Added cursor-centered placement clamped to the visible monitor, display-change repositioning, outside-click and Escape dismissal, and reduced-motion-aware fade.
- Added placement and AppKit panel tests. Too-small displays use the main-window actions. Live panel focus, appearance, multi-monitor, and signed sandbox behavior still need manual verification.

## Superseded - Phase 5 in-window interaction, 2026-09-29

- Earlier custom interaction was removed. Current panel uses standard SwiftUI buttons and preserves the conversion service path.

## Unreleased - Phase 4 image conversion, 2026-09-29

- Added ImageIO conversion among PNG, JPEG, HEIC, and TIFF when the encoder is available, with JPEG quality and optional metadata removal.
- Added white flattening for transparent JPEG output, per-file progress and cancellation, and Finder reveal for results.
- Added temporary output and atomic no-overwrite publication with numeric collision suffixes. The app requests an output folder when same-folder saving is denied.
- Sixteen tests passed on Apple Silicon macOS 27.0; an x86_64 build passed. Image conversion service coverage measured 90.3%; full-app coverage measured 42.1% because UI paths are not automated. Signed sandbox behavior and other macOS runtimes remain untested.

## Unreleased - Phase 3 image inspection, 2026-09-29

- Added ImageIO byte-based detection for single-image PNG, JPEG, HEIC/HEIF, and TIFF inputs, including misleading extensions.
- Added bounded, orientation-aware thumbnails; displayed file size, dimensions, content type, optional creation date, and encoder-filtered output options.
- Moved intake and ImageIO inspection to serial background work; kept security-scoped access balanced around reads.
- Seven tests passed for supported formats, corrupt and multi-image files, runtime output availability, thumbnails, and mixed batches; an x86_64 build passed. The user supplied a screenshot of the metadata UI. Conversion remains Phase 4.
- Measured coverage: 81.6% of type service and 44.6% of the app target. Automated UI coverage remains open.

## Unreleased - Phase 2 file intake, 2026-09-29

- Added native Choose Files picker and multi-file drop zone.
- Added provisional UTType image filtering and individual errors for non-file URLs, folders, unreadable or missing files, and non-image files.
- Valid images remain selected when other files in a batch fail; repeated imports do not duplicate selected URLs.
- Two automated tests pass and the x86_64 build succeeds. The user reports the Phase 2 UI works in manual testing. Signed sandbox testing remains open.
- Measured coverage: 91.9% of intake service, 55.0% of the app target; UI callbacks still need automated coverage.

## Unreleased - Phase 1 shell, 2026-09-29

- Added macOS-only SwiftUI app shell with OrbitConvert branding and a clear empty state.
- Set deployment target to macOS 14.0, added a shared Xcode scheme and unit-test target.
- Built, passed one smoke test, and launched the window on Apple Silicon macOS 27.0. An x86_64 build passed.
- File selection, drag/drop, conversion, sandbox write access, macOS 14 runtime, and Intel runtime remain unverified or unimplemented.

## Unreleased - documentation baseline, 2026-09-29

- Recorded product scope, phase boundaries, architecture, internal contracts, conversion policy, sandbox/output safety, persistence, and test plan.
- Confirmed existing repository is a SwiftUI Hello World shell with no converter or tests.
- Recorded configuration gaps: macOS deployment target 27.0, multiplatform target, Swift language mode 5.0, and read-only user-selected access.
- Observed local Xcode 27.0 (27A266a) and Swift compiler 6.4. No build or tests were performed during this documentation-only task.

No application feature is released. Modifier-based action modes and selection-based Finder commands remain deferred.

Related: [product plan](product-plan.md), [testing](testing.md), [README](../README.md).
