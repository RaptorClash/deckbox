#!/usr/bin/env python3
"""
DeckBox Monorepo Build Target Switcher & Export Pipeline
-------------------------------------------------------
Configures Godot 4 project settings (run/main_scene, config/name) and export presets
for building either the full DeckBox Collection Hub or standalone game apps (e.g. DeckBox UNO).

100% Python Standard Library (zero external pip dependencies).
"""

import os
import re
import sys
import shutil
import argparse
import subprocess
from pathlib import Path

TARGETS = {
    "collection": {
        "name": "DeckBox Collection Hub",
        "main_scene": "res://scenes/main_hub/main_menu.tscn",
        "app_name": "DeckBox",
        "default_output_windows": "build/windows/DeckBox.exe",
        "default_output_android": "build/android/DeckBox.apk",
        "export_presets": ["Windows Desktop", "Android"],
    },
    "uno": {
        "name": "DeckBox UNO Standalone",
        "main_scene": "res://games/uno/ui/uno_main.tscn",
        "app_name": "DeckBox UNO",
        "default_output_windows": "build/windows/DeckBox_UNO.exe",
        "default_output_android": "build/android/DeckBox_UNO.apk",
        "export_presets": ["DeckBox UNO Windows", "DeckBox UNO Android"],
    }
}

def get_target_config(target_key: str) -> dict:
    """Returns the target configuration dictionary or raises ValueError if invalid."""
    clean_key = target_key.lower().strip()
    if clean_key not in TARGETS:
        valid_keys = ", ".join(TARGETS.keys())
        raise ValueError(f"Unknown target '{target_key}'. Valid targets are: {valid_keys}")
    return TARGETS[clean_key]

def switch_project_scene(content: str, target_key: str) -> str:
    """Updates run/main_scene and config/name in project.godot content for the target."""
    cfg = get_target_config(target_key)
    main_scene = cfg["main_scene"]
    app_name = cfg["app_name"]

    # 1. Update config/name
    name_pattern = r'(^[ \t]*config/name\s*=\s*)"[^\r\n"]*"'
    if re.search(name_pattern, content, flags=re.MULTILINE):
        content = re.sub(name_pattern, rf'\g<1>"{app_name}"', content, flags=re.MULTILINE)
    elif re.search(r'\[application\]\r?\n', content):
        content = re.sub(
            r'(\[application\](\r?\n))',
            lambda m: f'{m.group(1)}config/name="{app_name}"{m.group(2)}',
            content,
            count=1
        )

    # 2. Update run/main_scene
    scene_pattern = r'(^[ \t]*run/main_scene\s*=\s*)"[^\r\n"]*"'
    if re.search(scene_pattern, content, flags=re.MULTILINE):
        content = re.sub(scene_pattern, rf'\g<1>"{main_scene}"', content, flags=re.MULTILINE)
    elif re.search(r'\[application\]\r?\n', content):
        content = re.sub(
            r'(\[application\](\r?\n))',
            lambda m: f'{m.group(1)}run/main_scene="{main_scene}"{m.group(2)}',
            content,
            count=1
        )
    else:
        nl = "\r\n" if "\r\n" in content else "\n"
        content = f'[application]{nl}config/name="{app_name}"{nl}run/main_scene="{main_scene}"{nl}{nl}' + content

    return content

def adjust_export_preset_paths(content: str, target_key: str, output_dir: str = None) -> str:
    """Adjusts export_path values in export_presets.cfg according to target and optional output_dir."""
    cfg = get_target_config(target_key)
    out_base = output_dir.strip().rstrip("/\\") if output_dir else "build"

    # Replace windows executable path
    win_bin_name = "DeckBox_UNO.exe" if target_key == "uno" else "DeckBox.exe"
    content = re.sub(
        r'(export_path\s*=\s*)"[^"\r\n]*windows/[^"\r\n]*"',
        rf'\g<1>"{out_base}/windows/{win_bin_name}"',
        content
    )

    # Replace android apk path
    apk_bin_name = "DeckBox_UNO.apk" if target_key == "uno" else "DeckBox.apk"
    content = re.sub(
        r'(export_path\s*=\s*)"[^"\r\n]*android/[^"\r\n]*"',
        rf'\g<1>"{out_base}/android/{apk_bin_name}"',
        content
    )

    return content

def apply_target(root_dir: Path, target_key: str, output_dir: str = None, dry_run: bool = False) -> None:
    """Applies target configuration to project.godot and export_presets.cfg."""
    cfg = get_target_config(target_key)
    project_file = root_dir / "project.godot"
    presets_file = root_dir / "export_presets.cfg"

    print(f"[*] Applying build target '{target_key}': {cfg['name']}")
    print(f"    Main Scene: {cfg['main_scene']}")
    print(f"    App Name:   {cfg['app_name']}")

    if project_file.exists():
        original_proj = project_file.read_text(encoding="utf-8")
        updated_proj = switch_project_scene(original_proj, target_key)
        if not dry_run:
            project_file.write_text(updated_proj, encoding="utf-8")
        print(f"    Updated:    {project_file.name}")
    else:
        print(f"    Warning:    {project_file.name} not found in {root_dir}")

    if presets_file.exists():
        original_presets = presets_file.read_text(encoding="utf-8")
        updated_presets = adjust_export_preset_paths(original_presets, target_key, output_dir=output_dir)
        if not dry_run:
            presets_file.write_text(updated_presets, encoding="utf-8")
        print(f"    Updated:    {presets_file.name}")

def main():
    parser = argparse.ArgumentParser(description="DeckBox Monorepo Build Target Switcher")
    parser.add_argument(
        "--target",
        type=str,
        default="collection",
        choices=list(TARGETS.keys()),
        help="Build target: 'collection' (full hub) or 'uno' (standalone reference game)"
    )
    parser.add_argument(
        "--output-dir",
        type=str,
        default=None,
        help="Optional custom output directory for export paths"
    )
    parser.add_argument(
        "--root",
        type=str,
        default=".",
        help="Project root directory (default: current directory)"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show changes without modifying files"
    )
    parser.add_argument(
        "--list-targets",
        action="store_true",
        help="List all supported build targets and exit"
    )
    parser.add_argument(
        "--export",
        type=str,
        default=None,
        help="Export preset name to execute via Godot headless runner"
    )
    parser.add_argument(
        "--godot-bin",
        type=str,
        default=None,
        help="Explicit path to godot / godot_console executable"
    )

    args = parser.parse_args()

    if args.list_targets:
        print("Available Build Targets:")
        for key, info in TARGETS.items():
            print(f"  - {key:12} : {info['name']} (Main: {info['main_scene']})")
        return

    root_path = Path(args.root).resolve()
    apply_target(root_path, args.target, output_dir=args.output_dir, dry_run=args.dry_run)

    if args.export:
        godot_candidates = [
            args.godot_bin,
            r"C:\Users\marvi\AppData\Local\Microsoft\WinGet\Links\godot_console.exe",
            "godot_console",
            "godot"
        ]
        godot_bin = None
        for cand in godot_candidates:
            if cand and (Path(cand).exists() or shutil.which(cand)):
                godot_bin = cand
                break

        if not godot_bin:
            print(f"Error: Godot executable not found for export '{args.export}'")
            sys.exit(1)

        print(f"[*] Executing Godot headless export for preset '{args.export}' using {godot_bin}...")
        cmd = [godot_bin, "--headless", "--export-release", args.export]
        res = subprocess.run(cmd, cwd=root_path)
        sys.exit(res.returncode)

if __name__ == "__main__":
    main()
