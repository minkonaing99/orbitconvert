# OrbitConvert

OrbitConvert is a native macOS utility for local image conversion. It uses SwiftUI, AppKit, and Apple ImageIO. Files stay on the user's Mac.

## Current status

Phases 1-6 are implemented: native SwiftUI window, file selection and drag/drop, image inspection, safe conversion, in-window radial selection, and a floating radial panel. Tools and Finder integration come later.

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

SwiftUI owns presentation; AppKit owns only the floating panel and its lifecycle. Focused services own file access, inspection, conversion, and safe output. Both radial presentations return the selected action to the existing conversion controls. No external dependencies are used. See [architecture](docs/architecture.md) and [internal contracts](docs/api.md).

## Supported conversions and tools

Single-image PNG, JPEG, HEIC/HEIF, and TIFF inputs can convert to a different format among PNG, JPEG, HEIC, and TIFF when the Apple encoder is available. JPEG quality defaults to 90%; metadata can be removed. Tools and PDF support come later. See [product scope and roadmap](docs/product-plan.md).

## Sandbox permissions

The project enables App Sandbox and read/write user-selected files. A dropped source file does not establish permission to create sibling files; the app asks for an output folder if saving beside the source is denied. Signed sandbox behavior still needs manual verification. See [sandbox and output design](docs/sandbox-and-output.md).

## Known limitations

Current UI handles one still image per file; each selected file has conversion buttons, an in-window menu, and a Floating Menu button. Displays smaller than the menu use the in-window menu. Animated or multi-image files are rejected; BMP, GIF, WebP, AVIF, and PDF remain unsupported. Full-size conversions can use substantial memory. Progress and cancellation are per-file. macOS 14 runtime, Intel runtime, signing, signed sandbox behavior, and manual panel/focus/accessibility behavior remain unverified. Finder-wide drag detection is not promised.

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

The `OrbitConvertTests` target covers shell, intake, detection, conversion, collision-safe output, radial geometry, and floating placement. Run `xcodebuild test -project OrbitConvert.xcodeproj -scheme OrbitConvert -destination 'platform=macOS' -derivedDataPath /tmp/OrbitConvert-tests CODE_SIGNING_ALLOWED=NO`. Planned cases and commands are in [testing](docs/testing.md).
