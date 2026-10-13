# Data Models and Internal Contracts

OrbitConvert has no backend, database, network API, HTTP server or OpenAPI schema. This document records persisted data (UserDefaults), in-memory value types and the internal service contracts that replace an API.

## Persistence overview

| Store | Key | Contents | Format |
| --- | --- | --- | --- |
| UserDefaults | `watchedFolders` | `[WatchedFolder]` | JSON (Codable) |
| UserDefaults | `watchedActivity` | `[WatchActivity]`, latest 200 | JSON (Codable) |
| UserDefaults | `watchingPaused` | Global watch pause | Bool |
| @AppStorage | `defaultCompressionPreset` | `CompressionPreset` raw value | String |
| @AppStorage | `jpegExportQuality` | JPEG conversion quality 0...1 (default 0.90) | Double |
| @AppStorage | `pdfImageDPI` | PDF-to-image resolution (72/100/150/200/300, default 150) | Int |
| @AppStorage | `removeMetadata` | Strip descriptive metadata | Bool |
| @AppStorage | `hideDockIcon` | Accessory activation policy | Bool |
| UserDefaults | `clipboardEnabled`, `clipboardImages`, `clipboardFiles` | Clipboard switches | Bool |
| UserDefaults | `clipboardPreset` | Clipboard compression preset | String |
| UserDefaults | `clipboardShowResults`, `clipboardCollect` | Result card, in-memory collection | Bool |
| UserDefaults | `clipboardIgnoredApps` | Ignored bundle IDs | [String] |
| @AppStorage | `paletteLevel` | Palette PNG (pngquant) for Compress, Compress to Size and Quick Action: `off`, `safe` (quality 80-100), `smaller` (60-100); default off | String (`PaletteLevel`) |
| (legacy) | `paletteReduction` | Pre-F8 Bool; read only when `paletteLevel` is missing or invalid (true = safe); `PaletteLevel.migrate` copies it to `paletteLevel` at app launch | Bool |
| UserDefaults | `quickCompressionMode` | Last Finder Quick Action save choice | String |
| UserDefaults | `lifetimeSavedBytes` | Total bytes saved across launches (watched folders, clipboard, manual, Quick Action); seeded once from history | Int64 (NSNumber) |
| UserDefaults | `lifetimeOptimizedCount` | Number of results that saved space | Int |

Test hosts use a unique `OrbitConvert.TestHost.<UUID>` suite and never start the clipboard monitor or restore personal folders.

Rules: validate loaded values and fall back to documented defaults. Bookmark bytes are stored, never raw paths as permission. Do not log bookmark bytes. Jobs, thumbnails and clipboard collections stay in memory. No schema migrations, database framework, sync or analytics storage. Any future DB change follows the repository rule: SQL goes to `docs/new-changes-db.sql`, applied manually.

## Entities

### WatchedFolder

| Field | Type | Constraints | Notes |
| --- | --- | --- | --- |
| id | UUID | immutable | Identity; also the ID of a migrated legacy rule |
| displayName | String | | Folder name shown in Settings |
| bookmarkData | Data | app-scoped security bookmark | Refreshed when stale |
| isEnabled | Bool | default true | |
| watchSubdirectories | Bool | default false | Legacy scope |
| preset | CompressionPreset | default `.balanced` | Legacy policy |
| supportedTypes | Set<WatchFileType> | default: available types | Legacy policy |
| replacementBehavior | ReplacementBehavior | default `.replaceOriginal` | Legacy policy |
| rules | [AutomationRule]? | nil = legacy | Ordered; first enabled match wins |

Derived: `effectiveRules` returns `rules`, or, when nil, one "Compress new files" rule built from the legacy fields (Match Any on file type). `recursive` is true when any rule includes subfolders.

### AutomationRule

| Field | Type | Constraints | Notes |
| --- | --- | --- | --- |
| id | UUID | | `duplicated()` assigns a new ID and appends " copy" |
| name | String | 1-120 chars, non-blank | |
| isEnabled | Bool | default true | |
| includeSubfolders | Bool | default false | Scope |
| matchAll | Bool | default true | All vs Any |
| conditions | [AutomationCondition] | 1-32 | |
| actions | [AutomationAction] | 1-16 | Executed in order |

### AutomationCondition

| Field | Type | Constraints |
| --- | --- | --- |
| id | UUID | |
| field | AutomationField | default `.fileExtension` |
| comparison | AutomationComparison | must be allowed for the field |
| value | String | 1-2,000 chars; numeric fields finite and >= 0; date fields `yyyy-MM-dd` |

### AutomationAction

| Field | Type | Default | Constraints |
| --- | --- | --- | --- |
| id | UUID | | |
| kind | AutomationActionKind | `.rename` | |
| template | String | `yyyy-MM-dd_{name}_{i}.{ext}` | Parsed by `AutomationRenameTemplate`; up to 1,024 bytes |
| destinationBookmark | Data? | nil | Required for Move/Copy |
| destinationName | String | "Choose a folder" | Display only |
| preset | CompressionPreset | `.balanced` | Not `.custom` |
| replacement | ReplacementBehavior | `.keepBoth` | Compress only |
| palette | PaletteLevel? | nil (Off) | Compress only, PNG only; optional so rules saved before 2026-10-13 decode; unknown stored values decode as Off so the watched-folder list never fails to load |
| format | String | `jpeg` | `jpeg`, `png`, `heic`, `tiff`, `pdf` |
| width / height | Int | 1920 / 1080 | 1-100,000 |
| quality | Double | 0.9 | finite, 0...1 |

### WatchActivity

| Field | Type | Notes |
| --- | --- | --- |
| id | UUID | |
| date | Date | |
| fileName | String | Name only, no full path |
| outcome | WatchActivityOutcome | Optimized / skipped / failed |
| originalBytes, outputBytes | Int64 | |
| message | String | Explanation for skipped/failed |
| automation | AutomationRunDetails? | Optional, so older history still decodes |

Derived: `savingsBytes` (automation savings, or `original - output` for optimized results, never negative) and `savingsPercentage`.

### AutomationRunDetails and AutomationStepRecord

`AutomationRunDetails`: `ruleName`, `finalName`, `destination`, `steps`, `dateFallback` (creation date unavailable), `compressionOriginalBytes`, `compressionSavedBytes`.

`AutomationStepRecord`: `id`, `action`, `inputName`, `outputName`, `destination`, `message`, `failed`, `savedBytes` (default 0).

`AutomationCheckpoint` (memory only, session-scoped): original facts, rule, working URL, expected fingerprint, next action index, completed steps, byte totals, optional cleanup output and its expected fingerprint. Checkpoints disappear on relaunch; persisted history stays readable.

### Relationships

- WatchedFolder has many AutomationRules (ordered).
- AutomationRule has many AutomationConditions and many AutomationActions (ordered).
- WatchActivity optionally has one AutomationRunDetails, which has many AutomationStepRecords.
- Activity is shared by watched-folder and clipboard jobs; manual foreground actions are not recorded.

## Enums and constants

| Enum | Values |
| --- | --- |
| CompressionPreset | `lossless`, `balanced`, `aggressive` (label "Maximum"), `custom` |
| WatchFileType | `jpeg`, `png`, `heic`, `pdf` (HEIC only when the encoder is available) |
| ReplacementBehavior | `replaceOriginal`, `moveOriginalToTrash` (legacy), `keepBoth` |
| AutomationField | Filename, Extension, File category, Size (MB), Created date, Modified date, Width (pixels), Height (pixels), Finder tags, Document text, File type |
| AutomationComparison | is, is not, contains, does not contain, starts with, ends with, is greater than, is less than |
| AutomationActionKind | Rename, Move to folder, Copy to folder, Compress, Convert image, Resize image, Remove metadata |

Comparisons per field: File type allows is/is not; numeric and date fields allow is, is not, greater, less; text fields allow the six text comparisons.

Constants: activity limit 200; popup shows 3, Settings shows 5; clipboard poll 600 ms; stability 2 x 1 s checks, 60-check timeout; clipboard SHA registry 128 entries / 1 hour; clipboard collection 20 results / 128 MB; export temp 64 directories / 256 MB, sweep after 24 h; Quick Action max 100 files.

## In-memory values

- **FileItem:** URL identity, URL, display name, extension, detected type identifier/name, byte size, optional creation date, pixel dimensions, bounded thumbnail data, available conversion formats. Permission is not retained after inspection.
- **ConversionFormat:** stable ID, UTType, canonical extension, label, options. Display "JPG", write `.jpg`.
- **ConversionOptions:** JPEG quality 0...1 (default 0.90, nonfinite rejected), metadata stripping flag.
- **ConversionResult / CompressionResult:** source and output URLs, original and result byte counts. No output URL until publication succeeds. Savings derived; zero-byte input handled.
- **FileAction:** kind, category (conversion or tool), ID, title. `FileAction.common` intersects selections. `FileActionSettings.resizeOptions` defaults to 50%.
- **ResizeOptions:** preset or custom bounds; `dimensions` computes aspect-fit without enlargement.
- **OptimizationOutcome:** smaller validated output or a no-reduction result (`estimatedJPEGQuality` set when a JPEG was skipped as already compressed).

## File and media storage

| Output | Naming |
| --- | --- |
| Conversion | `photo.jpg`, then `photo-1.jpg`, `photo-2.jpg` |
| Resize | `name-resized.ext` |
| Compress to Size | `name-target-size.jpg` |
| Quick Action Keep Both | `name-optimized.ext` |
| Automation rename | Template result, numbered per destination |
| Replacement backup | Hidden `.orbitconvert-backup-*` beside the source (removed after success) |
| Replacement staging | `.orbitconvert-replace-*` private directory beside the source |
| Quick Action request | `.orbitcompress` document in the extension container (expires after a day) |

Temporary work lives in private 0700 directories (destination folder or app temporary area) and is removed on success, failure and cancellation.

## Caching

- Recent output fingerprints and baseline sets prevent reprocessing the app's own outputs (about five minutes).
- Clipboard SHA256 registry (hashes only, not persisted).
- Clipboard temporary exports reused by result ID.

## Background jobs

| Queue | Jobs | Policy |
| --- | --- | --- |
| Shared watch queue (`WatchedFoldersController`) | Watched-folder arrivals, Run Now, clipboard optimizations | Sequential; dedupe by path; newer clipboard change replaces waiting clipboard job; legacy jobs retry up to 3 times; automation failures retry manually from the failed step |
| Manual selection worker | Main-window actions | Sequential detached task; cancelled when controls close |
| Quick Compression worker | Finder Quick Action batch | Sequential per window; Stop cancels remaining files |

## Migration

Legacy folders (rules = nil) load as one equivalent compression rule, keeping permissions, enabled state, scope, types, preset and original handling (including Move Original to Trash). `WatchActivity.automation` is optional so older history decodes. Add new fields with defaults or optionals; never reset the saved folder list because one entry fails to decode.

## Internal service contracts (API equivalent)

| Service | Input | Output and responsibility |
| --- | --- | --- |
| FileIntakeService | Selected/dropped URLs | Local regular readable files plus per-item issues |
| FileTypeService | Validated URLs | Byte-based type, metadata, bounded thumbnail, installed output formats |
| ImageConversionService | Job + temporary destination | Encoded image or typed error |
| PDFConversionService | Images or PDF + options | Image-to-PDF, page render, extraction, merge |
| ImageOptimizationService | JPEG/PNG/HEIC + preset | Smaller validated candidate or no reduction |
| OxipngService | PNG handle + preset | Lossless optimized PNG |
| PDFOptimizationService | PDF + preset/backend | Native or Ghostscript candidate, validated |
| ImageResizeService | Image + ResizeOptions | `OptimizationOutcome` |
| TargetSizeCompressionService | JPEG + byte limit | Within-limit JPEG or unreachable error |
| MarkdownConversionService | Markdown + options | DOCX or PDF |
| BatchConversionService / BatchOptimizationService | Ordered files + folder | Sequential per-file results |
| FileActionService | Action + settings | Dispatch to the services above |
| SelectionActionService | Selection snapshot | Sequential execution, grouped PDF operations |
| FileOutputService | Authorized directory + basename | No-overwrite publication |
| SafeFileReplacementService | Source + candidate | Guarded in-place replacement with rollback |
| AutomationConditionService | File facts + rule | Match result |
| AutomationExecutionService | File + rule | Ordered actions, run details, checkpoint |
| AutomationPreviewService | Folder + rule | Read-only plan with provisional names |
| QuickCompressionService | Sources + save mode | Per-file results |

Views never decode, encode, acquire persistent permissions or choose collision names.

### Errors

| Error | User-facing meaning |
| --- | --- |
| unsupportedInput | This file type is not supported |
| unsupportedOutput | This output format is unavailable on this Mac |
| cannotDecode | This image could not be opened; it may be damaged |
| cannotEncode | This image could not be converted to the selected format |
| cannotWriteFile | The result could not be saved; check space and destination |
| permissionDenied | OrbitConvert does not have permission; choose an authorized folder |
| invalidDestination | Choose an available folder for the output |
| AutomationError.invalid | Rule validation message (for example "Enter dates as yyyy-MM-dd.") |

Cancellation is a separate terminal state, not a failure alert. Keep underlying errors for redacted diagnostics; do not show raw NSError text by default.
