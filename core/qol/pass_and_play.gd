# core/qol/pass_and_play.gd
# Manages single-device hot-seat multiplayer with privacy curtain and masked hand states.
class_name PassAndPlayController extends RefCounted

signal curtain_state_changed(is_active: bool, player_id: String)
signal turn_transferred(seat_index: int, player_id: String)

enum CurtainState {
	REVEALED,
	CURTAIN_DOWN,
	PEEKING
}

var curtain_state: CurtainState = CurtainState.CURTAIN_DOWN
var players: Array[Dictionary] = []
var active_seat: int = 0
var target_player_id: String = ""
var hold_to_peek: bool = false
var auto_hide_on_turn_end: bool = true

func init_session(p_players: Array, starting_seat: int = 0) -> void:
	players.clear()
	for p in p_players:
		if p is Dictionary:
			players.append(p)
	active_seat = starting_seat
	if not players.is_empty() and active_seat >= 0 and active_seat < players.size():
		target_player_id = str(players[active_seat].get("player_id", ""))
	else:
		target_player_id = ""
	curtain_state = CurtainState.CURTAIN_DOWN
	curtain_state_changed.emit(true, target_player_id)

func advance_to_seat(seat: int, player_id: String = "", is_bot: bool = false) -> void:
	active_seat = seat
	if not player_id.is_empty():
		target_player_id = player_id
	elif active_seat >= 0 and active_seat < players.size():
		target_player_id = str(players[active_seat].get("player_id", ""))

	# If next player is bot, curtain is not needed; otherwise always engage curtain
	if is_bot:
		curtain_state = CurtainState.REVEALED
	else:
		curtain_state = CurtainState.CURTAIN_DOWN

	turn_transferred.emit(active_seat, target_player_id)
	curtain_state_changed.emit(curtain_state == CurtainState.CURTAIN_DOWN, target_player_id)

func request_reveal(player_id: String) -> Dictionary:
	if player_id != target_player_id:
		return {
			"success": false,
			"error": "UNAUTHORIZED_REVEAL: Player %s is not the active turn holder (%s)" % [player_id, target_player_id]
		}
	curtain_state = CurtainState.REVEALED
	curtain_state_changed.emit(false, target_player_id)
	return {"success": true, "player_id": player_id}

func hide_hand() -> void:
	curtain_state = CurtainState.CURTAIN_DOWN
	curtain_state_changed.emit(true, target_player_id)

func begin_peek(player_id: String) -> bool:
	if player_id != target_player_id:
		return false
	curtain_state = CurtainState.PEEKING
	curtain_state_changed.emit(false, target_player_id)
	return true

func end_peek() -> void:
	if curtain_state == CurtainState.PEEKING:
		curtain_state = CurtainState.CURTAIN_DOWN
		curtain_state_changed.emit(true, target_player_id)

func is_curtain_active() -> bool:
	return curtain_state == CurtainState.CURTAIN_DOWN

func get_active_seat() -> int:
	return active_seat

func get_active_player_id() -> String:
	return target_player_id

func filter_view_for_curtain(player_view: Dictionary) -> Dictionary:
	var view = player_view.duplicate(true)
	if is_curtain_active():
		var hand = view.get("hand", [])
		var masked_hand: Array = []
		for card in hand:
			masked_hand.append({
				"masked": true,
				"playable": false
			})
		view["hand"] = masked_hand
		if view.has("my_hand"):
			var masked_my_hand: Array = []
			for card in view.get("my_hand", []):
				masked_my_hand.append({
					"masked": true,
					"playable": false
				})
			view["my_hand"] = masked_my_hand
		view["hand_hidden"] = true
		view["curtain_active"] = true
		view["prompt"] = "Pass device to %s. Tap to reveal." % target_player_id
	else:
		view["hand_hidden"] = false
		view["curtain_active"] = false
	return view

func execute_player_action(cartridge, player_id: String, action: Dictionary) -> Dictionary:
	if player_id != target_player_id:
		return {
			"success": false,
			"error": "UNAUTHORIZED_ACTION: Player %s is not the active hot-seat turn holder (%s)" % [player_id, target_player_id]
		}
	if is_curtain_active():
		return {
			"success": false,
			"error": "CURTAIN_ACTIVE_ACTION_BLOCKED: Must reveal hand before playing action."
		}
	if cartridge != null and cartridge.has_method("handle_action"):
		var res = cartridge.handle_action(player_id, action)
		if auto_hide_on_turn_end:
			# If action resulted in turn advancing, curtain will re-engage on next advance_to_seat
			pass
		return res
	return {"success": false, "error": "Invalid cartridge"}
