# test_custom_card_interpreter.gd
# GUT 9.x Headless Test Suite: CustomCardInterpreter Declarative Execution & Sandbox Safety
extends GutTest

const INTERPRETER_PATH = "res://core/packs/custom_card_interpreter.gd"
var _interpreter_script: GDScript

func before_all():
	if ResourceLoader.exists(INTERPRETER_PATH):
		_interpreter_script = load(INTERPRETER_PATH)

func test_draw_cards_primitive():
	if _interpreter_script == null:
		pass_test("Interpreter not loaded")
		return

	var context = {
		"player_count": 4,
		"current_seat": 1,
		"direction": 1,
		"draw_pile": [{ "id": "c1" }, { "id": "c2" }, { "id": "c3" }, { "id": "c4" }],
		"hands": { 0: [], 1: [], 2: [], 3: [] }
	}

	# Draw 2 for next player (Seat 2)
	var action = { "type": "draw_cards", "count": 2, "target": "next" }
	var res = _interpreter_script.execute_action(action, context)
	assert_true(res["success"])
	assert_eq(context["hands"][2].size(), 2, "Seat 2 should have drawn 2 cards")
	assert_eq(context["draw_pile"].size(), 2)

func test_skip_next_primitive():
	if _interpreter_script == null:
		pass_test("Interpreter not loaded")
		return

	var context = { "skip_count": 0 }
	var action = { "type": "skip_next", "count": 2 }
	var res = _interpreter_script.execute_action(action, context)
	assert_true(res["success"])
	assert_eq(context["skip_count"], 2)

func test_reverse_primitive_four_players():
	if _interpreter_script == null:
		pass_test("Interpreter not loaded")
		return

	var context = { "player_count": 4, "direction": 1, "skip_count": 0 }
	var action = { "type": "reverse" }
	var res = _interpreter_script.execute_action(action, context)
	assert_true(res["success"])
	assert_eq(context["direction"], -1, "Direction must be inverted")
	assert_eq(context["skip_count"], 0, "4-player reverse does not skip")

func test_reverse_primitive_two_players_acts_as_skip():
	if _interpreter_script == null:
		pass_test("Interpreter not loaded")
		return

	var context = { "player_count": 2, "direction": 1, "skip_count": 0 }
	var action = { "type": "reverse" }
	var res = _interpreter_script.execute_action(action, context)
	assert_true(res["success"])
	assert_eq(context["direction"], -1)
	assert_eq(context["skip_count"], 1, "2-player reverse must increment skip_count")

func test_swap_hands_primitive():
	if _interpreter_script == null:
		pass_test("Interpreter not loaded")
		return

	var context = {
		"player_count": 3,
		"current_seat": 0,
		"direction": 1,
		"hands": {
			0: [{ "id": "p0_card" }],
			1: [{ "id": "p1_card1" }, { "id": "p1_card2" }],
			2: [{ "id": "p2_card" }]
		}
	}

	# Swap with left player (Seat 1)
	var action = { "type": "swap_hands", "target": "left" }
	var res = _interpreter_script.execute_action(action, context)
	assert_true(res["success"])
	assert_eq(context["hands"][0].size(), 2, "Seat 0 should now have Seat 1's hand")
	assert_eq(context["hands"][1].size(), 1, "Seat 1 should now have Seat 0's hand")

func test_discard_color_primitive():
	if _interpreter_script == null:
		pass_test("Interpreter not loaded")
		return

	var context = {
		"current_seat": 0,
		"discard_pile": [],
		"hands": {
			0: [
				{ "id": "c1", "color": "blue" },
				{ "id": "c2", "color": "red" },
				{ "id": "c3", "color": "blue" }
			]
		}
	}

	var action = { "type": "discard_color", "color": "blue" }
	var res = _interpreter_script.execute_action(action, context)
	assert_true(res["success"])
	assert_eq(context["hands"][0].size(), 1, "Only red card should remain")
	assert_eq(context["hands"][0][0]["color"], "red")
	assert_eq(context["discard_pile"].size(), 2, "2 blue cards should be discarded")

func test_negate_penalty_primitive():
	if _interpreter_script == null:
		pass_test("Interpreter not loaded")
		return

	var context = { "pending_penalty": 4, "pending_penalty_draws": 4 }
	var action = { "type": "negate_penalty" }
	var res = _interpreter_script.execute_action(action, context)
	assert_true(res["success"])
	assert_eq(context["pending_penalty"], 0)
	assert_eq(context["pending_penalty_draws"], 0)

func test_adversarial_zero_dynamic_code_execution():
	if _interpreter_script == null:
		pass_test("Interpreter not loaded")
		return

	var context = {}
	var bad_action = {
		"type": "run_eval",
		"code": "print('hacked')"
	}
	var res = _interpreter_script.execute_action(bad_action, context)
	assert_false(res["success"], "Unauthorized action types must be rejected by sandbox")
