# uno_house_rules.gd
# Configurable UNO House Rules & Combinable Expansions (No Mercy, UNO Flip, Progressive Stacking, Mercy Limit, Custom Cards)
class_name UnoHouseRules
extends RefCounted

var stacking_draw_two: bool = false
var stacking_draw_four: bool = false
var jump_in: bool = false
var seven_zero_passing: bool = false
var draw_to_match: bool = false
var force_play: bool = false
var bluff_challenge: bool = false

# Expansion & Custom Rule settings
var expansion_no_mercy: bool = false
var expansion_flip: bool = false
var progressive_stacking: bool = false
var mercy_hand_limit: int = 0
var skip_everyone_enabled: bool = false
var discard_all_enabled: bool = false
var custom_cards: Array = []

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

	expansion_no_mercy = bool(config.get("expansion_no_mercy", false))
	expansion_flip = bool(config.get("expansion_flip", false))
	progressive_stacking = bool(config.get("progressive_stacking", expansion_no_mercy))
	if config.has("mercy_hand_limit"):
		mercy_hand_limit = clampi(int(config.get("mercy_hand_limit", 0)), 0, 100)
	else:
		mercy_hand_limit = 25 if expansion_no_mercy else 0
	skip_everyone_enabled = bool(config.get("skip_everyone_enabled", expansion_no_mercy))
	discard_all_enabled = bool(config.get("discard_all_enabled", expansion_no_mercy))

	var raw_custom = config.get("custom_cards", [])
	custom_cards = raw_custom.duplicate(true) if raw_custom is Array else []

func to_dict() -> Dictionary:
	return {
		"stacking_draw_two": stacking_draw_two,
		"stacking_draw_four": stacking_draw_four,
		"jump_in": jump_in,
		"seven_zero_passing": seven_zero_passing,
		"draw_to_match": draw_to_match,
		"force_play": force_play,
		"bluff_challenge": bluff_challenge,
		"expansion_no_mercy": expansion_no_mercy,
		"expansion_flip": expansion_flip,
		"progressive_stacking": progressive_stacking,
		"mercy_hand_limit": mercy_hand_limit,
		"skip_everyone_enabled": skip_everyone_enabled,
		"discard_all_enabled": discard_all_enabled,
		"custom_cards": custom_cards.duplicate(true)
	}

static func get_card_draw_penalty(card: Dictionary) -> int:
	var val = str(card.get("value", "")).to_lower()
	match val:
		"draw_one": return 1
		"draw_two", "wild_draw_two": return 2
		"draw_four", "wild_draw_four", "wild_reverse_draw_four": return 4
		"draw_five": return 5
		"wild_draw_six": return 6
		"wild_draw_ten": return 10

	if card.has("actions") and card["actions"] is Array:
		var total = 0
		for act in card["actions"]:
			if act is Dictionary and str(act.get("type", "")) == "draw_cards":
				total += int(act.get("count", 0))
		if total > 0:
			return total
	return 0

static func card_has_action(card: Dictionary, action_type: String) -> bool:
	if not (card.has("actions") and card["actions"] is Array):
		return false
	for act in card["actions"]:
		if act is Dictionary and str(act.get("type", "")) == action_type:
			return true
	return false

func can_stack(card: Dictionary, pending_penalty: int, last_penalty_step: int = 0) -> bool:
	if pending_penalty <= 0:
		return false
	if card_has_action(card, "negate_penalty"):
		return true

	var pen = get_card_draw_penalty(card)
	if progressive_stacking or expansion_no_mercy:
		return pen > 0 and pen >= maxi(2, last_penalty_step)

	var val = str(card.get("value", ""))
	if val == "draw_two" and stacking_draw_two:
		return true
	if val == "wild_draw_four" and stacking_draw_four:
		return true
	if bool(card.get("is_custom", false)) and pen >= maxi(2, last_penalty_step) and (stacking_draw_two or stacking_draw_four):
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
