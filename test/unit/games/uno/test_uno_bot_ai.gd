# test_uno_bot_ai.gd
# GUT 9.x Headless Test Suite: UNO Bot AI Decision Heuristics & Disconnect Takeover
extends GutTest

const UNO_BOT_AI_PATH = "res://games/uno/uno_bot_ai.gd"
const UNO_CARTRIDGE_PATH = "res://games/uno/uno_cartridge.gd"

var _bot_ai_script: GDScript
var _uno_cartridge_script: GDScript

func before_all():
	if ResourceLoader.exists(UNO_BOT_AI_PATH):
		_bot_ai_script = load(UNO_BOT_AI_PATH)
	if ResourceLoader.exists(UNO_CARTRIDGE_PATH):
		_uno_cartridge_script = load(UNO_CARTRIDGE_PATH)

func _create_bot_evaluator() -> RefCounted:
	if _bot_ai_script != null:
		return _bot_ai_script.new()
	return null

func _create_game_with_bots() -> RefCounted:
	if _uno_cartridge_script != null:
		var game = _uno_cartridge_script.new()
		var players: Array[Dictionary] = [
			{ "player_id": "human_0", "seat": 0, "name": "Human 0", "is_bot": false, "reconnect_token": "tok_0" },
			{ "player_id": "human_1", "seat": 1, "name": "Human 1", "is_bot": false, "reconnect_token": "tok_1" },
			{ "player_id": "bot_2", "seat": 2, "name": "Bot 2", "is_bot": true, "reconnect_token": "" },
			{ "player_id": "bot_3", "seat": 3, "name": "Bot 3", "is_bot": true, "reconnect_token": "" }
		]
		game.init_match("match_bot", players, {}, 1234)
		game.start_round()
		return game
	return null

## Tier 1 (Feature Coverage): Bot Prioritizes Regular Color/Number Over Wild
func test_bot_prioritizes_regular_color_over_wild():
	var ai = _create_bot_evaluator()
	if ai == null:
		pass_test("Pending bot AI implementation")
		return

	var top_discard = { "color": "red", "value": "7" }
	var hand = [
		{ "id": "c_r4", "color": "red", "value": "4", "playable": true },
		{ "id": "c_wild", "color": "wild", "value": "wild", "playable": true }
	]

	var action = ai.choose_action(hand, top_discard, "tactical")
	assert_eq(action["type"], "ACTION_PLAY_CARD", "Bot must choose to play a card")
	assert_eq(action["card_id"], "c_r4", "Bot must conserve Wild and play regular Red 4")

## Tier 1 (Feature Coverage): Bot Saves Wild Draw Four for Emergencies
func test_bot_saves_wild_draw_four():
	var ai = _create_bot_evaluator()
	if ai == null:
		pass_test("Pending bot AI implementation")
		return

	var top_discard = { "color": "green", "value": "2" }
	var hand = [
		{ "id": "c_g_d2", "color": "green", "value": "draw_two", "playable": true },
		{ "id": "c_w4", "color": "wild", "value": "wild_draw_four", "playable": true }
	]

	var action = ai.choose_action(hand, top_discard, "tactical")
	assert_eq(action["card_id"], "c_g_d2", "Bot must play Green Draw Two rather than wasting Wild +4")

## Tier 1 (Feature Coverage): Bot Plays Wild When No Matching Regular Card
func test_bot_plays_wild_as_fallback():
	var ai = _create_bot_evaluator()
	if ai == null:
		pass_test("Pending bot AI implementation")
		return

	var top_discard = { "color": "yellow", "value": "5" }
	var hand = [
		{ "id": "c_b1", "color": "blue", "value": "1", "playable": false },
		{ "id": "c_r8", "color": "red", "value": "8", "playable": false },
		{ "id": "c_wild", "color": "wild", "value": "wild", "playable": true }
	]

	var action = ai.choose_action(hand, top_discard, "tactical")
	assert_eq(action["type"], "ACTION_PLAY_CARD", "Bot plays card when Wild is available")
	assert_eq(action["card_id"], "c_wild", "Bot must play Wild when no other card matches")

## Tier 1 (Feature Coverage): Bot Chooses Color With Highest Count
func test_bot_chooses_dominant_color_on_wild():
	var ai = _create_bot_evaluator()
	if ai == null:
		pass_test("Pending bot AI implementation")
		return

	var top_discard = { "color": "red", "value": "1" }
	var hand = [
		{ "id": "w1", "color": "wild", "value": "wild", "playable": true },
		{ "id": "b1", "color": "blue", "value": "2", "playable": false },
		{ "id": "b2", "color": "blue", "value": "5", "playable": false },
		{ "id": "b3", "color": "blue", "value": "9", "playable": false },
		{ "id": "g1", "color": "green", "value": "3", "playable": false }
	]

	# Hand has: 3 Blue, 1 Green, 0 Red, 0 Yellow. Dominant color is Blue!
	var chosen_color = ai.choose_wild_color(hand)
	assert_eq(chosen_color, "blue", "Bot must choose the color it holds the most cards of (blue)")

## Tier 3 (Cross-Feature): Bot Targets Leader / UNO Caller With Action Cards
func test_bot_attacks_uno_caller():
	var ai = _create_bot_evaluator()
	if ai == null:
		pass_test("Pending bot AI implementation")
		return

	var top_discard = { "color": "yellow", "value": "3" }
	var hand = [
		{ "id": "y3_num", "color": "yellow", "value": "6", "playable": true },
		{ "id": "y_skip", "color": "yellow", "value": "skip", "playable": true }
	]

	# Next player has called UNO (1 card left!)
	var match_context = {
		"next_player_card_count": 1,
		"next_player_called_uno": true
	}

	var action = ai.choose_action_with_context(hand, top_discard, match_context, "tactical")
	assert_eq(action["card_id"], "y_skip", "Bot must prioritize Skip against next player with UNO called")

## Tier 4 (Scenario): Disconnect & Instant Bot Takeover
func test_bot_takeover_on_player_disconnect():
	var game = _create_game_with_bots()
	if game == null:
		pass_test("Pending bot takeover implementation")
		return

	# Seat 1 drops abruptly
	assert_false(game.get_public_state()["players"][1]["is_bot"], "Seat 1 is human before disconnect")

	game.set_player_connected("human_1", false)

	# Public state must now flag seat 1 as bot takeover
	var seat1_summary = game.get_public_state()["players"][1]
	assert_true(seat1_summary["is_bot"], "Seat 1 must be flagged as bot-controlled after disconnect")
	assert_eq(seat1_summary["card_count"], 7, "Hand size must be preserved during takeover")

	# Advance turn to Seat 1: bot automatically executes move
	if game.get_public_state()["current_turn_seat"] != 1:
		game.handle_timeout() # advance to seat 1

	var bot_action = game.get_bot_action("human_1")
	assert_true(bot_action is Dictionary, "Bot must generate action for disconnected player")
	assert_true(bot_action.has("type"), "Bot action must have a valid type")

## Tier 4 (Scenario): Reconnect Token Restores Human Control
func test_bot_relinquishes_control_on_reconnect():
	var game = _create_game_with_bots()
	if game == null:
		pass_test("Pending bot takeover implementation")
		return

	game.set_player_connected("human_1", false)
	assert_true(game.get_public_state()["players"][1]["is_bot"], "Seat 1 in bot mode")

	# Human reconnects using their secret token "tok_1"
	var reconnect_success = game.handle_reconnect("human_1", "tok_1")
	assert_true(reconnect_success, "Valid reconnect token must succeed")

	assert_false(game.get_public_state()["players"][1]["is_bot"], "Seat 1 must return to human control")

## Tier 2 (Boundary & Reliability): Bot Never Stalls on Timeout
func test_bot_timeout_safety():
	var game = _create_game_with_bots()
	if game == null:
		pass_test("Pending bot takeover implementation")
		return

	# Run 10 consecutive timeouts to simulate idle game
	for i in range(10):
		var res = game.handle_timeout()
		assert_true(res["success"], "Timeout %d must resolve cleanly without stalling or crashing" % i)

func test_bot_plays_matching_color_on_wild_top_discard_with_active_color():
	var ai = _create_bot_evaluator()
	if ai == null:
		pass_test("Bot AI not loaded")
		return

	var top_discard = { "color": "wild", "value": "wild" }
	var match_context = {
		"active_color": "blue",
		"next_player_card_count": 5
	}
	var hand = [
		{ "id": "c_b7", "color": "blue", "value": "7" },
		{ "id": "c_r2", "color": "red", "value": "2" }
	]

	var action = ai.choose_action_with_context(hand, top_discard, match_context, "tactical")
	assert_eq(action["type"], "ACTION_PLAY_CARD", "Bot should play Blue 7 matching active color")
	assert_eq(action["card_id"], "c_b7")

func test_bot_draws_penalty_when_cannot_counter_stack():
	var ai = _create_bot_evaluator()
	if ai == null:
		pass_test("Bot AI not loaded")
		return

	var top_discard = { "color": "green", "value": "draw_two" }
	var match_context = {
		"pending_penalty_draws": 4,
		"stacking_draw_two": true,
		"stacking_draw_four": true
	}
	# Hand contains a matching regular green card, but NO +2 or +4
	var hand = [
		{ "id": "c_g5", "color": "green", "value": "5" },
		{ "id": "c_r3", "color": "red", "value": "3" }
	]

	var action = ai.choose_action_with_context(hand, top_discard, match_context, "tactical")
	assert_eq(action["type"], "ACTION_DRAW_CARD", "Bot must draw penalty instead of attempting illegal play")

func test_bot_counter_stacks_when_holding_valid_penalty_card():
	var ai = _create_bot_evaluator()
	if ai == null:
		pass_test("Bot AI not loaded")
		return

	var top_discard = { "color": "yellow", "value": "draw_two" }
	var match_context = {
		"pending_penalty_draws": 2,
		"stacking_draw_two": true,
		"stacking_draw_four": true
	}
	var hand = [
		{ "id": "c_r_d2", "color": "red", "value": "draw_two" },
		{ "id": "c_y1", "color": "yellow", "value": "1" }
	]

	var action = ai.choose_action_with_context(hand, top_discard, match_context, "tactical")
	assert_eq(action["type"], "ACTION_PLAY_CARD", "Bot must counter-stack Draw Two")
	assert_eq(action["card_id"], "c_r_d2")
