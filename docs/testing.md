# Testing and validation

Status: Finder drop-target phase adds an AppKit panel test. All 29 tests pass on Apple Silicon macOS 27.0, and an x86_64 build passes. Signed sandbox and live drop checks remain open.

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

Phase 5 adds radial zero/one/many item geometry, inner/outer bounds, exact segment boundaries, wraparound, and rendering/hit-test agreement. Test keyboard, VoiceOver, and reduced motion.

Phase 6 placement tests cover multiple monitors, negative origins, and visible-frame edges. Manually check display removal/repositioning, focus, Return/Escape, outside clicks, dark/light appearance, and panel dismissal before claiming the live UI is verified.

Finder drop-target manual checks: open the floating target, switch to Finder, drop one and several supported images, and confirm the first image opens the radial menu near the pointer. Check an unsupported file, a corrupted image, an off-screen existing scroll position, target close/reopen, multiple displays, and source/output grants in a signed sandbox build. Confirm the target never claims to appear automatically when a Finder drag starts.

Phase 8 adds resize aspect ratio, compression arithmetic including larger outputs, GPS removal, ordered PDF pages and page size, and optional Vision capability checks.

Before each implementation milestone report build command/result, tests/coverage, manual checks, and remaining limitations. Before committing, perform a security review. Do not claim a build or test passed unless executed successfully.

Related: [roadmap](product-plan.md), [conversion](image-conversion.md).
