# Product plan

Status: Phase 1 implemented; later phases planned. This document translates the supplied product brief into delivery gates.

## Product

Build an original, minimal macOS utility named OrbitConvert. Import files, inspect their content, choose an available action, process locally, save a new file, and show a useful result. The normal window remains usable independently of radial interactions. Do not copy another product's branding, assets, exact visual design, or code.

## Immediate scope: phases 1-4

1. Completed: configured a macOS 14+ SwiftUI app and unit-test target, isolated the working name, and verified build, test, and launch on Apple Silicon macOS 27.0. An x86_64 build passed; macOS 14 and Intel runtime still need verification.
2. Add Choose Files and native file-URL drag/drop, including multiple files. Show per-file import failures without losing valid files. Reject directories, unsupported content, and non-file URLs gracefully.
3. Inspect content using UTType and ImageIO. Show filename, extension, thumbnail, byte size, detected content type, optional creation date, and available outputs.
4. Convert supported still images to PNG, JPEG, HEIC, and TIFF using available Apple encoders. Provide JPEG quality (default 0.90), metadata policy, progress, safe output, collision handling, useful errors, and basic tests.

Default output is beside the source when authorized. Otherwise explain the permission need and let the user choose that folder or another destination. Never overwrite originals or existing results. Process imported files sequentially initially to bound memory; richer batch controls come later.

The Phase 1-4 gate is a working normal-window converter. It is not the complete radial-menu MVP. Stop after this implementation milestone and report files changed, architecture, completed features, testing, limitations, and the next milestone.

## Roadmap

| Phase | Scope | Exit condition |
| --- | --- | --- |
| 1 | App shell, macOS target, tests | Build and launch; baseline test passes |
| 2 | File selection and drop | Single and multiple imports; invalid items handled |
| 3 | Detection and preview | Content-based type, bounded thumbnails, supported actions |
| 4 | Image conversion and output | Required conversion and safety tests pass |
| 5 | In-window radial menu | Dynamic geometry, hover, click, keyboard, VoiceOver tested |
| 6 | Floating AppKit panel | Multi-display placement, appearance, focus, Escape tested |
| 7 | Configurable modifiers | Distinct conversion/tool mode without global interception |
| 8 | Tools | Incremental compression, resize, metadata, stripping, image-to-PDF |
| 9 | Finder feasibility | Public API investigation and approved supported workflow |
| 10 | Release preparation | Signed sandbox tests, accessibility, performance, release checks |

Testing, accessibility, and sandbox design start in Phase 1, not Phase 10. Advanced Finder integration requires explicit approval before implementation.

## Complete MVP gate, after Phase 5

- Launch normally and import an image by drag/drop.
- Detect PNG, JPEG, HEIC, and TIFF and list available output formats.
- Convert PNG to JPEG, JPEG to PNG, and HEIC to JPEG on a supported runtime.
- Save safely without overwriting existing files and show actionable errors.
- Open a radial menu for a selected file; hover highlights and click converts.
- Pass core unit tests and accessibility checks.

## Second milestone

Add a transparent floating panel near the cursor with thumbnail center, screen-bound placement, light/dark appearance, keyboard input, and close-on-selection/cancel/Escape behavior. It is app-owned and explicitly invoked; automatic detection of arbitrary Finder drags is not part of this milestone.

## Third milestone and later tools

- JPEG compression with adjustable quality; report actual size change. Never promise PNG size reduction.
- Resize by dimensions or 25%, 50%, 75%, and custom percentage; preserve aspect ratio by default.
- Inspect dimensions, profile, DPI, camera metadata, timestamps, and embedded GPS. Strip metadata only when requested.
- Image-to-PDF and ordered image merging, one image per page; PDF inspection and extraction later.
- Optional local Vision background removal with OS capability checks and transparent PNG output.
- Investigate WebP and AVIF only after core tools. Document native framework, library, or executable requirements before adoption.

## Settings and experience

Introduce settings as their features ship: output location (source folder, ask, custom), filename suffix, JPEG quality, metadata/profile preservation, radial visibility/size, animation, modifiers, notifications, and automatic Finder reveal. Use native controls and @AppStorage for simple preferences.

Use macOS materials, SF Symbols, accessible contrast, clear focus, light/dark appearance, and reduced-motion support. Radial animation target is 150-250 ms. Progress states are Preparing, Converting, Saving, Completed, Failed, and Cancelled; counts describe files, not invented codec progress.

Optional menu bar mode may expose Open Converter, Choose Files, Recent Conversions, Settings, and Quit. Keep the Dock icon unless the user intentionally configures otherwise. Recent history is not required for Phase 1-4.

## Privacy and exclusions

All conversion stays local. No analytics without consent, uploads, shell execution of files, private APIs, Finder injection, or unrelated filesystem scanning. No speculative plugin framework, database, cloud API, or external codec dependency.

Related: [architecture](architecture.md), [testing](testing.md), [release notes](release_notes.md).
