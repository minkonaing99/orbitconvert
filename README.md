# OrbitConvert

OrbitConvert is a native macOS utility for local image conversion. It uses SwiftUI, AppKit, and Apple ImageIO. Files stay on the user's Mac.

## Current status

Phases 1-6 and a supported Finder drop workflow are implemented. PDF conversion, PDF page utilities, and manual image/PDF optimization have been added. The app has a native SwiftUI window, file drag/drop, in-window and floating radial menus, and an app-owned floating drop target.

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

SwiftUI owns presentation; AppKit owns the floating windows and their lifecycle. Focused services own file access, inspection, conversion, and safe output. Both radial presentations return the selected action to the existing conversion controls. No external dependencies are used. See [architecture](docs/architecture.md) and [internal contracts](docs/api.md).

## Supported conversions and tools

Single-image PNG, JPEG, HEIC/HEIF, and TIFF inputs can convert to a different format among PNG, JPEG, HEIC, and TIFF when the Apple encoder is available. Images can also become PDF pages. PDFs can be rendered as JPEG/PNG, extracted by page or range, and merged in selection order. JPEG, PNG, and PDF files have a manual Compress action; batch optimization is available for multiple selected files. Settings control compression mode, JPEG export quality, PDF image resolution, and metadata removal. [PDF and compression details](docs/pdf-compression.md) describe each native backend and its limits.

## Sandbox permissions

The project enables App Sandbox and read/write user-selected files. A dropped source file does not establish permission to create sibling files; the app asks for an output folder if saving beside the source is denied. Signed sandbox behavior still needs manual verification. See [sandbox and output design](docs/sandbox-and-output.md).

## Known limitations

Each selected file has action buttons, an in-window menu, and a Floating Menu button. Open Floating Drop Target from the main window before dragging Finder files to it. Displays smaller than the menu use the in-window menu. Animated or multi-image inputs are rejected; BMP, GIF, WebP, and AVIF remain unsupported. PDF optimization uses PDFKit write options, so exact compression DPI and JPEG quality are unavailable. Replace Original and Undo are not yet offered; originals are always kept. Full-size conversions can use substantial memory. macOS 14 runtime, Intel runtime, signing, signed sandbox behavior, and manual panel/focus/accessibility behavior remain unverified. Finder-wide drag detection is not available through the APIs used here.

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

The `OrbitConvertTests` target covers intake, detection, conversion, PDF utilities, optimization, collision-safe output, radial geometry, and floating placement. The latest run passed 48 tests on Apple Silicon; the x86_64 build passed. Full app line coverage is 50.2%, below the 80% target. Run `xcodebuild test -project OrbitConvert.xcodeproj -scheme OrbitConvert -destination 'platform=macOS' -derivedDataPath /tmp/OrbitConvert-tests CODE_SIGNING_ALLOWED=NO`. Planned cases and commands are in [testing](docs/testing.md).
