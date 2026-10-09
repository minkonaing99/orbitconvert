# Implementation Plan: Markdown Export and Stronger PDF Compression

Status: proposed only. Reviewed 2026-10-01. No application changes, dependency installation, or benchmark execution performed for this plan.

Implementation update: the first version is now implemented with Pandoc and Ghostscript. PDF rendering uses native AppKit printing after WebKit startup and Core Text table-layout feasibility checks failed. Floating-panel references in this historical proposal were superseded by the 2026-10-09 removal. The plan below remains the original proposal; see [actual implementation and limitations](markdown-pdf-implementation.md).

## Decisions and assumptions

Add Markdown-to-DOCX using bundled Pandoc, and Markdown-to-PDF using the same Markdown pipeline followed by native WebKit printing. Add bundled Ghostscript as an explicit stronger PDF compression option. Preserve the existing PDFKit engine and current automatic-optimization defaults.

Assumptions: personal use; macOS 14 or later; offline processing; sandbox remains enabled; existing rectangular action UI, selected-file processing, safe output publication, menu, watched folders, and clipboard remain the foundation. No cloud service, editor, radial interface, or automatic Markdown conversion is included.

First Markdown scope: UTF-8 `.md` and `.markdown`, headings, paragraphs, emphasis, lists, task lists, quotes, fenced code, ordinary links, and GFM tables. PDF defaults to A4 with readable fixed styles; DOCX contains editable text and native document elements. Preserve Unicode. PDF and DOCX need not paginate identically. Block external resources by default; show image alt text and report omitted images. Math rendering, Mermaid, raw HTML, Obsidian wikilinks/transclusions, custom themes, bibliography processing, and image-folder authorization are later work.

The simpler all-native alternative is a Markdown parser plus attributed-string export. Apple exposes Office Open XML document types, but that alone does not establish acceptable GFM table, list, code-block, and document-style export. Prefer Pandoc's existing document writers over building and maintaining that mapping. Native-only remains the fallback if the packaging spike fails. [Apple document types](https://developer.apple.com/documentation/foundation/nsattributedstring/documenttype), [Swift Markdown upstream](https://github.com/swiftlang/swift-markdown), [Pandoc upstream](https://github.com/jgm/pandoc).

## Current architecture and reuse

- `OrbitConvert/FileTypeService.swift` recognizes PDF/ImageIO inputs. `FileItem.isPDF` currently divides PDF from everything else; new Markdown must not fall into image actions.
- `OrbitConvert/FileAction.swift` supplies shared action descriptors and intersections. Add two conversion cases here instead of extending image-only `ConversionFormat`.
- `OrbitConvert/FileActionService.swift` dispatches synchronous engines. `SelectionActionService.swift` processes files sequentially, grouping only image-to-PDF and PDF merge. Each Markdown file must produce its own output.
- `OrbitConvert/ConversionControlsView.swift` runs that selection service in a detached worker. WebKit requires a deliberate asynchronous handoff to MainActor; making existing synchronous engines run on MainActor is not acceptable.
- `OrbitConvert/FileOutputService.swift` already owns private temporary files, collision-safe publication, and cleanup. Reuse it unchanged unless a demonstrated requirement needs a small extension.
- `OrbitConvert/PDFOptimizationService.swift` currently writes with PDFKit. Native options reject exact DPI/quality. Validation checks page count, extracted text, URL-link count, and top-level outline count. Those checks do not prove complete PDF fidelity.
- `OrbitConvert/AutoOptimizationService.swift` and `BatchOptimizationService.swift` also call that optimizer. Watched folders already support replacement through `SafeFileReplacementService.swift`; older prose saying replacement is absent is stale. Clipboard optimization currently handles images.
- `OrbitConvert/OxipngService.swift`, `scripts/embed-oxipng.sh`, and `ThirdParty/oxipng/helper.entitlements` establish the bundled-helper precedent: fixed executable path, argument array, inherited sandbox, bounded cancellation, and no runtime download.

## Backend choices and tradeoffs

| Purpose | Recommended | Tradeoff / alternative |
| --- | --- | --- |
| Markdown parsing and DOCX | Bundled Pandoc | Larger app and GPL notices; avoids a new DOCX writer. Official 3.12 release has arm64 and x86_64 macOS archives. Pin and verify a tested release rather than resolving latest during build. |
| Markdown PDF layout | WebKit HTML printing to PDF | Native engine; pagination and sandbox behavior require an early spike. Do not assume `createPDF` provides ordinary print pagination. |
| Stronger PDF reduction | Bundled Ghostscript `pdfwrite`, manual opt-in | Can downsample/recompress embedded images, but rewrites PDF structure. Suitable only for inputs passing the safety policy below. |
| Conservative extra PDF optimization | Defer qpdf | Content-preserving structural compression and optional JPEG optimization; no image resampling. Useful if real samples show sufficient savings, but not a substitute for Ghostscript's downsampling. |

[Pandoc releases](https://github.com/jgm/pandoc/releases/tag/3.12), [WebKit print operation](https://developer.apple.com/documentation/webkit/wkwebview/printoperation(with:)), [WebKit PDF capture](https://developer.apple.com/documentation/webkit/wkwebview/createpdf(configuration:completionhandler:)), [qpdf size optimization](https://qpdf.readthedocs.io/en/stable/cli.html#optimizing-file-size).

Pandoc is GPL-licensed. Ghostscript offers AGPL and commercial licensing; its publisher explicitly permits unchanged, undistributed personal use of the AGPL release. This plan assumes no distribution and retains license/provenance records. Revisit licensing before sharing an app bundle or distributing publicly. A separate process is not a blanket licensing exemption. qpdf uses Apache 2.0. [Pandoc license](https://github.com/jgm/pandoc/blob/main/COPYING.md), [Ghostscript FAQ](https://ghostscript.com/faq/), [qpdf license](https://github.com/qpdf/qpdf/blob/main/LICENSE.txt).

## Implementation steps

### Phase 1: Prove packaging and output quality

1. **Run narrow feasibility spikes before product integration.** Proposed locations: temporary development harness, then findings in this document. Complexity: medium; risk: high; dependencies: none.
   - Run pinned Pandoc with `--sandbox` against representative GFM, producing DOCX and HTML. Confirm embedded data files support DOCX in sandbox mode. Inspect archive architectures, deployment minimum, dynamic-library dependencies, signatures, and license files.
   - Prove WebKit printing creates a multi-page A4 PDF with selectable text, margins, repeated table behavior, long code blocks, Unicode, and no blank/clipped pages on macOS 14. Use `printOperation(with:)` and a save-to-PDF print job with no print panel. Determine whether an additional printing entitlement is actually required; do not weaken the sandbox to make it work.
   - Build or obtain a provenance-verified Ghostscript macOS executable and its required resources. Do not assume upstream provides a self-contained macOS binary or that copying Homebrew's `gs` copies its libraries/fonts. Prefer a pinned source build with bundled resources and no Homebrew runtime paths.
   - Exercise each helper from a signed, installed app outside Xcode. Compare Ghostscript and current PDFKit on several image-heavy, scanned, text/vector, and already optimized samples. Record bytes, time, visual differences, and skipped features.
   - Gate: continue only when the offline, signed-sandbox path and output fidelity work. If WebKit pagination fails, investigate native print layout before adding another PDF engine. Do not silently bundle TeX, Chromium, Python, or LibreOffice.

2. **Bundle verified tools.** Proposed files: `ThirdParty/pandoc/`, `ThirdParty/ghostscript/`, `scripts/embed-document-tools.sh`, `OrbitConvert.xcodeproj/project.pbxproj`. Complexity: medium; risk: high; dependency: step 1.
   - Follow the existing Oxipng copy/sign pattern; keep licenses, source/release identifiers, SHA-256 hashes, architecture list, and resource manifests. No build-time or runtime downloads.
   - Sign nested executables and any libraries correctly before signing the app. Use only `app-sandbox` and `inherit` as sandbox entitlements for inherited helpers.
   - Apple states that child processes inherit static sandbox rights, not later PowerBox grants. Parent reads authorized sources into a private job directory inside its container; child sees only generated input/output names there. Parent copies the validated candidate into the existing destination temporary file and publishes it. Keep source/destination grants alive until their operations finish. This avoids relying on child access to user-selected paths. [Apple sandbox inheritance](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html).

### Phase 2: Markdown conversion

3. **Add a bounded document pipeline.** Proposed files: `OrbitConvert/PandocService.swift`, `OrbitConvert/MarkdownConversionService.swift`, `OrbitConvert/MarkdownPDFRenderer.swift`; optionally one small `BundledToolRunner.swift` used by both new helpers. Complexity: medium; risk: high; dependency: step 2 for Pandoc.
   - Validate extension plus bounded UTF-8 text; Markdown has no trustworthy magic signature. Reject binary/NUL content and report invalid encoding. Start with a documented 10 MiB Markdown limit and bounded AST depth/output size; treat these as conservative initial limits to profile, not measured maxima.
   - Parse GFM to Pandoc JSON with raw HTML disabled. Transform a bounded AST before either writer: replace images with alt text, discard raw nodes, and permit only ordinary `https`, `http`, `mailto`, and internal-fragment links. Reject unsupported URL schemes and unrecognized unsafe constructs. No regex-based HTML sanitization.
   - Feed the same sanitized AST to DOCX and HTML writers with fixed app-owned options. No user filters, Lua, templates, defaults files, executable directives, or PDF engines. Source metadata cannot choose command arguments. Do not inherit a user Pandoc data directory or configuration.
   - Pandoc recommends `--sandbox` for untrusted content, embedded data files for sandboxed DOCX, and timeouts; its HTML is not inherently safe. These are additional boundaries, not substitutes for AST/resource restrictions. [Pandoc security guidance](https://pandoc.org/MANUAL.html#security).
   - Load generated HTML into an ephemeral WebKit instance with JavaScript disabled, fixed bundled CSS, restrictive CSP, and blocked navigation/resource requests. No source-directory base URL. Deny file/network/data resource loading for the first text-only release. User links remain document links but are never fetched during conversion.
   - Keep WebKit creation, delegates, and print lifecycle on MainActor; retain the renderer through completion. Run parsing/process/file work off MainActor. Cancellation stops navigation/helper work and prevents publication, even if a native print callback arrives later. Apply a timeout to both loading and printing.
   - Reopen PDF with PDFKit, check page count/boxes and expected text markers. Validate DOCX as an actual Office Open XML package through a tested native reader and round-trip fixture checks; a ZIP header alone is insufficient. Final output uses existing collision-safe publication.

4. **Expose existing UI actions.** Existing files: `FileTypeService.swift`, `FileAction.swift`, `FileActionService.swift`, `SelectionActionService.swift`, `ConversionControlsView.swift`, `ContentView.swift`. Complexity: medium; risk: medium; dependency: step 3.
   - Add Markdown identification and a document icon fallback. Add `.markdownPDF` and `.markdownDOCX` conversion actions with stable IDs. Preserve image-only `ConversionFormat`; explicitly filter actual images for image-to-PDF rather than treating every non-PDF as an image.
   - Make dispatch/selection entry points async where required and add `await` at their callers/tests. Replace the synchronous `Result` closure in the detached worker with async `do/catch`; preserve cancellation and per-file successes. Existing codecs remain off MainActor.
   - Show PDF/DOCX in the current conversion picker and floating panel. Markdown batches export one document per input. Mixed selections expose only valid common actions. No Compress action for Markdown.
   - Use one default style and A4 initially. Report omitted resources explicitly. Reuse output-folder prompts, progress, cancellation, and reveal behavior. Do not add settings panels or Markdown watch/clipboard support.

### Phase 3: Stronger manual PDF compression

5. **Add Ghostscript behind the existing optimizer boundary.** Proposed `OrbitConvert/GhostscriptService.swift`; existing `PDFOptimizationService.swift` and `CompressionModels.swift`. Complexity: medium; risk: high; dependency: steps 1-2 for Ghostscript. This phase can proceed independently of Markdown UI.
   - Introduce an explicit PDF backend option with `.native` as the default. Keep current native preset behavior and exact-DPI rejection. Add a compact manual-only "Stronger PDF compression" choice in `ConversionControlsView.swift` and pass it through `FileActionSettings`.
   - For the stronger backend, start with two measured profiles: Balanced targets 150 DPI color/grayscale and 300 DPI monochrome; Maximum targets 100 DPI color/grayscale and 300 DPI monochrome. Never upscale images. These are proposed image targets, not claims about current PDFKit or full-page rasterization.
   - Use explicit downsample/filter parameters and a fixed app-owned JPEG configuration verified against the pinned Ghostscript build. Do not equate Ghostscript's JPEG configuration with ImageIO's 0...1 slider, and do not advertise exact JPEG quality until the spike demonstrates it. Avoid opaque `PDFSETTINGS` presets as the product specification.
   - Use `pdfwrite`, preserve vector/text content where supported, and never render every page to a bitmap as the compression implementation. Ghostscript rewrites the document and can alter or lose nonvisual features; links/widgets are specifically problematic. [Ghostscript high-level devices](https://ghostscript.readthedocs.io/en/latest/VectorDevices.html).
   - Compare one validated stronger candidate with the original and publish only if smaller. Do not run a costly multi-engine search per file. "No useful reduction. Original kept." remains a successful no-change result. Text/vector PDFs and already compressed scans may shrink little or grow.

6. **Apply PDF safety gates before publishing.** Proposed `OrbitConvert/PDFOptimizationValidation.swift`; existing `PDFOptimizationService.swift` and focused tests. Complexity: medium/high; risk: high; dependency: step 5.
   - Reject encrypted PDFs, including ones that open without a password; reject signed/certified PDFs. Rewriting cannot preserve existing digital signatures. No password stripping or signature override in this feature.
   - For the first stronger-backend release, conservatively skip forms/XFA, annotations, outlines, attachments/portfolios, layers, tagged PDFs, and declared archival/print-conformance documents. Tell the user which unsupported feature was found. This avoids pretending that the current count-based validator preserves interactive or accessibility semantics. Later support requires feature-specific comparison fixtures, not a bypass switch.
   - Inspect actual PDF structures using Core Graphics/PDFKit, including catalog and field dictionaries, with bounded traversal and cycle detection. Never use a raw byte search as proof that signatures or features are absent. If inspection is incomplete or ambiguous, do not use the stronger backend.
   - Check candidate opens, is unencrypted, has the same page count, page boxes, rotations, and per-page extracted text. Strict text comparison may reject valid rewrites; keeping the original is acceptable. Add visual comparison fixtures for images, vectors, transparency, color, rotation, and OCR text. These checks reduce risk; they do not certify arbitrary PDF semantic equivalence.
   - Put the signed/encrypted protection in the shared optimizer entry point so manual, batch, and watched-folder callers cannot bypass it. Keep stronger compression out of automatic replacement and out of global compression defaults initially. Existing watch replacement still uses its current stable-source/rollback checks; do not rewrite that service.

## Process and resource boundaries

Use `Process.executableURL` at a fixed bundle path and `Process.arguments`; never a shell, external PATH lookup, arbitrary executable picker, or user-supplied command fragments. New helpers may share a small concrete runner because there are two actual consumers; do not refactor Oxipng into a new plugin framework.

Create each job directory with mode 0700 and generated filenames, set it as the working directory, and use a minimal environment. Never pass original filenames to Ghostscript, where percent/device and option syntax have special meaning. Keep `-dSAFER`, fixed PDF input handling, and bounded stderr capture. Do not set `NOSAFER` or broadly allow filesystem paths. Configure temp/resource lookup inside the container or signed bundle. [Ghostscript invocation and security options](https://ghostscript.readthedocs.io/en/latest/Use.html).

Initial budgets: 60 seconds per Markdown helper/render step and 120 seconds per PDF helper; sequential jobs; terminate then bounded forced termination on cancellation/deadline. Cap input bytes, generated output bytes, page count, and AST nesting before expensive work; profile and document PDF limits during phase 1. A timeout alone is not a memory ceiling: use supported runtime limits where available and verify memory behavior with pathological fixtures. Clean only job-owned artifacts, and never publish after cancellation. The inherited helper sandbox does not provide a separate privilege boundary from its parent; introduce an XPC service only if the spike demonstrates a requirement for stronger isolation.

Local image support is a separate follow-up: explicit folder/file grant, canonical path containment, symlink/escape rejection, decoded image type and size checks, staged copies, and identical PDF/DOCX resource rules. Remote fetching remains outside this plan.

## Testing and completion gates

Use RED -> GREEN -> REFACTOR for implementation. Add tests only with executable behavior, not empty scaffolding.

- `FileTypeServiceTests.swift`, `FileActionTests.swift`, `FileActionCategoryTests.swift`: Markdown detection, invalid UTF-8/binary rejection, mixed selections, document-only actions, and no accidental image-to-PDF routing.
- Proposed `MarkdownConversionServiceTests.swift` and `MarkdownPDFRendererTests.swift`: headings/lists/tables/code/Unicode, editable DOCX, multipage PDF, stable margins, resource omission, malicious links/raw HTML, denied local/network reads, no execution directives, timeout/cancellation, collisions, cleanup, and unchanged source bytes.
- Proposed `GhostscriptServiceTests.swift` and existing `PDFOptimizationServiceTests.swift`: real bundled helper, substantial reduction on a deterministic oversized-image fixture, text/OCR/geometry retention, protected-feature rejection, malformed input, no-reduction, helper crash, cancellation, and unchanged originals. Include a fixture that fails the current count-only check despite lost semantics.
- Existing selection/output/watch/clipboard tests remain regression gates. Assert stronger mode never becomes an automatic watched-folder default. Verify signed/encrypted input is not replaced by any optimizer path.
- Run full tests with code coverage and both architecture builds using a fresh `/tmp` result path. Example: `rtk xcodebuild test -project OrbitConvert.xcodeproj -scheme OrbitConvert -destination 'platform=macOS' -derivedDataPath /tmp/OrbitConvert-document-tests -enableCodeCoverage YES -resultBundlePath /tmp/OrbitConvert-document-tests.xcresult`.
- Existing `docs/testing.md` records 62.30% full-app coverage, below the required 80%. Measure the current baseline again; require at least 80% for new executable conversion code and report full-app coverage honestly. Meeting the repository's full-app 80% gate also needs coverage of existing code; do not claim this feature alone automatically fixes that deficit or hide files from coverage.
- Verify a signed installed app, including helper signatures, with no Homebrew/TeX on PATH. Test macOS 14 and current macOS; exercise Intel separately before claiming Intel runtime support. Check output grants, restart, revoked access, keyboard/VoiceOver, responsiveness, and cancellation.
- Open DOCX in Word or Pages and PDF in Preview; compare long tables/code, Unicode/font fallback, images/scans, and OCR text. Record benchmark inputs and fidelity limits. No universal compression percentage guarantee.
- After nontrivial implementation use code-review and fix critical/high findings. Perform security review before committing. Update `docs/api.md`, `docs/architecture.md`, `docs/pdf-compression.md`, `docs/testing.md`, and `docs/release_notes.md` after behavior is verified.

## Success criteria

- [ ] Markdown files export through existing actions to readable paginated PDF and editable DOCX, fully offline.
- [ ] Untrusted Markdown cannot read arbitrary files, fetch resources, or execute content during conversion.
- [ ] Stronger PDF mode measurably improves representative image-heavy inputs while preserving the original and rejecting unsupported protected content.
- [ ] Native engines, menu, watched folders, clipboard, selection behavior, and output safety retain regression coverage.
- [ ] Helper bundling, signing, cancellation, sandbox behavior, coverage results, and supported runtime matrix are recorded with evidence.

No user decision blocks this plan. Packaging, pagination, memory limits, and compression profile quality are implementation feasibility gates, not proven results. Preserve existing dirty app-icon/menu/dock edits throughout implementation.
