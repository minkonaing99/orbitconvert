# Implementation Plan and Tasks

Keep updated. Claude reads this before starting work.

**Current status:** Phases 1-5 and 8-9 delivered; folder automation 2026-10-11; [hardening](HARDENING-PLAN.md) complete and version 2.0 set 2026-10-12. Direction: personal use, manual converter + folder automation ([PRD scope rule](PRD.md#scope-rule)). F1-F8 done 2026-10-13. Next: [FUTURE-FEATURES](FUTURE-FEATURES.md) F9 -> F10 -> F11.

## Phases

| Phase | Scope | Exit condition | Status |
| --- | --- | --- | --- |
| 1 | App shell, macOS 14 target, tests | Build and launch; baseline test passes | Done 2026-09-29 |
| 2 | File selection and drop | Single/multiple imports; invalid items handled | Done 2026-09-29 |
| 3 | Detection and preview | Content-based type, bounded thumbnails, supported actions | Done 2026-09-29 |
| 4 | Image conversion and output | Conversion and safety tests pass | Done 2026-09-29 |
| 5 | In-window action panel | Grouped buttons, keyboard, VoiceOver tested | Done; VoiceOver manual check open |
| 6 | Floating panel | Retired 2026-10-09; main window owns actions | Removed |
| 7 | Configurable modifiers | Distinct conversion/tool mode without global interception | Deferred |
| 8 | Tools | Compression, resize, metadata, image-to-PDF, target size | Done (no standalone metadata inspector) |
| 9 | Finder workflow | Main-window drops; Quick Action | Done; signed live verification pending |
| 10 | Release preparation | Signed sandbox tests, accessibility, performance, release checks | In progress |

Testing, accessibility and sandbox design apply from Phase 1. Advanced Finder integration needs explicit approval before implementation.

### MVP gate (met except manual checks)

- Launch normally and import an image by drag/drop.
- Detect PNG, JPEG, HEIC and TIFF and list available outputs.
- Convert PNG to JPEG, JPEG to PNG and HEIC to JPEG.
- Save without overwriting; show actionable errors.
- Action area buttons invoke valid conversions and tools.
- Core unit tests pass; accessibility checks (manual, open).

## Milestones

| Milestone | Description | Date | Status |
| --- | --- | --- | --- |
| Shell, intake, inspection, conversion | Phases 1-4 | 2026-09-29 | Done |
| PDF conversion and manual compression | PDFKit tools, ImageIO optimization, Settings | 2026-09-29 | Done |
| Watched folders | FSEvents, safe replacement, menu bar | 2026-09-30 | Done |
| Compact main window | Rows + shared action area | 2026-09-30 | Done |
| Oxipng PNG optimization | Bundled lossless helper | 2026-09-30 | Done |
| Clipboard optimization | Monitor, writer, cards, collection | 2026-10-01 | Done |
| Markdown export + stronger PDF | Pandoc, AppKit printing, Ghostscript | 2026-10-01 | Done |
| Document improvements 1-2 | Local images, PDF links/bookmarks, styles | 2026-10-03 | Done |
| Resize + Optimize | Manual resize tool | 2026-10-03 | Done |
| JPEG target size | Compress to Size | 2026-10-09 | Done |
| Activity history UI | Saved history window | 2026-10-09 | Done |
| Remove floating windows | Main window only | 2026-10-09 | Done |
| Finder Quick Action | Compress with OrbitConvert | 2026-10-10 | Done |
| Folder automation | Rules, rename, move/copy, preview, retry | 2026-10-11 | Done |
| Release verification | Signed/installed, macOS 14, Intel, VoiceOver | TBD | Open |

## Roadmap (personal optimizer plan, 2026-10-03)

Constraints: keep current engines, the action UI, scoped access and the single sequential queue. Extend services; no new engine, scheduler or workflow framework. Each stage has its own tests and review gate.

| Stage | Deliverable | Status |
| --- | --- | --- |
| 0 | Benchmark fixtures and measurements (vs Clop where available) | Not started |
| 1 | Durable Restore Original and crash recovery | Dropped 2026-10-11 (owner decision; Keep Both covers the need) |
| 2 | Manual Resize + Optimize | Done 2026-10-03 |
| 3 | Opt-in palette PNG reduction (pngquant) | Not started; license gate |
| 4 | Target file size | Partly done: JPEG Compress to Size (different search than proposed). HEIC/PNG, quality floor and Save Best Copy not done |
| 5 | Per-folder rules | Superseded by folder automation (2026-10-11) |
| 6 | DOCX equations, then offline PDF math/Mermaid | Not started |

### Stage 0: Honest comparison

Record fixtures with hashes, categories and dimensions in a new benchmark doc section (text screenshots, transparent graphics, gradients, photos, HEIC, scanned and vector PDFs, already-optimized and malformed files). Record hardware, OS, versions, preset, metadata policy, bytes, time, peak memory and outcome; one warm-up plus at least three runs, report medians. Compare Clop only with the same originals and comparable policies; label "Not measured" otherwise. Invalid output counts as failure. No universal savings claim.

### Stage 1: Durable Restore Original (dropped 2026-10-11, kept for reference)

Scope: successful watched-folder Replace Original jobs. Add Restore Original to activity rows and a recovery list in Settings that survives history eviction. States shown: Restorable, Needs Access, Conflict, Recovery Required, Expired. Provisional limits: seven days, 100 entries, 1,000,000,000 bytes of original payload. If capacity cannot be reserved, skip replacement and keep the original; never replace without Undo.

1. **Journal** (`OptimizationRecoveryStore.swift`, tests): versioned bounded per-entry JSON in private Application Support, atomic writes, no database, not UserDefaults. Record UUID, schema version, state, timestamps, folder ID, bookmark, root/volume identity, relative path, backup/staging names, byte counts and SHA-256 hashes, fingerprints. Quarantine malformed records.
2. **Durable states:** `prepared`, `replacing`, `restorable`, `restoring`, `purgePending`, `finished`, each with a defined restart reconciliation. Unknown schema versions block cleanup.
3. **Replacement** (`SafeFileReplacementService`, `AutoOptimizationService`): persist `prepared` then `replacing` before the swap, verify hashes after, persist `restorable` before reporting success. Report Recovery Required when uncertain.
4. **Restore:** reconcile before watching starts; restore only if the current file matches recorded optimized content and identity; otherwise offer Save Recovered Copy. Copy the backup to staging rather than consuming it. Serialize through the existing worker. Suppress re-admission of restored paths. Restore does not change savings statistics.
5. **Retention and UI** (`WatchMenuView`, `CompressionSettingsView`): optional recovery IDs in `WatchActivity`; cleanup at startup and before reserving; never purge unresolved records; explain that backups contain original metadata.

Acceptance: every state/file combination, corrupt journal, quota boundaries, injected failures around each durable write, edited/moved/deleted sources, symlink/hard link, low disk, stale bookmarks, volume loss; installed-app forced termination during replace and restore. Not enabled by default until these pass with code and security review.

### Stage 3: Palette PNG reduction

Separate **Allow palette reduction** option, off by default. Evaluate pinned pngquant / libimagequant; CLI pattern like `OxipngService`. Resolve GPL/commercial licensing first. Check exit status (99 = quality rejection maps to Skipped). Validate type, dimensions, decode, metadata policy. Keep watcher/clipboard defaults lossless.

### Stage 4 remainder: Target size

Extend to HEIC; consider a quality floor (proposed 0.70), optional minimum edge (proposed 640 px), at most 18 encodes and a 60 s admission deadline, and an explicit Save Best Copy for unreachable targets. PDF targeting out of scope.

### Stage 6: Equations and diagrams

6A: enable Pandoc math (`tex_math_dollars`) for native DOCX OMML; verify `m:oMath` in `word/document.xml`. 6B: reproduce the WebKit startup failure in a signed installed app before any renderer. 6C (only after 6B): pinned local KaTeX + Mermaid strict mode, bounded inputs (8 KiB per equation, 64 KiB per diagram, 100 objects, 4096 px edges), no network or file access, fallback to source text with warnings. No Node, Chromium or TeX without a separate decision.

## Document roadmap

Completed: local Markdown images, offline embedding, native PDF links, PDF font/page/margin controls; stronger PDF compression with external links and nested bookmarks.

Next:

- DOCX math first, then offline PDF equations and Mermaid (see stage 6).
- DOCX styling via a validated reference document if needed (current style controls are PDF only).
- Internal PDF anchors and annotation destinations only with real page-reference tests.
- Unsigned forms and other annotations need preservation fixtures before stronger compression accepts them. Signed PDFs stay excluded; encryption is a separate workflow.
- Verified Intel helpers if Intel execution is needed; macOS 14 and physical Intel tests.

## Dependencies

- Stage 1 journal blocks replacement changes, which block restore and retention UI.
- Stage 4 HEIC/PNG targeting depends on stage 3 for palette PNG.
- Stage 6C depends on 6B feasibility.
- Any redistribution depends on GPL/AGPL review, Developer ID signing and notarization.
- Phase 10 depends on access to macOS 14 and Intel hardware.

## Risks

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Data loss during in-place replacement | Low | High | Validation, fingerprints, backup + rollback; stage 1 journal before broader replacement |
| Uncoordinated writer resumes after quiet period | Medium | Medium | Stability checks; Keep Both default for Quick Action; test producer apps |
| Signed sandbox behaves differently from tests | Medium | High | Installed signed-app manual checks before relying on features |
| License obligations for bundled helpers | Medium (if shared) | High | Personal use only; review before distribution |
| Coverage drops below 80% again | Medium | Medium | Add tests for UI-adjacent logic; never exclude files to hit target |
| Memory spikes on large images/PDFs | Medium | Medium | Pixel/byte caps, sequential queue, profiling fixtures |

## Definition of done (per slice)

- Failing test first, smallest change, refactor while green; focused and full regression pass; Release build passes.
- Source preserved on failure, outputs validated, no publication after cancellation, collisions safe, permission recovery works, shared queue regressions pass.
- Non-trivial changes: code review with CRITICAL/HIGH fixed; security review before commit.
- Docs updated (this plan, [RELEASE-NOTES](RELEASE-NOTES.md) Unreleased, [SETUP](SETUP.md) test results). Unverified environments reported as unverified.

## Current tasks

### In Progress

- [ ] F11 Markdown math (stage 6A DOCX equations first; 6B/6C need a separate go-ahead) - next
- [ ] Optional: palette PNG for clipboard compression - owner TBD
- [ ] Installed-app check: Choose Files with a folder, then convert a file from it (sandbox access for folder contents) - owner

### Backlog

- [ ] Stage 0 benchmark fixtures - owner TBD
- [ ] Stage 6 (Markdown math and Mermaid) - owner TBD
- [ ] Large-image and large-PDF memory profiling - owner TBD

### Done

- [x] F10 faster Compress to Size quality search - 2026-10-13
- [x] F9 palette PNG in rule Compress actions - 2026-10-13
- [x] Rename brace date tokens {yyyy} {yy} {MM} {dd} {HH} {mm} {ss} - 2026-10-13
- [x] F8 palette PNG levels Off/Safe/Smaller - 2026-10-13
- [x] F7 lossless JPEG optimization (mozjpeg jpegtran, baseline) - 2026-10-12
- [x] F6 JPEG skip re-encode for already-compressed files - 2026-10-12
- [x] F5 palette PNG (pngquant), opt-in - 2026-10-12
- [x] F1 Compress to Size for HEIC and PNG - 2026-10-12
- [x] F4 rule templates - 2026-10-12
- [x] F2 folder drop and folder selection in the main window - 2026-10-12
- [x] F3 lifetime savings counter - 2026-10-12
- [x] Installed-app checks on the 2.0 build (owner-verified) and product direction decided - 2026-10-12
- [x] Cleanups: README limitations, folder automation release note, rename follow-ups (case-only rename, post-rename identity check, source access, unsupported-volume message) - 2026-10-11
- [x] Folder automation rules - 2026-10-11
- [x] Finder Quick Action - 2026-10-10
- [x] Floating window removal, activity history, JPEG target size - 2026-10-09
- [x] Resize + Optimize, document improvements 1-2 - 2026-10-03
- [x] Clipboard optimization, Markdown export, stronger PDF - 2026-10-01
- [x] Watched folders, Oxipng, compact main window - 2026-09-30
- [x] Phases 1-4, PDF tools, manual compression - 2026-09-29
