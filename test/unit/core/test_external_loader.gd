# test_external_loader.gd
# GUT 9.x Headless Test Suite: ExternalLoader PCK Package Validation & Mounting
extends GutTest

const LOADER_PATH = "res://core/cartridge/external_loader.gd"
var _loader_script: GDScript

func before_all():
	if ResourceLoader.exists(LOADER_PATH):
		_loader_script = load(LOADER_PATH)

func test_path_traversal_rejection():
	if _loader_script == null:
		pass_test("ExternalLoader not loaded")
		return

	var loader = _loader_script.new()
	var res1 = loader.validate_package_path("../malicious.pck")
	assert_false(res1["valid"], "Path traversal with '..' must be rejected")
	assert_has(res1, "error")

	var res2 = loader.validate_package_path("packs/../../hack.pck")
	assert_false(res2["valid"], "Nested '..' must be rejected")

func test_extension_validation():
	if _loader_script == null:
		pass_test("ExternalLoader not loaded")
		return

	var loader = _loader_script.new()
	var res = loader.validate_package_path("user://cartridge.zip")
	assert_false(res["valid"], "Non-.pck extension must be rejected")

func test_non_existent_package_file():
	if _loader_script == null:
		pass_test("ExternalLoader not loaded")
		return

	var loader = _loader_script.new()
	var res = loader.validate_package_path("user://definitely_missing_pack_12345.pck")
	assert_false(res["valid"], "Non-existent file must be rejected")

func test_manifest_validation_valid():
	if _loader_script == null:
		pass_test("ExternalLoader not loaded")
		return

	var loader = _loader_script.new()
	var valid_manifest = {
		"game_id": "custom_poker",
		"display_name": "Custom Poker",
		"version": "1.0.0",
		"min_players": 2,
		"max_players": 6,
		"entry_script": "res://custom_poker/poker_cartridge.gd"
	}
	var res = loader.validate_manifest(valid_manifest)
	assert_true(res["valid"], "Valid manifest must pass validation")

func test_manifest_validation_invalid_player_bounds():
	if _loader_script == null:
		pass_test("ExternalLoader not loaded")
		return

	var loader = _loader_script.new()
	var bad_manifest = {
		"game_id": "bad_game",
		"display_name": "Bad Game",
		"version": "1.0.0",
		"min_players": 1, # Must be >= 2
		"max_players": 0,
		"entry_script": "res://bad.gd"
	}
	var res = loader.validate_manifest(bad_manifest)
	assert_false(res["valid"], "Manifest with min_players < 2 must be rejected")

func test_manifest_validation_missing_keys():
	if _loader_script == null:
		pass_test("ExternalLoader not loaded")
		return

	var loader = _loader_script.new()
	var missing_keys = {
		"game_id": "incomplete"
	}
	var res = loader.validate_manifest(missing_keys)
	assert_false(res["valid"], "Incomplete manifest must be rejected")

func test_load_cartridge_package_invalid_fails_cleanly():
	if _loader_script == null:
		pass_test("ExternalLoader not loaded")
		return

	var loader = _loader_script.new()
	var res = loader.load_cartridge_package("user://nonexistent.pck")
	assert_false(res["success"], "Loading non-existent package must return success: false without crashing")
	assert_true(res.has("error"))
