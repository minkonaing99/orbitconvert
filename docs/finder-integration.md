# Finder workflow

Open OrbitConvert from the Dock or its menu bar, then drag Finder files into the main window. The empty window has a drop zone; once files are loaded, more files can be dropped anywhere in the main window. Add Files and Choose Files offer the native picker alternative.

`ContentView.onDrop` accepts file URLs through `NSItemProvider`. Loading begins inside the drop callback and preserves the order of dropped files. The existing intake and inspection services validate files and report individual errors without discarding supported items. Main-window controls then offer common actions for the selected files.

Floating Drop Target and Floating Actions have been removed, including their controllers, placement code, event monitors and toolbar menu. No Finder extension, global drag detection, Accessibility permission or new entitlement is introduced. Clipboard result cards are independent of this workflow.

Dropped-file access and the existing output-folder permission prompt still need installed signed-app testing. Check single/multiple Finder drops, unsupported files, selected-file actions and output-folder access in the main window.

Reference: Apple's [drag destination documentation](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/DragandDrop/Concepts/dragdestination.html).

Related: [architecture](architecture.md), [sandbox and output](sandbox-and-output.md), [testing](testing.md).
