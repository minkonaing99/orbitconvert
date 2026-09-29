# Release notes

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

No application feature is released. Next implementation milestone is Phase 2 file intake; radial and Finder workflows remain deferred.

Related: [product plan](product-plan.md), [testing](testing.md), [README](../README.md).
