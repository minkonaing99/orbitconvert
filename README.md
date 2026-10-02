# OrbitConvert

OrbitConvert is a native macOS utility for local image conversion. It uses SwiftUI, AppKit, and Apple ImageIO. Files stay on the user's Mac.

## Current status

The app has a native SwiftUI window, file drag/drop, compact rectangular action panels, an app-owned Finder drop target, watched folders, and automatic clipboard image optimization. A persistent menu bar popup shows background jobs, session savings, and recent activity. Image/PDF conversion and manual compression remain available.

## Requirements

- Planned runtime: macOS 14 or later; Apple Silicon and Intel where supported and tested.
- Development tools observed on 2026-09-29: Xcode 27.0 (27A266a), Swift compiler 6.4.
- Project: macOS-only deployment target 14.0 and Swift language mode 5.0. Build and launch have been verified on Apple Silicon macOS 27.0; an x86_64 build also passed. macOS 14 and Intel runtime remain untested.
- Use the current stable Xcode toolchain; compiler version and Swift language mode are separate settings. See [Apple's toolchain requirements](https://developer.apple.com/xcode/system-requirements).

## How to build

For a fresh clone, first [prepare the local document helpers](docs/document-helper-setup.md). Their executables are deliberately excluded from Git; licenses, provenance and build instructions are included. Existing local helper caches remain usable.

Open `OrbitConvert.xcodeproj`, select OrbitConvert and My Mac, then choose Product > Build. Configure a signing team for signed sandbox testing.

Command-line build for the existing shell:

```sh
xcodebuild -project OrbitConvert.xcodeproj -scheme OrbitConvert -destination 'platform=macOS' -derivedDataPath /tmp/OrbitConvert-build build CODE_SIGNING_ALLOWED=NO
```

Unsigned compilation does not verify sandbox permissions or distribution readiness. The Phase 1 shell built and launched on the local Mac.

## Architecture

SwiftUI owns presentation; AppKit owns floating windows and their lifecycle. Both action panels use the same `FileAction` descriptors and dispatch through existing services. Focused services own file access, inspection, conversion, and safe output. PNG optimization bundles the MIT-licensed Oxipng helper; other conversion engines use Apple frameworks. See [architecture](docs/architecture.md) and [internal contracts](docs/api.md).

## Supported conversions and tools

Single-image PNG, JPEG, HEIC/HEIF, and TIFF inputs can convert to a different format among PNG, JPEG, HEIC, and TIFF when the Apple encoder is available. Images can also become PDF pages. PDFs can be rendered as JPEG/PNG, extracted by page or range, and merged in selection order. JPEG, PNG, and PDF files have a manual Compress action; batch optimization is available for multiple selected files. Watched folders automatically optimize new JPEG, PNG, HEIC, and PDF files and replace originals only after validation and a size reduction. Settings control compression mode, JPEG export quality, PDF image resolution, metadata removal, and watched-folder policies. [PDF and compression details](docs/pdf-compression.md) and [watched folders](docs/watched-folders.md) describe the backends and their limits. See [PNG optimization](docs/png-optimization.md) for the bundled optimizer, provenance, and measured sample.

Clipboard optimization supports single PNG/JPEG/TIFF/HEIC images and copied image files, reuses the background queue, and preserves source files. Settings include independent pause, ignored apps, result cards, and an optional in-memory collection. See [clipboard optimization](docs/clipboard-optimization.md) for generation safety, temporary-file lifetime, and cross-application limitations.

## Markdown and stronger PDF compression

Markdown (`.md`, `.markdown`) exports locally to editable DOCX or paginated PDF through existing actions. Bundled Pandoc parses documents; native AppKit printing lays out PDFs with optional font, page and margin controls. Local images require an explicitly selected resource folder and are validated, orientation-normalized and bounded before embedding. Remote images are never fetched. Native PDF web links remain clickable. Stronger manual PDF compression uses bundled Ghostscript and preserves supported web links and nested bookmarks; unsupported protected/interactive documents remain excluded and originals stay intact. Current document helpers support Apple Silicon. See [document conversion and tool details](docs/markdown-pdf-implementation.md).

## Sandbox permissions

The project enables App Sandbox, read/write user-selected files, and app-scoped bookmarks for watched folders. A dropped source file does not establish permission to create sibling files; the app asks for an output folder if saving beside the source is denied. Signed sandbox behavior still needs manual verification. See [sandbox and output design](docs/sandbox-and-output.md).

## Known limitations

The main window uses compact selectable rows and one shared action area. Floating Actions and Floating Drop Target are available from the toolbar Windows menu. On small displays, actions remain available in the main window. Resize, standalone Metadata, Remove Metadata, and Split are not shown because handlers do not exist yet. Animated or multi-image inputs are rejected; BMP, GIF, WebP, and AVIF remain unsupported. PDF optimization uses PDFKit write options, so exact compression DPI and JPEG quality are unavailable. Manual actions keep originals; watched folders default to validated replacement with a temporary recovery backup. Undo is not offered. A paused writer can resume after the watched-folder quiet period; signed sandbox and real downloads need manual testing. Full-size conversions can use substantial memory. macOS 14 runtime, Intel runtime, signing, signed sandbox behavior, and manual panel/focus/accessibility behavior remain unverified. Finder-wide drag detection is not available through the APIs used here.

## Documentation and roadmap

- [Product plan, phases, and acceptance gates](docs/product-plan.md)
- [Architecture and future AppKit integration](docs/architecture.md)
- [Internal API contracts](docs/api.md)
- [Image conversion policies](docs/image-conversion.md)
- [Sandbox and output safety](docs/sandbox-and-output.md)
- [Persistence and database policy](docs/database.md)
- [Testing and validation](docs/testing.md)
- [Finder workflow feasibility](docs/finder-integration.md)
- [PDF and compression implementation](docs/pdf-compression.md)
- [Watched folders and replacement safety](docs/watched-folders.md)
- [Automatic clipboard optimization](docs/clipboard-optimization.md)
- [Release notes](docs/release_notes.md)

## Testing

The `OrbitConvertTests` target covers intake, detection, conversion, PDF utilities, optimization, collision-safe output, action grouping, and floating placement. Run `xcodebuild test -project OrbitConvert.xcodeproj -scheme OrbitConvert -destination 'platform=macOS' -derivedDataPath /tmp/OrbitConvert-tests CODE_SIGNING_ALLOWED=NO`. Latest counts and coverage are in [testing](docs/testing.md).
