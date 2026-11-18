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
import zlib
import struct
import shutil
import tempfile
import argparse
import subprocess
from pathlib import Path

REQUIRED_TEMPLATES = {
    "windows": ["windows_debug_x86_64.exe", "windows_release_x86_64.exe"],
    "android": ["android_debug.apk", "android_release.apk"],
}

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

    # 3. Ensure Android ETC2/ASTC texture compression stays enabled when [rendering] is present
    etc2_pattern = r'^[ \t]*textures/vram_compression/import_etc2_astc\s*=\s*\w+'
    if re.search(etc2_pattern, content, flags=re.MULTILINE):
        content = re.sub(
            etc2_pattern,
            "textures/vram_compression/import_etc2_astc=true",
            content,
            flags=re.MULTILINE,
        )
    elif re.search(r'\[rendering\]\r?\n', content):
        content = re.sub(
            r'(\[rendering\](?:\r?\n)+)',
            lambda m: f"{m.group(1)}textures/vram_compression/import_etc2_astc=true" + ("\r\n" if "\r\n" in m.group(1) else "\n"),
            content,
            count=1,
        )

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


def _normalize_godot_path(raw_path: str) -> str:
    """Normalizes a filesystem path to forward slashes for Godot config files."""
    norm = raw_path.replace("\\", "/")
    if len(norm) > 3 and norm.endswith("/"):
        norm = norm.rstrip("/")
    return norm


def update_editor_settings_android_paths(
    content: str,
    java_sdk_path: str,
    android_sdk_path: str,
    debug_keystore_path: str,
) -> str:
    """Updates Java SDK, Android SDK, and debug keystore paths inside Godot EditorSettings content."""
    replacements = {
        "export/android/java_sdk_path": _normalize_godot_path(java_sdk_path),
        "export/android/android_sdk_path": _normalize_godot_path(android_sdk_path),
        "export/android/debug_keystore": _normalize_godot_path(debug_keystore_path),
    }

    missing_lines = []
    for key, val in replacements.items():
        pattern = rf'(^[ \t]*{re.escape(key)}\s*=\s*)"[^\r\n"]*"'
        if re.search(pattern, content, flags=re.MULTILINE):
            content = re.sub(pattern, rf'\g<1>"{val}"', content, flags=re.MULTILINE)
        else:
            missing_lines.append(f'{key} = "{val}"')

    if missing_lines:
        nl = "\r\n" if "\r\n" in content else "\n"
        block = nl.join(missing_lines)
        if re.search(r"\[resource\]\r?\n", content):
            content = re.sub(
                r"(\[resource\](\r?\n))",
                lambda m: f"{m.group(1)}{block}{m.group(2)}",
                content,
                count=1,
            )
        else:
            content = f"{content.rstrip()}{nl}{block}{nl}"

    return content


def find_zip_entry_range(tail_bytes: bytes, total_size: int, target_filename: str) -> dict:
    """Locates a target entry's byte offset and sizes inside a ZIP tail buffer."""
    eocd_sig = b"PK\x05\x06"
    search_end = len(tail_bytes)
    eocd_pos = -1

    while True:
        idx = tail_bytes.rfind(eocd_sig, 0, search_end)
        if idx == -1:
            break
        if idx + 22 <= len(tail_bytes):
            comment_len = struct.unpack_from("<H", tail_bytes, idx + 20)[0]
            if idx + 22 + comment_len == len(tail_bytes):
                eocd_pos = idx
                break
        search_end = idx

    if eocd_pos == -1:
        raise ValueError("ZIP End of Central Directory (PK\\x05\\x06) not found in tail buffer")

    _, _disk, _cd_disk, _num_disk, total_entries, _cd_size, cd_offset, _comment_len = struct.unpack_from(
        "<4sHHHHIIH", tail_bytes, eocd_pos
    )
    tail_start = total_size - len(tail_bytes)
    cd_rel = cd_offset - tail_start
    if cd_rel < 0:
        raise ValueError(
            f"Central directory offset {cd_offset} precedes tail buffer start {tail_start}"
        )

    pos = cd_rel
    for _ in range(total_entries):
        if pos + 46 > len(tail_bytes) or tail_bytes[pos : pos + 4] != b"PK\x01\x02":
            raise ValueError(f"Invalid ZIP Central Directory header at offset {pos}")
        (
            _sig,
            _ver_made,
            _ver_need,
            _flags,
            compress_type,
            _mod_time,
            _mod_date,
            crc32,
            compress_size,
            file_size,
            name_len,
            extra_len,
            comment_len_e,
            _disk_start,
            _int_attr,
            _ext_attr,
            local_header_offset,
        ) = struct.unpack_from("<4sHHHHHHIIIHHHHHII", tail_bytes, pos)
        name_start = pos + 46
        name_end = name_start + name_len
        fname = tail_bytes[name_start:name_end].decode("utf-8", errors="replace")
        if fname == target_filename:
            return {
                "filename": fname,
                "header_offset": local_header_offset,
                "compress_size": compress_size,
                "file_size": file_size,
                "compress_type": compress_type,
                "crc32": crc32,
            }
        pos = name_end + extra_len + comment_len_e

    raise KeyError(f"Entry '{target_filename}' not found in ZIP central directory")


def extract_zip_entry_from_local_chunk(
    chunk_bytes: bytes, compress_size: int, compress_type: int
) -> bytes:
    """Decompresses a single ZIP entry starting at its local file header."""
    if len(chunk_bytes) < 30 or chunk_bytes[:4] != b"PK\x03\x04":
        raise ValueError("Invalid ZIP local file header signature")
    name_len, extra_len = struct.unpack_from("<HH", chunk_bytes, 26)
    data_start = 30 + name_len + extra_len
    data_end = data_start + compress_size
    if len(chunk_bytes) < data_end:
        raise ValueError(
            f"Incomplete ZIP payload: need {data_end} bytes, got {len(chunk_bytes)}"
        )
    payload = chunk_bytes[data_start:data_end]
    if compress_type == 0:
        return payload
    if compress_type == 8:
        return zlib.decompress(payload, -zlib.MAX_WBITS)
    raise ValueError(f"Unsupported ZIP compression method: {compress_type}")


def get_platform_export_commands(
    godot_bin: str,
    target_key: str,
    platforms: list,
    release: bool = False,
    output_dir: str = None,
) -> list:
    """Builds Godot headless export command descriptors for requested platforms."""
    get_target_config(target_key)
    out_base = output_dir.strip().rstrip("/\\") if output_dir else "build"
    is_uno = target_key.lower().strip() == "uno"

    commands = []
    for plat in platforms:
        p = plat.lower().strip()
        if p == "windows":
            preset = "DeckBox UNO Windows" if is_uno else "Windows Desktop"
            bin_name = "DeckBox_UNO.exe" if is_uno else "DeckBox.exe"
            out_path = f"{out_base}/windows/{bin_name}"
            flag = "--export-release"
        elif p == "android":
            preset = "DeckBox UNO Android" if is_uno else "Android"
            bin_name = "DeckBox_UNO.apk" if is_uno else "DeckBox.apk"
            out_path = f"{out_base}/android/{bin_name}"
            flag = "--export-release" if release else "--export-debug"
        else:
            raise ValueError(f"Unsupported platform '{plat}'. Valid platforms: windows, android")

        commands.append(
            {
                "platform": p,
                "preset": preset,
                "output_path": out_path,
                "cmd": [godot_bin, "--headless", flag, preset],
            }
        )
    return commands


def resolve_godot_bin(explicit_bin: str = None) -> str:
    """Finds a usable Godot console/editor binary on the system."""
    local_app = os.environ.get("LOCALAPPDATA", "")
    candidates = [
        explicit_bin,
        str(Path(local_app) / "Microsoft" / "WinGet" / "Links" / "godot_console.exe") if local_app else None,
        str(Path(local_app) / "Microsoft" / "WinGet" / "Links" / "godot.exe") if local_app else None,
        "godot_console",
        "godot",
    ]
    for cand in candidates:
        if cand and (Path(cand).exists() or shutil.which(cand)):
            return cand
    return None


def _get_godot_version_info(godot_bin: str) -> tuple:
    """Returns (template_dir_name, github_tag) for the given Godot binary."""
    res = subprocess.run([godot_bin, "--version"], capture_output=True, text=True, check=True)
    raw = res.stdout.strip()
    m = re.match(r"^(\d+\.\d+(?:\.\d+)?)\.(stable|rc\d*|beta\d*|alpha\d*|dev)", raw)
    if not m:
        raise RuntimeError(f"Could not parse Godot version from '{raw}'")
    ver, flavor = m.group(1), m.group(2)
    return f"{ver}.{flavor}", f"{ver}-{flavor}", f"Godot_v{ver}-{flavor}_export_templates.tpz"


def _curl_content_length(url: str) -> int:
    """Queries the final Content-Length of a URL via curl.exe following redirects."""
    res = subprocess.run(
        ["curl.exe", "-s", "-I", "-L", url],
        capture_output=True,
        text=True,
        check=True,
    )
    lengths = re.findall(r"^content-length:\s*(\d+)", res.stdout, flags=re.IGNORECASE | re.MULTILINE)
    if not lengths:
        raise RuntimeError(f"Could not determine Content-Length for {url}")
    return int(lengths[-1])


def _curl_range_to_bytes(url: str, start: int, end: int, show_progress: bool = False) -> bytes:
    """Downloads an inclusive HTTP byte range using curl.exe."""
    with tempfile.NamedTemporaryFile(delete=False) as tmp:
        tmp_path = tmp.name
    try:
        cmd = ["curl.exe"]
        cmd.append("-#" if show_progress else "-s")
        cmd.extend(["-f", "-L", "-r", f"{start}-{end}", url, "-o", tmp_path])
        subprocess.run(cmd, check=True)
        return Path(tmp_path).read_bytes()
    finally:
        Path(tmp_path).unlink(missing_ok=True)


def ensure_godot_export_templates(godot_bin: str, platforms: list) -> Path:
    """Ensures required Godot export templates exist locally, downloading only missing slices if needed."""
    template_dirname, release_tag, archive_name = _get_godot_version_info(godot_bin)
    appdata = os.environ.get("APPDATA", "")
    templates_dir = Path(appdata) / "Godot" / "export_templates" / template_dirname
    templates_dir.mkdir(parents=True, exist_ok=True)

    needed = []
    for plat in platforms:
        for fname in REQUIRED_TEMPLATES.get(plat, []):
            target_file = templates_dir / fname
            if not target_file.exists() or target_file.stat().st_size < 1024:
                needed.append(fname)

    if not needed:
        return templates_dir

    url = f"https://github.com/godotengine/godot-builds/releases/download/{release_tag}/{archive_name}"
    print(f"[*] Missing export templates ({', '.join(needed)}). Fetching metadata from GitHub Releases...")
    total_size = _curl_content_length(url)

    tail_size = min(262144, total_size)
    tail_bytes = _curl_range_to_bytes(url, total_size - tail_size, total_size - 1)

    for fname in needed:
        zip_member = f"templates/{fname}"
        entry = find_zip_entry_range(tail_bytes, total_size, zip_member)
        size_mb = entry["compress_size"] / (1024 * 1024)
        print(f"    Downloading {fname} ({size_mb:.1f} MB compressed slice via HTTP Range)...")
        start = entry["header_offset"]
        end = min(total_size - 1, start + 4096 + entry["compress_size"])
        chunk = _curl_range_to_bytes(url, start, end, show_progress=True)
        data = extract_zip_entry_from_local_chunk(
            chunk, entry["compress_size"], entry["compress_type"]
        )
        if len(data) != entry["file_size"]:
            raise RuntimeError(
                f"Extracted size mismatch for {fname}: expected {entry['file_size']}, got {len(data)}"
            )
        dest = templates_dir / fname
        tmp_dest = templates_dir / f".{fname}.tmp"
        tmp_dest.write_bytes(data)
        tmp_dest.replace(dest)
        print(f"    Installed template: {dest}")

    version_txt = templates_dir / "version.txt"
    if not version_txt.exists():
        version_txt.write_text(f"{template_dirname}\n", encoding="utf-8")

    return templates_dir


def _find_jdk_home() -> Path:
    """Locates an installed JDK directory, preferring JDK 17+ in PATH or Program Files."""
    java_exe = shutil.which("java")
    if java_exe:
        cand = Path(java_exe).resolve().parent.parent
        if (cand / "bin" / "keytool.exe").exists():
            return cand

    env_java_home = os.environ.get("JAVA_HOME")
    if env_java_home and (Path(env_java_home) / "bin" / "keytool.exe").exists():
        return Path(env_java_home)

    search_roots = [
        Path(r"C:\Program Files\Microsoft"),
        Path(r"C:\Program Files\Eclipse Adoptium"),
        Path(r"C:\Program Files\Java"),
    ]
    for root in search_roots:
        if not root.exists():
            continue
        jdks = sorted(root.glob("jdk-*"), reverse=True)
        for jdk_dir in jdks:
            if "jdk-17" in jdk_dir.name and (jdk_dir / "bin" / "keytool.exe").exists():
                return jdk_dir
        for jdk_dir in jdks:
            if (jdk_dir / "bin" / "keytool.exe").exists():
                return jdk_dir
    raise RuntimeError("No JDK installation with keytool.exe found. Install Microsoft OpenJDK 17.")


def detect_and_repair_android_env() -> dict:
    """Validates JDK, Android SDK, and debug keystore, repairing Godot EditorSettings if stale."""
    jdk_home = _find_jdk_home()
    local_app = os.environ.get("LOCALAPPDATA", "")
    appdata = os.environ.get("APPDATA", "")

    sdk_candidates = [
        os.environ.get("ANDROID_HOME"),
        os.environ.get("ANDROID_SDK_ROOT"),
        str(Path(local_app) / "Android" / "Sdk") if local_app else None,
    ]
    android_sdk = next((Path(p) for p in sdk_candidates if p and Path(p).exists()), None)
    if not android_sdk:
        raise RuntimeError(
            "Android SDK not found. Expected at %LOCALAPPDATA%\\Android\\Sdk or ANDROID_HOME."
        )

    ks_candidates = [
        Path(appdata) / "Godot" / "keystores" / "debug.keystore",
        Path.home() / ".android" / "debug.keystore",
    ]
    debug_ks = next((p for p in ks_candidates if p.exists()), None)
    if not debug_ks:
        debug_ks = ks_candidates[0]
        debug_ks.parent.mkdir(parents=True, exist_ok=True)
        keytool_bin = jdk_home / "bin" / "keytool.exe"
        print(f"[*] Generating Android debug.keystore at {debug_ks}...")
        subprocess.run(
            [
                str(keytool_bin),
                "-genkey",
                "-v",
                "-keystore",
                str(debug_ks),
                "-alias",
                "androiddebugkey",
                "-storepass",
                "android",
                "-keypass",
                "android",
                "-keyalg",
                "RSA",
                "-keysize",
                "2048",
                "-validity",
                "10000",
                "-dname",
                "CN=Android Debug,O=Android,C=US",
            ],
            check=True,
        )

    godot_cfg_dir = Path(appdata) / "Godot"
    for settings_file in godot_cfg_dir.glob("editor_settings-*.tres"):
        orig = settings_file.read_text(encoding="utf-8")
        updated = update_editor_settings_android_paths(
            orig, str(jdk_home), str(android_sdk), str(debug_ks)
        )
        if updated != orig:
            settings_file.write_text(updated, encoding="utf-8")
            print(f"[*] Updated Android/JDK paths in {settings_file}")

    return {
        "java_sdk_path": str(jdk_home),
        "android_sdk_path": str(android_sdk),
        "debug_keystore": str(debug_ks),
    }


def run_build_all(
    root_path: Path,
    targets: list,
    platforms: list,
    godot_bin: str,
    release: bool = False,
    output_dir: str = None,
) -> int:
    """Runs prerequisites repair, template provisioning, and Godot exports for all requested targets/platforms."""
    if not godot_bin:
        print("Error: Godot executable (godot_console / godot) not found.")
        return 1

    print(f"[*] Using Godot binary: {godot_bin}")
    if "android" in platforms:
        env_info = detect_and_repair_android_env()
        print(f"    Java SDK:    {env_info['java_sdk_path']}")
        print(f"    Android SDK: {env_info['android_sdk_path']}")
        print(f"    Keystore:    {env_info['debug_keystore']}")

    ensure_godot_export_templates(godot_bin, platforms)

    built_artifacts = []
    restore_target = "collection"
    for target_key in targets:
        apply_target(root_path, target_key, output_dir=output_dir, dry_run=False)
        print("[*] Refreshing Godot resource cache (--headless --import)...")
        subprocess.run([godot_bin, "--headless", "--import", "--quit"], cwd=root_path, check=False)

        jobs = get_platform_export_commands(
            godot_bin, target_key, platforms, release=release, output_dir=output_dir
        )
        for job in jobs:
            out_file = (root_path / job["output_path"]).resolve()
            out_file.parent.mkdir(parents=True, exist_ok=True)
            print(f"\n[*] Exporting {target_key} -> {job['platform']} ({job['preset']})...")
            print(f"    Output: {out_file}")
            res = subprocess.run(job["cmd"], cwd=root_path)
            if res.returncode != 0 or not out_file.exists():
                print(f"[!] Export FAILED for {job['preset']} (exit code {res.returncode})")
                return res.returncode or 1
            size_mb = out_file.stat().st_size / (1024 * 1024)
            built_artifacts.append((target_key, job["platform"], out_file, size_mb))

    # Restore default workspace target cleanly when multi-target builds include standalone 'uno'
    if targets[-1] != restore_target:
        apply_target(root_path, restore_target, output_dir=output_dir, dry_run=False)

    print("\n============================================================")
    print(" Build Summary (DeckBox)")
    print("============================================================")
    for target_key, plat, out_file, size_mb in built_artifacts:
        print(f"  [OK] {target_key:10} | {plat:8} | {size_mb:6.1f} MB | {out_file}")
    print("============================================================")
    return 0


def main():
    parser = argparse.ArgumentParser(description="DeckBox Monorepo Build Target Switcher & Exporter")
    parser.add_argument(
        "--target",
        type=str,
        default="collection",
        choices=list(TARGETS.keys()) + ["both"],
        help="Build target: 'collection' (full hub), 'uno' (standalone), or 'both'"
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
        "--build-all",
        action="store_true",
        help="Compile Windows & Android builds automatically (fetching templates & repairing SDK settings if needed)"
    )
    parser.add_argument(
        "--platforms",
        type=str,
        default="windows,android",
        help="Comma-separated platforms for --build-all (default: windows,android)"
    )
    parser.add_argument(
        "--release",
        action="store_true",
        help="Use --export-release for Android as well (requires release keystore configured)"
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

    if args.build_all:
        targets = ["collection", "uno"] if args.target == "both" else [args.target]
        platforms = [p.strip().lower() for p in args.platforms.split(",") if p.strip()]
        godot_bin = resolve_godot_bin(args.godot_bin)
        rc = run_build_all(
            root_path,
            targets=targets,
            platforms=platforms,
            godot_bin=godot_bin,
            release=args.release,
            output_dir=args.output_dir,
        )
        sys.exit(rc)

    if args.target == "both":
        print("Error: --target both requires --build-all")
        sys.exit(1)

    apply_target(root_path, args.target, output_dir=args.output_dir, dry_run=args.dry_run)

    if args.export:
        godot_bin = resolve_godot_bin(args.godot_bin)
        if not godot_bin:
            print(f"Error: Godot executable not found for export '{args.export}'")
            sys.exit(1)

        print(f"[*] Executing Godot headless export for preset '{args.export}' using {godot_bin}...")
        cmd = [godot_bin, "--headless", "--export-release", args.export]
        res = subprocess.run(cmd, cwd=root_path)
        sys.exit(res.returncode)

if __name__ == "__main__":
    main()
