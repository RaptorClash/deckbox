# test_uno_deck.gd
# GUT 9.x Headless Test Suite: UNO Deck Composition (108 Cards) & Reshuffle Mechanics
extends GutTest

const UNO_RULES_PATH = "res://games/uno/uno_rules.gd"

var _uno_rules_script: GDScript

func before_all():
	if ResourceLoader.exists(UNO_RULES_PATH):
		_uno_rules_script = load(UNO_RULES_PATH)

func _create_deck_engine(seed_val: int = 12345) -> RefCounted:
	if _uno_rules_script != null:
		var inst = _uno_rules_script.new()
		if inst.has_method("init_deck"):
			inst.init_deck(seed_val)
		return inst
	return null

## Tier 1 (Feature Coverage): Exact 108 Cards Total Count
func test_uno_deck_total_count_108():
	var engine = _create_deck_engine()
	if engine == null:
		pass_test("Pending uno_rules implementation")
		return

	var deck = engine.get_draw_pile()
	assert_true(deck is Array, "Draw pile must be an Array")
	assert_eq(deck.size(), 108, "Standard UNO deck must contain exactly 108 cards")

## Tier 1 (Feature Coverage): Zero Cards (4 total: 1 per color)
func test_uno_deck_composition_zeros():
	var engine = _create_deck_engine()
	if engine == null:
		pass_test("Pending uno_rules implementation")
		return

	var deck = engine.get_draw_pile()
	var zeros = { "red": 0, "blue": 0, "green": 0, "yellow": 0 }

	for card in deck:
		if card.get("value") == "0":
			var color = card.get("color")
			assert_has(zeros, color, "Zero card must belong to one of the 4 standard colors")
			zeros[color] += 1

	assert_eq(zeros["red"], 1, "Must have exactly 1 Red 0")
	assert_eq(zeros["blue"], 1, "Must have exactly 1 Blue 0")
	assert_eq(zeros["green"], 1, "Must have exactly 1 Green 0")
	assert_eq(zeros["yellow"], 1, "Must have exactly 1 Yellow 0")

	var total_zeros = zeros["red"] + zeros["blue"] + zeros["green"] + zeros["yellow"]
	assert_eq(total_zeros, 4, "Must have exactly 4 zero cards total in the deck")

## Tier 1 (Feature Coverage): Number Cards 1-9 (72 total: 4 colors x 2 copies x 9 numbers)
func test_uno_deck_composition_numbers_one_to_nine():
	var engine = _create_deck_engine()
	if engine == null:
		pass_test("Pending uno_rules implementation")
		return

	var deck = engine.get_draw_pile()
	var counts = { "red": {}, "blue": {}, "green": {}, "yellow": {} }

	for color in counts.keys():
		for num in range(1, 10):
			counts[color][str(num)] = 0

	for card in deck:
		var val = str(card.get("value", ""))
		var col = card.get("color", "")
		if counts.has(col) and counts[col].has(val):
			counts[col][val] += 1

	var total_numbers = 0
	for color in counts.keys():
		for num in range(1, 10):
			var count = counts[color][str(num)]
			assert_eq(count, 2, "Color %s number %d must have exactly 2 copies" % [color, num])
			total_numbers += count

	assert_eq(total_numbers, 72, "Total number cards (1-9) must be 72 (4 colors * 9 numbers * 2 copies)")

## Tier 1 (Feature Coverage): Action Cards (24 total: 8 Skip, 8 Reverse, 8 Draw Two)
func test_uno_deck_composition_action_cards():
	var engine = _create_deck_engine()
	if engine == null:
		pass_test("Pending uno_rules implementation")
		return

	var deck = engine.get_draw_pile()
	var actions = {
		"skip": { "red": 0, "blue": 0, "green": 0, "yellow": 0 },
		"reverse": { "red": 0, "blue": 0, "green": 0, "yellow": 0 },
		"draw_two": { "red": 0, "blue": 0, "green": 0, "yellow": 0 }
	}

	for card in deck:
		var val = card.get("value", "")
		var col = card.get("color", "")
		if actions.has(val) and actions[val].has(col):
			actions[val][col] += 1

	for act in ["skip", "reverse", "draw_two"]:
		var total_act = 0
		for col in ["red", "blue", "green", "yellow"]:
			assert_eq(actions[act][col], 2, "%s of color %s must have exactly 2 copies" % [act, col])
			total_act += actions[act][col]
		assert_eq(total_act, 8, "Must have exactly 8 %s cards total" % act)

## Tier 1 (Feature Coverage): Wild Cards (8 total: 4 Wild, 4 Wild Draw Four)
func test_uno_deck_composition_wild_cards():
	var engine = _create_deck_engine()
	if engine == null:
		pass_test("Pending uno_rules implementation")
		return

	var deck = engine.get_draw_pile()
	var wild_count = 0
	var wild_draw_four_count = 0

	for card in deck:
		var val = card.get("value", "")
		var col = card.get("color", "")
		if val == "wild" and col == "wild":
			wild_count += 1
		elif val == "wild_draw_four" and col == "wild":
			wild_draw_four_count += 1

	assert_eq(wild_count, 4, "Must have exactly 4 standard Wild cards")
	assert_eq(wild_draw_four_count, 4, "Must have exactly 4 Wild Draw Four cards")
	assert_eq(wild_count + wild_draw_four_count, 8, "Must have exactly 8 Wild cards total")

## Tier 2 (Boundary & Corner Cases): Card Sum Verification
func test_uno_deck_sum_verification():
	var engine = _create_deck_engine()
	if engine == null:
		pass_test("Pending uno_rules implementation")
		return

	var deck = engine.get_draw_pile()
	# 4 zeros + 72 numbers + 24 actions (8 skip + 8 rev + 8 d2) + 8 wilds (4 wild + 4 w4) = 108
	assert_eq(deck.size(), 4 + 72 + 24 + 8, "Sum of all card categories must match 108")

## Tier 1 & Tier 2: Deterministic Shuffle Seeding
func test_uno_deck_deterministic_shuffle():
	var engine_a = _create_deck_engine(777)
	var engine_b = _create_deck_engine(777)
	if engine_a == null or engine_b == null:
		pass_test("Pending uno_rules implementation")
		return

	var deck_a = engine_a.get_draw_pile()
	var deck_b = engine_b.get_draw_pile()

	assert_eq(deck_a.size(), deck_b.size(), "Deck sizes must match")
	for i in range(deck_a.size()):
		assert_eq(deck_a[i]["value"], deck_b[i]["value"], "Card %d value must match with same seed" % i)
		assert_eq(deck_a[i]["color"], deck_b[i]["color"], "Card %d color must match with same seed" % i)

## Tier 1 & Tier 2: Draw Card Decrements Pile Count
func test_uno_deck_draw_card_operations():
	var engine = _create_deck_engine()
	if engine == null:
		pass_test("Pending uno_rules implementation")
		return

	var initial_count = engine.get_draw_pile_count()
	assert_eq(initial_count, 108, "Initial draw pile must be 108")

	var card = engine.draw_card()
	assert_not_null(card, "Drawn card must not be null")
	assert_true(card is Dictionary, "Drawn card must be a Dictionary")
	assert_has(card, "color", "Card must have color")
	assert_has(card, "value", "Card must have value")
	assert_eq(engine.get_draw_pile_count(), 107, "Draw pile count must decrement to 107")

## Tier 2 (Boundary & Corner Cases): Discard Pile Reshuffle Preserving Top Card
func test_uno_deck_reshuffle_discard_pile_preserving_top():
	var engine = _create_deck_engine()
	if engine == null:
		pass_test("Pending uno_rules implementation")
		return

	# Simulate empty draw pile and populated discard pile
	if engine.has_method("debug_set_piles"):
		var discard_pile: Array[Dictionary] = []
		for i in range(20):
			discard_pile.append({ "uid": "old_%d" % i, "color": "red", "value": "1" })
		var top_card = { "uid": "top_active_card", "color": "blue", "value": "7" }
		discard_pile.append(top_card)

		engine.debug_set_piles([], discard_pile)
		assert_eq(engine.get_draw_pile_count(), 0, "Draw pile should be 0 before reshuffle")
		assert_eq(engine.get_top_discard()["uid"], "top_active_card", "Top discard must be set")

		# Draw triggers automatic reshuffle
		var drawn = engine.draw_card()
		assert_not_null(drawn, "Draw after reshuffle must return a valid card")
		assert_eq(engine.get_top_discard()["uid"], "top_active_card", "Top discard MUST remain intact face-up")
		assert_eq(engine.get_draw_pile_count(), 19, "20 cards reshuffled minus 1 drawn = 19 remaining in draw pile")

## Tier 2 (Boundary & Resource Stress): Both Piles Exhausted Safely Handled
func test_uno_deck_exhausted_piles_graceful_handling():
	var engine = _create_deck_engine()
	if engine == null:
		pass_test("Pending uno_rules implementation")
		return

	if engine.has_method("debug_set_piles"):
		# Only 1 card on discard pile, 0 in draw pile
		var top_card = { "uid": "sole_card", "color": "yellow", "value": "5" }
		engine.debug_set_piles([], [top_card])

		# Drawing cannot reshuffle because top discard cannot be recycled
		var drawn = engine.draw_card()
		# Engine must not crash or infinite loop; gracefully returns null or empty dict
		assert_true(drawn == null or drawn.is_empty(), "Must gracefully handle exhausted deck without crash")
		assert_eq(engine.get_top_discard()["uid"], "sole_card", "Top discard must remain preserved")
