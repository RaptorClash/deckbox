# uno_bot_ai.gd
# Tactical Bot AI Decision Evaluator and Disconnect Takeover Heuristics
class_name UnoBotAi
extends RefCounted

func choose_wild_color(hand: Array) -> String:
	var counts = { "red": 0, "blue": 0, "green": 0, "yellow": 0 }
	for c in hand:
		if c is Dictionary:
			var col = str(c.get("color", ""))
			if counts.has(col):
				counts[col] += 1

	var best_color = "red"
	var max_count = -1
	for col in ["red", "blue", "green", "yellow"]:
		if counts[col] > max_count:
			max_count = counts[col]
			best_color = col
	return best_color

func is_card_playable(card: Dictionary, top_discard: Dictionary, active_color: String = "") -> bool:
	if card.has("playable"):
		return bool(card["playable"])

	var c_col = str(card.get("color", ""))
	var c_val = str(card.get("value", ""))
	var target_col = active_color if not active_color.is_empty() else str(top_discard.get("color", ""))
	var target_val = str(top_discard.get("value", ""))

	if c_col == "wild":
		return true
	if c_col == target_col:
		return true
	if not c_val.is_empty() and c_val == target_val:
		return true
	return false

func choose_action(hand: Array, top_discard: Dictionary, difficulty: String = "tactical") -> Dictionary:
	return choose_action_with_context(hand, top_discard, {}, difficulty)

func choose_action_with_context(hand: Array, top_discard: Dictionary, match_context: Dictionary, _difficulty: String = "tactical") -> Dictionary:
	var pending_penalty = int(match_context.get("pending_penalty_draws", 0))
	var active_color = str(match_context.get("active_color", ""))

	# If there is a pending penalty draw, bot must counter-stack if possible, otherwise draw penalty
	if pending_penalty > 0:
		var can_stack_two = bool(match_context.get("stacking_draw_two", true))
		var can_stack_four = bool(match_context.get("stacking_draw_four", true))
		for c in hand:
			if c is Dictionary:
				var val = str(c.get("value", ""))
				if val == "draw_two" and can_stack_two:
					return {
						"type": "ACTION_PLAY_CARD",
						"card_id": str(c.get("id", c.get("uid", "")))
					}
		for c in hand:
			if c is Dictionary:
				var val = str(c.get("value", ""))
				if val == "wild_draw_four" and can_stack_four:
					return {
						"type": "ACTION_PLAY_CARD",
						"card_id": str(c.get("id", c.get("uid", ""))),
						"chosen_color": choose_wild_color(hand)
					}
		return { "type": "ACTION_DRAW_CARD" }

	var playable_cards: Array[Dictionary] = []
	for c in hand:
		if c is Dictionary and is_card_playable(c, top_discard, active_color):
			playable_cards.append(c)

	if playable_cards.is_empty():
		return { "type": "ACTION_DRAW_CARD" }

	# 1. Attack leader: if next player has 1 card or called UNO, prioritize action attacks
	var next_card_count = int(match_context.get("next_player_card_count", 99))
	var next_called_uno = bool(match_context.get("next_player_called_uno", false))
	if next_called_uno or next_card_count <= 1:
		for c in playable_cards:
			var val = str(c.get("value", ""))
			if val in ["skip", "draw_two", "reverse"]:
				return {
					"type": "ACTION_PLAY_CARD",
					"card_id": str(c.get("id", c.get("uid", "")))
				}
		for c in playable_cards:
			if str(c.get("value", "")) == "wild_draw_four":
				return {
					"type": "ACTION_PLAY_CARD",
					"card_id": str(c.get("id", c.get("uid", ""))),
					"chosen_color": choose_wild_color(hand)
				}

	# 2. Prioritize regular color/number cards over Wilds
	var regular_playable: Array[Dictionary] = []
	for c in playable_cards:
		if str(c.get("color", "")) != "wild":
			regular_playable.append(c)

	if not regular_playable.is_empty():
		# Save Draw Two / actions if number cards exist, or play regular
		var chosen = regular_playable[0]
		return {
			"type": "ACTION_PLAY_CARD",
			"card_id": str(chosen.get("id", chosen.get("uid", "")))
		}

	# 3. Fallback: play standard Wild if held
	for c in playable_cards:
		if str(c.get("value", "")) == "wild":
			return {
				"type": "ACTION_PLAY_CARD",
				"card_id": str(c.get("id", c.get("uid", ""))),
				"chosen_color": choose_wild_color(hand)
			}

	# 4. Fallback: play Wild Draw Four
	for c in playable_cards:
		if str(c.get("value", "")) == "wild_draw_four":
			return {
				"type": "ACTION_PLAY_CARD",
				"card_id": str(c.get("id", c.get("uid", ""))),
				"chosen_color": choose_wild_color(hand)
			}

	return { "type": "ACTION_DRAW_CARD" }
