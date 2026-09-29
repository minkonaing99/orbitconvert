# Finder workflow feasibility

OrbitConvert uses only documented macOS APIs. No public API supplies both the start of an arbitrary Finder drag and the dragged file URLs to an unrelated app. A global mouse event is not a drag payload. The app must either receive an explicit Finder command or own a visible drop destination.

| Approach | Supported entry point | Fit for drag-to-radial workflow |
| --- | --- | --- |
| [Finder Sync Extension](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Finder.html) | Badges, toolbar and contextual menus for monitored sync folders | Poor. Apple describes it for folder synchronization, not general Finder UI or arbitrary drag interception. |
| [Services](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CocoaKeys.html) and [Quick Actions](https://developer.apple.com/documentation/appkit/add-functionality-to-finder-with-action-extensions) | User invokes a command on selected Finder files; an Action Extension can receive items in an extension context | Strong selection-based alternative, but no drag-start event. An extension target, user enablement, separate sandbox lifecycle, and explicit handoff to the app would add complexity. |
| [Share Extension](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Share.html) | User opens Share and chooses OrbitConvert; attachments arrive through `NSExtensionContext` | Supported, but more steps and no cursor-positioned drag UI. |
| [App-owned drag destination](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/DragandDrop/Concepts/dragdestination.html) | Finder delivers file URLs after user drops onto OrbitConvert's visible window | Best fit. A compact floating drop target can remain visible while Finder is active; after drop, the existing radial panel and converter take over. It cannot materialize when an arbitrary drag starts. |
| [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra) | Persistent menu bar command can open an app window or drop target | Useful launcher later, but the menu bar API does not expose Finder's drag payload. |
| [Global NSEvent monitor](https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents%28matching%3Ahandler%3A%29) | Observes mouse events in other apps; keyboard monitoring has additional permission rules | No drag source or file URL contract. Suitable for dismissing OrbitConvert's visible panel on an outside click, not for detecting Finder drags. |

## Chosen workflow

User opens OrbitConvert's floating drop target from its main window. The target stays above ordinary windows while Finder is active. User drags a file onto that target. OrbitConvert inspects the dropped URL, displays import errors in the main window, and opens the existing radial panel for the first supported image. Selection returns through `ConversionControlsView` to `ImageConversionService`; window code never converts files. Additional dropped files remain in the main window for separate conversion.

The target must be opened before dragging. No Accessibility permission, private Finder hook, global pasteboard polling, Finder Sync extension, or new entitlement is needed. App Store acceptance still requires normal signing and review. Signed sandbox testing must verify dropped-file access and the existing output-folder prompt. The existing drop zone remains available if the floating target is closed.
