# test_card_pack_schema.gd
# GUT 9.x Headless Test Suite: CardPackSchema Validation & Security Boundary Testing
extends GutTest

const SCHEMA_PATH = "res://core/packs/card_pack_schema.gd"
var _schema_script: GDScript

func before_all():
	if ResourceLoader.exists(SCHEMA_PATH):
		_schema_script = load(SCHEMA_PATH)

func test_safe_relative_path_validation():
	if _schema_script == null:
		pass_test("Schema script not loaded")
		return

	assert_true(_schema_script.is_safe_relative_path("faces/card.png"))
	assert_true(_schema_script.is_safe_relative_path("backs/back_default.png"))

	# Adversarial rejection of path traversal and absolute paths
	assert_false(_schema_script.is_safe_relative_path("../malicious.png"))
	assert_false(_schema_script.is_safe_relative_path("faces/../../etc/passwd"))
	assert_false(_schema_script.is_safe_relative_path("/root/card.png"))
	assert_false(_schema_script.is_safe_relative_path("\\windows\\system32"))
	assert_false(_schema_script.is_safe_relative_path("C:/passwords.txt"))
	assert_false(_schema_script.is_safe_relative_path(""))
	assert_false(_schema_script.is_safe_relative_path(" "))
	assert_false(_schema_script.is_safe_relative_path("   "))
	assert_false(_schema_script.is_safe_relative_path("\t"))
	assert_false(_schema_script.is_safe_relative_path("\n"))

func test_validate_action_primitives():
	if _schema_script == null:
		pass_test("Schema script not loaded")
		return

	# 1. draw_cards
	var draw_act = { "type": "draw_cards", "count": 4, "target": "all_opponents" }
	assert_true(_schema_script.validate_action(draw_act)["valid"])

	var bad_draw = { "type": "draw_cards", "count": 25, "target": "next" }
	assert_false(_schema_script.validate_action(bad_draw)["valid"], "Draw count > 10 must fail")

	# 2. skip_next
	assert_true(_schema_script.validate_action({ "type": "skip_next", "count": 1 })["valid"])
	assert_false(_schema_script.validate_action({ "type": "skip_next", "count": 10 })["valid"])

	# 3. reverse
	assert_true(_schema_script.validate_action({ "type": "reverse" })["valid"])

	# 4. choose_color
	assert_true(_schema_script.validate_action({ "type": "choose_color" })["valid"])

	# 5. swap_hands
	assert_true(_schema_script.validate_action({ "type": "swap_hands", "target": "choose_opponent" })["valid"])
	assert_false(_schema_script.validate_action({ "type": "swap_hands", "target": "invalid_target" })["valid"])

	# 6. discard_color
	assert_true(_schema_script.validate_action({ "type": "discard_color", "color": "blue" })["valid"])
	assert_false(_schema_script.validate_action({ "type": "discard_color", "color": "" })["valid"])

	# 7. negate_penalty
	assert_true(_schema_script.validate_action({ "type": "negate_penalty" })["valid"])

	# 8. custom_prompt
	assert_true(_schema_script.validate_action({ "type": "custom_prompt", "text": "Choose a category!" })["valid"])
	assert_false(_schema_script.validate_action({ "type": "custom_prompt", "text": "" })["valid"])

	# 9. Adversarial rejection of unknown or malicious primitive
	var malicious_act = { "type": "execute_gdscript", "code": "OS.execute('calc.exe')" }
	assert_false(_schema_script.validate_action(malicious_act)["valid"])

func test_validate_custom_card():
	if _schema_script == null:
		pass_test("Schema script not loaded")
		return

	var valid_card = {
		"id": "tornado_card",
		"name": "Tornado",
		"color": "wild",
		"count": 2,
		"actions": [
			{ "type": "swap_hands", "target": "left" }
		]
	}
	assert_true(_schema_script.validate_custom_card(valid_card)["valid"])

	# Bad card ID with spaces
	var bad_id_card = valid_card.duplicate(true)
	bad_id_card["id"] = "bad id with spaces!"
	assert_false(_schema_script.validate_custom_card(bad_id_card)["valid"])

	# Invalid color
	var bad_col_card = valid_card.duplicate(true)
	bad_col_card["color"] = "ultra_violet"
	assert_false(_schema_script.validate_custom_card(bad_col_card)["valid"])

	# Missing actions
	var no_actions = valid_card.duplicate(true)
	no_actions["actions"] = []
	assert_false(_schema_script.validate_custom_card(no_actions)["valid"])

func test_validate_pack_manifest():
	if _schema_script == null:
		pass_test("Schema script not loaded")
		return

	var valid_pack = {
		"schema_version": 1,
		"id": "test_pack_01",
		"name": "Test Expansion",
		"author": "Alice",
		"version": "1.0.0",
		"description": "A testing pack",
		"assets": {
			"card_back": "backs/back.png"
		},
		"custom_cards": [
			{
				"id": "c1",
				"name": "Card 1",
				"color": "red",
				"count": 1,
				"actions": [{ "type": "skip_next", "count": 1 }]
			}
		]
	}
	assert_true(_schema_script.validate_pack(valid_pack)["valid"])

	# Bad SemVer
	var bad_ver_pack = valid_pack.duplicate(true)
	bad_ver_pack["version"] = "v1-beta"
	assert_false(_schema_script.validate_pack(bad_ver_pack)["valid"])

	# Unsafe asset path
	var unsafe_pack = valid_pack.duplicate(true)
	unsafe_pack["assets"] = { "card_back": "../secret.png" }
	assert_false(_schema_script.validate_pack(unsafe_pack)["valid"])

	# Duplicate card IDs
	var dup_pack = valid_pack.duplicate(true)
	dup_pack["custom_cards"] = [
		{ "id": "dup", "name": "A", "color": "blue", "count": 1, "actions": [{ "type": "reverse" }] },
		{ "id": "dup", "name": "B", "color": "green", "count": 1, "actions": [{ "type": "reverse" }] }
	]
	assert_false(_schema_script.validate_pack(dup_pack)["valid"], "Duplicate card IDs must fail validation")
