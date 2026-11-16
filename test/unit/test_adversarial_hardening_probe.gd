# test_adversarial_hardening_probe.gd
# GUT 9.x Headless Test Suite: Tier 5 Empirical Adversarial Hardening Probe
# Probes Godot Core, Uno Cartridge, Anti-Leak Security, Card Packs, Persistence & Network
extends GutTest

const UNO_CARTRIDGE_PATH = "res://games/uno/uno_cartridge.gd"
const ANTI_LEAK_FILTER_PATH = "res://core/security/anti_leak_filter.gd"
const CARD_PACK_SCHEMA_PATH = "res://core/packs/card_pack_schema.gd"
const CARD_PACK_MANAGER_PATH = "res://core/packs/card_pack_manager.gd"
const CUSTOM_INTERPRETER_PATH = "res://core/packs/custom_card_interpreter.gd"
const BACKUP_SERVICE_PATH = "res://core/profile/backup_service.gd"
const PROFILE_SERVICE_PATH = "res://core/profile/profile_service.gd"
const STATS_SERVICE_PATH = "res://core/stats/stats_service.gd"
const VERSION_HANDSHAKE_PATH = "res://core/network/version_handshake.gd"
const VECTOR_CHARTS_PATH = "res://core/stats/vector_charts.gd"

var _uno_cartridge_script: GDScript
var _anti_leak_script: GDScript
var _pack_schema_script: GDScript
var _pack_manager_script: GDScript
var _interpreter_script: GDScript
var _backup_script: GDScript
var _profile_script: GDScript
var _stats_script: GDScript
var _handshake_script: GDScript
var _vector_charts_script: GDScript

func before_all():
	if ResourceLoader.exists(UNO_CARTRIDGE_PATH):
		_uno_cartridge_script = load(UNO_CARTRIDGE_PATH)
	if ResourceLoader.exists(ANTI_LEAK_FILTER_PATH):
		_anti_leak_script = load(ANTI_LEAK_FILTER_PATH)
	if ResourceLoader.exists(CARD_PACK_SCHEMA_PATH):
		_pack_schema_script = load(CARD_PACK_SCHEMA_PATH)
	if ResourceLoader.exists(CARD_PACK_MANAGER_PATH):
		_pack_manager_script = load(CARD_PACK_MANAGER_PATH)
	if ResourceLoader.exists(CUSTOM_INTERPRETER_PATH):
		_interpreter_script = load(CUSTOM_INTERPRETER_PATH)
	if ResourceLoader.exists(BACKUP_SERVICE_PATH):
		_backup_script = load(BACKUP_SERVICE_PATH)
	if ResourceLoader.exists(PROFILE_SERVICE_PATH):
		_profile_script = load(PROFILE_SERVICE_PATH)
	if ResourceLoader.exists(STATS_SERVICE_PATH):
		_stats_script = load(STATS_SERVICE_PATH)
	if ResourceLoader.exists(VERSION_HANDSHAKE_PATH):
		_handshake_script = load(VERSION_HANDSHAKE_PATH)
	if ResourceLoader.exists(VECTOR_CHARTS_PATH):
		_vector_charts_script = load(VECTOR_CHARTS_PATH)

func _create_uno_match(player_count: int = 4, rules: Dictionary = {}, seed_val: int = 42) -> RefCounted:
	if _uno_cartridge_script == null:
		return null
	var inst = _uno_cartridge_script.new()
	var players: Array[Dictionary] = []
	for i in range(player_count):
		players.append({ "player_id": "player_%d" % i, "seat": i, "name": "Player %d" % i })
	inst.init_match("probe_match", players, rules, seed_val)
	inst.start_round()
	return inst

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

# ==============================================================================
# Domain 1: UNO Engine Action Timing, Special Cards & Wraparound
# ==============================================================================

## Probe 1: Direction wraparound, consecutive Skips & Reverses in 4-player game
func test_probe_uno_action_timing_consecutive_special_cards_and_wraparound():
	var game = _create_uno_match(4)
	assert_not_null(game, "UNO cartridge must instantiate")

	# Setup state:
	# P0 plays Skip -> P1 is skipped -> active becomes P2
	# P2 plays Reverse -> direction becomes -1 -> active becomes P1? Wait: (2 + (-1)) = 1!
	# P1 plays Skip (in reverse direction) -> P0 is skipped -> active becomes P3 ((1 + 2 * -1 + 4) % 4 = 3)
	game.debug_set_state({
		"top_discard": { "id": "t1", "uid": "t1", "color": "red", "value": "1" },
		"active_seat": 0,
		"direction": 1,
		"player_hands": {
			"player_0": [{ "id": "p0_s", "uid": "p0_s", "color": "red", "value": "skip" }],
			"player_1": [{ "id": "p1_s", "uid": "p1_s", "color": "red", "value": "skip" }],
			"player_2": [{ "id": "p2_r", "uid": "p2_r", "color": "red", "value": "reverse" }],
			"player_3": [{ "id": "p3_1", "uid": "p3_1", "color": "red", "value": "5" }]
		}
	})

	# Step 1: P0 plays Skip -> P1 is skipped, active seat must be 2
	var r0 = game.handle_action("player_0", { "type": "ACTION_PLAY_CARD", "card_id": "p0_s" })
	assert_true(r0.get("success", false), "P0 plays Skip")
	assert_eq(game.get_public_state()["current_turn_seat"], 2, "Seat 1 skipped, seat 2 active")

	# Step 2: P2 plays Reverse -> direction becomes -1, next seat is (2 + (-1)) % 4 = 1
	var r2 = game.handle_action("player_2", { "type": "ACTION_PLAY_CARD", "card_id": "p2_r" })
	assert_true(r2.get("success", false), "P2 plays Reverse")
	assert_eq(game.get_public_state()["direction"], -1, "Direction must be -1")
	assert_eq(game.get_public_state()["current_turn_seat"], 1, "Next seat in reverse must be 1")

	# Step 3: P1 plays Skip in reverse -> (1 + (-1 * 2) + 4) % 4 = 3 -> Seat 0 skipped, Seat 3 active!
	var r1 = game.handle_action("player_1", { "type": "ACTION_PLAY_CARD", "card_id": "p1_s" })
	assert_true(r1.get("success", false), "P1 plays Skip in reverse")
	assert_eq(game.get_public_state()["current_turn_seat"], 3, "Seat 0 skipped in reverse, seat 3 active")

## Probe 2: 2-Player Official Rules: Reverse acts as Skip (turn stays with player)
func test_probe_uno_two_player_official_rules_reverse_acts_as_skip():
	var game = _create_uno_match(2)
	assert_not_null(game, "UNO cartridge 2-player match")

	game.debug_set_state({
		"top_discard": { "id": "t1", "uid": "t1", "color": "blue", "value": "5" },
		"active_seat": 0,
		"direction": 1,
		"player_hands": {
			"player_0": [
				{ "id": "p0_rev", "uid": "p0_rev", "color": "blue", "value": "reverse" },
				{ "id": "p0_num", "uid": "p0_num", "color": "blue", "value": "7" }
			],
			"player_1": [
				{ "id": "p1_num", "uid": "p1_num", "color": "blue", "value": "2" }
			]
		}
	})

	# P0 plays Reverse in 2-player game: Turn STAYS at P0!
	var res = game.handle_action("player_0", { "type": "ACTION_PLAY_CARD", "card_id": "p0_rev" })
	assert_true(res.get("success", false), "P0 plays Reverse in 2-player game")
	assert_eq(game.get_public_state()["current_turn_seat"], 0, "In 2-player game, Reverse keeps turn at P0")

	# P0 immediately plays Blue 7 and wins the round!
	var res2 = game.handle_action("player_0", { "type": "ACTION_PLAY_CARD", "card_id": "p0_num" })
	assert_true(res2.get("success", false), "P0 plays remaining card")
	assert_true(game.is_round_over(), "P0 ran out of cards, round is over")
	assert_eq(game.get_round_results()["winner_seat"], 0, "P0 is the winner")

## Probe 3: Turn Timeout and Bot Takeover Loop Resilience
func test_probe_uno_turn_timeout_and_bot_takeover_resilience():
	var game = _create_uno_match(4)
	assert_not_null(game)

	# Simulate 12 consecutive timeouts across all seats
	for t in range(12):
		var active_seat_before = game.get_public_state()["current_turn_seat"]
		var active_id = game.get_active_player_id()
		var res = game.handle_timeout()
		assert_true(res.get("success", false), "Timeout %d should execute successfully" % t)
		var active_seat_after = game.get_public_state()["current_turn_seat"]
		assert_ne(active_seat_before, active_seat_after, "Turn must advance on timeout")

## Probe 4: Disconnect mid-match, bot takeover, and reconnect verification
func test_probe_uno_disconnect_takeover_and_reconnect():
	var game = _create_uno_match(4)
	assert_not_null(game)

	# Set reconnect token for player_1
	game.player_map["player_1"]["reconnect_token"] = "valid_tok_123"

	# Disconnect player_1
	game.set_player_connected("player_1", false)
	assert_true(game.player_map["player_1"]["is_bot"], "player_1 marked as bot upon disconnect")

	# Attempt reconnect with invalid token -> fails
	var bad_reconn = game.handle_reconnect("player_1", "invalid_token_xyz")
	assert_false(bad_reconn, "Reconnect with bad token must fail")
	assert_true(game.player_map["player_1"]["is_bot"], "Still marked as bot after failed reconnect")

	# Reconnect with correct token -> succeeds
	var good_reconn = game.handle_reconnect("player_1", "valid_tok_123")
	assert_true(good_reconn, "Reconnect with valid token must succeed")
	assert_false(game.player_map["player_1"]["is_bot"], "player_1 is no longer bot after reconnect")

## Probe 5: Jump-In Boundary & Illegality Rejections
func test_probe_uno_jump_in_adversarial_boundaries():
	# Match with jump_in disabled
	var game_disabled = _create_uno_match(4, { "jump_in": false })
	game_disabled.debug_set_state({
		"top_discard": { "id": "t", "uid": "t", "color": "green", "value": "4" },
		"active_seat": 0,
		"player_hands": {
			"player_1": [{ "id": "p1_g4", "uid": "p1_g4", "color": "green", "value": "4" }]
		}
	})
	var r_dis = game_disabled.handle_action("player_1", { "type": "ACTION_JUMP_IN", "card_id": "p1_g4" })
	assert_false(r_dis.get("success", true), "Jump-in must fail when house rule is disabled")

	# Match with jump_in enabled
	var game_enabled = _create_uno_match(4, { "jump_in": true })
	game_enabled.debug_set_state({
		"top_discard": { "id": "t", "uid": "t", "color": "green", "value": "4" },
		"active_seat": 0,
		"player_hands": {
			"player_1": [
				{ "id": "p1_r4", "uid": "p1_r4", "color": "red", "value": "4" }, # wrong color
				{ "id": "p1_w", "uid": "p1_w", "color": "wild", "value": "wild" }, # wild cannot jump in
				{ "id": "p1_g4", "uid": "p1_g4", "color": "green", "value": "4" }  # valid identical
			]
		}
	})

	# Mismatched color
	var r_bad_col = game_enabled.handle_action("player_1", { "type": "ACTION_JUMP_IN", "card_id": "p1_r4" })
	assert_false(r_bad_col.get("success", true), "Jump-in rejected for mismatched color")

	# Wild card jump in
	var r_wild = game_enabled.handle_action("player_1", { "type": "ACTION_JUMP_IN", "card_id": "p1_w" })
	assert_false(r_wild.get("success", true), "Jump-in rejected for Wild card")

	# Valid jump in succeeds
	var r_ok = game_enabled.handle_action("player_1", { "type": "ACTION_JUMP_IN", "card_id": "p1_g4" })
	assert_true(r_ok.get("success", false), "Valid identical Jump-In succeeds")
	assert_eq(game_enabled.get_public_state()["current_turn_seat"], 2, "Turn stolen; advances to seat 2")

# ==============================================================================
# Domain 2: Security & Anti-Leak Deep Recursive Invariant Probing
# ==============================================================================

## Probe 6: Deep Recursive Scan for Injected Malicious Fields & Tokens
func test_probe_security_anti_leak_deep_hierarchical_inspection():
	var game = _create_uno_match(4)
	assert_not_null(game)

	# Inject sensitive metadata into player_1's private cards
	var secret_token = "CRITICAL_SECRET_SALT_778899"
	game.player_hands["player_1"] = [
		{
			"id": "c_secret_01",
			"uid": "c_secret_01",
			"color": "red",
			"value": "7",
			"__private_salt__": secret_token,
			"database_id": 999999
		}
	]

	# 1. Inspect public state: MUST NOT leak secret token or card UID
	var pub_state = game.get_public_state()
	assert_false(_deep_search_for_string(pub_state, secret_token), "Public state must NEVER contain private salt")
	assert_false(_deep_search_for_string(pub_state, "c_secret_01"), "Public state must NEVER expose opponent card IDs")

	# 2. Inspect player_0's view (opponent to player_1): MUST NOT leak player_1's card or token
	var p0_view = game.get_player_view("player_0")
	assert_false(_deep_search_for_string(p0_view, secret_token), "Player 0 view must NEVER contain player 1's secret salt")
	assert_false(_deep_search_for_string(p0_view, "c_secret_01"), "Player 0 view must NEVER expose player 1's card ID")

	# Verify opponent hands structure in player_0's view
	var opp_hands = p0_view.get("opponent_hands", {})
	assert_has(opp_hands, "seat_1", "Opponent hands must contain seat_1")
	var seat1_tokens = opp_hands["seat_1"]
	assert_eq(seat1_tokens.size(), 1, "Seat 1 has 1 card")
	for token in seat1_tokens:
		assert_eq(token.keys(), ["masked"], "Token must contain strictly ['masked'] key")
		assert_true(token["masked"], "Token masked must be true")

# ==============================================================================
# Domain 3: Card Packs & Custom Action Sandbox Hardening
# ==============================================================================

## Probe 7: Comprehensive Zip Traversal & Unsafe Path Defense Matrix
func test_probe_card_pack_manager_adversarial_zip_traversal_matrix():
	var schema = _pack_schema_script
	assert_not_null(schema, "CardPackSchema must be loaded")

	var malicious_paths = [
		"../../escaped.txt",
		"..\\windows\\system32\\cmd.exe",
		"C:/Windows/win.ini",
		"C:\\boot.ini",
		"D:/secret.dat",
		"/etc/passwd",
		"/root/pwn.bin",
		"\\root\\pwn.bin",
		"assets/../../evil.png",
		"assets/..\\..\\evil.png",
		"valid.png\u0000.zip",
		"",
		"   ",
		"://network/path",
		"http://evil.com/payload.png"
	]

	for bad_path in malicious_paths:
		assert_false(schema.is_safe_relative_path(bad_path),
			"Unsafe path must be rejected by is_safe_relative_path: '%s'" % bad_path)

	# Legitimate safe relative paths must pass
	var safe_paths = [
		"cards/front_01.png",
		"backs/classic_blue.png",
		"textures/felt_green.png",
		"icons/star.png",
		"manifest.json"
	]

	for safe_path in safe_paths:
		assert_true(schema.is_safe_relative_path(safe_path),
			"Safe path must be accepted by is_safe_relative_path: '%s'" % safe_path)

## Probe 8: Card Pack Schema Validation Boundaries & Malformed Manifest Rejections
func test_probe_card_pack_schema_malformed_manifest_rejections():
	var schema = _pack_schema_script
	assert_not_null(schema)

	# 1. Non-dictionary input
	assert_false(schema.validate_pack("not a dict")["valid"])
	assert_false(schema.validate_pack([])["valid"])
	assert_false(schema.validate_pack(null)["valid"])

	# 2. Missing mandatory fields
	assert_false(schema.validate_pack({})["valid"], "Empty dict must fail validation")

	# 3. Invalid SemVer versions
	var pack_base = {
		"schema_version": 1,
		"id": "valid_pack_id",
		"name": "Valid Pack",
		"author": "Author",
		"version": "1.0.0"
	}
	for bad_ver in ["1", "1.0", "v1.0.0", "beta-1", "1.0.0.0"]:
		var p = pack_base.duplicate()
		p["version"] = bad_ver
		assert_false(schema.validate_pack(p)["valid"], "Invalid version '%s' must fail" % bad_ver)

	# 4. Prohibited action primitive types
	for bad_act in ["eval", "exec", "system", "os_command", "shell", "import"]:
		var act_res = schema.validate_action({ "type": bad_act })
		assert_false(act_res["valid"], "Prohibited action primitive '%s' must fail" % bad_act)

## Probe 9: Custom Card Interpreter Sandboxed Chaining & Boundary Testing
func test_probe_custom_card_interpreter_sandbox_boundaries():
	var interp = _interpreter_script
	assert_not_null(interp)

	# Test chained safe actions: Reverse, Skip, Draw Cards
	var actions = [
		{ "type": "reverse" },
		{ "type": "skip_next", "count": 1 },
		{ "type": "draw_cards", "count": 2, "target": "next" }
	]

	var context = {
		"player_count": 4,
		"current_seat": 0,
		"direction": 1,
		"draw_pile": [
			{ "id": "d1", "color": "red" },
			{ "id": "d2", "color": "blue" }
		],
		"hands": {
			0: [], 1: [], 2: [], 3: []
		}
	}

	var res = interp.execute_card_actions(actions, context)
	assert_true(res.get("success", false), "Chained actions must succeed")
	assert_eq(res["events"].size(), 3, "Must produce 3 events")
	assert_eq(context["direction"], -1, "Direction reversed to -1")
	assert_eq(context["skip_count"], 1, "Skip count incremented")
	# In direction -1, next seat from 0 is 3
	assert_eq(context["hands"][3].size(), 2, "Next seat (3) received 2 drawn cards")

# ==============================================================================
# Domain 4: Persistence, Stats & QoL Durability
# ==============================================================================

## Probe 10: Stats Service Div-by-Zero and History Capping
func test_probe_persistence_stats_div_by_zero_and_history_capping():
	var stats_svc = _stats_script.new()
	assert_not_null(stats_svc)

	# Clean state has 0 matches -> win_rate must be 0.0, not NaN or div-by-zero
	var summary = stats_svc.get_summary() if stats_svc.has_method("get_summary") else stats_svc._data["summary"]
	assert_eq(summary["total_matches"], 0)
	assert_eq(summary["win_rate"], 0.0, "Initial win rate must be 0.0")
	assert_eq(summary["average_match_duration"], 0.0, "Initial avg duration must be 0.0")

	# Flood with 550 match recordings to test MAX_MATCH_HISTORY (500) capping
	for i in range(550):
		stats_svc.record_match_result({
			"match_id": "match_%d" % i,
			"game_id": "uno",
			"result": "win" if i % 2 == 0 else "loss",
			"duration_seconds": 60,
			"my_player_id": "p0",
			"winner_id": "p0" if i % 2 == 0 else "p1",
			"opponents": ["p1"]
		})

	var history = stats_svc._data["match_history"]
	assert_eq(history.size(), 500, "Match history must be strictly capped at 500 entries")
	assert_eq(history[0]["match_id"], "match_549", "Most recent match at head of history")

## Probe 11: Vector Charts Boundary Values (Empty / Zero-Sum Data)
func test_probe_vector_charts_extreme_boundaries():
	if _vector_charts_script == null:
		pass_test("Vector charts script not found")
		return

	# DonutChart with empty data
	var donut = _vector_charts_script.DonutChart.new()
	donut.chart_data = []
	assert_eq(donut.get_total_value(), 0.0, "Empty donut total is 0.0")
	var angles_empty = donut.calculate_slice_angles()
	assert_eq(angles_empty.size(), 0, "Empty data produces 0 slice angles")

	# DonutChart with zero total sum (all values 0) -> must not divide by zero
	donut.chart_data = [
		{ "label": "Wins", "value": 0, "color": Color.GREEN },
		{ "label": "Losses", "value": 0, "color": Color.RED }
	]
	assert_eq(donut.get_total_value(), 0.0, "Total sum is 0.0")
	var angles_zero = donut.calculate_slice_angles()
	assert_eq(angles_zero.size(), 0, "Zero-sum data produces empty slice angles (avoids NaN)")

	# DonutChart with valid data
	donut.chart_data = [
		{ "label": "Wins", "value": 75, "color": Color.GREEN },
		{ "label": "Losses", "value": 25, "color": Color.RED }
	]
	assert_eq(donut.get_total_value(), 100.0, "Total is 100.0")
	var angles_valid = donut.calculate_slice_angles()
	assert_eq(angles_valid.size(), 2)
	assert_almost_eq(angles_valid[0] + angles_valid[1], TAU, 0.001, "Sum of angles equals TAU (360 deg)")

	# BarChart with empty & zero data: defaults to 1.0 to prevent division by zero in drawing logic
	var bar = _vector_charts_script.BarChart.new()
	bar.chart_data = []
	assert_eq(bar.get_max_value(), 1.0, "Empty bar chart returns safe scale 1.0 to prevent division by zero")

	bar.chart_data = [
		{ "label": "Uno", "value": 0 },
		{ "label": "Poker", "value": 0 }
	]
	assert_eq(bar.get_max_value(), 1.0, "Zero-value bar chart returns safe scale 1.0")

	bar.chart_data = [
		{ "label": "Uno", "value": 45 },
		{ "label": "Poker", "value": 15 }
	]
	assert_eq(bar.get_max_value(), 45.0, "Non-zero bar chart returns true maximum")

	donut.free()
	bar.free()

# ==============================================================================
# Domain 5: Network Handshake Boundary & Downgrade Rejection Matrix
# ==============================================================================

## Probe 12: Version Handshake Rejection Matrix & Seat Allocation
func test_probe_network_version_handshake_adversarial_matrix():
	var handshake = _handshake_script.new()
	assert_not_null(handshake)

	handshake.configure_host({
		"app_version": "0.1.0",
		"protocol_version": 1,
		"rules_hash": "RULES_HASH_ABC",
		"max_players": 2
	})

	# 1. Empty request
	var r_empty = handshake.evaluate_join_request({})
	assert_eq(r_empty["payload"]["status"], "REJECTED_MALFORMED")

	# 2. Missing sender
	var r_no_sender = handshake.evaluate_join_request({ "payload": {} })
	assert_eq(r_no_sender["payload"]["status"], "REJECTED_MISSING_SENDER")

	# 3. Protocol mismatch
	var r_proto = handshake.evaluate_join_request({
		"sender": "client_1",
		"payload": { "protocol_version": 99, "app_version": "0.1.0", "rules_hash": "RULES_HASH_ABC" }
	})
	assert_eq(r_proto["payload"]["status"], "REJECTED_PROTOCOL_MISMATCH")
	assert_has(r_proto["payload"], "web_fallback_url", "Must supply web fallback URL")

	# 4. App SemVer mismatch
	var r_ver = handshake.evaluate_join_request({
		"sender": "client_1",
		"payload": { "protocol_version": 1, "app_version": "0.9.9", "rules_hash": "RULES_HASH_ABC" }
	})
	assert_eq(r_ver["payload"]["status"], "REJECTED_VERSION_MISMATCH")
	assert_has(r_ver["payload"], "web_fallback_url", "Must supply web fallback URL")

	# 5. Rules hash mismatch
	var r_hash = handshake.evaluate_join_request({
		"sender": "client_1",
		"payload": { "protocol_version": 1, "app_version": "0.1.0", "rules_hash": "DIFFERENT_HASH" }
	})
	assert_eq(r_hash["payload"]["status"], "REJECTED_RULES_MISMATCH")

	# 6. Valid player 1 join
	var r_p1 = handshake.evaluate_join_request({
		"sender": "client_1",
		"payload": { "protocol_version": 1, "app_version": "0.1.0", "rules_hash": "RULES_HASH_ABC", "role": "player" }
	})
	assert_eq(r_p1["payload"]["status"], "ACCEPTED")
	assert_eq(r_p1["payload"]["seat_index"], 0)

	# 7. Valid player 2 join (room now full at max_players = 2)
	var r_p2 = handshake.evaluate_join_request({
		"sender": "client_2",
		"payload": { "protocol_version": 1, "app_version": "0.1.0", "rules_hash": "RULES_HASH_ABC", "role": "player" }
	})
	assert_eq(r_p2["payload"]["status"], "ACCEPTED")
	assert_eq(r_p2["payload"]["seat_index"], 1)

	# 8. 3rd player attempts to join -> REJECTED_ROOM_FULL
	var r_p3 = handshake.evaluate_join_request({
		"sender": "client_3",
		"payload": { "protocol_version": 1, "app_version": "0.1.0", "rules_hash": "RULES_HASH_ABC", "role": "player" }
	})
	assert_eq(r_p3["payload"]["status"], "REJECTED_ROOM_FULL")

	# 9. Spectator can still join full room
	var r_spec = handshake.evaluate_join_request({
		"sender": "spec_1",
		"payload": { "protocol_version": 1, "app_version": "0.1.0", "rules_hash": "RULES_HASH_ABC", "role": "spectator" }
	})
	assert_eq(r_spec["payload"]["status"], "ACCEPTED")
	assert_eq(r_spec["payload"]["role"], "spectator")
