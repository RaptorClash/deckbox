# test_card_pack_manager.gd
# GUT 9.x Headless Test Suite: CardPackManager ZIP Export/Import, SHA-256 Caching & Asset Extraction
extends GutTest

const MANAGER_PATH = "res://core/packs/card_pack_manager.gd"
var _manager_script: GDScript

func before_all():
	if ResourceLoader.exists(MANAGER_PATH):
		_manager_script = load(MANAGER_PATH)

func test_export_and_import_cycle():
	if _manager_script == null:
		pass_test("Manager script not loaded")
		return

	var mgr = _manager_script.new()
	var pack_data = {
		"schema_version": 1,
		"id": "bundle_pack_01",
		"name": "Bundle Pack",
		"author": "Tester",
		"version": "1.0.0",
		"assets": {
			"card_back": "backs/back_test.png"
		},
		"custom_cards": [
			{
				"id": "burst_card",
				"name": "Burst",
				"color": "yellow",
				"count": 2,
				"actions": [{ "type": "draw_cards", "count": 2, "target": "all_opponents" }]
			}
		]
	}

	var dummy_back_bytes = "DUMMY_TEXTURE_PNG_BYTES".to_utf8_buffer()
	var assets_map = {
		"backs/back_test.png": dummy_back_bytes
	}

	var output_zip = "user://test_output_pack.cardpack"
	var export_res = mgr.export_pack_to_zip(pack_data, output_zip, assets_map)
	assert_true(export_res["success"], "Export must succeed")
	assert_gt(export_res["hash"].length(), 0, "Export must compute SHA-256")

	# Re-import from zip
	var load_res = mgr.load_pack_from_zip(output_zip)
	assert_true(load_res["success"], "Re-import must succeed")
	assert_eq(load_res["pack_id"], "bundle_pack_01")
	assert_eq(load_res["hash"], export_res["hash"], "Computed hash must match export hash")

	# Verify asset retrieval
	var back_bytes = mgr.get_card_back_texture_data("bundle_pack_01")
	assert_eq(back_bytes.get_string_from_utf8(), "DUMMY_TEXTURE_PNG_BYTES")

	# Verify path traversal rejection in asset reading
	var hack_bytes = mgr.read_pack_asset("bundle_pack_01", "../malicious.png")
	assert_eq(hack_bytes.size(), 0, "Unsafe asset read must return empty bytes")

func test_load_pack_from_bytes():
	if _manager_script == null:
		pass_test("Manager script not loaded")
		return

	var mgr = _manager_script.new()
	var pack_data = {
		"schema_version": 1,
		"id": "bytes_pack_02",
		"name": "Bytes Pack",
		"author": "Tester",
		"version": "1.0.0",
		"custom_cards": []
	}

	var tmp_zip = "user://temp_bytes.cardpack"
	var exp_res = mgr.export_pack_to_zip(pack_data, tmp_zip)
	assert_true(exp_res["success"])

	var file = FileAccess.open(tmp_zip, FileAccess.READ)
	assert_not_null(file)
	var zip_bytes = file.get_buffer(file.get_length())
	file.close()

	# Load from raw bytes (simulating network transfer)
	var mgr2 = _manager_script.new()
	var byte_res = mgr2.load_pack_from_bytes(zip_bytes)
	assert_true(byte_res["success"])
	assert_eq(byte_res["pack_id"], "bytes_pack_02")
	assert_eq(byte_res["hash"], exp_res["hash"])

func test_corrupt_zip_rejection():
	if _manager_script == null:
		pass_test("Manager script not loaded")
		return

	var mgr = _manager_script.new()
	var corrupt_path = "user://corrupt.cardpack"
	var fa = FileAccess.open(corrupt_path, FileAccess.WRITE)
	fa.store_string("THIS IS NOT A VALID ZIP ARCHIVE")
	fa.close()

	var res = mgr.load_pack_from_zip(corrupt_path)
	assert_false(res["success"], "Corrupt ZIP file must fail gracefully")

func test_load_pack_from_bytes_path_traversal_defense():
	if _manager_script == null:
		pass_test("Manager script not loaded")
		return

	var mgr = _manager_script.new()
	var pack_data = {
		"schema_version": 1,
		"id": "traversal_pack",
		"name": "Traversal Test",
		"author": "Tester",
		"version": "1.0.0",
		"custom_cards": []
	}
	var tmp_zip = "user://temp_traversal.cardpack"
	var exp_res = mgr.export_pack_to_zip(pack_data, tmp_zip)
	assert_true(exp_res["success"])

	var file = FileAccess.open(tmp_zip, FileAccess.READ)
	assert_not_null(file)
	var zip_bytes = file.get_buffer(file.get_length())
	file.close()

	var bad_filenames = [
		"../../../traversal_escape.cardpack",
		"../traversal_escape.cardpack",
		"../../",
		"..",
		"   ",
		""
	]

	for bad_name in bad_filenames:
		var res = mgr.load_pack_from_bytes(zip_bytes, bad_name)
		assert_true(res["success"], "Loading with bad filename should fallback safely to hash name")
		assert_false(FileAccess.file_exists("user://../traversal_escape.cardpack"), "Must not write outside user://")
		assert_false(FileAccess.file_exists("user://traversal_escape.cardpack"), "Must not write to root user://")
