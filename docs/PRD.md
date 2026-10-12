# Product Requirements and App Flow

Status: Main-window conversion and tools, watched folders with rule automation, clipboard optimization, the menu bar popup and the Finder Quick Action are implemented. Signed sandbox, accessibility, macOS 14 and Intel runtime checks remain open. Implementation details live in [TECH](TECH.md); delivery status lives in [PLAN](PLAN.md).

## Product requirements

### Problem

Converting, compressing and organizing images, PDFs and notes on a Mac usually means juggling several apps or uploading files to web services. OrbitConvert does this locally, in one native utility, without ever overwriting an original by accident.

### Goals and success metrics

- Convert a dropped image to another format and reveal the result in under 30 seconds of user time.
- Never overwrite an original or an existing output unless the user explicitly chose Replace Original, and then only after the candidate validates and is smaller.
- Automatic work (watched folders, clipboard) runs in the background with visible status in the menu bar and a persistent 200-entry activity log.
- All processing stays on the Mac: no uploads, no analytics, no runtime downloads.
- Report actual byte savings; never promise that a file will shrink.

### Target users

- **Personal power user (primary):** the developer's own daily use on an Apple Silicon Mac. They compress screenshots, downloads and PDFs and organize folders automatically.
- **Mac user handling media:** someone who needs a quick format conversion or smaller file without learning command-line tools.

Public distribution is not prepared. Bundled GPL/AGPL helpers need a separate license review before sharing a built app.

### Features

**Core (implemented)**

- File intake by Choose Files, Add Files and drag/drop into the main window; content-based type detection.
- Image conversion among PNG, JPEG, HEIC/HEIF and TIFF where an Apple encoder exists; JPEG quality and metadata removal.
- PDF: image-to-PDF (fit, image size, A4, US Letter), PDF to JPEG/PNG at 72-300 DPI, page/range extraction, merge in selection order.
- Compress JPEG, PNG, HEIC and PDF (Lossless, Balanced, Maximum); Oxipng for PNG; optional Stronger PDF compression via Ghostscript.
- Compress to Size for JPEGs (default 2 MB per file, 1080 px short-edge floor).
- Resize + Optimize (25/50/75%, longest edge 1080/1920, custom bounds).
- Markdown (`.md`, `.markdown`) export to PDF and DOCX, with optional local images.
- Watched folders with ordered automation rules (conditions plus Rename, Move, Copy, Compress, Convert, Resize, Remove metadata).
- Clipboard image optimization with result cards and an optional in-memory collection.
- Menu bar popup with live jobs, session savings and recent activity; full activity window.
- Finder Quick Action **Compress with OrbitConvert** for up to 100 JPEG/PNG/HEIC images.

**Extended (v2 candidates, see [PLAN](PLAN.md))**

- Optional palette PNG reduction (pngquant), disabled by default.
- Target size for HEIC and PNG.
- Editable DOCX equations, then offline PDF math and Mermaid.
- Benchmark fixtures and an honest comparison with Clop.
- Verified Intel document helpers; macOS 14 runtime validation.

**Out of scope**

- Cloud processing, uploads, analytics, automatic downloads, private APIs, Finder injection.
- Deletion actions and custom scripts in automation rules.
- Video optimization, ZIP/archive creation, OCR of scanned PDFs, Word-document text extraction.
- Animated or multi-image inputs; BMP, GIF, WebP and AVIF (deferred).
- Radial or floating action panels (floating windows were removed on 2026-10-09).
- Undo / Restore Original for in-place replacements (dropped 2026-10-11; use Keep Both when the original matters).
- Redo stacks, persistent retry queues, plugin frameworks, a database.

### User stories

- As a power user, I want to drop a HEIC photo and convert it to JPEG, so that I can share it anywhere.
- As a power user, I want new screenshots in a watched folder compressed and renamed automatically, so that my folders stay small and organized.
- As a power user, I want copied screenshots optimized on the clipboard, so that pasted images are smaller without extra steps.
- As a Mac user, I want to right-click images in Finder and compress them, so that I do not have to open the app first.
- As a power user, I want to export a Markdown note to PDF or DOCX offline, so that I can share it without a word processor.
- As a power user, I want to preview what a rule would do before running it on existing files, so that I never change files by surprise.
- As a power user, I want to compress JPEGs to a byte limit, so that uploads with size caps succeed.

### Constraints

- Platform: macOS 14 or later, SwiftUI plus AppKit. Verified on Apple Silicon macOS 27.0; macOS 14 and Intel runtime unverified.
- App Sandbox with user-selected read/write and app-scoped bookmarks only. No broad filesystem, network, Accessibility, Input Monitoring or Screen Recording permission.
- Bundled Pandoc and Ghostscript are arm64 only and are not committed to Git (fresh clones run [setup](SETUP.md)).
- Personal use. GPL (Pandoc) and AGPL (Ghostscript) obligations apply before any redistribution.
- Coverage target 80%; current whole-app coverage is 80.67%.

### Scope rule

Decided 2026-10-12: OrbitConvert is **personal use only** (no distribution, no notarization or license work for sharing) and is both a **manual converter** and a **folder automation tool**. New features must serve one of these; planned work is in [FUTURE-FEATURES](FUTURE-FEATURES.md). Excluded unless this rule changes: public distribution, Intel/macOS 14 support work, deletion or script actions in rules.

### Open questions and assumptions

- Recovery retention for Undo: proposed seven days, 100 entries, 1 GB (see [PLAN](PLAN.md)).
- Whether Intel document helpers are needed.
- Whether automation should react to modified files or schedules (see [FUTURE-FEATURES](FUTURE-FEATURES.md#open-watch-folder-changes)).
- Assumption: the app stays running to watch folders and the clipboard.

## App flow

### Entry points

| Entry | Opens |
| --- | --- |
| Dock / app launch | Main window (single instance; Open does not duplicate it) |
| Menu bar icon | MenuBarExtra popup (350 pt wide) with jobs, savings, recent activity, Open, Settings, Quit |
| Finder Quick Action | A compact Quick Compression window per invocation |
| Watched folder arrival | Background job; status in the menu bar |
| Clipboard copy | Background job; optional result card |
| Launch at Login (optional) | App starts in the background so watching continues |

### Core flows

**1. Manual conversion and tools**

1. Drop files or a folder into the main window, or use Add Files / Choose Files (folders add their top-level supported files, up to 500).
2. The app validates each file and shows a compact selectable row with a thumbnail, type, size and dimensions. Invalid files show individual errors; valid ones stay selected.
3. Check the files to act on. The shared action area shows only actions every checked file supports: a primary Compress button, a format picker, a Tools menu and collapsed Options.
4. Run an action. Files process one at a time. Batches ask for a shared output folder when none is chosen.
5. Results show output size and savings, with Reveal in Finder. Originals are kept. Existing names get numeric suffixes (`photo-1.jpg`).

**2. Compress to Size (JPEG)**

1. Tools > Compress to Size; enter a limit in decimal KB/MB (1 MB = 1,000,000 bytes, default 2 MB).
2. The app tries quality 100% down to 0% in 5-point steps, then shrinks dimensions down to a 1080 px short edge (1920 x 1080 for 16:9).
3. Only a validated JPEG within the limit is saved as `-target-size.jpg`. Already-small files are skipped; unreachable limits report an error.

**3. Resize + Optimize**

1. Tools > Resize + Optimize on JPEG, PNG or HEIC.
2. Choose 25/50/75%, longest edge 1080/1920 px, or custom bounds. The sheet previews orientation-aware dimensions; images never enlarge.
3. A smaller validated result is saved as `filename-resized.ext`; otherwise "No useful reduction".

**4. Markdown export**

1. Drop a UTF-8 `.md` or `.markdown` file (up to 10 MB). Actions: PDF and DOCX.
2. Options: Allow Local Images (grants a folder), page size A4/US Letter, serif/sans font, 8-24 pt body, 20-90 pt margins (PDF only).
3. Images default to alt text; remote images are never fetched. Each file exports separately.

**5. Stronger PDF compression**

1. Select a PDF, expand Options, enable Stronger PDF compression, choose Balanced (150 DPI images) or Maximum (100 DPI), then Compress.
2. Protected or interactive PDFs (encrypted, signed, forms, other annotations, layers, tagged) show an error and keep the original.

**6. Watched folders and automation rules**

1. Settings > Watched Folders > add a folder through the native picker.
2. Manage Rules: add a rule with a name, enabled toggle, scope (include subfolders), Match All/Any conditions and ordered actions.
3. Test Rule previews matching files, planned actions and provisional filenames without changing anything.
4. New, stable arrivals run automatically. Enabled rules evaluate top to bottom; the first match runs and the rest are skipped.
5. Run Now previews existing files and requires an explicit Run. Saving or editing a rule never processes existing files.
6. Activity records each run; a failed step can be retried from that step in the same session.

Rule behavior:

| Area | Behavior |
| --- | --- |
| Conditions | Filename, extension, category (image, PDF, video, audio, document, archive, other), size (MB), created/modified date (`yyyy-MM-dd`), width/height, Finder tags, document text, file type |
| Comparisons | Text: is, is not, contains, does not contain, starts with, ends with (case-insensitive). Numbers/dates: is, is not, greater, less |
| Text search | UTF-8 files up to 2 MB; searchable PDFs up to 20 MB and 500 pages, at most 2 MB extracted text. No OCR |
| Missing metadata | Never satisfies a negative condition |
| Actions | Rename, Move to folder, Copy to folder, Compress, Convert image (to JPEG/PNG/HEIC/TIFF/PDF), Resize image, Remove metadata |
| Working file | Copy, Convert, Resize and Remove metadata create copies that later actions operate on. Compress offers Keep Both or Replace Original |
| No reduction | Not an error; the rule continues and no savings are reported |
| Failure | Stops remaining actions for that file only; completed results are kept |
| Chaining | OrbitConvert outputs never trigger another watched folder's rules |
| Overlap | The most specific enabled watched folder owns a file |
| Migration | Pre-rule folder settings become an equivalent "Compress new files" rule; new folders start with no rules |

Rename tokens use the file's creation date (falling back to modification date, recorded in activity):

| Token | Meaning | Example |
| --- | --- | --- |
| `yy` / `yyyy` | Year | `26` / `2026` |
| `MM` | Month (case-sensitive) | `10` |
| `dd` | Day | `10` |
| `HH` | Hour 00-23 | `19` |
| `mm` | Minute (case-sensitive) | `16` |
| `ss` | Second | `15` |
| `{name}` | Original name without extension | `Screenshot` |
| `{ext}` | Current extension | `png` |
| `{i}` / `{i:03}` | First unused number / padded | `1` / `001` |

Quote literal text in single quotes (`'Photo'`); double a quote to escape it. Omitting `{ext}` keeps the extension. Examples for `Screenshot.png` created 2026-10-10 19:16:15:

| Template | Result |
| --- | --- |
| `'Photo'_yyyy-MM-dd_HH-mm-ss_{i}.{ext}` | `Photo_2026-10-10_19-16-15_1.png` |
| `yyyy-MM-dd_HH-mm-ss_{name}_{i}.{ext}` | `2026-10-10_19-16-15_Screenshot_1.png` |
| `'Scan'_{i:03}.{ext}` | `Scan_001.png` |
| `'Photo'_yyyy-MM-dd_{i}` | `Photo_2026-10-10_1.png` |

`{i}` starts at 1 per destination folder and advances until the full name is unused, accounting for names reserved earlier in the same batch. Repeated `{i}` tokens share one number. Without `{i}`, collisions get a numeric suffix. Preview names are provisional; history shows the actual final name.

**7. Clipboard optimization**

1. Enable in Settings (separately for copied pixels and copied image files).
2. Copy a PNG, JPEG, TIFF or HEIC image (up to 128 MB, 64 MP). The app optimizes it in the background and writes the smaller version back only if the clipboard has not changed since.
3. An optional result card shows the thumbnail, sizes, reduction, Copy, Save, Reveal and Close. A newer card replaces the old one.
4. Optional collection (off by default, 20 results / 128 MB, memory only) offers Copy All, Save All and Clear.
5. Pasting before optimization finishes uses the original image.

**8. Finder Quick Action**

1. Select up to 100 JPEG/PNG/HEIC images, right-click, Quick Actions > Compress with OrbitConvert. Enable it in System Settings > Extensions if missing.
2. Choose **Keep Both** (default, `-optimized` copy), **Replace Original** (button reads Compress & Replace; no undo) or **Choose Output Folder**. The last choice is remembered.
3. Press Compress. macOS asks for access to each source folder for Keep Both/Replace Original. Cancelling a picker cancels the batch before writes.
4. Results show per-file savings, errors and Show in Finder. Stop cancels the remaining files only.

**9. Settings**

General: compression preset, JPEG export quality, PDF image DPI, metadata removal, Dock icon visibility. Clipboard: enable switches, preset, result cards, collection, ignored apps. Watched Folders: folder list, enable/disable, global pause, Launch at Login, Manage Rules, five recent results, View All Activity.

### Navigation structure

- Main window (default 760 x 620, minimum 620 x 460): toolbar with Add Files and Settings; file list; shared action area.
- Settings scene with tabs: General, Clipboard, Watched Folders.
- Recent Activity window (460 x 500).
- Sheets: Resize options, Compress to Size options, Rules list (680 x 520), Rule editor (760 x 620), Preview (700 x 520).
- Windows: Quick Compression (one per Finder invocation), clipboard result card (330 x 180, nonactivating).
- MenuBarExtra popup.

Closing the main window leaves the menu bar and watching running; Quit terminates.

### Permission gating

There are no accounts or sign-in. Access is gated by sandbox grants:

| Operation | Requires |
| --- | --- |
| Reading a dropped/chosen file | That file's user grant |
| Saving beside the source | A grant for the parent folder; otherwise the app asks for an output folder |
| Watching a folder | App-scoped bookmark from the folder picker |
| Move/Copy rule destinations | Bookmark from the destination picker |
| Markdown local images | Explicitly granted resource folder |
| Finder Quick Action Keep Both/Replace | Per-source-folder grant during the dialog |

### State transitions

| Surface | States |
| --- | --- |
| Manual job | Preparing, Converting, Saving, Completed / Failed / Cancelled |
| Watched job | Queued, checking, compressing, validating/saving; Optimized / Skipped / Failed |
| Watched folder | Active, disabled, paused (globally), unavailable (needs Grant Access) |
| Main window | Empty (large drop zone), loaded (rows + actions), processing (selection locked) |
| Activity | Empty state "No Activity Yet"; populated list |
| Progress | Indeterminate; counts describe files, never invented codec percentages |

### Edge cases

- **Offline:** no effect; nothing uses the network.
- **Permission denied / revoked:** ask for a folder; never save somewhere else silently. Watched folders become unavailable with Grant Access.
- **Unmounted or moved folder:** marked unavailable.
- **Partial downloads:** temporary names are ignored; files must be stable for two one-second checks (60-check timeout).
- **Writer pauses longer than the quiet period:** best-effort only; test producer apps before relying on Replace Original.
- **Pause:** stops new admissions; the active job finishes safely; queued jobs wait for Resume. Arrivals during pause need Run Now.
- **Crash during replacement:** a hidden `.orbitconvert-backup-*` file may remain; inspect before deleting.
- **No reduction:** original kept, reported as skipped, not failed.
- **Clipboard changed during processing:** the newer content is left untouched.
- **iCloud placeholders, symlinks, packages, hidden files:** skipped.

## Privacy

All conversion stays local. Activity stores filenames, outcomes, byte counts, dates, messages, rule names, step results and destination paths; no file contents. Clipboard writes use `.currentHostOnly`. The app never requests clipboard-privacy bypasses.
