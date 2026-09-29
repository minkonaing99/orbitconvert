# Architecture

Status: Phases 1-3 implemented; conversion architecture remains proposed. The app has `OrbitConvertApp.swift`, `AppIdentity.swift`, `ContentView.swift`, `FileIntakeService.swift`, and `FileTypeService.swift`.

## Small native application

The project has one application target and one test target. Create files when their behavior is implemented, not an empty copy of every folder in the brief. Use value types and immutable job inputs; preserve source files. Inject focused services where testing needs them. Add protocols at actual interchangeable boundaries, not one protocol per class.

| Area | Responsibility |
| --- | --- |
| App | Lifecycle, isolated branding, composition, UI state |
| Models | FileItem, formats, immutable jobs, results, errors |
| Views | Main window, drop zone, file details, options, settings |
| Services | Type inspection, thumbnails, conversion, safe output, scoped access |
| Tests | Service behavior, fixtures, later radial geometry |
| RadialMenu, later | Geometry, view, controller, floating panel |

Current intake flow: user selects or drops file URLs; FileIntakeService checks local, regular, readable files. FileTypeService then inspects actual bytes with ImageIO, creates bounded oriented thumbnails, reads file metadata, and intersects output formats with installed encoders. Both checks run in a serial background job. Each service balances its security-scoped access around its own read. The UI stores FileItem values and individual issues. Conversion must reacquire scope for its full operation.

Planned conversion flow: inspection creates FileItem values; UI shows available formats; an immutable job captures options; conversion encodes to a temporary file; output publishes safely; UI receives a result. Both the normal window and future radial menu use the same job path.

## Concurrency

Keep observable UI state on MainActor. Run synchronous ImageIO work on an explicitly non-main execution context; marking a method async alone does not move it off MainActor. The current project defaults actor isolation to MainActor, so review service isolation carefully.

Begin with a single bounded worker processing files sequentially. Maintain a structured parent task, propagate cancellation, and check it between inspect, decode, encode, and publish. A synchronous codec call may finish before cancellation takes effect. Keep scoped access alive for the full operation, including awaits. Do not publish a cancelled job; preserve results already completed.

Use ImageIO downsampled thumbnails, not full-size SwiftUI previews. Validate dimensions and arithmetic before expensive allocation. Determine resource limits through large-image profiling and document them before shipping; never silently resize conversions.

## State and errors

FileItem contains identity, source URL, filename, extension, content type/category, file size, optional creation date, bounded thumbnail, and available conversions. Keep framework image objects out of cross-actor value transfers where possible.

Jobs transition through preparing, converting, saving, and a terminal completed/failed/cancelled state. Each file retains its own result. Use errors defined in [API contracts](api.md); map them to readable messages and recovery actions.

Use os.Logger categories FileAccess, Conversion, UI, RadialMenu, Permissions, and Errors. Log operation identifiers and error categories, not image contents, GPS, or complete user paths.

## Radial menu, Phase 5

Pass action descriptors to the menu; execution belongs to services. Separate pure geometry from SwiftUI drawing. Handle zero/one/many actions, inner dead zone, outer boundary, wraparound, and coordinate direction explicitly. Use atan2 and a normalized angle for selection, with the same origin and ordering used for rendering.

Provide arrows, Return, Escape, VoiceOver labels, visible focus, and a conventional list alternative. Do not depend on hover alone. For mixed file types, offer only actions valid for the complete selection, or explain exclusions before execution.

## Floating NSPanel, Phase 6

AppKit is needed for window level, transparent chrome, activation/focus behavior, and screen coordinates. Host the existing SwiftUI radial content in an app-owned panel. Keep placement and lifecycle in FloatingRadialWindowController; use an AppDelegate only if lifecycle integration requires it.

Use the screen containing the cursor and its visibleFrame, including negative display origins. Clamp the complete panel bounds. Reposition on display changes. Avoid stealing focus on presentation, while allowing key-window behavior when keyboard interaction is requested. Explicitly test Escape delivery and Return. Remove event monitors and release the panel on close.

## Finder integration, Phase 9

No public global drag detector has been established by this plan. Do not infer reliable Finder-wide drag interception from a mouse monitor. Apple's [Finder Sync documentation](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Finder.html) describes synchronization-oriented integration; it is not a general drag-interception contract.

Investigate Services/Quick Actions, Share extensions, a menu bar entry, and an explicitly opened drag-destination panel. Compare file grants, invocation, sandbox behavior, and review suitability. Choose a supported alternative before implementing. Do not request Accessibility permission unless a specific justified design requires it; App Store acceptance remains subject to review.

Related: [product plan](product-plan.md), [conversion](image-conversion.md), [sandbox](sandbox-and-output.md).
