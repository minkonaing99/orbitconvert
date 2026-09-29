# Persistence and database policy

Status: planned. No database is needed or implemented.

Use @AppStorage/UserDefaults for small preferences as the corresponding features ship: output mode, filename suffix, JPEG quality, preservation options, radial appearance, modifiers, and feedback preferences. Validate loaded values and fall back to documented defaults when invalid.

Store user-selected persistent folder access as security-scoped bookmark data in the app container. Resolve and renew stale bookmarks; ask for selection when access cannot be restored. Do not treat stored paths as permission grants or log bookmark bytes.

Keep jobs, thumbnails, and per-file results in memory initially. Do not persist user file lists or image contents for speculative history features. Recent conversions, if later approved, need explicit retention and clear-history behavior.

No schema migrations, database framework, cloud synchronization, or analytics storage are planned for Phase 1-4.

Related: [sandbox](sandbox-and-output.md), [product plan](product-plan.md).
