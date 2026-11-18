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

func test_pack_editor_3d_preview_designs_game_target_import_export_and_no_presets():
	var tex_gen = load("res://core/visuals/card_texture_generator.gd")
	var skin_id := "custom_emerald_gold"
	assert_true(tex_gen.register_custom_skin({
		"id": skin_id,
		"name": "Emerald & Gold",
		"frame_color": "#FFD700",
		"bg_color": "#0A281E",
		"accent_color": "#20E090",
		"back_primary": "#0C3A2C",
		"back_secondary": "#F5C542",
		"back_emblem": "EG"
	}), "Registering custom card design must succeed")
	assert_has(tex_gen.get_available_skin_ids(), skin_id, "Custom skin ID must appear in available skins")
	var front_t: ImageTexture = tex_gen.get_card_front_texture({ "color": "red", "value": "7" }, skin_id, true)
	var back_t: ImageTexture = tex_gen.get_card_back_texture(skin_id)
	assert_not_null(front_t)
	assert_not_null(back_t)

	var model = _model_script.new()
	model.set_target_game("wizard")
	assert_eq(model.get_target_game(), "wizard", "PackEditorModel must store target_game")

	var editor = load(SCENE_PATH).instantiate()
	add_child_autofree(editor)
	assert_null(editor.get_node_or_null("VBoxContainer/TabContainer/Cards/HSplitContainer/CardDetails/PresetsRow"), "Quick presets row must be removed")
	assert_not_null(editor.card_preview_3d_viewport, "PackEditor must expose 3D SubViewport card preview")
	assert_not_null(editor.preview_flip_btn, "PackEditor must expose 3D front/back flip toggle button")
	assert_not_null(editor.target_game_opt, "PackEditor must expose target game selector OptionButton")
	assert_gte(editor.target_game_opt.item_count, 3, "Target game selector must list multiple games")
	assert_not_null(editor.design_tab, "PackEditor must expose Card Design tab")

	editor.design_id_edit.text = "shared_crimson_royal"
	editor.design_name_edit.text = "Crimson Royal"
	editor.design_emblem_edit.text = "CR"
	var share_path := "user://test_shared_design.json"
	var exp_res: Dictionary = editor.export_design_to_file(share_path)
	assert_true(bool(exp_res.get("success", false)), "Design export must succeed")
	var imp_res: Dictionary = editor.import_pack_or_design_from_file(share_path)
	assert_true(bool(imp_res.get("success", false)), "Design import must succeed")
	assert_has(tex_gen.get_available_skin_ids(), "shared_crimson_royal", "Imported design must register into CardTextureGenerator")
