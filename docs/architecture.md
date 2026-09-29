# Architecture

Status: Main-window and floating rectangular action panels, PDF conversion, manual compression, and the supported Finder drop-target workflow are implemented.

## Small native application

The project has one application target and one test target. Create files when their behavior is implemented, not an empty copy of every folder in the brief. Use value types and immutable job inputs; preserve source files. Inject focused services where testing needs them. Add protocols at actual interchangeable boundaries, not one protocol per class.

| Area | Responsibility |
| --- | --- |
| App | Lifecycle, isolated branding, composition, UI state |
| Models | FileItem, formats, immutable jobs, results, errors |
| Views | Main window, drop zone, file details, options, settings |
| Services | Type inspection, thumbnails, conversion, safe output, scoped access |
| Tests | Service behavior, fixtures, action grouping, floating placement |
| FileActionPanelView | Shared rectangular file header and valid action buttons |

Current intake flow: user selects or drops file URLs; FileIntakeService checks local, regular, readable files. FileTypeService then inspects actual bytes with ImageIO, creates bounded oriented thumbnails, reads file metadata, and intersects output formats with installed encoders. Both checks run in a serial background job. Each service balances its security-scoped access around its own read. The UI stores FileItem values and individual issues. Conversion must reacquire scope for its full operation.

Action flow: each file row presents actions valid for its detected ImageIO or PDFKit content. `FileActionPanelView` renders the same descriptors in the main window and floating panel, grouped as Convert and Tools. Selection returns to `ConversionControlsView`; a detached worker calls `FileActionService`, which routes to ImageIO conversion, PDFKit/Core Graphics PDF operations, or native optimization. Services reacquire source and destination scope, validate temporary output, and use `FileOutputService` for no-overwrite publication. Batch conversion and optimization process selected files sequentially and report per-file failures without discarding prior results.

PDFKit owns document/page structure for image-to-PDF, extraction, merge, and optimization. Core Graphics renders individual PDF pages for JPEG/PNG export; ImageIO encodes the bitmap. PDFKit optimization write options may reduce embedded image size without flattening every page. Apple does not expose exact PDF compression DPI or JPEG quality through these options; precise controls require a separate vetted backend. See [PDF and compression](pdf-compression.md).

## Concurrency

Keep observable UI state on MainActor. Run synchronous ImageIO work on an explicitly non-main execution context; marking a method async alone does not move it off MainActor. The current project defaults actor isolation to MainActor, so review service isolation carefully.

Begin with a single bounded worker processing files sequentially. Maintain a structured parent task, propagate cancellation, and check it between inspect, decode, encode, and publish. A synchronous codec call may finish before cancellation takes effect. Keep scoped access alive for the full operation, including awaits. Do not publish a cancelled job; preserve results already completed.

Use ImageIO downsampled thumbnails, not full-size SwiftUI previews. Validate dimensions and arithmetic before expensive allocation. Determine resource limits through large-image profiling and document them before shipping; never silently resize conversions.

## State and errors

FileItem contains identity, source URL, filename, extension, content type/category, file size, optional creation date, bounded thumbnail, and available conversions. Keep framework image objects out of cross-actor value transfers where possible.

Jobs transition through preparing, converting, saving, and a terminal completed/failed/cancelled state. Each file retains its own result. Use errors defined in [API contracts](api.md); map them to readable messages and recovery actions.

Use os.Logger categories FileAccess, Conversion, UI, Permissions, and Errors when logging is added. Log operation identifiers and error categories, not image contents, GPS, or complete user paths.

## Rectangular action panel

`FileActionPanelView` receives `[FileAction]`, thumbnail data, and select/dismiss closures; it contains no conversion logic. `FileAction.category` separates valid conversion actions from tools. Adaptive grid buttons use standard SwiftUI hit testing, keyboard focus, and accessibility labels. The main-window panel remains available if a display cannot fit the floating panel.

Tab navigates controls, Return invokes the first action, and Escape dismisses the floating panel. Native buttons provide pointer and VoiceOver access. For mixed file types, actions remain per-file; batch JPEG/PNG buttons appear only when every selected file supports the format.

## Floating NSPanel, Phase 6

SwiftUI's regular window scene does not expose the panel's nonactivating style, transparent chrome, floating level, or global screen placement. `FloatingActionPanelController` hosts `FileActionPanelView` in `NSHostingView` inside a borderless [nonactivating NSPanel](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel). It returns actions to `ConversionControlsView`; no conversion or file access runs in the controller. The panel can become key for keyboard input without explicitly activating the application.

`FloatingPanelPlacement` chooses the display whose full frame contains the cursor, then clamps the panel to its [visibleFrame](https://developer.apple.com/documentation/appkit/nsscreen/visibleframe), including negative monitor origins. It falls back to the nearest display if needed. If no display can fit the panel, main-window actions remain. The controller repositions on display changes, uses local and global mouse-down monitors for outside clicks, intercepts Escape in its own panel, and removes observers when closing. Global keyboard monitoring is not used. Opening and closing fade for 180 ms unless Reduce Motion is enabled. Live panel focus, Escape, appearance, and monitor changes still need manual verification.

## Finder integration, Phase 9

`FloatingDropWindowController` owns a visible nonactivating drop-target panel. The main window opens it on request. SwiftUI's `onDrop` receives Finder file providers only after the pointer enters and drops on this app-owned window; loading starts inside the drop callback. `ContentView` performs the existing intake/type inspection, scrolls the first supported item into view, and tells its existing `ConversionControlsView` to open the floating action panel. Extra files remain in the main window. Panel code does not inspect or convert files.

This does not detect arbitrary Finder drag starts. No Accessibility permission or Finder extension is used. Details and official API sources: [Finder feasibility](finder-integration.md). Signed sandbox, inactive-app drop delivery, and multi-display behavior still require manual tests; App Store acceptance remains subject to review.

Related: [product plan](product-plan.md), [conversion](image-conversion.md), [sandbox](sandbox-and-output.md).
