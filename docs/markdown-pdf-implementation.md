# Markdown export and stronger PDF optimization

## Implemented behavior

UTF-8 `.md` and `.markdown` documents up to 10 MB can be imported through Choose Files or drag-and-drop. Their actions are PDF and DOCX. Batch selection exports each document separately. Source files are kept and existing results are never overwritten.

Pandoc 3.12 parses GFM into a bounded JSON syntax tree. Both writers receive a sanitized copy with empty metadata, removed raw nodes, no user attributes, and only HTTP, HTTPS, mailto, or internal-fragment links. By default images become alt text. Under Options, **Allow Local Images** explicitly grants access to a folder containing the notes and images. Only relative paths beneath that folder are accepted; remote/absolute paths, traversal, symlinks and nonregular files are excluded. Image reads use descriptor-relative `openat` with `O_NOFOLLOW` for every path component. Nothing downloads resources.

Supported local image resources are PNG, JPEG, TIFF and HEIC. ImageIO validates and normalizes orientation into PNG while preserving transparency. Resources are downsampled to at most 2,400 pixels on the longest side for document use. Limits are 20 MB per input, 40 million source pixels, 100 resources, 24 million aggregate embedded pixels and 40 MB aggregate encoded resource data. Excess or unavailable images become alt text and are reported. Metadata is not copied into document illustrations. Originals are not modified. Pandoc receives only normalized PNG data URIs while keeping `--sandbox`; it never receives source image paths.

DOCX uses Pandoc's Office Open XML writer and is reopened with its DOCX reader to validate meaningful text. PDF uses Pandoc's RTF writer and AppKit `NSTextView` printing to A4 with 40-point margins, without a print dialog. Native printing preserves external clickable links. PDF options include A4/US Letter, serif/sans body font, 8-24 point body size and 20-90 point margins. These style controls affect PDF only; DOCX retains its editable Pandoc styles. Heading proportions and code font distinction are retained.

AppKit's RTF importer dropped embedded `pict` images during testing. The PDF branch therefore replaces sanitized image nodes with random internal markers before RTF generation and inserts native `NSTextAttachmentCell` images after import. Images fit the printable page without enlargement. AppKit supports RTF table blocks; a table-header position test guards against flattened columns. Native print callbacks stay on MainActor; parsing, helpers, and output handling stay in the detached selection task. Cancellation waits for an in-flight native print operation to finish before cleaning its files and never publishes the cancelled result. A 60-second print deadline marks the result timed out; it cannot forcibly interrupt Apple's native print job.

The planned WebKit renderer failed repeatedly when starting its sandboxed content process. Core Text pagination was also tested but flattened tables. Both were replaced by native AppKit text printing. No network or printing entitlements were added. Internal PDF anchors, long tables, exceptionally wide code, complex scripts and font fallback need further work or visual checks. Raw HTML, Mermaid, math and Obsidian links/transclusions remain outside this stage.

## Stronger PDF compression

For a PDF selection, expand Options and enable **Stronger PDF compression**, then choose Balanced or Maximum and Compress. Lossless continues to use PDFKit. This is a manual-only option; watched folders retain the native backend.

The new Ghostscript 10.08.0 helper uses `pdfwrite`. Balanced targets 150 DPI color/grayscale images; Maximum targets 100 DPI. Monochrome target is 300 DPI. Targets apply to embedded images, not entire rasterized pages; compression is lossy. Duplicate-image detection and font compression are enabled. No exact ImageIO-style JPEG quality claim is made.

Strong compression now supports HTTP/HTTPS/mailto link annotations and bounded nested bookmarks. Link annotations are copied onto optimized pages because pdfwrite can omit them; their URLs and geometry are verified after saving. Existing pdfwrite bookmarks are retained and compared recursively by hierarchy, labels, action targets, destination page/coordinates and zoom. Traversal is bounded and chained/unsupported actions are rejected. Native PDF writing uses a separate candidate file before reopening and validation.

Strong compression still excludes encrypted/signed PDFs, forms, other annotations, internal annotation links, attachments/names/named destinations, layers, tagged documents, output-intent documents and automatic actions. Native construction/remapping of internal annotations failed page-reference validation during testing, so that subset remains disabled. Ambiguous protected structures fail safely. The shared native entry point also rejects encrypted or signed documents. Field inspection has depth and total-node limits plus cancellation checks. Input limit is 256 MB and 2,000 pages for PDF optimization; helper time limit is 120 seconds. Source files are staged under generated filenames in private app temporary directories.

Output must reopen with matching page count, page boxes, rotations and per-page extracted text. Metadata removal is applied to the generated candidate when requested. A candidate is saved only when smaller, using existing collision-safe publication. These checks are conservative and do not establish universal visual or PDF semantic equivalence. Manual originals are always retained.

## Bundled tools and reproducibility

Both tools are bundled, not discovered on PATH. Gzip assets decompress locally during the existing helper build phase and receive inherited App Sandbox signing. No download is performed during build or runtime. Processes use fixed executable paths, separate arguments, restricted environments, generated filenames, 0700 job directories, timeout/cancellation handling and cleanup.

Current new helpers are arm64, for this personal Apple Silicon installation. Intel document-tool execution and macOS 14 runtime have not been verified. They add about 206 MB of executable data to the built app; compressed local caches total about 55 MB. These gzip executables are excluded from Git. Fresh clones must follow [helper setup](document-helper-setup.md) before building.

Pandoc archive: [official 3.12 arm64 release](https://github.com/jgm/pandoc/releases/tag/3.12), `pandoc-3.12-arm64-macOS.zip`.

- Archive SHA256: `f148ca09c9f36594db527a9fc988ad736290ce428f79594c50208cd1ec58b3c0`.
- Unpacked executable SHA256: `944a597887d68721af64673df44b366905f1771307bbb57615b299d0cb9245f4`.
- Only Apple system libraries are linked. GPL license is bundled.

Ghostscript source: [official 10.08.0 release](https://github.com/ArtifexSoftware/ghostpdl-downloads/releases/tag/gs10080), `ghostscript-10.08.0.tar.gz`.

- Source archive SHA256: `caf199e3f233f1290b27d0972d636f66c303355f2353309b7bfddf1edda06b3d`.
- Locally built executable SHA256: `a94e0278a8dc5977f9d3c31fc44da5ee2e7e502c208ada974b99dc52692d410e`.
- Built using Apple clang, `MACOSX_DEPLOYMENT_TARGET=14.0`, system-only PATH, configure options `--without-tesseract --without-libidn --without-libpaper --without-x --disable-fontconfig --disable-cups --disable-dbus --prefix=/tmp/orbitconvert-gs`, then `make -j4`.
- Initialization resources are compiled in; only libSystem and libiconv are linked. Source archive includes supporting-library sources. AGPL and third-party notices are bundled.

This is a personal-use implementation. The Git repository publishes source and setup instructions, not these helper executable caches. Sharing the built app or publishing helper binaries requires a separate redistribution/license review, including appropriate source and notice obligations. No public app release was prepared. [Pandoc security guidance](https://pandoc.org/MANUAL.html#security), [Ghostscript build documentation](https://ghostscript.readthedocs.io/en/latest/Make.html), [Ghostscript license FAQ](https://ghostscript.com/faq/).

## Validation

The real-export tests cover editable DOCX round-trip, multipage PDF, Unicode, table columns, code text, collision naming, source preservation and output cleanup. PDF tests exercise image-heavy reduction, selectable text, metadata removal, and annotation rejection. Full regression results and coverage are recorded in [testing](testing.md).

Manual check: import a Markdown note, export PDF and DOCX, and open them in Preview and Pages/Word. Then import a plain image-heavy PDF, enable Stronger PDF compression, and compare its output visually. Protected documents should show an error and retain originals. Test the installed app outside Xcode before relying on these document features for important files.
