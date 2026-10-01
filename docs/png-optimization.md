# PNG optimization

OrbitConvert bundles [Oxipng 10.2.1](https://github.com/oxipng/oxipng/releases/tag/v10.2.1), a lossless PNG optimizer under the MIT license. It is used by the existing image optimization service for manual, batch, and watched-folder PNG jobs. Users do not need Homebrew, network access, or an external installation. JPEG/HEIC still use ImageIO and PDF still uses PDFKit. This is not full Clop feature or compression parity.

## Behavior

PNG presets control effort, not image quality: Lossless uses Oxipng level 1, Balanced level 2, Maximum level 4. All preserve pixels and alpha; neither `--alpha` nor `--scale16` is used. Default metadata preservation passes every discovered ancillary chunk to `--keep`, except Apple's iDOT encoder cache. Content credentials in caBX cannot survive a rewrite, so the app refuses optimization with a clear message unless Remove metadata was explicitly selected. Metadata stripping uses the existing ImageIO path before Oxipng.

Oxipng reads an already-open read-only input handle and writes to an exclusively created output handle. No shell is invoked, filenames do not become command arguments, and only the embedded executable is used. The child inherits the parent's sandbox; scoped external paths need not be resolved by the child. Processing runs off the main actor, uses two optimizer threads, and has a 30-second optimizer budget plus a 60-second parent deadline. Cancellation terminates the process, with a bounded grace period before forced termination. Failed temporary output is removed.

PNG input is limited to 256 MB compressed/decompressed data for this backend; the chunk scanner also caps chunk count at 100,000. ImageIO reopens and fully decodes the candidate, checks format, frame count and dimensions, and the existing output service publishes only a smaller result. Existing no-overwrite manual output and safe watched-folder replacement remain in force. Animation remains unsupported.

## Bundling and provenance

The universal executable in `ThirdParty/oxipng/oxipng` combines the two official release executables using `lipo -create`. Both downloaded archive SHA-256 hashes were compared with the GitHub release API asset digests before extraction:

- `oxipng-10.2.1-aarch64-apple-darwin.tar.gz`: `7039fcfc78e8aa1ed2b57d848057a0296f082e92b3e1807ac65402d10d926764`
- `oxipng-10.2.1-x86_64-apple-darwin.tar.gz`: `111883bbe42b25e01cb1ca41f39f8094e4830b173f0e42be342ecc4ca48f3131`
- Combined executable before build signing: `3075732d53c63423b66fe6fcd4a0c3a7d8d0ed3c104cce28798512518b012647`

The Xcode Embed PNG optimizer phase calls `scripts/embed-oxipng.sh`. It copies the helper to `Contents/Helpers`, copies license notices into Resources, and signs the helper using the app's signing identity with app-sandbox and inherit entitlements. Unsigned test builds use an ad-hoc helper signature without sandbox entitlements. No download occurs during build or at runtime.

The upstream MIT license is retained. `THIRD-PARTY-NOTICES.txt` includes license files from all 75 registry crates in the pinned upstream Cargo.lock, including platform/build/test dependencies that may not be present in the macOS executable. Crate archive hashes were verified against that lockfile. Maintain these notices when upgrading; do not replace the binary without verifying its source, architectures, dependencies, and signing.

## Measured sample

One supplied 1120 x 2048 app screenshot was processed locally on the development Apple Silicon Mac with metadata preserved. This is a single-sample comparison, not a Clop benchmark or a general compression guarantee.

| Path | Bytes | Reduction from original |
| --- | ---: | ---: |
| Original | 651,432 | - |
| Previous ImageIO re-encode | 652,127 | Larger, would be skipped |
| Oxipng Lossless | 379,856 | 41.7% |
| Oxipng Balanced | 375,926 | 42.3% |
| Oxipng Maximum | 370,844 | 43.1% |

Balanced took approximately 0.74 seconds in this local run. Decoded sRGB RGBA pixels for the original and Balanced output compared equal. The supplied source was not changed. Already optimized or noisy images can show much smaller savings.

## Validation and remaining work

Tests cover a real bundled executable, meaningful size reduction, metadata retention, normalized alpha/pixel equality, exclusive destination creation, malformed/truncated input, corrupt-CRC cleanup, cancellation before work, iDOT compatibility, and content-credential protection. Focused tests also pass with a signed sandbox test host; Xcode adds test-host exceptions, so this is not a substitute for a clean installed-app test. The app builds for both CPU architectures; Intel runtime and macOS 14 still need validation. Distribution signing/notarization and App Store review are separate release gates.

Larger lossy PNG reductions need palette quantization. pngquant is not included: its GPL/commercial distribution choice remains unresolved. Ghostscript and other GPL/commercial optimizers are also not bundled. No clipboard monitoring, video optimization, or copied Clop source/assets were introduced.
