# test_anti_leak_filter.gd
# GUT 9.x Headless Test Suite: Dedicated Unit Tests for AntiLeakFilter
extends GutTest

const ANTI_LEAK_FILTER_PATH = "res://core/security/anti_leak_filter.gd"
var _filter_script: GDScript

func before_all():
	if ResourceLoader.exists(ANTI_LEAK_FILTER_PATH):
		_filter_script = load(ANTI_LEAK_FILTER_PATH)

class MockGame extends RefCounted:
	var match_id: String = "mock_match_100"
	var status: String = "in_progress"
	var current_turn_seat: int = 1
	var direction: int = 1
	var draw_pile: Array = [
		{ "id": "secret_draw_1", "color": "red", "value": "2" },
		{ "id": "secret_draw_2", "color": "blue", "value": "5" }
	]
	var discard_pile: Array = [
		{ "id": "top_card_id", "color": "green", "value": "7" }
	]
	var players: Array[Dictionary] = [
		{ "player_id": "alice", "seat": 0, "name": "Alice", "called_uno": false, "is_bot": false },
		{ "player_id": "bob", "seat": 1, "name": "Bob", "called_uno": true, "is_bot": false },
		{ "player_id": "carol", "seat": 2, "name": "Carol", "called_uno": false, "is_bot": true }
	]
	var hands: Dictionary = {
		"alice": [
			{ "id": "card_a1", "uid": "card_a1", "color": "green", "value": "3" },
			{ "id": "card_a2", "uid": "card_a2", "color": "yellow", "value": "7" }
		],
		"bob": [
			{ "id": "secret_b1", "uid": "secret_b1", "color": "red", "value": "9" }
		],
		"carol": [
			{ "id": "secret_c1", "uid": "secret_c1", "color": "blue", "value": "1" },
			{ "id": "secret_c2", "uid": "secret_c2", "color": "wild", "value": "wild" },
			{ "id": "secret_c3", "uid": "secret_c3", "color": "green", "value": "5" }
		]
	}

	func get_top_discard() -> Dictionary:
		return discard_pile.back() if discard_pile.size() > 0 else {}

	func get_player_card_count(p_id: String) -> int:
		return hands.get(p_id, []).size()

	func get_player_hand(p_id: String) -> Array:
		return hands.get(p_id, [])

	func is_card_playable(card: Dictionary) -> bool:
		var top = get_top_discard()
		return card.get("color") == top.get("color") or card.get("value") == top.get("value") or card.get("color") == "wild"

func test_filter_public_state_contract():
	if _filter_script == null:
		pass_test("AntiLeakFilter script not yet loaded")
		return

	var game = MockGame.new()
	var pub_state = _filter_script.filter_public_state(game)

	assert_true(pub_state is Dictionary, "Public state must be Dictionary")
	assert_eq(pub_state["match_id"], "mock_match_100")
	assert_eq(pub_state["draw_pile_count"], 2, "Draw pile count must be int 2")
	assert_eq(pub_state["turn_seat"], 1)
	assert_eq(pub_state["current_turn_seat"], 1)
	assert_eq(pub_state["direction"], 1)

	# Verify top discard sanitization: must have color and value, must NOT leak internal id
	assert_eq(pub_state["top_discard"]["color"], "green")
	assert_eq(pub_state["top_discard"]["value"], "7")
	assert_does_not_have(pub_state["top_discard"], "id", "Top discard must not expose internal card id")

	# Verify forbidden keys absent
	for forbidden in ["draw_pile", "deck", "cards", "remaining_cards", "draw_pile_order", "next_card", "peek", "upcoming_cards"]:
		assert_does_not_have(pub_state, forbidden, "Public state must not have %s" % forbidden)

	# Check player summaries
	var p_list = pub_state["players"]
	assert_eq(p_list.size(), 3)
	assert_eq(p_list[0]["seat"], 0)
	assert_eq(p_list[0]["name"], "Alice")
	assert_eq(p_list[0]["card_count"], 2)
	assert_false(p_list[0]["called_uno"])
	assert_eq(p_list[1]["card_count"], 1)
	assert_true(p_list[1]["called_uno"])
	assert_eq(p_list[2]["card_count"], 3)
	assert_true(p_list[2]["is_bot"])

	for p in p_list:
		assert_does_not_have(p, "hand")
		assert_does_not_have(p, "card_ids")

func test_filter_player_view_anonymizes_opponents():
	if _filter_script == null:
		pass_test("AntiLeakFilter script not yet loaded")
		return

	var game = MockGame.new()
	var view = _filter_script.filter_player_view(game, "alice")

	assert_true(view is Dictionary)
	assert_eq(view["my_player_id"], "alice")
	assert_eq(view["my_seat"], 0)

	# Alice's own hand
	assert_has(view, "hand")
	var hand = view["hand"]
	assert_eq(hand.size(), 2)
	assert_eq(hand[0]["id"], "card_a1")
	assert_eq(hand[0]["uid"], "card_a1")
	assert_eq(hand[0]["color"], "green")
	assert_eq(hand[0]["value"], "3")
	assert_true(hand[0]["playable"], "card_a1 (green) matches top discard (green 7)")

	assert_eq(hand[1]["id"], "card_a2")
	assert_eq(hand[1]["value"], "7")
	assert_true(hand[1]["playable"], "card_a2 (value 7) matches top discard (green 7)")

	# Opponent hands
	assert_has(view, "opponent_hands")
	var opps = view["opponent_hands"]
	assert_has(opps, "seat_1")
	assert_has(opps, "seat_2")
	assert_does_not_have(opps, "seat_0", "Requesting player seat must not be in opponent_hands")

	# Bob (seat 1): 1 card
	assert_eq(opps["seat_1"].size(), 1)
	assert_true(opps["seat_1"][0]["masked"])
	assert_does_not_have(opps["seat_1"][0], "id")
	assert_does_not_have(opps["seat_1"][0], "uid")
	assert_does_not_have(opps["seat_1"][0], "color")
	assert_does_not_have(opps["seat_1"][0], "value")

	# Carol (seat 2): 3 cards
	assert_eq(opps["seat_2"].size(), 3)
	for token in opps["seat_2"]:
		assert_true(token["masked"])
		assert_does_not_have(token, "id")
		assert_does_not_have(token, "uid")
		assert_does_not_have(token, "face_texture")
		assert_does_not_have(token, "texture_path")
		assert_does_not_have(token, "custom_action")

func test_adversarial_zero_leak_of_opponent_ids():
	if _filter_script == null:
		pass_test("AntiLeakFilter script not yet loaded")
		return

	var game = MockGame.new()
	var alice_view = _filter_script.filter_player_view(game, "alice")
	var alice_json = JSON.stringify(alice_view)

	var secrets = ["secret_b1", "secret_c1", "secret_c2", "secret_c3", "secret_draw_1", "secret_draw_2"]
	for s in secrets:
		assert_false(alice_json.contains(s), "Secret string '%s' must not appear in alice_view JSON" % s)
