# UI/UX Design Brief

OrbitConvert is an original native macOS utility. Do not copy another product's branding, assets, exact visual design or code (including Clop).

## Design goals

Native, minimal, fast, trustworthy, truthful. The UI never invents progress percentages or promises savings it has not measured.

## Target devices

macOS only (14 or later), desktop pointer and keyboard. No breakpoints; fixed and minimum window sizes instead:

| Surface | Size (points) |
| --- | --- |
| Main window | default 760 x 620, minimum 620 x 460 (two selected files must fit) |
| Settings | 590 x 480, tabs General / Clipboard / Watched Folders |
| Recent Activity window | default 460 x 500 |
| MenuBarExtra popup | 350 wide, window style |
| Rules list sheet | 680 x 520 |
| Rule editor sheet | 760 x 620 (field column 160, comparison 150) |
| Preview sheet | 700 x 520 |
| Quick Compression window | 520 x 480 |
| Clipboard result card | 330 x 180, nonactivating, rectangular |

## Color system

Use system semantic colors only; no custom palette.

| Role | Color |
| --- | --- |
| Primary / accent | `Color.accentColor` (system accent); drop-zone highlight stroke 2 pt |
| Neutral | System backgrounds, materials, `.secondary` foreground for captions |
| Error | `.red` caption text (validation, intake issues) |
| Warning | `.orange` (unavailable checks in previews, folder access warnings) |
| Success | Savings text; no custom green |
| App icon | Blue and teal conversion arrows around a white folded document on a blue-gray tile |

All colors must keep accessible contrast in light and dark appearance.

## Typography

System font (SF Pro) through SwiftUI text styles; no custom fonts in the app UI.

| Use | Style |
| --- | --- |
| Empty state title | `.largeTitle` / `.title` |
| Section headings | `.headline` |
| Secondary labels | `.subheadline`, `.callout` |
| Metadata, sizes, messages, validation | `.caption` (most common) |

Markdown PDF exports are separate: serif or sans body, 8-24 pt, headings proportional, monospaced code.

## Spacing

Native SwiftUI layout. Observed scale: 3, 4, 5, 6, 8, 12, 16 point stack spacing; 16, 20, 24 point container padding; 12 pt corner radius for the drop zone. Prefer 4/8/12/16 for new work.

## Component inventory

| Component | File |
| --- | --- |
| Drop zone and compact selectable file rows | `ContentView.swift` |
| Shared action area: Compress button, format picker, Tools menu, collapsed Options | `ConversionControlsView.swift` |
| Resize options sheet | `ResizeOptionsView.swift` |
| Compress to Size sheet | `TargetSizeOptionsView.swift` |
| Settings tabs | `CompressionSettingsView.swift`, `ClipboardSettingsView.swift`, `WatchedFoldersSettingsView.swift` |
| Rules list (enable, duplicate, reorder, Test Rule, Run Now) | `AutomationRulesView.swift` |
| Rule editor (conditions, All/Any, actions, token help, live filename preview, Save/Cancel) | `AutomationRuleEditor.swift`, `AutomationActionEditor.swift` |
| Rule/Run Now preview | `AutomationPreviewView.swift` |
| Menu bar popup, job rows, result rows, activity list | `WatchMenuView.swift` |
| Clipboard result card | `ClipboardResultPanel.swift` |
| Finder Quick Compression dialog (Keep Both / Compress & Replace / Choose Output Folder) | `QuickCompressionView.swift` |

## Interaction patterns

- Native buttons, pickers, toggles, menus and `NSOpenPanel`; keyboard focus works by default.
- One shared action area acts on checked rows; only actions common to every checked file appear.
- Options stay collapsed until needed.
- Progress is indeterminate; labels show truthful phases (checking, compressing, validating/saving) and file counts.
- Destructive choice is explicit: the replace button reads **Compress & Replace**. Rule previews and Run Now require an explicit Run.
- Empty states use `ContentUnavailableView` ("No Activity Yet") or the large drop zone.
- Results show sizes in adaptive units (KB, MB), saved bytes and percentage; failures show a short message.
- Clipboard cards do not auto-dismiss or stack; a newer card replaces the old one.
- No toast notifications; optional system notifications should summarize batches.

## Accessibility

- Target WCAG 2.1 AA equivalent contrast; macOS light/dark and Increase Contrast.
- Full keyboard operation through native controls.
- VoiceOver: accessibility labels on controls and the menu bar status (`accessibilityStatus`); decorative thumbnails are hidden.
- Respect Reduce Motion for any new animation (the app currently has no custom animation).
- VoiceOver, keyboard and installed-app checks are still manual and unverified.

## Icons

SF Symbols for UI (for example `plus`, `folder.badge.gearshape`, `clipboard`, `slider.horizontal.3`, `clock`, `exclamationmark.triangle`). A separate monochrome menu bar symbol reflects watch status.

App icon: original generated artwork, transparent PNGs in `OrbitConvert/Assets.xcassets/AppIcon.appiconset` for 16, 32, 128, 256 and 512 pt at 1x and 2x (the 512 @2x asset is the 1024 px master). Prompt direction: original native macOS converter icon, blue/teal arrows around a white folded document, restrained depth, centered blue-gray tile, transparent exterior, no text or copied branding. Sizes made with `sips`. Raster only; no Icon Composer source. Both build configurations select `AppIcon`. The Dock may show an older icon until relaunch.

## Dark mode

Required. All surfaces use semantic colors and must be checked in light and dark appearance.

## References

- Rule editor follows a user-supplied screenshot's structure (scope, All/Any, action rows, rename tokens, destination picker, enabled toggle, Save/Cancel) in native styling.
- Figma: none.
- Layout snapshots are produced by tests as xcresult attachments.
