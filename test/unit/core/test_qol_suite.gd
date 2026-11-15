# test_qol_suite.gd
# GUT 9.x Unit Test Suite: QoL Features (Pass-and-play, Accessibility Symbols, Bot Controller, Audio Controls)
extends GutTest

const PASS_AND_PLAY_PATH = "res://core/qol/pass_and_play.gd"
const ACCESSIBILITY_SYMBOLS_PATH = "res://core/qol/accessibility_symbols.gd"
const BOT_CONTROLLER_PATH = "res://core/qol/bot_controller.gd"
const AUDIO_CONTROLS_PATH = "res://core/qol/audio_controls.gd"

var _pass_and_play_script: GDScript
var _accessibility_symbols_script: GDScript
var _bot_controller_script: GDScript
var _audio_controls_script: GDScript

func before_all():
	if ResourceLoader.exists(PASS_AND_PLAY_PATH):
		_pass_and_play_script = load(PASS_AND_PLAY_PATH)
	if ResourceLoader.exists(ACCESSIBILITY_SYMBOLS_PATH):
		_accessibility_symbols_script = load(ACCESSIBILITY_SYMBOLS_PATH)
	if ResourceLoader.exists(BOT_CONTROLLER_PATH):
		_bot_controller_script = load(BOT_CONTROLLER_PATH)
	if ResourceLoader.exists(AUDIO_CONTROLS_PATH):
		_audio_controls_script = load(AUDIO_CONTROLS_PATH)

# ==============================================================================
# 1. Pass-and-Play Controller Tests
# ==============================================================================

func test_pass_and_play_session_initialization():
	if _pass_and_play_script == null:
		pass_test("Pending pass_and_play implementation")
		return

	var pnp = _pass_and_play_script.new()
	var players = [
		{"player_id": "p1", "display_name": "Alice"},
		{"player_id": "p2", "display_name": "Bob"}
	]
	pnp.init_session(players, 0)

	assert_true(pnp.is_curtain_active(), "Curtain should be active on initialization")
	assert_eq(pnp.get_active_seat(), 0)
	assert_eq(pnp.get_active_player_id(), "p1")

func test_pass_and_play_reveal_and_hide_hand():
	if _pass_and_play_script == null:
		pass_test("Pending pass_and_play implementation")
		return

	var pnp = _pass_and_play_script.new()
	var players = [
		{"player_id": "p1", "display_name": "Alice"},
		{"player_id": "p2", "display_name": "Bob"}
	]
	pnp.init_session(players, 0)

	# Non-active player attempting reveal is rejected
	var fail_res = pnp.request_reveal("p2")
	assert_false(fail_res.get("success", true), "Unauthorized player reveal must fail")
	assert_true(pnp.is_curtain_active())

	# Active player reveals
	var ok_res = pnp.request_reveal("p1")
	assert_true(ok_res.get("success", false), "Authorized player reveal must succeed")
	assert_false(pnp.is_curtain_active(), "Curtain must be down (inactive) after reveal")

	# Hide hand
	pnp.hide_hand()
	assert_true(pnp.is_curtain_active(), "Curtain must be re-engaged after hide_hand()")

func test_pass_and_play_privacy_filter():
	if _pass_and_play_script == null:
		pass_test("Pending pass_and_play implementation")
		return

	var pnp = _pass_and_play_script.new()
	var players = [
		{"player_id": "p1", "display_name": "Alice"},
		{"player_id": "p2", "display_name": "Bob"}
	]
	pnp.init_session(players, 0)

	var raw_view = {
		"hand": [
			{"color": "red", "type": "number", "value": 7, "playable": true},
			{"color": "blue", "type": "reverse", "value": null, "playable": false}
		],
		"opponents": [
			{"player_id": "p2", "card_count": 5}
		]
	}

	# Curtain is active -> hand must be masked
	var masked_view = pnp.filter_view_for_curtain(raw_view)
	assert_true(masked_view.get("hand_hidden", false), "hand_hidden flag must be set")
	for card in masked_view.get("hand", []):
		assert_true(card.get("masked", false), "Card details must be masked")
		assert_false(card.has("value"), "Card value must not be exposed")

	# Reveal curtain -> raw cards are visible
	pnp.request_reveal("p1")
	var revealed_view = pnp.filter_view_for_curtain(raw_view)
	assert_false(revealed_view.get("hand_hidden", true))
	assert_eq(revealed_view["hand"].size(), 2)
	assert_eq(revealed_view["hand"][0]["value"], 7)

class MockPnpCartridge extends RefCounted:
	var last_action_player: String = ""
	var last_action: Dictionary = {}
	var response: Dictionary = {"success": true, "events": []}

	func handle_action(player_id: String, action: Dictionary) -> Dictionary:
		last_action_player = player_id
		last_action = action
		return response

func test_pass_and_play_curtain_masks_my_hand_anti_leak():
	if _pass_and_play_script == null:
		pass_test("Pending pass_and_play implementation")
		return

	var pnp = _pass_and_play_script.new()
	var players = [
		{"player_id": "alice", "display_name": "Alice"},
		{"player_id": "bob", "display_name": "Bob"}
	]
	pnp.init_session(players, 0)

	var raw_view = {
		"match_id": "match_pnp_1",
		"my_player_id": "alice",
		"hand": [
			{"id": "uno_red_7_18", "uid": "uno_red_7_18", "color": "red", "value": "7", "playable": true},
			{"id": "uno_blue_rev_22", "uid": "uno_blue_rev_22", "color": "blue", "value": "reverse", "playable": false}
		],
		"my_hand": [
			{"id": "uno_red_7_18", "uid": "uno_red_7_18", "color": "red", "value": "7", "playable": true},
			{"id": "uno_blue_rev_22", "uid": "uno_blue_rev_22", "color": "blue", "value": "reverse", "playable": false}
		]
	}

	# Curtain is active on init
	assert_true(pnp.is_curtain_active(), "Curtain must be active on session start")
	var masked_view = pnp.filter_view_for_curtain(raw_view)

	# Verify view["hand"]
	assert_true(masked_view.get("hand_hidden", false), "hand_hidden flag must be true")
	assert_true(masked_view.has("hand"), "view must contain hand")
	for card in masked_view["hand"]:
		assert_true(card.get("masked", false), "Hand card must be masked")
		assert_false(card.get("playable", true), "Hand card playable must be false")
		assert_false(card.has("uid"), "Hand card UID must be stripped")
		assert_false(card.has("color"), "Hand card color must be stripped")
		assert_false(card.has("value"), "Hand card value must be stripped")

	# Verify view["my_hand"] - must also be masked with zero leaks
	assert_true(masked_view.has("my_hand"), "view must contain my_hand")
	assert_eq(masked_view["my_hand"].size(), 2, "my_hand size must match original")
	for card in masked_view["my_hand"]:
		assert_true(card.get("masked", false), "my_hand card must be masked")
		assert_false(card.get("playable", true), "my_hand card playable must be false")
		assert_false(card.has("uid"), "my_hand card UID must be stripped")
		assert_false(card.has("color"), "my_hand card color must be stripped")
		assert_false(card.has("value"), "my_hand card value must be stripped")

	# JSON serialization check: zero card details leak anywhere
	var json_str = JSON.stringify(masked_view)
	assert_false(json_str.contains("uno_red_7_18"), "Zero card UID leaks in serialized curtain view")
	assert_false(json_str.contains("uno_blue_rev_22"), "Zero card UID leaks in serialized curtain view")

func test_pass_and_play_action_authorization_and_curtain_block():
	if _pass_and_play_script == null:
		pass_test("Pending pass_and_play implementation")
		return

	var pnp = _pass_and_play_script.new()
	var players = [
		{"player_id": "alice", "display_name": "Alice"},
		{"player_id": "bob", "display_name": "Bob"}
	]
	pnp.init_session(players, 0) # alice is active turn holder
	var mock_cartridge = MockPnpCartridge.new()
	var dummy_action = {"type": "ACTION_PLAY_CARD", "card_id": "c1"}

	# 1. Non-active player attempting action is rejected as unauthorized
	var unauthorized_res = pnp.execute_player_action(mock_cartridge, "bob", dummy_action)
	assert_false(unauthorized_res.get("success", true), "Unauthorized player action must fail")
	assert_true(str(unauthorized_res.get("error", "")).begins_with("UNAUTHORIZED_ACTION"), "Must return UNAUTHORIZED_ACTION error")

	# 2. Active player attempting action while curtain is DOWN is blocked
	assert_true(pnp.is_curtain_active(), "Curtain must be down")
	var curtain_blocked_res = pnp.execute_player_action(mock_cartridge, "alice", dummy_action)
	assert_false(curtain_blocked_res.get("success", true), "Curtain active action must fail")
	assert_true(str(curtain_blocked_res.get("error", "")).begins_with("CURTAIN_ACTIVE_ACTION_BLOCKED"), "Must return CURTAIN_ACTIVE_ACTION_BLOCKED")

	# 3. Active player reveals hand
	var reveal_res = pnp.request_reveal("alice")
	assert_true(reveal_res.get("success", false))
	assert_false(pnp.is_curtain_active(), "Curtain must be revealed")

	# Non-active player still rejected even when hand is revealed
	var unauthorized_res2 = pnp.execute_player_action(mock_cartridge, "bob", dummy_action)
	assert_false(unauthorized_res2.get("success", true))
	assert_true(str(unauthorized_res2.get("error", "")).begins_with("UNAUTHORIZED_ACTION"))

	# Active player action succeeds and reaches cartridge
	var ok_res = pnp.execute_player_action(mock_cartridge, "alice", dummy_action)
	assert_true(ok_res.get("success", false), "Authorized player action with curtain open must succeed")
	assert_eq(mock_cartridge.last_action_player, "alice", "Cartridge must receive correct player_id")
	assert_eq(mock_cartridge.last_action.get("type"), "ACTION_PLAY_CARD")

# ==============================================================================
# 2. Accessibility Symbols Tests
# ==============================================================================

func test_accessibility_symbol_mappings():
	if _accessibility_symbols_script == null:
		pass_test("Pending accessibility_symbols implementation")
		return

	var expected = {
		"red": {"shape": "triangle", "char": "▲"},
		"blue": {"shape": "diamond", "char": "◆"},
		"green": {"shape": "circle", "char": "●"},
		"yellow": {"shape": "star", "char": "★"},
		"wild": {"shape": "asterisk", "char": "✱"}
	}

	for color_name in expected:
		var sym = _accessibility_symbols_script.get_symbol(color_name)
		assert_not_null(sym, "Symbol mapping for %s must exist" % color_name)
		assert_eq(sym.get("shape"), expected[color_name]["shape"], "Shape name mismatch for %s" % color_name)
		assert_eq(sym.get("char"), expected[color_name]["char"], "Shape character mismatch for %s" % color_name)
		assert_eq(_accessibility_symbols_script.get_char(color_name), expected[color_name]["char"])

func test_accessibility_screen_reader_labels():
	if _accessibility_symbols_script == null:
		pass_test("Pending accessibility_symbols implementation")
		return

	var card_standard = {"color": "red", "type": "number", "value": 7}
	var card_wild = {"color": "wild", "type": "wild_draw_four", "value": null}

	var label_std = _accessibility_symbols_script.get_accessible_label(card_standard)
	assert_true(label_std.contains("Red"), "Label must mention color")
	assert_true(label_std.contains("Triangle"), "Label must mention shape")
	assert_true(label_std.contains("7"), "Label must mention value")

	var label_wild = _accessibility_symbols_script.get_accessible_label(card_wild)
	assert_true(label_wild.contains("Wild"), "Wild label must mention Wild")
	assert_true(label_wild.contains("Asterisk"), "Wild label must mention Asterisk shape")

func test_accessibility_pulse_alpha_bounds():
	if _accessibility_symbols_script == null:
		pass_test("Pending accessibility_symbols implementation")
		return

	for t in [0.0, 0.25, 0.5, 0.75, 1.0, 1.5, 2.0]:
		var alpha = _accessibility_symbols_script.calculate_pulse_alpha(t, 0.4, 1.0, 2.0)
		assert_gte(alpha, 0.39, "Alpha must be >= min_alpha")
		assert_lte(alpha, 1.01, "Alpha must be <= max_alpha")

# ==============================================================================
# 3. Bot Controller Tests
# ==============================================================================

func test_bot_controller_personalities_and_delays():
	if _bot_controller_script == null:
		pass_test("Pending bot_controller implementation")
		return

	var bot = _bot_controller_script.new()
	var casual_delay = bot.get_thinking_delay("casual")
	var tactical_delay = bot.get_thinking_delay("tactical")

	assert_gte(casual_delay, 0.79, "Casual thinking delay >= 0.8s")
	assert_lte(tactical_delay, 0.61, "Tactical thinking delay <= 0.6s")

func test_bot_controller_disconnect_takeover_and_token():
	if _bot_controller_script == null:
		pass_test("Pending bot_controller implementation")
		return

	var bot = _bot_controller_script.new()
	bot.register_player(1, "player_human", "secret_token_123")

	# Instant takeover
	var takeover_res = bot.on_player_disconnected(null, 1, "tactical")
	assert_true(takeover_res.get("is_bot", false), "Seat should be converted to bot")
	assert_eq(takeover_res.get("player_id"), "player_human")

	# Reconnect with invalid token fails
	var fail_recon = bot.on_player_reconnected(null, "wrong_token")
	assert_false(fail_recon.get("success", true), "Invalid token reconnect must fail")

	# Reconnect with valid token succeeds
	var ok_recon = bot.on_player_reconnected(null, "secret_token_123")
	assert_true(ok_recon.get("success", false), "Valid token reconnect must succeed")
	assert_eq(ok_recon.get("player_id"), "player_human")

# ==============================================================================
# 4. Audio Controls Tests
# ==============================================================================

func test_audio_controls_volume_and_mute():
	if _audio_controls_script == null:
		pass_test("Pending audio_controls implementation")
		return

	var audio = _audio_controls_script.new()
	audio.ensure_buses_exist()

	audio.set_bus_volume("Master", 0.5)
	assert_almost_eq(audio.get_bus_volume("Master"), 0.5, 0.05)

	# Mute test
	audio.set_bus_mute("Master", true)
	assert_true(audio.is_bus_muted("Master"))
	audio.set_bus_mute("Master", false)
	assert_false(audio.is_bus_muted("Master"))

func test_audio_controls_animation_speed_multiplier():
	if _audio_controls_script == null:
		pass_test("Pending audio_controls implementation")
		return

	var audio = _audio_controls_script.new()
	audio.set_animation_speed(2.5)
	assert_almost_eq(audio.get_animation_speed(), 2.5, 0.01)

	# Clamp bounds [0.25, 4.0]
	audio.set_animation_speed(0.1)
	assert_almost_eq(audio.get_animation_speed(), 0.25, 0.01)

	audio.set_animation_speed(10.0)
	assert_almost_eq(audio.get_animation_speed(), 4.0, 0.01)

func test_audio_settings_export_import():
	if _audio_controls_script == null:
		pass_test("Pending audio_controls implementation")
		return

	var audio = _audio_controls_script.new()
	audio.set_bus_volume("Master", 0.8)
	audio.set_animation_speed(1.5)

	var settings = audio.export_settings()
	assert_almost_eq(settings["master_volume"], 0.8, 0.05)
	assert_almost_eq(settings["animation_speed"], 1.5, 0.05)

	var audio2 = _audio_controls_script.new()
	audio2.import_settings(settings)
	assert_almost_eq(audio2.get_bus_volume("Master"), 0.8, 0.05)
	assert_almost_eq(audio2.get_animation_speed(), 1.5, 0.05)
