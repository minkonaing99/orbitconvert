# OrbitConvert

OrbitConvert is a native macOS utility for local image conversion. It uses SwiftUI, AppKit, and Apple ImageIO. Files stay on the user's Mac.

## Current status

The app has a native SwiftUI window, file drag/drop, compact rectangular action panels in the main and floating windows, and an app-owned Finder drop target. Image/PDF conversion and manual compression remain available.

## Requirements

- Planned runtime: macOS 14 or later; Apple Silicon and Intel where supported and tested.
- Development tools observed on 2026-09-29: Xcode 27.0 (27A266a), Swift compiler 6.4.
- Project: macOS-only deployment target 14.0 and Swift language mode 5.0. Build and launch have been verified on Apple Silicon macOS 27.0; an x86_64 build also passed. macOS 14 and Intel runtime remain untested.
- Use the current stable Xcode toolchain; compiler version and Swift language mode are separate settings. See [Apple's toolchain requirements](https://developer.apple.com/xcode/system-requirements).

## How to build

Open `OrbitConvert.xcodeproj`, select OrbitConvert and My Mac, then choose Product > Build. Configure a signing team for signed sandbox testing.

Command-line build for the existing shell:

```sh
xcodebuild -project OrbitConvert.xcodeproj -scheme OrbitConvert -destination 'platform=macOS' -derivedDataPath /tmp/OrbitConvert-build build CODE_SIGNING_ALLOWED=NO
```

Unsigned compilation does not verify sandbox permissions or distribution readiness. The Phase 1 shell built and launched on the local Mac.

## Architecture

SwiftUI owns presentation; AppKit owns floating windows and their lifecycle. Both action panels use the same `FileAction` descriptors and dispatch through existing services. Focused services own file access, inspection, conversion, and safe output. No external dependencies are used. See [architecture](docs/architecture.md) and [internal contracts](docs/api.md).

## Supported conversions and tools

Single-image PNG, JPEG, HEIC/HEIF, and TIFF inputs can convert to a different format among PNG, JPEG, HEIC, and TIFF when the Apple encoder is available. Images can also become PDF pages. PDFs can be rendered as JPEG/PNG, extracted by page or range, and merged in selection order. JPEG, PNG, and PDF files have a manual Compress action; batch optimization is available for multiple selected files. Settings control compression mode, JPEG export quality, PDF image resolution, and metadata removal. [PDF and compression details](docs/pdf-compression.md) describe each native backend and its limits.

## Sandbox permissions

The project enables App Sandbox and read/write user-selected files. A dropped source file does not establish permission to create sibling files; the app asks for an output folder if saving beside the source is denied. Signed sandbox behavior still needs manual verification. See [sandbox and output design](docs/sandbox-and-output.md).

## Known limitations

Each selected file has a rectangular action panel and an Open Floating Panel button. Open Floating Drop Target from the main window before dragging Finder files to it. On small displays, actions remain available in the main window. Resize, standalone Metadata, Remove Metadata, and Split are not shown because handlers do not exist yet. Animated or multi-image inputs are rejected; BMP, GIF, WebP, and AVIF remain unsupported. PDF optimization uses PDFKit write options, so exact compression DPI and JPEG quality are unavailable. Replace Original and Undo are not offered; originals are always kept. Full-size conversions can use substantial memory. macOS 14 runtime, Intel runtime, signing, signed sandbox behavior, and manual panel/focus/accessibility behavior remain unverified. Finder-wide drag detection is not available through the APIs used here.

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
- [Release notes](docs/release_notes.md)

## Testing

The `OrbitConvertTests` target covers intake, detection, conversion, PDF utilities, optimization, collision-safe output, action grouping, and floating placement. Run `xcodebuild test -project OrbitConvert.xcodeproj -scheme OrbitConvert -destination 'platform=macOS' -derivedDataPath /tmp/OrbitConvert-tests CODE_SIGNING_ALLOWED=NO`. Latest counts and coverage are in [testing](docs/testing.md).
