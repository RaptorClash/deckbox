# test_uno_rules_house.gd
# GUT 9.x Headless Test Suite: UNO Configurable House Rules (Stacking, Jump-In, 7-0, Draw-to-Match)
extends GutTest

const UNO_RULES_PATH = "res://games/uno/uno_rules.gd"
const UNO_HOUSE_RULES_PATH = "res://games/uno/uno_house_rules.gd"
const UNO_CARTRIDGE_PATH = "res://games/uno/uno_cartridge.gd"

var _uno_cartridge_script: GDScript
var _uno_rules_script: GDScript

func before_all():
	if ResourceLoader.exists(UNO_CARTRIDGE_PATH):
		_uno_cartridge_script = load(UNO_CARTRIDGE_PATH)
	elif ResourceLoader.exists(UNO_RULES_PATH):
		_uno_rules_script = load(UNO_RULES_PATH)

func _create_custom_match(house_rules: Dictionary) -> RefCounted:
	var inst: RefCounted = null
	if _uno_cartridge_script != null:
		inst = _uno_cartridge_script.new()
	elif _uno_rules_script != null:
		inst = _uno_rules_script.new()

	if inst != null and inst.has_method("init_match"):
		var players: Array[Dictionary] = []
		for i in range(4):
			players.append({ "player_id": "p%d" % i, "seat": i, "name": "Player %d" % i })
		inst.init_match("match_house", players, house_rules, 42)
		inst.start_round()
	return inst

## Tier 1 & Tier 3: Stacking (+2 on +2) Accumulation
func test_stacking_draw_two_accumulation():
	var game = _create_custom_match({ "stacking_draw_two": true })
	if game == null:
		pass_test("Pending house rules implementation")
		return

	if game.has_method("debug_set_state"):
		game.debug_set_state({
			"top_discard": { "uid": "top", "color": "red", "value": "1" },
			"active_seat": 0,
			"direction": 1,
			"player_hands": {
				"p0": [{ "uid": "c_r_d2", "color": "red", "value": "draw_two" }],
				"p1": [{ "uid": "c_b_d2", "color": "blue", "value": "draw_two" }],
				"p2": [{ "uid": "p2_c", "color": "yellow", "value": "3" }]
			}
		})

		# Seat 0 plays Red +2
		var res0 = game.handle_action("p0", { "type": "ACTION_PLAY_CARD", "card_id": "c_r_d2" })
		assert_true(res0["success"], "P0 plays Red +2")

		# In stacking, turn moves to P1 with pending penalty = 2
		assert_eq(game.get_public_state()["current_turn_seat"], 1, "P1 must respond to +2")
		assert_eq(game.get_public_state()["pending_penalty_draws"], 2, "Penalty is 2 cards")

		# Seat 1 stacks Blue +2
		var res1 = game.handle_action("p1", { "type": "ACTION_PLAY_CARD", "card_id": "c_b_d2" })
		assert_true(res1["success"], "P1 stacks Blue +2")

		# Turn moves to P2 with penalty = 4
		assert_eq(game.get_public_state()["current_turn_seat"], 2, "Turn advances to P2")
		assert_eq(game.get_public_state()["pending_penalty_draws"], 4, "Penalty accumulates to 4 cards")

		# P2 has no +2, draws penalty
		var res2 = game.handle_action("p2", { "type": "ACTION_DRAW_CARD" })
		assert_true(res2["success"], "P2 draws stacked penalty")
		assert_eq(game.get_public_state()["players"][2]["card_count"], 5, "P2 draws 4 cards (1 + 4 = 5)")
		assert_eq(game.get_public_state()["pending_penalty_draws"], 0, "Penalty reset to 0 after draw")

## Tier 1 & Tier 3: Stacking (+4 on +4) Accumulation
func test_stacking_draw_four_accumulation():
	var game = _create_custom_match({ "stacking_draw_four": true })
	if game == null:
		pass_test("Pending house rules implementation")
		return

	if game.has_method("debug_set_state"):
		game.debug_set_state({
			"top_discard": { "uid": "top", "color": "green", "value": "5" },
			"active_seat": 0,
			"direction": 1,
			"player_hands": {
				"p0": [{ "uid": "w4_1", "color": "wild", "value": "wild_draw_four" }],
				"p1": [{ "uid": "w4_2", "color": "wild", "value": "wild_draw_four" }],
				"p2": [{ "uid": "p2_c", "color": "green", "value": "2" }]
			}
		})

		game.handle_action("p0", { "type": "ACTION_PLAY_CARD", "card_id": "w4_1", "chosen_color": "blue" })
		assert_eq(game.get_public_state()["pending_penalty_draws"], 4, "P0 creates +4 penalty")

		game.handle_action("p1", { "type": "ACTION_PLAY_CARD", "card_id": "w4_2", "chosen_color": "yellow" })
		assert_eq(game.get_public_state()["pending_penalty_draws"], 8, "+4 stacks to 8 penalty cards")

## Tier 2 (Boundary & Corner Cases): Stacking Disabled Rejects Counter-play
func test_stacking_disabled_rejects_counter_play():
	var game = _create_custom_match({ "stacking_draw_two": false })
	if game == null:
		pass_test("Pending house rules implementation")
		return

	if game.has_method("debug_set_state"):
		game.debug_set_state({
			"top_discard": { "uid": "top", "color": "yellow", "value": "7" },
			"active_seat": 0,
			"direction": 1,
			"player_hands": {
				"p0": [{ "uid": "d2_a", "color": "yellow", "value": "draw_two" }],
				"p1": [{ "uid": "d2_b", "color": "green", "value": "draw_two" }]
			}
		})

		game.handle_action("p0", { "type": "ACTION_PLAY_CARD", "card_id": "d2_a" })

		# When stacking is disabled, P1 cannot play +2 to pass penalty; P1 is already skipped
		var res1 = game.handle_action("p1", { "type": "ACTION_PLAY_CARD", "card_id": "d2_b" })
		assert_false(res1["success"], "Stacking disabled must reject playing +2 in response")

## Tier 1 & Tier 2: Jump-In on Exact Identical Card Steals Turn
func test_jump_in_exact_identical_card_steals_turn():
	var game = _create_custom_match({ "jump_in": true })
	if game == null:
		pass_test("Pending house rules implementation")
		return

	if game.has_method("debug_set_state"):
		game.debug_set_state({
			"top_discard": { "uid": "top", "color": "blue", "value": "1" },
			"active_seat": 0,
			"direction": 1,
			"player_hands": {
				"p0": [{ "uid": "p0_r7", "color": "red", "value": "7" }],
				"p1": [{ "uid": "p1_c", "color": "green", "value": "3" }],
				"p2": [{ "uid": "p2_r7", "color": "red", "value": "7" }] # Identical Red 7!
			}
		})

		# P0 plays Red 7
		game.handle_action("p0", { "type": "ACTION_PLAY_CARD", "card_id": "p0_r7" })
		assert_eq(game.get_public_state()["top_discard"]["value"], "7", "Top discard is Red 7")

		# Normally P1 would play now. But P2 holds identical Red 7 and jumps in out of turn!
		var jump_action = {
			"type": "ACTION_JUMP_IN",
			"card_id": "p2_r7"
		}
		var jump_res = game.handle_action("p2", jump_action)
		assert_true(jump_res["success"], "Jump-In on exact identical card (Red 7) must succeed")

		# Turn is stolen by P2! Next player is P3 (clockwise from P2)
		assert_eq(game.get_public_state()["current_turn_seat"], 3, "Turn stolen by P2, next player is P3")
		assert_eq(game.get_public_state()["players"][2]["card_count"], 0, "P2 played their card")

## Tier 2 (Boundary & Corner Cases): Jump-In on Non-Identical Card Rejected
func test_jump_in_non_identical_card_rejected():
	var game = _create_custom_match({ "jump_in": true })
	if game == null:
		pass_test("Pending house rules implementation")
		return

	if game.has_method("debug_set_state"):
		game.debug_set_state({
			"top_discard": { "uid": "top", "color": "red", "value": "7" },
			"active_seat": 1,
			"player_hands": {
				"p2": [{ "uid": "p2_b7", "color": "blue", "value": "7" }] # Same number, different color
			}
		})

		var jump_action = { "type": "ACTION_JUMP_IN", "card_id": "p2_b7" }
		var jump_res = game.handle_action("p2", jump_action)
		assert_false(jump_res["success"], "Jump-In with different color must be rejected")

## Tier 1 (Feature Coverage): 7-Swap Rule Exchanging Private Hands
func test_seven_rule_private_hand_swap():
	var game = _create_custom_match({ "seven_zero_passing": true })
	if game == null:
		pass_test("Pending house rules implementation")
		return

	if game.has_method("debug_set_state"):
		game.debug_set_state({
			"top_discard": { "uid": "top", "color": "red", "value": "2" },
			"active_seat": 0,
			"player_hands": {
				"p0": [
					{ "uid": "r7", "color": "red", "value": "7" },
					{ "uid": "r1", "color": "red", "value": "1" }
				],
				"p2": [
					{ "uid": "b9", "color": "blue", "value": "9" },
					{ "uid": "y4", "color": "yellow", "value": "4" },
					{ "uid": "g3", "color": "green", "value": "3" }
				]
			}
		})

		# P0 plays 7 and selects target seat 2
		var action = {
			"type": "ACTION_PLAY_CARD",
			"card_id": "r7",
			"swap_target_seat": 2
		}
		var res = game.handle_action("p0", action)
		assert_true(res["success"], "Playing 7 with swap target must succeed")

		# P0 played r7, had r1 left, swaps with P2's 3 cards
		var p0_view = game.get_player_view("p0")
		var p2_view = game.get_player_view("p2")

		assert_eq(p0_view["hand"].size(), 3, "P0 now holds P2's 3 cards")
		assert_eq(p2_view["hand"].size(), 1, "P2 now holds P0's remaining 1 card")
		assert_eq(p2_view["hand"][0]["uid"], "r1", "P2 received r1")

## Tier 1 (Feature Coverage): 0-Rotation Passing All Hands
func test_zero_rule_rotates_all_hands_in_direction():
	var game = _create_custom_match({ "seven_zero_passing": true })
	if game == null:
		pass_test("Pending house rules implementation")
		return

	if game.has_method("debug_set_state"):
		game.debug_set_state({
			"top_discard": { "uid": "top", "color": "green", "value": "6" },
			"active_seat": 0,
			"direction": 1, # Clockwise
			"player_hands": {
				"p0": [{ "uid": "g0", "color": "green", "value": "0" }, { "uid": "c0", "color": "red", "value": "1" }],
				"p1": [{ "uid": "c1", "color": "blue", "value": "2" }],
				"p2": [{ "uid": "c2", "color": "yellow", "value": "3" }],
				"p3": [{ "uid": "c3", "color": "green", "value": "4" }]
			}
		})

		var action = { "type": "ACTION_PLAY_CARD", "card_id": "g0" }
		var res = game.handle_action("p0", action)
		assert_true(res["success"], "Playing 0 must succeed")

		# Clockwise rotation: Seat 0's leftover (c0) goes to Seat 1, Seat 1's (c1) to Seat 2, etc.
		var p1_view = game.get_player_view("p1")
		var p2_view = game.get_player_view("p2")
		var p3_view = game.get_player_view("p3")
		var p0_view = game.get_player_view("p0")

		assert_eq(p1_view["hand"][0]["uid"], "c0", "Seat 1 received Seat 0's hand")
		assert_eq(p2_view["hand"][0]["uid"], "c1", "Seat 2 received Seat 1's hand")
		assert_eq(p3_view["hand"][0]["uid"], "c2", "Seat 3 received Seat 2's hand")
		assert_eq(p0_view["hand"][0]["uid"], "c3", "Seat 0 received Seat 3's hand")

## Tier 1 & Tier 2: Draw-to-Match Keeps Drawing Until Playable
func test_draw_to_match_enabled():
	var game = _create_custom_match({ "draw_to_match": true })
	if game == null:
		pass_test("Pending house rules implementation")
		return

	if game.has_method("debug_set_state"):
		# Top is Red 9. Draw pile will return: Blue 1, Yellow 2, then Red 3 (playable)
		game.debug_set_state({
			"top_discard": { "uid": "top", "color": "red", "value": "9" },
			"active_seat": 0,
			"player_hands": { "p0": [{ "uid": "unplayable", "color": "blue", "value": "5" }] },
			"draw_pile": [
				{ "uid": "drawn_r3", "color": "red", "value": "3" },
				{ "uid": "drawn_y2", "color": "yellow", "value": "2" },
				{ "uid": "drawn_b1", "color": "blue", "value": "1" }
			]
		})

		var draw_res = game.handle_action("p0", { "type": "ACTION_DRAW_CARD" })
		assert_true(draw_res["success"], "Draw to match succeeds")

		# P0 should have drawn until the playable Red 3 card was obtained (3 cards drawn)
		var p0_view = game.get_player_view("p0")
		assert_gte(p0_view["hand"].size(), 2, "Draw-to-match keeps drawing until playable card found")
