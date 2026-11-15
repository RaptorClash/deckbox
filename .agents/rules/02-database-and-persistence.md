# Rule: Database Architecture, Portable Storage & Persistence Safety

## Scope & Applicability
This rule governs all persistent data storage, database engines (SQLite, JSON stores, key-value caches), schema migrations, and serialization layers.

## Core Directives

### 1. Storage Location & Portability (Never Personal Documents)
- Applications must never write persistent application databases into personal user documents directories (e.g. `C:\Users\<user>\Documents`).
- **Development Mode**: Persist data in `<project>/database/` or `<project>/user_data/` (strictly excluded in `.gitignore`).
- **Portable / Release Mode**: Persist data relative to the executable directory or within standard designated application support paths (`AppData`, `XDG_DATA_HOME`, etc.) with fallback if the executable folder is read-only.
- **Migration**: If legacy data is discovered in user documents, migrate using atomic **Copy-Verify-Delete** semantics and clean up the legacy location.

### 2. Idempotent Migrations & Downgrade Resilience
- **No Downgrade Crashes**: Databases must include an `onDowngrade` handler or version check that allows opening older versions safely without dropping tables or corrupting user data.
- **Idempotent Upgrades**: Column additions must verify column existence before issuing `ALTER TABLE ADD COLUMN` (e.g. via `PRAGMA table_info` or schema inspection). Re-upgrading after a downgrade must never crash on duplicate columns.

### 3. Non-Destructive Writes & Atomic Updates
- Never use blind `REPLACE INTO` / overwrite queries on entities that may contain future or extended fields.
- Atomic writes: write new data to temporary files (e.g. `<filename>.tmp`), flush/sync to disk, and atomically rename over the target file, maintaining backup copies (`<filename>.bak`) where critical.

### 4. Indexing & Query Optimization
- Tables with more than 1,000 rows must have explicit indexes for all filtered and sorted columns.
- Queries must be verified using `EXPLAIN QUERY PLAN` to ensure index usage (`USING INDEX`) instead of full table scans (`SCAN TABLE`).
- Enable robust pragmas where supported: `PRAGMA journal_mode = WAL;`, `PRAGMA synchronous = NORMAL;`, `PRAGMA foreign_keys = ON;`.
