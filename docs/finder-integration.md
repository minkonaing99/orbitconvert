# Finder workflow

## Compress with OrbitConvert

Select up to 100 JPEG, PNG, or HEIC/HEIF images in Finder, then right-click and choose **Quick Actions > Compress with OrbitConvert**. The action opens a normal OrbitConvert window showing the selected filenames. If the action is missing, enable it in macOS System Settings under Extensions / Finder / Quick Actions; the exact location varies by macOS version. The application must contain the embedded extension and be registered with macOS.

Choose how to save the results:

- **Keep Both** starts selected and saves a smaller `-optimized` copy next to each original. Existing names receive a numeric suffix.
- **Replace Original** keeps the original filename and replaces it only after the candidate passes validation and is smaller. The button explicitly says **Compress & Replace**. This choice has no user-facing undo or recovery feature.
- **Choose Output Folder** asks for one destination for the whole selection, saving smaller copies without changing the originals.

The last confirmed save choice is remembered. Compression level and removal of hidden file details come from General settings. The JPEG conversion-quality slider does not override compression presets. Every invocation requires pressing Compress; opening a request document never starts compression automatically.

For Keep Both and Replace Original, macOS asks for access to each distinct source folder before any file is changed. Select the displayed original folder. Canceling a picker cancels the batch before writes. Choose Output Folder requests only its selected destination. Results show original/final sizes, saved space and percentage, per-file errors, and Show in Finder. Stop cancels remaining work; completed files remain completed.

## Implementation and safety

`OrbitConvertQuickAction` is a sandboxed native Action extension (`com.apple.services`), not an NSServices menu substitute. Its activation predicate accepts supported image selections only. The extension loads in-place representations and rejects copied representations, creates temporary implicit security-scope bookmarks, and sends a bounded `.orbitcompress` request document to its containing application using NSWorkspace. The app validates the document version, size, bookmark sizes and count; it resolves bookmarks without UI or mounting volumes. No App Group, broad filesystem entitlement, Accessibility permission, or duplicated compressor is added.

The extension returns **all original input items unchanged** on completion. Finder may delete omitted input attachments, so the bridge never returns just its newly created request document or an empty output list. The extension retains its private request document until a later invocation removes requests older than a day; launch completion is not proof that the app has read it. The app does not delete arbitrary inbound request documents.

`QuickCompressionController` retains input access through the dialog and running work, obtains destination grants, and propagates cancellation to the background worker. Separate invocations own separate windows. `QuickCompressionService` reuses ImageOptimizationService, SafeFileReplacementService and FileOutputService. It checks regular-file fingerprints before replacement/publication, rejects symlinks, validates candidates, preserves larger/no-reduction originals, and uses collision-safe copy publication. Transactional replacement uses the existing temporary rollback mechanism internally.

## Main-window drops

Open OrbitConvert from the Dock or menu bar, then drag Finder files into the main window. The empty window has a drop zone; more files can be dropped anywhere after loading. Add Files and Choose Files offer the native picker alternative. `ContentView.onDrop` loads file URLs through NSItemProvider, preserves input order, and reports individual intake errors.

Floating Drop Target and Floating Actions remain removed. Clipboard result cards are independent of this workflow.

## Verification boundary

Automated checks cover save modes, original preservation, collisions, cancellation, request validation, extension activation/configuration, and compact dialog layouts. A build and signature check alone do not prove Finder's live in-place providers, cross-process sandbox grants, or system extension registration. Installed Finder checks remain required for single/multiple selections, app cold start, each save mode, denied folder access and completion without original deletion. See [testing](testing.md) for actual results.

References: Apple [Finder Action extension sample](https://developer.apple.com/documentation/appkit/add-functionality-to-finder-with-action-extensions), [implicit bookmark scope](https://developer.apple.com/documentation/foundation/nsurl/bookmarkcreationoptions/withoutimplicitsecurityscope), and [drag destinations](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/DragandDrop/Concepts/dragdestination.html).

Related: [architecture](architecture.md), [sandbox and output](sandbox-and-output.md), [testing](testing.md).
