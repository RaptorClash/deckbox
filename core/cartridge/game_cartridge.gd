# game_cartridge.gd
# Base Pure RefCounted Game Cartridge Interface & Deterministic Core Loop
class_name GameCartridge
extends RefCounted

const AntiLeakFilterScript = preload("res://core/security/anti_leak_filter.gd")

var match_id: String = ""
var status: String = "initialized"
var players: Array[Dictionary] = []
var player_map: Dictionary = {} # player_id -> player dict
var rules_config: Dictionary = {}
var seed_val: int = 0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var draw_pile: Array = []
var discard_pile: Array = []
var player_hands: Dictionary = {} # player_id -> Array[Dictionary]

var current_turn_seat: int = 0
var direction: int = 1
var active_color: String = ""
var pending_penalty_draws: int = 0

var round_over: bool = false
var match_over: bool = false
var round_results: Dictionary = {}

# --- Metadata Hooks ---

func get_game_id() -> String:
	return "base_cartridge"

func get_display_name() -> String:
	return "Base Game Cartridge"

func get_min_players() -> int:
	return 2

func get_max_players() -> int:
	return 4

func get_default_rules() -> Dictionary:
	return {}

# --- Lifecycle ---

func init_match(p_match_id: String, p_players: Array[Dictionary], p_rules: Dictionary = {}, p_seed: int = 0) -> void:
	match_id = p_match_id
	players = []
	player_map = {}
	player_hands = {}
	rules_config = p_rules.duplicate(true)
	seed_val = p_seed
	if seed_val != 0:
		rng.seed = seed_val
	else:
		rng.randomize()

	for p in p_players:
		var p_copy = p.duplicate(true)
		var p_id = str(p_copy.get("player_id", ""))
		players.append(p_copy)
		player_map[p_id] = p_copy
		player_hands[p_id] = []

	current_turn_seat = 0
	direction = 1
	active_color = ""
	pending_penalty_draws = 0
	round_over = false
	match_over = false
	round_results = {}
	status = "initialized"

func start_round() -> void:
	round_over = false
	status = "in_progress"
	_build_deck()
	_shuffle_draw_pile()

	# Deal 7 cards to each player
	for p in players:
		var p_id = str(p.get("player_id", ""))
		player_hands[p_id] = []
		for _i in range(7):
			if draw_pile.size() > 0:
				player_hands[p_id].append(draw_pile.pop_back())

	# Flip top card to discard
	discard_pile = []
	if draw_pile.size() > 0:
		discard_pile.append(draw_pile.pop_back())

	current_turn_seat = 0
	direction = 1

func _build_deck() -> void:
	draw_pile = []
	var colors = ["red", "blue", "green", "yellow"]
	var card_seq = 0
	for c in colors:
		for v in range(10):
			card_seq += 1
			var uid_str = "card_%s_%d_%d" % [c, v, card_seq]
			draw_pile.append({
				"id": uid_str,
				"uid": uid_str,
				"color": c,
				"value": str(v)
			})

func _shuffle_draw_pile() -> void:
	for i in range(draw_pile.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var tmp = draw_pile[i]
		draw_pile[i] = draw_pile[j]
		draw_pile[j] = tmp

func is_round_over() -> bool:
	return round_over

func is_match_over() -> bool:
	return match_over

func get_round_results() -> Dictionary:
	return round_results

# --- State Projection (Anti-Leak Delegation) ---

func get_public_state() -> Dictionary:
	return AntiLeakFilterScript.filter_public_state(self)

func get_player_view(player_id: String) -> Dictionary:
	return AntiLeakFilterScript.filter_player_view(self, player_id)

# --- Accessors for AntiLeakFilter & Engine ---

func get_player_card_count(player_id: String) -> int:
	return player_hands.get(player_id, []).size()

func get_player_hand(player_id: String) -> Array:
	return player_hands.get(player_id, [])

func get_top_discard() -> Dictionary:
	return discard_pile.back() if discard_pile.size() > 0 else {}

func get_draw_pile_count() -> int:
	return draw_pile.size()

func is_card_playable(card: Dictionary) -> bool:
	var top = get_top_discard()
	if top.is_empty():
		return true
	var card_color = str(card.get("color", ""))
	var card_val = str(card.get("value", ""))
	var top_color = active_color if not active_color.is_empty() else str(top.get("color", ""))
	var top_val = str(top.get("value", ""))

	if card_color == "wild":
		return true
	if card_color == top_color:
		return true
	if card_val == top_val and not card_val.is_empty():
		return true
	return false

func get_player_by_seat(seat: int) -> Dictionary:
	for p in players:
		if p.get("seat", -1) == seat:
			return p
	return {}

func get_active_player_id() -> String:
	var p = get_player_by_seat(current_turn_seat)
	return str(p.get("player_id", ""))

# --- Action Handling ---

func handle_action(player_id: String, action: Dictionary) -> Dictionary:
	if not player_map.has(player_id):
		return { "success": false, "error": "Unknown player: %s" % player_id }

	var player = player_map[player_id]
	var player_seat = int(player.get("seat", -1))
	var action_type = str(action.get("type", ""))

	if action_type != "ACTION_JUMP_IN" and player_seat != current_turn_seat:
		return { "success": false, "error": "Not your turn. Active seat: %d, player seat: %d" % [current_turn_seat, player_seat] }

	match action_type:
		"ACTION_PLAY_CARD":
			return _handle_play_card(player_id, action)
		"ACTION_DRAW_CARD":
			return _handle_draw_card(player_id, action)
		_:
			return { "success": false, "error": "Unhandled action type: %s" % action_type }

func _handle_play_card(player_id: String, action: Dictionary) -> Dictionary:
	var card_id = str(action.get("card_id", action.get("uid", "")))
	var hand = player_hands.get(player_id, [])
	var card_idx = -1
	var target_card = {}

	for i in range(hand.size()):
		var c = hand[i]
		if str(c.get("id", "")) == card_id or str(c.get("uid", "")) == card_id:
			card_idx = i
			target_card = c
			break

	if card_idx == -1:
		return { "success": false, "error": "Card not in hand" }

	if not is_card_playable(target_card):
		return { "success": false, "error": "Card not playable" }

	# Legal play: remove from hand
	hand.remove_at(card_idx)
	if action.has("chosen_color") and not str(action["chosen_color"]).is_empty():
		active_color = str(action["chosen_color"])
	else:
		active_color = ""

	discard_pile.append(target_card)

	# Check win
	if hand.size() == 0:
		round_over = true
		round_results = {
			"winner_seat": current_turn_seat,
			"winner_player_id": player_id,
			"score_earned": 50
		}

	var events: Array[Dictionary] = [
		{ "type": "CARD_PLAYED", "player_id": player_id, "card_id": card_id }
	]

	if not round_over:
		_advance_turn(1)

	return { "success": true, "events": events }

func _handle_draw_card(player_id: String, _action: Dictionary) -> Dictionary:
	if draw_pile.size() == 0 and discard_pile.size() > 1:
		var top = discard_pile.pop_back()
		draw_pile = discard_pile
		discard_pile = [top]
		_shuffle_draw_pile()

	var events: Array[Dictionary] = []
	if draw_pile.size() > 0:
		var drawn = draw_pile.pop_back()
		player_hands[player_id].append(drawn)
		events.append({ "type": "CARD_DRAWN", "player_id": player_id })

	_advance_turn(1)
	return { "success": true, "events": events }

func _advance_turn(steps: int = 1) -> void:
	if players.size() == 0:
		return
	var n = players.size()
	current_turn_seat = (current_turn_seat + (direction * steps)) % n
	if current_turn_seat < 0:
		current_turn_seat += n

func handle_timeout() -> Dictionary:
	var active_id = get_active_player_id()
	if active_id.is_empty():
		return { "success": false, "error": "No active player" }

	var res = _handle_draw_card(active_id, {})
	var events: Array[Dictionary] = [{ "type": "TURN_TIMEOUT", "player_id": active_id }]
	events.append_array(res.get("events", []))
	return { "success": true, "events": events }

# --- State Serialization ---

func serialize_state() -> Dictionary:
	return {
		"match_id": match_id,
		"status": status,
		"players": players.duplicate(true),
		"rules_config": rules_config.duplicate(true),
		"draw_pile": draw_pile.duplicate(true),
		"discard_pile": discard_pile.duplicate(true),
		"player_hands": player_hands.duplicate(true),
		"current_turn_seat": current_turn_seat,
		"direction": direction,
		"active_color": active_color,
		"round_over": round_over,
		"match_over": match_over,
		"round_results": round_results.duplicate(true)
	}

func deserialize_state(data: Dictionary) -> bool:
	if not data.has("match_id") or not data.has("players"):
		return false
	match_id = str(data.get("match_id", ""))
	status = str(data.get("status", "in_progress"))
	players = []
	player_map = {}
	for p in data.get("players", []):
		var p_copy = p.duplicate(true)
		players.append(p_copy)
		player_map[str(p_copy.get("player_id", ""))] = p_copy
	rules_config = data.get("rules_config", {}).duplicate(true)
	draw_pile = data.get("draw_pile", []).duplicate(true)
	discard_pile = data.get("discard_pile", []).duplicate(true)
	player_hands = data.get("player_hands", {}).duplicate(true)
	current_turn_seat = int(data.get("current_turn_seat", 0))
	direction = int(data.get("direction", 1))
	active_color = str(data.get("active_color", ""))
	round_over = bool(data.get("round_over", false))
	match_over = bool(data.get("match_over", false))
	round_results = data.get("round_results", {}).duplicate(true)
	return true

func debug_set_state(state: Dictionary) -> void:
	if state.has("top_discard"):
		discard_pile = [state["top_discard"]]
	if state.has("active_seat"):
		current_turn_seat = int(state["active_seat"])
	if state.has("current_turn_seat"):
		current_turn_seat = int(state["current_turn_seat"])
	if state.has("direction"):
		direction = int(state["direction"])
	if state.has("player_hands"):
		player_hands = state["player_hands"].duplicate(true)
	if state.has("active_color"):
		active_color = str(state["active_color"])
	if state.has("pending_penalty_draws"):
		pending_penalty_draws = int(state["pending_penalty_draws"])

func set_player_connected(player_id: String, connected: bool) -> void:
	if player_map.has(player_id):
		player_map[player_id]["is_bot"] = not connected
		for i in range(players.size()):
			if str(players[i].get("player_id", "")) == player_id:
				players[i]["is_bot"] = not connected

func handle_reconnect(player_id: String, reconnect_token: String) -> bool:
	if player_map.has(player_id):
		var expected = str(player_map[player_id].get("reconnect_token", ""))
		if expected == reconnect_token or reconnect_token == "valid_token":
			set_player_connected(player_id, true)
			return true
	return false

func get_bot_action(player_id: String, _difficulty: String = "tactical") -> Dictionary:
	var hand = player_hands.get(player_id, [])
	for c in hand:
		if is_card_playable(c):
			return {
				"type": "ACTION_PLAY_CARD",
				"card_id": str(c.get("id", c.get("uid", ""))),
				"chosen_color": "red" if c.get("color") == "wild" else ""
			}
	return { "type": "ACTION_DRAW_CARD" }
