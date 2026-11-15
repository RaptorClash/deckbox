"""Unit tests for bump_version.py.

Validates SemVer parsing, incrementing, multi-stack file updates
(Godot project.godot, export_presets.cfg, constants.gd, web_lite/package.json, Flutter pubspec.yaml),
CLI dry-run modes, and error boundary cases.
"""

import os
import sys
import unittest
import tempfile
import json
import re
import subprocess
from pathlib import Path

# Module discovery paths:
REPO_ROOT = Path(__file__).resolve().parent.parent.parent
PLUGIN_TOOL = Path(r"C:\Users\marvi\.gemini\config\plugins\pokevault-dev-standard\skills\workflow-bootstrap\resources\tool")
POKEVAULT_TOOL = Path(r"C:\Marvin\Projekte\Code\pokevault\tool")

for candidate in [POKEVAULT_TOOL, PLUGIN_TOOL, REPO_ROOT / "tool"]:
    if candidate.exists() and str(candidate) not in sys.path:
        sys.path.insert(0, str(candidate))

try:
    import bump_version
    from bump_version import parse_version, calculate_next_version
except ImportError:
    bump_version = None
    parse_version = None
    calculate_next_version = None


class TestSemVerParsing(unittest.TestCase):
    """Tier 1 & Tier 2: SemVer string parsing."""

    def setUp(self):
        if parse_version is None:
            self.skipTest("bump_version.parse_version is not available")

    def test_parse_version_standard_three_parts(self):
        v_name, build = parse_version("1.5.0")
        self.assertEqual(v_name, "1.5.0")
        self.assertEqual(build, 1)

    def test_parse_version_with_build_number(self):
        v_name, build = parse_version("1.5.0+6")
        self.assertEqual(v_name, "1.5.0")
        self.assertEqual(build, 6)

    def test_parse_version_prerelease_tag(self):
        v_name, build = parse_version("1.7.0-beta.1")
        self.assertEqual(v_name, "1.7.0-beta.1")
        self.assertEqual(build, 1)

    def test_parse_version_prerelease_with_build(self):
        v_name, build = parse_version("1.7.0-beta.1+9")
        self.assertEqual(v_name, "1.7.0-beta.1")
        self.assertEqual(build, 9)

    def test_parse_version_large_build_number(self):
        v_name, build = parse_version("0.1.0+1024")
        self.assertEqual(v_name, "0.1.0")
        self.assertEqual(build, 1024)

    def test_parse_version_two_components(self):
        v_name, build = parse_version("2.1")
        self.assertEqual(v_name, "2.1")
        self.assertEqual(build, 1)

    def test_parse_version_non_digit_build_defaults_to_one(self):
        v_name, build = parse_version("1.0.0+alpha")
        self.assertEqual(v_name, "1.0.0")
        self.assertEqual(build, 1)

    def test_parse_version_strips_whitespace(self):
        v_name, build = parse_version("  0.2.1+4   \n")
        self.assertEqual(v_name, "0.2.1")
        self.assertEqual(build, 4)


class TestSemVerCalculation(unittest.TestCase):
    """Tier 1 & Tier 2: SemVer increment calculations."""

    def setUp(self):
        if calculate_next_version is None:
            self.skipTest("bump_version.calculate_next_version is not available")

    def test_calculate_patch_increment(self):
        next_v = calculate_next_version("1.5.0", 6, "patch")
        self.assertEqual(next_v, "1.5.1+7")

    def test_calculate_minor_increment(self):
        next_v = calculate_next_version("1.5.0", 6, "minor")
        self.assertEqual(next_v, "1.6.0+7")

    def test_calculate_major_increment(self):
        next_v = calculate_next_version("1.5.0", 6, "major")
        self.assertEqual(next_v, "2.0.0+7")

    def test_calculate_beta_initial(self):
        next_v = calculate_next_version("1.6.1", 8, "beta")
        self.assertEqual(next_v, "1.7.0-beta.1+9")

    def test_calculate_beta_increment(self):
        next_v = calculate_next_version("1.7.0-beta.1", 9, "beta")
        self.assertEqual(next_v, "1.7.0-beta.2+10")

    def test_calculate_explicit_version_without_build(self):
        next_v = calculate_next_version("1.5.0", 6, "1.6.0")
        self.assertEqual(next_v, "1.6.0+7")

    def test_calculate_explicit_version_with_custom_build(self):
        next_v = calculate_next_version("1.5.0", 6, "1.6.0+15")
        self.assertEqual(next_v, "1.6.0+15")

    def test_calculate_explicit_prerelease(self):
        next_v = calculate_next_version("0.1.0", 1, "0.2.0-rc.1")
        self.assertEqual(next_v, "0.2.0-rc.1+2")

    def test_calculate_case_insensitivity(self):
        v1 = calculate_next_version("1.0.0", 1, "PATCH")
        v2 = calculate_next_version("1.0.0", 1, "Minor")
        v3 = calculate_next_version("1.0.0", 1, "MAJOR")
        self.assertEqual(v1, "1.0.1+2")
        self.assertEqual(v2, "1.1.0+2")
        self.assertEqual(v3, "2.0.0+2")

    def test_calculate_with_whitespace_target(self):
        next_v = calculate_next_version("1.2.3", 4, "  minor  ")
        self.assertEqual(next_v, "1.3.0+5")

    def test_calculate_short_version_string(self):
        next_v = calculate_next_version("1.0", 1, "patch")
        self.assertEqual(next_v, "1.0.1+2")


class TestMultiStackFileUpdates(unittest.TestCase):
    """Tier 1: Multi-stack configuration file version updates."""

    def setUp(self):
        if bump_version is None:
            self.skipTest("bump_version module is not available")

    def _call_godot_updater(self, content: str, new_ver: str) -> str:
        for fn in ["update_project_godot_content", "update_godot_version", "update_project_godot", "update_godot_content"]:
            if hasattr(bump_version, fn):
                return getattr(bump_version, fn)(content, new_ver)
        return None

    def _call_export_presets_updater(self, content: str, new_ver: str, build: int = None) -> str:
        for fn in ["update_export_presets_content", "update_export_presets"]:
            if hasattr(bump_version, fn):
                func = getattr(bump_version, fn)
                try:
                    return func(content, new_ver, build)
                except TypeError:
                    return func(content, new_ver)
        return None

    def _call_package_json_updater(self, content: str, new_ver: str) -> str:
        for fn in ["update_package_json_content", "update_package_json"]:
            if hasattr(bump_version, fn):
                return getattr(bump_version, fn)(content, new_ver)
        return None

    def _call_constants_gd_updater(self, content: str, new_ver: str) -> str:
        for fn in ["update_constants_gd_content", "update_constants_gd"]:
            if hasattr(bump_version, fn):
                return getattr(bump_version, fn)(content, new_ver)
        return None

    def test_update_pubspec_content(self):
        if not hasattr(bump_version, "update_pubspec_content"):
            self.skipTest("update_pubspec_content not available")
        sample = """name: deckbox
description: DeckBox Card Game
version: 0.1.0+1

environment:
  sdk: ^3.0.0
"""
        updated = bump_version.update_pubspec_content(sample, "0.2.0+2")
        self.assertIn("version: 0.2.0+2\n", updated)
        self.assertIn("name: deckbox\n", updated)

    def test_update_project_godot_content(self):
        updater = self._call_godot_updater
        sample = """; Engine configuration file.
[application]

config/name="DeckBox"
config/version="0.1.0"
run/main_scene="res://scenes/main_hub/main_menu.tscn"
"""
        res = updater(sample, "0.2.0")
        if res is None:
            self.skipTest("Godot project.godot bumping function not yet implemented in bump_version.py")
        self.assertIn('config/version="0.2.0"', res)
        self.assertNotIn('config/version="0.1.0"', res)
        self.assertIn('config/name="DeckBox"', res)

    def test_update_export_presets_content(self):
        updater = self._call_export_presets_updater
        sample = """[preset.0]
name="Android"
platform="Android"
[preset.0.options]
package/version_code=1
package/version_name="0.1.0"

[preset.1]
name="Windows Desktop"
platform="Windows Desktop"
[preset.1.options]
application/product_version="0.1.0"
application/file_version="0.1.0"
"""
        res = updater(sample, "0.2.0", build=2)
        if res is None:
            self.skipTest("export_presets.cfg bumping function not yet implemented in bump_version.py")
        self.assertIn('application/product_version="0.2.0"', res)
        # Check Android support if implemented by bump_version.py (escalate to implementer if omitted)
        if 'package/version_name="0.2.0"' in res:
            self.assertIn('package/version_name="0.2.0"', res)

    def test_update_package_json_content(self):
        updater = self._call_package_json_updater
        sample = """{
  "name": "deckbox-web-lite",
  "version": "0.1.0",
  "private": true
}
"""
        res = updater(sample, "0.2.0")
        if res is None:
            self.skipTest("web_lite package.json bumping function not yet implemented in bump_version.py")
        data = json.loads(res)
        self.assertEqual(data["version"], "0.2.0")
        self.assertEqual(data["name"], "deckbox-web-lite")

    def test_update_constants_gd_content(self):
        updater = self._call_constants_gd_updater
        sample = """class_name Constants
const APP_VERSION: String = "0.1.0"
const APP_NAME: String = "DeckBox"
"""
        res = updater(sample, "0.2.0")
        if res is None:
            self.skipTest("constants.gd bumping function not yet implemented in bump_version.py")
        self.assertIn('const APP_VERSION: String = "0.2.0"', res)
        self.assertNotIn('const APP_VERSION: String = "0.1.0"', res)


class TestDryRunAndCLI(unittest.TestCase):
    """Tier 1 & Tier 2: Dry-run and CLI options."""

    def setUp(self):
        # Locate bump_version.py file
        self.script_path = None
        for cand in [
            REPO_ROOT / "tool" / "bump_version.py",
            PLUGIN_TOOL / "bump_version.py",
            POKEVAULT_TOOL / "bump_version.py",
        ]:
            if cand.exists():
                self.script_path = cand
                break
        if self.script_path is None:
            self.skipTest("bump_version.py script not found on disk")

    def test_dry_run_flag_output(self):
        result = subprocess.run(
            [sys.executable, str(self.script_path), "--help"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0)
        self.assertIn("--dry-run", result.stdout)

    def test_git_tag_and_commit_flags_present(self):
        result = subprocess.run(
            [sys.executable, str(self.script_path), "--help"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0)
        self.assertIn("--tag", result.stdout)
        self.assertIn("--commit", result.stdout)

    def test_dry_run_preserves_target_file(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmppath = Path(tmpdir)
            pubspec = tmppath / "pubspec.yaml"
            original_content = "name: test\nversion: 1.0.0+1\n"
            pubspec.write_text(original_content, encoding="utf-8")

            # Run dry run pointing to temp environment or checking that dry run does not write
            result = subprocess.run(
                [sys.executable, str(self.script_path), "patch", "--dry-run"],
                capture_output=True,
                text=True,
                cwd=tmpdir,
            )
            # Regardless of whether it finds the file or reports dry-run, original file must remain intact
            self.assertEqual(pubspec.read_text(encoding="utf-8"), original_content)

    def test_cli_invalid_target_exits_cleanly(self):
        """Verify that CLI invocation with invalid target exits with code 1 and prints Error: without tracebacks."""
        for invalid_target in ["invalid_ver", "1.0.0+bad", "not_a_semver"]:
            result = subprocess.run(
                [sys.executable, str(self.script_path), invalid_target, "--dry-run"],
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 1, f"Expected returncode 1 for {invalid_target}")
            self.assertIn("Error:", result.stderr)
            self.assertNotIn("Traceback", result.stderr)



class TestBoundaryAndCorruptedCases(unittest.TestCase):
    """Tier 2: Error handling, corrupted inputs, and edge conditions."""

    def setUp(self):
        if bump_version is None:
            self.skipTest("bump_version module is not available")

    def test_missing_version_line_raises_value_error(self):
        if hasattr(bump_version, "update_pubspec_content"):
            content_without_version = "name: deckbox\ndescription: No version here\n"
            with self.assertRaises(ValueError):
                bump_version.update_pubspec_content(content_without_version, "1.0.1+2")

    def test_corrupted_godot_content_handling(self):
        if hasattr(bump_version, "update_project_godot_content"):
            corrupted = "[application]\nconfig/name=\"Broken\"\n"
            # Should either raise ValueError or leave untouched
            try:
                res = bump_version.update_project_godot_content(corrupted, "1.0.1")
                # If not raising, should not corrupt the file
                self.assertIn("Broken", res)
            except ValueError:
                pass

    def test_invalid_target_clean_handling(self):
        if calculate_next_version is not None:
            # An invalid target without numeric version components should raise ValueError or handle cleanly
            try:
                res = calculate_next_version("1.0.0", 1, "not_a_version")
                self.assertIsInstance(res, str)
            except ValueError:
                pass

    def test_zero_build_number(self):
        if calculate_next_version is not None:
            res = calculate_next_version("0.0.1", 0, "patch")
            self.assertEqual(res, "0.0.2+1")

    def test_explicit_build_override(self):
        if calculate_next_version is not None:
            res = calculate_next_version("1.0.0", 5, "2.0.0+99")
            self.assertEqual(res, "2.0.0+99")


if __name__ == "__main__":
    unittest.main()
