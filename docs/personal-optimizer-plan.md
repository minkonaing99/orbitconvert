# Personal optimizer improvement plan

Date: 2026-10-03
Status: detailed proposal; no application implementation is included.
Scope: personal, local/offline use of the existing OrbitConvert application.

## Goal and constraints

Make daily optimization safer, add useful image controls, improve document export, and measure results against Clop. Similar workflows do not establish equivalent compression quality, speed or reliability. No side-by-side Clop benchmark has been completed.

Keep the current conversion engines, rectangular action interface, security-scoped access and single sequential watcher/clipboard queue. Extend existing services instead of building another engine, task scheduler or general workflow framework. Keep immutable job settings and return new result values. Create proposed files only when their behavior is implemented.

All application paths below are relative to `OrbitConvert/`; test paths are relative to `OrbitConvertTests/`. The implementation should follow the existing Swift conventions, keep functions focused and use separate files only for cohesive new behavior. Documentation belongs in `docs/`.

## Verified starting points

| Area | Current integration point | Consequence for this plan |
| --- | --- | --- |
| Replacement | `SafeFileReplacementService.replace` stages beside the source, retains a backup during `replaceItemAt`, then deletes it on success | Durable Undo needs persisted intent and retained originals, not just a UI button |
| Automatic work | `WatchedFoldersController.enqueue/drain`, `AutoOptimizationService.process` | Extend the shared queue; retain clipboard generation checks, watcher pause and retry behavior |
| History | `WatchActivity` in `AutoOptimizationService.swift`; 200 entries in UserDefaults | History can reference recovery IDs but cannot be the recovery journal |
| Image optimization | `ImageOptimizationService.optimize/encode`; Oxipng for PNG; validator requires unchanged pixel dimensions | Add an explicit resized-dimensions contract without weakening Compress |
| Actions | `FileAction`, `FileActionSettings`, `FileActionService.execute`, `ConversionControlsView` | New image tools use current action selection, options and batch execution |
| Folder settings | `WatchedFolder` uses synthesized Codable; queued tuples contain folder IDs | Add decoding defaults and immutable policy snapshots deliberately |
| Markdown | GFM to sanitized JSON AST; DOCX writer or RTF plus `MarkdownPDFRenderer` | Native DOCX math can ship independently of a new equation/diagram renderer |

Last recorded baseline: **104 passing tests**, **60.60% whole-app coverage**, Release build and strict deep signature verification passed. Source: [testing](testing.md). These are previous measurements, not checks run for this documentation change. Installed-app tests, macOS 14 runtime and Intel document-helper execution remain unverified. Existing document helpers are arm64; compiling an Intel target is not runtime validation.

## Delivery order and merge boundaries

| Stage | Deliverable | Depends on | Complexity / main risk |
| --- | --- | --- | --- |
| 0 | Reproducible benchmark fixtures and measurements | None; establish alongside stage 1 | Medium / misleading comparisons |
| 1 | Durable Restore Original and crash recovery | Existing replacement and watcher services | High / data loss and filesystem races |
| 2 | Manual Resize + Optimize | Existing image/action/output services | Medium / orientation and metadata fidelity |
| 3 | Opt-in palette PNG reduction | Backend, metadata and licensing feasibility | Medium / lossy output and helper behavior |
| 4 | Image target size | Stage 2 for optional resize; stage 3 only for palette PNG | Medium / cost and unattainable targets |
| 5 | Additional folder rules | Basic filters independently; advanced policies after stages 2-4 | Medium / migration and overlapping roots |
| 6 | DOCX equations, then offline PDF math/Mermaid | DOCX independent; other rendering needs feasibility proof | High for renderer / sandbox and resource isolation |

Start implementation with stage 1. Each stage has its own tests and review gate. Stage 5 basic rules and stage 6 DOCX equations can be delivered independently when priorities change; dependency gates still apply. Do not enable new automatic destructive behavior before its manual/service path and recovery interaction pass.

## Stage 0: Establish an honest comparison

### Work packages

1. **Define fixtures and protocol** - Record in `docs/optimization-benchmarks.md` when fixture selection begins. Use original or licensed private copies with hashes, categories and dimensions. Never benchmark watched originals. Include text-heavy screenshots, transparent graphics, gradients, photos, high-quality JPEG, HEIC, scanned/image-heavy PDFs and text/vector PDFs. Include already optimized files and malformed inputs as safety cases.
2. **Measure the current application** - Record hardware, OS, application/helper versions, preset, metadata policy, resize policy, input/output bytes, elapsed time, peak memory, outcome and reason. Run one warm-up and at least three measured repetitions per fixture; retain individual measurements and report medians. Separate cold launch from encoding time and single-file from batch timing.
3. **Compare Clop when available** - Use the same originals and comparable fidelity policies. Record exact Clop version and all applicable settings. Equal JPEG quality numbers do not imply equal visual quality. Separate lossless, lossy, resized and metadata-stripped results; do not merge them into one savings ranking. The [Clop upstream repository](https://github.com/FuzzyIdeas/Clop) establishes product context, not measured parity or permission to copy its assets/code.
4. **Validate and exercise load** - Compare normalized decoded pixels and alpha for lossless PNG. Inspect lossy text/edges/gradients at normal size and magnification. For PDFs, check text, page geometry, navigation and representative rendered pages. Run a mixed batch and 50 simultaneous arrivals; measure idle energy separately. Record recovery-backup storage separately from optimized payload bytes.

### Exit criteria

Every measured row is reproducible from the recorded fixture and policy. Invalid output counts as failure regardless of savings. Report per-category results and sample count; make no universal savings claim. If Clop is unavailable, label that column **Not measured** and continue OrbitConvert work.

## Stage 1: Durable Undo / Restore Original

### User contract

Initial scope is successful watched-folder **Replace Original** jobs. Manual actions already keep sources; Keep Both and Move Original to Trash retain their current meanings. Trash is operating-system recovery, not indexed Undo. Clipboard Undo and multiple redo generations are outside this stage.

Add Restore Original to eligible detailed activity rows and a recovery list in Settings. The recovery list must remain available when its activity row ages out of the 50-entry history. Display Restorable, Needs Access, Conflict, Recovery Required and Expired states with a useful action. Removing a watched folder must not silently delete its recoveries.

Provisional limits: **seven days, 100 restorable entries, 1,000,000,000 bytes of original payload**, whichever limit is reached first. Explain that count/storage pressure can expire originals earlier. Show retained bytes separately from optimization savings. Never purge an unresolved transaction to satisfy a quota. If safe capacity cannot be reserved, skip replacement and leave the original intact; never silently replace without Undo.

### 1A. Journal and deterministic recovery tests

**Files:** new `OptimizationRecoveryStore.swift`, new `OptimizationRecoveryTests.swift`. Complexity: medium; prerequisite for replacement changes.

Use versioned, bounded per-entry JSON files in a private Application Support recovery directory, written through temporary files and atomic replacement. Avoid a database, append-only event system or a second index requiring coordinated commits. Derive the small UI list from journal records; do not use UserDefaults for transaction durability. Inject a clock and narrow filesystem/failure hooks only where crash tests require them.

Each record holds a UUID, schema version, state, timestamps, folder ID, retained security-scoped bookmark, root/volume identity, relative source path, generated sibling backup/staging names, original and candidate byte counts/SHA-256 hashes, source fingerprint and observed post-swap fingerprint. Restore transactions also record their rollback artifact names. Use bounded decoding and validate every relative path component; malformed records are quarantined for inspection, not interpreted as cleanup commands.

The original fingerprint detects concurrent writes; a streaming hash verifies byte identity after copy/restore, where inode and timestamps can legitimately change. Hash opened regular files off MainActor with cancellation between chunks, and check identity before/after reading. Hashes do not authorize access or prove a path is safe.

| Durable state | Meaning | Restart action |
| --- | --- | --- |
| `prepared` | Validated candidate is staged and intent is stored; swap not started | If source still has original hash and no backup exists, abandon staged candidate safely; otherwise reconcile actual files |
| `replacing` | Swap intent persisted before calling replacement | Original source/no backup means no committed swap; optimized source/valid original backup means promote to `restorable`; other combinations require conservative recovery |
| `restorable` | Valid original backup and optimized source were verified | Revalidate before an action; changed or unavailable source becomes conflict/access status, never an automatic overwrite |
| `restoring` | Guarded restore is in progress; original backup remains intact | Original source means finish restore after verification; optimized source means restore did not complete; ambiguous bytes preserve all copies and require recovery |
| `purgePending` | Eligible backup deletion was explicitly recorded | Retry deletion only for the exact verified owned artifact; a missing artifact finishes cleanup |
| `finished` | Restored, abandoned or expired with a recorded reason | Remove only recorded transient artifacts; retain bounded display information as needed |

`Needs Access`, `Conflict` and `Recovery Required` can be derived/reported conditions, not another sprawling transaction state machine. Unknown schema versions block affected recovery operations and cleanup; they do not justify deleting data.

### 1B. Retain originals through replacement

**Files:** `SafeFileReplacementService.swift`, `AutoOptimizationService.swift`, `WatchedFolderSafetyTests.swift`. Complexity/risk: high; depends on 1A.

1. Resolve the retained folder grant, verify containment/regular-file identity, inspect the stable source, reserve quota and validate the candidate using the existing optimizer checks. Keep the existing `.orbitconvert-replace-*` private same-volume staging directory and `.orbitconvert-backup-*` naming convention.
2. Flush staged candidate bytes and persist `prepared`, then persist `replacing` before the swap. Retain the backup using the existing replacement operation. Account for both filesystem data and journal ordering; atomic JSON replacement alone does not prove durability after power loss.
3. Reopen the result and backup. Require expected candidate/original hashes, type/decode validity and original-preservation evidence. Persist `restorable` before exposing Undo or reporting a safely completed replacement. Return a recovery ID with the result.
4. If validation or journal completion fails after swapping, attempt guarded rollback while keeping the original backup. Never hide a retained-original failure behind the generic message "Original kept." Report Recovery Required when the final state is uncertain.

Reuse [Apple's replacement API](https://developer.apple.com/documentation/foundation/filemanager/replaceitemat(_:withitemat:backupitemname:options:)) at the existing boundary. Verify actual backup and metadata behavior on the supported filesystem. If stronger flush primitives are needed, document them and their platform limits. Promise tested process-crash recovery first; sudden power loss, media failure and nonlocal filesystem guarantees require separate evidence.

### 1C. Guarded restore, startup and loop prevention

**Files:** `OptimizationRecoveryStore.swift`, `SafeFileReplacementService.swift`, `WatchedFoldersController.swift`, `AutoOptimizationService.swift`, `MenuStatus.swift` as needed. Complexity/risk: high; depends on 1B.

- Reconcile journal records before watched folders begin admission. Unmounted/revoked roots remain unavailable without blocking unrelated roots forever. Retain the original bookmark even if folder settings are removed or relinked; a relink to another directory must never redirect an old recovery record.
- Reacquire scoped access for the entire operation and balance successful starts/stops. Refresh stale bookmarks only after resolving and confirming the same root. Offer Grant Access when that fails. Follow [Apple's security-scoped resource lifetime](https://developer.apple.com/documentation/foundation/nsurl/startaccessingsecurityscopedresource()).
- Restore only if the current source still matches the recorded optimized content and identity. A replaced inode with identical bytes is still a conflict unless deliberately reauthorized. Deleted, moved, renamed or edited files use **Save Recovered Copy** through an explicit destination picker and existing collision-safe publication; do not chase files across the filesystem or recreate an old path automatically.
- Copy the retained original into same-volume private staging instead of consuming the sole backup. Persist `restoring` with the optimized rollback path, recheck source identity immediately before swapping, then validate the restored original hash. Preserve the original backup and any captured conflicting version if a writer races or validation fails. Persist completion before cleanup. A successful restore offers no redo.
- Serialize restore/retention mutations through the existing worker's operation boundary. If necessary replace the pending tuple with one small typed job value so restore can share that worker; do not add another optimization queue. Explicit restore should remain usable while automatic watching is paused, and wait for an active job to finish safely.
- Before mutation, suppress admission for the exact affected path; after success update `recent`, all overlapping `RunningWatch.known` sets and queued duplicates. Release suppression on every exit. Reconciliation must seed the same protection before watchers start. The current five-minute recent cache alone is insufficient for durable restore protection.
- Restore must not increment optimized count or savings. Retain historical byte reductions as historical activity, mark the row Restored and label session savings as optimization reductions rather than currently freed disk space.

No cooperative file coordinator can stop arbitrary external writers. Use descriptor-relative no-follow access for journaled artifacts and path components where possible, reject symlinks and multiply linked source files for this new replacement path, and recheck identities around pathname APIs. A race must preserve copies and surface conflict, not silently destroy the newer data. Retest inherited behavior rather than claiming race freedom.

### 1D. Retention and interface

**Files:** `WatchMenuView.swift` (`WatchResultRow`/`WatchActivityView`), `CompressionSettingsView.swift`, recovery store, controller. Complexity: medium; depends on 1C.

Add optional recovery IDs with backward-compatible `WatchActivity` decoding; old rows are readable and simply have no Restore action. Keep file contents and full paths out of history/logs. Add compact status/actions, retained bytes and expiration policy without another window architecture.

Run bounded cleanup at startup and before reserving a new backup, not through a continuous polling timer. Evict oldest eligible restorable entries when limits require it, using `purgePending` before unlinking. Missing access defers cleanup and still consumes reserved quota. Unknown, mismatched or unresolved artifacts are never quota candidates. A source larger than the whole quota is skipped before replacement. Keep an independent limit on journal input sizes/count scanning so corrupt storage cannot exhaust launch memory.

Hidden backup files still contain originals, including metadata the optimized file removed. Explain that briefly beside retention controls. Keep private directory/file permissions without broadening source access. Verify filesystem metadata, Finder tags and ACL behavior; disclose any unsupported restoration attributes rather than equating byte equality with complete filesystem restoration.

### Stage 1 acceptance

Unit tests cover every state/file combination, corrupt journal, unknown schema, quota/clock boundaries, denied writes and repeated reconciliation. Integration tests inject failures before/after each durable write, swap, validation and cleanup. Cover edited/deleted/moved source, swapped ancestor, symlink/hard link, missing/corrupt backup, low disk, stale bookmark, folder removal/relink, external volume loss and cancellation at the swap boundary.

Installed-app checks force termination during replacement and restoration, restart twice, restore byte-identical originals and verify no reoptimization. Confirm a new external edit survives every conflict path, a recovery remains reachable after history eviction, and watcher/clipboard ordering and pause still work. Do not enable durable replacement by default until these checks and the non-trivial security/code review pass.

## Stage 2: Manual Resize + Optimize

### Product contract and options

Add a tool action for single-frame JPEG, PNG and HEIC when the matching encoder is available. Offer 25%, 50%, 75%, longest edge 1080/1920 px and custom width/height bounds. **Initial custom mode fits within the box while preserving aspect ratio; it does not crop or stretch.** Display the resulting dimensions before execution. Never enlarge; a larger requested bound is clamped to original dimensions and reported. Keep format and source; publish only a smaller validated result. If dimensions changed but bytes did not shrink, report No useful reduction instead of silently saving an exception.

Use existing options disclosure, selection action intersection and batch error handling. Automatic resizing remains off. TIFF, animation, HDR/gain-map preservation, crop and unrestricted aspect-ratio changes need separate decisions rather than accidental support through ImageIO.

### Work packages

1. **Dimension contract** - Add immutable resize options and result dimensions in `CompressionModels.swift`; put calculation/validation in new `ImageResizeService.swift`. Derive displayed width/height after EXIF orientation, calculate scale once, use deterministic integer rounding and enforce at least one pixel. Reject nonfinite, zero, negative, overflowing or over-budget dimensions before decoding. Preserve existing 100-million-pixel safety limit until profiling supports a smaller explicit allocation budget.
2. **Transform and encode** - Use ImageIO transformed downsampling, then Core Graphics only when needed to obtain the calculated dimensions. Request creation from full image data rather than trusting a small embedded thumbnail. Normalize orientation exactly once. Apple's [ImageIO source guide](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/ImageIOGuide/imageio_source/ikpg_source.html) documents transformed thumbnails and maximum pixel size. Work off MainActor and reuse scoped access, private workspace, cancellation and final publication.
3. **Fidelity contract** - Preserve alpha and color meaning/ICC profile, including when personal EXIF/GPS metadata is removed. Update pixel dimensions and normalize orientation tags; remove stale thumbnails. Do not blindly copy image-dependent or signature/credential metadata after resizing. Retain existing credential rejection and add a preflight for the transform path. Reject unsupported high-bit-depth/HDR cases until fixtures prove preservation; do not silently reduce precision.
4. **Reuse candidate boundary** - Extract the smallest internal encode/validate operation from `ImageOptimizationService` needed by resize and later target search. Candidate generation must not publish user-visible files. Existing Compress still requires unchanged dimensions; resize validation requires its explicit expected dimensions and orientation. PNG may pass through existing Oxipng after the transform. Do not repeatedly call the current publish-on-success `optimize` method for intermediate work.
5. **Wire the tool** - Extend `FileAction.swift`, `FileActionService.swift`, `ConversionControlsView.swift` and relevant action tests. Keep `SelectionActionService` sequencing and report actual dimensions/bytes. The current action list exposes Compress only for JPEG/PNG despite service HEIC support; explicitly test capability checks for the new HEIC action without a broad unrelated action rewrite.

### Acceptance

New `ImageResizeTests.swift`: all eight EXIF orientations, alpha edges, portrait/landscape, odd dimensions, aspect-ratio rounding, no enlargement, malicious dimensions, metadata remove/preserve, color profiles, unsupported multiframe/HDR cases, credential protection, cancellation and larger output. Extend `FileActionTests.swift` and batch tests for mixed availability and collisions. Profile a large source for responsiveness and peak allocation; compare visual orientation, color and alpha in Preview.

## Stage 3: Optional palette PNG reduction

### Backend gate

Keep bundled Oxipng and existing lossless presets unchanged. Add a separate **Allow palette reduction** option, disabled by default, explaining that colors and fine detail may change. No automatic PNG-to-JPEG conversion.

Evaluate a pinned [pngquant upstream build](https://github.com/kornelski/pngquant), its [registry package](https://crates.io/crates/pngquant) and [libimagequant](https://pngquant.org/lib/) before choosing integration. Prefer the isolated CLI pattern already used by `OxipngService`; an embedded library requires extra encoding/metadata ownership. pngquant's documented minimum-quality rejection is exit 99. Its Cocoa reader removes metadata, so test the actual chosen build. GPL/commercial licensing and notices must be resolved before distributing binaries; personal source/setup instructions do not waive redistribution obligations.

### Work packages

1. **Feasibility fixture run** - Record pinned version, build flags, architecture, checksum, notices, quality results and ancillary-chunk/profile behavior in `docs/png-optimization.md`. Proposed initial quality range is 80-100 on pngquant's own scale, subject to screenshot/gradient review; this is not ImageIO's quality scale. If preserve-metadata mode cannot be honored, keep that combination unavailable rather than silently stripping metadata.
2. **Helper service** - Add `PngquantService.swift` only after the gate passes. Follow `OxipngService`'s fixed executable, inherited sandbox, input/output descriptors where supported, private generated filenames, no shell, bounded output/stderr, cancellation and timeout pattern. Start with a 60-second parent deadline and tune from measurements. Never invoke in-place overwrite flags or PATH discovery.
3. **Validate and finalize** - Check exit status before accepting stdout, because rejection paths may return original bytes. Map quality rejection to Skipped. Treat unavailable/crashed helpers separately. Require matching type/dimensions, full decode, single frame and metadata/color policy. Palette alpha may change numerically: test visible transparency and edge quality, do not assert exact RGBA equality for lossy mode. Optionally run Oxipng, then retain only a smaller validated final candidate.
4. **Options and packaging** - Extend the existing compression options/action path; use source-only helper setup and existing embedding/signing conventions if a local helper is selected. Keep watcher/clipboard defaults lossless. Enable their opt-in controls only after manual tests and policy serialization exist.

### Acceptance

New `PngquantServiceTests.swift`: text screenshots, gradients, semi-transparent edges, already indexed/16-bit PNG, ICC/gamma chunks, metadata, credentials, quality rejection, larger output, corrupt output, missing helper, timeout/cancellation and cleanup. Benchmark lossless versus palette results separately. No claim of exact alpha or pixel preservation is allowed for this mode.

## Stage 4: Target file size

### Contract

Start with JPEG/HEIC. The user selects a byte target, minimum quality and optional Allow resize. Use decimal KB/MB, explicitly **1 MB = 1,000,000 bytes**. Suggested target 1 MB and quality floor 0.70 are provisional defaults; nothing runs unless the action is selected. Preserve format/metadata and never silently lower the quality floor. An input already under target needs no re-encode.

Allow resize is off by default. When enabled, require a displayed minimum longest-edge limit; propose 640 px, clamped to the original size. Retain aspect ratio. Target mode owns any dimension search; it is mutually exclusive with a separate fixed resize rule. PDF targeting is outside version one. Lossless PNG can report its best lossless result; palette targeting requires stage 3 opt-in and its own quality scale.

### Work packages

1. **Bounded search** - Add `TargetSizeOptimizationService.swift` and immutable options/result states. Reuse the unpublished candidate boundary from stage 2. For each dimension level, test a deterministic descending grid of at most six qualities between the selected maximum and floor. Observe actual output sizes; do not assume monotonicity or use an unbounded binary search. Stop at the first valid grid candidate under target. This selects the highest tested quality at that level, not a mathematically optimal quality.
2. **Dimension policy** - Try original dimensions first, then at most two smaller levels derived from the best observed size ratio and clamped to the user minimum. Recheck rounding and avoid duplicate dimensions. Prefer original/larger dimensions before quality when comparing levels; state this policy in the UI. Every candidate derives from the original source or an original-derived resized raster, never a prior lossy encode or resized predecessor.
3. **Resource bounds** - Cap six candidates per level, three levels and 18 encodes total. Proposed 60-second overall admission deadline stops new encodes; synchronous ImageIO work cannot be forcibly interrupted safely, so cancellation/time limits are checked between stages and publication. Keep only the current best candidate and current trial, not 18 decoded images. Measure actual memory/time before enabling automatic use.
4. **Result handling** - Distinguish Already within target, Reached target, Unreachable with these limits, Cancelled and Failed. On unreachable target, keep the original, show best observed size and allow an explicit manual Save Best Copy only for a valid smaller candidate. Retain that candidate only in the live result workspace, deleting it on dismissal/expiry. Automatic jobs never save an over-target result or relax policy.
5. **Action integration** - Extend `FileAction.swift`, `FileActionService.swift`, `CompressionModels.swift` and `ConversionControlsView.swift`. Report measured final bytes and actual dimensions. Avoid fabricated percentage progress; show attempts and stage labels.

### Acceptance

New `TargetSizeOptimizationTests.swift`: attainable/unattainable targets, already-small input, invalid/overflow byte units, boundary sizes, nonmonotonic fake encoder results, dimensions-versus-quality preference, attempt/time limits, no cumulative encoding, minimum dimensions, cancellation and metadata. Add real JPEG/HEIC fixtures to check the service against actual codec behavior. PNG targeting is a later slice, not permission to conflate pngquant's quality metric with ImageIO's.

## Stage 5: Additional per-folder rules

### Policy and migration

Keep existing presets, supported types, subfolder choice and original handling. Add only minimum input bytes, relative-path exclusions, optional JPEG/HEIC quality and explicit preserve/remove metadata. Advanced resize/target/palette options arrive after their stages pass. Defaults mean no filters, metadata preserved and all advanced features off, matching current automatic behavior even if manual global defaults differ.

Use one optional versioned rules value on `WatchedFolder`. `decodeIfPresent` with explicit defaults reads old records without resetting IDs/bookmarks. Preserve unknown-version settings and disable the affected rule with a visible explanation; never replace the whole saved folder list with an empty default because one entry failed. Validate ranges on decode and when editing. Test legacy UserDefaults bytes and encode/decode round trips before writing migration output.

### Work packages

1. **Filter contract** - Extend `WatchFilePolicy` in `WatchedFolder.swift`; add `WatchedFolderRulesTests.swift`. Use a small anchored glob syntax: `*` and `?` stay within one component, `**` occupies whole path components, and `/` separates components. Reject absolute paths, `..`, braces, negation and scripts. Specify literal case-sensitive matching and Unicode normalization; bound pattern count/length and use bounded matching rather than unrestricted regex backtracking. Show examples such as `**/*.tmp` and `exports/**`.
2. **Admission and stable recheck** - Apply filters in `WatchedFoldersController.enqueue`, rescans and Optimize Existing, then again in `AutoOptimizationService.process` after stability. Minimum bytes uses the stable size. Never bypass hidden/temp/package/symlink/cloud exclusions. Recheck file type and source fingerprint before publication as today.
3. **Snapshot and overlap** - Store a small immutable accepted-job policy with the queued job; retries retain it. Before starting, still honor folder removal/disable and pause. Settings updates currently stop/restart a folder, so document that queued jobs from that folder are dropped and new admissions use new settings; an already running job keeps its snapshot if it reaches safe completion. Resolve ownership among all enabled containing roots before applying custom filters: most specific eligible root wins, with a stable UUID tie-breaker. A child exclusion does not fall back to a parent policy. Deduplicate each canonical file once, independent of FSEvents delivery order.
4. **Apply policies** - Pass custom quality/metadata into existing image/PDF option values in `AutoOptimizationService`; ensure JPEG/HEIC-only quality does not select `.custom` for PNG/PDF. Target mode owns quality/dimension limits and cannot combine with fixed resize. Palette is independent but legal only for PNG. Reject unavailable helper/policy combinations visibly without falling back to destructive defaults. Durable recovery remains mandatory for Replace Original.
5. **Settings and docs** - Extend `WatchedFoldersSettingsView.swift` with a collapsed Advanced area and per-folder summary. Update `docs/watched-folders.md` with pattern semantics, overlapping-root ownership, settings-change behavior and defaults. Keep current new-files-only baseline: broadening rules does not silently optimize old files; Optimize Existing is explicit.

### Acceptance

Test old configurations, corrupt/unknown rules, bounds/patterns/Unicode, size changes during stability, nested roots with different policies and event orders, child exclusions, pause/retry/remove/relink, settings edits while active, no duplicate jobs and unchanged defaults. Add watcher integration fixtures for each advanced policy only when its stage is enabled. Preserve clipboard scheduling and self-write protection throughout.

## Stage 6: Markdown equations and Mermaid

### 6A. Editable DOCX equations first

**Files:** `MarkdownConversionService.swift`, `MarkdownConversionTests.swift`, `docs/document-improvements-roadmap.md`. Complexity: low-medium; independent of browser rendering.

Verify the bundled Pandoc 3.12 reader's supported extensions and explicitly select dollar/GFM math syntax, for example `gfm-raw_html+tex_math_dollars` if that exact build supports it. Preserve only validated bounded Math nodes through sanitization; do not enable raw TeX, arbitrary filters or script execution. Test inline/display equations, fractions, Greek letters and matrices plus escaped dollars, currency and code blocks.

[Pandoc's math documentation](https://pandoc.org/MANUAL.html#math) specifies OMML for DOCX and a Unicode/verbatim fallback for RTF. Therefore the current RTF/PDF path is not evidence of complete PDF equation rendering. Inspect bounded `word/document.xml` from real DOCX exports for `m:oMath`/`m:oMathPara` and expected structure; text round-tripping alone cannot prove editable equations. Unsupported math retains source notation with a warning. Verify editability in available Word/Pages and label untested applications honestly.

### 6B. Offline renderer feasibility gate

**Files:** initially a disposable experiment and findings in `docs/document-improvements-roadmap.md`; no production renderer until the result is known. Complexity/risk: high.

Reproduce the prior WKWebView startup failure in a clean installed signed sandbox app. Separate renderer startup, local asset loading, JavaScript execution, local font readiness and image capture. Record OS, signing, entitlements and failure evidence. Do not add broad network permission to make a local renderer start. Prove a simple equation and flowchart render offline with bounded dimensions, cancellation, repeated jobs and no leaked WebKit processes/resources.

Prefer pinned local KaTeX plus Mermaid only if WebKit proves reliable. MathJax is an alternative if necessary for supported notation, not a second simultaneous renderer. A Node/Chromium or TeX installation materially changes app size, licensing and maintenance and needs a separate explicit dependency decision. If the experiment fails, ship 6A and preserve notation/diagram source with warnings; do not replace the document engine to force this stage through.

### 6C. Isolated rendering and existing export integration

1. **Bounded inputs** - Add one focused renderer only after 6B. Proposed initial limits: 8 KiB per equation, 64 KiB per diagram, 100 generated objects/document, 500 diagram edges, 4096 px per output edge and the existing 24-million aggregate image-pixel budget. A 10-second per-object deadline and 60-second rendering-stage deadline are provisional and must be enforced against hung rendering, not merely checked afterward.
2. **Safe configuration** - Recognize `mermaid` CodeBlocks before `sanitize` removes their attributes, extract only the language marker and bounded text, then discard user attributes. Reject configuration directives/front matter, remote images/icons and click directives. Use [Mermaid strict mode](https://mermaid.js.org/config/schema-docs/config-properties-securitylevel.html), which encodes HTML labels and disables clicks. It is not a network sandbox.
3. **Resource boundary** - Serve only allowlisted bundled assets and generated job data. Deny navigation, popups, remote/local-file fetches and subresources; use a restrictive content policy plus resource/navigation controls and adversarial tests. Do not interpolate user text into executable JavaScript. For [KaTeX options](https://katex.org/docs/options.html), use untrusted input mode, bounded expansion and no user-supplied shared macro state. Asset versions, licenses/checksums and bundled fonts are documented; builds/runtime never download them.
4. **Embed generated objects** - Feed validated raster output through the existing AST image/`pdfImages` attachment path, without requiring Allow Local Images for app-generated bytes. Local source images still require their existing folder grant. Keep DOCX math native OMML; Mermaid becomes an embedded image. Extend `MarkdownPDFRenderer.attachImages` only as required to preserve equation baseline, inline sizing, display placement and diagram page fit. Test these separately; current page-width image attachment sizing does not establish correct inline math layout.
5. **Fallback and reporting** - Preserve ordinary code blocks. Malformed or unsupported equations/diagrams retain readable source and emit a bounded warning count in `FileActionReport`; do not omit content or claim it rendered. Cancellation publishes nothing and cleans workspaces; native print's existing soft cancellation remains accurately described.

### Acceptance

Verify native DOCX equations, inline/display PDF layout, multipage diagrams, normal code, invalid syntax, budget exhaustion, denied remote/file/resource/configuration attempts, hung renderer, process termination and temporary cleanup. Inspect embedded DOCX media/relationships and rendered PDF pages, not just output existence. Run installed-app offline tests with networking unavailable and available to prove denial rather than assuming it from a disconnected machine.

## Decisions and stop conditions

| Decision | Proposed default | Must resolve before |
| --- | --- | --- |
| Recovery retention | Seven days / 100 entries / 1 GB; unresolved records protected | Stage 1 Settings and capacity tests |
| Durability claim | Process-crash recovery on tested local filesystems | Enabling automatic durable replacement; stronger power-loss claims need evidence |
| Resize semantics | Aspect-ratio fit, no enlargement, smaller output only | Stage 2 UI/tests; crop/stretch remains separate scope |
| PNG backend | Optional isolated pngquant; lossless stays default | Dependency, metadata, quality and redistribution gates |
| Target search | Six qualities, three dimensions, 18 encodes; 0.70 floor, optional 640 px minimum edge | Stage 4 measurements and UI defaults |
| Rules overlap | Most specific enabled eligible root; no parent fallback after child exclusion | Stage 5 admission tests |
| PDF math/Mermaid | Offline WebKit proof before new renderer | Stage 6B; no automatic Node/Chromium/TeX addition |

These are implementation proposals, not completed behavior. If a materially different interpretation changes the outcome, present it before implementation. No extra approval is needed merely to perform already authorized read-only feasibility work.

## Verification and completion gates

For each implementation slice, write and run meaningful failing tests, implement the smallest change, run focused tests plus full regression and Release build, then complete non-trivial code review and security review for replacement/parsing/helper paths. Fix critical/high findings before enabling the feature. Documentation-only work is exempt from TDD; no app test run is claimed for this plan edit.

Use isolated fixtures and injectable failure points; never test replacement on personal Desktop/Documents data. Test actual codecs/helpers as well as deterministic service fakes. Aim for at least 80% meaningful coverage on new behavior and measure/report whole-app coverage separately. The repository's whole-app 80% goal is still unmet; do not exclude UI/services or imply new-service coverage closes that gap.

Record build/test commands, versions, coverage, manual outcomes, benchmark rows and unsupported environments in `docs/testing.md` and the stage-specific document. Update `docs/api.md`, `docs/database.md`, `docs/architecture.md` and `docs/release_notes.md` only as real public contracts, persistence or behavior change. macOS 14 and Intel claims require actual available runtime validation.

A stage is complete only when source preservation on failure, output validation, cancellation/no-publication, collision handling, permission recovery and shared queue regressions pass. Security-scoped access must outlive the whole operation. Show truthful stage/attempt progress; do not invent encoder percentages. Preserve clipboard generation/self-write protection, protected document rejection and watcher loop prevention.

## Scope exclusions and next implementation

No radial interface, video engine, cloud processing, analytics, automatic downloads, engine rewrite, second queue, arbitrary folder scripts, redo stack or public-release packaging. No promise that every file shrinks, every target is reachable or OrbitConvert equals Clop.

Next implementation is **stage 1 only**: journal and reconciliation tests, retained replacement, guarded restore, retention/UI, then installed-app crash and permission checks. Establish stage 0 fixtures alongside it. Complete that safety gate before moving to Resize + Optimize.
