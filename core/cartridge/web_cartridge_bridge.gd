# web_cartridge_bridge.gd
# Bidirectional WebSocket / JSON-RPC Bridge between Headless Cartridges and Web Clients
class_name WebCartridgeBridge
extends RefCounted

var cartridge: RefCounted = null
var seq_counter: int = 1

func attach_cartridge(p_cartridge: RefCounted) -> void:
	cartridge = p_cartridge

func process_incoming_envelope(_peer_id: int, sender_player_id: String, envelope: Dictionary) -> Dictionary:
	# Validate standard envelope framing
	if not (envelope.has("v") and envelope.has("type") and envelope.has("seq") and envelope.has("sender") and envelope.has("payload")):
		return { "success": false, "error": "Malformed envelope structure: required fields v, type, seq, sender, payload" }

	if cartridge == null:
		return { "success": false, "error": "No cartridge attached to bridge" }

	var action_type = str(envelope.get("type", ""))
	var payload = envelope.get("payload", {})
	if not (payload is Dictionary):
		payload = {}

	var action = payload.duplicate(true)
	if not action.has("type"):
		action["type"] = action_type

	var action_res = cartridge.handle_action(sender_player_id, action)

	var result_envelope = {
		"v": 1,
		"type": "ACTION_RESULT",
		"seq": int(envelope.get("seq", 0)),
		"sender": "host",
		"timestamp": int(Time.get_unix_time_from_system()),
		"payload": action_res
	}

	var pub_state = cartridge.get_public_state() if cartridge.has_method("get_public_state") else {}
	var public_envelope = {
		"v": 1,
		"type": "PUBLIC_STATE_UPDATE",
		"seq": seq_counter,
		"sender": "host",
		"timestamp": int(Time.get_unix_time_from_system()),
		"payload": pub_state
	}
	seq_counter += 1

	var player_envelopes: Dictionary = {}
	var players_list = pub_state.get("players", [])
	for p in players_list:
		var p_id = str(p.get("player_id", ""))
		if not p_id.is_empty():
			player_envelopes[p_id] = {
				"v": 1,
				"type": "PLAYER_VIEW_UPDATE",
				"seq": seq_counter,
				"sender": "host",
				"timestamp": int(Time.get_unix_time_from_system()),
				"payload": cartridge.get_player_view(p_id) if cartridge.has_method("get_player_view") else {}
			}
			seq_counter += 1

	if not player_envelopes.has(sender_player_id) and not sender_player_id.is_empty():
		player_envelopes[sender_player_id] = {
			"v": 1,
			"type": "PLAYER_VIEW_UPDATE",
			"seq": seq_counter,
			"sender": "host",
			"timestamp": int(Time.get_unix_time_from_system()),
			"payload": cartridge.get_player_view(sender_player_id) if cartridge.has_method("get_player_view") else {}
		}
		seq_counter += 1

	return {
		"success": bool(action_res.get("success", false)),
		"result_envelope": result_envelope,
		"public_envelope": public_envelope,
		"player_envelopes": player_envelopes
	}

func handle_json_rpc(_peer_id: int, request: Dictionary) -> Dictionary:
	var rpc_id = request.get("id")
	var method = str(request.get("method", ""))
	var params = request.get("params", {})
	if not (params is Dictionary):
		params = {}

	if cartridge == null:
		return {
			"jsonrpc": "2.0",
			"id": rpc_id,
			"error": { "code": -32000, "message": "No cartridge attached" }
		}

	match method:
		"get_public_state":
			var pub = cartridge.get_public_state() if cartridge.has_method("get_public_state") else {}
			return { "jsonrpc": "2.0", "id": rpc_id, "result": pub }
		"get_player_view":
			var p_id = str(params.get("player_id", ""))
			var view = cartridge.get_player_view(p_id) if cartridge.has_method("get_player_view") else {}
			return { "jsonrpc": "2.0", "id": rpc_id, "result": view }
		"handle_action":
			var p_id = str(params.get("player_id", ""))
			var action = params.get("action", {})
			if not (action is Dictionary):
				action = {}
			var res = cartridge.handle_action(p_id, action)
			return { "jsonrpc": "2.0", "id": rpc_id, "result": res }
		_:
			return {
				"jsonrpc": "2.0",
				"id": rpc_id,
				"error": { "code": -32601, "message": "Method not found: %s" % method }
			}
