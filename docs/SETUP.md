# Setup and Testing

## Prerequisites

- macOS with Xcode 27.0 or the current stable Xcode (observed: Xcode 27.0 27A266a, Swift compiler 6.4). Project uses Swift language mode 5.0, deployment target macOS 14.0.
- Apple Silicon Mac. The project builds for x86_64, but Pandoc and Ghostscript helpers are arm64 only; macOS 14 and Intel runtime are unverified.
- For a fresh clone only: Xcode command-line tools, `curl`, `unzip`, `tar`, `gzip`, `make`.
- A signing team for signed sandbox testing (optional for unsigned builds).

## Install

1. Clone the repository.
2. Prepare document helpers (fresh clone only; existing local caches already work). Oxipng is committed; Pandoc and Ghostscript gzip caches are ignored by Git.
3. Open `OrbitConvert.xcodeproj`, select the OrbitConvert scheme and My Mac, then Product > Build.

There is no database, package manager or environment configuration.

### Preparing document helpers

Run from the repository root. Downloads happen only here, never during builds or at runtime.

```sh
repositoryRoot="$PWD"
toolWorkspace="$(mktemp -d "${TMPDIR:-/tmp}/OrbitConvert-setup.XXXXXX")"
cd "$toolWorkspace"

curl --fail --location --output pandoc.zip https://github.com/jgm/pandoc/releases/download/3.12/pandoc-3.12-arm64-macOS.zip
printf '%s  %s\n' f148ca09c9f36594db527a9fc988ad736290ce428f79594c50208cd1ec58b3c0 pandoc.zip | shasum -a 256 -c -
```

Stop if verification does not report `OK`. Then:

```sh
unzip -q pandoc.zip
gzip -n -c pandoc-3.12-arm64/bin/pandoc > "$repositoryRoot/ThirdParty/pandoc/pandoc.gz"

curl --fail --location --output ghostscript.tar.gz https://github.com/ArtifexSoftware/ghostpdl-downloads/releases/download/gs10080/ghostscript-10.08.0.tar.gz
printf '%s  %s\n' caf199e3f233f1290b27d0972d636f66c303355f2353309b7bfddf1edda06b3d ghostscript.tar.gz | shasum -a 256 -c -
```

Stop if verification does not report `OK`. Then build Ghostscript from source:

```sh
tar -xzf ghostscript.tar.gz
cd ghostscript-10.08.0
env PATH=/usr/bin:/bin:/usr/sbin:/sbin MACOSX_DEPLOYMENT_TARGET=14.0 ./configure --without-tesseract --without-libidn --without-libpaper --without-x --disable-fontconfig --disable-cups --disable-dbus --prefix=/tmp/orbitconvert-gs
env PATH=/usr/bin:/bin:/usr/sbin:/sbin make -j4
gzip -n -c bin/gs > "$repositoryRoot/ThirdParty/ghostscript/gs.gz"
cd "$repositoryRoot"
```

If any command fails, stop rather than continuing with partial assets. Xcode builds decompress and sign the helpers inside the app. Remove the temporary workspace after success; keep upstream source if preparing a distribution. A locally rebuilt executable can differ from the recorded hash. Provenance is in [TECH](TECH.md#bundled-helpers).

This setup is for personal builds. It does not establish license compliance for distributing a built app; review GPL/AGPL source and notice obligations first ([GNU license FAQ](https://www.gnu.org/licenses/gpl-faq.en.html), [Ghostscript license](https://ghostscript.com/faq/)).

## Environment variables

None configure the app. `XCTestConfigurationFilePath` (set by Xcode) is checked so test hosts use an isolated UserDefaults suite, skip the clipboard monitor and do not change Dock visibility.

## Run locally

Unsigned command-line build:

```sh
xcodebuild -project OrbitConvert.xcodeproj -scheme OrbitConvert -destination 'platform=macOS' -derivedDataPath /tmp/OrbitConvert-build build CODE_SIGNING_ALLOWED=NO
```

Ad-hoc signed Release build for personal use:

```sh
xcodebuild build -project OrbitConvert.xcodeproj -scheme OrbitConvert \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/OrbitConvert-local \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=
```

The app is at `/tmp/OrbitConvert-local/Build/Products/Release/OrbitConvert.app`. Quit the running copy before opening a new build. This is not a notarized distribution; public downloads need Developer ID signing, notarization, a permanent bundle identifier and privacy documentation.

Unsigned builds do not verify sandbox permissions or distribution readiness.

## Common errors

| Symptom | Fix |
| --- | --- |
| Build fails on missing `pandoc.gz` / `gs.gz` | Run helper preparation above |
| Release tests fail: module not built for testing | Add `ENABLE_TESTABILITY=YES` to Release test runs |
| Compiler macro plugins fail to launch | Run xcodebuild outside a sandboxed shell |
| Quick Action missing in Finder | System Settings > Extensions (Finder / Quick Actions); the app must contain the embedded extension and be registered |
| Dock shows an old icon | Relaunch the app |
| Same-folder save denied in signed app | Expected sandbox behavior; choose the parent or another output folder |
| Hidden `.orbitconvert-backup-*` file in a watched folder | Left by a crash during replacement; inspect the source before deleting |
| Test host exited during a full run | Rerun; one interrupted run occurred in `testMenuCountsAndPausePreserveAcceptedQueue`. Do not count an interrupted run as a pass |

## Testing

### Framework

XCTest in the `OrbitConvertTests` target with the shared OrbitConvert scheme. About 36 test files and 200 tests. Coverage through `-enableCodeCoverage YES` and xcresult bundles.

### Run tests

Debug, unsigned:

```sh
xcodebuild test -project OrbitConvert.xcodeproj -scheme OrbitConvert -destination 'platform=macOS' -derivedDataPath /tmp/OrbitConvert-tests -enableCodeCoverage YES -resultBundlePath /tmp/OrbitConvert-tests.xcresult
```

Release, ad-hoc signed (used for milestone results):

```sh
xcodebuild test -project OrbitConvert.xcodeproj -scheme OrbitConvert -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/OrbitConvert-tests ENABLE_TESTABILITY=YES -enableCodeCoverage YES -resultBundlePath /tmp/OrbitConvert-<run>.xcresult
```

Use a fresh result bundle path for each run. Signed installed-app testing is required for real sandbox verification.

### Coverage target and workflow

- Target: 80%+ of executable application code. Current whole-app coverage is 80.67% (2026-10-11). Never exclude difficult code to reach the target; report scope and result honestly.
- TDD: RED -> GREEN -> REFACTOR for every nontrivial behavior. Docs and config-only changes are exempt.
- Test types: unit and service integration tests (real codecs and bundled helpers), layout snapshot tests (xcresult attachments). No automated E2E; installed-app checks are manual.
- Never claim a build or test passed unless it ran successfully. Report the build command, tests, coverage, manual checks and limitations per milestone.

### Writing tests

- Generate small deterministic fixtures, or commit originals with provenance. `scripts/memory-fixtures.swift` creates large profiling inputs.
- Use temporary directories, never the user's Desktop or Documents.
- Use private named `NSPasteboard`s and isolated UserDefaults suites.
- Lossy assertions use pixel tolerance, not byte equality. Report codec capability skips.
- Mocking: inject focused services or deterministic failure points where needed (clock, filesystem hooks); otherwise exercise real ImageIO, PDFKit and helpers. chmod alone does not prove sandbox denial.

### Memory profiling

`MemoryProfilingTests.testMemoryWorkload` is opt-in and skipped in normal runs. It samples memory while processing three batches of a scenario, then checks that every input completed and sources are unchanged.

1. Generate fixtures in a new directory (default: a unique folder in the per-user temporary directory; existing directories are refused):
   ```sh
   swift scripts/memory-fixtures.swift [/absolute/new/directory]
   ```
   It prints the fixture path: `images24` (12 x 6000x4000 JPEG), `images48` (4 x 8000x6000 JPEG), `pdfs` (3 x 20-page image PDFs).
2. Run the test with the scenario and fixture path. xcodebuild forwards variables prefixed with `TEST_RUNNER_`:
   ```sh
   TEST_RUNNER_ORBIT_MEMORY_SCENARIO=images24 TEST_RUNNER_ORBIT_MEMORY_FIXTURES=/path/printed/above \
   xcodebuild test -project OrbitConvert.xcodeproj -scheme OrbitConvert -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/OrbitConvert-tests ENABLE_TESTABILITY=YES -only-testing:OrbitConvertTests/MemoryProfilingTests -resultBundlePath /tmp/OrbitConvert-memory.xcresult
   ```
   Scenarios: `images24`, `images48` (Balanced optimization), `convert` (`images24` to PNG), `pdfs`, `idle`. The run takes several minutes by design (idle, cooldown and settle phases).
3. The memory CSV is attached to the result bundle as `memory-<scenario>.csv`; phase markers print as `MEMORY_PROFILE` lines.

Only these test variables exist; nothing configures the app itself through the environment.

### Required automated cases

| Area | Evidence |
| --- | --- |
| Detection | Real PNG/JPEG/HEIC/TIFF, misleading extension, unknown TXT, corrupt content, Markdown UTF-8/binary |
| Capability | Only available encoders appear; unavailable HEIC handled |
| Conversion | PNG to JPEG, JPEG to PNG, HEIC to JPEG, PNG to TIFF; reopen and check format/dimensions |
| Fidelity | All EXIF orientations, alpha-to-JPEG, alpha preservation, DPI/profile, metadata policy |
| Input validation | Non-file URL, folder, missing file, bad quality, multi-frame rejection |
| Naming and output safety | Collisions (including concurrent), unchanged sources/destinations, write failure, temp cleanup |
| Errors | Decode/encode/write/permission mapping |
| Concurrency | Sequential batches, cancellation before publication |
| Scoped access | Balanced start/stop on success, error, cancellation |
| PDF | Page count, order, rotation, DPI, annotations, text through extract/merge, corrupt PDF, protected-PDF rejection, navigation retention |
| Watched folders | FSEvents, bookmarks, new-files-only, stability, symlinks, packages, temp names, larger-candidate rejection, changed source, rollback |
| Automation | Condition families, rename tokens, ordered execution and retry, preview-only, collisions, symlink ancestors, Keep Both without reduction, cross-folder suppression, legacy migration and history |
| Clipboard | Type filtering, stale generation, newer copy preserved, SHA loop prevention, alpha/pixels, TIFF/JPEG, cleanup, ignored apps |
| Quick Action | Save modes, collisions, guarded replacement, cancellation, malformed/oversized requests, activation predicate |

### Results history

| Date | Milestone | Tests | Whole-app coverage | Notes |
| --- | --- | --- | --- | --- |
| 2026-10-12 | F2 folder intake (Release, arm64) | 210 run, 209 pass, 1 skipped | 80.13% (7759/9683) | Folder expansion, empty and 500-file notices, dedupe |
| 2026-10-12 | F3 lifetime savings (Release, arm64) | 207 run, 206 pass, 1 skipped | 80.07% (7712/9632) | Persisted total, seeding, manual recording, reset |
| 2026-10-11 | Cleanups (Release, arm64) | 202 run, 201 pass, 1 skipped | 80.26% (7635/9513) | Case-only rename, unsupported-volume message |
| 2026-10-11 | Hardening step 5, source folders (Release, arm64) | 200 run, 199 pass, 1 skipped | 80.33% (7622/9488) | Rename-only change; variance from async render tests |
| 2026-10-11 | Hardening step 4 (Release, arm64) | 200 run, 199 pass, 1 skipped | 80.67% (7654/9488) | Render, dispatch, folder management and clipboard collection tests; target met |
| 2026-10-11 | Hardening step 1 (Release, arm64) | 185 run, 184 pass, 1 skipped | 66.14% (6275/9488) | Trash on Move, atomic Rename, Replace Original warning |
| 2026-10-11 | Hardening baseline (Release, arm64) | 175 run, 174 pass, 1 skipped (opt-in memory test) | 65.94% (6224/9439) | Quick Action extension 29.82% (51/171) |
| 2026-10-11 | Folder automation | 174 pass | 65.94% | Automation core 89.38% (views excluded from that figure) |
| 2026-10-10 | Finder Quick Action | 133 pass | 67.84% | QuickCompressionService 98.90%, QuickActionRequest 92.73% |
| 2026-10-09 | Watched-folder history | 129 pass | 66.01% | |
| 2026-10-09 | Floating-window removal | 121 pass | 67.91% | |
| 2026-10-09 | JPEG target size | 126 pass | 64.33% | Target-size backend 93.39% |
| 2026-10-03 | Resize + Optimize | 115 pass | 59.97% | Resize service 84.97% |
| 2026-10-03 | Document stages 1-2 | 104 pass | 60.60% | Markdown 96.88%, renderer 94.52% |
| 2026-10-01 | Markdown + stronger PDF | 98 pass | 58.86% | New document services 83.65% |
| 2026-10-01 | Clipboard | 87 pass | 62.30% | |
| 2026-09-30 | Oxipng / menu bar | 69 / 73 pass | not measured | |
| 2026-09-30 | Watched folders | 61 pass | 49.36% | |
| 2026-09-29 | Phases 1-4, PDF tools | 1 to 48 pass | 42-55% | |

Two existing main-thread responsiveness warnings (HEIC tests) and an AppIntents metadata build diagnostic remain.

### Manual checks still open

- Installed signed app: source-folder prompt, alternate folder, denial, read-only destination, revoked access.
- Finder Quick Action: single/multiple selection, cold start, each save mode, denied access, originals kept on extension completion.
- Watched folders: add via NSOpenPanel, restart, real downloads/exports, pause/resume, remove/relink, external and cloud volumes, 50 simultaneous files, rule editor interaction, physical cross-volume moves.
- Clipboard: screenshot copy and paste into Preview; browser Copy Image with transparency; Finder file copy outside granted folders; copy image then text during processing; independent pause; ignored apps; Copy All/Save All/Clear; Quit.
- Documents: Markdown PDF/DOCX in Preview and Pages/Word; long tables, fonts; image-heavy PDF with stronger compression; protected PDFs rejected.
- Visual: orientation, color and alpha in Preview; light/dark; keyboard; VoiceOver; menu bar appearance.
- Performance: large images and low disk space with Instruments.
- Platforms: macOS 14 and physical Intel.

Before committing, run a security review.
