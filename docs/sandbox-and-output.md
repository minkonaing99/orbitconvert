# Sandbox and safe output

Status: App Sandbox, read/write user-selected access, and app-scoped bookmarks are configured. Signed sandbox behavior needs manual verification.

## Permission model

Enable `com.apple.security.app-sandbox` and `com.apple.security.files.user-selected.read-write` for conversion. Watched folders use `com.apple.security.files.bookmarks.app-scope` for persistent user-chosen folder access. No broad filesystem, network, automation, or Accessibility permission is needed. Apple documents these in its [sandbox entitlement reference](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html).

Accept URLs from explicit selection or drag/drop. A file grant does not authorize arbitrary sibling creation. For the default same-folder policy, use an existing authorized directory grant or prompt the user to choose that parent folder. If they decline, let them choose another output or cancel. Never silently save somewhere else.

Ask-each-time uses an output picker. Custom-folder mode stores a security-scoped bookmark, not merely a path. Bookmark persistence is described in [database policy](database.md).

## Scoped lifetime

A dedicated service resolves bookmarks, recognizes staleness, and refreshes grants or requests selection again. Start scoped access before inspection/processing and keep it active through final publication. Balance each successful start with one stop on success, failure, and cancellation. A false start is not by itself proof of denied access for URLs already accessible inside the sandbox; handle the actual file operation's error.

Never return a temporary scoped URL and stop its access before an async consumer finishes. Avoid shared mutable counters unless overlapping access actually requires them. Test balanced lifetimes and signed sandbox behavior separately.

## No-overwrite output

1. Validate destination is an authorized existing directory; use URL path APIs, not shell commands.
2. Derive a basename from the source and selected format. Validate any future user suffix so it cannot insert path components.
3. Encode to a unique temporary file in the authorized destination directory.
4. Publish with a filesystem operation whose contract fails if the target exists. A file-existence check followed by an overwriting write is insufficient.
5. On a collision, retry `photo.jpg`, `photo-1.jpg`, `photo-2.jpg`, and so on without changing existing files. Let the filesystem resolve case sensitivity and equivalent names.
6. Remove only the temporary artifact created by this job on failure or cancellation. Preserve every source and pre-existing destination.

Phase 4 creates a private mode-0700 temporary directory with `mkdtemp` inside the destination folder, encodes and validates a file inside it, then calls POSIX `link` to publish without replacing any existing name. The private directory prevents another local user from swapping the in-progress file in a shared folder. If the output name exists, publication retries with a numeric suffix. Concurrent collision tests pass. This method requires a filesystem supporting hard links; a destination that does not support them produces a write error. For same-format conversion, the existing source is itself a collision and remains intact.

Handle full disk, revoked grants, read-only folders, disconnected volumes, disappearing sources, symlink destinations, and destination changes as recoverable failures. Do not follow a symlink to overwrite its target. Return the final URL only after successful publication; reveal it using NSWorkspace when requested.

## Privacy and feedback

No uploads, file execution, unrelated scanning, or raw paths in routine logs. Prefer in-window per-file results. Optional system notifications should be permission-aware and summarize batches instead of flooding the user.

Related: [API contracts](api.md), [tests](testing.md).
