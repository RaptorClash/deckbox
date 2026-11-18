# uno_bot_ai.gd
# Tactical Bot AI Decision Evaluator supporting Classic, No Mercy Stacking, UNO Flip Dark Side & Custom Cards
class_name UnoBotAi
extends RefCounted

const UnoHouseRulesScript = preload("res://games/uno/uno_house_rules.gd")

const LIGHT_COLS: Array[String] = ["red", "blue", "green", "yellow"]
const DARK_COLS: Array[String] = ["pink", "teal", "purple", "orange"]

func choose_wild_color(hand: Array, active_side: String = "light") -> String:
	var valid_cols: Array[String] = DARK_COLS if active_side == "dark" else LIGHT_COLS
	var counts: Dictionary = {}
	for c_key in valid_cols:
		counts[c_key] = 0

	for c in hand:
		if c is Dictionary:
			var col = str(c.get("color", ""))
			if counts.has(col):
				counts[col] += 1

	var best_color = valid_cols[0]
	var max_count = -1
	for col in valid_cols:
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

	if c_col in ["wild", "special", "colorless"]:
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
	var last_step = int(match_context.get("last_penalty_step", 0))
	var active_color = str(match_context.get("active_color", ""))
	var active_side = str(match_context.get("active_side", "light"))

	# If there is a pending penalty draw, bot must counter-stack (or use shield) if allowed
	if pending_penalty > 0:
		var prog = bool(match_context.get("progressive_stacking", false))
		var can_stack_two = bool(match_context.get("stacking_draw_two", true))
		var can_stack_four = bool(match_context.get("stacking_draw_four", true))

		# First check shield custom cards
		for c in hand:
			if c is Dictionary and UnoHouseRulesScript.card_has_action(c, "negate_penalty"):
				return _build_play(c, hand, active_side)

		if prog:
			var best_stack: Dictionary = {}
			var min_pen = 999
			for c in hand:
				if c is Dictionary:
					var pen = UnoHouseRulesScript.get_card_draw_penalty(c)
					if pen > 0 and pen >= maxi(2, last_step) and pen < min_pen:
						min_pen = pen
						best_stack = c
			if not best_stack.is_empty():
				return _build_play(best_stack, hand, active_side)
			return { "type": "ACTION_DRAW_CARD" }

		for c in hand:
			if c is Dictionary and str(c.get("value", "")) == "draw_two" and can_stack_two:
				return _build_play(c, hand, active_side)
		for c in hand:
			if c is Dictionary and str(c.get("value", "")) == "wild_draw_four" and can_stack_four:
				return _build_play(c, hand, active_side)
		return { "type": "ACTION_DRAW_CARD" }

	var playable_cards: Array[Dictionary] = []
	for c in hand:
		if c is Dictionary and is_card_playable(c, top_discard, active_color):
			playable_cards.append(c)

	if playable_cards.is_empty():
		return { "type": "ACTION_DRAW_CARD" }

	# 1. Attack leader if close to winning
	var next_card_count = int(match_context.get("next_player_card_count", 99))
	var next_called_uno = bool(match_context.get("next_player_called_uno", false))
	if next_called_uno or next_card_count <= 2:
		for c in playable_cards:
			var val = str(c.get("value", ""))
			if val in ["skip", "skip_everyone", "draw_two", "draw_four", "draw_five", "reverse", "discard_all"]:
				return _build_play(c, hand, active_side)
		for c in playable_cards:
			if str(c.get("value", "")) in ["wild_draw_ten", "wild_draw_six", "wild_draw_four", "wild_reverse_draw_four", "wild_draw_color"]:
				return _build_play(c, hand, active_side)

	# 2. Prioritize regular colored cards / Discard All over Wilds
	var regular_playable: Array[Dictionary] = []
	for c in playable_cards:
		if not (str(c.get("color", "")) in ["wild", "special", "colorless"]):
			regular_playable.append(c)

	if not regular_playable.is_empty():
		return _build_play(regular_playable[0], hand, active_side)

	# 3. Play standard Wild before heavy Wilds
	for c in playable_cards:
		if str(c.get("value", "")) == "wild":
			return _build_play(c, hand, active_side)

	# 4. Play any remaining Wild / Custom card
	return _build_play(playable_cards[0], hand, active_side)

func _build_play(c: Dictionary, hand: Array, active_side: String) -> Dictionary:
	var act = {
		"type": "ACTION_PLAY_CARD",
		"card_id": str(c.get("id", c.get("uid", "")))
	}
	if str(c.get("color", "")) in ["wild", "special", "colorless"]:
		act["chosen_color"] = choose_wild_color(hand, active_side)
	return act
