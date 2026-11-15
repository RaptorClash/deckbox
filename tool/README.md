# PokéVault Development Tools Suite

A modular suite of automation tools engineered for multi-stack development, release management, and internationalization.

All scripts in this directory are written using **100% Python Standard Library** and require **zero external pip dependencies**.

---

## Tool Inventory

### 1. `bump_version.py` — Multi-Stack SemVer Version Bumper
Automatically increments and synchronizes version numbers across multiple platforms:
- **Godot 4**: Updates `config/version="X.Y.Z"` in `project.godot` and `application/product_version`, `application/version` in `export_presets.cfg`.
- **Flutter**: Updates `version: X.Y.Z+N` in `pubspec.yaml`.
- **Node.js**: Updates `"version": "X.Y.Z"` in `package.json`.
- **Generic**: Updates version strings in any specified file via `--file`.

#### Usage Examples:
```bash
# Preview the next patch release without changing files
python tool/bump_version.py patch --dry-run

# Bump minor version (e.g. 0.1.0 -> 0.2.0)
python tool/bump_version.py minor

# Bump to explicit version and auto-commit + tag
python tool/bump_version.py 1.0.0 --commit --tag

# Target a specific file
python tool/bump_version.py patch --file core/version.txt
```

---

### 2. `extract_release_info.py` — GitHub Actions Release Extractor
Extracts release metadata for GitHub Actions CI/CD workflows:
- Extracts title quotes from the first heading of `RELEASE_NOTES.md` (e.g. `# v0.1.0 — "The Foundation"`).
- Automatically discovers version numbers from `project.godot`, `pubspec.yaml`, or `package.json`.
- Detects pre-release tags (`-beta`, `-rc`, `-alpha`).
- Populates GitHub Actions output parameters via `$GITHUB_OUTPUT`.

#### Usage Examples:
```bash
python tool/extract_release_info.py --notes RELEASE_NOTES.md --github-output $GITHUB_OUTPUT
```

---

### 3. `translate_all.py` — 13-Language Translation Pipeline
Translates UI strings and markdown documentation into 13 supported languages:
- German (`de`), English (`en`), French (`fr`), Spanish (`es`), Italian (`it`), Japanese (`ja`), Korean (`ko`), Simplified Chinese (`zh-Hans`), Traditional Chinese (`zh-Hant`), Portuguese (`pt`), Dutch (`nl`), Polish (`pl`), Russian (`ru`).
- Uses standard Python `urllib` to query free translation endpoints.
- Features ICU/Slang variable protection (`{count, plural, ...}`, `{name}`, newlines).
- Maintains an MD5 cache in `tool/.translation_cache.json` for lightning-fast incremental updates.
- Automatically rewrites relative markdown documentation links to point to localized files.

#### Usage Examples:
```bash
# Preview translation pipeline
python tool/translate_all.py --dry-run

# Translate a specific documentation file
python tool/translate_all.py --doc README.md --source-lang de
```

---

### 4. `translate_release_notes.py` — Collapsible Release Notes Generator
Generates clean, multi-language GitHub release notes:
- Translates draft notes (`RELEASE_NOTES_DRAFT.md`) into all 13 supported languages.
- Folds each language into its own `<details><summary>` dropdown with localized flag icons.
- Fully compatible with in-app updater parsers and markdown viewers.

#### Usage Examples:
```bash
# Preview collapsible release notes
python tool/translate_release_notes.py --dry-run

# Generate RELEASE_NOTES.md from draft
python tool/translate_release_notes.py RELEASE_NOTES_DRAFT.md -o RELEASE_NOTES.md
```

---

## Verification & Testing

Run the automated test suite verifying all tool scripts:
```bash
python -m unittest discover -s test/tool
```
