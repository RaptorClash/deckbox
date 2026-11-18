# test_uno_expansions_and_custom_rules.gd
# GUT 9.x Headless Test Suite: UNO No Mercy, UNO Flip, Combinable Rules & Custom Card Creator
extends GutTest

const UNO_CARTRIDGE_PATH = "res://games/uno/uno_cartridge.gd"
const UNO_HOUSE_RULES_PATH = "res://games/uno/uno_house_rules.gd"
const CARD_TEX_GEN_PATH = "res://core/visuals/card_texture_generator.gd"
const COLOR_WHEEL_PATH = "res://games/uno/ui/radial_color_wheel.gd"
const PACK_EDITOR_PATH = "res://scenes/main_hub/pack_editor.tscn"
const MAIN_MENU_PATH = "res://scenes/main_hub/main_menu.tscn"

var _cartridge_script: GDScript
var _house_rules_script: GDScript
var _tex_gen_script: GDScript

func before_all() -> void:
	_cartridge_script = load(UNO_CARTRIDGE_PATH)
	_house_rules_script = load(UNO_HOUSE_RULES_PATH)
	_tex_gen_script = load(CARD_TEX_GEN_PATH)

func _make_players(count: int) -> Array[Dictionary]:
	var arr: Array[Dictionary] = []
	for i in range(count):
		arr.append({
			"player_id": "p%d" % i,
			"seat": i,
			"name": "Player %d" % (i + 1),
			"is_bot": false
		})
	return arr

func test_no_mercy_deck_contains_brutal_cards() -> void:
	var game = _cartridge_script.new()
	game.init_match("nm_deck", _make_players(4), { "expansion_no_mercy": true }, 42)
	game.start_round()

	var all_cards: Array = []
	all_cards.append_array(game.draw_pile)
	all_cards.append_array(game.discard_pile)
	for pid in game.player_hands.keys():
		all_cards.append_array(game.player_hands[pid])

	var found_values: Dictionary = {}
	for c in all_cards:
		found_values[str(c.get("value", ""))] = true

	assert_has(found_values, "draw_four", "No Mercy deck must include colored +4 cards")
	assert_has(found_values, "discard_all", "No Mercy deck must include Discard All cards")
	assert_has(found_values, "skip_everyone", "No Mercy deck must include Skip Everyone cards")
	assert_has(found_values, "wild_reverse_draw_four", "No Mercy deck must include Wild Reverse +4")
	assert_has(found_values, "wild_draw_six", "No Mercy deck must include Wild +6")
	assert_has(found_values, "wild_draw_ten", "No Mercy deck must include Wild +10")
	assert_has(found_values, "wild_color_roulette", "No Mercy deck must include Wild Color Roulette")

func test_no_mercy_progressive_penalty_stacking() -> void:
	var game = _cartridge_script.new()
	game.init_match("nm_stack", _make_players(4), { "expansion_no_mercy": true, "mercy_hand_limit": 0 }, 42)
	game.start_round()

	game.debug_set_state({
		"top_discard": { "uid": "top", "color": "red", "value": "5" },
		"active_seat": 0,
		"direction": 1,
		"player_hands": {
			"p0": [
				{ "uid": "p0_d2", "id": "p0_d2", "color": "red", "value": "draw_two" },
				{ "uid": "p0_keep", "id": "p0_keep", "color": "red", "value": "1" }
			],
			"p1": [
				{ "uid": "p1_d4", "id": "p1_d4", "color": "blue", "value": "draw_four" },
				{ "uid": "p1_keep", "id": "p1_keep", "color": "blue", "value": "2" }
			],
			"p2": [
				{ "uid": "p2_d2_small", "id": "p2_d2_small", "color": "green", "value": "draw_two" },
				{ "uid": "p2_w6", "id": "p2_w6", "color": "wild", "value": "wild_draw_six" },
				{ "uid": "p2_keep", "id": "p2_keep", "color": "green", "value": "3" }
			],
			"p3": [
				{ "uid": "p3_w10", "id": "p3_w10", "color": "wild", "value": "wild_draw_ten" },
				{ "uid": "p3_keep", "id": "p3_keep", "color": "yellow", "value": "4" }
			]
		}
	})

	# P0 plays +2 -> penalty = 2
	assert_true(game.handle_action("p0", { "type": "ACTION_PLAY_CARD", "card_id": "p0_d2" })["success"])
	assert_eq(game.pending_penalty_draws, 2)

	# P1 stacks +4 -> penalty = 6
	assert_true(game.handle_action("p1", { "type": "ACTION_PLAY_CARD", "card_id": "p1_d4" })["success"])
	assert_eq(game.pending_penalty_draws, 6)

	# P2 CANNOT stack smaller +2 onto +4!
	var small_res = game.handle_action("p2", { "type": "ACTION_PLAY_CARD", "card_id": "p2_d2_small" })
	assert_false(small_res["success"], "Cannot stack smaller +2 onto a +4 penalty")

	# P2 CAN stack Wild +6 onto +4 -> penalty = 12
	assert_true(game.handle_action("p2", { "type": "ACTION_PLAY_CARD", "card_id": "p2_w6", "chosen_color": "green" })["success"])
	assert_eq(game.pending_penalty_draws, 12)

	# P3 CAN stack Wild +10 onto +6 -> penalty = 22
	assert_true(game.handle_action("p3", { "type": "ACTION_PLAY_CARD", "card_id": "p3_w10", "chosen_color": "yellow" })["success"])
	assert_eq(game.pending_penalty_draws, 22)

	# P0 cannot counter, draws all 22 cards!
	assert_true(game.handle_action("p0", { "type": "ACTION_DRAW_CARD" })["success"])
	assert_eq(game.get_player_card_count("p0"), 23, "P0 had 1 card + drew 22 = 23 cards")
	assert_eq(game.pending_penalty_draws, 0)

func test_no_mercy_special_actions_skip_everyone_and_discard_all() -> void:
	var game = _cartridge_script.new()
	game.init_match("nm_spec", _make_players(4), { "expansion_no_mercy": true }, 42)
	game.start_round()

	game.debug_set_state({
		"top_discard": { "uid": "top", "color": "red", "value": "3" },
		"active_seat": 0,
		"direction": 1,
		"player_hands": {
			"p0": [
				{ "uid": "p0_se", "id": "p0_se", "color": "red", "value": "skip_everyone" },
				{ "uid": "p0_da", "id": "p0_da", "color": "red", "value": "discard_all" },
				{ "uid": "p0_r5", "id": "p0_r5", "color": "red", "value": "5" },
				{ "uid": "p0_r9", "id": "p0_r9", "color": "red", "value": "9" },
				{ "uid": "p0_b2", "id": "p0_b2", "color": "blue", "value": "2" }
			],
			"p1": [{ "uid": "p1_1", "id": "p1_1", "color": "blue", "value": "1" }],
			"p2": [{ "uid": "p2_1", "id": "p2_1", "color": "blue", "value": "2" }],
			"p3": [{ "uid": "p3_1", "id": "p3_1", "color": "blue", "value": "3" }]
		}
	})

	# Skip Everyone keeps turn on P0!
	assert_true(game.handle_action("p0", { "type": "ACTION_PLAY_CARD", "card_id": "p0_se" })["success"])
	assert_eq(game.current_turn_seat, 0, "Skip Everyone must keep turn on P0")

	# Discard All (Red) drops p0_da, p0_r5, and p0_r9 together, leaving only p0_b2!
	assert_true(game.handle_action("p0", { "type": "ACTION_PLAY_CARD", "card_id": "p0_da" })["success"])
	assert_eq(game.get_player_card_count("p0"), 1, "Discard All must discard all matching Red cards at once")
	assert_eq(game.get_player_view("p0")["hand"][0]["id"], "p0_b2")

func test_no_mercy_25_card_knockout_elimination() -> void:
	var game = _cartridge_script.new()
	game.init_match("nm_ko", _make_players(3), { "expansion_no_mercy": true, "mercy_hand_limit": 25 }, 42)
	game.start_round()

	var p1_24: Array = []
	for i in range(24):
		p1_24.append({ "uid": "p1_c_%d" % i, "id": "p1_c_%d" % i, "color": "blue", "value": "1" })

	game.debug_set_state({
		"top_discard": { "uid": "top", "color": "red", "value": "5" },
		"active_seat": 0,
		"direction": 1,
		"player_hands": {
			"p0": [
				{ "uid": "p0_d4", "id": "p0_d4", "color": "red", "value": "draw_four" },
				{ "uid": "p0_keep", "id": "p0_keep", "color": "red", "value": "2" }
			],
			"p1": p1_24,
			"p2": [{ "uid": "p2_keep", "id": "p2_keep", "color": "green", "value": "7" }]
		}
	})

	# P0 plays +4 -> P1 cannot stack, draws 4 -> 28 >= 25 -> P1 Knocked Out!
	game.handle_action("p0", { "type": "ACTION_PLAY_CARD", "card_id": "p0_d4" })
	var draw_res = game.handle_action("p1", { "type": "ACTION_DRAW_CARD" })
	assert_true(draw_res["success"])
	assert_true(bool(game.player_map["p1"].get("eliminated", false)), "Player reaching >= 25 cards must be knocked out")
	assert_eq(game.get_player_card_count("p1"), 0, "Knocked out player's hand is recycled back to deck")
	assert_eq(game.current_turn_seat, 2, "Turn must advance past knocked out P1 to P2")

	# Verify next turn skips eliminated P1 cleanly
	game.handle_action("p2", { "type": "ACTION_DRAW_CARD" })
	assert_eq(game.current_turn_seat, 0, "Turn must wrap from P2 straight to P0, skipping knocked-out P1")

func test_uno_flip_light_and_dark_side_mechanics() -> void:
	var game = _cartridge_script.new()
	game.init_match("flip_test", _make_players(3), { "expansion_flip": true }, 42)
	game.start_round()

	assert_eq(game.active_side, "light", "UNO Flip must start on Light side")

	game.debug_set_state({
		"top_discard": { "uid": "top", "color": "red", "value": "5", "dark_color": "pink", "dark_value": "5" },
		"active_seat": 0,
		"direction": 1,
		"player_hands": {
			"p0": [
				{ "uid": "p0_flip", "id": "p0_flip", "color": "red", "value": "flip", "dark_color": "pink", "dark_value": "flip" },
				{ "uid": "p0_d", "id": "p0_d", "color": "blue", "value": "draw_two", "dark_color": "teal", "dark_value": "draw_five" }
			],
			"p1": [
				{ "uid": "p1_d5", "id": "p1_d5", "color": "yellow", "value": "2", "dark_color": "pink", "dark_value": "draw_five" },
				{ "uid": "p1_k", "id": "p1_k", "color": "green", "value": "4", "dark_color": "orange", "dark_value": "4" }
			],
			"p2": [
				{ "uid": "p2_k", "id": "p2_k", "color": "red", "value": "7", "dark_color": "purple", "dark_value": "7" }
			]
		}
	})

	# Play Flip -> switches to Dark Side!
	var r0 = game.handle_action("p0", { "type": "ACTION_PLAY_CARD", "card_id": "p0_flip" })
	assert_true(r0["success"], "Playing Flip card must succeed")
	assert_eq(game.active_side, "dark", "Active side must flip to dark")

	var pub = game.get_public_state()
	assert_eq(pub["active_side"], "dark", "Public state must advertise active_side='dark'")
	assert_eq(pub["top_discard"]["color"], "pink", "Top discard must project its Dark Side color (pink)")

	var p1_view = game.get_player_view("p1")
	assert_eq(p1_view["hand"][0]["color"], "pink", "P1's hand must project Dark Side colors")
	assert_eq(p1_view["hand"][0]["value"], "draw_five", "P1's draw_five must activate on Dark Side")

	# P1 plays Pink Draw Five -> P2 draws 5 cards!
	var r1 = game.handle_action("p1", { "type": "ACTION_PLAY_CARD", "card_id": "p1_d5" })
	assert_true(r1["success"], "P1 plays Pink Draw Five on Dark Side")
	assert_eq(game.get_player_card_count("p2"), 6, "P2 drew 5 cards on Dark Side (1 + 5 = 6)")

func test_combined_no_mercy_plus_flip_plus_custom_cards() -> void:
	var custom_def = {
		"id": "mega_plus_8",
		"name": "Mega +8",
		"color": "wild",
		"count": 4,
		"actions": [{ "type": "draw_cards", "count": 8, "target": "next" }]
	}
	var game = _cartridge_script.new()
	game.init_match("combo_test", _make_players(3), {
		"expansion_no_mercy": true,
		"expansion_flip": true,
		"custom_cards": [custom_def]
	}, 42)
	game.start_round()

	# Verify custom card is present in the match deck
	var all_cards: Array = []
	all_cards.append_array(game.draw_pile)
	all_cards.append_array(game.discard_pile)
	for pid in game.player_hands.keys():
		all_cards.append_array(game.player_hands[pid])
	var custom_found = 0
	for c in all_cards:
		if str(c.get("custom_id", "")) == "mega_plus_8":
			custom_found += 1
	assert_eq(custom_found, 4, "All 4 copies of custom card 'mega_plus_8' must be in the match deck")

	# Verify custom +8 card can be stacked on No Mercy +4 and delivers 12 penalty!
	game.debug_set_state({
		"top_discard": { "uid": "top", "color": "red", "value": "draw_four" },
		"active_seat": 0,
		"direction": 1,
		"pending_penalty_draws": 4,
		"last_penalty_step": 4,
		"player_hands": {
			"p0": [
				{
					"uid": "cust_8",
					"id": "cust_8",
					"color": "wild",
					"value": "custom_draw_8",
					"is_custom": true,
					"actions": [{ "type": "draw_cards", "count": 8, "target": "next" }]
				},
				{ "uid": "p0_keep", "id": "p0_keep", "color": "red", "value": "1" }
			],
			"p1": [{ "uid": "p1_k", "id": "p1_k", "color": "blue", "value": "2" }],
			"p2": [{ "uid": "p2_k", "id": "p2_k", "color": "green", "value": "3" }]
		}
	})

	var play_res = game.handle_action("p0", { "type": "ACTION_PLAY_CARD", "card_id": "cust_8", "chosen_color": "blue" })
	assert_true(play_res["success"], "Custom +8 wild card must stack onto +4 in No Mercy progressive mode")
	assert_eq(game.pending_penalty_draws, 12, "Penalty must accumulate 4 + 8 = 12 cards")

func test_card_texture_generator_and_radial_wheel_support_dark_side_and_no_mercy() -> void:
	for c_dict in [
		{ "id": "w10", "color": "wild", "value": "wild_draw_ten" },
		{ "id": "w6", "color": "wild", "value": "wild_draw_six" },
		{ "id": "se", "color": "pink", "value": "skip_everyone" },
		{ "id": "da", "color": "teal", "value": "discard_all" },
		{ "id": "fl", "color": "purple", "value": "flip" },
		{ "id": "d5", "color": "orange", "value": "draw_five" }
	]:
		var tex = _tex_gen_script.get_card_front_texture(c_dict, "classic_arcade", true)
		assert_not_null(tex, "Texture must generate for %s" % c_dict["id"])
		assert_gte(tex.get_width(), 128)

	var wheel = load(COLOR_WHEEL_PATH).new()
	add_child_autofree(wheel)
	assert_true(wheel.has_method("set_dark_side"), "RadialColorWheel must expose set_dark_side()")
	wheel.set_dark_side(true)
	var active_qs = wheel.get_active_quadrants()
	var ids: Array = []
	for q in active_qs:
		ids.append(q["id"])
	assert_has(ids, "pink", "Dark side wheel must include pink")
	assert_has(ids, "teal", "Dark side wheel must include teal")
	assert_has(ids, "purple", "Dark side wheel must include purple")
	assert_has(ids, "orange", "Dark side wheel must include orange")

func test_main_menu_and_pack_editor_expose_expansion_and_custom_card_controls() -> void:
	var menu = load(MAIN_MENU_PATH).instantiate()
	add_child_autofree(menu)
	assert_not_null(menu.no_mercy_check, "Main menu must expose No Mercy toggle")
	assert_not_null(menu.flip_mode_check, "Main menu must expose UNO Flip toggle")
	assert_not_null(menu.mercy_limit_spin, "Main menu must expose Mercy knockout limit SpinBox")

	var editor = load(PACK_EDITOR_PATH).instantiate()
	add_child_autofree(editor)
	assert_not_null(editor.card_effect_opt, "Pack Editor must expose custom card effect OptionButton")
	assert_not_null(editor.card_power_spin, "Pack Editor must expose custom card power SpinBox")

func test_uno_flip_opposite_side_card_helper_and_display_name() -> void:
	var game = _cartridge_script.new()
	assert_eq(game.get_display_name(), "Alle Ablegen!", "Game display name must be renamed to 'Alle Ablegen!'")

	var rules_script = load("res://games/uno/uno_rules.gd")
	var sample = { "id": "c1", "color": "blue", "value": "draw_two", "light_color": "blue", "light_value": "draw_two", "dark_color": "teal", "dark_value": "draw_five" }
	var opp_when_light = rules_script.get_opposite_side_card(sample, "light")
	assert_eq(opp_when_light.get("color"), "teal", "Opposite of light blue draw_two must be dark teal")
	assert_eq(opp_when_light.get("value"), "draw_five", "Opposite value of light draw_two must be dark draw_five")

	var dark_sample = { "id": "c1", "color": "teal", "value": "draw_five", "light_color": "blue", "light_value": "draw_two", "dark_color": "teal", "dark_value": "draw_five" }
	var opp_when_dark = rules_script.get_opposite_side_card(dark_sample, "dark")
	assert_eq(opp_when_dark.get("color"), "blue", "Opposite of dark teal draw_five must be light blue")
	assert_eq(opp_when_dark.get("value"), "draw_two", "Opposite value of dark draw_five must be light draw_two")
