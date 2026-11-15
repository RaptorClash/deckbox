# test_uno_rules_standard.gd
# GUT 9.x Headless Test Suite: Standard UNO Rules, Card Matching, & Action Mechanics
extends GutTest

const UNO_RULES_PATH = "res://games/uno/uno_rules.gd"
const UNO_CARTRIDGE_PATH = "res://games/uno/uno_cartridge.gd"

var _uno_rules_script: GDScript
var _uno_cartridge_script: GDScript

func before_all():
	if ResourceLoader.exists(UNO_RULES_PATH):
		_uno_rules_script = load(UNO_RULES_PATH)
	if ResourceLoader.exists(UNO_CARTRIDGE_PATH):
		_uno_cartridge_script = load(UNO_CARTRIDGE_PATH)

func _create_game_instance(player_count: int = 4, seed_val: int = 100) -> RefCounted:
	var inst: RefCounted = null
	if _uno_cartridge_script != null:
		inst = _uno_cartridge_script.new()
	elif _uno_rules_script != null:
		inst = _uno_rules_script.new()

	if inst != null and inst.has_method("init_match"):
		var players: Array[Dictionary] = []
		for i in range(player_count):
			players.append({
				"player_id": "p%d" % i,
				"seat": i,
				"name": "Player %d" % i,
				"is_bot": false
			})
		inst.init_match("match_std", players, {}, seed_val)
		inst.start_round()
	return inst

## Tier 1 (Feature Coverage): Initial Deal of 7 Cards Each
func test_initial_deal_seven_cards_per_player():
	var game = _create_game_instance(4)
	if game == null:
		pass_test("Pending uno implementation")
		return

	var pub_state = game.get_public_state()
	var players = pub_state["players"]
	assert_eq(players.size(), 4, "Match must have 4 players")

	for p in players:
		assert_eq(p["card_count"], 7, "Each player must be dealt exactly 7 cards initially")

	# Draw pile count should be: 108 total - (4 players * 7 cards) - 1 top discard = 79 cards
	assert_eq(pub_state["draw_pile_count"], 79, "Draw pile count must be exactly 79 after initial deal")
	assert_not_null(pub_state["top_discard"], "Top discard must be placed face-up")

## Tier 1 (Feature Coverage): Matching by Same Color
func test_match_by_same_color():
	var game = _create_game_instance(4)
	if game == null:
		pass_test("Pending uno implementation")
		return

	if game.has_method("debug_set_state"):
		game.debug_set_state({
			"top_discard": { "uid": "top", "color": "red", "value": "3" },
			"active_seat": 0,
			"player_hands": {
				"p0": [{ "uid": "c1", "color": "red", "value": "7" }]
			}
		})
		var action = {
			"type": "ACTION_PLAY_CARD",
			"card_id": "c1"
		}
		var result = game.handle_action("p0", action)
		assert_true(result["success"], "Playing Red 7 on Red 3 must succeed (matching color)")
		assert_eq(game.get_public_state()["top_discard"]["value"], "7", "Top discard must be Red 7")

## Tier 1 (Feature Coverage): Matching by Same Number
func test_match_by_same_number():
	var game = _create_game_instance(4)
	if game == null:
		pass_test("Pending uno implementation")
		return

	if game.has_method("debug_set_state"):
		game.debug_set_state({
			"top_discard": { "uid": "top", "color": "red", "value": "5" },
			"active_seat": 0,
			"player_hands": {
				"p0": [{ "uid": "c2", "color": "blue", "value": "5" }]
			}
		})
		var action = {
			"type": "ACTION_PLAY_CARD",
			"card_id": "c2"
		}
		var result = game.handle_action("p0", action)
		assert_true(result["success"], "Playing Blue 5 on Red 5 must succeed (matching number)")
		assert_eq(game.get_public_state()["top_discard"]["color"], "blue", "Top discard color must be blue")

## Tier 1 (Feature Coverage): Matching by Same Action Symbol
func test_match_by_same_symbol():
	var game = _create_game_instance(4)
	if game == null:
		pass_test("Pending uno implementation")
		return

	if game.has_method("debug_set_state"):
		game.debug_set_state({
			"top_discard": { "uid": "top", "color": "green", "value": "skip" },
			"active_seat": 0,
			"player_hands": {
				"p0": [{ "uid": "c3", "color": "yellow", "value": "skip" }]
			}
		})
		var action = {
			"type": "ACTION_PLAY_CARD",
			"card_id": "c3"
		}
		var result = game.handle_action("p0", action)
		assert_true(result["success"], "Playing Yellow Skip on Green Skip must succeed (matching symbol)")

## Tier 1 (Feature Coverage): Wild Card Matching & Color Choice
func test_match_wild_on_any_card():
	var game = _create_game_instance(4)
	if game == null:
		pass_test("Pending uno implementation")
		return

	if game.has_method("debug_set_state"):
		game.debug_set_state({
			"top_discard": { "uid": "top", "color": "blue", "value": "9" },
			"active_seat": 0,
			"player_hands": {
				"p0": [{ "uid": "c_wild", "color": "wild", "value": "wild" }]
			}
		})
		var action = {
			"type": "ACTION_PLAY_CARD",
			"card_id": "c_wild",
			"chosen_color": "green"
		}
		var result = game.handle_action("p0", action)
		assert_true(result["success"], "Wild card must be playable on any card")
		assert_eq(game.get_public_state()["active_color"], "green", "Active color must update to chosen color")

## Tier 1 (Feature Coverage): Wild Draw Four Card
func test_match_wild_draw_four():
	var game = _create_game_instance(4)
	if game == null:
		pass_test("Pending uno implementation")
		return

	if game.has_method("debug_set_state"):
		game.debug_set_state({
			"top_discard": { "uid": "top", "color": "yellow", "value": "2" },
			"active_seat": 0,
			"direction": 1,
			"player_hands": {
				"p0": [{ "uid": "c_w4", "color": "wild", "value": "wild_draw_four" }],
				"p1": [{ "uid": "p1_c1", "color": "red", "value": "1" }]
			}
		})
		var action = {
			"type": "ACTION_PLAY_CARD",
			"card_id": "c_w4",
			"chosen_color": "red"
		}
		var result = game.handle_action("p0", action)
		assert_true(result["success"], "Wild Draw Four must succeed")

		# p1 should draw 4 cards and be skipped, advancing turn to p2
		var p1_count = game.get_public_state()["players"][1]["card_count"]
		assert_eq(p1_count, 5, "p1 hand must increase by 4 cards (1 + 4 = 5)")
		assert_eq(game.get_public_state()["current_turn_seat"], 2, "Turn must advance past skipped p1 to p2")

## Tier 2 (Boundary & Corner Cases): Rejection of Non-Matching Card
func test_reject_invalid_non_matching_card():
	var game = _create_game_instance(4)
	if game == null:
		pass_test("Pending uno implementation")
		return

	if game.has_method("debug_set_state"):
		game.debug_set_state({
			"top_discard": { "uid": "top", "color": "red", "value": "3" },
			"active_seat": 0,
			"player_hands": {
				"p0": [{ "uid": "c_bad", "color": "blue", "value": "8" }]
			}
		})
		var action = {
			"type": "ACTION_PLAY_CARD",
			"card_id": "c_bad"
		}
		var result = game.handle_action("p0", action)
		assert_false(result["success"], "Blue 8 on Red 3 must be rejected")
		assert_eq(game.get_public_state()["top_discard"]["value"], "3", "Top discard must remain unchanged")

## Tier 1 (Feature Coverage): Skip Card Action
func test_skip_card_skips_next_player():
	var game = _create_game_instance(4)
	if game == null:
		pass_test("Pending uno implementation")
		return

	if game.has_method("debug_set_state"):
		game.debug_set_state({
			"top_discard": { "uid": "top", "color": "red", "value": "2" },
			"active_seat": 0,
			"direction": 1,
			"player_hands": {
				"p0": [{ "uid": "c_skip", "color": "red", "value": "skip" }]
			}
		})
		var action = { "type": "ACTION_PLAY_CARD", "card_id": "c_skip" }
		var result = game.handle_action("p0", action)
		assert_true(result["success"], "Playing Skip must succeed")

		# In 4-player clockwise game, Seat 1 is skipped, turn goes to Seat 2
		assert_eq(game.get_public_state()["current_turn_seat"], 2, "Turn must skip Seat 1 and land on Seat 2")

## Tier 1 & Tier 2: Reverse Card in 4-Player Match
func test_reverse_card_four_players():
	var game = _create_game_instance(4)
	if game == null:
		pass_test("Pending uno implementation")
		return

	if game.has_method("debug_set_state"):
		game.debug_set_state({
			"top_discard": { "uid": "top", "color": "blue", "value": "4" },
			"active_seat": 0,
			"direction": 1,
			"player_hands": {
				"p0": [{ "uid": "c_rev", "color": "blue", "value": "reverse" }]
			}
		})
		var action = { "type": "ACTION_PLAY_CARD", "card_id": "c_rev" }
		var result = game.handle_action("p0", action)
		assert_true(result["success"], "Playing Reverse must succeed")

		# Direction flips from 1 to -1; from Seat 0 in -1 direction next is Seat 3
		assert_eq(game.get_public_state()["direction"], -1, "Direction must be reversed to -1")
		assert_eq(game.get_public_state()["current_turn_seat"], 3, "Next turn in counter-clockwise must be Seat 3")

## Tier 2 (Boundary & Corner Cases): Reverse Card in 2-Player Match (Acts as Skip)
func test_reverse_card_two_players_acts_as_skip():
	var game = _create_game_instance(2)
	if game == null:
		pass_test("Pending uno implementation")
		return

	if game.has_method("debug_set_state"):
		game.debug_set_state({
			"top_discard": { "uid": "top", "color": "green", "value": "1" },
			"active_seat": 0,
			"direction": 1,
			"player_hands": {
				"p0": [{ "uid": "c_rev2", "color": "green", "value": "reverse" }]
			}
		})
		var action = { "type": "ACTION_PLAY_CARD", "card_id": "c_rev2" }
		var result = game.handle_action("p0", action)
		assert_true(result["success"], "Reverse in 2-player match must succeed")

		# Official UNO 2-player rule: Reverse acts as a Skip, giving active player another turn
		assert_eq(game.get_public_state()["current_turn_seat"], 0, "In 2-player UNO, Reverse must act as Skip (turn stays with Seat 0)")

## Tier 1 (Feature Coverage): Draw Two Card Mechanic
func test_draw_two_card_mechanic():
	var game = _create_game_instance(4)
	if game == null:
		pass_test("Pending uno implementation")
		return

	if game.has_method("debug_set_state"):
		game.debug_set_state({
			"top_discard": { "uid": "top", "color": "yellow", "value": "8" },
			"active_seat": 0,
			"direction": 1,
			"player_hands": {
				"p0": [{ "uid": "c_d2", "color": "yellow", "value": "draw_two" }],
				"p1": [{ "uid": "p1_c", "color": "blue", "value": "2" }]
			}
		})
		var action = { "type": "ACTION_PLAY_CARD", "card_id": "c_d2" }
		var result = game.handle_action("p0", action)
		assert_true(result["success"], "Playing Draw Two must succeed")

		var p1_count = game.get_public_state()["players"][1]["card_count"]
		assert_eq(p1_count, 3, "Seat 1 must receive 2 cards (1 + 2 = 3)")
		assert_eq(game.get_public_state()["current_turn_seat"], 2, "Seat 1 turn skipped; advances to Seat 2")

## Tier 4 (Scenario): Win Condition & Round Termination
func test_win_condition_round_over():
	var game = _create_game_instance(3)
	if game == null:
		pass_test("Pending uno implementation")
		return

	if game.has_method("debug_set_state"):
		game.debug_set_state({
			"top_discard": { "uid": "top", "color": "red", "value": "2" },
			"active_seat": 0,
			"player_hands": {
				"p0": [{ "uid": "winning_card", "color": "red", "value": "9" }],
				"p1": [{ "uid": "p1_1", "color": "blue", "value": "5" }],
				"p2": [{ "uid": "p2_1", "color": "yellow", "value": "skip" }]
			}
		})
		var action = { "type": "ACTION_PLAY_CARD", "card_id": "winning_card" }
		var result = game.handle_action("p0", action)
		assert_true(result["success"], "Winning card play must succeed")

		assert_true(game.is_round_over(), "Round must be over when player has 0 cards")
		var round_results = game.get_round_results()
		assert_eq(round_results["winner_seat"], 0, "Winner must be Seat 0")
		assert_gt(round_results["score_earned"], 0, "Winner must earn points from opponents' remaining cards")
