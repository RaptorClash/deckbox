# test_pack_editor.gd
# GUT 9.x Headless Test Suite: PackEditorModel & Pack Editor Scene Instantiation
extends GutTest

const MODEL_PATH = "res://core/packs/pack_editor/pack_editor_model.gd"
const SCENE_PATH = "res://scenes/main_hub/pack_editor.tscn"

var _model_script: GDScript

func before_all():
	if ResourceLoader.exists(MODEL_PATH):
		_model_script = load(MODEL_PATH)

func test_model_draft_lifecycle():
	if _model_script == null:
		pass_test("PackEditorModel not loaded")
		return

	var model = _model_script.new()
	model.new_pack("draft_01", "My Draft", "Author Bob")
	assert_false(model.is_dirty())

	model.set_metadata("Updated Name", "Author Bob", "1.1.0", "New description")
	assert_true(model.is_dirty(), "Setting metadata should mark dirty")

	var data = model.get_pack_data()
	assert_eq(data["name"], "Updated Name")
	assert_eq(data["version"], "1.1.0")

func test_set_pack_id_validation():
	if _model_script == null:
		pass_test("PackEditorModel not loaded")
		return

	var model = _model_script.new()
	assert_true(model.set_pack_id("new_valid_id_123"))
	assert_eq(model.get_pack_data()["id"], "new_valid_id_123")
	assert_true(model.is_dirty())

	# Rejection of invalid IDs
	assert_false(model.set_pack_id(""))
	assert_false(model.set_pack_id("   "))
	assert_false(model.set_pack_id("invalid id with spaces"))
	assert_false(model.set_pack_id("invalid/slash"))
	assert_false(model.set_pack_id("invalid:colon"))

func test_model_custom_cards_management():
	if _model_script == null:
		pass_test("PackEditorModel not loaded")
		return

	var model = _model_script.new()
	model.new_pack("cards_pack", "Cards Pack", "Author")

	var card1 = {
		"id": "c_skip",
		"name": "Super Skip",
		"color": "blue",
		"count": 2,
		"actions": [{ "type": "skip_next", "count": 2 }]
	}

	var add_ok = model.add_custom_card(card1)
	assert_true(add_ok, "Valid custom card must be added")
	assert_eq(model.get_custom_cards().size(), 1)

	# Duplicate ID rejection
	var add_dup = model.add_custom_card(card1)
	assert_false(add_dup, "Duplicate custom card ID must be rejected")

	# Update card
	var updated = card1.duplicate(true)
	updated["name"] = "Mega Skip"
	var up_ok = model.update_custom_card("c_skip", updated)
	assert_true(up_ok)
	assert_eq(model.get_custom_cards()[0]["name"], "Mega Skip")

	# Remove card
	var rm_ok = model.remove_custom_card("c_skip")
	assert_true(rm_ok)
	assert_eq(model.get_custom_cards().size(), 0)

func test_model_validation_and_export():
	if _model_script == null:
		pass_test("PackEditorModel not loaded")
		return

	var model = _model_script.new()
	model.new_pack("export_pack", "Export Pack", "Author")
	var val_res = model.validate_current_draft()
	assert_true(val_res["valid"], "Clean draft should be valid")

	var mgr = load("res://core/packs/card_pack_manager.gd").new()
	var out_path = "user://editor_export.cardpack"
	var exp_res = model.export_to_file(mgr, out_path)
	assert_true(exp_res["success"], "Export through model must succeed")
	assert_false(model.is_dirty(), "Export should clear dirty flag")

func test_pack_editor_scene_instantiation():
	if not ResourceLoader.exists(SCENE_PATH):
		pass_test("Pack editor scene not found")
		return

	var scene_res = load(SCENE_PATH)
	assert_not_null(scene_res, "pack_editor.tscn must be loadable")

	var instance = scene_res.instantiate()
	assert_not_null(instance, "pack_editor.tscn must instantiate cleanly")
	assert_true(instance is Control, "Scene root must be Control")

	# Clean up instance
	instance.free()
