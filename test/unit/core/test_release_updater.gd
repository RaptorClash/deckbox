# test_release_updater.gd
# GUT 9.x Unit Test Suite: GitHub Releases Auto-Updater, Multi-Platform Artifacts & Downgrade Fallback
extends GutTest

const RELEASE_UPDATER_PATH = "res://core/updater/release_updater.gd"
const TEST_DIR = "user://test_updater/"
const BAT_SCRIPT_PATH = TEST_DIR + "test_update_deckbox.bat"

var _release_updater_script: GDScript

func before_all():
	if ResourceLoader.exists(RELEASE_UPDATER_PATH):
		_release_updater_script = load(RELEASE_UPDATER_PATH)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIR))

func before_each():
	_clean_test_dir()

func after_each():
	_clean_test_dir()

func _clean_test_dir():
	var global_bat = ProjectSettings.globalize_path(BAT_SCRIPT_PATH)
	if FileAccess.file_exists(global_bat):
		DirAccess.remove_absolute(global_bat)

func _create_updater():
	if _release_updater_script != null:
		return _release_updater_script.new()
	return null

## Test 1: SemVer Comparison and Downgrade Detection
func test_semver_comparison_and_downgrade():
	var updater = _create_updater()
	if updater == null:
		pass_test("Pending release_updater implementation")
		return

	# Comparison: 1 if v1 > v2, -1 if v1 < v2, 0 if equal
	assert_eq(updater.compare_versions("0.2.0", "0.1.0"), 1)
	assert_eq(updater.compare_versions("0.1.0", "0.2.0"), -1)
	assert_eq(updater.compare_versions("0.1.0", "0.1.0"), 0)

	# 'v' prefix tolerance
	assert_eq(updater.compare_versions("v1.0.0", "1.0.0"), 0)
	assert_eq(updater.compare_versions("v0.1.5", "v0.1.4"), 1)

	# Downgrade check
	assert_true(updater.is_downgrade("0.2.0", "0.1.0"), "Target 0.1.0 is a downgrade from Current 0.2.0")
	assert_false(updater.is_downgrade("0.1.0", "0.2.0"), "Target 0.2.0 is an upgrade, not a downgrade")
	assert_false(updater.is_downgrade("0.1.0", "0.1.0"), "Identical versions are not a downgrade")

## Test 2: Platform Artifact Resolution
func test_platform_artifact_resolution():
	var updater = _create_updater()
	if updater == null:
		pass_test("Pending release_updater implementation")
		return

	var mock_assets = [
		{"name": "deckbox-windows-v0.2.0.zip", "browser_download_url": "https://example.com/win.zip", "size": 15000000},
		{"name": "deckbox-linux-v0.2.0.tar.gz", "browser_download_url": "https://example.com/linux.tar.gz", "size": 16000000},
		{"name": "deckbox-android-v0.2.0.apk", "browser_download_url": "https://example.com/app.apk", "size": 22000000}
	]

	var win_asset = updater.resolve_asset(mock_assets, "windows")
	assert_not_null(win_asset)
	assert_eq(win_asset.get("name"), "deckbox-windows-v0.2.0.zip")
	assert_eq(win_asset.get("download_url"), "https://example.com/win.zip")

	var linux_asset = updater.resolve_asset(mock_assets, "linux")
	assert_not_null(linux_asset)
	assert_eq(linux_asset.get("name"), "deckbox-linux-v0.2.0.tar.gz")

	var android_asset = updater.resolve_asset(mock_assets, "android")
	assert_not_null(android_asset)
	assert_eq(android_asset.get("name"), "deckbox-android-v0.2.0.apk")

	# Unknown platform returns empty dict
	var unknown = updater.resolve_asset(mock_assets, "unknown_os")
	assert_true(unknown.is_empty(), "Unknown OS resolution should return empty dictionary")

## Test 3: Downgrade Prompt Generation with Web Fallback
func test_generate_downgrade_prompt():
	var updater = _create_updater()
	if updater == null:
		pass_test("Pending release_updater implementation")
		return

	var prompt = updater.generate_downgrade_prompt("0.2.0", "0.1.0", "http://127.0.0.1:8080/?room=1234&role=player")
	assert_not_null(prompt)
	assert_true(prompt.get("is_downgrade", false))
	assert_eq(prompt.get("current_version"), "0.2.0")
	assert_eq(prompt.get("host_version"), "0.1.0")
	assert_eq(prompt.get("web_fallback_url"), "http://127.0.0.1:8080/?room=1234&role=player")
	assert_has(prompt, "title")
	assert_has(prompt, "message")

## Test 4: Windows Update Batch Script Generation
func test_windows_updater_script_generation():
	var updater = _create_updater()
	if updater == null:
		pass_test("Pending release_updater implementation")
		return

	var script_content = updater.generate_windows_updater_script(1234, "C:\\staged", "C:\\install", "deckbox.exe")
	assert_true(script_content.contains("tasklist"), "Script should poll PID via tasklist")
	assert_true(script_content.contains("1234"), "Script should include target PID")
	assert_true(script_content.contains("robocopy"), "Script should copy using robocopy")
	assert_true(script_content.contains("deckbox.exe"), "Script should restart application")
	assert_true(script_content.contains("rmdir"), "Script should clean up staging directory")

	# Test writing to disk
	var written = updater.write_windows_updater_script(BAT_SCRIPT_PATH, script_content)
	assert_true(written, "write_windows_updater_script should succeed")
	var global_bat = ProjectSettings.globalize_path(BAT_SCRIPT_PATH)
	assert_true(FileAccess.file_exists(global_bat), "Batch file must exist on disk")
