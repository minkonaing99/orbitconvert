# Future Features

Status: F1-F11 done. F12-F16 planned 2026-10-14. Order: F12 -> F14 -> F15 -> F13 -> F16.

Product direction (decided 2026-10-12, see [PRD scope rule](PRD.md#scope-rule)): OrbitConvert stays **personal use only** and is both a **manual converter** and a **folder automation tool** (watched folders run rules). Features below serve one or both sides.

Rules for every feature: TDD, code review (fix CRITICAL/HIGH), security review before commit, coverage stays at or above 80%, update [PLAN](PLAN.md) and [RELEASE-NOTES](RELEASE-NOTES.md) Unreleased.

## Overview

| # | Feature | Side | Effort | Depends on | Status |
| --- | --- | --- | --- | --- | --- |
| F1 | Compress to Size for HEIC and PNG | Converter | 1-2 days | F5 for PNG beyond lossless | Done 2026-10-12 |
| F2 | Drag a folder onto the main window | Converter | 0.5-1 day | - | Done 2026-10-12 |
| F3 | Lifetime "Saved X MB" counter | Both | 0.5 day | - | Done 2026-10-12 |
| F4 | Rule templates | Automation | 1 day | - | Done 2026-10-12 |
| F5 | Palette PNG option (pngquant) | Both | 1-2 days | License check | Done 2026-10-12 |
| F6 | JPEG: skip re-encoding already-compressed files | Both | 1 day | - | Done 2026-10-12 |
| F7 | JPEG lossless optimization (mozjpeg jpegtran) | Both | 1-2 days | Binary/license check | Done 2026-10-12 |
| F8 | Palette PNG levels: Safe and Smaller | Both | 0.5 day | F5 | Done 2026-10-13 |
| F9 | Palette PNG in rule Compress actions | Automation | 0.5 day | F8 | Done 2026-10-13 |
| F10 | Faster Compress to Size quality search | Converter | 0.5 day | - | Done 2026-10-13 |
| F11 | Markdown math and diagrams (PLAN stage 6) | Converter | 6A 0.5-1 day; 6B-6C several days | 6B before 6C | Done 2026-10-13 |
| F12 | Pause automation when hot or in Low Power Mode | Automation | 0.5 day | - | Done 2026-10-14 |
| F13 | Optional PNG to JPEG for photo-like PNGs | Both | 1-2 days | - | Planned 2026-10-14 |
| F14 | Skip tiny files in automation | Automation | 0.25 day | - | Planned 2026-10-14 |
| F15 | Palette option for clipboard compression | Automation | 0.5 day | F8 | Planned 2026-10-14 |
| F16 | Benchmark against Clop (PLAN stage 0) | Both | 1 day | Clop installed (yes) | Planned 2026-10-14 |

Suggested order: F3 (smallest, visible daily) -> F2 -> F4 -> F5 -> F1 (PNG part benefits from F5).

## F1. Compress to Size for HEIC and PNG

**Done 2026-10-12.** HEIC and PNG keep their format; no JPEG fallback (owner decision). PNG candidates use ImageIO plus Oxipng. Finding: downscaling screenshot-like PNGs usually increases their size, so PNG targets work mainly for photo-like PNGs; F5 should add palette reduction as the first PNG step. Follow-up: faster HEIC quality search.

**Goal:** fit uploads with size limits for HEIC and PNG, not only JPEG.

**Today:** `TargetSizeCompressionService` (Images/) handles JPEG only: quality 100% to 0% in 5-point steps, then downscale to a 1080 px short-edge floor, output `-target-size.jpg`.

**Behavior:**

- HEIC: same search as JPEG (quality steps, then downscale), output stays HEIC (`-target-size.heic`), requires the installed HEIC encoder.
- PNG: PNG is lossless, so quality steps do not apply. Search order: Oxipng lossless, then palette reduction (F5, if enabled), then downscale to the 1080 px floor. Output stays PNG.
- Option (decide during build): allow "convert to JPEG if needed" for PNG/HEIC that cannot reach the target; off by default, because it drops transparency.
- Same guarantees as today: original untouched, only a validated result within the byte limit is saved, unreachable targets report a clear error.

**Files:** `Images/TargetSizeCompressionService.swift`, `Core/FileAction.swift` (availability for HEIC/PNG), `Settings/TargetSizeOptionsView.swift` (wording), tests in `TargetSizeCompressionTests.swift`.

**Tests:** HEIC reaches target and stays HEIC; PNG with alpha keeps alpha; unreachable PNG target reports error; already-small files skipped; encoder unavailable path; mixed JPEG/HEIC/PNG batch.

**Open question:** offer the "convert to JPEG if needed" fallback or not.

## F2. Drag a folder onto the main window

**Done 2026-10-12.** `Core/FileIntakeService.swift` expands dropped or chosen folders to their top-level PNG, JPEG, HEIC/HEIF, TIFF, PDF and Markdown files, sorted by name, using the watched-folder skip rules; capped at 500 with a notice; empty folders report a notice; duplicates across inputs are removed. Choose Files accepts folders. Decision: top level only (subfolders not included). Folder access is kept for the session so the files inside stay readable; confirm Choose Files with a folder in the installed signed app.

**Goal:** drop a folder and get all its supported files, instead of selecting files one by one.

**Today:** `FileIntakeService` (Core/) rejects directories; `ContentView.importDrop` forwards only file URLs.

**Behavior:**

- A dropped or chosen folder expands to its supported files (images, PDFs, Markdown), sorted by name.
- Top level only by default; an option or modifier for subfolders (decide during build).
- Skip hidden files, packages, symlinks and temporary download names, same rules as watched folders (`WatchFilePolicy`).
- Limit: at most 500 files per drop; above that, show "Folder has N files; first 500 added".
- Unsupported files are silently skipped (count shown), not listed as errors.

**Files:** `Core/FileIntakeService.swift` (folder expansion), `App/ContentView.swift` (drop and picker allow folders), tests in `FileIntakeServiceTests.swift`.

**Tests:** folder with mixed files, nested folder (flat vs recursive), hidden/symlink/package skipped, limit reached, empty folder message, sandbox access kept for expanded files.

## F3. Lifetime "Saved X MB" counter

**Done 2026-10-12.** `Watch/LifetimeSavings.swift` stores the total in UserDefaults (seeded once from history). Automatic jobs add through `WatchedFoldersController.record`; the main window and Finder Quick Action add through `LifetimeSavings.record`, which notifies the controller. The menu bar popup and Watched Folders settings show "Total saved: X across N files"; settings has a two-step Reset. Decisions: manual results count; seeding from history on first launch.

**Goal:** see total space saved, kept across launches.

**Today:** session statistics reset on launch; history keeps only the last 200 results, so summing history undercounts.

**Behavior:**

- Store a running total in UserDefaults (`lifetimeSavedBytes`, `lifetimeOptimizedCount`), added when a watched-folder or clipboard job finishes as optimized. Manual actions can count too (decide during build).
- Show "Saved 1.2 GB total" in the menu bar popup next to session statistics, and in Watched Folders settings.
- Reset button in Settings with an inline confirmation.
- On first launch after the update, seed the total from existing history so it does not start at zero.

**Files:** `Watch/WatchedFoldersController.swift` (accumulate), `Watch/MenuStatus.swift`, `Watch/WatchMenuView.swift`, `Settings/WatchedFoldersSettingsView.swift`; `docs/SCHEMA.md` (new keys).

**Tests:** total survives a new controller with the same defaults; skipped/failed add nothing; seeding from history happens once; reset clears it; overflow-safe arithmetic.

**Open question:** include manual (main-window and Quick Action) savings or only automatic ones.

## F4. Rule templates

**Done 2026-10-12.** `Automation/AutomationRuleTemplates.swift`; "Add Rule" is a menu (Blank Rule, templates, Sort Downloads submenu) that opens the normal editor, so nothing runs until Save. Shipped templates (changed from the proposal after review):

| Template | Conditions | Actions |
| --- | --- | --- |
| Screenshots: rename and compress | Name starts with "Screenshot" (English macOS; edit for other languages), file type PNG, name does not contain "-optimized" | Rename `'Screenshot'_{yyyy}-{MM}-{dd}_{HH}-{mm}-{ss}.{ext}`, Compress (Keep Both, PNG colors Safe since 2026-10-14) |
| Large JPEG photos: make smaller copy | File type JPEG, width greater than 2560 | Resize to fit 2560 x 2560 (separate `-resized` copy) |
| PDFs: add date and compress | Category PDF | Rename `{yyyy}-{MM}-{dd}_{name}.{ext}`, Compress (Keep Both) |
| Sort Downloads: Images / PDFs / Archives / Documents and text files | Category | Move (choose destination before Save) |

New rules without a Move action are inserted above existing Move rules, so sort rules stay last in first-match-wins order. Known behavior: a PDF that already starts with a date gets a second date prefix.

**Goal:** create common rules in one click instead of building them by hand.

**Behavior:** "Add Rule" offers a template menu; choosing one opens the normal rule editor pre-filled, so nothing runs until Save. Initial templates:

| Template | Conditions | Actions |
| --- | --- | --- |
| Screenshots: rename + compress | Filename starts with "Screenshot" and category is image | Rename `'Screenshot'_{yyyy}-{MM}-{dd}_{HH}-{mm}-{ss}.{ext}`, Compress (Keep Both) |
| Downloads: sort by type | Category is image / PDF / archive / document (one rule each) | Move to a chosen subfolder (destination picked in the editor) |
| Shrink photos | Extension is jpg/heic, size greater than 5 MB | Resize 2560 px, Compress Keep Both |
| PDF tidy | Category is PDF | Rename `{yyyy}-{MM}-{dd}_{name}.{ext}`, Compress Keep Both |

- Templates are plain `AutomationRule` values in code; no new storage.
- Move templates require choosing a destination before Save (existing validation already enforces this).

**Files:** new `Automation/AutomationRuleTemplates.swift`, `Automation/AutomationRulesView.swift` (menu), tests.

**Tests:** every template passes `AutomationRule.validate()` once destinations are set; templates never auto-save; Screenshot rename preview matches example.

**Open question:** Screenshots template default - Keep Both (safe) or Replace Original (saves space). Recommendation: Keep Both.

## F5. Palette PNG option (pngquant)

**Done 2026-10-12.** Official pngquant 3.0.3 universal binary, local-only like Pandoc (owner decision), quality 80-100 (owner decision). "Reduce PNG colors" in General settings, off by default; applies to manual Compress, Compress to Size (tried first for PNG) and the Finder Quick Action. Watched folders and clipboard stay lossless for now. Palette output is sRGB and drops metadata, which the setting text states.

**Goal:** much smaller screenshots and graphics (often 60-80%) by reducing colors.

**Trade-off:** lossy. Colors and fine gradients can change; must be opt-in.

**License:** pngquant and libimagequant are GPL v3 (commercial license also offered). For this personal, undistributed build that is acceptable, same as bundled Pandoc (GPL) and Ghostscript (AGPL). Keep the license and notices in `ThirdParty/pngquant/`. Revisit only if the app is ever shared.

**Behavior:**

- New "Allow palette reduction" option, off by default, in General settings, Compress options, and as a Compress action option in rules.
- Pipeline for PNG: pngquant (quality range 80-100), then Oxipng; keep only a smaller validated result.
- pngquant exit code 99 (quality too low) = skipped, original kept.
- Metadata: if pngquant drops chunks that "keep metadata" requires, keep that combination unavailable rather than silently stripping.
- Bundling: follow the Oxipng pattern (fixed path, argument array, no shell, inherited sandbox, timeout, cancellation) and verified release hash; Apple Silicon build at minimum.

**Files:** new `Images/PngquantService.swift`, `Images/ImageOptimizationService.swift`, `Core/CompressionModels.swift`, settings and rule editor options, `scripts/embed-oxipng.sh` (embed step), `ThirdParty/pngquant/`, setup instructions in `docs/SETUP.md`, provenance in `docs/TECH.md`.

**Tests:** screenshot and gradient fixtures shrink; transparency visually kept; exit 99 skipped; corrupt output rejected; missing helper reported; timeout and cancellation; option off = current lossless behavior unchanged.

## F6. JPEG: skip re-encoding already-compressed files

**Done 2026-10-12.** `Images/JPEGQualityEstimator.swift`. Finding: ImageIO quality is not IJG quality (0.85 ~ IJG 95, 0.70 ~ IJG 91), so the comparison uses the IJG-equivalent of the ImageIO quality, measured at runtime, not the preset number. In practice Balanced now keeps most JPEGs below about IJG 95 untouched (re-encoding them measured 130-192% of the source). With Remove metadata on, the skip does not apply (privacy over size); lossless metadata removal comes with F7.

**Goal:** stop making JPEGs bigger and worse. Today Compress re-encodes every JPEG at 0.85 (Balanced) or 0.70 (Maximum), even when the file is already at a lower quality. Clop's `jpegoptim --max 85` only re-encodes when the estimated quality is above the cap.

**Behavior:**

- Estimate the source JPEG quality from its quantization tables (standard IJG scaling; no decode needed).
- If the estimate is at or below the preset's quality, do not re-encode; only lossless optimization (F7, once available) can run. Report "Already compressed at about N% quality".
- Otherwise re-encode as today; the existing "publish only if smaller" check stays.
- Applies to Compress, batch, watched-folder and Quick Action JPEG paths (they share `ImageOptimizationService`). Compress to Size is unchanged (it searches quality to hit a byte limit).

**Files:** new `Images/JPEGQualityEstimator.swift`, `Images/ImageOptimizationService.swift`, tests.

**Tests:** estimates within a few points for JPEGs written at 50/70/85/95; already-low JPEG is not re-encoded and reports why; high-quality JPEG still compresses; corrupt/missing tables fall back to today's behavior.

## F7. JPEG lossless optimization (mozjpeg jpegtran)

**Done 2026-10-12.** `Images/JpegtranService.swift`; mozjpeg 4.1.1 built from source (static universal, committed gz, see SETUP). Decisions: every JPEG (skipped ones plus re-encodes, smallest wins); baseline instead of progressive, because macOS renders 4:2:0 progressive JPEGs slightly differently (owner choice after measurement); Remove metadata strips losslessly with `-copy icc` for upright photos, which re-enables the F6 skip there.

**Goal:** 5-15% smaller JPEGs with zero quality change, for every JPEG (including ones F6 skips).

**Behavior:** run `jpegtran -copy all -optimize -progressive` (mozjpeg build) on the source or the re-encoded candidate; keep it only if smaller and the decoded pixels are identical. Metadata is kept unless Remove metadata is on (`-copy none`).

**Open before building:** source of a self-contained universal `jpegtran` binary (mozjpeg is BSD/IJG-licensed; check official releases vs a local build), same local-cache pattern and hash recording as pngquant.

**Files:** new `Images/JpegtranService.swift`, `scripts/embed-oxipng.sh`, `ThirdParty/mozjpeg/`, `Images/ImageOptimizationService.swift`, docs (SETUP, TECH provenance).

**Tests:** smaller with identical pixels; metadata kept/removed per setting; progressive output decodes; helper missing or failing falls back.

## F8. Palette PNG levels: Safe and Smaller

**Done 2026-10-13.** `PaletteLevel` (Images/PngquantService.swift), stored as `paletteLevel`; the old Bool is migrated at launch (on = Safe). Settings shows a picker.

**Goal:** let screenshots shrink further when slight color changes are acceptable.

**Behavior:** replace the on/off "Reduce PNG colors" with Off / Safe (quality 80-100, today) / Smaller (quality 60-100). Existing "on" maps to Safe. Same fallbacks and metadata note as F5.

**Files:** `Images/PngquantService.swift` (quality parameter), settings view, `QuickCompressionSettings`, `FileActionSettings`, `docs/SCHEMA.md`.

**Tests:** Smaller produces a palette file where Safe skips (fixture between the two floors); migration from the old Bool; Off unchanged.

## F9. Palette PNG in rule Compress actions

**Done 2026-10-13.** Optional `palette` field on `AutomationAction`, "PNG colors" picker in the Compress action, passed to `ImageOptimizationService`.

**Goal:** the screenshot-folder rule gets palette savings (often 50-80%) instead of lossless only (about 40%).

**Today:** rule Compress calls `ImageOptimizationService.optimize(file, in:, preset:)` without `palette`, so rules are always lossless for PNG. The JPEG improvements (F6, F7) already apply to rules.

**Behavior:**

- Compress action gets a "PNG colors" picker: Off / Safe / Smaller, default Off. Per rule, independent of the app-wide setting.
- Only PNGs are affected; JPEG/HEIC/PDF ignore it.
- Same fallbacks as F5: pngquant skip falls back to lossless; content-credential PNGs are still refused (the action reports the error); palette output is sRGB without metadata, and the caption says so.
- Replace Original keeps its warning; Keep Both remains the template default.
- The Screenshots template stays Off (owner turns it on per rule).

**Data compatibility (critical):** rules are stored as JSON inside `watchedFolders` and decoded with synthesized `Codable` and `try?`. A new non-optional field would make old data fail to decode and every watched folder would disappear. So the field is `palette: PaletteLevel?` (missing = Off), and `PaletteLevel` becomes `Codable`.

**Files:** `Automation/AutomationRule.swift` (field), `Automation/AutomationMediaService.swift` (pass level), `Automation/AutomationActionEditor.swift` (picker, caption), `Images/PngquantService.swift` (`Codable`), `docs/SCHEMA.md`.

**Tests:** old rule JSON without the key decodes (palette Off) and a stored `smaller` round-trips; rule Compress with Safe on a screenshot-like PNG publishes a palette PNG (PLTE chunk); Off stays lossless; noisy PNG below the floor falls back to lossless; Replace Original with palette replaces in place.

## F10. Faster Compress to Size quality search

**Done 2026-10-13.** `TargetSizeCompressionService.highestFittingQuality` (binary search, at most 6 encodes per size level). Encode count is tested through the search function directly; the real-JPEG test checks it picks the same quality as a full scan.

**Goal:** Compress to Size on large HEIC (and JPEG) files finishes in seconds instead of trying up to 21 quality steps per size level.

**Today:** `TargetSizeCompressionService.findCandidate` encodes quality 100, 95, ... 0 until one fits: up to 21 full encodes per size level, then again for each downscale level. HEIC encodes are slow.

**Behavior:**

- Binary search over the same 5-point grid (100 to 0): about 5 encodes per size level. Pick the highest quality that fits.
- Output size is not strictly monotonic in quality, so the chosen candidate is always the last measured one that fit (never assumed). Rarely, a slightly higher fitting quality may be missed; acceptable and documented.
- PNG unchanged (one candidate per level). Messages, guarantees and output naming unchanged.

**Files:** `Images/TargetSizeCompressionService.swift`, tests in `TargetSizeCompressionTests.swift`.

**Tests:** same results as today for the existing JPEG/HEIC fixtures (quality chosen is the highest fitting step); encode count per size level at most 6 (counted through an injected encode closure or by measuring calls in a test helper); unreachable target still errors; cancellation still stops.

## F11. Markdown math and diagrams

**6B/6C done 2026-10-13.** WebKit needed `com.apple.security.network.client`; renderer locked down (see TECH ADR). PDF now draws formulas and Mermaid diagrams as vector graphics.

**6A done 2026-10-13.** Finding: already worked; Pandoc 3.12 `gfm` parses dollar math, DOCX gets native Word equations. Added a regression test. PDF renders simple inline math as styled text but complex TeX (fractions, integrals) as raw TeX; fixing that is 6B/6C.

Already planned as [PLAN stage 6](PLAN.md#stage-6-equations-and-diagrams). Order: 6A first (Pandoc `tex_math_dollars` so DOCX gets native Word equations; verify `m:oMath` in `word/document.xml`), small and self-contained. 6B (reproduce the WebKit startup failure in a signed installed app) decides whether 6C (offline KaTeX and Mermaid for PDF) is feasible; 6C needs a separate go-ahead.

## F12. Pause automation when the Mac is hot or in Low Power Mode

**Done 2026-10-14.** `Watch/LoadGate.swift`. Owner wanted "hot" to mean CPU/GPU above 70 C or battery above 33 C; degree readings are not public API (CPU/GPU need private sensor APIs plus a sandbox exception; this M4 MacBook Air exposes no battery temperature in IORegistry), so the owner chose macOS's thermal state with the earlier threshold: pause from `.fair` (first warm level), not `.serious`. Menu shows "Waiting: Mac is warm/hot" or "Low Power Mode".

**Goal:** automation never adds heat when the Mac is already hot or saving power.

**Behavior:**

- Before starting each watched-folder or rule job, check `ProcessInfo.thermalState` (pause at `.serious` or `.critical`) and `isLowPowerModeEnabled`.
- While paused, queued files wait (nothing is dropped); resume automatically on `thermalStateDidChangeNotification` / `NSProcessInfoPowerStateDidChange`, with a slow fallback check (60 s).
- Menu bar shows "Waiting: Mac is hot" or "Waiting: Low Power Mode". Setting "Pause automation when the Mac is hot or in Low Power Mode", default on.
- Manual Compress, Quick Action, exports and clipboard compression are not paused (the user is waiting for them).

**Files:** `Watch/WatchedFoldersController.swift` (gate in the drain loop, injected condition for tests), small `Watch/SystemLoad.swift`, `Watch/WatchMenuView.swift`, settings view, SCHEMA (setting key).

**Tests:** hot or Low Power defers jobs and keeps them queued; cooling resumes; setting off ignores the state; manual paths unaffected.

## F13. Optional PNG to JPEG for photo-like PNGs

**Goal:** photo-like PNGs (camera exports, photo screenshots) shrink 5-10x, as Clop does.

**Behavior:**

- Option "Convert photo-like PNGs to JPEG", off by default; per rule Compress action and in manual Compress settings.
- Only opaque PNGs (no alpha channel, or alpha fully 255); encode JPEG at the preset quality and keep it only if it saves at least 100 KB and at least 30% versus the best PNG result (Clop uses a 100 KB rule).
- Output gets `.jpg`. Keep Both writes `name-optimized.jpg`; Replace Original and Move to Trash publish the `.jpg` and remove/trash the `.png` with the same safety checks (fingerprint, validated output). Following rule actions continue with the `.jpg`.
- Metadata policy and orientation as for normal JPEG output; transparency is never lost because transparent PNGs are excluded.

**Open question (decide while building):** whether Replace Original should be allowed to change the extension or only Keep Both (default proposal: allowed, because Move to Trash is the safe alternative).

**Files:** `Images/ImageOptimizationService.swift` (photo check + JPEG candidate), `Automation/AutomationRule.swift` (optional field, decode-safe), `Automation/AutomationMediaService.swift`, editor, settings, `Core/FileActionService.swift`.

**Tests:** opaque gradient PNG converts and shrinks; transparent PNG never converts; small saving keeps PNG; screenshot-like PNG stays PNG; Replace Original swaps extension safely; old rules decode with the option off.

## F14. Skip tiny files in automation

**Goal:** no helper launches for files that cannot save meaningful bytes.

**Behavior:** watched-folder and rule Compress skip images under 20 KB with "Too small to compress" (not an error; following rule actions still run on the original). Manual Compress unchanged.

**Files:** `Watch/AutoOptimizationService.swift`, `Automation/AutomationMediaService.swift`, tests.

## F15. Palette option for clipboard compression

**Goal:** copied screenshots get palette savings like rules.

**Behavior:** clipboard settings gain "PNG colors: Off / Safe / Smaller" (default Off, stored separately from the manual setting); `ClipboardOptimizationService` passes it to `ImageOptimizationService`. Same fallbacks and metadata note as F5.

**Files:** `Clipboard/ClipboardOptimizationService.swift`, clipboard settings view, SCHEMA.

## F16. Benchmark against Clop (PLAN stage 0)

**Goal:** measured, honest comparison instead of claims.

**Plan:** a fixture set (text screenshots, photo screenshots, transparent graphics, photos as JPEG/HEIC/PNG, already-optimized files) with hashes; run OrbitConvert presets (Balanced, Maximum, palette Safe/Smaller) through a test harness and Clop 2.x (installed at `/Applications/Clop.app`, run by the owner or via its CLI if available) on copies; record bytes, time and visual result. Results go to a new benchmark section in SETUP; no universal savings claims.

## Open: "watch folder changes"

Today automation runs rules only on **new, stable files arriving** in a watched folder (plus Run Now on existing files). Editing an existing file does not re-run rules; this is deliberate, to avoid loops and repeated recompression.

Possible additions, to decide before building:

| Option | What it does | Risk |
| --- | --- | --- |
| A. Re-run on modified files | When a known file changes, run matching rules again | Loops (OrbitConvert's own output counts as a change); needs strict self-change suppression |
| B. Scheduled Run Now | Re-check a folder every N hours and run rules on files that match | Repeated work; needs "already processed" tracking |
| C. Folder-level triggers | Conditions on folder state (e.g. folder over 2 GB, file older than 30 days) | New condition types; deletion-like actions stay excluded |
| D. Keep as is | New arrivals only | None |

**Decision 2026-10-12: D, keep as is.** New-arrival triggering already covers the main use (screenshots saved to a dedicated watched folder run a rule automatically; the owner has this set up). Revisit A-C only if a concrete need appears.
