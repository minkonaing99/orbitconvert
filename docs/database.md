# Persistence and database policy

Status: UserDefaults persists watched-folder configuration and bounded activity. No database is needed.

Use @AppStorage/UserDefaults for small preferences as the corresponding features ship: output mode, filename suffix, JPEG quality, preservation options, panel appearance, modifiers, and feedback preferences. Validate loaded values and fall back to documented defaults when invalid.

Watched folders store app-scoped bookmark data and per-folder settings as JSON in UserDefaults. Resolve and renew stale bookmarks; ask for selection when access cannot be restored. Do not treat stored paths as permission grants or log bookmark bytes.

Keep jobs and thumbnails in memory. Watched-folder activity retains the most recent 200 filenames, dates, byte counts, outcomes, and messages in UserDefaults; no file contents or full paths. Other conversion history is not persisted.

No schema migrations, database framework, cloud synchronization, or analytics storage are planned for Phase 1-4.

Related: [sandbox](sandbox-and-output.md), [product plan](product-plan.md).
