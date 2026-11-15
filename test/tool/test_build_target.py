"""Unit tests for tool/build_target.py.

Validates target filtering (collection vs. uno), main scene switching in project.godot,
export preset adjustments, and CLI dry-run capabilities.
"""

import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
TOOL_DIR = REPO_ROOT / "tool"
if str(TOOL_DIR) not in sys.path:
    sys.path.insert(0, str(TOOL_DIR))

try:
    import build_target
    switch_project_scene = getattr(build_target, "switch_project_scene", None)
    get_target_config = getattr(build_target, "get_target_config", None)
    adjust_export_preset_paths = getattr(build_target, "adjust_export_preset_paths", None)
except ImportError:
    build_target = None
    switch_project_scene = None
    get_target_config = None
    adjust_export_preset_paths = None


class TestBuildTargetDefinitions(unittest.TestCase):
    """Tier 1: Target definitions and configurations."""

    def test_target_definitions_exist(self):
        self.assertIsNotNone(build_target, "build_target module must be importable")
        self.assertTrue(hasattr(build_target, "TARGETS"), "build_target must expose TARGETS dict")
        self.assertIn("collection", build_target.TARGETS)
        self.assertIn("uno", build_target.TARGETS)

    def test_target_collection_properties(self):
        cfg = get_target_config("collection")
        self.assertEqual(cfg["main_scene"], "res://scenes/main_hub/main_menu.tscn")
        self.assertEqual(cfg["app_name"], "DeckBox")

    def test_target_uno_properties(self):
        cfg = get_target_config("uno")
        self.assertEqual(cfg["main_scene"], "res://games/uno/ui/uno_main.tscn")
        self.assertEqual(cfg["app_name"], "DeckBox UNO")

    def test_unknown_target_raises_value_error(self):
        with self.assertRaises(ValueError):
            get_target_config("nonexistent_game")


class TestProjectGodotTargetSwitching(unittest.TestCase):
    """Tier 1 & Tier 2: Updating project.godot main_scene and app name."""

    def test_switch_scene_to_uno(self):
        sample = """; Engine configuration file.
[application]

config/name="DeckBox"
config/version="0.1.0"
run/main_scene="res://scenes/main_hub/main_menu.tscn"
"""
        updated = switch_project_scene(sample, "uno")
        self.assertIn('run/main_scene="res://games/uno/ui/uno_main.tscn"', updated)
        self.assertNotIn('run/main_scene="res://scenes/main_hub/main_menu.tscn"', updated)
        self.assertIn('config/name="DeckBox UNO"', updated)

    def test_switch_scene_to_collection(self):
        sample = """; Engine configuration file.
[application]

config/name="DeckBox UNO"
config/version="0.1.0"
run/main_scene="res://games/uno/ui/uno_main.tscn"
"""
        updated = switch_project_scene(sample, "collection")
        self.assertIn('run/main_scene="res://scenes/main_hub/main_menu.tscn"', updated)
        self.assertNotIn('run/main_scene="res://games/uno/ui/uno_main.tscn"', updated)
        self.assertIn('config/name="DeckBox"', updated)

    def test_switch_scene_when_missing_main_scene(self):
        sample = """[application]
config/name="DeckBox"
"""
        updated = switch_project_scene(sample, "uno")
        self.assertIn('run/main_scene="res://games/uno/ui/uno_main.tscn"', updated)

    def test_switch_scene_preserves_other_sections(self):
        sample = """[application]
config/name="DeckBox"
run/main_scene="res://scenes/main_hub/main_menu.tscn"

[display]
window/size/viewport_width=1280
window/size/viewport_height=720
"""
        updated = switch_project_scene(sample, "uno")
        self.assertIn("[display]", updated)
        self.assertIn("window/size/viewport_width=1280", updated)


class TestExportPresetAdjustment(unittest.TestCase):
    """Tier 1 & Tier 2: Adjust export preset paths."""

    def test_adjust_export_preset_paths_collection(self):
        sample = """[preset.0]
name="Windows Desktop"
platform="Windows Desktop"
export_path="build/windows/DeckBox.exe"

[preset.1]
name="Android"
platform="Android"
export_path="build/android/DeckBox.apk"
"""
        updated = adjust_export_preset_paths(sample, "collection", output_dir="dist")
        self.assertIn('export_path="dist/windows/DeckBox.exe"', updated)
        self.assertIn('export_path="dist/android/DeckBox.apk"', updated)

    def test_adjust_export_preset_paths_uno(self):
        sample = """[preset.0]
name="Windows Desktop"
platform="Windows Desktop"
export_path="build/windows/DeckBox.exe"
"""
        updated = adjust_export_preset_paths(sample, "uno", output_dir="dist")
        self.assertIn('export_path="dist/windows/DeckBox_UNO.exe"', updated)


if __name__ == "__main__":
    unittest.main()
