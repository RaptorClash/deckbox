# DeckBox v0.1.0 Release Notes — "Foundation Edition"

Welcome to DeckBox 0.1.0! This release establishes the production-grade foundation for the modular 3D card game collection, repository automation, and multi-stack build pipeline.

---

## What's New in v0.1.0

### Monorepo Architecture & Build Pipeline
- **Dual-Target Building**: Dedicated build script `tool/build_target.py` supporting both full collection hub (`--target collection`) and standalone UNO app (`--target uno`).
- **Multi-Stack Version Automation**: Synchronized SemVer updates across Godot (`project.godot`, `export_presets.cfg`), GDScript constants (`core/constants.gd`), and Web client (`web_lite/package.json`).
- **13-Language Localization Engine**: Automated translation tooling (`tool/translate_all.py`, `tool/translate_release_notes.py`) with MD5 hash caching and ICU placeholder safety.

### Godot 4 & Testing Infrastructure
- **Godot 4.7.2 Configuration**: Forward Plus rendering, responsive window settings, and comprehensive export presets for Windows and Android.
- **GUT 9.x Headless Test Runner**: Fully configured GUT framework in `addons/gut/` allowing automated CI validation with zero GUI overhead.
- **PokéVault Development Standard**: Zero-tolerance quality gates, 3-role committee workflows, and direct-in-engine UI development without static mockups.

---

## Verification
- Python Tool Tests: `python -m unittest discover -s test/tool`
- GUT Headless Test Suite: `godot_console --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -gexit`
- Web Client Test Suite: `node --test web_lite/test/*.test.js`
