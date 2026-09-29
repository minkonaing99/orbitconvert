# OrbitConvert

OrbitConvert is a planned native macOS utility for local image conversion, followed by an original radial action menu. It uses SwiftUI, AppKit, and Apple imaging frameworks. Files stay on the user's Mac.

## Current status

Phases 1-3 are implemented: native SwiftUI window, macOS-only target, test target, file selection, drag/drop intake, image detection, thumbnails, metadata, and available output formats. Conversion, tools, and radial menu are not implemented yet.

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

SwiftUI owns presentation; focused services own file access, inspection, thumbnails, conversion, and safe output. No external dependencies are planned. See [architecture](docs/architecture.md) and [internal contracts](docs/api.md).

## Supported conversions and tools

None implemented yet. PNG, JPEG, HEIC, and TIFF inputs are recognized from image data; output options are shown only when an Apple encoder is available. Phase 4 will add conversion. Tools and PDF support come later. See [product scope and roadmap](docs/product-plan.md).

## Sandbox permissions

The shell enables App Sandbox and read-only user-selected files. Conversion will require user-selected read/write access. A dropped source file does not establish permission to create sibling files; request folder access when needed. See [sandbox and output design](docs/sandbox-and-output.md).

## Known limitations

Current UI inspects one still image per file. Animated or multi-image files are rejected; BMP, GIF, WebP, and AVIF remain unsupported. Output formats are display only until Phase 4. macOS 14 runtime, Intel runtime, signing, and signed sandbox behavior remain unverified. Finder-wide drag detection is not promised.

## Documentation and roadmap

- [Product plan, phases, and acceptance gates](docs/product-plan.md)
- [Architecture and future AppKit integration](docs/architecture.md)
- [Internal API contracts](docs/api.md)
- [Image conversion policies](docs/image-conversion.md)
- [Sandbox and output safety](docs/sandbox-and-output.md)
- [Persistence and database policy](docs/database.md)
- [Testing and validation](docs/testing.md)
- [Release notes](docs/release_notes.md)

## Testing

The `OrbitConvertTests` target contains shell, intake, and type-detection tests. Run `xcodebuild test -project OrbitConvert.xcodeproj -scheme OrbitConvert -destination 'platform=macOS' -derivedDataPath /tmp/OrbitConvert-tests CODE_SIGNING_ALLOWED=NO`. Planned cases and commands are in [testing](docs/testing.md). No conversion coverage exists yet.
