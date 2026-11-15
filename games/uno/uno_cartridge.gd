# uno_cartridge.gd
# Modular Game Cartridge Implementation for UNO Reference Game
class_name UnoCartridge
extends "res://core/cartridge/game_cartridge.gd"

const UnoRulesScript = preload("res://games/uno/uno_rules.gd")
const UnoHouseRulesScript = preload("res://games/uno/uno_house_rules.gd")
const UnoBotAiScript = preload("res://games/uno/uno_bot_ai.gd")

var uno_rules: RefCounted = null
var house_rules: RefCounted = null
var bot_ai: RefCounted = null

func _init() -> void:
	uno_rules = UnoRulesScript.new()
	house_rules = UnoHouseRulesScript.new()
	bot_ai = UnoBotAiScript.new()

func get_game_id() -> String:
	return "uno"

func get_display_name() -> String:
	return "UNO Reference Game"

func get_min_players() -> int:
	return 2

func get_max_players() -> int:
	return 4

func get_default_rules() -> Dictionary:
	return {
		"stacking_draw_two": false,
		"stacking_draw_four": false,
		"jump_in": false,
		"seven_zero_passing": false,
		"draw_to_match": false
	}

func init_match(p_match_id: String, p_players: Array[Dictionary], p_rules: Dictionary = {}, p_seed: int = 0) -> void:
	super.init_match(p_match_id, p_players, p_rules, p_seed)
	house_rules = UnoHouseRulesScript.new(p_rules)
	uno_rules = UnoRulesScript.new(p_seed)
	bot_ai = UnoBotAiScript.new()

func _add_to_discard(card: Dictionary) -> void:
	discard_pile.append(card)
	uno_rules.discard_pile = discard_pile

func _draw_card() -> Variant:
	uno_rules.draw_pile = draw_pile
	uno_rules.discard_pile = discard_pile
	var drawn = uno_rules.draw_card()
	draw_pile = uno_rules.draw_pile
	discard_pile = uno_rules.discard_pile
	return drawn

func _calculate_round_results(player_seat: int) -> Dictionary:
	var player = get_player_by_seat(player_seat)
	var player_id = str(player.get("player_id", ""))
	var earned_points = 0
	for pid in player_hands.keys():
		if pid != player_id:
			earned_points += uno_rules.calculate_hand_points(player_hands[pid])
	round_results = {
		"winner_seat": player_seat,
		"winner_player_id": player_id,
		"score_earned": earned_points if earned_points > 0 else 50
	}
	return round_results

func start_round() -> void:
	round_over = false
	status = "in_progress"
	uno_rules.init_deck(seed_val)
	draw_pile = uno_rules.get_draw_pile()
	discard_pile = []
	uno_rules.discard_pile = discard_pile

	# Deal 7 cards to each player
	for p in players:
		var p_id = str(p.get("player_id", ""))
		player_hands[p_id] = []
		for _i in range(7):
			var c = _draw_card()
			if c != null:
				player_hands[p_id].append(c)

	# Flip 1 top discard
	var first_discard = _draw_card()
	if first_discard != null:
		_add_to_discard(first_discard)
		if str(first_discard.get("color", "")) == "wild":
			active_color = "red"
		else:
			active_color = ""

	current_turn_seat = 0
	direction = 1
	pending_penalty_draws = 0

func is_card_playable(card: Dictionary) -> bool:
	var top = get_top_discard()
	return uno_rules.is_card_matching(card, top, active_color)

func handle_action(player_id: String, action: Dictionary) -> Dictionary:
	uno_rules.discard_pile = discard_pile
	uno_rules.draw_pile = draw_pile

	if not player_map.has(player_id):
		return { "success": false, "error": "Unknown player: %s" % player_id }

	var player = player_map[player_id]
	var player_seat = int(player.get("seat", -1))
	var action_type = str(action.get("type", ""))

	# Jump-In check (can occur out of turn)
	if action_type == "ACTION_JUMP_IN":
		return _handle_jump_in(player_id, player_seat, action)

	if action_type == "ACTION_CALL_UNO":
		player["called_uno"] = true
		return { "success": true, "events": [{ "type": "CALLED_UNO", "player_id": player_id }] }

	if player_seat != current_turn_seat:
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

	# If there is a pending penalty draw (+2 or +4)
	if pending_penalty_draws > 0:
		if house_rules.can_stack(target_card, pending_penalty_draws):
			# Legal counter-stack
			var val = str(target_card.get("value", ""))
			if val == "draw_two":
				pending_penalty_draws += 2
			elif val == "wild_draw_four":
				pending_penalty_draws += 4

			hand.remove_at(card_idx)
			_add_to_discard(target_card)
			if action.has("chosen_color") and not str(action["chosen_color"]).is_empty():
				active_color = str(action["chosen_color"])
			_advance_turn(1)
			return {
				"success": true,
				"events": [{ "type": "CARD_STACKED", "player_id": player_id, "penalty": pending_penalty_draws }]
			}
		else:
			return { "success": false, "error": "Cannot counter-play; must draw accumulated penalty" }

	if not is_card_playable(target_card):
		return { "success": false, "error": "Card not matching top discard" }

	var player = player_map[player_id]
	var player_seat = int(player.get("seat", 0))

	# Legal play: remove from hand
	hand.remove_at(card_idx)

	var card_color = str(target_card.get("color", ""))
	if card_color == "wild":
		active_color = str(action.get("chosen_color", "red"))
	else:
		active_color = ""

	_add_to_discard(target_card)

	# Apply card action effects first (turn advance, skip, reverse, draw penalty, swap)
	_apply_card_action_effects(player_id, target_card, action)

	# Check UNO call requirement & win condition on the player's updated hand
	var current_hand = player_hands.get(player_id, [])
	if current_hand.size() == 1:
		player_map[player_id]["called_uno"] = bool(action.get("called_uno", false))
	elif current_hand.size() == 0:
		round_over = true
		var res = _calculate_round_results(player_seat)
		var earned_points = res.get("score_earned", 50)
		return {
			"success": true,
			"events": [{ "type": "ROUND_WON", "winner": player_id, "score": earned_points }]
		}

	return {
		"success": true,
		"events": [{ "type": "CARD_PLAYED", "player_id": player_id, "card_id": card_id }]
	}

func _apply_card_action_effects(player_id: String, card: Dictionary, action: Dictionary) -> void:
	var val = str(card.get("value", ""))

	match val:
		"skip":
			_advance_turn(2)

		"reverse":
			if players.size() == 2:
				# Official 2-player UNO rule: Reverse acts as Skip!
				# Turn stays with active player!
				pass
			else:
				direction = -direction
				_advance_turn(1)

		"draw_two":
			if house_rules.stacking_draw_two:
				pending_penalty_draws = 2
				_advance_turn(1)
			else:
				# Next player draws 2 and is skipped
				var next_p_seat = (current_turn_seat + direction + players.size()) % players.size()
				var next_p = get_player_by_seat(next_p_seat)
				var next_pid = str(next_p.get("player_id", ""))
				for _i in range(2):
					var drawn = _draw_card()
					if drawn != null:
						player_hands[next_pid].append(drawn)
				_advance_turn(2)

		"wild_draw_four":
			if house_rules.stacking_draw_four:
				pending_penalty_draws = 4
				_advance_turn(1)
			else:
				# Next player draws 4 and is skipped
				var next_p_seat = (current_turn_seat + direction + players.size()) % players.size()
				var next_p = get_player_by_seat(next_p_seat)
				var next_pid = str(next_p.get("player_id", ""))
				for _i in range(4):
					var drawn = _draw_card()
					if drawn != null:
						player_hands[next_pid].append(drawn)
				_advance_turn(2)

		"7":
			if house_rules.seven_zero_passing and action.has("swap_target_seat"):
				var target_s = int(action["swap_target_seat"])
				var target_p = get_player_by_seat(target_s)
				var target_pid = str(target_p.get("player_id", ""))
				if not target_pid.is_empty() and player_hands.has(target_pid):
					var my_hand = player_hands[player_id]
					player_hands[player_id] = player_hands[target_pid]
					player_hands[target_pid] = my_hand
			_advance_turn(1)

		"0":
			if house_rules.seven_zero_passing:
				# Rotate all hands in direction
				var n = players.size()
				var old_hands: Dictionary = {}
				for p in players:
					var pid = str(p.get("player_id", ""))
					old_hands[pid] = player_hands[pid].duplicate(true)

				for p in players:
					var s = int(p.get("seat", 0))
					var from_seat = (s - direction + n) % n
					var from_p = get_player_by_seat(from_seat)
					var from_pid = str(from_p.get("player_id", ""))
					var to_pid = str(p.get("player_id", ""))
					player_hands[to_pid] = old_hands[from_pid]
			_advance_turn(1)

		_:
			_advance_turn(1)

func _handle_draw_card(player_id: String, _action: Dictionary) -> Dictionary:
	if pending_penalty_draws > 0:
		# Drawing accumulated penalty
		var events: Array[Dictionary] = []
		for _i in range(pending_penalty_draws):
			var drawn = _draw_card()
			if drawn != null:
				player_hands[player_id].append(drawn)
		events.append({ "type": "PENALTY_DRAWN", "count": pending_penalty_draws, "player_id": player_id })
		pending_penalty_draws = 0
		_advance_turn(1)
		return { "success": true, "events": events }

	if house_rules.draw_to_match:
		var events: Array[Dictionary] = []
		var found_playable = false
		for _i in range(20): # Safety bound
			var drawn = _draw_card()
			if drawn == null:
				break
			player_hands[player_id].append(drawn)
			events.append({ "type": "CARD_DRAWN", "player_id": player_id })
			if is_card_playable(drawn):
				found_playable = true
				break
		_advance_turn(1)
		return { "success": true, "events": events, "found_playable": found_playable }

	# Standard single card draw
	var drawn = _draw_card()
	var events: Array[Dictionary] = []
	if drawn != null:
		player_hands[player_id].append(drawn)
		events.append({ "type": "CARD_DRAWN", "player_id": player_id })

	_advance_turn(1)
	return { "success": true, "events": events }

func _handle_jump_in(player_id: String, player_seat: int, action: Dictionary) -> Dictionary:
	var top = get_top_discard()
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

	if not house_rules.can_jump_in(target_card, top):
		return { "success": false, "error": "Invalid Jump-In: card must be identical in color and value" }

	# Successful Jump-In!
	hand.remove_at(card_idx)
	_add_to_discard(target_card)

	# Turn is stolen by jumping player; next player is (player_seat + direction)
	var n = players.size()
	current_turn_seat = (player_seat + direction + n) % n

	if hand.size() == 0:
		round_over = true
		var res = _calculate_round_results(player_seat)
		var earned_points = res.get("score_earned", 50)
		return {
			"success": true,
			"events": [
				{ "type": "JUMP_IN", "player_id": player_id, "card_id": card_id },
				{ "type": "ROUND_WON", "winner": player_id, "score": earned_points }
			]
		}

	if hand.size() == 1:
		player_map[player_id]["called_uno"] = bool(action.get("called_uno", false))

	return {
		"success": true,
		"events": [{ "type": "JUMP_IN", "player_id": player_id, "card_id": card_id }]
	}

func get_bot_action(player_id: String, difficulty: String = "tactical") -> Dictionary:
	var hand = player_hands.get(player_id, [])
	var top = get_top_discard()
	var next_seat = (current_turn_seat + direction + players.size()) % players.size()
	var next_player = get_player_by_seat(next_seat)

	var match_context = {
		"next_player_card_count": get_player_card_count(str(next_player.get("player_id", ""))),
		"next_player_called_uno": bool(next_player.get("called_uno", false)),
		"active_color": active_color,
		"pending_penalty_draws": pending_penalty_draws,
		"stacking_draw_two": house_rules.stacking_draw_two,
		"stacking_draw_four": house_rules.stacking_draw_four
	}

	return bot_ai.choose_action_with_context(hand, top, match_context, difficulty)

func handle_timeout() -> Dictionary:
	var active_id = get_active_player_id()
	if active_id.is_empty():
		return { "success": false, "error": "No active player" }

	var bot_act = get_bot_action(active_id)
	var res = handle_action(active_id, bot_act)

	var events: Array[Dictionary] = [{ "type": "TURN_TIMEOUT", "player_id": active_id }]
	events.append_array(res.get("events", []))
	return { "success": true, "events": events }

func debug_set_state(state: Dictionary) -> void:
	super.debug_set_state(state)
	if state.has("draw_pile"):
		draw_pile = state["draw_pile"].duplicate(true)
		uno_rules.draw_pile = draw_pile
	if state.has("discard_pile"):
		discard_pile = state["discard_pile"].duplicate(true)
		uno_rules.discard_pile = discard_pile
	elif state.has("top_discard"):
		discard_pile = [state["top_discard"].duplicate(true)]
		uno_rules.discard_pile = discard_pile
	active_color = str(state.get("active_color", ""))
	pending_penalty_draws = int(state.get("pending_penalty_draws", 0))
