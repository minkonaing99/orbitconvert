# Testing and validation

## JPEG target size (2026-10-09)

The ad-hoc signed Release suite passes on Apple Silicon: **126 tests, 0 failures, 0 skips**, including 11 new target-size tests. Result bundle: `/tmp/OrbitConvert-target-final.xcresult`. The focused target-size and shared-resize run also passed all 22 tests. Code and pre-commit security review found no blocking issues.

```sh
xcodebuild test -project OrbitConvert.xcodeproj -scheme OrbitConvert -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/OrbitConvert-target-tests ENABLE_TESTABILITY=YES -enableCodeCoverage YES -resultBundlePath /tmp/OrbitConvert-target-final.xcresult
```

Target-size backend coverage is **93.39% (113/121 executable lines)**; shared resize coverage is **86.29% (170/197)**. Whole-app coverage is **64.33% (4498/6992)**, below the repository's 80% target. The new SwiftUI options sheet is not covered by these service tests.

Tests cover measured byte ceilings, repeated filename collisions, unchanged originals and dimensions, already-small inputs, impossible and malformed limits, nonfinite/overflow input, unsupported/corrupt files, invalid destinations, cancellation, metadata removal/preservation, EXIF orientation, action availability and selection dispatch. Real resized JPEG output respects the 1080-pixel short-edge floor; landscape, portrait, square and smaller-source arithmetic is checked. A regression caught cached URL file sizes across repeated encodes; candidate measurements now use fresh filesystem attributes.

An initial sandboxed Xcode invocation failed to launch compiler macro plugins; the successful runs used the normal host environment. Existing runtime service/IOSurface warnings remain. Live options-sheet/floating-panel interaction, installed sandbox permission behavior, large-image memory profiling, macOS 14 and Intel runtime remain unverified. No original replacement, backup or recovery feature is introduced.

## Manual Resize + Optimize (2026-10-03)

The full ad-hoc signed Release test suite passes: **115 tests, 0 failures, 0 skips**, in `/tmp/OrbitConvert-resize-final.xcresult`. A normal Release build also passes at `/tmp/OrbitConvert-resize-release/Build/Products/Release/OrbitConvert.app`.

Strict deep signature verification passes for the normal Release application and bundled helpers. Two existing HEIC-test main-thread responsiveness warnings remain; new async tests explicitly respect MainActor isolation.

After fixing test-only actor annotations, all 11 focused resize/action tests pass again with no actor-isolation compiler warnings. Result bundle: `/tmp/OrbitConvert-resize-focused-final.xcresult`. Production code is unchanged from the full passing suite and normal Release build.

Commands used:

```sh
xcodebuild test -project OrbitConvert.xcodeproj -scheme OrbitConvert -configuration Release -destination 'platform=macOS' -derivedDataPath /tmp/OrbitConvert-resize-verified ENABLE_TESTABILITY=YES -enableCodeCoverage YES -resultBundlePath /tmp/OrbitConvert-resize-final.xcresult
xcodebuild build -project OrbitConvert.xcodeproj -scheme OrbitConvert -configuration Release -derivedDataPath /tmp/OrbitConvert-resize-release
```

An initial Release test run failed because the app module was built without testability. The successful command explicitly enables it; the separate normal Release build uses the unchanged production configuration.

New tests cover resize presets/custom fit, bounds, all eight EXIF orientations with corner-pixel checks, sampled PNG alpha, DPI and metadata policy, HEIC, unchanged originals, existing output collisions, corrupt/unsupported inputs, cancellation, larger-candidate skipping, action availability and two-file selection execution. The action-availability test failed before Resize was implemented. Focused backend tests were written first, although their initial build stopped on concurrent incomplete action switches rather than reaching a test assertion.

Resize service coverage is **84.97% (164/193 lines)**. Whole-app coverage is **59.97% (4,042/6,740)**, below the requested 80% goal; the new options sheet has no automated interaction coverage. No files were excluded. Code and security reviews have no unresolved findings.

Manual installed-app checks remain: options-sheet keyboard behavior, floating-panel invocation, Preview visual comparison, revoked destination permission, large-image memory profiling, macOS 14 and physical Intel runtime. Existing image/PDF conversion, compression, folder watching and clipboard regression tests pass. See [resize behavior](resize-optimization.md).

Status: 87 tests pass on Apple Silicon macOS 27.0.1 with no failures or skips (clipboard milestone, ad-hoc signed). Full-app line coverage is 62.30% (3,429/5,504), below the 80% target. The earlier x86_64 build passed; this milestone was tested on arm64 only. Two existing main-thread responsiveness warnings remain. Signed cross-application clipboard and installed-folder workflows still require manual checks.

The 2026-09-29 Finder drop-target coverage report measured 53.91% (965/1790) of the full app target, below the 80% target. Most SwiftUI/AppKit interaction paths lack automated coverage. Do not treat passing service and panel tests as live Finder drag verification.

## Workflow

For each nontrivial behavior, write and run a failing test, implement the smallest fix, then refactor while green. Documentation and configuration-only work are exempt. Maintain at least 80% measured coverage of executable application code, record the scope and result, and do not exclude difficult code merely to reach the target.

The OrbitConvertTests target and shared scheme were added in Phase 1. Run:

```sh
xcodebuild test -project OrbitConvert.xcodeproj -scheme OrbitConvert -destination 'platform=macOS' -derivedDataPath /tmp/OrbitConvert-tests -enableCodeCoverage YES -resultBundlePath /tmp/OrbitConvert-tests.xcresult
```

Choose a fresh result bundle path for each run. The Phase 1 smoke test passed using this command without `-resultBundlePath`; the local result bundle reported one passed test and zero failures. Signed app testing is required for real sandbox verification.

## Required automated cases

| Area | Evidence |
| --- | --- |
| Detection | Real PNG/JPEG/HEIC/TIFF, misleading extension, unknown TXT, corrupted content |
| Capability | Only available and allowed encoders appear; unavailable HEIC produces clear result |
| Conversion | PNG to JPEG, JPEG to PNG, HEIC to JPEG, PNG to TIFF; reopen output and assert format/dimensions |
| Fidelity | All EXIF orientations, alpha-to-JPEG policy, alpha preservation, DPI/profile and metadata policy |
| Input validation | Non-file URL, folder, missing file, nonfinite/out-of-range quality, multi-frame rejection |
| Naming | Basename, canonical extension, repeated collisions, same-format conversion |
| Output safety | Existing source/destination bytes unchanged; concurrent collision; write failure; temporary cleanup |
| Errors | Decode/encode/write/permission failures map to useful messages |
| Concurrency | Sequential batch results, cancellation before publication, no new output after cancellation |
| Scoped access | Balanced successful starts/stops on success, error, and cancellation |

Generate small deterministic fixtures or commit original test resources with provenance. Tests use temporary directories, never the user's Desktop or Documents. A codec capability skip must be reported; the release matrix must include a machine that actually exercises required HEIC conversion. Lossy JPEG assertions use reasonable pixel tolerance, not byte equality.

Use controlled service failures for deterministic permission tests; chmod alone may not prove signed sandbox denial. Include real signed-app permission tests as well.

## Manual Phase 1-4 checklist

- Build and launch on macOS 14 and the current supported runtime where available; record untested systems.
- Exercise Choose Files, single drop, multiple drop, mixed invalid/valid input, and repeated conversion.
- Verify source-folder permission prompt, alternate folder, denial, read-only destination, and revoked access.
- Open outputs in Preview and compare visible orientation, dimensions, transparency policy, and color.
- Test large images and low disk space; verify responsive UI and bounded thumbnail memory with Instruments.
- Check progress, cancellation, errors, keyboard operation, VoiceOver labels, light/dark appearance.
- Verify Intel separately before claiming Intel support.

## Later gates

Action-panel tests cover grouping conversion and tool actions. AppKit tests cover floating panel Return for its initial action and Escape; Tab-to-another-action, VoiceOver, and reduced motion still need live checks.

Phase 6 placement tests cover multiple monitors, negative origins, and visible-frame edges. Manually check display removal/repositioning, focus, Return/Escape, outside clicks, dark/light appearance, and panel dismissal before claiming the live UI is verified.

Finder drop-target manual checks: open the floating target, switch to Finder, drop one and several supported files, and confirm the first file opens the rectangular action panel near the pointer. Check an unsupported file, a corrupted image, an off-screen existing scroll position, target close/reopen, multiple displays, and source/output grants in a signed sandbox build. Confirm the target never claims to appear automatically when a Finder drag starts.

PDF/compression automated cases now include PDF recognition, page count, 150-DPI output dimensions, rotated page export, visible annotation rendering, extraction/merge with selectable text, corrupt PDF rejection, image-to-PDF page count, PNG lossless pixel equivalence, JPEG original preservation, rejection of Lossless JPEG, PDFKit rewrite text preservation, no-reduction policy, savings arithmetic, and a batch with one missing file. A manual PDF matrix remains: linked and bookmarked documents, scanned/image-heavy files, interactive widgets, transparency, EXIF orientation, complex outlines, and large page counts. Image-to-PDF visual layout and metadata should be compared in Preview. Manual-action replacement/Undo and exact PDF compression DPI remain unimplemented, so related tests are deferred. No test uses Desktop or Documents.

Watched-folder tests cover FSEvents delivery, bookmark-backed settings persistence, new-files-only startup, the Optimize Existing choice, Keep Both loop prevention, package exclusion, temporary names, symlinks, file stability, HEIC encoder availability, larger candidate rejection, changed-source rejection, JPEG replacement, PDF replacement, and forced post-swap rollback. The full run used `CODE_SIGNING_ALLOWED=NO`, so it does not prove sandbox access after installation. Manual signed checks: add a folder through NSOpenPanel, restart, copy JPEG/PDF/HEIC and a browser-style partial download, verify same-name smaller replacement, pause/resume, remove/relink, test an external/cloud volume, and inspect Trash/Keep Both. A writer paused longer than the quiet period can still resume later; test the actual producer apps before relying on automatic replacement. Test 50 simultaneous files and a read-only destination without using personal Desktop/Documents folders.

Before each implementation milestone report build command/result, tests/coverage, manual checks, and remaining limitations. Before committing, perform a security review. Do not claim a build or test passed unless executed successfully.

Related: [roadmap](product-plan.md), [conversion](image-conversion.md).

Compact-window regression checks cover common action intersection, selected-file-only execution, one ordered PDF merge per selection, continued processing after a per-file failure, and fitting two selected files in a 620 x 460 window. Test-host snapshots are layout artifacts; native control appearance and live keyboard interaction still need a running-app check.

PNG backend: bundled helper, metadata and alpha preservation, actual size reduction, malformed input, destination collision, cancellation, encoder-cache compatibility, content credentials, and failed-output cleanup pass. Focused tests pass in an ad-hoc signed sandbox test host, which includes Xcode test exceptions. See [PNG validation and benchmark](png-optimization.md).

Menu-bar validation: signed build and strict deep signature verification pass. The 73-test run includes session outcomes/savings, zero-byte inputs, unavailable/paused presentation, three-file active-plus-waiting counts, paused queue preservation, resume, and completion. Test snapshots remain in xcresult attachments rather than a fixed shared /tmp file. Two existing main-thread responsiveness warnings remain. Live computer-use inspection timed out; verify menu appearance, main-window close/reopen, Settings, Quit, light/dark mode, and VoiceOver manually. The latest result bundle is `/tmp/OrbitConvert-menu-verified.xcresult`. Coverage was not remeasured in this run.

Clipboard tests use private NSPasteboards and isolated preferences. Safety cases include valid-image stale-generation rejection, delayed optimization followed by a newer text copy, failure/no-reduction preservation, type/ignored-app filtering, SHA256 loop prevention, PNG alpha/pixel equivalence, TIFF/JPEG processing, source-file preservation, temporary cleanup, independent folder pause, and repeated NSURL export reuse. A cleanup test caught inconsistent directory URL keys; the implementation now constructs canonical directory URLs. See [clipboard verification](clipboard-optimization.md). The full passing result bundle is `/tmp/OrbitConvert-clipboard-final.xcresult`.


## Markdown and stronger PDF validation (2026-10-01)

The ad-hoc signed arm64 full suite passes: **98 tests, 0 failures, 0 skipped**, in `/tmp/OrbitConvert-documents-verified.xcresult`. Release build and strict deep signature verification also pass for `/tmp/OrbitConvert-icon/Build/Products/Release/OrbitConvert.app`. Existing two main-thread responsiveness warnings remain.

New behavior tests cover UTF-8 Markdown identification, document-only actions, binary rejection, sanitized resources/unsafe links, real Pandoc DOCX round-trip, native AppKit multipage PDF, Unicode/code content, table-header column positions, no-overwrite collisions, cancellation, output cleanup and unchanged sources. Stronger PDF tests cover image-heavy size reduction while retaining selectable text, requested Author/Title metadata removal, annotated-document rejection and encrypted-PDF rejection. Existing image, PDF, watcher, clipboard and output regression tests pass.

Coverage: the five new document services have **312/373 executable lines covered (83.65%)**. Full application coverage is **58.86% (3492/5933)**, below the repository's 80% target; no files were excluded to conceal that gap. Native UI coverage remains limited. Installed-app sandbox behavior outside Xcode test exceptions, macOS 14, Intel helper execution, visual PDF/DOCX comparison in Preview and Pages/Word, long tables, hyperlinks and large-document responsiveness remain manual gates. Native printing has a soft timeout and finishes safely before cancelling publication.

See [actual implementation](markdown-pdf-implementation.md) for helper provenance and backend limitations.

## Document improvements, stages 1 and 2 (2026-10-03)

The full Apple Silicon regression suite passed: **104 tests, 0 failures, 0 skipped**. Result bundle: `/tmp/OrbitConvert-stage2-verified.xcresult`. Release build and strict deep code-signature verification passed. Existing two main-thread responsiveness warnings remain; they are not new test failures.

New checks cover authorized local image embedding into DOCX and PDF, transparency-bearing PNG normalization, traversal/absolute/remote/symlink exclusion, aggregate decoded-pixel limits, image-only DOCX, native clickable external PDF links, custom US Letter sizing and style bounds. Stronger PDF tests use a real image-heavy document with a URL annotation and nested bookmark destinations, require useful reduction, compare navigation after reopening and verify unchanged source bytes.

Full-app line coverage is **60.60% (3,810 / 6,287)**, still below the requested 80%. Current document service coverage: Markdown conversion 96.88%, PDF renderer 94.52%, image resources 100%, navigation service 85.57%. Coverage does not substitute for manual visual checks.

Not yet verified: installed-app resource-folder permission behavior, Preview/Word/Pages visual fidelity, complex fonts/long tables, large-document profiling, macOS 14 runtime and Intel helper execution. Internal annotation links remain rejected after a native PDF destination-remapping probe produced invalid page references. Signed/encrypted PDFs and unsupported interactive structures remain protected.
