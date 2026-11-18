# test_uno_scaling.gd
# GUT 9.x Headless Test Suite: N-Player Unlimited Scaling, Multi-Deck & Dynamic Table Sizing
extends GutTest

const UNO_RULES_PATH = "res://games/uno/uno_rules.gd"
const UNO_CARTRIDGE_PATH = "res://games/uno/uno_cartridge.gd"
const ROOM_MANAGER_PATH = "res://core/network/room_manager.gd"
const ARCADE_TABLE_PATH = "res://scenes/tables/arcade_ps5.tscn"

var _uno_rules_script: GDScript
var _uno_cartridge_script: GDScript
var _room_manager_script: GDScript

func before_all() -> void:
	_uno_rules_script = load(UNO_RULES_PATH)
	_uno_cartridge_script = load(UNO_CARTRIDGE_PATH)
	_room_manager_script = load(ROOM_MANAGER_PATH)

func _make_players(count: int) -> Array[Dictionary]:
	var arr: Array[Dictionary] = []
	for i in range(count):
		arr.append({
			"player_id": "p%d" % i,
			"seat": i,
			"name": "Player %d" % (i + 1),
			"is_bot": i > 0
		})
	return arr

func test_recommended_deck_count_scaling() -> void:
	assert_true(_uno_rules_script != null, "UnoRules script must exist")
	var rules = _uno_rules_script.new()
	assert_true(rules.has_method("calculate_recommended_deck_count") or _uno_rules_script.has_method("calculate_recommended_deck_count"), "Must expose calculate_recommended_deck_count")

	# 2-5 players with 7 cards -> 1 deck (preserves classic 108-card matches)
	assert_eq(_uno_rules_script.calculate_recommended_deck_count(2, 7), 1, "2 players should use 1 deck")
	assert_eq(_uno_rules_script.calculate_recommended_deck_count(4, 7), 1, "4 players should use 1 deck")
	assert_eq(_uno_rules_script.calculate_recommended_deck_count(5, 7), 1, "5 players should use 1 deck")

	# 6-10 players -> 2 decks
	assert_eq(_uno_rules_script.calculate_recommended_deck_count(6, 7), 2, "6 players should use 2 decks")
	assert_eq(_uno_rules_script.calculate_recommended_deck_count(10, 7), 2, "10 players should use 2 decks")

	# 11-15 players -> 3 decks
	assert_eq(_uno_rules_script.calculate_recommended_deck_count(11, 7), 3, "11 players should use 3 decks")
	assert_eq(_uno_rules_script.calculate_recommended_deck_count(15, 7), 3, "15 players should use 3 decks")

	# 24 players -> 5 decks
	assert_eq(_uno_rules_script.calculate_recommended_deck_count(24, 7), 5, "24 players should use 5 decks")

	# Adversarial boundaries
	assert_eq(_uno_rules_script.calculate_recommended_deck_count(0, 7), 1, "0 players must clamp to 1 deck")
	assert_eq(_uno_rules_script.calculate_recommended_deck_count(-5, 0), 1, "Negative players must clamp to 1 deck")

func test_multi_deck_initialization() -> void:
	var rules = _uno_rules_script.new()
	rules.init_deck(12345, 3, true)
	var pile = rules.get_draw_pile()
	assert_eq(pile.size(), 324, "3 decks must contain 3 * 108 = 324 cards")

	var seen_uids: Dictionary = {}
	for c in pile:
		var uid = str(c.get("uid", ""))
		assert_false(uid.is_empty(), "Every card must have a non-empty uid")
		assert_false(seen_uids.has(uid), "Every card across multi-deck must have a unique uid: %s" % uid)
		seen_uids[uid] = true
	assert_eq(seen_uids.size(), 324, "All 324 UIDs must be strictly unique")

func test_auto_expand_endless_deck_refill() -> void:
	var rules = _uno_rules_script.new()
	rules.init_deck(12345, 1, true)
	rules.debug_set_piles([], [{ "uid": "sole", "color": "red", "value": "5" }])

	var drawn = rules.draw_card()
	assert_not_null(drawn, "With auto_expand=true, drawing on exhausted piles must refill a new deck")
	assert_true(drawn is Dictionary and not drawn.is_empty(), "Refilled drawn card must be valid")
	assert_eq(rules.get_draw_pile_count(), 107, "Fresh 108-card expansion deck minus 1 drawn = 107 remaining")

func test_cartridge_supports_8_and_16_players() -> void:
	var cartridge = _uno_cartridge_script.new()
	assert_gte(cartridge.get_max_players(), 999, "UNO cartridge must allow large/unlimited player counts")

	# 8 players -> 2 decks (216 cards) -> 56 dealt + 1 discard = 159 remaining
	var p8 = _make_players(8)
	cartridge.init_match("m8", p8, {}, 42)
	cartridge.start_round()
	var pub8 = cartridge.get_public_state()
	assert_eq(pub8["players"].size(), 8, "8-player match must preserve all 8 players")
	for i in range(8):
		assert_eq(cartridge.get_player_card_count("p%d" % i), 7, "Player %d must start with 7 cards" % i)
	assert_gt(pub8["draw_pile_count"], 100, "8 players must auto-scale to multi-deck draw pile")

	# 16 players -> 4 decks (432 cards) -> 112 dealt + 1 discard = 319 remaining
	var p16 = _make_players(16)
	cartridge.init_match("m16", p16, {}, 42)
	cartridge.start_round()
	var pub16 = cartridge.get_public_state()
	assert_eq(pub16["players"].size(), 16, "16-player match must preserve all 16 players")
	for i in range(16):
		assert_eq(cartridge.get_player_card_count("p%d" % i), 7, "Player %d in 16p match must start with 7 cards" % i)
	assert_gt(pub16["draw_pile_count"], 250, "16 players must auto-scale to 4 decks")

func test_room_manager_unlimited_and_large_player_counts() -> void:
	var rm = _room_manager_script.new("", 0, "127.0.0.1", 8080, 8081)
	var tokens: Array[String] = []
	for i in range(12):
		var res = rm.allocate_player_seat("pid_%d" % i, "Player %d" % i)
		assert_true(res.get("success", false), "Unlimited room must allocate seat %d" % i)
		assert_eq(res.get("seat_index", -1), i, "Seat index must increment sequentially")
		tokens.append(str(res.get("reconnect_token", "")))

	assert_eq(rm.get_occupied_seat_count(), 12, "12 seats must be occupied")
	assert_false(rm.is_full(), "Unlimited room (max_players=0) must never report is_full()=true")

	# Reconnect test on high seat
	rm.disconnect_player(11)
	var rec = rm.reconnect_player(tokens[11])
	assert_true(rec.get("success", false), "Reconnect on seat 11 must succeed")
	assert_eq(rec.get("seat_index", -1), 11, "Reconnected seat index must be 11")

func test_dynamic_table_seat_positions_and_scaling() -> void:
	var scene = load(ARCADE_TABLE_PATH)
	assert_not_null(scene, "arcade_ps5.tscn must load")
	var table = scene.instantiate()
	add_child_autofree(table)

	assert_true(table.has_method("configure_for_player_count"), "TableTheme must expose configure_for_player_count()")
	table.configure_for_player_count(4, "full_3d", false)
	var base_scale = table.table_mesh.scale if "table_mesh" in table and table.table_mesh != null else Vector3.ONE

	table.configure_for_player_count(10, "full_3d", false)
	var scaled = table.table_mesh.scale if "table_mesh" in table and table.table_mesh != null else Vector3.ONE
	assert_gt(scaled.x, base_scale.x, "Table must grow wider when player count increases to 10")
	assert_gt(scaled.z, base_scale.z, "Table must grow deeper when player count increases to 10")

	var positions: Array[Vector3] = []
	for i in range(10):
		var pos = table.get_seat_position(i, 10, 0)
		assert_ne(pos, Vector3.ZERO, "Seat %d position must be valid" % i)
		for prev in positions:
			assert_gt(pos.distance_to(prev), 0.15, "Seats around table must not overlap")
		positions.append(pos)

	# Local seat 0 should sit at the front (+Z)
	assert_gt(positions[0].z, 0.3, "Local seat 0 should be positioned in front (+Z) of the table")

	# Verify 9+ players get generous table expansion and outer rim seat placement
	table.configure_for_player_count(9, "full_3d", false)
	var scale9 = table.get_table_scale()
	assert_gt(scale9, 1.5, "9-player table scale must expand generously (> 1.5)")
	var seat0_9 = table.get_seat_position(0, 9, 0)
	assert_gte(seat0_9.z, 0.50 * scale9 - 0.05, "Seat 0 must sit along the outer rim of the scaled table")
	var max_abs_x = 0.0
	for i in range(9):
		max_abs_x = maxf(max_abs_x, absf(table.get_seat_position(i, 9, 0).x))
	assert_gte(max_abs_x, 0.85 * scale9, "Side seats must sit near the outer table rim (~0.94 * scale)")
