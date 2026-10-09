# Architecture

Status: Main-window action controls, PDF conversion, manual compression, Finder drops into the main window, and watched folders are implemented.

## Small native application

The project has one application target and one test target. Create files when their behavior is implemented, not an empty copy of every folder in the brief. Use value types and immutable job inputs; preserve source files. Inject focused services where testing needs them. Add protocols at actual interchangeable boundaries, not one protocol per class.

| Area | Responsibility |
| --- | --- |
| App | Lifecycle, isolated branding, composition, UI state |
| Models | FileItem, formats, immutable jobs, results, errors |
| Views | Main window, drop zone, file details, options, settings |
| Services | Type inspection, thumbnails, conversion, safe output, scoped access |
| Tests | Service behavior, fixtures, action grouping, main-window layouts |

Current intake flow: user selects or drops file URLs; FileIntakeService checks local, regular, readable files. FileTypeService then inspects actual bytes with ImageIO, creates bounded oriented thumbnails, reads file metadata, and intersects output formats with installed encoders. Both checks run in a serial background job. Each service balances its security-scoped access around its own read. The UI stores FileItem values and individual issues. Conversion must reacquire scope for its full operation.

Action flow: the main window displays compact checkbox rows and one shared action area for the selected files. `FileAction.common` intersects supported actions. `ConversionControlsView` shows primary compression, a format picker, a tools menu, and collapsed options. `SelectionActionService` snapshots and processes the selection sequentially through the existing `FileActionService`; combined PDF creation and merging execute once. Selection/removal is disabled during processing. Batch jobs request a shared output folder when none has been chosen; single files retain the permission-recovery folder picker. Individual failures do not discard successful batch outputs.

PDFKit owns document/page structure for image-to-PDF, extraction, merge, and optimization. Core Graphics renders individual PDF pages for JPEG/PNG export; ImageIO encodes the bitmap. PDFKit optimization write options may reduce embedded image size without flattening every page. Apple does not expose exact PDF compression DPI or JPEG quality through these options; precise controls require a separate vetted backend. See [PDF and compression](pdf-compression.md).

## Concurrency

Keep observable UI state on MainActor. Run synchronous ImageIO work on an explicitly non-main execution context; marking a method async alone does not move it off MainActor. The current project defaults actor isolation to MainActor, so review service isolation carefully.

Begin with a single bounded worker processing files sequentially. Maintain a structured parent task, propagate cancellation, and check it between inspect, decode, encode, and publish. A synchronous codec call may finish before cancellation takes effect. Keep scoped access alive for the full operation, including awaits. Do not publish a cancelled job; preserve results already completed.

Use ImageIO downsampled thumbnails, not full-size SwiftUI previews. Validate dimensions and arithmetic before expensive allocation. Determine resource limits through large-image profiling and document them before shipping; never silently resize conversions.

## State and errors

FileItem contains identity, source URL, filename, extension, content type/category, file size, optional creation date, bounded thumbnail, and available conversions. Keep framework image objects out of cross-actor value transfers where possible.

Jobs transition through preparing, converting, saving, and a terminal completed/failed/cancelled state. Each file retains its own result. Use errors defined in [API contracts](api.md); map them to readable messages and recovery actions.

Use os.Logger categories FileAccess, Conversion, UI, Permissions, and Errors when logging is added. Log operation identifiers and error categories, not image contents, GPS, or complete user paths.

## Main-window actions and Finder drops

`ConversionControlsView` presents conversion choices and tools for the current selection. `FileAction.category` separates conversions from tools; `FileAction.common` exposes only actions supported by every selected file. Native buttons provide keyboard focus and accessibility labels. Image batches can use mutually supported output formats; PDF batches can export pages or merge.

`ContentView.onDrop` receives Finder file providers in the main window. Provider loading starts inside the drop callback, preserves input order, and forwards URLs through the existing intake and inspection services. Import errors remain in the main window. Selected files flow through the normal action controls; no auxiliary action or drop window is created. Closing the controls still cancels their manual worker.

The floating action and drop-target controllers, panel view, placement code and associated event monitors were removed. Clipboard result cards remain a separate feature. See [Finder workflow](finder-integration.md).

Related: [product plan](product-plan.md), [conversion](image-conversion.md), [sandbox](sandbox-and-output.md).

Watched folders use an app-lifetime controller shared by Settings and MenuBarExtra. FSEvents reports file paths; the controller deduplicates and queues them. `AutoOptimizationService` runs one job off the main actor, reuses ImageIO/PDFKit optimizers, and delegates replacement to `SafeFileReplacementService`. See [watched folders](watched-folders.md).

Automatic clipboard optimization shares that background queue and menu state. It uses generation-guarded pasteboard writes, bounded in-memory results, and the existing image conversion/optimization services. Details, retention policy, and public API limitations: [clipboard optimization](clipboard-optimization.md).

Manual `FileAction.resize` uses the existing selection worker. `ResizeOptionsView` previews orientation-aware dimensions and collects aspect-fit bounds; `ImageResizeService` downsamples, normalizes metadata and reuses image optimization encoding. Collision-safe outputs use a `-resized` suffix. Normal Compress retains its unchanged-dimensions contract. No watcher or clipboard resize policy is introduced. See [Resize + Optimize](resize-optimization.md).
