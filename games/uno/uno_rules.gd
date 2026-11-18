# uno_rules.gd
# Headless UNO Rules Engine: Classic 108 Deck, No Mercy & UNO Flip Expansions, Custom Cards & Reshuffle
class_name UnoRules
extends RefCounted

const COLORS: Array[String] = ["red", "blue", "green", "yellow"]
const DARK_COLORS: Array[String] = ["pink", "teal", "purple", "orange"]
const NUMBERS: Array[String] = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
const ACTIONS: Array[String] = ["skip", "reverse", "draw_two"]
const WILDS: Array[String] = ["wild", "wild_draw_four"]

const SIDE_COLOR_MAP: Dictionary = {
	"red": "pink", "blue": "teal", "green": "purple", "yellow": "orange",
	"pink": "red", "teal": "blue", "purple": "green", "orange": "yellow",
	"wild": "wild"
}

const DARK_VALUE_MAP: Dictionary = {
	"draw_two": "draw_five",
	"skip": "skip_everyone",
	"wild_draw_four": "wild_draw_color"
}

var draw_pile: Array = []
var discard_pile: Array = []
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var auto_expand: bool = false
var _card_seq_counter: int = 0
var _active_rules: Dictionary = {}

func _init(seed_val: int = 0) -> void:
	init_deck(seed_val)

static func calculate_recommended_deck_count(player_count: int, hand_size: int = 7) -> int:
	if player_count <= 0 or hand_size <= 0:
		return 1
	return maxi(1, int(ceil(float(player_count * hand_size) / 35.0)))

func init_deck(seed_val: int = 0, deck_count: int = 1, p_auto_expand: bool = false) -> void:
	_active_rules = {}
	_build_deck_internal(seed_val, deck_count, p_auto_expand)

func init_deck_with_rules(seed_val: int, rules: Dictionary, deck_count: int = 1, p_auto_expand: bool = false) -> void:
	_active_rules = rules.duplicate(true) if rules is Dictionary else {}
	_build_deck_internal(seed_val, deck_count, p_auto_expand)

func _build_deck_internal(seed_val: int, deck_count: int, p_auto_expand: bool) -> void:
	if seed_val != 0:
		rng.seed = seed_val
	else:
		rng.randomize()

	auto_expand = p_auto_expand
	draw_pile = []
	discard_pile = []
	_card_seq_counter = 0

	var count = maxi(1, deck_count)
	for _d in range(count):
		_append_single_108_deck()

	_shuffle_draw_pile()

func _append_single_108_deck() -> void:
	var start_idx = draw_pile.size()

	# 1. 4 Zero cards (1 per color)
	for col in COLORS:
		_card_seq_counter += 1
		var uid = "uno_%s_0_%d" % [col, _card_seq_counter]
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
				_card_seq_counter += 1
				var uid = "uno_%s_%d_%d" % [col, num, _card_seq_counter]
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
				_card_seq_counter += 1
				var uid = "uno_%s_%s_%d" % [col, act, _card_seq_counter]
				draw_pile.append({
					"id": uid,
					"uid": uid,
					"color": col,
					"value": act
				})

	# 4. 8 Wild cards (4 standard Wild, 4 Wild Draw Four)
	for _copy in range(4):
		_card_seq_counter += 1
		var uid_w = "uno_wild_%d" % _card_seq_counter
		draw_pile.append({
			"id": uid_w,
			"uid": uid_w,
			"color": "wild",
			"value": "wild"
		})

	for _copy in range(4):
		_card_seq_counter += 1
		var uid_w4 = "uno_wild_draw_four_%d" % _card_seq_counter
		draw_pile.append({
			"id": uid_w4,
			"uid": uid_w4,
			"color": "wild",
			"value": "wild_draw_four"
		})

	# 5. Expansion: UNO Show 'Em No Mercy
	var no_mercy = bool(_active_rules.get("expansion_no_mercy", false))
	var add_skip_all = no_mercy or bool(_active_rules.get("skip_everyone_enabled", false))
	var add_discard_all = no_mercy or bool(_active_rules.get("discard_all_enabled", false))
	if no_mercy or add_skip_all or add_discard_all:
		for col in COLORS:
			if no_mercy:
				for _copy in range(2):
					_card_seq_counter += 1
					var uid_d4 = "uno_nm_%s_d4_%d" % [col, _card_seq_counter]
					draw_pile.append({ "id": uid_d4, "uid": uid_d4, "color": col, "value": "draw_four" })
			if add_discard_all:
				for _copy in range(2):
					_card_seq_counter += 1
					var uid_da = "uno_nm_%s_da_%d" % [col, _card_seq_counter]
					draw_pile.append({ "id": uid_da, "uid": uid_da, "color": col, "value": "discard_all" })
			if add_skip_all:
				for _copy in range(2):
					_card_seq_counter += 1
					var uid_se = "uno_nm_%s_se_%d" % [col, _card_seq_counter]
					draw_pile.append({ "id": uid_se, "uid": uid_se, "color": col, "value": "skip_everyone" })

	if no_mercy:
		for wild_val in ["wild_reverse_draw_four", "wild_draw_six", "wild_draw_ten", "wild_color_roulette"]:
			for _copy in range(4):
				_card_seq_counter += 1
				var uid_nw = "uno_nm_%s_%d" % [wild_val, _card_seq_counter]
				draw_pile.append({ "id": uid_nw, "uid": uid_nw, "color": "wild", "value": wild_val })

	# 6. Expansion: UNO Flip!
	var flip_enabled = bool(_active_rules.get("expansion_flip", false))
	if flip_enabled:
		for col in COLORS:
			for _copy in range(2):
				_card_seq_counter += 1
				var uid_fl = "uno_flip_%s_%d" % [col, _card_seq_counter]
				draw_pile.append({ "id": uid_fl, "uid": uid_fl, "color": col, "value": "flip" })

	# 7. Custom Cards (user-defined or from CardPack Editor)
	var custom_cards = _active_rules.get("custom_cards", [])
	if custom_cards is Array:
		for cc in custom_cards:
			if not (cc is Dictionary):
				continue
			var cc_id = str(cc.get("id", "custom"))
			var cc_name = str(cc.get("name", cc_id))
			var cc_col = str(cc.get("color", "wild")).to_lower()
			var cc_cnt = clampi(int(cc.get("count", 1)), 1, 20)
			var cc_actions = cc.get("actions", []).duplicate(true) if cc.get("actions", []) is Array else []
			var cc_val = _derive_custom_value(cc_name, cc_actions)
			for _copy in range(cc_cnt):
				_card_seq_counter += 1
				var uid_cc = "uno_custom_%s_%d" % [cc_id, _card_seq_counter]
				draw_pile.append({
					"id": uid_cc,
					"uid": uid_cc,
					"custom_id": cc_id,
					"name": cc_name,
					"color": cc_col,
					"value": cc_val,
					"is_custom": true,
					"actions": cc_actions.duplicate(true)
				})

	# Attach Dark-Side metadata onto newly appended cards when UNO Flip is active, shuffling dark pairing so backs never leak fronts
	if flip_enabled:
		var dark_pairs: Array[Dictionary] = []
		for idx in range(start_idx, draw_pile.size()):
			var c = draw_pile[idx]
			if not c.has("light_color"):
				c["light_color"] = str(c.get("color", "wild"))
			if not c.has("light_value"):
				c["light_value"] = str(c.get("value", "0"))
			var dc = str(c.get("dark_color", SIDE_COLOR_MAP.get(c["light_color"], "wild")))
			var dv = str(c.get("dark_value", DARK_VALUE_MAP.get(c["light_value"], c["light_value"])))
			dark_pairs.append({ "dark_color": dc, "dark_value": dv })
		for i in range(dark_pairs.size() - 1, 0, -1):
			var j = rng.randi_range(0, i)
			var tmp = dark_pairs[i]
			dark_pairs[i] = dark_pairs[j]
			dark_pairs[j] = tmp
		for offset in range(dark_pairs.size()):
			var c = draw_pile[start_idx + offset]
			c["dark_color"] = dark_pairs[offset]["dark_color"]
			c["dark_value"] = dark_pairs[offset]["dark_value"]

static func _derive_custom_value(cname: String, actions: Array) -> String:
	for act in actions:
		if act is Dictionary:
			var t = str(act.get("type", ""))
			if t == "draw_cards":
				return "custom_draw_%d" % int(act.get("count", 1))
			if t == "negate_penalty":
				return "custom_shield"
			if t == "swap_hands":
				return "custom_swap"
			if t == "flip_side":
				return "flip"
			if t == "skip_everyone":
				return "skip_everyone"
	return "custom_%s" % cname.to_lower().replace(" ", "_").substr(0, 10)

static func flip_card_side(card: Dictionary, target_side: String) -> Dictionary:
	if not (card is Dictionary):
		return {}
	if not card.has("light_color"):
		var cur_c = str(card.get("color", "wild"))
		var cur_v = str(card.get("value", "0"))
		if cur_c in DARK_COLORS:
			card["dark_color"] = cur_c
			card["dark_value"] = cur_v
			card["light_color"] = SIDE_COLOR_MAP.get(cur_c, "red")
			card["light_value"] = cur_v
		else:
			card["light_color"] = cur_c
			card["light_value"] = cur_v
			if not card.has("dark_color"):
				card["dark_color"] = SIDE_COLOR_MAP.get(cur_c, "wild")
			if not card.has("dark_value"):
				card["dark_value"] = DARK_VALUE_MAP.get(cur_v, cur_v)

	if target_side == "dark":
		card["color"] = str(card.get("dark_color", SIDE_COLOR_MAP.get(card.get("light_color", "wild"), "wild")))
		card["value"] = str(card.get("dark_value", card.get("light_value", "")))
	else:
		card["color"] = str(card.get("light_color", "wild"))
		card["value"] = str(card.get("light_value", ""))
	return card

static func get_opposite_side_card(card: Dictionary, current_active_side: String = "light") -> Dictionary:
	if not (card is Dictionary) or card.is_empty():
		return { "color": "pink" if current_active_side == "light" else "red", "value": "flip" }

	if current_active_side == "light":
		var l_col = str(card.get("light_color", card.get("color", "wild"))).to_lower()
		var l_val = str(card.get("light_value", card.get("value", "0"))).to_lower()
		var d_col = str(card.get("dark_color", "")).to_lower()
		if d_col.is_empty():
			d_col = str(SIDE_COLOR_MAP.get(l_col, "pink" if l_col != "wild" else "wild"))
		var d_val = str(card.get("dark_value", "")).to_lower()
		if d_val.is_empty():
			d_val = str(DARK_VALUE_MAP.get(l_val, l_val))
		return { "color": d_col, "value": d_val }

	var d_col_cur = str(card.get("dark_color", card.get("color", "wild"))).to_lower()
	var d_val_cur = str(card.get("dark_value", card.get("value", "0"))).to_lower()
	var l_col_out = str(card.get("light_color", "")).to_lower()
	if l_col_out.is_empty():
		l_col_out = str(SIDE_COLOR_MAP.get(d_col_cur, "red" if d_col_cur != "wild" else "wild"))
	var l_val_out = str(card.get("light_value", "")).to_lower()
	if l_val_out.is_empty():
		l_val_out = d_val_cur
		for k in DARK_VALUE_MAP.keys():
			if str(DARK_VALUE_MAP[k]) == d_val_cur:
				l_val_out = str(k)
				break
	return { "color": l_col_out, "value": l_val_out }

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

	if auto_expand:
		_append_single_108_deck()
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

	if card_col == "wild" or card_col == "special" or card_col == "colorless":
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
	if val in ["skip", "reverse", "draw_two", "flip", "discard_all"]:
		return 20
	if val in ["skip_everyone", "draw_four", "draw_five"]:
		return 30
	if val in ["wild", "wild_draw_four", "wild_reverse_draw_four", "wild_color_roulette", "wild_draw_color"]:
		return 50
	if val in ["wild_draw_six", "wild_draw_ten"]:
		return 75
	return 20

func calculate_hand_points(hand: Array) -> int:
	var sum = 0
	for c in hand:
		if c is Dictionary:
			sum += get_card_points(c)
	return sum
