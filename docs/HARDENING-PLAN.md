# Hardening Plan

Status: In progress. Step 0 done 2026-10-11.

Goal: make existing features safe and verified before adding new ones. Order follows risk: data safety first, real-environment verification second, coverage third, cleanup last. The feature freeze lasts until step 3 is complete.

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
| 1 | Quick safety fixes | 1 day | 0 | Not started |
| 2 | Installed signed-app verification | 1-2 days | 1 | Not started |
| 3 | Restore Original (Undo) | 1-2 weeks | 2 | Not started |
| 4 | Coverage to 80% | ~1 week | 1 (parallel with 3) | Not started |
| 5 | Source structure | 0.5 day | 1 | Not started |
| 6 | Product direction decision | Decision | - (before any new feature) | Not started |

```
0 -> 1 -> 2 -> 3a -> 3b -> 3c -> 3d
       \-> 4 (parallel with 3)
       \-> 5 (any time after 1)
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
| 1.1 | After a validated Move, send the source to Trash (`FileManager.trashItem`) instead of `removeItem`, so a wrong deletion is recoverable. Keep the existing fingerprint recheck immediately before | `OrbitConvert/AutomationFileOperations.swift` | Source ends in Trash; changed source between check and removal is kept |
| 1.2 | Reject a copy/move source whose final path component is a symlink (ancestors are already checked) | `OrbitConvert/AutomationFileOperations.swift` | Symlinked source fails with a clear message; target file untouched |
| 1.3 | Take the output directory as an argument, defaulting to a per-user temporary directory instead of `/tmp/orbit-memory-fixtures` | `scripts/memory-fixtures.swift` | Manual run with and without argument |
| 1.4 | Show a visible warning in the rule editor when a Compress action uses Replace Original ("Replaces the file in place. There is no Undo yet.") | `OrbitConvert/AutomationActionEditor.swift` | Editor test: warning present for Replace Original, absent for Keep Both |
| 1.5 | Point the `MemoryProfilingTests` skip message at an existing doc (`docs/SETUP.md`) | `OrbitConvertTests/MemoryProfilingTests.swift` | Trivial; no test |

Notes:

- `trashItem` may be unavailable on some volumes (for example network shares). On failure, keep the source and report the retained copy; do not fall back to permanent deletion silently.
- Check sandbox behavior of `trashItem` in step 2.

Done when: each change has a test that failed first, the full suite passes, code review has no CRITICAL/HIGH findings, security review passes.

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

## Step 3: Restore Original (Undo)

Goal: make Replace Original reversible after crashes and mistakes. Full design: [PLAN stage 1](PLAN.md#stage-1-durable-restore-original). Scope: watched-folder and automation Replace Original jobs. Quick Action Replace Original can adopt it after 3d.

Provisional limits: 7 days, 100 entries, 1,000,000,000 bytes of retained originals. If capacity cannot be reserved, skip replacement and keep the original.

### 3a. Recovery journal (no UI, no behavior change)

- New `OrbitConvert/OptimizationRecoveryStore.swift`, `OrbitConvertTests/OptimizationRecoveryTests.swift`.
- One versioned, bounded JSON file per entry in a private Application Support directory; atomic writes; not UserDefaults.
- Fields: UUID, schema version, state, timestamps, folder ID, folder bookmark, volume identity, relative source path, backup and staging names, byte counts, SHA-256 of original and candidate, source and post-swap fingerprints.
- States: `prepared`, `replacing`, `restorable`, `restoring`, `purgePending`, `finished`. Malformed records are quarantined; unknown schema versions block cleanup.
- Inject clock and narrow filesystem failure hooks for tests.

Done when: every state transition and reconciliation decision is unit tested, including corrupt and unknown-version records.

### 3b. Journaled replacement

- `SafeFileReplacementService.swift`, `AutoOptimizationService.swift`, `AutomationExecutionService.swift`.
- Persist `prepared`, then `replacing` before the swap; keep the backup instead of deleting it; verify hashes; persist `restorable` before reporting success.
- If journal completion fails after the swap, roll back while keeping the backup and report Recovery Required.

Done when: injected failures before and after each durable write, swap, validation and cleanup leave either the original or a recoverable backup, never neither.

### 3c. Guarded restore and startup reconciliation

- Reconcile all records before watched folders admit files.
- Restore only if the current file matches the recorded optimized content and identity; otherwise offer Save Recovered Copy to a chosen folder.
- Restore from a staged copy of the backup; never consume the only backup.
- Run restore through the existing sequential queue; suppress re-admission of the restored path.
- Restore does not change savings statistics.

Done when: edited, moved, deleted and symlink-swapped sources all keep every copy and report a conflict.

### 3d. Retention and UI

- Optional recovery ID on `WatchActivity` (backward-compatible decoding).
- Restore Original on eligible rows in `WatchMenuView.swift`; recovery list with retained bytes and expiry in Settings.
- States shown: Restorable, Needs Access, Conflict, Recovery Required, Expired.
- Cleanup at startup and before reserving space; never purge unresolved records.
- Explain that backups keep original metadata that compression may have removed.

Done when: installed-app test kills the app during replace and during restore, relaunches twice, restores byte-identical originals, and nothing is reoptimized. Only then remove the step 1.4 "no Undo" warning and enable by default.

## Step 4: Coverage to 80%

Goal: reach the repository's 80% whole-app line coverage honestly.

1. Sort the step 0 per-file report by uncovered lines; target the top files first.
2. Extract logic mixed into SwiftUI views into small testable types, starting with the rule editor (validation, live filename preview, action ordering) and settings views.
3. Cover controller state in `WatchedFoldersController`, `QuickCompressionController` and `ClipboardMonitorService` with injected dependencies.
4. Add layout snapshot tests only where logic cannot be extracted.

Rules: no files excluded from measurement; no tests that only mirror implementation; coverage must not drop in any commit.

Done when: whole-app coverage is at least 80% in a full Release run, recorded in [SETUP](SETUP.md#results-history).

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

## Step 6: Product direction

Goal: decide what OrbitConvert is before adding features. This is the owner's decision.

Options:

| Direction | Means | Roadmap impact |
| --- | --- | --- |
| Converter/optimizer | Core is conversion and compression; automation stays limited to current actions | Prioritize palette PNG, HEIC/PNG target size, benchmarks |
| File automation tool | Rules engine is the core; conversion is one action type | Prioritize rule features, scheduling, more conditions; heavier testing burden |
| Personal only vs distributed | Distribution needs license review (GPL/AGPL helpers), Developer ID, notarization, real bundle IDs, Intel helpers | Large non-feature effort before any release |

Output: a "Scope rule" section in [PRD](PRD.md) and a reordered roadmap in [PLAN](PLAN.md).

## Risks

| Risk | Mitigation |
| --- | --- |
| Step 2 finds sandbox failures that block step 3 design | Step 2 runs first; adjust 3a-3d before coding |
| `trashItem` fails on some volumes | Keep source and report; never silently delete permanently |
| Journal durability on power loss | Promise process-crash recovery only; document limits |
| Coverage work turns into mirror tests | Extract real logic; review tests for meaningful assertions |
| Freeze slips under feature pressure | New ideas go to PLAN backlog until step 3 is done |

## Tracking

- [x] Step 0: freeze and baseline
- [ ] Step 1: safety fixes 1.1-1.5
- [ ] Step 2: installed signed-app verification
- [ ] Step 3a: recovery journal
- [ ] Step 3b: journaled replacement
- [ ] Step 3c: guarded restore and reconciliation
- [ ] Step 3d: retention and UI
- [ ] Step 4: coverage at 80%
- [ ] Step 5: source structure
- [ ] Step 6: product direction decision
