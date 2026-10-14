# Architecture, Decisions and Security

Status: Main-window actions, PDF conversion, manual compression, Markdown export, Finder drops, watched folders with automation rules, clipboard optimization and the Finder Quick Action are implemented. Signed sandbox behavior, macOS 14 and Intel runtime remain unverified.

## Tech stack

| Layer | Choice | Rationale |
| --- | --- | --- |
| Language | Swift (language mode 5.0; compiler 6.4, Xcode 27.0) | Native macOS, strong concurrency checks |
| UI | SwiftUI scenes; AppKit for panels, printing, pasteboard, open panels | Native look, keyboard and accessibility; AppKit where SwiftUI lacks APIs |
| Images | ImageIO, Core Graphics | Built-in codecs, byte-based detection, bounded thumbnails; no package needed |
| PDF | PDFKit + Core Graphics; bundled Ghostscript 10.08.0 for stronger compression | PDFKit for structure; Ghostscript only where precise image downsampling is needed |
| PNG | Bundled Oxipng 10.2.1 (MIT) | ImageIO re-encoding often grew PNGs; Oxipng is lossless |
| Markdown | Bundled Pandoc 3.12 (GPL) + AppKit text printing | Mature DOCX writer; native printing preserved links and tables |
| Folder events | Core Services FSEvents | Public API, file-level events |
| Persistence | UserDefaults / @AppStorage (JSON for folders/history) | Small settings and bounded history; no database needed |
| Login item | ServiceManagement | Optional Launch at Login |
| Tests | XCTest (`OrbitConvertTests`) | Xcode-native, coverage via xcresult |

Deployment target macOS 14.0; bundle IDs `com.example.OrbitConvert`, `.QuickAction`, `com.example.OrbitConvertTests`; version 3.1 (build 1); App Store category Utilities (`public.app-category.utilities`). The extension reads its version from the same build settings. Default actor isolation is MainActor; services opt out with `nonisolated`.

## Targets and folder structure

```
OrbitConvert/                 App target (62 Swift files in feature folders; Xcode synced folder group)
  App/                        OrbitConvertApp (scenes, app delegate), AppIdentity, ContentView, ConversionControlsView
  Core/                       Intake, type detection, actions, selection, output, stability, safe replacement, batches, compression models
  Images/                     Image conversion, optimization, resize, target size, Oxipng
  PDF/                        PDF conversion, navigation, optimization, validation, Ghostscript
  Documents/                  Markdown conversion, PDF renderer, image resources, bundled tool runner
  Watch/                      FSEvents watcher, watched folder model and controller, auto optimization, menu bar views
  Automation/                 Rules, conditions, rename templates, execution, file operations, media, preview, editors
  Clipboard/                  Monitor, writer, optimization, result card, settings
  QuickAction/                Finder Quick Action request (also compiled into the extension), controller, service, view
  Settings/                   General and watched-folder settings, resize and target-size sheets
  Assets.xcassets             AppIcon (16-512 pt @1x/@2x), symbols
  OrbitConvert.entitlements   Sandbox, user-selected read/write, app-scope bookmarks, network client (WebKit only)
OrbitConvertQuickAction/      Finder Action extension (ActionRequestHandler, Info.plist, entitlements)
OrbitConvertTests/            XCTest target (~36 files, 200 tests)
Config/OrbitConvert-Info.plist
ThirdParty/oxipng|pandoc|ghostscript/   Helper binaries/caches, licenses, notices
scripts/embed-oxipng.sh       Copies and signs helpers during build
scripts/memory-fixtures.swift Generates memory-profiling fixtures
docs/                         Project documentation
```

Add new files to the matching feature folder; new folders are picked up automatically. `QuickAction/QuickActionRequest.swift` is referenced by path from the extension target in `project.pbxproj`; update that path if it moves. Create files when behavior is implemented, not empty folders. Use value types and immutable job inputs. Add protocols only at real interchangeable boundaries.

## Data flow

**Intake.** User selects or drops URLs. `FileIntakeService` accepts local, regular, readable files. `FileTypeService` inspects bytes with ImageIO/PDFKit (extension is only a hint), makes bounded oriented thumbnails, reads metadata, and intersects outputs with installed encoders. Both run in a serial background job. Each service balances its own security-scoped access; conversion reacquires scope for the full operation.

**Actions.** `FileAction` descriptors (kind, category, ID, title) drive the UI. `FileAction.common` intersects actions supported by every selected file. `ConversionControlsView` shows Compress, a format picker, Tools and collapsed options. `SelectionActionService` snapshots the selection and processes it sequentially in a detached task through `FileActionService`; image-to-PDF and merge execute once. Selection is locked while processing. Individual failures keep successful outputs.

**Output.** Services encode to a private temporary file, reopen and validate, then publish through `FileOutputService` (see Safe output). Results return URLs only after publication.

**Watched folders.** `WatchedFoldersController` (app lifetime, MainActor, shared by Settings and MenuBarExtra) owns one sequential queue. `FolderWatchService` streams FSEvents with `WatchRoot`; dropped events and new subdirectories trigger off-main rescans. `FileStabilityService` checks size, nanosecond mtime, device and inode across two one-second intervals (60-check timeout). `AutomationWatchService` connects the queue to `AutomationConditionService` (matching) and `AutomationExecutionService` (ordered actions with session checkpoints). `AutoOptimizationService` runs compression; `SafeFileReplacementService` swaps files.

**Clipboard.** `ClipboardMonitorService` polls `NSPasteboard.general.changeCount` every 600 ms on MainActor, inspects advertised types, and admits jobs into the same queue. `ClipboardOptimizationService` works off MainActor; `ClipboardWriterService` commits with generation checks.

**Finder Quick Action.** The extension creates implicit security-scope bookmarks and sends a bounded `.orbitcompress` document to the app through NSWorkspace. The app delegate opens a `QuickCompressionController` window per request; `QuickCompressionService` runs optimizers off MainActor.

**Markdown.** Pandoc parses GFM to a JSON AST, which is sanitized, then written to DOCX (Pandoc) or RTF and printed by `MarkdownPDFRenderer` (AppKit `NSTextView`).

## Components

### Image conversion and optimization

- Accepts single-image PNG, JPEG, HEIC/HEIF and TIFF. Animated/multi-image inputs are rejected. Outputs limited to an allowlist of `CGImageDestination` types, excluding the input format.
- Pipeline: acquire access and validate options; inspect count, dimensions, type, orientation; decode off MainActor; encode a temporary file and check finalization; reopen and validate; publish; report actual size.
- Preserve visible orientation (normalize once), dimensions, color profile, DPI and compatible metadata. JPEG flattens alpha onto white. Default JPEG quality 0.90 (UI 0-100%).
- Metadata removal strips EXIF/IPTC/XMP/GPS and embedded previews but keeps color data. Full-decode paths reject images above 100 million pixels.
- Savings = `(original - result) / original * 100`; growth is reported, not shown as negative savings.
- JPEG optimization: ImageIO at 0.85 (Balanced) or 0.70 (Maximum). HEIC uses the installed encoder.
- **JPEG skip re-encode** (`JPEGQualityEstimator`): estimates source quality on the IJG 1-100 scale from the luminance quantization table (the table named by the first SOF0-SOF2 component, else table 0; sum-based IJG scaling; header walk from SOI to SOS, first 4 MB only, no decode). ImageIO quality is not IJG quality (measured: 0.85 ~ IJG 95, 0.70 ~ IJG 91, 0.5 ~ IJG 78), so the target is measured at runtime by encoding an 8 x 8 image at the requested quality and estimating its table. Source estimate <= target: no encode, `.noReduction` with `estimatedJPEGQuality`, reported as "Already compressed at about N% quality". Unreadable tables fall back to re-encoding. Applies to every caller of `ImageOptimizationService` (Compress, batch, watched folders, Quick Action, clipboard, automation, Resize's final pass); Compress to Size unchanged. With Remove metadata on, the skip applies only to upright photos, where F7 strips metadata losslessly; rotated photos are re-encoded. Measured re-encode of cjpeg photos at IJG 50-90: Balanced 130-192% of source, Maximum 97-141%; only IJG 95 sources shrank at Balanced.
- **Compress to Size** (`TargetSizeCompressionService`): JPEG, HEIC and PNG, output keeps its format. JPEG/HEIC: binary search over quality 100% to 0% in 5-point steps (at most 6 encodes per size level instead of 21; each quality encodes to its own file and the winner is moved into place; output size is not strictly monotonic in quality, so a slightly higher fitting step can rarely be missed); PNG: one lossless ImageIO encode plus Oxipng per size level. Then aspect-preserving downscale to a 1080 px short-edge floor; each candidate derives from the original. Uses fresh filesystem attributes for measured sizes. Publishes `-target-size.<ext>` only within the byte limit. Rejects high-bit-depth and HDR gain-map input. Measured 2026-10-12: downscaling screenshot-like PNGs usually makes them larger (interpolation adds colors; a 2160 x 1440 test pattern went from 827 KB to 3,040 KB at 75%), so PNG targets mostly succeed only for photo-like PNGs until palette reduction exists.
- **Resize** (`ImageResizeService`, `ResizeOptionsView`): ImageIO transformed downsampling from full image data, orientation and dimension metadata normalized, alpha and color space kept. Publishes `-resized` only when smaller. Normal Compress still requires unchanged dimensions.

### PNG: Oxipng

- Presets set effort, not quality: Lossless level 1, Balanced level 2, Maximum level 4. Pixels and alpha preserved; `--alpha` and `--scale16` not used.
- Metadata: every ancillary chunk passed to `--keep` except Apple's iDOT cache. Content credentials (caBX) cannot survive a rewrite, so optimization is refused unless Remove metadata was chosen. Stripping uses ImageIO before Oxipng.
- Reads an open read-only handle, writes an exclusively created handle; no shell, filenames never become arguments. Two threads, 30 s optimizer budget, 60 s parent deadline; cancellation terminates with a bounded grace period.
- Limits: 256 MB compressed/decompressed, 100,000 chunks. Candidate fully decoded by ImageIO and published only if smaller.
- Measured sample (one 1120 x 2048 screenshot, 651,432 bytes): ImageIO re-encode 652,127 (larger); Oxipng Lossless 379,856 (41.7%), Balanced 375,926 (42.3%, ~0.74 s, identical pixels), Maximum 370,844 (43.1%). Single sample, not a general guarantee.

### JPEG: lossless jpegtran

- `JpegtranService` runs the bundled mozjpeg `jpegtran` through `BundledDocumentTool` (private job dir, generated names): `-revert -copy all|icc -optimize -outfile output.jpg input.jpg`. Coefficients untouched; only Huffman tables and markers change.
- Baseline on purpose: ImageIO decodes 4:2:0 progressive JPEGs with different chroma upsampling than baseline ones (measured: about 19% of values differ, up to 87/255 at edges, while libjpeg decodes both identically), so progressive output would look different in Preview and Finder. Baseline costs 2-17% of the extra progressive saving.
- Accepted only when smaller and the ImageIO-decoded pixels are byte-identical to the input; otherwise skipped. Inputs over 256 MB or 100 megapixels, non-JPEG, truncated input, helper failure and a missing helper all mean skipped. Cancellation still stops the job.
- Pipeline (`ImageOptimizationService.encodeJPEG`): already compressed (F6) -> lossless rewrite of the source, else no reduction with the estimate; otherwise the smallest of ImageIO re-encode, its lossless rewrite and the source's lossless rewrite.
- Remove metadata: `-copy icc` keeps only the ICC profile (drops EXIF incl. GPS, XMP, IPTC, comments). EXIF orientation would be lost, so rotated photos (orientation not 1) use the ImageIO re-encode path, which keeps orientation.
- Measured (2400 px photos): 191 KB -> 152 KB (cjpeg q85), 1,018 KB -> 977 KB (q95), 294 KB -> 266 KB (sips q80).

### Palette PNG: pngquant

- Opt-in (`paletteLevel`: Off / Safe / Smaller, off by default) for manual Compress, Compress to Size and the Finder Quick Action. Rule Compress actions have their own per-action level (`AutomationAction.palette`, default Off, F9). Clipboard stays lossless. Safe uses `--quality=80-100`, Smaller `--quality=60-100` (accepts visible but slight color changes; measured: a gradient with +-6 noise is rejected by Safe and goes from 122 KB to 26 KB with Smaller). The old Bool `paletteReduction` maps on to Safe (migrated at launch).
- `PngquantService` runs the bundled helper through `BundledDocumentTool` in a private job directory with generated names: `--quality=<level range> --speed 3 --skip-if-larger`. Exit 99 (quality floor not met) and 98 (not smaller) mean skipped; the lossless Oxipng path then runs.
- The palette result is optimized with Oxipng and validated like any PNG candidate. Measured on a 1200 x 800 screenshot-like PNG: 29.8 KB to 6.7 KB.
- Inputs over 256 MB or 100 megapixels (checked from IHDR before the helper runs), helper failures and a missing helper all count as "skipped" and fall back to lossless; cancellation still stops the job.
- The macOS build converts colors to sRGB (rendered pixels compared identical for in-gamut colors) and drops metadata chunks (ICC, EXIF, text). With Remove metadata off, content-credential PNGs are still refused before pngquant runs, in both Compress and Compress to Size; other metadata is removed by design and the setting says so.

### PDF

- PDFKit: image-to-PDF (fit, image size, A4, Letter), extraction without rasterizing, merge in selection order. Core Graphics renders pages to JPEG/PNG at 72/100/150/200/300 DPI, rejecting pages over 100 million output pixels, drawing visible annotations after content.
- Native optimization: Lossless rewrite; Balanced `saveImagesAsJPEG`; Maximum adds `optimizeImagesForScreen`. PDFKit exposes no exact DPI/quality, so such parameters are rejected. Candidates are checked for page count, extractable text, URL-link count and top-level outline count.
- **Stronger compression** (`GhostscriptService`, manual only): `pdfwrite`, Balanced 150 DPI and Maximum 100 DPI for color/gray images, 300 DPI monochrome; duplicate-image detection and font compression on. HTTP/HTTPS/mailto link annotations are re-applied and verified; nested bookmarks compared recursively (`PDFNavigationService`).
- `PDFOptimizationValidation` excludes encrypted/signed PDFs (in the shared entry point, so no caller bypasses it), forms, other annotations, internal annotation links, attachments, named destinations, layers, tagged and output-intent documents and automatic actions. Bounded inspection with depth/node limits. Limits: 256 MB, 2,000 pages, 120 s helper timeout.
- Output must reopen with matching page count, boxes, rotations and per-page text. These checks reduce risk; they do not prove full semantic equivalence.

### Markdown export

- UTF-8 `.md`/`.markdown` up to 10 MB. Pandoc runs with `--sandbox`. The sanitized AST has empty metadata, no raw nodes, no attributes, and only HTTP, HTTPS, mailto or internal-fragment links.
- Local images (opt-in folder grant): relative paths only; traversal, absolute, remote, symlink and nonregular paths excluded; reads use `openat` with `O_NOFOLLOW` per component. PNG/JPEG/TIFF/HEIC normalized to PNG data URIs, max 2,400 px long edge. Limits: 20 MB per input, 40 MP source, 100 resources, 24 MP aggregate embedded, 40 MB aggregate encoded. Excess images become alt text.
- DOCX is reopened with Pandoc's reader to validate text. PDF: RTF via Pandoc, AppKit `NSTextView` printing without a dialog. AppKit drops RTF `pict` images, so images are replaced with markers and inserted as `NSTextAttachmentCell` after import. Print callbacks on MainActor; 60 s soft print deadline.
- Not supported: raw HTML, Mermaid, math, Obsidian links/transclusions, internal PDF anchors.

### Watched folders and safe replacement

- Ignored: hidden, `orbitconvert-` prefixed, temporary/download suffixes (`.crdownload`, `.download`, `.part`, `.tmp`, `.temp`, `.partial`, `.filepart`), symlinks, packages, non-current iCloud files.
- Initial snapshot excludes existing files; the stream replays arrivals during the snapshot. Duplicate paths queue once; recent output fingerprints and the baseline set stop the app's own outputs being reprocessed.
- Legacy optimization retries up to three times. Automation failures record the step; checkpoints allow in-session retry from that step after revalidating the working file.
- Optimizers write into a private job directory in the app's temporary area. `SafeFileReplacementService` copies a valid candidate into a private directory beside the source (same volume), rechecks the fingerprint, calls `FileManager.replaceItemAt` with a unique backup, validates, then removes or trashes the backup per policy. Failed post-swap validation restores the backup; if that fails, the hidden backup is kept and reported.
- `AutomationFileOperations` publishes general files without overwrite (`link()` fails with EEXIST). Moves validate a complete destination copy (byte compare, fingerprint rechecks) before removing the source. Symlinks and symlinked ancestors rejected except macOS root aliases (/tmp, /var, /etc).
- Pause stops admission and the next job; the active job finishes. The menu count includes queued retry delays. One window-style MenuBarExtra observes the controller; no polling timer.

### Clipboard

- Skips plain text, URLs, mixed/multiple items, concealed/transient/autogenerated items, and ignored frontmost bundle IDs (heuristic).
- A newer clipboard change drops an older waiting clipboard job. Clipboard pause is independent of folder pause and invalidates the commit generation.
- TIFF converts to PNG then optimizes; result compared with original TIFF bytes. Lossless JPEG/HEIC skipped.
- Writer prepares representations, rechecks generation before and after `prepareForNewContents`, writes without an async gap. Self-write prevention: last written generation, a private marker, and a SHA256 registry (max 128 entries, one hour, hashes only, not persisted).
- NSPasteboard has no atomic compare-and-swap; a race in the final synchronous window remains possible. Rollback restores image/file representations only.
- Temporary exports: 64 directories / 256 MB; reused by result ID; files referenced by the clipboard kept at quit; unreferenced UUID directories older than 24 hours swept on launch. Not secure deletion.

### Finder Quick Action

- Sandboxed Action extension (`com.apple.services`); activation predicate accepts supported images only. Loads in-place representations, rejects copies.
- The extension returns all original input items unchanged (Finder may delete omitted attachments). It keeps its private request document until a later invocation removes requests older than a day.
- The app validates document version, size, bookmark sizes and count, resolves bookmarks without UI or mounting volumes. No App Group or broad entitlement.
- `QuickCompressionService` reuses `ImageOptimizationService`, `SafeFileReplacementService` and `FileOutputService`; rejects symlinks; checks fingerprints before publication.

## Concurrency

- Observable UI state on MainActor. Synchronous ImageIO/PDFKit work runs on explicitly non-main contexts; `async` alone does not move work off MainActor.
- One bounded sequential worker for manual actions; one shared sequential queue for watched folders and clipboard. No second queue.
- Structured parent tasks propagate cancellation, checked between inspect, decode, encode and publish. Synchronous codec calls finish before cancellation applies. Never publish a cancelled job; keep completed results.
- Scoped access stays alive across awaits for the whole operation.

## Safe output

1. Validate the destination is an authorized existing directory (URL APIs, never shell).
2. Derive the basename from the source and format; user-supplied name parts cannot contain path components.
3. Create a private mode-0700 directory with `mkdtemp` inside the destination; encode and validate there.
4. Publish with POSIX `link()`, which fails if the name exists. An exists-check followed by a write is not acceptable.
5. On collision retry `photo.jpg`, `photo-1.jpg`, `photo-2.jpg`; the filesystem decides case sensitivity.
6. Remove only this job's temporary artifacts on failure or cancellation.

Requires hard-link support on the destination filesystem; otherwise a write error. Full disk, revoked grants, read-only folders, disconnected volumes, disappearing sources and symlink destinations are recoverable failures. Same-format conversion treats the source as a collision.

## Bundled helpers

All helpers use fixed bundle paths, `Process.arguments` (no shell, no PATH lookup), restricted environments, generated filenames in 0700 job directories, timeouts, cancellation and cleanup. They are signed with `app-sandbox` + `inherit` entitlements (`ThirdParty/oxipng/helper.entitlements`) by `scripts/embed-oxipng.sh`; unsigned test builds get ad-hoc signatures. Nothing downloads at build or run time.

| Helper | Version / arch | Provenance |
| --- | --- | --- |
| Oxipng | 10.2.1, universal (lipo of official arm64 + x86_64) | aarch64 tarball `7039fcfc78e8aa1ed2b57d848057a0296f082e92b3e1807ac65402d10d926764`; x86_64 tarball `111883bbe42b25e01cb1ca41f39f8094e4830b173f0e42be342ecc4ca48f3131`; combined binary before signing `3075732d53c63423b66fe6fcd4a0c3a7d8d0ed3c104cce28798512518b012647`. Committed. Notices cover all 75 crates in the pinned Cargo.lock |
| Pandoc | 3.12, arm64 | `pandoc-3.12-arm64-macOS.zip` `f148ca09c9f36594db527a9fc988ad736290ce428f79594c50208cd1ec58b3c0`; executable `944a597887d68721af64673df44b366905f1771307bbb57615b299d0cb9245f4`. Gzip cache not committed |
| KaTeX | 0.19.0 (MIT) | npm `katex-0.19.0.tgz` sha512 `v6Tznz3zJ7u3niRCoDTsumM2+HA2XXcCu+WAacCeHD2z3p9A9Ks987o5FzfTGBN0e8A0vjEgIDvLbICrXpdw/Q==` (sha256 `d8e49f2fea6eeed7cdae2cf4fd48e2f1d348758aa9e5740715e4533c2c96d1ee`); `katex.min.js` `103a53763cc033bba8d175bf3f0ba597c3505c9b6747dd3f2c7bc2a6bfcc8ae7`; `katex-inline.css` (katex.min.css with the 20 woff2 fonts inlined as data URIs) `c6457047d81b045d962c90ec3a2a690a46789d820b0a6d85ecabe5369621771a`. Committed gzipped in `ThirdParty/katex/` |
| Mermaid | 12.1.0 (MIT) | npm `mermaid-12.1.0.tgz` sha512 `wlVCp+8eTupfCeeFvoZNNiTuHrvag0P2jz/ILgb/f/6jkVokUefOcujefi8qUe/j2asHiSePncVsz/xzzA80LQ==` (sha256 `3e516f33246e1a6a5bc5ebcabd35434669b487c3b3791f9b0466aa2c254d004a`); `mermaid.min.js` `6484afc32872a3aa16cac9a76ba1816a1ed4cc870a6593cc2e17757750f518b2` (global build, no eval). Committed gzipped in `ThirdParty/mermaid/` |
| mozjpeg jpegtran | 4.1.1, universal static build (arm64 + x86_64, macOS 14 target) | Source `https://github.com/mozilla/mozjpeg/archive/refs/tags/v4.1.1.tar.gz` `66b1b8d6b55d263f35f27f55acaaa3234df2a401232de99b6d099e2bb0a9d196`; binary before signing `3ae83cef18c004629c9d29a328a71a57589be4e8775628aa129baa49d1eaa525`; committed gz `e86585497f76cb388496b8d9ca5327ce7995340ee193c6ea3142d605278f7f05`; links only libSystem; IJG + BSD licenses (`ThirdParty/mozjpeg/LICENSE`). Built locally (SETUP); x86_64 slice not run (no Rosetta here) |
| pngquant | 3.0.3, universal (official macOS build) | `https://pngquant.org/pngquant.tar.bz2` `68c32e4988d3f99f79f0642a94900756b7a2a463166067c5862826ced1e0ce1e`; executable `00d3e980ab3c3c39a9df1069b406f4e5013b97394988f66d8356d4d7d05f011c`; Developer ID team 59KZTZA4XR; links only system libraries; GPL v3. Gzip cache not committed; publisher provides no checksum |
| Ghostscript | 10.08.0, arm64, built locally | `ghostscript-10.08.0.tar.gz` `caf199e3f233f1290b27d0972d636f66c303355f2353309b7bfddf1edda06b3d`; executable `a94e0278a8dc5977f9d3c31fc44da5ee2e7e502c208ada974b99dc52692d410e`. Gzip cache not committed |

Pandoc and Ghostscript add about 206 MB to the built app (about 55 MB compressed caches). Build steps are in [SETUP](SETUP.md). Do not replace a binary without verifying source, architectures, dependencies and signing.

## Non-functional requirements

- **Memory:** sequential processing; bounded thumbnails; pixel caps (100 MP full decode, 64 MP clipboard, 40 MP Markdown source); `MemoryProfilingTests` and `scripts/memory-fixtures.swift` for profiling. Large-image profiling remains open.
- **Responsiveness:** codec work off MainActor. Two existing main-thread responsiveness warnings in HEIC tests remain.
- **Timeouts:** Oxipng 30/60 s, Ghostscript 120 s, Markdown print 60 s (soft).
- **Availability:** watching requires the app running; Launch at Login optional.
- **Scale:** personal workloads; test target 50 simultaneous arrivals.

## Deployment

Local Xcode builds only, ad-hoc or development signed. No Developer ID, notarization or public distribution. See [SETUP](SETUP.md) for the local Release build.

## Observability

Logging categories (os.Logger) when added: FileAccess, Conversion, UI, Permissions, Errors. Log operation IDs and error categories; never image contents, GPS or complete user paths. The user-facing record is the 200-entry activity history.

## Architecture decision records

### [2026-09-29] Native Apple frameworks first
**Status:** Accepted
**Context:** Needed local, sandbox-friendly conversion without dependency risk.
**Decision:** Use ImageIO, Core Graphics and PDFKit; no Swift packages. Researched Swift Package Index ImageIO listings and SDWebImage's coder; neither adopted.
**Consequences:** Small dependency surface. PDFKit cannot set exact DPI/quality; WebP/AVIF unsupported.

### [2026-09-29] UserDefaults instead of a database
**Status:** Accepted
**Context:** Persisted data is small: preferences, folder bookmarks, 200 history entries.
**Decision:** UserDefaults/@AppStorage with JSON for folders and activity. Validate loaded values; fall back to defaults.
**Consequences:** No migrations or schema files. Durable recovery (planned Undo) needs separate journal files, not UserDefaults.

### [2026-09-29] Publish with link() into a private temporary directory
**Status:** Accepted
**Context:** Must never overwrite originals or existing outputs, even under races.
**Decision:** Encode into a `mkdtemp` 0700 directory in the destination, publish with POSIX `link()`, retry numeric suffixes.
**Consequences:** Atomic no-overwrite. Destinations without hard-link support fail with a write error.

### [2026-09-30] Bundle Oxipng for PNG
**Status:** Accepted
**Context:** ImageIO PNG re-encoding often produced larger files.
**Decision:** Bundle official Oxipng 10.2.1 universal binary, MIT, signed with inherited sandbox.
**Consequences:** About 42% reduction on a sample screenshot; adds a helper process and notices to maintain.

### [2026-10-01] Bundle Pandoc and Ghostscript for documents
**Status:** Accepted (personal use)
**Context:** Needed Markdown to DOCX/PDF and precise PDF image downsampling.
**Decision:** Bundle pinned Pandoc 3.12 and locally built Ghostscript 10.08.0 (arm64). Ghostscript is manual opt-in only. Binaries excluded from Git.
**Consequences:** GPL/AGPL review needed before redistribution; fresh clones need setup; Intel unsupported for these helpers.

### [2026-10-01] AppKit text printing for Markdown PDF
**Status:** Accepted
**Context:** The planned WebKit renderer failed to start its sandboxed content process; Core Text pagination flattened tables.
**Decision:** Pandoc RTF writer plus `NSTextView` printing with native image attachments.
**Consequences:** Links and tables work; print cancellation is soft. Math and Mermaid added on top on 2026-10-13 (see that ADR).

### [2026-10-14] Background jobs run on efficiency cores
**Status:** Accepted
**Context:** Idle cost is negligible (0.0% CPU, about 40 MB, no idle wakeups with the window open), but watched-folder PNG jobs heated the Mac: helper processes (Oxipng, pngquant, jpegtran, Pandoc, Ghostscript) ignored the job's `.utility` priority and ran at default QoS on performance cores. Measured per full screenshot (2915 x 1892): Lossless 1.8 s, Balanced 2.9 s, Maximum 5.6 s (7 s CPU), palette Safe 1.5 s.
**Decision:** `HelperPriority` sets each helper's `Process.qualityOfService` from the job's base task priority (base, because awaiting from the main actor escalates the current priority): `<= .utility` -> `.background` (efficiency cores on Apple Silicon), otherwise `.userInitiated`. Watched-folder/rule and clipboard jobs run at `.background`; Oxipng uses 1 thread there (2 for manual work). Background helper deadlines (including Oxipng's own `--timeout`) are 4x longer so results do not depend on machine load. Manual Compress, Quick Action and exports stay `.userInitiated`.
**Consequences:** Measured 5K screenshot at Maximum: 13 s on performance cores vs 54 s on efficiency cores. Background jobs take longer but draw far less power and leave performance cores free. Maximum (Oxipng level 4) costs about twice Balanced for about 1% smaller PNGs; palette Safe is the cheapest PNG path.

### [2026-10-13] Offline KaTeX and Mermaid for Markdown PDF (stage 6B/6C)
**Status:** Accepted (owner decision)
**Context:** PDF export printed complex TeX and Mermaid as source text. 6B reproduced the 2026-10-01 WebKit failure in the sandboxed app: `WebContent ... Application does not have permission to communicate with network resources`; adding `com.apple.security.network.client` fixes it.
**Decision:** Add the network-client entitlement. `MarkdownGraphicsRenderer` renders math (KaTeX 0.19.0, `trust:false`) and ```mermaid blocks (Mermaid 12.1.0, `securityLevel:'strict'`, `htmlLabels:false`) in one hidden `WKWebView` per document and exports each as a vector PDF snippet (`WKPDFConfiguration.rect`); `MarkdownPDFRenderer` inserts them as attachments (inline math lowered by its depth to the baseline; display math and diagrams centered). The existing RTF/AppKit pipeline, links, bookmarks and tables are unchanged. Lockdown: CSP `default-src 'none'` with `script-src` limited to SHA-256 hashes of the page's own three scripts (injected markup cannot run), inline styles, data: fonts/images only, `base-uri 'none'`, `form-action 'none'`; a content rule blocking every URL, non-persistent data store, navigation limited to the initial `about:blank`, `loadHTMLString(baseURL: nil)`; sources passed as `callAsyncJavaScript` arguments, never spliced into HTML; pages refuse assets containing `</script` or `</style`. Limits: 100 items, 8 KiB per equation, 64 KiB per diagram, 4096 pt edges, 15 s page load, 10 s per item (a timeout abandons the rest), 60 s total. Mermaid styling keys (`themeCSS`, `fontFamily`, etc.) are in its `secure` list so diagram frontmatter cannot override them. The script call uses the completion-handler API so a hung script does not keep the web view alive. Anything that fails keeps its previous output (Pandoc text or code block). All KaTeX fonts are loaded before the first render (with `font-display:block` text is invisible until its face loads). DOCX unchanged (native equations; Mermaid stays code).
**Consequences:** The sandbox now permits outbound connections for the app and for helpers signed with `inherit` (residual risk: a future helper parser bug could reach the network). Every Pandoc call must keep `--sandbox` and Ghostscript `-dSAFER`; other helpers never open sockets. About 1.9 MB of gzipped JS/CSS in the repo, decompressed into Resources at build time. Formula text in PDF is vector but rendered inside the snippet.

### [2026-10-09] Remove floating action and drop windows
**Status:** Accepted
**Context:** Auxiliary panels duplicated main-window actions and added event-monitor complexity.
**Decision:** Delete floating controllers, placement and monitors; the main window owns intake and actions.
**Consequences:** Simpler code; Finder drops go into the main window. Clipboard cards remain.

### [2026-10-10] Finder Action extension with bookmark hand-off
**Status:** Accepted
**Context:** Users wanted compression from Finder without broad entitlements.
**Decision:** Sandboxed Action extension sends a bounded `.orbitcompress` bookmark document to the app; compression stays app-owned.
**Consequences:** No App Group or duplicated compressor; live Finder hand-off needs manual verification.

### [2026-10-11] Rules replace per-folder compression policy
**Status:** Accepted
**Context:** Watched folders needed renaming, moving and conversion, not just compression.
**Decision:** Per-folder ordered rules (first match wins, ordered actions); old settings migrate to an equivalent rule via `WatchedFolder.effectiveRules`.
**Consequences:** Any regular file can be organized; outputs never chain into other folders; no deletion or scripts.

## Security

**Authorization.** No accounts. Access comes from App Sandbox grants only: `com.apple.security.app-sandbox`, `com.apple.security.files.user-selected.read-write`, `com.apple.security.files.bookmarks.app-scope`, and `com.apple.security.network.client` (added 2026-10-13 only because WebKit's content process cannot start in the sandbox without it; the app itself makes no network requests, see the Markdown math ADR). A file grant does not authorize sibling creation; the app asks for the parent folder or another destination and never saves elsewhere silently. Stored paths are never treated as permission; bookmarks are resolved, refreshed when stale, and re-requested when lost. Start and stop scoped access in balanced pairs on every exit path.

**Input validation.**

- File types from bytes, not extensions; directories and non-file URLs rejected.
- Size, pixel, page and count limits listed above are enforced before expensive work.
- Rules: name 1-120 chars, 1-32 conditions, 1-16 actions, values up to 2,000 chars, nonnegative finite numbers, `yyyy-MM-dd` dates, quality 0...1, width/height 1-100,000, format allowlist, rename pattern up to 1,024 bytes. Rules re-validate at execution.
- Rendered filenames: at most 255 UTF-8 bytes; no `/`, `:`, control characters, leading `.`, `.` or `..`, or empty names.
- Quick Action requests: version, byte size, bookmark size and count bounded.
- Markdown: UTF-8 only, binary/NUL rejected, AST sanitized, links scheme-allowlisted.

**Secrets.** None. No API keys, tokens or network services. No environment variables configure the app.

**Attack surfaces and mitigations.**

| Surface | Mitigation |
| --- | --- |
| Malicious Markdown | Pandoc `--sandbox`, sanitized AST, no raw HTML, no fetching, `openat`/`O_NOFOLLOW` resource reads |
| Crafted PDFs to Ghostscript | Generated filenames only (Ghostscript treats `%` and options specially), `-dSAFER`, staged copies, 120 s timeout, protected-structure rejection |
| Path traversal via rename templates | Full rendered-name validation in `AutomationRenameTemplate` and `AutomationFileOperations` |
| Symlink swaps | Symlinks and symlinked ancestors rejected; fingerprints rechecked before replace/remove |
| Shared-folder races | Private 0700 temp directories; `link()` publication |
| Clipboard races | Generation checks; documented residual race |
| Decompression bombs | Pixel/byte caps before decode |
| Helper processes | Fixed paths, argument arrays, inherited sandbox, restricted environment, bounded stderr |

Rule renames use exclusive `renamex_np(RENAME_EXCL)` in place (a case-only change goes through a hidden unique name so no step can overwrite) and verify the renamed file's identity; moves copy, verify and send the source to Trash. Drives without exclusive rename or hard links report a clear unsupported-volume error. Remaining low-severity item: a small check-to-rename window can rename a file swapped in at the same moment (never deletes or overwrites); Move/Copy destinations can be any user-chosen folder.

**Dependency audit.** No package manager. On each helper upgrade verify upstream release hashes, architectures, linked libraries (Pandoc: Apple system libraries only; Ghostscript: libSystem and libiconv), signing, and update licenses and `THIRD-PARTY-NOTICES.txt`. Review GPL/AGPL obligations before distributing a built app.
