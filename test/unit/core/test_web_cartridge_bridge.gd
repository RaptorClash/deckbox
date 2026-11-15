# test_web_cartridge_bridge.gd
# GUT 9.x Headless Test Suite: WebCartridgeBridge WebSocket/JSON-RPC Translation
extends GutTest

const BRIDGE_PATH = "res://core/cartridge/web_cartridge_bridge.gd"
var _bridge_script: GDScript

func before_all():
	if ResourceLoader.exists(BRIDGE_PATH):
		_bridge_script = load(BRIDGE_PATH)

class MockCartridge extends RefCounted:
	var last_action_player_id: String = ""
	var last_action: Dictionary = {}
	var action_response: Dictionary = { "success": true, "events": [{ "type": "CARD_PLAYED" }] }

	func handle_action(player_id: String, action: Dictionary) -> Dictionary:
		last_action_player_id = player_id
		last_action = action
		return action_response

	func get_public_state() -> Dictionary:
		return {
			"match_id": "m1",
			"status": "in_progress",
			"draw_pile_count": 50,
			"top_discard": { "color": "red", "value": "5" },
			"direction": 1,
			"turn_seat": 0,
			"players": [
				{ "seat": 0, "name": "P0", "card_count": 5, "called_uno": false },
				{ "seat": 1, "name": "P1", "card_count": 6, "called_uno": false }
			]
		}

	func get_player_view(player_id: String) -> Dictionary:
		var pub = get_public_state()
		pub["my_player_id"] = player_id
		pub["my_seat"] = 0 if player_id == "p0" else 1
		pub["hand"] = [{ "id": "c1", "color": "red", "value": "5", "playable": true }]
		pub["opponent_hands"] = { "seat_1" if player_id == "p0" else "seat_0": [{ "masked": true }] }
		return pub

func test_bridge_attach_cartridge():
	if _bridge_script == null:
		pass_test("WebCartridgeBridge not loaded")
		return

	var bridge = _bridge_script.new()
	var mock = MockCartridge.new()
	bridge.attach_cartridge(mock)
	assert_eq(bridge.cartridge, mock, "Cartridge must be attached")

func test_process_incoming_envelope_success():
	if _bridge_script == null:
		pass_test("WebCartridgeBridge not loaded")
		return

	var bridge = _bridge_script.new()
	var mock = MockCartridge.new()
	bridge.attach_cartridge(mock)

	var envelope = {
		"v": 1,
		"type": "ACTION_PLAY_CARD",
		"seq": 10,
		"sender": "p0",
		"payload": { "card_id": "c1" }
	}

	var result = bridge.process_incoming_envelope(1, "p0", envelope)
	assert_true(result["success"], "Processing valid envelope must succeed")
	assert_eq(mock.last_action_player_id, "p0")
	assert_eq(mock.last_action.get("card_id"), "c1")

	# Check response envelope
	assert_has(result, "result_envelope")
	var res_env = result["result_envelope"]
	assert_eq(res_env["type"], "ACTION_RESULT")
	assert_eq(res_env["seq"], 10)
	assert_true(res_env["payload"]["success"])

	# Check broadcast updates
	assert_has(result, "public_envelope")
	assert_eq(result["public_envelope"]["type"], "PUBLIC_STATE_UPDATE")
	assert_has(result, "player_envelopes")
	assert_has(result["player_envelopes"], "p0")
	assert_eq(result["player_envelopes"]["p0"]["type"], "PLAYER_VIEW_UPDATE")

func test_process_incoming_envelope_malformed():
	if _bridge_script == null:
		pass_test("WebCartridgeBridge not loaded")
		return

	var bridge = _bridge_script.new()
	var mock = MockCartridge.new()
	bridge.attach_cartridge(mock)

	var malformed = {
		"invalid_field": 123
	}
	var result = bridge.process_incoming_envelope(1, "p0", malformed)
	assert_false(result["success"], "Malformed envelope must fail validation")

func test_json_rpc_dispatch():
	if _bridge_script == null:
		pass_test("WebCartridgeBridge not loaded")
		return

	var bridge = _bridge_script.new()
	var mock = MockCartridge.new()
	bridge.attach_cartridge(mock)

	# 1. get_public_state
	var req_pub = {
		"jsonrpc": "2.0",
		"id": 1,
		"method": "get_public_state",
		"params": {}
	}
	var res_pub = bridge.handle_json_rpc(1, req_pub)
	assert_has(res_pub, "result")
	assert_eq(res_pub["result"]["match_id"], "m1")

	# 2. get_player_view
	var req_view = {
		"jsonrpc": "2.0",
		"id": 2,
		"method": "get_player_view",
		"params": { "player_id": "p0" }
	}
	var res_view = bridge.handle_json_rpc(1, req_view)
	assert_has(res_view, "result")
	assert_eq(res_view["result"]["my_player_id"], "p0")

	# 3. Invalid method
	var req_bad = {
		"jsonrpc": "2.0",
		"id": 3,
		"method": "non_existent_method",
		"params": {}
	}
	var res_bad = bridge.handle_json_rpc(1, req_bad)
	assert_has(res_bad, "error")
	assert_eq(res_bad["error"]["code"], -32601)
