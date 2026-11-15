# lan_discovery.gd
# UDP broadcast announcer and listener on subnet for zero-cloud LAN room discovery
class_name LanDiscovery
extends RefCounted

signal room_found(room: Dictionary)
signal room_updated(room: Dictionary)
signal room_expired(room_code: String)

const DEFAULT_LAN_PORT: int = 42424
const MAGIC_BEACON: String = "DECKBOX_LAN_BEACON"

var _announcer_udp: PacketPeerUDP = null
var _listener_udp: PacketPeerUDP = null
var _is_broadcasting: bool = false
var _is_listening: bool = false
var _broadcast_interval_ms: int = 1500
var _last_broadcast_ms: int = 0
var _room_info: Dictionary = {}

# room_code -> Dictionary
var _discovered_rooms: Dictionary = {}

func build_beacon_packet(room_info: Dictionary) -> PackedByteArray:
	var payload = {
		"magic": MAGIC_BEACON,
		"room_code": str(room_info.get("room_code", "")),
		"game_id": str(room_info.get("game_id", "uno")),
		"host_name": str(room_info.get("host_name", "DeckBox Host")),
		"app_version": str(room_info.get("app_version", "0.1.0")),
		"http_port": int(room_info.get("http_port", 8080)),
		"ws_port": int(room_info.get("ws_port", 8081)),
		"players_count": int(room_info.get("players_count", 0)),
		"max_players": int(room_info.get("max_players", 4)),
		"rules_hash": str(room_info.get("rules_hash", "")),
		"timestamp_ms": int(Time.get_unix_time_from_system() * 1000)
	}
	return JSON.stringify(payload).to_utf8_buffer()

func parse_beacon_packet(bytes: PackedByteArray) -> Dictionary:
	var json_str = bytes.get_string_from_utf8()
	var json = JSON.new()
	if json.parse(json_str) != OK or not (json.data is Dictionary):
		return { "valid": false, "error": "Invalid JSON" }

	var data: Dictionary = json.data
	if data.get("magic") != MAGIC_BEACON:
		return { "valid": false, "error": "Magic beacon mismatch" }

	var code = str(data.get("room_code", "")).strip_edges()
	if code.is_empty():
		return { "valid": false, "error": "Empty room code" }

	data["valid"] = true
	return data

func start_broadcasting(room_info: Dictionary, interval_ms: int = 1500) -> Error:
	if _is_broadcasting:
		stop_broadcasting()

	_room_info = room_info
	_broadcast_interval_ms = interval_ms

	_announcer_udp = PacketPeerUDP.new()
	_announcer_udp.set_broadcast_enabled(true)
	var err = _announcer_udp.set_dest_address("255.255.255.255", DEFAULT_LAN_PORT)
	if err != OK:
		return err

	_is_broadcasting = true
	_send_broadcast()
	return OK

func update_room_info(room_info: Dictionary) -> void:
	_room_info = room_info

func stop_broadcasting() -> void:
	if not _is_broadcasting:
		return
	if _announcer_udp != null:
		_announcer_udp.close()
		_announcer_udp = null
	_is_broadcasting = false

func start_listening(port: int = DEFAULT_LAN_PORT) -> Error:
	if _is_listening:
		stop_listening()

	_listener_udp = PacketPeerUDP.new()
	var err = _listener_udp.bind(port, "*")
	if err != OK:
		return err

	_is_listening = true
	return OK

func stop_listening() -> void:
	if not _is_listening:
		return
	if _listener_udp != null:
		_listener_udp.close()
		_listener_udp = null
	_is_listening = false
	_discovered_rooms.clear()

func upsert_discovered_room(room_info: Dictionary) -> void:
	var code = str(room_info.get("room_code", ""))
	if code.is_empty():
		return

	if not room_info.has("last_seen_ms"):
		room_info["last_seen_ms"] = int(Time.get_unix_time_from_system() * 1000)

	var is_new = not _discovered_rooms.has(code)
	_discovered_rooms[code] = room_info

	if is_new:
		room_found.emit(room_info)
	else:
		room_updated.emit(room_info)

func prune_expired_rooms(timeout_ms: int = 5000, current_time_ms: int = -1) -> void:
	var now = current_time_ms if current_time_ms >= 0 else int(Time.get_unix_time_from_system() * 1000)
	var to_remove: Array[String] = []

	for code in _discovered_rooms.keys():
		var room = _discovered_rooms[code]
		var last_seen = int(room.get("last_seen_ms", 0))
		if now - last_seen > timeout_ms:
			to_remove.append(code)

	for code in to_remove:
		_discovered_rooms.erase(code)
		room_expired.emit(code)

func get_discovered_rooms() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for k in _discovered_rooms.keys():
		list.append(_discovered_rooms[k].duplicate(true))
	return list

func poll() -> void:
	var now = int(Time.get_unix_time_from_system() * 1000)

	# Broadcast tick
	if _is_broadcasting and now - _last_broadcast_ms >= _broadcast_interval_ms:
		_send_broadcast()

	# Listen tick
	if _is_listening and _listener_udp != null:
		while _listener_udp.get_available_packet_count() > 0:
			var pkt = _listener_udp.get_packet()
			var ip = _listener_udp.get_packet_ip()
			# Filter own loopback
			if ip != "127.0.0.1":
				var parsed = parse_beacon_packet(pkt)
				if parsed.get("valid", false):
					parsed["host_ip"] = ip
					parsed["last_seen_ms"] = now
					upsert_discovered_room(parsed)

		prune_expired_rooms(5000, now)

func _send_broadcast() -> void:
	if _announcer_udp == null:
		return
	var packet_bytes = build_beacon_packet(_room_info)
	_announcer_udp.put_packet(packet_bytes)
	_last_broadcast_ms = int(Time.get_unix_time_from_system() * 1000)
