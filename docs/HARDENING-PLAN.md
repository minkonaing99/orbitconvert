# Hardening Plan

Status: Complete. Steps 0-2 closed, step 3 dropped 2026-10-11. Steps 4-6 done. Hardening complete; next work in FUTURE-FEATURES.md.

Goal: make existing features safe and verified before adding new ones. Order follows risk: data safety first, real-environment verification second, coverage third, cleanup last. The feature freeze lasts until the step 6 direction decision.

Related: [PLAN](PLAN.md) (roadmap and task lists), [TECH](TECH.md) (architecture and security), [SETUP](SETUP.md) (test commands and manual checklist).

## Rules for every step

- TDD: failing test first, smallest change, refactor while green. Docs/config-only work is exempt.
- Run focused tests, then the full Release suite with coverage. Never report a pass that did not run.
- Non-trivial code: code review; fix CRITICAL and HIGH findings.
- Before each commit: security review.
- After each step: update [PLAN](PLAN.md) tasks, [RELEASE-NOTES](RELEASE-NOTES.md) Unreleased and [SETUP](SETUP.md#results-history) results.
- Unverified environments are reported as unverified.

## Step overview

| Step | Goal | Effort | Depends on | Status |
| --- | --- | --- | --- | --- |
| 0 | Freeze and baseline | 0.5 day | - | Done 2026-10-11 |
| 1 | Quick safety fixes | 1 day | 0 | Done 2026-10-11 |
| 2 | Installed signed-app verification | 1-2 days | 1 | Closed 2026-10-11 (owner-reported, not itemized) |
| 3 | Restore Original (Undo) | - | - | Dropped 2026-10-11 (owner decision) |
| 4 | Coverage to 80% | ~1 week | 1 | Done 2026-10-11 (80.67%) |
| 5 | Source structure | 0.5 day | 1 | Done 2026-10-11 |
| 6 | Product direction decision | Decision | - (before any new feature) | Done 2026-10-12 |

```
0 -> 1 -> 2 (done)    3 dropped
4 coverage, 5 structure: any order
6 before any new feature
```

## Step 0: Freeze and baseline

Goal: know the real starting point.

Tasks:

1. Declare a feature freeze in [PLAN](PLAN.md) current status.
2. Run the full Release suite with coverage:
   ```sh
   xcodebuild test -project OrbitConvert.xcodeproj -scheme OrbitConvert -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/OrbitConvert-tests ENABLE_TESTABILITY=YES -enableCodeCoverage YES -resultBundlePath /tmp/OrbitConvert-baseline.xcresult
   ```
3. Export per-file coverage (`xcrun xccov view --report --files-for-target OrbitConvert.app /tmp/OrbitConvert-baseline.xcresult`) and keep the sorted list for step 4.
4. Record test count, failures and whole-app coverage in [SETUP](SETUP.md#results-history). Last documented: 174 tests, 65.94%.
5. Stop tracking the per-user Xcode file: `git rm --cached OrbitConvert.xcodeproj/xcuserdata/aurora.xcuserdatad/xcschemes/xcschememanagement.plist` (already ignored by `**/xcuserdata/`).

Done when: baseline numbers are recorded and the suite result is known (pass or listed failures).

### Step 0 results (2026-10-11)

- Full Release suite (arm64, ad-hoc signed): **175 tests, 0 failures, 1 skipped** (`MemoryProfilingTests.testMemoryWorkload`, opt-in). Result bundle `/tmp/OrbitConvert-baseline.xcresult`.
- Coverage: app **65.94% (6224/9439)**, Quick Action extension 29.82% (51/171). Reaching 80% needs about **1,328 more covered lines** in the app target.
- `xcschememanagement.plist` untracked; no other `xcuserdata` file is tracked.
- Found: `MemoryProfilingTests.swift:13` skip message points to `docs/memory-profiling.md`, which does not exist. Fix in step 1.

Top uncovered files (input for step 4):

| Uncovered lines | File | Coverage |
| ---: | --- | --- |
| 430 | ConversionControlsView.swift | 44.08% (339/769) |
| 322 | WatchMenuView.swift | 35.21% (175/497) |
| 264 | AutomationRulesView.swift | 0.00% (0/264) |
| 192 | ResizeOptionsView.swift | 0.00% (0/192) |
| 179 | AutomationActionEditor.swift | 33.46% (90/269) |
| 167 | ContentView.swift | 60.61% (257/424) |
| 165 | AutomationPreviewView.swift | 0.00% (0/165) |
| 156 | WatchedFoldersController.swift | 77.33% (532/688) |
| 149 | QuickCompressionController.swift | 9.15% (15/164) |
| 149 | ClipboardMonitorService.swift | 45.02% (122/271) |
| 114 | ClipboardSettingsView.swift | 0.00% (0/114) |
| 101 | AutomationRuleEditor.swift | 79.84% (400/501) |
| 92 | ClipboardResultPanel.swift | 0.00% (0/92) |
| 86 | TargetSizeOptionsView.swift | 0.00% (0/86) |
| 79 | QuickCompressionView.swift | 64.73% (145/224) |
| 60 | WatchedFoldersSettingsView.swift | 82.66% (286/346) |
| 56 | ClipboardWriterService.swift | 66.47% (111/167) |
| 42 | FileActionService.swift | 61.47% (67/109) |

Most of the gap is SwiftUI views and controllers, confirming step 4's extract-logic approach.

## Step 1: Quick safety fixes

Goal: close the low-severity findings from the 2026-10-11 security review and reduce the risk of the destructive Replace Original choice.

| # | Change | File | Test |
| --- | --- | --- | --- |
| 1.1 | After a validated Move, send the source to Trash (`FileManager.trashItem`) instead of `removeItem`, so a wrong deletion is recoverable. Keep the existing fingerprint recheck immediately before | `OrbitConvert/Automation/AutomationFileOperations.swift` | Source ends in Trash; changed source between check and removal is kept |
| 1.2 | Reject a copy/move source whose final path component is a symlink (ancestors are already checked) | `OrbitConvert/Automation/AutomationFileOperations.swift` | Symlinked source fails with a clear message; target file untouched |
| 1.3 | Take the output directory as an argument, defaulting to a per-user temporary directory instead of `/tmp/orbit-memory-fixtures` | `scripts/memory-fixtures.swift` | Manual run with and without argument |
| 1.4 | Show a visible warning in the rule editor when a Compress action uses Replace Original ("Replaces the file in place. There is no Undo yet.") | `OrbitConvert/Automation/AutomationActionEditor.swift` | Editor test: warning present for Replace Original, absent for Keep Both |
| 1.5 | Point the `MemoryProfilingTests` skip message at an existing doc (`docs/SETUP.md`) | `OrbitConvertTests/MemoryProfilingTests.swift` | Trivial; no test |

Notes:

- `trashItem` may be unavailable on some volumes (for example network shares). On failure, keep the source and report the retained copy; do not fall back to permanent deletion silently.
- Check sandbox behavior of `trashItem` in step 2.

Done when: each change has a test that failed first, the full suite passes, code review has no CRITICAL/HIGH findings, security review passes.

### Step 1 results (2026-10-11)

- 1.1: Move sends the source to Trash through an injectable `trash` closure (default `FileManager.trashItem`); Trash failure keeps the source and reports the published copy. Decision during implementation: Rename no longer copies and removes; it uses atomic same-folder `renamex_np(RENAME_EXCL)` (inode kept, no Trash entry). Only Move uses Trash.
- 1.2: No change needed. `FileFingerprint.read` uses `lstat` and requires a regular file; `testSymlinkSourceIsRejected` covers it.
- 1.3: Default fixture output is a unique folder in the per-user temporary directory.
- 1.4: `AutomationActionEditor.replacementNote` shows an orange warning for Replace Original; the legacy Move Original to Trash note no longer claims it cannot be undone.
- 1.5: Skip message points to [SETUP memory profiling](SETUP.md#memory-profiling).
- Full Release suite: **185 tests, 0 failures, 1 opt-in skip**; app coverage **66.14% (6275/9488)**.
- Code review: no CRITICAL/HIGH. Open items moved to [PLAN](PLAN.md) backlog: case-only rename on case-insensitive volumes yields a `-1` suffix (pre-existing); check-to-rename window (moves, never deletes); `rename` does not start access on the source URL itself.
- Trash behavior inside the signed sandbox is checked in step 2.

## Step 2: Installed signed-app verification

Goal: prove the app works outside Xcode, under the real sandbox. Bugs found here may change the Undo design, so this precedes step 3.

Setup:

```sh
xcodebuild build -project OrbitConvert.xcodeproj -scheme OrbitConvert \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/OrbitConvert-local \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=
```

Copy the app to `/Applications`, quit any running copy, launch from Finder. Use test folders only, never personal Desktop/Documents data.

Checklist (record Pass / Fail / Not testable with a note for each):

| Area | Checks |
| --- | --- |
| Manual actions | Drop single and multiple files; convert; save beside source; permission prompt; choose another folder; deny; read-only destination |
| Finder Quick Action | Enable in System Settings > Extensions; single and multiple selection; app not running (cold start); Keep Both; Replace Original; Choose Output Folder; deny folder access; originals present after completion |
| Watched folders | Add via picker; restart app; browser download; large file copy; pause/resume; remove/relink; rule with Rename + Move; Run Now preview; Test Rule makes no changes; external volume; 50 files at once |
| Automation safety | Move to Trash (step 1.1) works in sandbox; symlink source rejected; outputs do not trigger another watched folder |
| Clipboard | Screenshot copy and paste into Preview; browser Copy Image with transparency; Finder file copy; copy image then text during processing; ignored app; Copy All / Save All / Clear |
| Documents | Markdown to PDF and DOCX, open in Preview and Pages/Word; local images folder grant; stronger PDF compression on an image-heavy PDF; protected PDF rejected |
| Accessibility | Keyboard-only operation of main window, rule editor, Quick Compression window; VoiceOver labels; light and dark |
| Menu bar | Counts, pause, open/close main window, Settings, Quit |

Output: a dated "Installed-app verification" section in [SETUP](SETUP.md), and one PLAN backlog task per failure, ranked by data-loss risk.

Done when: every row has a recorded result and every failure is tracked.

### Step 2 results (2026-10-11)

- Release build (commit `268ddf1`) installed at `~/Applications/OrbitConvert.app`: universal binary, strict deep signature verification passes, app and extension carry the expected sandbox entitlements, Quick Action registered with PlugInKit from the installed copy.
- A 43-check checklist and fixture folder were prepared. The owner reported that everything works in daily use and chose to close the step without filling in the checklist; the fixtures were deleted.
- **Evidence level: owner-reported, not itemized.** No individual result is recorded for in-sandbox `trashItem` on Move, Finder Quick Action hand-off (cold start, Replace Original, originals kept), read-only destination errors, VoiceOver or keyboard-only use. Treat these as unverified for step 3 design decisions; re-run the high-risk checks (watched-folder Rename and Move, Quick Action Keep Both and Replace Original, read-only destination) before enabling Restore Original by default.

## Step 3: Restore Original (Undo) - dropped

Decision 2026-10-11 (owner): not implemented. Rationale: the cost (about 1-2 weeks, a recovery journal, retained originals, restore UI) outweighs the need. Replace Original already publishes only a validated, smaller file with in-swap rollback, and Keep Both is available wherever the original matters. The planned design (journal schema, state machine, decision table, backup location options) remains in git history (`docs/PLAN.md` stage 1 and this file before this change) if it is ever revisited.

Consequences:

- Replace Original stays without Undo; the rule editor warning from step 1.4 is permanent.
- The itemized installed-app checks in [PLAN](PLAN.md) are no longer gating Undo, but still matter before relying on Replace Original for important folders.

## Step 4: Coverage to 80%

Goal: reach the repository's 80% whole-app line coverage honestly.

1. Sort the step 0 per-file report by uncovered lines; target the top files first.
2. Extract logic mixed into SwiftUI views into small testable types, starting with the rule editor (validation, live filename preview, action ordering) and settings views.
3. Cover controller state in `WatchedFoldersController`, `QuickCompressionController` and `ClipboardMonitorService` with injected dependencies.
4. Add layout snapshot tests only where logic cannot be extracted.

Rules: no files excluded from measurement; no tests that only mirror implementation; coverage must not drop in any commit.

Done when: whole-app coverage is at least 80% in a full Release run, recorded in [SETUP](SETUP.md#results-history).

### Step 4 results (2026-10-11)

App coverage **66.14% -> 80.67% (7654/9488)**; full Release suite **200 tests, 0 failures, 1 opt-in skip**. No production logic changed and no files were excluded.

| Batch | Tests added | Coverage after |
| --- | --- | --- |
| 1 | `ViewRenderingTests`: Compress to Size, Resize (all presets, real image), rules list (legacy and custom), rule preview (matches and unavailable folder), clipboard settings, clipboard result card show/close | 74.54% |
| 2 | `ControlsRenderingTests`: action editor for every action kind and replacement, menu and activity with saved history (paused and empty), action controls for image/PDF/Markdown/mixed selections, Quick Compression window open/close with saved mode | 79.11% |
| 3 | `FileActionServiceTests`: real dispatch for convert, image to PDF, PDF to PNG, page extraction, image and PDF compression | 79.48% |
| 4 | `WatchedFolderManagementTests`: relink, display path, invalid relink target, eligible-file counts | 79.75% |
| 5 | `ClipboardTests.testCollectedResultsCanBeCopiedAgainAndCleared`: collection, Copy All, Clear, collection off | 80.67% |

Render tests (shared helper `RenderTestSupport.swift`) fix the width to the window so text wraps as on screen, then assert the content fits the window height (skipped for scrolling forms), that the render is not blank, and that opening a view never fires save/run callbacks or changes its input. They render in light and dark appearance. A code review found the first version's size check could never fail; it was corrected before commit. They use isolated UserDefaults suites (including `defaultAppStorage` for the action controls), private pasteboards and temporary folders.

Remaining low-coverage areas: `ConversionControlsView` (option panels and running states need interaction), `ContentView` drop import, `QuickCompressionController` compress flow (needs folder pickers), Quick Action extension 29.82% (outside the app target).

## Step 5: Source structure

Goal: make the flat 64-file `OrbitConvert/` folder navigable. No behavior change.

Proposed groups (Xcode groups backed by folders):

| Group | Files |
| --- | --- |
| App | `OrbitConvertApp.swift`, `AppIdentity.swift`, `ContentView.swift`, `ConversionControlsView.swift` |
| Core | Intake, type, output, action, selection, stability, replacement services; `FileAction.swift`, `CompressionModels.swift` |
| Images | Image conversion, optimization, resize, target size, Oxipng |
| PDF | PDF conversion, optimization, validation, navigation, Ghostscript |
| Documents | Markdown conversion, renderer, image resources, `BundledDocumentTool.swift` |
| Watch | Folder watch, watched folder model/controller, auto optimization, menu views |
| Automation | All `Automation*.swift` |
| Clipboard | All `Clipboard*.swift` |
| QuickAction | All `Quick*.swift` |
| Settings | Settings and options views |

Done when: build and full suite pass with only file moves in the diff (`git diff -M` shows renames only).

### Step 5 results (2026-10-11)

- 62 Swift files moved with `git mv` into 10 folders (App 4, Core 11, Images 5, PDF 5, Documents 4, Watch 6, Automation 13, Clipboard 6, QuickAction 4, Settings 4). `MenuStatus.swift` went to Watch and `ClipboardSettingsView.swift` to Clipboard. Diff: 62 renames with no content change, plus one `project.pbxproj` path for `QuickActionRequest.swift`, which the extension target references by path.
- The app target uses an Xcode synced folder group, so no other project edits were needed.
- Full Release suite: 200 tests, 0 failures, 1 opt-in skip; normal Release build and strict deep signature verification pass. App coverage 80.33% in this run (80.67% before); the small difference comes from timing in async render tests, since no code changed.

## Step 6: Product direction

Goal: decide what OrbitConvert is before adding features. This is the owner's decision.

Options:

| Direction | Means | Roadmap impact |
| --- | --- | --- |
| Converter/optimizer | Core is conversion and compression; automation stays limited to current actions | Prioritize palette PNG, HEIC/PNG target size, benchmarks |
| File automation tool | Rules engine is the core; conversion is one action type | Prioritize rule features, scheduling, more conditions; heavier testing burden |
| Personal only vs distributed | Distribution needs license review (GPL/AGPL helpers), Developer ID, notarization, real bundle IDs, Intel helpers | Large non-feature effort before any release |

Output: a "Scope rule" section in [PRD](PRD.md) and a reordered roadmap in [PLAN](PLAN.md).

### Step 6 results (2026-10-12)

Decision: personal use only; both manual converter and folder automation. Recorded as the [PRD scope rule](PRD.md#scope-rule). Next features are in [FUTURE-FEATURES](FUTURE-FEATURES.md); the feature freeze ends.

## Risks

| Risk | Mitigation |
| --- | --- |
| `trashItem` fails on some volumes | Keep source and report; never silently delete permanently |
| Journal durability on power loss | Promise process-crash recovery only; document limits |
| Coverage work turns into mirror tests | Extract real logic; review tests for meaningful assertions |
| Freeze slips under feature pressure | New ideas go to PLAN backlog until the step 6 direction decision |

## Tracking

- [x] Step 0: freeze and baseline
- [x] Step 1: safety fixes 1.1-1.5
- [x] Step 2: installed signed-app verification (owner-reported, not itemized)
- [x] Step 3: dropped (owner decision 2026-10-11)
- [x] Step 4: coverage at 80% (80.67%)
- [x] Step 5: source structure
- [x] Step 6: product direction decision
