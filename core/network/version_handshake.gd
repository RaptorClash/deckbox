# version_handshake.gd
# Version-locked handshake evaluator with web fallback negotiation
class_name VersionHandshake
extends RefCounted

const DEFAULT_PROTOCOL_VERSION: int = 1
const DEFAULT_APP_VERSION: String = "0.1.0"

var host_config: Dictionary = {
	"app_version": DEFAULT_APP_VERSION,
	"protocol_version": DEFAULT_PROTOCOL_VERSION,
	"rules_hash": "",
	"room_code": "",
	"host_ip": "127.0.0.1",
	"http_port": 8080,
	"max_players": 4
}

var _seats: Dictionary = {} # seat_index -> { "player_id": String, "reconnect_token": String }
var _reconnect_tokens: Dictionary = {} # reconnect_token -> seat_index
var _spectators: Array[String] = []
var _table_displays: Array[String] = []

func configure_host(config: Dictionary) -> void:
	for key in config.keys():
		host_config[key] = config[key]

func evaluate_join_request(request: Variant) -> Dictionary:
	var response_seq: int = 1
	var sender: String = ""

	if not (request is Dictionary) or request.is_empty():
		return _build_response("REJECTED_MALFORMED", response_seq, sender, { "error": "Empty request" })

	response_seq = request.get("seq", 0) + 1
	sender = request.get("sender", "")

	if not request.has("payload") or not (request["payload"] is Dictionary):
		return _build_response("REJECTED_MALFORMED", response_seq, sender, { "error": "Missing payload" })

	if sender.is_empty():
		return _build_response("REJECTED_MISSING_SENDER", response_seq, sender, { "error": "Missing sender" })

	var payload: Dictionary = request["payload"]

	# 1. Protocol version validation
	var client_protocol = payload.get("protocol_version", 0)
	if client_protocol != host_config.get("protocol_version", DEFAULT_PROTOCOL_VERSION):
		return _build_response("REJECTED_PROTOCOL_MISMATCH", response_seq, sender, {
			"host_version": host_config.get("app_version", DEFAULT_APP_VERSION),
			"required_protocol": host_config.get("protocol_version", DEFAULT_PROTOCOL_VERSION),
			"client_protocol": client_protocol,
			"web_fallback_url": _generate_fallback_url(payload.get("role", "player"))
		})

	# 2. App SemVer validation
	var client_app_version = str(payload.get("app_version", ""))
	var host_app_version = str(host_config.get("app_version", DEFAULT_APP_VERSION))
	if client_app_version != host_app_version:
		return _build_response("REJECTED_VERSION_MISMATCH", response_seq, sender, {
			"host_version": host_app_version,
			"client_version": client_app_version,
			"web_fallback_url": _generate_fallback_url(payload.get("role", "player"))
		})

	# 3. Rules Hash validation
	var client_rules_hash = str(payload.get("rules_hash", ""))
	var host_rules_hash = str(host_config.get("rules_hash", ""))
	if not host_rules_hash.is_empty() and client_rules_hash != host_rules_hash:
		return _build_response("REJECTED_RULES_MISMATCH", response_seq, sender, {
			"host_version": host_app_version,
			"required_rules_hash": host_rules_hash,
			"client_rules_hash": client_rules_hash
		})

	# 4. Role Assignment & Seat Allocation
	var role: String = payload.get("role", "player")
	var reconnect_token: String = payload.get("reconnect_token", "")

	match role:
		"table":
			if not _table_displays.has(sender):
				_table_displays.append(sender)
			return _build_response("ACCEPTED", response_seq, sender, {
				"role": "table",
				"seat_index": -1,
				"room_code": host_config.get("room_code", "")
			})
		"spectator":
			if not _spectators.has(sender):
				_spectators.append(sender)
			return _build_response("ACCEPTED", response_seq, sender, {
				"role": "spectator",
				"seat_index": -1,
				"room_code": host_config.get("room_code", "")
			})
		"player":
			# Reconnect flow
			if not reconnect_token.is_empty() and _reconnect_tokens.has(reconnect_token):
				var seat_idx = _reconnect_tokens[reconnect_token]
				_seats[seat_idx]["player_id"] = sender
				return _build_response("ACCEPTED", response_seq, sender, {
					"role": "player",
					"seat_index": seat_idx,
					"reconnect_token": reconnect_token,
					"room_code": host_config.get("room_code", "")
				})

			# New seat allocation
			var seat = _find_free_seat()
			if seat < 0:
				return _build_response("REJECTED_ROOM_FULL", response_seq, sender, { "error": "Room full" })

			var new_token = Crypto.new().generate_random_bytes(16).hex_encode()
			_seats[seat] = { "player_id": sender, "reconnect_token": new_token }
			_reconnect_tokens[new_token] = seat

			return _build_response("ACCEPTED", response_seq, sender, {
				"role": "player",
				"seat_index": seat,
				"reconnect_token": new_token,
				"room_code": host_config.get("room_code", "")
			})
		_:
			return _build_response("REJECTED_INVALID_ROLE", response_seq, sender, { "error": "Invalid role" })

func _generate_fallback_url(role: String) -> String:
	var ip = host_config.get("host_ip", "127.0.0.1")
	var port = host_config.get("http_port", 8080)
	var room = host_config.get("room_code", "")
	return "http://%s:%d/?room=%s&role=%s" % [ip, port, room, role]

func _find_free_seat() -> int:
	var max_p = int(host_config.get("max_players", 4))
	var limit = 999 if max_p <= 0 else max_p
	for s in range(limit):
		if not _seats.has(s):
			return s
	return -1

func _build_response(status: String, seq: int, recipient: String, extra_payload: Dictionary) -> Dictionary:
	var payload = { "status": status }
	for k in extra_payload.keys():
		payload[k] = extra_payload[k]
	return {
		"v": 1,
		"type": "JOIN_RESPONSE",
		"seq": seq,
		"sender": "host",
		"recipient": recipient,
		"timestamp": int(Time.get_unix_time_from_system()),
		"payload": payload
	}
