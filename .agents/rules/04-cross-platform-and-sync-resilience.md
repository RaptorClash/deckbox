# Rule: Cross-Platform & Sync Resilience

## Scope & Applicability
Applies to all network synchronization, multiplayer protocols, cloud/local backup import/export, and cross-platform compatibility across Windows, Linux, macOS, Android, iOS, and Web.

## Core Directives

### 1. Schema Forward- & Backward-Tolerance
- **Import Handling**:
  - When a client receives a state payload or database export from a newer version of the software, unknown fields or tables must not cause a fatal crash.
  - Dynamically filter fields against known schemas: only locally recognized attributes should be ingested.
  - Unknown fields should be safely ignored or retained in raw form for round-trip preservation.

### 2. Field-Level Patch-Merge (Protection of Remote Data)
- When uploading local state to a shared remote server, cloud store, or peer host:
  - Do not blindly overwrite the entire remote record.
  - Load the remote record, patch only the locally modified and recognized fields, and preserve untouched remote fields created by other platforms or newer clients.

### 3. Cross-Platform Filesystem & Path Normalization
- Never hardcode OS-specific path separators (`\` or `/`).
- Use standard path manipulation utilities (`pathlib.Path`, `os.path.join`, `package:path`).
- Use portable UTF-8 encoding for all files and streams.
- Ensure case sensitivity compatibility for cross-platform filesystems (Linux/macOS vs. Windows).
