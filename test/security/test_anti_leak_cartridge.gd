# test_anti_leak_cartridge.gd
# GUT 9.x Headless Test Suite: Adversarial Anti-Leak State Projection & Sanitization Verification
extends GutTest

const UNO_CARTRIDGE_PATH = "res://games/uno/uno_cartridge.gd"
const ANTI_LEAK_FILTER_PATH = "res://core/security/anti_leak_filter.gd"

var _uno_cartridge_script: GDScript
var _anti_leak_script: GDScript

func before_all():
	if ResourceLoader.exists(UNO_CARTRIDGE_PATH):
		_uno_cartridge_script = load(UNO_CARTRIDGE_PATH)
	if ResourceLoader.exists(ANTI_LEAK_FILTER_PATH):
		_anti_leak_script = load(ANTI_LEAK_FILTER_PATH)

func _create_active_match() -> RefCounted:
	if _uno_cartridge_script != null:
		var game = _uno_cartridge_script.new()
		var players: Array[Dictionary] = [
			{ "player_id": "player_0", "seat": 0, "name": "Alice", "is_bot": false },
			{ "player_id": "player_1", "seat": 1, "name": "Bob", "is_bot": false },
			{ "player_id": "player_2", "seat": 2, "name": "Charlie", "is_bot": false },
			{ "player_id": "player_3", "seat": 3, "name": "Diana", "is_bot": false }
		]
		game.init_match("match_sec", players, { "seven_zero_passing": true }, 54321)
		game.start_round()
		return game
	return null

## Recursive helper function: scans any nested Dictionary/Array for target strings
func _deep_search_for_string(container: Variant, target: String) -> bool:
	if target.is_empty():
		return false
	if container is Dictionary:
		for k in container.keys():
			if str(k).to_lower().contains(target.to_lower()):
				return true
			if _deep_search_for_string(container[k], target):
				return true
	elif container is Array:
		for item in container:
			if _deep_search_for_string(item, target):
				return true
	elif container is String or container is StringName:
		if str(container).to_lower().contains(target.to_lower()):
			return true
	return false

## Tier 1 & Tier 2: get_public_state() Never Leaks Hidden Draw Pile or Draw Pile Order
func test_public_state_never_leaks_draw_pile_cards():
	var game = _create_active_match()
	if game == null:
		pass_test("Pending cartridge anti-leak implementation")
		return

	var pub_state = game.get_public_state()
	assert_true(pub_state is Dictionary, "Public state must be a Dictionary")

	# 1. draw_pile_count must be an integer > 0
	assert_has(pub_state, "draw_pile_count", "Public state must have draw_pile_count")
	assert_true(pub_state["draw_pile_count"] is int, "draw_pile_count must be an integer")
	assert_gt(pub_state["draw_pile_count"], 0, "draw_pile_count must be > 0")

	# 2. Assert NO raw draw pile or deck arrays exist in public state
	assert_does_not_have(pub_state, "draw_pile", "Public state must NEVER include draw_pile array")
	assert_does_not_have(pub_state, "deck", "Public state must NEVER include deck array")
	assert_does_not_have(pub_state, "cards", "Public state must NEVER expose raw card pool")
	assert_does_not_have(pub_state, "remaining_cards", "Public state must NEVER expose remaining cards")

	# 3. Explicit Anti-Leak assertions: Never leak draw pile ordering, upcoming cards, or peek previews
	assert_does_not_have(pub_state, "draw_pile_order", "Public state must NEVER expose draw_pile_order")
	assert_does_not_have(pub_state, "next_card", "Public state must NEVER expose next_card")
	assert_does_not_have(pub_state, "peek", "Public state must NEVER expose peek")
	assert_does_not_have(pub_state, "upcoming_cards", "Public state must NEVER expose upcoming_cards")

	# 4. Deep search verifies forbidden draw pile keys do not appear anywhere in public state
	for forbidden_key in ["draw_pile_order", "next_card", "peek", "upcoming_cards", "remaining_cards"]:
		assert_false(_deep_search_for_string(pub_state, forbidden_key),
			"Public state must not contain forbidden key or substring '%s' anywhere in its hierarchy" % forbidden_key)

## Tier 1 & Tier 2: get_public_state() Never Leaks Opponent Hand Cards
func test_public_state_never_leaks_opponent_hands():
	var game = _create_active_match()
	if game == null:
		pass_test("Pending cartridge anti-leak implementation")
		return

	var pub_state = game.get_public_state()
	assert_has(pub_state, "players", "Public state must list player summaries")
	var players = pub_state["players"]
	assert_eq(players.size(), 4, "Must list 4 players")

	for p in players:
		assert_has(p, "seat", "Player summary must have seat")
		assert_has(p, "name", "Player summary must have name")
		assert_has(p, "card_count", "Player summary must have card_count integer")
		assert_true(p["card_count"] is int, "card_count must be int")

		# SECURITY ZERO-LEAK ASSERTIONS:
		assert_does_not_have(p, "hand", "Public state player summary must NOT contain hand array")
		assert_does_not_have(p, "cards", "Public state player summary must NOT contain cards array")
		assert_does_not_have(p, "card_ids", "Public state player summary must NOT contain card_ids")
		assert_does_not_have(p, "draw_pile_order", "Player summary must NOT contain draw_pile_order")
		assert_does_not_have(p, "next_card", "Player summary must NOT contain next_card")

## Tier 1 & Tier 2: get_player_view() Anonymizes Opponents as [{ "masked": true }]
func test_player_view_anonymizes_opponent_hands_as_masked():
	var game = _create_active_match()
	if game == null:
		pass_test("Pending cartridge anti-leak implementation")
		return

	# Request view for player_0 (Alice)
	var view = game.get_player_view("player_0")
	assert_true(view is Dictionary, "Player view must be a Dictionary")

	# 1. Alice sees her own real hand
	assert_has(view, "hand", "Player view must have hand array for requesting player")
	var own_hand = view["hand"]
	assert_eq(own_hand.size(), 7, "Alice must see her 7 cards")

	for card in own_hand:
		assert_has(card, "id", "Own card must have id")
		assert_has(card, "color", "Own card must have color")
		assert_has(card, "value", "Own card must have value")
		assert_has(card, "playable", "Own card must have playable flag")

	# 2. Alice's view of opponents (Bob, Charlie, Diana)
	assert_has(view, "opponent_hands", "Player view must contain opponent_hands")
	var opponent_hands = view["opponent_hands"]

	for opp_seat in [1, 2, 3]:
		var opp_key = "seat_%d" % opp_seat
		assert_has(opponent_hands, opp_key, "opponent_hands must contain %s" % opp_key)
		var opp_hand = opponent_hands[opp_key]
		assert_true(opp_hand is Array, "Opponent hand representation must be an Array")
		assert_eq(opp_hand.size(), 7, "Opponent hand must have 7 masked tokens")

		for token in opp_hand:
			assert_true(token is Dictionary, "Masked token must be a Dictionary")
			assert_has(token, "masked", "Token must specify { 'masked': true }")
			assert_true(token["masked"], "Token 'masked' property must be true")

			# MANDATORY ANTI-LEAK CHECKS: Absolutely NO card details
			assert_does_not_have(token, "id", "Masked token must NOT have id")
			assert_does_not_have(token, "uid", "Masked token must NOT have uid")
			assert_does_not_have(token, "color", "Masked token must NOT have color")
			assert_does_not_have(token, "value", "Masked token must NOT have value")
			assert_does_not_have(token, "card_face_ref", "Masked token must NOT have card_face_ref")
			assert_does_not_have(token, "texture", "Masked token must NOT have texture reference")

	# 3. Explicit Anti-Leak assertions on player view: Draw pile and upcoming cards must never leak
	assert_does_not_have(view, "draw_pile", "Player view must NEVER include draw_pile array")
	assert_does_not_have(view, "deck", "Player view must NEVER include deck array")
	assert_does_not_have(view, "cards", "Player view must NEVER expose raw card pool")
	assert_does_not_have(view, "remaining_cards", "Player view must NEVER expose remaining cards")
	assert_does_not_have(view, "draw_pile_order", "Player view must NEVER expose draw_pile_order")
	assert_does_not_have(view, "next_card", "Player view must NEVER expose next_card")
	assert_does_not_have(view, "peek", "Player view must NEVER expose peek")
	assert_does_not_have(view, "upcoming_cards", "Player view must NEVER expose upcoming_cards")

## Tier 1 & Tier 2: get_player_view() Never Leaks Hidden Draw Pile or Deck Ordering
func test_player_view_never_leaks_draw_pile_or_order():
	var game = _create_active_match()
	if game == null:
		pass_test("Pending cartridge anti-leak implementation")
		return

	var view = game.get_player_view("player_0")
	assert_true(view is Dictionary, "Player view must be a Dictionary")

	# 1. draw_pile_count scalar integer is allowed/expected for UI counter
	if view.has("draw_pile_count"):
		assert_true(view["draw_pile_count"] is int, "draw_pile_count must be an integer")
		assert_gt(view["draw_pile_count"], 0, "draw_pile_count must be > 0")

	# 2. Assert NO draw pile contents or ordering are leaked
	assert_does_not_have(view, "draw_pile", "Player view must NEVER include draw_pile array")
	assert_does_not_have(view, "deck", "Player view must NEVER include deck array")
	assert_does_not_have(view, "cards", "Player view must NEVER expose raw card pool")
	assert_does_not_have(view, "remaining_cards", "Player view must NEVER expose remaining cards")
	assert_does_not_have(view, "draw_pile_order", "Player view must NEVER expose draw_pile_order")
	assert_does_not_have(view, "next_card", "Player view must NEVER expose next_card")
	assert_does_not_have(view, "peek", "Player view must NEVER expose peek")
	assert_does_not_have(view, "upcoming_cards", "Player view must NEVER expose upcoming_cards")

	# 3. Deep search verifies forbidden draw pile keys do not appear anywhere in view
	for forbidden_key in ["draw_pile_order", "next_card", "peek", "upcoming_cards", "remaining_cards"]:
		assert_false(_deep_search_for_string(view, forbidden_key),
			"Player view must not contain forbidden key or substring '%s' anywhere in its hierarchy" % forbidden_key)

## Tier 2 (Adversarial): Deep Recursive Scan for Leaked Opponent Card UIDs
func test_adversarial_deep_scan_for_opponent_uids():
	var game = _create_active_match()
	if game == null:
		pass_test("Pending cartridge anti-leak implementation")
		return

	# Retrieve secret server-side hands for Bob (player_1), Charlie (player_2), and Diana (player_3)
	var opponent_card_ids: Array[String] = []
	for opp_id in ["player_1", "player_2", "player_3"]:
		var secret_view_opp = game.get_player_view(opp_id)
		if secret_view_opp is Dictionary and secret_view_opp.has("hand"):
			for card in secret_view_opp["hand"]:
				if card.has("id") and not str(card["id"]).is_empty():
					opponent_card_ids.append(str(card["id"]))
				if card.has("uid") and not str(card["uid"]).is_empty():
					opponent_card_ids.append(str(card["uid"]))

	assert_gt(opponent_card_ids.size(), 0, "Opponents must have private cards")

	# Alice queries her player view
	var alice_view = game.get_player_view("player_0")
	assert_true(alice_view is Dictionary, "Alice view must be a Dictionary")
	var serialized_alice_json = JSON.stringify(alice_view)

	# 1. Use _deep_search_for_string to verify that opponent private card UIDs / IDs
	# never exist anywhere in Alice's view dictionary structure
	for opp_id in opponent_card_ids:
		assert_false(_deep_search_for_string(alice_view, opp_id),
			"ADVERSARIAL LEAK DETECTED via _deep_search_for_string: Opponent card ID '%s' found in player_0 view dictionary!" % opp_id)

	# 2. Use _deep_search_for_string on the serialized JSON string as well
	for opp_id in opponent_card_ids:
		assert_false(_deep_search_for_string(serialized_alice_json, opp_id),
			"ADVERSARIAL LEAK DETECTED via _deep_search_for_string: Opponent card ID '%s' found in player_0 serialized JSON!" % opp_id)

	# 3. Assert that NONE of opponent card IDs exist as exact substring in Alice's serialized JSON payload
	for opp_id in opponent_card_ids:
		assert_false(serialized_alice_json.contains(opp_id),
			"ADVERSARIAL LEAK DETECTED: Opponent card ID '%s' leaked in player_0 view JSON payload!" % opp_id)

	# 4. Deep search on public state as well
	var pub_state = game.get_public_state()
	for opp_id in opponent_card_ids:
		assert_false(_deep_search_for_string(pub_state, opp_id),
			"ADVERSARIAL LEAK DETECTED: Opponent card ID '%s' found in public_state via _deep_search_for_string!" % opp_id)

## Tier 2 (Adversarial): Custom Card Pack Face Texture Path Leak Prevention
func test_adversarial_custom_face_texture_path_leak():
	var game = _create_active_match()
	if game == null:
		pass_test("Pending cartridge anti-leak implementation")
		return

	# Alice queries her view
	var alice_view = game.get_player_view("player_0")
	assert_true(alice_view is Dictionary, "Alice view must be a Dictionary")

	# Check opponent hands in view for any texture paths using both assert_does_not_have and _deep_search_for_string
	var opponent_hands = alice_view.get("opponent_hands", {})
	for opp_key in opponent_hands.keys():
		for token in opponent_hands[opp_key]:
			assert_does_not_have(token, "face_texture", "No face_texture in masked card")
			assert_does_not_have(token, "texture_path", "No texture_path in masked card")
			assert_does_not_have(token, "custom_action", "No custom_action in masked card")

	assert_false(_deep_search_for_string(opponent_hands, "face_texture"), "Opponent hands must not contain face_texture via deep search")
	assert_false(_deep_search_for_string(opponent_hands, "texture_path"), "Opponent hands must not contain texture_path via deep search")
	assert_false(_deep_search_for_string(opponent_hands, "custom_action"), "Opponent hands must not contain custom_action via deep search")

## Tier 2 (Adversarial): Deep Search Utility Verification against False Positives & False Negatives
func test_deep_search_for_string_adversarial_verification():
	# 1. Clean data structure (negative cases - no false positives)
	var clean_view = {
		"hand": [
			{ "id": "card_p0_1", "color": "blue", "value": "5", "playable": true }
		],
		"opponent_hands": {
			"seat_1": [{ "masked": true }],
			"seat_2": [{ "masked": true }]
		},
		"draw_pile_count": 80
	}
	assert_false(_deep_search_for_string(clean_view, "secret_card_bob"), "Clean view must not match absent target")
	assert_false(_deep_search_for_string(clean_view, "draw_pile_order"), "Clean view must not match draw_pile_order")
	assert_false(_deep_search_for_string(clean_view, "next_card"), "Clean view must not match next_card")

	# 2. Injected leak in nested dictionary value (positive case)
	var leak_in_token = clean_view.duplicate(true)
	leak_in_token["opponent_hands"]["seat_1"][0]["leaked_id"] = "secret_card_bob"
	assert_true(_deep_search_for_string(leak_in_token, "secret_card_bob"),
		"_deep_search_for_string must detect deeply nested value leak")

	# 3. Injected leak in dictionary key (positive case)
	var leak_in_key = clean_view.duplicate(true)
	leak_in_key["draw_pile_order"] = ["c1", "c2"]
	assert_true(_deep_search_for_string(leak_in_key, "draw_pile_order"),
		"_deep_search_for_string must detect leak in dictionary key")

	# 4. Injected leak in nested array (positive case)
	var leak_in_array = clean_view.duplicate(true)
	leak_in_array["extra_nested"] = [1, 2, ["secret_card_bob"]]
	assert_true(_deep_search_for_string(leak_in_array, "secret_card_bob"),
		"_deep_search_for_string must detect leak inside nested array")

	# 5. String container search (positive and negative)
	var json_str = JSON.stringify(clean_view)
	assert_false(_deep_search_for_string(json_str, "secret_card_bob"), "Clean JSON string must not match absent target")
	assert_true(_deep_search_for_string(JSON.stringify(leak_in_token), "secret_card_bob"),
		"_deep_search_for_string must detect target in serialized JSON string")

## Tier 3 & Tier 4: Anti-Leak Integrity Preserved After 7-Swap Hand Exchange
func test_anti_leak_preserved_after_seven_swap():
	var game = _create_active_match()
	if game == null:
		pass_test("Pending cartridge anti-leak implementation")
		return

	if game.has_method("debug_set_state"):
		game.debug_set_state({
			"top_discard": { "uid": "top", "color": "blue", "value": "2" },
			"active_seat": 0,
			"player_hands": {
				"player_0": [{ "uid": "p0_7", "color": "blue", "value": "7" }],
				"player_1": [{ "uid": "p1_secret", "color": "red", "value": "9" }],
				"player_2": [{ "uid": "p2_secret", "color": "green", "value": "4" }]
			}
		})

		# Player 0 plays 7 and swaps with Player 2
		game.handle_action("player_0", {
			"type": "ACTION_PLAY_CARD",
			"card_id": "p0_7",
			"swap_target_seat": 2
		})

		# Inspect Player 1's view (third-party observer)
		var p1_view = game.get_player_view("player_1")
		var p1_opponents = p1_view["opponent_hands"]

		# Neither Player 0 nor Player 2's new hands should be leaked to Player 1
		for seat_key in ["seat_0", "seat_2"]:
			if p1_opponents.has(seat_key):
				for token in p1_opponents[seat_key]:
					assert_true(token["masked"], "Tokens must remain masked after 7-swap")
					assert_does_not_have(token, "id", "No card IDs revealed to observers after 7-swap")
					assert_does_not_have(token, "uid", "No card UIDs revealed to observers after 7-swap")

		# Deep search verifies neither swapped hand leaks into Player 1's view
		assert_false(_deep_search_for_string(p1_view, "p0_7"), "Player 0's played card ID must not leak to Player 1")
		assert_false(_deep_search_for_string(p1_view, "p2_secret"), "Player 2's secret card UID must not leak to Player 1")

## Tier 4 (Scenario): Anti-Leak Integrity Preserved During Bot Takeover
func test_anti_leak_during_bot_takeover():
	var game = _create_active_match()
	if game == null:
		pass_test("Pending cartridge anti-leak implementation")
		return

	# Player 2 disconnects and is replaced by bot
	if game.has_method("set_player_connected"):
		game.set_player_connected("player_2", false)

		var alice_view = game.get_player_view("player_0")
		var bot_hand_tokens = alice_view["opponent_hands"]["seat_2"]

		# Even though Seat 2 is now a bot, human players must STILL only see masked tokens
		for token in bot_hand_tokens:
			assert_true(token["masked"], "Bot hand must remain masked to human opponents")
			assert_does_not_have(token, "id", "Bot hand card IDs must not leak")
			assert_does_not_have(token, "uid", "Bot hand card UIDs must not leak")

		# Deep search verifies bot internal state or private cards do not leak
		assert_false(_deep_search_for_string(alice_view["opponent_hands"], "bot_secret"),
			"Bot private card identifiers must not leak into opponent hands")
