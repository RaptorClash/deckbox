# uno_house_rules.gd
# Configurable UNO House Rules (Stacking, Jump-In, 7-0 Passing, Draw-To-Match)
class_name UnoHouseRules
extends RefCounted

var stacking_draw_two: bool = false
var stacking_draw_four: bool = false
var jump_in: bool = false
var seven_zero_passing: bool = false
var draw_to_match: bool = false
var force_play: bool = false
var bluff_challenge: bool = false

func _init(config: Dictionary = {}) -> void:
	init_from_config(config)

func init_from_config(config: Dictionary) -> void:
	stacking_draw_two = bool(config.get("stacking_draw_two", false))
	stacking_draw_four = bool(config.get("stacking_draw_four", false))
	jump_in = bool(config.get("jump_in", false))
	seven_zero_passing = bool(config.get("seven_zero_passing", false))
	draw_to_match = bool(config.get("draw_to_match", false))
	force_play = bool(config.get("force_play", false))
	bluff_challenge = bool(config.get("bluff_challenge", false))

func to_dict() -> Dictionary:
	return {
		"stacking_draw_two": stacking_draw_two,
		"stacking_draw_four": stacking_draw_four,
		"jump_in": jump_in,
		"seven_zero_passing": seven_zero_passing,
		"draw_to_match": draw_to_match,
		"force_play": force_play,
		"bluff_challenge": bluff_challenge
	}

func can_stack(card: Dictionary, pending_penalty: int) -> bool:
	if pending_penalty <= 0:
		return false
	var val = str(card.get("value", ""))
	if val == "draw_two" and stacking_draw_two:
		return true
	if val == "wild_draw_four" and stacking_draw_four:
		return true
	return false

func can_jump_in(card: Dictionary, top_discard: Dictionary) -> bool:
	if not jump_in:
		return false
	if card.is_empty() or top_discard.is_empty():
		return false
	var card_col = str(card.get("color", ""))
	var top_col = str(top_discard.get("color", ""))
	var card_val = str(card.get("value", ""))
	var top_val = str(top_discard.get("value", ""))

	# Cannot jump in with Wilds
	if card_col == "wild" or top_col == "wild":
		return false

	# Must be exact match of color and value
	return card_col == top_col and card_val == top_val
