# Folder automation

Status: implemented. This document records the agreed behavior and implementation limits. Validation results are recorded below.

## Goal

Extend watched folders into customizable file automation. Users build rules inside each watched folder: when a new file matches conditions, run an ordered list of actions. The supplied rule-editor screenshot is the interaction reference: scope, All/Any conditions, action rows, rename tokens, destination picker, enabled toggle, and Save/Cancel.

Support any regular file for organization. Image and PDF processing remains limited to formats and operations OrbitConvert actually supports. "Compress" means supported image/PDF optimization; it does not imply ZIP/archive creation or video compression.

## Confirmed decisions

| Area | Agreed behavior |
| --- | --- |
| Location | Rules belong inside each watched folder, not a separate Automation page. |
| Existing settings | Replace the current single compression policy with rules; migrate existing settings into an equivalent rule. |
| Rule priority | Evaluate enabled rules top to bottom. Run the first matching rule, then stop evaluating other rules. |
| Action order | Run the matching rule's actions in the user's chosen order. |
| Automatic trigger | New arrivals only, after the file finishes copying/downloading sufficiently to pass stability checks. |
| Existing files | Run Now opens a preview and requires an explicit Run action. |
| Rule edits | Adding or editing a rule does not automatically process existing files. |
| Ordinary modifications | Editing an already-known file does not automatically rerun its rules. |
| Cross-folder chaining | OrbitConvert outputs moved into another watched folder do not trigger that folder's rules automatically. |
| Conditions | Support Match All and Match Any. |
| Rule controls | Enable/disable, duplicate, drag to reorder, and Test Rule. |
| Preview | Test Rule previews matches and planned filenames without changing files. |
| History | Retain the latest 200 file runs locally, with per-action results. |

The app must remain running to watch folders. Retain the existing pause, folder enablement, scope and permission model unless a later decision explicitly changes them. Any-file support does not mean following symlinks, entering application packages, or processing partially downloaded files.

## Conditions

The user accepted all of these condition families:

- Filename.
- File extension.
- File category: image, PDF, video, audio, document, archive, and other regular files.
- File size.
- Creation date and modification date.
- Image width and height.
- Finder tags.
- Text inside searchable PDFs and plain-text files.

Scanned-PDF OCR and Word-document text extraction are outside the first version. Media-specific conditions must be presented clearly for relevant files. Do not imply that an unreadable, unsupported or uninspected file was successfully searched.

A condition row contains the field, a suitable comparison, its value, and a remove control. The editor supports adding multiple rows and choosing All/Any. Text comparisons are case-insensitive. Numeric/date fields support equal, not equal, greater and less; text fields support equal, not equal, contains, does not contain, starts with and ends with. Dates use local calendar days in yyyy-MM-dd format. Missing metadata never satisfies a negative condition. Text search supports UTF-8 files up to 2 MB, and searchable PDFs up to 20 MB and 500 pages with at most 2 MB of extracted text.

## Actions

| Action | Intended capability |
| --- | --- |
| Rename | Apply the date/name/number template below. |
| Move | Move the current working file to a user-selected destination. |
| Copy | Create a copy in a user-selected destination. |
| Compress | Optimize supported images/PDFs using existing compression capabilities. |
| Convert | Convert a JPEG, PNG, HEIC or TIFF image to JPEG, PNG, HEIC, TIFF or PDF. |
| Resize | Fit JPEG, PNG or HEIC images within chosen bounds, preserving aspect ratio and never upscaling. |
| Remove metadata | Remove supported hidden details from supported media formats. |

Deletion and custom scripts are excluded from the first version. Supported media actions should expose applicable options without promising that every format supports every operation. Destination folders use native selection and persisted security-scoped access.

### Working file and originals

When Compress uses Keep Both, subsequent Rename and Move actions operate on the compressed copy, leaving the original untouched. A compression action reporting no useful reduction is not an error: continue the rule. If Keep Both needs a file for later actions, make an unchanged copy and continue with that copy.

Replace Original must retain existing candidate validation and smaller-result checks. A failed or larger candidate must not replace the source. Keep Both, Replace Original and destination choices must be clear in the editor, rather than inferred from action ordering.

The existing internal safe-replacement rollback mechanism remains reusable. No new user-facing backup/recovery system is requested.

### Collisions

Never silently overwrite an existing destination. Add a number until an unused filename is found, for example `photo-1.png`. If the rename template contains `{i}`, resolve that placeholder as described below rather than adding an unrelated suffix during ordinary preview planning.

Preview filenames are provisional: another process may create a conflicting name before execution. Publication must remain collision-safe at execution time and history must show the actual final name.

### Failures and retries

If an action fails, stop the remaining actions for that file. Keep completed results and record exactly which step failed. Continue processing other files.

Offer retry from the failed step, without repeating successful compression, rename, copy or move operations. Revalidate the working file and destination access before retrying. Do not silently restart the whole rule if an intermediate file has changed or disappeared.

A no-reduction compression result continues through later actions and is logged distinctly from an error. Do not report byte savings for an unchanged copy.

## Rename templates

Use the source file's creation date, displayed in the Mac's local timezone. If the creation date is unavailable, fall back to its modification date and record that fallback in activity. This means filesystem creation date, not a photo's EXIF capture date.

| Token | Meaning | Example |
| --- | --- | --- |
| `yy` | Two-digit year | `26` |
| `yyyy` | Four-digit year | `2026` |
| `MM` | Month | `10` |
| `dd` | Day | `10` |
| `HH` | Hour, 00-23 | `19` |
| `mm` | Minute | `16` |
| `ss` | Second | `15` |
| `{name}` | Original filename without its extension | `Screenshot` |
| `{ext}` | Current file's extension | `png` |
| `{i}` | First available positive filename number | `1`, `2`, `3` |
| `{i:03}` | Same numbering, padded to at least three digits | `001`, `002`, `003` |

Month `MM` and minute `mm` are case-sensitive. Quote literal text with single quotes so words are not interpreted as date tokens. The editor shows a live filename preview and visible token help.

If `{ext}` is omitted, preserve the working file's extension automatically. Rename must not silently change the file format. After conversion, the output extension must remain consistent with the new format.

### Examples

Assume a PNG named `Screenshot.png`, created on 2026-10-10 at 19:16:15 local time.

| Template | First available result |
| --- | --- |
| `'Photo'_yyyy-MM-dd_HH-mm-ss_{i}.{ext}` | `Photo_2026-10-10_19-16-15_1.png` |
| `yyyy-MM-dd_HH-mm-ss_{name}_{i}.{ext}` | `2026-10-10_19-16-15_Screenshot_1.png` |
| `'Scan'_{i:03}.{ext}` | `Scan_001.png` |
| `'Photo'_yyyy-MM-dd_{i}` | `Photo_2026-10-10_1.png` |

### Increment behavior

Numbering starts at 1 for the candidate name and checks the applicable destination folder. It advances until that complete filename is unused; it is not a global counter shared by all rules.

For `'Photo'_{i}.{ext}`:

1. If `Photo_1.png` does not exist, use it.
2. If `Photo_1.png` exists, try `Photo_2.png`.
3. If both exist, try `Photo_3.png`.
4. Existing files remain unchanged.

Account for names reserved by earlier files in the same batch. Collision checks must respect the destination filesystem's case sensitivity and actual publication behavior.

Rename resolves numbering in its current folder. A later Move performs a separate collision check in its destination. Single quotes are escaped by doubling them. Repeated increment tokens share one number. With no date metadata, patterns containing date tokens fail; patterns without date tokens still work. Extensionless files remain extensionless, including when the pattern ends in .{ext}.

## Rule editor and previews

Each watched folder shows its ordered rules and an Add Rule control. Each rule exposes a readable name, enabled state, scope, All/Any condition group, and ordered actions.

The editor follows the reference screenshot's structure while using OrbitConvert's native styling:

- Condition rows with field, comparison and value controls.
- Action rows with relevant options; no irrelevant media options for arbitrary files.
- Rename template input, token helpers and live preview.
- Native destination-folder picker for Move/Copy.
- Add/remove controls and action reordering.
- Save and Cancel, with readable validation messages.

Test Rule performs no file mutations. Show matching files, planned actions, proposed filenames/destinations, and any unavailable checks. Do not claim a predicted compression ratio is a measured result.

Run Now previews existing files first and requires explicit Run. Editing or saving a rule alone never executes it on the existing folder contents.

## Activity

Keep the latest 200 file runs locally. Each run records:

- Rule name and run time.
- Original filename and resulting filename.
- Destination.
- Each action's outcome, including skipped/no-reduction steps.
- Original/final size and savings where compression occurred.
- Failure details and the step from which retry is available.
- Creation-date fallback when used.

History shows completed and failed steps, partial runs, and no-reduction messages. Optional automation details preserve compatibility with older history. Retry checkpoints are session-only and disappear on relaunch; persisted history remains readable. A retry verifies its working file before resuming the failed step.

## Existing implementation to reuse

- `FolderWatchService`: FSEvents monitoring and rescans.
- `WatchedFoldersController`: sequential queue, pause, cancellation, permissions and output-loop suppression.
- Existing stability/fingerprint checks and scoped bookmarks.
- Existing image/PDF processing services.
- `SafeFileReplacementService`: guarded replacement and Keep Both.
- `FileOutputService`: no-overwrite publication.
- Existing activity presentation and storage, extended for rule runs.

AutomationRule and AutomationConditionService model rules and matching. AutomationRenameTemplate expands names. AutomationExecutionService runs actions with session checkpoints. AutomationFileOperations publishes general files without overwrite; AutomationMediaService reuses media processors. AutomationWatchService connects the queue; AutomationPreviewService provides read-only planning. Native SwiftUI rules, editor and preview sheets live under Watched Folders.

## Migration and limits

Existing folder settings migrate to an equivalent compression rule on load, preserving permissions, enabled state, scope, supported types, preset and original handling, including legacy Move Original to Trash. New folders start with no rules and leave files alone until a rule is saved.

Copy makes the copy the working file for later actions. Rename and Move preserve the user's action order. The most specific enabled watched folder owns an overlapping input; other watched folders do not process it again. Every intermediate output is suppressed from automatic chaining. Publication attempts that collide do not discard other queued inputs.

Moves validate a complete destination copy before removing the source. A failed source removal records the retained destination and retries only cleanup, after validating both files. Symlinks and symlink ancestors are rejected, apart from macOS root-level system aliases. File stability and fingerprint checks are best-effort protection against uncoordinated external writers, not a filesystem transaction across applications.

Conversion, resizing and metadata removal create copies. Compression alone exposes Keep Both or Replace Original. Media output names in previews are provisional; final names and compression savings are measured during execution. Unsupported media actions are reported before Run when detectable from the file type. PDF metadata removal clears document attributes; it does not redact visible content or embedded attachments. Image metadata removal may re-encode the copy.

Rule names are limited to 120 characters, rules to 32 conditions and 16 actions, and rename patterns to 1,024 bytes. Published names must fit 255 UTF-8 bytes and cannot contain path separators, control characters or hidden-file prefixes. No deletion, scripts, OCR, archive compression, PDF-to-image automation, or persistent retry queue is added.

## Acceptance checks

- Existing folder settings and history remain readable after migration.
- Generic documents can be renamed/moved/copied without being sent to an image decoder.
- Only new, stable arrivals run automatically; edits and rule changes do not process old files.
- First matching enabled rule wins; actions retain the chosen order.
- Keep Both chains never mutate the original, including after no reduction.
- Failure stops only that file; retry does not repeat successful steps.
- Rule outputs do not trigger another watched folder automatically.
- Rename date tokens, quoted literals, extension preservation, `{i}` and padded numbering match the agreed examples.
- Batch and concurrent filename collisions never overwrite existing files.
- Test Rule and Run Now previews make no file changes before execution is confirmed.
- History explains partial runs and correctly reports savings and date fallback.
- Folder permission loss, cancellation and cross-volume failures retain recoverable files and truthful outcomes.

Implementation should use tests first for rule evaluation, migration, template parsing, collision allocation and ordered failure/retry behavior, plus native UI checks for the rule editor.

## Validation

The normal Release build and strict deep code-signature verification pass. The full Release test suite passes 174 tests. Automation core line coverage is 89.38%; whole-app line coverage is 65.94%, below the repository's 80% target. Core coverage excludes SwiftUI view/editor files. Tests cover ordered execution and retry, condition families, rename tokens, legacy history, preview-only behavior, changed inputs, collision publication, substituted symlink ancestors, Keep Both without reduction, and cross-folder output suppression.

The rule editor fits its 760 by 620 point host window in the native layout test. Cached screenshot rendering does not reliably capture native controls, so full visual interaction, VoiceOver, installed-app sandbox access and physical cross-volume moves remain manual checks. Code review found no remaining high-severity issues after the reported fixes.

## References and related documentation

Apple documents optional filesystem creation dates and Finder tag names in [URLResourceValues](https://developer.apple.com/documentation/foundation/urlresourcevalues). Existing PDF text can be read through [PDFDocument.string](https://developer.apple.com/documentation/pdfkit/pdfdocument/string); that capability does not imply OCR.

Related: [current watched folders](watched-folders.md), [sandbox and output safety](sandbox-and-output.md), [architecture](architecture.md), [testing](testing.md).
