# core/qol/bot_controller.gd
# Bot AI personality controller, instant disconnect takeover, and reconnect token handoff.
class_name BotController extends RefCounted

signal bot_took_over(seat_index: int, player_id: String)
signal player_restored(seat_index: int, player_id: String)

var _registered_seats: Dictionary = {} # seat_index -> {"player_id": id, "token": token}
var _active_takeovers: Dictionary = {}  # seat_index -> {"player_id": id, "token": token, "difficulty": diff}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _init() -> void:
	_rng.randomize()

func register_player(seat_index: int, player_id: String, reconnect_token: String) -> void:
	_registered_seats[seat_index] = {
		"player_id": player_id,
		"token": reconnect_token
	}

func on_player_disconnected(cartridge, seat_index: int, difficulty: String = "tactical") -> Dictionary:
	var reg = _registered_seats.get(seat_index, {})
	var player_id = str(reg.get("player_id", "seat_%d" % seat_index))
	var token = str(reg.get("token", ""))

	_active_takeovers[seat_index] = {
		"player_id": player_id,
		"token": token,
		"difficulty": difficulty
	}

	if cartridge != null and cartridge.has_method("set_player_connected"):
		cartridge.set_player_connected(player_id, false)

	bot_took_over.emit(seat_index, player_id)

	return {
		"seat_index": seat_index,
		"player_id": player_id,
		"is_bot": true,
		"difficulty": difficulty
	}

func on_player_reconnected(cartridge, reconnect_token: String, new_player_id: String = "") -> Dictionary:
	if reconnect_token.is_empty():
		return {"success": false, "error": "EMPTY_TOKEN"}

	for seat in _active_takeovers:
		var takeover = _active_takeovers[seat]
		if takeover.get("token") == reconnect_token:
			var orig_id = takeover.get("player_id")
			_active_takeovers.erase(seat)

			if cartridge != null and cartridge.has_method("handle_reconnect"):
				cartridge.handle_reconnect(orig_id, reconnect_token)
			elif cartridge != null and cartridge.has_method("set_player_connected"):
				cartridge.set_player_connected(orig_id, true)

			player_restored.emit(seat, orig_id)
			return {
				"success": true,
				"seat_index": seat,
				"player_id": orig_id
			}

	return {"success": false, "error": "INVALID_RECONNECT_TOKEN"}

func get_thinking_delay(difficulty: String) -> float:
	match difficulty.to_lower():
		"casual":
			return _rng.randf_range(0.8, 1.4)
		"tactical", _:
			return _rng.randf_range(0.3, 0.6)

func evaluate_bot_move(cartridge, player_id: String, difficulty: String = "tactical") -> Dictionary:
	if cartridge == null:
		return {"action": "draw"}

	if cartridge.has_method("get_bot_action"):
		return cartridge.get_bot_action(player_id, difficulty)

	return {"action": "draw"}
