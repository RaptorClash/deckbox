# uno_cartridge.gd
# Modular Game Cartridge Implementation for UNO (Classic, No Mercy, UNO Flip, Custom Cards & N-Player Scaling)
class_name UnoCartridge
extends "res://core/cartridge/game_cartridge.gd"

const UnoRulesScript = preload("res://games/uno/uno_rules.gd")
const UnoHouseRulesScript = preload("res://games/uno/uno_house_rules.gd")
const UnoBotAiScript = preload("res://games/uno/uno_bot_ai.gd")
const CustomCardInterpreterScript = preload("res://core/packs/custom_card_interpreter.gd")

var uno_rules: RefCounted = null
var house_rules: RefCounted = null
var bot_ai: RefCounted = null

var active_side: String = "light"
var last_penalty_step: int = 0
var mercy_hand_limit: int = 0
var last_plus_four_challenge: Dictionary = {}
var _last_sort_mode: String = ""
var _last_immediate_draw: Dictionary = {}

const COLOR_SORT_ORDER: Dictionary = {
	"red": 0, "pink": 0,
	"blue": 1, "teal": 1,
	"green": 2, "purple": 2,
	"yellow": 3, "orange": 3,
	"wild": 4
}

func _init() -> void:
	uno_rules = UnoRulesScript.new()
	house_rules = UnoHouseRulesScript.new()
	bot_ai = UnoBotAiScript.new()

func get_game_id() -> String:
	return "uno"

func get_display_name() -> String:
	return "Alle Ablegen!"

func get_min_players() -> int:
	return 2

func get_max_players() -> int:
	return 999

func get_default_rules() -> Dictionary:
	return {
		"stacking_draw_two": false,
		"stacking_draw_four": false,
		"jump_in": false,
		"seven_zero_passing": false,
		"draw_to_match": false,
		"expansion_no_mercy": false,
		"expansion_flip": false,
		"progressive_stacking": false,
		"mercy_hand_limit": 0,
		"custom_cards": []
	}

func init_match(p_match_id: String, p_players: Array[Dictionary], p_rules: Dictionary = {}, p_seed: int = 0) -> void:
	super.init_match(p_match_id, p_players, p_rules, p_seed)
	house_rules = UnoHouseRulesScript.new(p_rules)
	uno_rules = UnoRulesScript.new(p_seed)
	bot_ai = UnoBotAiScript.new()
	active_side = "light"
	last_penalty_step = 0
	mercy_hand_limit = house_rules.mercy_hand_limit
	last_plus_four_challenge = {}
	_last_sort_mode = ""

func _add_to_discard(card: Dictionary) -> void:
	discard_pile.append(card)
	uno_rules.discard_pile = discard_pile

func _draw_card() -> Variant:
	uno_rules.draw_pile = draw_pile
	uno_rules.discard_pile = discard_pile
	var drawn = uno_rules.draw_card()
	if drawn is Dictionary:
		UnoRulesScript.flip_card_side(drawn, active_side)
	draw_pile = uno_rules.draw_pile
	discard_pile = uno_rules.discard_pile
	return drawn

func _get_alive_player_count() -> int:
	var alive = 0
	for p in players:
		if not bool(p.get("eliminated", false)):
			alive += 1
	return alive

func _advance_turn(steps: int = 1) -> void:
	var n = players.size()
	if n == 0:
		return
	if _get_alive_player_count() <= 1:
		return

	if steps <= 0:
		var cur_p = get_player_by_seat(current_turn_seat)
		if not bool(cur_p.get("eliminated", false)):
			return
		steps = 1

	for _s in range(steps):
		for _guard in range(n):
			current_turn_seat = (current_turn_seat + direction + n) % n
			var cand = get_player_by_seat(current_turn_seat)
			if not bool(cand.get("eliminated", false)):
				break

func _get_next_alive_seat(from_seat: int = -1, step_dir: int = 0) -> int:
	var n = players.size()
	if n == 0:
		return 0
	var s = current_turn_seat if from_seat < 0 else from_seat
	var d = direction if step_dir == 0 else step_dir
	for _i in range(n):
		s = (s + d + n) % n
		var p = get_player_by_seat(s)
		if not bool(p.get("eliminated", false)):
			return s
	return current_turn_seat

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
	active_side = "light"
	last_penalty_step = 0
	mercy_hand_limit = house_rules.mercy_hand_limit
	last_plus_four_challenge = {}
	_last_sort_mode = ""
	for p in players:
		p["eliminated"] = false
		p["called_uno"] = false

	var requested_decks = int(rules_config.get("deck_count", 0))
	var deck_count = requested_decks if requested_decks > 0 else uno_rules.calculate_recommended_deck_count(players.size(), 7)
	var auto_exp = bool(rules_config.get("endless_deck", players.size() > 4))
	uno_rules.init_deck_with_rules(seed_val, rules_config, deck_count, auto_exp)
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
		if str(first_discard.get("color", "")) in ["wild", "special", "colorless"]:
			active_color = "red"
		else:
			active_color = ""

	current_turn_seat = 0
	direction = 1
	pending_penalty_draws = 0

func is_card_playable(card: Dictionary) -> bool:
	if pending_penalty_draws > 0:
		return house_rules.can_stack(card, pending_penalty_draws, last_penalty_step)
	var top = get_top_discard()
	return uno_rules.is_card_matching(card, top, active_color)

func handle_action(player_id: String, action: Dictionary) -> Dictionary:
	uno_rules.discard_pile = discard_pile
	uno_rules.draw_pile = draw_pile

	if not player_map.has(player_id):
		return { "success": false, "error": "Unknown player: %s" % player_id }

	var player = player_map[player_id]
	if bool(player.get("eliminated", false)):
		return { "success": false, "error": "Player eliminated: %s" % player_id }

	var player_seat = int(player.get("seat", -1))
	var action_type = str(action.get("type", ""))

	# Jump-In check (can occur out of turn)
	if action_type == "ACTION_JUMP_IN":
		return _handle_jump_in(player_id, player_seat, action)

	if action_type == "ACTION_CALL_UNO":
		player["called_uno"] = true
		return { "success": true, "events": [{ "type": "CALLED_UNO", "player_id": player_id }] }

	if action_type == "ACTION_SORT_HAND":
		var mode = str(action.get("mode", "auto"))
		var ok_s = sort_player_hand(player_id, mode)
		return { "success": ok_s, "events": [{ "type": "HAND_SORTED", "player_id": player_id, "mode": _last_sort_mode }] }

	if action_type == "ACTION_SHUFFLE_HAND":
		var ok_sh = shuffle_player_hand(player_id)
		return { "success": ok_sh, "events": [{ "type": "HAND_SHUFFLED", "player_id": player_id }] }

	if action_type == "ACTION_CATCH_UNO":
		return _handle_catch_uno(player_id, action)

	if action_type == "ACTION_CHALLENGE_PLUS_FOUR":
		return _handle_challenge_plus_four(player_id, action)

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

	var extra_events: Array[Dictionary] = []

	# If there is a pending penalty draw (+2, +4, +5, +6, +10, or Shield)
	if pending_penalty_draws > 0:
		if house_rules.can_stack(target_card, pending_penalty_draws, last_penalty_step):
			hand.remove_at(card_idx)
			var card_col_s = str(target_card.get("color", ""))
			if card_col_s in ["wild", "special", "colorless"]:
				var default_c = "pink" if active_side == "dark" else "red"
				active_color = str(action.get("chosen_color", default_c))
				if active_color.is_empty():
					active_color = default_c
			elif action.has("chosen_color") and not str(action["chosen_color"]).is_empty():
				active_color = str(action["chosen_color"])
			else:
				active_color = ""
			_add_to_discard(target_card)

			if UnoHouseRulesScript.card_has_action(target_card, "negate_penalty"):
				var cancelled = pending_penalty_draws
				pending_penalty_draws = 0
				last_penalty_step = 0
				_advance_turn(1)
				return {
					"success": true,
					"events": [{ "type": "PENALTY_NEGATED", "player_id": player_id, "cancelled": cancelled, "card": target_card.duplicate(true) }]
				}

			var step_pen = UnoHouseRulesScript.get_card_draw_penalty(target_card)
			pending_penalty_draws += step_pen
			last_penalty_step = step_pen
			if str(target_card.get("value", "")) == "wild_reverse_draw_four":
				direction = -direction
			_advance_turn(1)
			return {
				"success": true,
				"events": [{
					"type": "CARD_STACKED",
					"player_id": player_id,
					"penalty": pending_penalty_draws,
					"card": target_card.duplicate(true),
					"direction": direction
				}]
			}
		else:
			return { "success": false, "error": "Cannot counter-play; must draw accumulated penalty" }

	if not uno_rules.is_card_matching(target_card, get_top_discard(), active_color):
		return { "success": false, "error": "Card not matching top discard" }

	var player = player_map[player_id]
	var player_seat = int(player.get("seat", 0))
	var prev_top: Dictionary = get_top_discard().duplicate(true)
	var prev_active_color: String = active_color
	last_plus_four_challenge = {}
	_last_immediate_draw = {}

	# Legal play: remove from hand
	hand.remove_at(card_idx)

	var card_color = str(target_card.get("color", ""))
	if card_color in ["wild", "special", "colorless"]:
		var default_col = "pink" if active_side == "dark" else "red"
		var chosen = str(action.get("chosen_color", default_col))
		active_color = chosen if not chosen.is_empty() else default_col
	else:
		active_color = ""

	# Apply card action effects (Discard All appends matching cards first, then puts target_card on top; Flip flips target_card too!)
	if target_card.has("actions") and target_card["actions"] is Array and not target_card["actions"].is_empty():
		_add_to_discard(target_card)
		_apply_custom_card_actions(player_id, target_card, action, extra_events)
	elif str(target_card.get("value", "")) == "discard_all":
		_apply_card_action_effects(player_id, target_card, action, extra_events)
	else:
		_add_to_discard(target_card)
		_apply_card_action_effects(player_id, target_card, action, extra_events)

	var elim_events = _check_mercy_elimination()
	extra_events.append_array(elim_events)

	# Check win condition (hand emptied OR last survivor standing)
	var current_hand = player_hands.get(player_id, [])
	if round_over:
		return { "success": true, "events": extra_events }

	if current_hand.size() == 1:
		player_map[player_id]["called_uno"] = bool(player_map[player_id].get("called_uno", false)) or bool(action.get("called_uno", false))
	elif current_hand.size() > 1:
		player_map[player_id]["called_uno"] = false
	if current_hand.size() == 0:
		round_over = true
		var res = _calculate_round_results(player_seat)
		var earned_points = res.get("score_earned", 50)
		var win_evs: Array[Dictionary] = [{ "type": "ROUND_WON", "winner": player_id, "score": earned_points, "card": target_card.duplicate(true) }]
		win_evs.append_array(extra_events)
		return { "success": true, "events": win_evs }

	var played_val = str(target_card.get("value", ""))
	if played_val in ["wild_draw_four", "wild_reverse_draw_four", "wild_draw_six", "wild_draw_ten"] and not round_over:
		_record_wild_draw_challenge(player_id, player_seat, target_card, prev_top, prev_active_color)

	var all_evs: Array[Dictionary] = [{
		"type": "CARD_PLAYED",
		"player_id": player_id,
		"card_id": card_id,
		"card": target_card.duplicate(true),
		"seat": player_seat,
		"next_seat": current_turn_seat,
		"direction": direction,
		"active_color": active_color,
		"active_side": active_side
	}]
	all_evs.append_array(extra_events)
	return { "success": true, "events": all_evs }

func _apply_card_action_effects(player_id: String, card: Dictionary, action: Dictionary, out_events: Array[Dictionary]) -> void:
	var val = str(card.get("value", ""))
	var alive_n = _get_alive_player_count()

	match val:
		"skip":
			_advance_turn(2)

		"skip_everyone":
			out_events.append({ "type": "SKIP_EVERYONE", "player_id": player_id })
			_advance_turn(0)

		"discard_all":
			var match_col = str(card.get("color", ""))
			var hand: Array = player_hands.get(player_id, [])
			var kept: Array = []
			var dropped: int = 0
			for hc in hand:
				if hc is Dictionary and str(hc.get("color", "")) == match_col:
					_add_to_discard(hc)
					dropped += 1
				else:
					kept.append(hc)
			player_hands[player_id] = kept
			_add_to_discard(card)
			out_events.append({ "type": "DISCARD_ALL", "player_id": player_id, "color": match_col, "dropped_count": dropped })
			_advance_turn(1)

		"flip":
			_flip_active_side()
			out_events.append({ "type": "DECK_FLIPPED", "active_side": active_side })
			_advance_turn(1)

		"reverse":
			if alive_n == 2:
				_advance_turn(0)
			else:
				direction = -direction
				_advance_turn(1)

		"draw_two", "draw_four", "draw_five", "wild_draw_four", "wild_draw_six", "wild_draw_ten", "wild_reverse_draw_four":
			if val == "wild_reverse_draw_four":
				direction = -direction
			var pen = UnoHouseRulesScript.get_card_draw_penalty(card)
			var can_stack_this = house_rules.progressive_stacking or house_rules.expansion_no_mercy or (val == "draw_two" and house_rules.stacking_draw_two) or (val == "wild_draw_four" and house_rules.stacking_draw_four)
			if can_stack_this:
				pending_penalty_draws = pen
				last_penalty_step = pen
				_advance_turn(1)
			else:
				var next_s = _get_next_alive_seat()
				var next_p = get_player_by_seat(next_s)
				var next_pid = str(next_p.get("player_id", ""))
				var drawn_ids: Array[String] = []
				for _i in range(pen):
					var drawn = _draw_card()
					if drawn != null:
						player_hands[next_pid].append(drawn)
						drawn_ids.append(str(drawn.get("id", drawn.get("uid", ""))))
				if player_hands.get(next_pid, []).size() > 1 and player_map.has(next_pid):
					player_map[next_pid]["called_uno"] = false
				_last_immediate_draw = {
					"victim_id": next_pid,
					"victim_seat": next_s,
					"penalty": pen,
					"card_ids": drawn_ids
				}
				_advance_turn(2)

		"wild_color_roulette", "wild_draw_color":
			var target_col = active_color if not active_color.is_empty() else ("pink" if active_side == "dark" else "red")
			var next_s = _get_next_alive_seat()
			var next_p = get_player_by_seat(next_s)
			var next_pid = str(next_p.get("player_id", ""))
			var drawn_cnt = 0
			for _i in range(12):
				var drawn = _draw_card()
				if drawn == null:
					break
				player_hands[next_pid].append(drawn)
				drawn_cnt += 1
				if str(drawn.get("color", "")) == target_col:
					break
			out_events.append({ "type": "COLOR_ROULETTE_DRAWN", "player_id": next_pid, "count": drawn_cnt, "target_color": target_col })
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
				var alive_players: Array[Dictionary] = []
				for p in players:
					if not bool(p.get("eliminated", false)):
						alive_players.append(p)
				var m = alive_players.size()
				var old_hands: Dictionary = {}
				for p in alive_players:
					var pid = str(p.get("player_id", ""))
					old_hands[pid] = player_hands[pid].duplicate(true)
				for idx in range(m):
					var from_idx = (idx - direction + m) % m
					var from_pid = str(alive_players[from_idx].get("player_id", ""))
					var to_pid = str(alive_players[idx].get("player_id", ""))
					player_hands[to_pid] = old_hands[from_pid]
			_advance_turn(1)

		_:
			_advance_turn(1)

func _apply_custom_card_actions(player_id: String, card: Dictionary, action: Dictionary, out_events: Array[Dictionary]) -> void:
	var actions: Array = card.get("actions", [])
	var hands_by_seat: Dictionary = {}
	for p in players:
		var s = int(p.get("seat", 0))
		var pid = str(p.get("player_id", ""))
		hands_by_seat[s] = player_hands.get(pid, [])

	var p_seat = int(player_map[player_id].get("seat", 0))
	var ctx = {
		"player_count": players.size(),
		"current_seat": p_seat,
		"direction": direction,
		"active_side": active_side,
		"active_color": active_color,
		"pending_penalty": pending_penalty_draws,
		"pending_penalty_draws": pending_penalty_draws,
		"draw_pile": draw_pile,
		"discard_pile": discard_pile,
		"hands": hands_by_seat,
		"skip_count": 0,
		"skip_everyone": false
	}

	# Check if this custom card acts as a stackable draw penalty card
	var custom_pen = UnoHouseRulesScript.get_card_draw_penalty(card)
	if custom_pen > 0 and (house_rules.progressive_stacking or house_rules.expansion_no_mercy or house_rules.stacking_draw_two or house_rules.stacking_draw_four):
		pending_penalty_draws += custom_pen
		last_penalty_step = custom_pen
		_advance_turn(1)
		return

	var res = CustomCardInterpreterScript.execute_card_actions(actions, ctx)
	if res.get("success", false):
		direction = int(ctx.get("direction", direction))
		pending_penalty_draws = int(ctx.get("pending_penalty_draws", pending_penalty_draws))
		for p in players:
			var s = int(p.get("seat", 0))
			var pid = str(p.get("player_id", ""))
			player_hands[pid] = hands_by_seat.get(s, [])

		if str(ctx.get("active_side", active_side)) != active_side:
			_flip_active_side()
			out_events.append({ "type": "DECK_FLIPPED", "active_side": active_side })

		if bool(ctx.get("skip_everyone", false)):
			out_events.append({ "type": "SKIP_EVERYONE", "player_id": player_id })
			_advance_turn(0)
			return

		var skips = int(ctx.get("skip_count", 0))
		if skips > 0:
			_advance_turn(1 + skips)
			return

	_advance_turn(1)

func _flip_active_side() -> void:
	active_side = "dark" if active_side == "light" else "light"
	if not active_color.is_empty():
		active_color = str(UnoRulesScript.SIDE_COLOR_MAP.get(active_color, active_color))

	for c in draw_pile:
		if c is Dictionary:
			UnoRulesScript.flip_card_side(c, active_side)
	for c in discard_pile:
		if c is Dictionary:
			UnoRulesScript.flip_card_side(c, active_side)
	for pid in player_hands.keys():
		for c in player_hands[pid]:
			if c is Dictionary:
				UnoRulesScript.flip_card_side(c, active_side)

func _check_mercy_elimination() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var limit = house_rules.mercy_hand_limit
	if limit <= 0:
		return events

	var recycled_any = false
	for p in players:
		if bool(p.get("eliminated", false)):
			continue
		var pid = str(p.get("player_id", ""))
		var hand: Array = player_hands.get(pid, [])
		if hand.size() >= limit:
			p["eliminated"] = true
			if player_map.has(pid):
				player_map[pid]["eliminated"] = true
			for hc in hand:
				draw_pile.append(hc)
			player_hands[pid] = []
			recycled_any = true
			events.append({
				"type": "PLAYER_ELIMINATED",
				"player_id": pid,
				"seat": int(p.get("seat", 0)),
				"reason": "mercy_limit"
			})

	if recycled_any:
		uno_rules.draw_pile = draw_pile
		uno_rules._shuffle_draw_pile()
		draw_pile = uno_rules.draw_pile

		# If current turn seat was eliminated, move to next alive player
		var cur_p = get_player_by_seat(current_turn_seat)
		if bool(cur_p.get("eliminated", false)):
			_advance_turn(1)

		# Check if only 1 surviving player remains
		var alive_players: Array[Dictionary] = []
		for p in players:
			if not bool(p.get("eliminated", false)):
				alive_players.append(p)
		if alive_players.size() == 1:
			var survivor = alive_players[0]
			var win_seat = int(survivor.get("seat", 0))
			var win_pid = str(survivor.get("player_id", ""))
			round_over = true
			var res = _calculate_round_results(win_seat)
			events.append({
				"type": "ROUND_WON",
				"winner": win_pid,
				"score": res.get("score_earned", 50),
				"reason": "last_survivor"
			})

	return events

func _handle_draw_card(player_id: String, _action: Dictionary) -> Dictionary:
	last_plus_four_challenge = {}
	if pending_penalty_draws > 0:
		var events: Array[Dictionary] = []
		var drawn_total = pending_penalty_draws
		for _i in range(drawn_total):
			var drawn = _draw_card()
			if drawn != null:
				player_hands[player_id].append(drawn)
		if player_hands.get(player_id, []).size() > 1:
			player_map[player_id]["called_uno"] = false
		events.append({ "type": "PENALTY_DRAWN", "count": drawn_total, "player_id": player_id })
		pending_penalty_draws = 0
		last_penalty_step = 0
		var elim_evs = _check_mercy_elimination()
		events.append_array(elim_evs)
		if not round_over and not bool(player_map[player_id].get("eliminated", false)):
			_advance_turn(1)
		return { "success": true, "events": events }

	if house_rules.draw_to_match:
		var events: Array[Dictionary] = []
		var found_playable = false
		for _i in range(20):
			var drawn = _draw_card()
			if drawn == null:
				break
			player_hands[player_id].append(drawn)
			events.append({ "type": "CARD_DRAWN", "player_id": player_id })
			if uno_rules.is_card_matching(drawn, get_top_discard(), active_color):
				found_playable = true
				break
		if player_hands.get(player_id, []).size() > 1:
			player_map[player_id]["called_uno"] = false
		var elim_evs = _check_mercy_elimination()
		events.append_array(elim_evs)
		if not round_over and not bool(player_map[player_id].get("eliminated", false)):
			_advance_turn(1)
		return { "success": true, "events": events, "found_playable": found_playable }

	# Standard single card draw
	var drawn = _draw_card()
	var events: Array[Dictionary] = []
	if drawn != null:
		player_hands[player_id].append(drawn)
		events.append({ "type": "CARD_DRAWN", "player_id": player_id })
	if player_hands.get(player_id, []).size() > 1:
		player_map[player_id]["called_uno"] = false

	var elim_evs = _check_mercy_elimination()
	events.append_array(elim_evs)
	if not round_over and not bool(player_map[player_id].get("eliminated", false)):
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

	current_turn_seat = _get_next_alive_seat(player_seat, direction)

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
	var next_seat = _get_next_alive_seat()
	var next_player = get_player_by_seat(next_seat)

	var match_context = {
		"next_player_card_count": get_player_card_count(str(next_player.get("player_id", ""))),
		"next_player_called_uno": bool(next_player.get("called_uno", false)),
		"active_color": active_color,
		"active_side": active_side,
		"pending_penalty_draws": pending_penalty_draws,
		"last_penalty_step": last_penalty_step,
		"stacking_draw_two": house_rules.stacking_draw_two,
		"stacking_draw_four": house_rules.stacking_draw_four,
		"progressive_stacking": house_rules.progressive_stacking or house_rules.expansion_no_mercy
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
	last_plus_four_challenge = {}
	_last_immediate_draw = {}
	active_color = str(state.get("active_color", ""))
	pending_penalty_draws = int(state.get("pending_penalty_draws", 0))
	if state.has("active_side"):
		active_side = str(state["active_side"])
	if state.has("last_penalty_step"):
		last_penalty_step = int(state["last_penalty_step"])
	if state.has("mercy_hand_limit"):
		mercy_hand_limit = int(state["mercy_hand_limit"])
		house_rules.mercy_hand_limit = mercy_hand_limit

func sort_player_hand(player_id: String, mode: String = "auto") -> bool:
	if not player_hands.has(player_id):
		return false
	var hand: Array = player_hands[player_id]
	var use_mode = mode.to_lower().strip_edges()
	if use_mode == "auto" or use_mode.is_empty():
		use_mode = "value" if _last_sort_mode == "color" else "color"
	_last_sort_mode = use_mode

	hand.sort_custom(func(a: Variant, b: Variant) -> bool:
		if not (a is Dictionary and b is Dictionary):
			return false
		var ca = str(a.get("color", "wild")).to_lower()
		var cb = str(b.get("color", "wild")).to_lower()
		var ra = int(COLOR_SORT_ORDER.get(ca, 9))
		var rb = int(COLOR_SORT_ORDER.get(cb, 9))
		var va = _card_value_sort_key(str(a.get("value", "")))
		var vb = _card_value_sort_key(str(b.get("value", "")))
		if use_mode == "value":
			if va != vb:
				return va < vb
			return ra < rb
		if ra != rb:
			return ra < rb
		return va < vb
	)
	return true

static func _card_value_sort_key(val: String) -> String:
	var v = val.to_lower().strip_edges()
	if v.is_valid_int():
		return "%02d" % int(v)
	return "99_" + v

func shuffle_player_hand(player_id: String) -> bool:
	if not player_hands.has(player_id):
		return false
	var hand: Array = player_hands[player_id]
	var n = hand.size()
	if n <= 1:
		return true
	var first_before = str(hand[0].get("id", hand[0].get("uid", ""))) if hand[0] is Dictionary else ""
	for i in range(n - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var tmp = hand[i]
		hand[i] = hand[j]
		hand[j] = tmp
	var first_after = str(hand[0].get("id", hand[0].get("uid", ""))) if hand[0] is Dictionary else ""
	if n >= 2 and first_before == first_after:
		var tmp2 = hand[0]
		hand[0] = hand[1]
		hand[1] = tmp2
	return true

func get_catchable_uno_players(exclude_player_id: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for p in players:
		if not (p is Dictionary):
			continue
		if bool(p.get("eliminated", false)):
			continue
		var pid = str(p.get("player_id", ""))
		if pid.is_empty() or pid == exclude_player_id:
			continue
		if get_player_card_count(pid) == 1 and not bool(p.get("called_uno", false)):
			result.append(p.duplicate(true))
	return result

func can_challenge_plus_four(player_id: String = "") -> bool:
	if not bool(last_plus_four_challenge.get("active", false)) or round_over:
		return false
	if player_id.is_empty():
		return true
	var victim = str(last_plus_four_challenge.get("victim_id", ""))
	return player_id == victim

func get_plus_four_challenge_info() -> Dictionary:
	return last_plus_four_challenge.duplicate(true)

func _record_wild_draw_challenge(offender_id: String, offender_seat: int, played_card: Dictionary, prev_top: Dictionary, prev_active_color: String) -> void:
	var offender_p = player_map.get(offender_id, {})
	var offender_name = str(offender_p.get("name", offender_id))
	var hand_after: Array = player_hands.get(offender_id, [])
	var snapshot: Array[Dictionary] = []
	var is_bluff = false
	for hc in hand_after:
		if hc is Dictionary:
			var c_copy = hc.duplicate(true)
			var hc_col = str(c_copy.get("color", ""))
			var playable_alt = (not (hc_col in ["wild", "special", "colorless"])) and uno_rules.is_card_matching(c_copy, prev_top, prev_active_color)
			c_copy["could_have_played"] = playable_alt
			if playable_alt:
				is_bluff = true
			snapshot.append(c_copy)

	var was_drawn = not _last_immediate_draw.is_empty()
	var pen = int(_last_immediate_draw.get("penalty", UnoHouseRulesScript.get_card_draw_penalty(played_card)))
	var victim_id = str(_last_immediate_draw.get("victim_id", ""))
	var victim_seat = int(_last_immediate_draw.get("victim_seat", current_turn_seat))
	if not was_drawn:
		var vp = get_player_by_seat(current_turn_seat)
		victim_id = str(vp.get("player_id", ""))
		victim_seat = current_turn_seat

	last_plus_four_challenge = {
		"active": not victim_id.is_empty(),
		"offender_id": offender_id,
		"offender_seat": offender_seat,
		"offender_name": offender_name,
		"victim_id": victim_id,
		"victim_seat": victim_seat,
		"penalty": pen,
		"was_already_drawn": was_drawn,
		"drawn_card_ids": _last_immediate_draw.get("card_ids", []).duplicate(),
		"offender_hand_snapshot": snapshot,
		"is_bluff": is_bluff,
		"card_value": str(played_card.get("value", "wild_draw_four"))
	}

func _handle_catch_uno(challenger_id: String, action: Dictionary) -> Dictionary:
	var target_id = str(action.get("target_player_id", ""))
	if target_id.is_empty():
		var candidates = get_catchable_uno_players(challenger_id)
		if candidates.is_empty():
			return { "success": false, "error": "No player forgot LETZTE!" }
		target_id = str(candidates[0].get("player_id", ""))

	if not player_map.has(target_id):
		return { "success": false, "error": "Unknown target player" }
	var target_p = player_map[target_id]
	if bool(target_p.get("eliminated", false)):
		return { "success": false, "error": "Target eliminated" }
	if get_player_card_count(target_id) != 1 or bool(target_p.get("called_uno", false)):
		return { "success": false, "error": "Target already called LETZTE! or does not have 1 card" }

	for _i in range(2):
		var c = _draw_card()
		if c != null:
			player_hands[target_id].append(c)
	target_p["called_uno"] = false
	var elim_evs = _check_mercy_elimination()
	var evs: Array[Dictionary] = [{
		"type": "UNO_CAUGHT",
		"challenger_id": challenger_id,
		"target_player_id": target_id,
		"target_name": str(target_p.get("name", target_id)),
		"count": 2
	}]
	evs.append_array(elim_evs)
	return { "success": true, "target_player_id": target_id, "events": evs }

func _handle_challenge_plus_four(challenger_id: String, _action: Dictionary) -> Dictionary:
	if not can_challenge_plus_four(challenger_id):
		return { "success": false, "error": "No active +4 challenge available for this player" }

	var ch: Dictionary = last_plus_four_challenge.duplicate(true)
	last_plus_four_challenge["active"] = false

	var offender_id = str(ch.get("offender_id", ""))
	var victim_id = str(ch.get("victim_id", ""))
	var victim_seat = int(ch.get("victim_seat", current_turn_seat))
	var pen = int(ch.get("penalty", 4))
	var was_drawn = bool(ch.get("was_already_drawn", true))
	var drawn_ids: Array = ch.get("drawn_card_ids", [])
	var snapshot: Array = ch.get("offender_hand_snapshot", [])
	var is_bluff = bool(ch.get("is_bluff", false))

	if is_bluff:
		if was_drawn and player_hands.has(victim_id):
			var v_hand: Array = player_hands[victim_id]
			var moved = 0
			for cid in drawn_ids:
				for idx in range(v_hand.size() - 1, -1, -1):
					var c = v_hand[idx]
					if c is Dictionary and (str(c.get("id", "")) == str(cid) or str(c.get("uid", "")) == str(cid)):
						v_hand.remove_at(idx)
						player_hands[offender_id].append(c)
						moved += 1
						break
			while moved < pen and not v_hand.is_empty():
				player_hands[offender_id].append(v_hand.pop_back())
				moved += 1
		else:
			pending_penalty_draws = 0
			last_penalty_step = 0
			for _i in range(pen):
				var c = _draw_card()
				if c != null:
					player_hands[offender_id].append(c)

		if player_hands.get(offender_id, []).size() > 1 and player_map.has(offender_id):
			player_map[offender_id]["called_uno"] = false
		if not bool(player_map.get(victim_id, {}).get("eliminated", false)):
			current_turn_seat = victim_seat
		_check_mercy_elimination()
	else:
		var extra = 2
		if was_drawn:
			for _i in range(extra):
				var c = _draw_card()
				if c != null:
					player_hands[challenger_id].append(c)
		else:
			var total_take = maxi(pen, pending_penalty_draws) + extra
			for _i in range(total_take):
				var c = _draw_card()
				if c != null:
					player_hands[challenger_id].append(c)
			pending_penalty_draws = 0
			last_penalty_step = 0
			_advance_turn(1)

		if player_hands.get(challenger_id, []).size() > 1 and player_map.has(challenger_id):
			player_map[challenger_id]["called_uno"] = false
		_check_mercy_elimination()

	var applied = pen if is_bluff else (2 if was_drawn else pen + 2)
	return {
		"success": true,
		"challenge_won": is_bluff,
		"offender_id": offender_id,
		"offender_name": str(ch.get("offender_name", offender_id)),
		"challenger_id": challenger_id,
		"penalty_applied": applied,
		"offender_hand": snapshot,
		"events": [{
			"type": "PLUS_FOUR_CHALLENGED",
			"challenge_won": is_bluff,
			"offender_id": offender_id,
			"challenger_id": challenger_id,
			"penalty": applied,
			"offender_hand": snapshot
		}]
	}
