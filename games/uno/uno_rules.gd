# uno_rules.gd
# Headless UNO Rules Engine: 108 Card Composition, Matching, Reshuffle & Scoring
class_name UnoRules
extends RefCounted

const COLORS: Array[String] = ["red", "blue", "green", "yellow"]
const NUMBERS: Array[String] = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
const ACTIONS: Array[String] = ["skip", "reverse", "draw_two"]
const WILDS: Array[String] = ["wild", "wild_draw_four"]

var draw_pile: Array = []
var discard_pile: Array = []
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _init(seed_val: int = 0) -> void:
	init_deck(seed_val)

func init_deck(seed_val: int = 0) -> void:
	if seed_val != 0:
		rng.seed = seed_val
	else:
		rng.randomize()

	draw_pile = []
	discard_pile = []
	var card_seq = 0

	# 1. 4 Zero cards (1 per color)
	for col in COLORS:
		card_seq += 1
		var uid = "uno_%s_0_%d" % [col, card_seq]
		draw_pile.append({
			"id": uid,
			"uid": uid,
			"color": col,
			"value": "0"
		})

	# 2. 72 Number cards 1-9 (4 colors * 9 numbers * 2 copies)
	for col in COLORS:
		for num in range(1, 10):
			for _copy in range(2):
				card_seq += 1
				var uid = "uno_%s_%d_%d" % [col, num, card_seq]
				draw_pile.append({
					"id": uid,
					"uid": uid,
					"color": col,
					"value": str(num)
				})

	# 3. 24 Action cards (4 colors * 3 actions * 2 copies)
	for act in ACTIONS:
		for col in COLORS:
			for _copy in range(2):
				card_seq += 1
				var uid = "uno_%s_%s_%d" % [col, act, card_seq]
				draw_pile.append({
					"id": uid,
					"uid": uid,
					"color": col,
					"value": act
				})

	# 4. 8 Wild cards (4 standard Wild, 4 Wild Draw Four)
	for _copy in range(4):
		card_seq += 1
		var uid_w = "uno_wild_%d" % card_seq
		draw_pile.append({
			"id": uid_w,
			"uid": uid_w,
			"color": "wild",
			"value": "wild"
		})

	for _copy in range(4):
		card_seq += 1
		var uid_w4 = "uno_wild_draw_four_%d" % card_seq
		draw_pile.append({
			"id": uid_w4,
			"uid": uid_w4,
			"color": "wild",
			"value": "wild_draw_four"
		})

	# Deterministic Fisher-Yates shuffle
	_shuffle_draw_pile()

func _shuffle_draw_pile() -> void:
	for i in range(draw_pile.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var tmp = draw_pile[i]
		draw_pile[i] = draw_pile[j]
		draw_pile[j] = tmp

func get_draw_pile() -> Array:
	return draw_pile

func get_draw_pile_count() -> int:
	return draw_pile.size()

func get_top_discard() -> Dictionary:
	return discard_pile.back() if discard_pile.size() > 0 else {}

func debug_set_piles(p_draw: Array, p_discard: Array) -> void:
	draw_pile = p_draw.duplicate(true)
	discard_pile = p_discard.duplicate(true)

func draw_card() -> Variant:
	if draw_pile.size() > 0:
		return draw_pile.pop_back()

	if discard_pile.size() > 1:
		var top = discard_pile.pop_back()
		draw_pile = discard_pile
		discard_pile = [top]
		_shuffle_draw_pile()
		return draw_pile.pop_back()

	# Both piles exhausted: graceful handling without crashing
	return null

func is_card_matching(card: Dictionary, top_card: Dictionary, active_color: String = "") -> bool:
	if card.is_empty():
		return false
	if top_card.is_empty():
		return true

	var card_col = str(card.get("color", ""))
	var card_val = str(card.get("value", ""))

	var target_col = active_color if not active_color.is_empty() else str(top_card.get("color", ""))
	var top_val = str(top_card.get("value", ""))

	if card_col == "wild":
		return true
	if card_col == target_col:
		return true
	if not card_val.is_empty() and card_val == top_val:
		return true

	return false

func get_card_points(card: Dictionary) -> int:
	var val = str(card.get("value", ""))
	if val in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]:
		return int(val)
	if val in ["skip", "reverse", "draw_two"]:
		return 20
	if val in ["wild", "wild_draw_four"]:
		return 50
	return 0

func calculate_hand_points(hand: Array) -> int:
	var sum = 0
	for c in hand:
		if c is Dictionary:
			sum += get_card_points(c)
	return sum
