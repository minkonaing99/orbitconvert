# Release Notes

Newest first. Follows SemVer. Dates ISO 8601.

No version has been released yet (the app is set to version 3.1, build 1), so all work is collected under Unreleased. When a version ships, move the entries into a block using this format and keep section order fixed, omitting empty sections:

```
## [X.Y.Z] - YYYY-MM-DD
**Summary:** 1-3 sentences. What this release is about + who benefits.

### Highlights
### New Features
### Improvements
### Bug Fixes
### Security

### Deprecated
### Removed
### Breaking Changes
### Upgrade / Migration Steps
### Known Issues
### Links
```

Entry format: `- **Headline** - what changed + why it matters to the user. (#issue/PR)`. Plain language, benefit first, no commit hashes as prose. Test counts and coverage live in [SETUP](SETUP.md#results-history).

## [Unreleased]

### New Features

- **Formulas and diagrams in PDF export** (2026-10-13) - Markdown to PDF now draws math (`$...$`, `$$...$$`) as real typeset formulas and turns ```mermaid code blocks into diagrams, all offline. Anything that cannot be drawn keeps its text.
- **Equations in Word export** (2026-10-13) - Confirmed and now tested: `$...$` and `$$...$$` math in Markdown becomes real, editable Word equations in DOCX export. Dollar amounts like `$5` stay as text. PDF export shows simple formulas but not yet fractions or integrals.
- **Faster Compress to Size** (2026-10-13) - JPEG and HEIC targets are found with at most 6 trial encodes per size instead of up to 21, so large HEIC photos finish much sooner. Results are the same in normal cases.
- **Smaller screenshots from folder rules** (2026-10-13) - A rule's Compress action now has a "PNG colors" option (Off, Safe, Smaller), so watched-folder rules can shrink screenshots as much as manual Compress. Existing rules stay Off.
- **Date tokens in rename rules** (2026-10-13) - Rename patterns now have separate `{yyyy}`, `{yy}`, `{MM}`, `{dd}`, `{HH}`, `{mm}` and `{ss}` tokens (with buttons in the rule editor), so you can arrange date and time parts any way you like, for example `{dd}-{MM}-{yyyy}`. Existing patterns keep working.
- **PNG color levels** (2026-10-13) - "Reduce PNG colors" is now Off, Safe or Smaller. Safe works as before; Smaller also shrinks images where a slight color change is acceptable. If you had it on, it is set to Safe.
- **Lossless JPEG shrinking** (2026-10-12) - Compress now also shrinks JPEGs without any quality change (often 5-20%), including ones that are already compressed. Remove metadata strips location and camera details without re-encoding upright photos. Pixels are checked to be identical before a file is saved.
- **Smarter JPEG compression** (2026-10-12) - Compress no longer re-encodes JPEGs that are already at or below the chosen quality, which used to make them bigger and slightly worse. They are kept as they are and reported as "Already compressed at about N% quality". Applies everywhere JPEGs are compressed except Compress to Size, and not when Remove metadata is on.
- **Smaller PNG screenshots** (2026-10-12) - Turn on "Reduce PNG colors" in General settings to shrink screenshots and graphics much further (often 50-80%) when quality stays high. Works with Compress, Compress to Size and the Finder Quick Action. Colors are converted to sRGB and hidden file details are removed; off by default.
- **Compress to Size for HEIC and PNG** (2026-10-12) - Compress to Size now works on HEIC and PNG as well as JPEG, and keeps each file's format. PNGs are optimized losslessly first; screenshot PNGs often cannot reach small targets yet, which palette reduction will address.
- **Rule templates** (2026-10-12) - Add Rule now offers ready-made rules: rename and compress screenshots, make smaller copies of large JPEG photos, add dates to PDFs and compress them, and sort downloads into folders by type. Each opens in the editor for review before saving, and new rules are placed above sorting rules so they are not skipped.
- **Add whole folders** (2026-10-12) - Drop a folder onto the main window, or pick one with Choose Files, to add all its supported images, PDFs and Markdown files at once (top level only, up to 500). Hidden and partially downloaded files are skipped.
- **Lifetime savings total** (2026-10-12) - The menu bar and Watched Folders settings show how much space OrbitConvert has saved across launches, including manual and Finder compressions. It starts from your saved history and can be reset in Settings.
- **Folder automation rules** (2026-10-11) - Each watched folder can run ordered rules on new files: match on name, extension, category, size, dates, image size, Finder tags or document text, then Rename (date/name/number templates), Move, Copy, Compress, Convert, Resize or Remove metadata. Test Rule and Run Now preview changes before anything happens, failed steps can be retried, and OrbitConvert's own outputs never trigger other folders. Existing compression settings migrate to an equivalent rule.
- **Compress with OrbitConvert in Finder** (2026-10-10) - Right-click up to 100 JPEG, PNG or HEIC/HEIF images and compress them without opening the app first. A compact window offers Keep Both, Replace Original or Choose Output Folder, remembers your choice, shows per-file savings and supports Stop and Show in Finder. It reuses the same validated compression, collision-safe saving and guarded replacement; the Finder bridge keeps every original attachment and passes access bookmarks instead of raw paths.
- **Compress to Size for JPEGs** (2026-10-09) - Set a maximum size per file (decimal KB/MB, default 2 MB) so uploads with size limits succeed. Quality drops first, then dimensions shrink no lower than a 1080 px short edge. Results are separate collision-safe files; unreachable limits are reported and already-small files skipped.
- **View All Activity** (2026-10-09) - Open the full saved watched-folder and clipboard history from Settings or the menu bar, with date/time, original and final sizes, amount saved and percentage.
- **Resize + Optimize** (2026-10-03) - Shrink JPEG/PNG/HEIC images to 25%, 50%, 75%, a 1080/1920 px longest edge or custom bounds, with an orientation-aware preview and Balanced/Maximum compression. Saves `-resized` copies only when smaller; never enlarges.
- **Local images, links and page styles in Markdown exports** (2026-10-03) - Allow a notes folder to embed its PNG/JPEG/TIFF/HEIC images offline into DOCX and PDF. External links stay clickable in PDFs. Choose A4 or US Letter, serif or sans, body size and margins for PDF.
- **Stronger PDF compression keeps links and bookmarks** (2026-10-03) - Web links and nested bookmarks survive Ghostscript compression and are verified after saving.
- **Markdown to PDF and DOCX** (2026-10-01) - Export `.md`/`.markdown` notes to paginated PDF or editable DOCX, fully offline. Remote images are never fetched.
- **Stronger PDF compression** (2026-10-01) - Optional manual Ghostscript mode targets 150 DPI (Balanced) or 100 DPI (Maximum) for embedded images. Protected or interactive PDFs are refused and originals always kept.
- **Clipboard image optimization** (2026-10-01) - Copied PNG, JPEG, TIFF and HEIC images are optimized locally in the background and written back only if the clipboard has not changed. Optional result cards (Copy, Save, Reveal) and an in-memory collection (Copy All, Save All, Clear); ignored apps and an independent pause.
- **Live menu bar status** (2026-10-01) - See active and queued jobs, session statistics and recent results from the menu bar.
- **Lossless PNG optimization with Oxipng** (2026-09-30) - PNGs in manual, batch and watched-folder jobs now shrink losslessly (about 42% on a sample screenshot) with metadata kept. Content credentials are protected unless you choose Remove metadata.
- **Watched folders** (2026-09-30) - Pick folders to watch; new JPEG, PNG, HEIC and PDF files are optimized automatically after they finish downloading, with Keep Both or validated Replace Original, global pause, Launch at Login and local history.
- **PDF tools and manual compression** (2026-09-29) - Image-to-PDF, PDF to JPEG/PNG, page extraction and merge; JPEG/PNG and PDF compression with savings shown; Settings for compression and export.
- **Image conversion** (2026-09-29) - Convert among PNG, JPEG, HEIC and TIFF with JPEG quality and optional metadata removal; transparent images flatten onto white for JPEG; results never overwrite existing files.
- **File intake and inspection** (2026-09-29) - Choose Files or drop multiple files; types are detected from content, with thumbnails, size, dimensions and available outputs. Invalid files show individual errors while valid ones stay selected.

### Improvements

- **Cooler background work** (2026-10-14) - Watched folders, rules and clipboard compression now run on the Mac's efficiency cores with one helper thread, so automation no longer heats the Mac or competes with what you are doing. They take longer per file; manual Compress stays fast.
- **Simpler General settings** (2026-10-10) - Everyday choices grouped with short explanations; saved preferences kept.
- **Compact watched-folder layout** (2026-10-09) - Top-aligned folder section with scrollable recent activity.
- **Compact main window** (2026-09-30) - Selectable rows and one shared action area (Compress, conversion picker, Tools, collapsed options) replace repeated per-file cards. Batches process only checked files and keep per-file failures.
- **Background work stays responsive** (2026-09-29) - Intake and inspection moved to background work.

### Bug Fixes

- **Menu bar popup sizing** (2026-10-01) - Fixed collapsed popup sizing.
- **Repeated target-size measurements** (2026-10-09) - Candidate sizes use fresh file attributes instead of cached values.

### Security

- The app now has the outbound-network sandbox permission (2026-10-13), required for the WebKit formula/diagram renderer to start. The renderer blocks every remote load (content rules, CSP, no navigation), and no feature sends data anywhere.
- **Moved files go to Trash** (2026-10-11) - When an automation rule moves a file, the original is sent to Trash after the verified copy is saved, so a mistaken move can be recovered. If Trash is unavailable, the original is kept and the copy is reported.
- **Rename no longer copies files** (2026-10-11) - Rule renames now rename the file in place: faster, no duplicate data, and nothing is deleted.
- **Clearer Replace Original warning** (2026-10-11) - The rule editor shows a visible warning that in-place replacement cannot be undone.

### Removed

- **Floating Drop Target and Floating Actions** (2026-10-09) - Removed with their Windows toolbar menu. Drop files into the main window instead; clipboard result cards, watched folders and history remain. Earlier floating-panel work (2026-09-29) is superseded.

### Known Issues

- Finder Quick Action may need enabling in System Settings > Extensions; live Finder hand-off and sandbox grants are not yet verified on an installed app.
- No Undo for Replace Original. A crash during replacement can leave a hidden `.orbitconvert-backup-*` recovery file.
- A file writer that pauses longer than the stability quiet period can resume after a watched-folder job.
- Pasting before clipboard optimization finishes uses the original image; some apps re-encode pasted pixels.
- NSPasteboard has no atomic compare-and-swap; a small cross-process race remains.
- PDFKit compression cannot set exact DPI or JPEG quality. Internal PDF links, forms and other annotations are excluded from stronger compression.
- Markdown: no math, Mermaid, raw HTML or Obsidian links; PDF style controls do not affect DOCX.
- Document helpers are arm64 only. macOS 14 runtime, Intel runtime, signed sandbox behavior, VoiceOver and keyboard use are unverified.
- Animated/multi-image inputs, BMP, GIF, WebP and AVIF are unsupported.

### Links

- [PRD](PRD.md), [TECH](TECH.md), [SETUP](SETUP.md)
