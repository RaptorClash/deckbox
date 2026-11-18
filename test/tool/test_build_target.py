"""Unit tests for tool/build_target.py.

Validates target filtering (collection vs. uno), main scene switching in project.godot,
export preset adjustments, and CLI dry-run capabilities.
"""

import io
import sys
import unittest
import zipfile
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
    update_editor_settings_android_paths = getattr(build_target, "update_editor_settings_android_paths", None)
    find_zip_entry_range = getattr(build_target, "find_zip_entry_range", None)
    extract_zip_entry_from_local_chunk = getattr(build_target, "extract_zip_entry_from_local_chunk", None)
    get_platform_export_commands = getattr(build_target, "get_platform_export_commands", None)
except ImportError:
    build_target = None
    switch_project_scene = None
    get_target_config = None
    adjust_export_preset_paths = None
    update_editor_settings_android_paths = None
    find_zip_entry_range = None
    extract_zip_entry_from_local_chunk = None
    get_platform_export_commands = None


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

[rendering]
renderer/rendering_method="forward_plus"
"""
        updated = switch_project_scene(sample, "uno")
        self.assertIn("[display]", updated)
        self.assertIn("window/size/viewport_width=1280", updated)
        self.assertIn("[rendering]", updated)
        self.assertIn("textures/vram_compression/import_etc2_astc=true", updated)


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


class TestEditorSettingsAndroidRepair(unittest.TestCase):
    """Tier 1 & Tier 2: Updating stale Java/Android SDK and keystore paths in editor_settings."""

    def test_update_editor_settings_android_paths_replaces_stale(self):
        self.assertIsNotNone(update_editor_settings_android_paths)
        sample = """[gd_resource type="EditorSettings" format=3]

[resource]
_export_preset_advanced_mode = false
export/android/debug_keystore = "C:/old/debug.keystore"
export/android/debug_keystore_pass = "android"
export/android/java_sdk_path = "C:\\\\Program Files\\\\Microsoft\\\\jdk-11.0.31.11-hotspot\\\\"
export/android/android_sdk_path = "C:\\\\Users\\\\old\\\\Android/Sdk"
"""
        updated = update_editor_settings_android_paths(
            sample,
            java_sdk_path=r"C:\Program Files\Microsoft\jdk-17.0.21.21-hotspot",
            android_sdk_path=r"C:\Users\marvi\AppData\Local\Android\Sdk",
            debug_keystore_path=r"C:\Users\marvi\AppData\Roaming\Godot\keystores\debug.keystore",
        )
        self.assertIn('export/android/java_sdk_path = "C:/Program Files/Microsoft/jdk-17.0.21.21-hotspot"', updated)
        self.assertIn('export/android/android_sdk_path = "C:/Users/marvi/AppData/Local/Android/Sdk"', updated)
        self.assertIn('export/android/debug_keystore = "C:/Users/marvi/AppData/Roaming/Godot/keystores/debug.keystore"', updated)
        self.assertNotIn("jdk-11.0.31.11-hotspot", updated)

    def test_update_editor_settings_android_paths_inserts_when_missing(self):
        self.assertIsNotNone(update_editor_settings_android_paths)
        sample = """[gd_resource type="EditorSettings" format=3]

[resource]
interface/editor/appearance/display_scale = 0
"""
        updated = update_editor_settings_android_paths(
            sample,
            java_sdk_path="C:/Java/jdk-17",
            android_sdk_path="C:/Android/Sdk",
            debug_keystore_path="C:/keystores/debug.keystore",
        )
        self.assertIn('export/android/java_sdk_path = "C:/Java/jdk-17"', updated)
        self.assertIn('export/android/android_sdk_path = "C:/Android/Sdk"', updated)
        self.assertIn('export/android/debug_keystore = "C:/keystores/debug.keystore"', updated)
        self.assertIn("interface/editor/appearance/display_scale = 0", updated)


class TestZipRangeParsingAndExtraction(unittest.TestCase):
    """Tier 1 & Tier 2: HTTP Range ZIP Central Directory parsing and entry extraction."""

    def _build_mock_tpz(self) -> bytes:
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w") as zf:
            zf.writestr("templates/other.txt", b"hello world", compress_type=zipfile.ZIP_STORED)
            zf.writestr(
                "templates/android_debug.apk",
                b"PK-MOCK-APK-CONTENT-" * 200,
                compress_type=zipfile.ZIP_DEFLATED,
            )
        return buf.getvalue()

    def test_parse_zip_central_directory_and_extract_deflated(self):
        self.assertIsNotNone(find_zip_entry_range)
        self.assertIsNotNone(extract_zip_entry_from_local_chunk)
        archive = self._build_mock_tpz()
        total_size = len(archive)
        # Simulate reading only the last 2048 bytes (or full archive if smaller)
        tail_size = min(2048, total_size)
        tail_bytes = archive[total_size - tail_size :]

        entry = find_zip_entry_range(tail_bytes, total_size, "templates/android_debug.apk")
        self.assertIsInstance(entry, dict)
        self.assertIn("header_offset", entry)
        self.assertIn("compress_size", entry)
        self.assertIn("file_size", entry)
        self.assertIn("compress_type", entry)
        self.assertEqual(entry["compress_type"], zipfile.ZIP_DEFLATED)

        chunk_start = entry["header_offset"]
        # Read local file header + compressed payload (+ small padding margin as Range would)
        chunk_end = min(total_size, chunk_start + 512 + entry["compress_size"])
        chunk_bytes = archive[chunk_start:chunk_end]
        extracted = extract_zip_entry_from_local_chunk(
            chunk_bytes, entry["compress_size"], entry["compress_type"]
        )
        self.assertEqual(extracted, b"PK-MOCK-APK-CONTENT-" * 200)

    def test_parse_zip_central_directory_and_extract_stored(self):
        self.assertIsNotNone(find_zip_entry_range)
        self.assertIsNotNone(extract_zip_entry_from_local_chunk)
        archive = self._build_mock_tpz()
        total_size = len(archive)
        entry = find_zip_entry_range(archive, total_size, "templates/other.txt")
        self.assertEqual(entry["compress_type"], zipfile.ZIP_STORED)
        chunk = archive[entry["header_offset"] : total_size]
        extracted = extract_zip_entry_from_local_chunk(
            chunk, entry["compress_size"], entry["compress_type"]
        )
        self.assertEqual(extracted, b"hello world")

    def test_missing_zip_entry_raises_key_error(self):
        self.assertIsNotNone(find_zip_entry_range)
        archive = self._build_mock_tpz()
        with self.assertRaises(KeyError):
            find_zip_entry_range(archive, len(archive), "templates/does_not_exist.apk")


class TestPlatformExportCommands(unittest.TestCase):
    """Tier 1: Building Windows & Android export command descriptors."""

    def test_get_platform_export_commands_collection(self):
        self.assertIsNotNone(get_platform_export_commands)
        cmds = get_platform_export_commands(
            godot_bin="godot_console.exe",
            target_key="collection",
            platforms=["windows", "android"],
            release=False,
        )
        self.assertEqual(len(cmds), 2)
        self.assertEqual(cmds[0]["platform"], "windows")
        self.assertEqual(cmds[0]["preset"], "Windows Desktop")
        self.assertEqual(cmds[0]["output_path"], "build/windows/DeckBox.exe")
        self.assertEqual(
            cmds[0]["cmd"],
            ["godot_console.exe", "--headless", "--export-release", "Windows Desktop"],
        )

        self.assertEqual(cmds[1]["platform"], "android")
        self.assertEqual(cmds[1]["preset"], "Android")
        self.assertEqual(cmds[1]["output_path"], "build/android/DeckBox.apk")
        self.assertEqual(
            cmds[1]["cmd"],
            ["godot_console.exe", "--headless", "--export-debug", "Android"],
        )

    def test_get_platform_export_commands_uno_release(self):
        self.assertIsNotNone(get_platform_export_commands)
        cmds = get_platform_export_commands(
            godot_bin="godot",
            target_key="uno",
            platforms=["windows", "android"],
            release=True,
            output_dir="dist",
        )
        self.assertEqual(cmds[0]["preset"], "DeckBox UNO Windows")
        self.assertEqual(cmds[0]["output_path"], "dist/windows/DeckBox_UNO.exe")
        self.assertEqual(
            cmds[1]["cmd"],
            ["godot", "--headless", "--export-release", "DeckBox UNO Android"],
        )
        self.assertEqual(cmds[1]["output_path"], "dist/android/DeckBox_UNO.apk")


if __name__ == "__main__":
    unittest.main()
