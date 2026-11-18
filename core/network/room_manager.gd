# room_manager.gd
# Room PIN generation, seat allocation, deep links, and session lifecycle
class_name RoomManager
extends RefCounted

enum RoomState { LOBBY, STARTING, IN_GAME, PAUSED, FINISHED, CLOSED }

const SAFE_ALPHANUM: String = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"

var room_code: String = ""
var state: RoomState = RoomState.LOBBY
var max_players: int = 4
var host_ip: String = "127.0.0.1"
var http_port: int = 8080
var ws_port: int = 8081

var seats: Dictionary = {} # seat_index (int) -> Dictionary
var token_to_seat: Dictionary = {} # token (String) -> seat_index (int)
var spectators: Dictionary = {} # client_id -> info
var table_clients: Dictionary = {} # client_id -> info

var _crypto: Crypto = Crypto.new()

func _init(p_room_code: String = "", p_max_players: int = 4, p_host_ip: String = "127.0.0.1", p_port: int = 8080, p_ws_port: int = 8081):
	room_code = p_room_code if not p_room_code.is_empty() else generate_room_code(4, true)
	max_players = p_max_players
	host_ip = p_host_ip
	http_port = p_port
	ws_port = p_ws_port

static func generate_room_code(length: int = 4, numeric_only: bool = true) -> String:
	var c = Crypto.new()
	var bytes = c.generate_random_bytes(length)
	var result: String = ""
	if numeric_only:
		for i in range(length):
			result += str(bytes[i] % 10)
	else:
		var alphalen = SAFE_ALPHANUM.length()
		for i in range(length):
			result += SAFE_ALPHANUM[bytes[i] % alphalen]
	return result

func get_deep_link_url(role: String = "player") -> String:
	return "http://%s:%d/?room=%s&role=%s" % [host_ip, http_port, room_code, role]

func allocate_player_seat(player_id: String, player_name: String, avatar_id: String = "default") -> Dictionary:
	var free_seat: int = -1
	if max_players <= 0:
		var s: int = 0
		while seats.has(s):
			s += 1
		free_seat = s
	else:
		for s in range(max_players):
			if not seats.has(s):
				free_seat = s
				break

	if free_seat < 0:
		return { "success": false, "error": "ROOM_FULL" }

	var token = _crypto.generate_random_bytes(16).hex_encode()
	seats[free_seat] = {
		"seat_index": free_seat,
		"player_id": player_id,
		"player_name": player_name,
		"avatar_id": avatar_id,
		"role": "player",
		"connected": true,
		"is_bot": false,
		"reconnect_token": token,
		"joined_at": int(Time.get_unix_time_from_system())
	}
	token_to_seat[token] = free_seat
	return {
		"success": true,
		"seat_index": free_seat,
		"reconnect_token": token,
		"room_code": room_code
	}

func reconnect_player(token: String, new_player_id: String = "") -> Dictionary:
	if not token_to_seat.has(token):
		return { "success": false, "error": "INVALID_TOKEN" }
	var seat_idx = token_to_seat[token]
	if not seats.has(seat_idx):
		return { "success": false, "error": "SEAT_NOT_FOUND" }

	var seat_data = seats[seat_idx]
	if not new_player_id.is_empty():
		seat_data["player_id"] = new_player_id
	seat_data["connected"] = true
	return {
		"success": true,
		"seat_index": seat_idx,
		"reconnect_token": token,
		"room_code": room_code
	}

func disconnect_player(seat_index: int) -> void:
	if seats.has(seat_index):
		seats[seat_index]["connected"] = false

func register_spectator(client_id: String, client_info: Dictionary = {}) -> void:
	spectators[client_id] = client_info

func unregister_spectator(client_id: String) -> void:
	spectators.erase(client_id)

func register_table_client(client_id: String, client_info: Dictionary = {}) -> void:
	table_clients[client_id] = client_info

func unregister_table_client(client_id: String) -> void:
	table_clients.erase(client_id)

func get_occupied_seat_count() -> int:
	return seats.size()

func is_full() -> bool:
	if max_players <= 0:
		return false
	return seats.size() >= max_players

func get_room_info() -> Dictionary:
	return {
		"room_code": room_code,
		"state": state,
		"max_players": max_players,
		"player_count": seats.size(),
		"spectator_count": spectators.size(),
		"table_count": table_clients.size(),
		"host_ip": host_ip,
		"http_port": http_port,
		"ws_port": ws_port
	}
