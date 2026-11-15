#!/usr/bin/env python3
"""
PokéVault Multi-Stack Release & Version Bumping Utility
------------------------------------------------------
Automates version updates cleanly across multiple technology stacks:
- Godot 4: project.godot (config/version) and export_presets.cfg (application/product_version, application/version)
- Flutter: pubspec.yaml (version: X.Y.Z+N)
- Node.js: package.json ("version": "X.Y.Z")
- Generic: Configurable files via --file

Supports targets: patch, minor, major, beta, explicit X.Y.Z, or explicit X.Y.Z+N.
100% Python Standard Library (zero external pip dependencies).
"""

import os
import re
import sys
import json
import argparse
import subprocess
from pathlib import Path

def parse_version(version_str: str) -> tuple[str, int]:
    """Parses '1.5.0+6' or '1.5.0' into ('1.5.0', 6).

    If no build number is present, defaults build number to 1.
    """
    cleaned = version_str.strip().strip('"').strip("'")
    if not cleaned:
        raise ValueError("Version string cannot be empty")
    cleaned = re.split(r'\s*#', cleaned)[0].strip()
    if not cleaned:
        raise ValueError("Invalid version string format")
    parts = cleaned.split("+")
    v_name = parts[0].strip()
    if not v_name:
        raise ValueError("Invalid version string format")
    build = int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else 1
    return v_name, build

def calculate_next_version(v_name: str, build: int, target: str) -> str:
    """Calculates the next version string based on target (patch, minor, major, beta, or explicit)."""
    if not target or not target.strip():
        raise ValueError("Target bump cannot be empty")

    target_clean = target.lower().strip()
    next_build = build + 1

    semver_parts = [int(p) for p in re.findall(r'\d+', v_name)]
    while len(semver_parts) < 3:
        semver_parts.append(0)
    major, minor, patch = semver_parts[0], semver_parts[1], semver_parts[2]

    if target_clean == "patch":
        return f"{major}.{minor}.{patch + 1}+{next_build}"
    elif target_clean == "minor":
        return f"{major}.{minor + 1}.0+{next_build}"
    elif target_clean == "major":
        return f"{major + 1}.0.0+{next_build}"
    elif target_clean == "beta":
        beta_match = re.search(r'-beta\.(\d+)', v_name, flags=re.IGNORECASE)
        if beta_match:
            current_beta_num = int(beta_match.group(1))
            base_v = v_name.split('-beta')[0]
            return f"{base_v}-beta.{current_beta_num + 1}+{next_build}"
        else:
            return f"{major}.{minor + 1}.0-beta.1+{next_build}"
    elif "+" in target:
        explicit_parts = target.split("+")
        if not explicit_parts[1].isdigit():
            raise ValueError(f"Build number after '+' must be digits: '{target}'")
        return f"{explicit_parts[0].strip()}+{int(explicit_parts[1])}"
    else:
        # User specified explicit version like '1.6.0' or '0.2.0-rc.1'
        # Validate that it has at least numbers
        if not re.search(r'\d+', target):
            raise ValueError(f"Invalid target version: '{target}'")
        return f"{target.strip()}+{next_build}"

def update_godot_content(content: str, new_version: str) -> str:
    """Replaces or inserts config/version in project.godot content."""
    # Strip build number for Godot version string if desired, or keep as standard
    v_clean = new_version.split("+")[0] if "+" in new_version else new_version
    pattern = r'(^[ \t]*config/version\s*=\s*)"[^\r\n"]*"'
    if re.search(pattern, content, flags=re.MULTILINE):
        return re.sub(pattern, rf'\g<1>"{v_clean}"', content, flags=re.MULTILINE)
    elif re.search(r'\[application\]\r?\n', content):
        return re.sub(
            r'(\[application\](\r?\n))',
            lambda m: f'{m.group(1)}config/version="{v_clean}"{m.group(2)}',
            content,
            count=1
        )
    else:
        nl = "\r\n" if "\r\n" in content else "\n"
        return f'[application]{nl}config/version="{v_clean}"{nl}{nl}' + content

def update_export_presets_content(content: str, new_version: str, build: int = None) -> str:
    """Replaces application/product_version, application/file_version, package/version_name, and package/version_code in export_presets.cfg."""
    v_clean = new_version.split("+")[0] if "+" in new_version else new_version
    
    # Windows Desktop & generic versions
    content = re.sub(r'(application/product_version\s*=\s*)"[^\r\n"]*"', rf'\g<1>"{v_clean}"', content)
    content = re.sub(r'(application/file_version\s*=\s*)"[^\r\n"]*"', rf'\g<1>"{v_clean}"', content)
    content = re.sub(r'(application/version\s*=\s*)"[^\r\n"]*"', rf'\g<1>"{v_clean}"', content)
    
    # Android options: version_name and version_code
    content = re.sub(r'(package/version_name\s*=\s*)"[^\r\n"]*"', rf'\g<1>"{v_clean}"', content)
    if build is not None:
        content = re.sub(r'(package/version_code\s*=\s*)\d+', rf'\g<1>{build}', content)
    elif "+" in new_version:
        b_part = new_version.split("+")[1]
        if b_part.isdigit():
            content = re.sub(r'(package/version_code\s*=\s*)\d+', rf'\g<1>{int(b_part)}', content)
            
    return content

def update_constants_gd_content(content: str, new_version: str) -> str:
    """Replaces APP_VERSION constant in GDScript constants file."""
    v_clean = new_version.split("+")[0] if "+" in new_version else new_version
    pattern = r'(^[ \t]*(?:const|var)\s+APP_VERSION(?:\s*:\s*String)?\s*=\s*)"[^\r\n"]*"'
    if re.search(pattern, content, flags=re.MULTILINE):
        return re.sub(pattern, rf'\g<1>"{v_clean}"', content, flags=re.MULTILINE)
    loose_pattern = r'(APP_VERSION\s*=\s*)"[^\r\n"]*"'
    if re.search(loose_pattern, content):
        return re.sub(loose_pattern, rf'\g<1>"{v_clean}"', content)
    return content

# Function aliases for test runners and compatibility
update_project_godot_content = update_godot_content
update_godot = update_godot_content
update_export_presets = update_export_presets_content
update_constants_gd = update_constants_gd_content

def update_pubspec_content(content: str, new_version: str) -> str:
    """Replaces the version value in pubspec.yaml content while preserving inline comments."""
    pattern = r'(^[ \t]*version:\s*)([^\s#\r\n]+)([^\r\n]*)'
    if not re.search(pattern, content, flags=re.MULTILINE):
        raise ValueError("Could not find 'version: ...' line in pubspec.yaml")
    return re.sub(pattern, rf'\g<1>{new_version}\g<3>', content, flags=re.MULTILINE)

def _is_top_level_json_key(text_before: str) -> bool:
    """Determines if the position right after text_before is at the top-level of a JSON object (depth 1)."""
    depth = 0
    in_string = False
    escape = False
    for char in text_before:
        if escape:
            escape = False
            continue
        if char == '\\' and in_string:
            escape = True
            continue
        if char == '"':
            in_string = not in_string
            continue
        if not in_string:
            if char == '{':
                depth += 1
            elif char == '}':
                depth -= 1
    return depth == 1

def update_package_json_content(content: str, new_version: str) -> str:
    """Replaces top-level "version": "..." in package.json content."""
    v_clean = new_version.split("+")[0] if "+" in new_version else new_version
    pattern = re.compile(r'("version"\s*:\s*)"([^"]+)"')
    for match in pattern.finditer(content):
        if _is_top_level_json_key(content[:match.start()]):
            return content[:match.start()] + match.group(1) + f'"{v_clean}"' + content[match.end():]
    raise ValueError("Could not find '\"version\": ...' in package.json")

update_package_json = update_package_json_content

def get_stack_files(root_dir: Path, stack: str) -> list[Path]:
    """Returns the version files associated with a given stack."""
    if stack == "godot":
        godot_file = root_dir / "project.godot"
        if godot_file.exists():
            files = [godot_file]
            presets = root_dir / "export_presets.cfg"
            if presets.exists():
                files.append(presets)
            constants = root_dir / "core" / "constants.gd"
            if constants.exists():
                files.append(constants)
            web_lite_pkg = root_dir / "web_lite" / "package.json"
            if web_lite_pkg.exists():
                files.append(web_lite_pkg)
            return files
    elif stack == "flutter":
        pubspec_file = root_dir / "pubspec.yaml"
        if pubspec_file.exists():
            return [pubspec_file]
    elif stack == "node":
        package_json = root_dir / "package.json"
        if package_json.exists():
            return [package_json]
    return []

def detect_project_stack(root_dir: Path) -> tuple[str, list[Path]]:
    """Detects the project stack and relevant version files based on root directory files."""
    for s in ["godot", "flutter", "node"]:
        files = get_stack_files(root_dir, s)
        if files:
            return s, files

    return "generic", []

def get_current_version_from_file(path: Path) -> str:
    """Extracts current version string from a supported file type."""
    if not path.exists():
        raise FileNotFoundError(f"Version file not found: {path}")

    content = path.read_text(encoding="utf-8", errors="replace")
    name = path.name.lower()

    if name == "project.godot":
        match = re.search(r'^[ \t]*config/version\s*=\s*"([^"]+)"', content, flags=re.MULTILINE)
        if match:
            return match.group(1).strip()
        return "0.1.0"

    if name == "pubspec.yaml":
        match = re.search(r'^[ \t]*version:\s*([^\r\n#]+)', content, flags=re.MULTILINE)
        if match:
            return match.group(1).strip()
        raise ValueError(f"No version line found in {path}")

    if name == "package.json":
        data = json.loads(content)
        if "version" in data:
            return str(data["version"]).strip()
        raise ValueError(f"No 'version' field found in {path}")

    # Generic regex search
    match = re.search(r'(?:version["\']?\s*[:=]\s*["\']?)([\d\w\.\+-]+)', content, re.IGNORECASE)
    if match:
        return match.group(1).strip()

    return "1.0.0"

def apply_version_to_file(path: Path, new_version: str, dry_run: bool = False) -> str:
    """Updates the specified file with new_version and returns the updated text."""
    if not path.exists():
        raise FileNotFoundError(f"File not found: {path}")

    content = path.read_text(encoding="utf-8", errors="replace")
    name = path.name.lower()

    if name == "project.godot":
        updated = update_godot_content(content, new_version)
    elif name == "export_presets.cfg":
        build_val = None
        if "+" in new_version:
            b_part = new_version.split("+")[1]
            if b_part.isdigit():
                build_val = int(b_part)
        updated = update_export_presets_content(content, new_version, build=build_val)
    elif name == "constants.gd":
        updated = update_constants_gd_content(content, new_version)
    elif name == "pubspec.yaml":
        updated = update_pubspec_content(content, new_version)
    elif name == "package.json":
        updated = update_package_json_content(content, new_version)
    else:
        # Generic update: replace previous version occurrence
        curr = get_current_version_from_file(path)
        v_clean = new_version.split("+")[0] if "+" in new_version else new_version
        updated = content.replace(curr, v_clean)

    if not dry_run:
        path.write_text(updated, encoding="utf-8")

    return updated

def main():
    parser = argparse.ArgumentParser(description="PokéVault Multi-Stack Release Version Bumper")
    parser.add_argument(
        "target",
        nargs="?",
        default=None,
        help="Target bump: 'patch', 'minor', 'major', 'beta', or specific version (e.g. '1.6.0' or '1.6.0+7')"
    )
    parser.add_argument(
        "--file",
        type=str,
        default=None,
        help="Explicit version file to bump (overrides auto-detection)"
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
        help="Simulate the version change without modifying files"
    )
    parser.add_argument(
        "--build",
        type=int,
        default=None,
        help="Explicit build number (override default auto-increment)"
    )
    parser.add_argument(
        "--stack",
        type=str,
        choices=["godot", "flutter", "node", "generic"],
        default=None,
        help="Explicit stack override"
    )
    parser.add_argument(
        "--commit",
        action="store_true",
        help="Automatically create a git commit after updating version"
    )
    parser.add_argument(
        "--tag",
        action="store_true",
        help="Automatically create an annotated git tag after updating version"
    )

    args = parser.parse_args()
    root_path = Path(args.root).resolve()

    if args.file:
        target_files = [Path(args.file).resolve()]
        stack = args.stack or "generic"
    elif args.stack:
        stack = args.stack
        target_files = get_stack_files(root_path, stack)
        if not target_files:
            detected_stack, detected_files = detect_project_stack(root_path)
            target_files = detected_files
    else:
        detected_stack, detected_files = detect_project_stack(root_path)
        stack = detected_stack
        target_files = detected_files

    if not target_files:
        print(f"Error: No version files detected in '{root_path}'. Specify with --file.")
        sys.exit(1)

    primary_file = target_files[0]
    current_ver = get_current_version_from_file(primary_file)
    v_name, build = parse_version(current_ver)

    if not args.target:
        print("=" * 60)
        print("  PokéVault Multi-Stack Version Bumper")
        print("=" * 60)
        print(f"Detected Stack: {stack}")
        print(f"Primary Version File: {primary_file}")
        print(f"Current Version: {current_ver} (Name: {v_name}, Build: {build})\n")
        print("Available bump options for next release:")
        print(f"  • patch:    {calculate_next_version(v_name, build, 'patch')}")
        print(f"  • minor:    {calculate_next_version(v_name, build, 'minor')}")
        print(f"  • major:    {calculate_next_version(v_name, build, 'major')}")
        print(f"  • beta:     {calculate_next_version(v_name, build, 'beta')}")
        print("  • explicit: e.g. python tool/bump_version.py 0.2.0")
        print("\nExamples:")
        print("  python tool/bump_version.py patch --dry-run")
        print("  python tool/bump_version.py 0.2.0")
        print("  python tool/bump_version.py minor --commit --tag")
        return

    new_ver = calculate_next_version(v_name, build, args.target)
    new_v_name, new_build = parse_version(new_ver)
    if args.build is not None:
        new_build = args.build
        new_ver = f"{new_v_name}+{new_build}"

    # For Godot / Node, clean version string without build number is typically preferred unless specified
    effective_ver_for_file = new_ver if stack == "flutter" else new_v_name

    print(f"Bumping Version ({stack}): {current_ver} -> {new_ver} (Files: {[f.name for f in target_files]})")

    if args.dry_run:
        print("[DRY-RUN] Files that would be updated:")
        for f in target_files:
            print(f"  - {f}")
        print("Proposed Git commands:")
        print(f'  git commit -am "chore(release): bump version to {new_ver}"')
        print(f'  git tag -a v{new_v_name} -m "Release v{new_v_name}"')
        return

    # Update all relevant files
    for f in target_files:
        apply_version_to_file(f, new_ver, dry_run=False)
        print(f"Successfully updated: {f}")

    commit_msg = f"chore(release): bump version to {new_ver}"
    tag_name = f"v{new_v_name}"

    if args.commit:
        try:
            for f in target_files:
                subprocess.run(["git", "add", str(f)], check=True)
            subprocess.run(["git", "commit", "-m", commit_msg], check=True)
            print(f"Git commit created: '{commit_msg}'")
        except subprocess.CalledProcessError as e:
            print(f"Error during git commit: {e}", file=sys.stderr)
            sys.exit(1)

    if args.tag:
        try:
            subprocess.run(["git", "tag", "-a", tag_name, "-m", f"Release {tag_name}"], check=True)
            print(f"Git tag created: '{tag_name}'")
        except subprocess.CalledProcessError as e:
            print(f"Error during git tag creation: {e}", file=sys.stderr)
            sys.exit(1)

    if not args.commit:
        print("\nRecommended next Git steps:")
        print(f'  git commit -am "{commit_msg}"')
        if not args.tag:
            print(f'  git tag -a {tag_name} -m "Release {tag_name}"')

if __name__ == "__main__":
    main()
