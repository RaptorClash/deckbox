#!/usr/bin/env python3
"""
PokéVault Multi-Stack Release Information Extractor
---------------------------------------------------
Extracts release metadata (release title, version tag, release notes body)
from RELEASE_NOTES.md and project configuration (Godot project.godot, Flutter pubspec.yaml, Node package.json)
for automated GitHub Releases and CI pipelines.

100% Python Standard Library.
"""

import os
import re
import sys
import json
import argparse
from pathlib import Path

def extract_release_title(content: str, fallback_tag: str = "") -> str:
    """Extracts the release subtitle within quotes in the first heading/line of release notes."""
    if not content:
        return fallback_tag

    lines = [line.strip() for line in content.splitlines() if line.strip()]
    if not lines:
        return fallback_tag

    first_line = lines[0]

    # Look for quotes: "...", '...', “...”, or „...“
    match = re.search(r'["“„\'](.+?)["”„“\']', first_line)
    if match:
        title = match.group(1).strip()
        if title:
            return title

    # Fallback to cleaning the first heading line
    cleaned = re.sub(r'^[#\s*_-]+', '', first_line).strip()
    return cleaned if cleaned else fallback_tag

def get_project_version(root_or_file: str = None) -> str:
    """Extracts version string from project file (Godot, Flutter, Node) or directory."""
    path = Path(root_or_file) if root_or_file else Path.cwd()

    if path.is_file():
        candidates = [path]
    else:
        candidates = [
            path / "project.godot",
            path / "pubspec.yaml",
            path / "package.json",
        ]

    for candidate in candidates:
        if candidate.exists():
            content = candidate.read_text(encoding="utf-8", errors="replace")
            name = candidate.name.lower()
            if name == "project.godot":
                match = re.search(r'^[ \t]*config/version\s*=\s*"([^"]+)"', content, flags=re.MULTILINE)
                if match:
                    return match.group(1).split("+")[0].strip()
            elif name == "pubspec.yaml":
                match = re.search(r'^[ \t]*version:\s*([^\r\n+#]+)', content, flags=re.MULTILINE)
                if match:
                    return match.group(1).strip()
            elif name == "package.json":
                try:
                    data = json.loads(content)
                    if "version" in data:
                        return str(data["version"]).split("+")[0].strip()
                except Exception:
                    pass

    return "1.0.0"

def determine_release_metadata(
    ref_name: str = "",
    input_tag: str = "",
    notes_content: str = "",
    project_version: str = "",
    is_prerelease_input: str = "",
    root_dir: str = None,
) -> dict:
    """Calculates all metadata keys needed for creating a GitHub release."""
    # 1. Determine Tag Name
    tag_name = input_tag.strip() if input_tag else ""
    if not tag_name:
        # If running on a git tag push (e.g. v1.7.0 or v0.1.0)
        if ref_name and ref_name.startswith("v") and ref_name != "main":
            tag_name = ref_name
        else:
            ver = project_version if project_version else get_project_version(root_dir)
            tag_name = f"v{ver}" if not ver.startswith("v") else ver

    # 2. Determine Pre-release flag
    tag_lower = tag_name.lower()
    is_pre = (
        "-beta" in tag_lower
        or "-rc" in tag_lower
        or "-alpha" in tag_lower
        or is_prerelease_input.lower() == "true"
    )

    # 3. Determine Title
    release_title = extract_release_title(notes_content, fallback_tag=tag_name)

    return {
        "tag_name": tag_name,
        "release_title": release_title,
        "is_prerelease": is_pre,
    }

def main():
    parser = argparse.ArgumentParser(description="Extract release information for GitHub Actions")
    parser.add_argument("--notes", default="RELEASE_NOTES.md", help="Path to RELEASE_NOTES.md")
    parser.add_argument("--ref", default=os.environ.get("GITHUB_REF_NAME", ""), help="Git ref name (e.g. main or v1.0.0)")
    parser.add_argument("--tag-input", default="", help="Explicit version tag input from workflow")
    parser.add_argument("--prerelease-input", default="", help="Explicit prerelease boolean input")
    parser.add_argument("--root", default=".", help="Project root directory")
    parser.add_argument("--github-output", default=os.environ.get("GITHUB_OUTPUT", ""), help="Path to $GITHUB_OUTPUT file")
    args = parser.parse_args()

    root_path = Path(args.root).resolve()
    notes_path = root_path / args.notes if not Path(args.notes).is_absolute() else Path(args.notes)
    notes_content = ""
    if notes_path.exists():
        notes_content = notes_path.read_text(encoding="utf-8", errors="replace")

    meta = determine_release_metadata(
        ref_name=args.ref,
        input_tag=args.tag_input,
        notes_content=notes_content,
        is_prerelease_input=args.prerelease_input,
        root_dir=str(root_path),
    )

    print(f"Tag Name:      {meta['tag_name']}")
    print(f"Release Title: {meta['release_title']}")
    print(f"Is PreRelease: {meta['is_prerelease']}")
    print(f"Body Path:     {args.notes}")

    if args.github_output:
        with open(args.github_output, "a", encoding="utf-8") as f:
            f.write(f"tag_name={meta['tag_name']}\n")
            f.write(f"release_title={meta['release_title']}\n")
            f.write(f"is_prerelease={'true' if meta['is_prerelease'] else 'false'}\n")
            f.write(f"body_path={args.notes}\n")

if __name__ == "__main__":
    main()
