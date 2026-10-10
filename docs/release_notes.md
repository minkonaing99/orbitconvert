# Release notes

## Unreleased - Finder Quick Action, 2026-10-10

- Added a native **Compress with OrbitConvert** Finder Quick Action for up to 100 JPEG, PNG, or HEIC/HEIF images.
- Added a compact confirmation window with remembered Keep Both, Replace Original, and Choose Output Folder choices, saved compression preferences, per-file savings, cancellation and Finder reveal.
- Reused existing validated compression, collision-safe output and guarded replacement. The Finder bridge preserves all input attachments and transfers scoped bookmarks rather than raw paths.
- General settings now group everyday choices with short explanations while preserving saved preferences.
- All 133 tests pass; normal Release build and signature verification pass.
- The action may need enabling in macOS Extensions settings. Live installed Finder handoff and sandbox grants remain manual verification items; see [testing](testing.md).


## Unreleased - remove auxiliary floating windows, 2026-10-09

- Removed Floating Drop Target, Floating Actions and their Windows toolbar menu. Add Files, Settings, and main-window drag/drop and action controls remain.
- Deleted floating controllers, panel presentation, placement helpers, event monitors, unused action icons and dedicated tests. Manual worker cancellation remains intact.
- Clipboard result cards, watched folders and saved activity history remain available. Earlier release entries describing floating windows are historical.

## Unreleased - watched-folder layout and activity history, 2026-10-09

- Replaced the split empty layout with a compact, top-aligned folder section and scrollable recent activity. Folder controls and Launch at Login remain available.
- Added View All Activity from Settings and the menu bar. Existing saved watched-folder and clipboard results show date/time, original and final sizes, amount saved, and percentage reduction.
- Reused the existing 200-record local history without changing stored data or original-file handling. Previously unrecorded operations cannot be reconstructed.

## Unreleased - JPEG target size, 2026-10-09

- Added Tools > Compress to Size for single JPEGs and JPEG batches, including the floating panel. Targets use decimal KB/MB and default to 2 MB per file.
- Tries quality reduction first, then aspect-preserving resizing with a 1080-pixel short-edge minimum. Smaller originals keep their dimensions.
- Reports unreachable limits, skips already-small files, and publishes only validated results within the byte limit as separate collision-safe files. No backup or recovery feature is added.
- See [image conversion](image-conversion.md) for limits and [testing](testing.md) for verification.

## Unreleased - manual Resize + Optimize, 2026-10-03

- Added 25%, 50%, 75%, longest-edge 1080/1920 px and custom aspect-fit bounds for JPEG/PNG/HEIC.
- Added a compact options sheet with oriented dimension previews, Balanced/Maximum compression and separate collision-safe `-resized` outputs.
- Preserved originals, PNG alpha and metadata policy; only smaller validated candidates are published. JPEG/HEIC use a single lossy encode through existing encoding facilities.
- Release build and all 115 tests pass. Resize service coverage is 84.97%; whole-app coverage remains below 80%. Installed UI/permission checks and macOS 14/Intel runtime remain manual.
- Automatic watched-folder and clipboard resizing are outside this milestone.

## Unreleased - clipboard optimization and live menu status, 2026-10-01

- Added local clipboard image optimization with 600 ms monitoring, generation-checked writes, SHA256 duplicate protection, ignored applications, and independent pause.
- Reused the sequential background queue and existing image engines. TIFF uses PNG conversion; copied image files produce temporary exports without modifying sources.
- Added rectangular result cards, Copy/Save/Reveal, and bounded in-memory collection with Copy All/Save All/Clear.
- Expanded MenuBarExtra with live jobs, outstanding count, session statistics, recent results, and a full activity window. Fixed collapsed popup sizing.
- Final signed build and signature verification pass. All 87 tests pass with no skips. Full-app coverage is 62.30%, below the 80% target; two existing runtime responsiveness warnings remain.
- Live installed-app screenshot/browser/Finder paste and sandbox permission checks remain manual. NSPasteboard has no atomic conditional replacement; the final cross-process race is documented.

## Unreleased - dedicated PNG optimization, 2026-09-30

- Bundled universal Oxipng 10.2.1 with license notices and sandbox-inheriting signing. PNG manual/batch/watched-folder optimization now uses the dedicated lossless engine.
- Added bounded execution, metadata retention, Apple encoder-cache handling, content-credential protection, and decode/dimension validation.
- 69 tests pass. Signed helper tests and Intel compilation pass. A supplied screenshot measured 42.3% smaller with identical rendered pixels in Balanced mode; this is one sample, not general parity with Clop.

## Unreleased - compact main window, 2026-09-30

- Replaced repeated per-file action cards with compact selectable rows and one shared action area. The large drop zone appears only in the empty state.
- Added a primary Compress button, conversion picker, tools menu, collapsed contextual options, and shared output controls. Floating-window commands and Settings live in the toolbar.
- Batch actions process only checked files, preserve per-file failures and compression totals, and keep combined PDF creation/merge as a single operation.

## Unreleased - watched folders, 2026-09-30

- Added user-selected watched folders with app-scoped bookmarks, FSEvents, per-folder type/preset/original handling, global pause, menu bar status, optional Launch at Login, and local activity history.
- Added sequential automatic JPEG/PNG/HEIC/PDF optimization with temporary-file filtering, stability checks, bounded retries, validation, size checks, same-volume replacement backup/rollback, and Keep Both loop prevention. Existing manual conversion/compression paths remain.
- 61 tests pass on Apple Silicon macOS 27.0.1; x86_64 build passes. Full-app line coverage is 49.36%, below the 80% target. Ad-hoc signed build contains required entitlements. Live signed sandbox, long paused writers, external/cloud volumes, and macOS 14/Intel runtime remain to be checked.

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
