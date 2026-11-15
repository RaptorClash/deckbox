# anti_leak_filter.gd
# Host-Authoritative Anti-Leak State Projection Filter
class_name AntiLeakFilter
extends RefCounted

## Projects the public table state for shared displays / spectators / broadcasts.
## Guarantees ZERO leaks of hidden draw pile ordering, upcoming cards, or player hands.
static func filter_public_state(game: Object) -> Dictionary:
	var match_id = str(game.get("match_id")) if game.get("match_id") != null else ""
	var status = str(game.get("status")) if game.get("status") != null else "in_progress"

	var draw_count = 0
	if game.has_method("get_draw_pile_count"):
		draw_count = game.get_draw_pile_count()
	elif "draw_pile" in game and game.draw_pile is Array:
		draw_count = game.draw_pile.size()

	var turn_seat = 0
	if "current_turn_seat" in game:
		turn_seat = game.current_turn_seat
	elif "turn_seat" in game:
		turn_seat = game.turn_seat
	elif "active_seat" in game:
		turn_seat = game.active_seat

	var direction = 1
	if "direction" in game:
		direction = game.direction

	var raw_top = {}
	if game.has_method("get_top_discard"):
		raw_top = game.get_top_discard()
	elif "top_discard" in game and game.top_discard != null:
		raw_top = game.top_discard
	elif "discard_pile" in game and game.discard_pile is Array and game.discard_pile.size() > 0:
		raw_top = game.discard_pile.back()

	var sanitized_top = {}
	if raw_top is Dictionary and not raw_top.is_empty():
		sanitized_top["color"] = str(raw_top.get("color", ""))
		sanitized_top["value"] = str(raw_top.get("value", ""))
		if raw_top.has("action"):
			sanitized_top["action"] = raw_top["action"]
		if raw_top.has("chosen_color"):
			sanitized_top["chosen_color"] = raw_top["chosen_color"]

	var player_summaries: Array[Dictionary] = []
	if "players" in game and game.players is Array:
		for p in game.players:
			if p is Dictionary:
				var p_id = str(p.get("player_id", ""))
				var card_count = 0
				if game.has_method("get_player_card_count"):
					card_count = game.get_player_card_count(p_id)
				elif "player_hands" in game and game.player_hands is Dictionary and game.player_hands.has(p_id):
					card_count = game.player_hands[p_id].size()
				elif "hands" in game and game.hands is Dictionary and game.hands.has(p_id):
					card_count = game.hands[p_id].size()
				elif p.has("card_count"):
					card_count = int(p.get("card_count", 0))

				var summary = {
					"seat": int(p.get("seat", 0)),
					"name": str(p.get("name", "")),
					"card_count": int(card_count),
					"called_uno": bool(p.get("called_uno", false)),
					"is_bot": bool(p.get("is_bot", false))
				}
				player_summaries.append(summary)

	var pub_state = {
		"match_id": match_id,
		"status": status,
		"draw_pile_count": int(draw_count),
		"top_discard": sanitized_top,
		"turn_seat": int(turn_seat),
		"current_turn_seat": int(turn_seat),
		"direction": int(direction),
		"players": player_summaries
	}

	if "active_color" in game and not str(game.active_color).is_empty():
		pub_state["active_color"] = str(game.active_color)
	if "pending_penalty_draws" in game:
		pub_state["pending_penalty_draws"] = int(game.pending_penalty_draws)

	return pub_state

## Projects the private player view for the requesting player.
## Includes requesting player's real cards with playability flags,
## while strictly masking all opponents as dummy tokens: [{ "masked": true }].
static func filter_player_view(game: Object, player_id: String) -> Dictionary:
	var view = filter_public_state(game)
	view["my_player_id"] = player_id

	var my_seat = -1
	if "players" in game and game.players is Array:
		for p in game.players:
			if p is Dictionary and str(p.get("player_id", "")) == player_id:
				my_seat = int(p.get("seat", -1))
				break
	view["my_seat"] = my_seat

	var raw_hand: Array = []
	if game.has_method("get_player_hand"):
		raw_hand = game.get_player_hand(player_id)
	elif "player_hands" in game and game.player_hands is Dictionary:
		raw_hand = game.player_hands.get(player_id, [])
	elif "hands" in game and game.hands is Dictionary:
		raw_hand = game.hands.get(player_id, [])

	var sanitized_hand: Array[Dictionary] = []
	for card in raw_hand:
		if card is Dictionary:
			var card_id = str(card.get("id", card.get("uid", "")))
			var card_uid = str(card.get("uid", card.get("id", "")))
			var is_playable = false
			if game.has_method("is_card_playable"):
				is_playable = game.is_card_playable(card)

			var clean_card = {
				"id": card_id,
				"uid": card_uid,
				"color": str(card.get("color", "")),
				"value": str(card.get("value", "")),
				"playable": bool(is_playable)
			}
			if card.has("action"):
				clean_card["action"] = card["action"]
			if card.has("actions"):
				clean_card["actions"] = card["actions"]
			if card.has("custom_action"):
				clean_card["custom_action"] = card["custom_action"]
			if card.has("texture_path"):
				clean_card["texture_path"] = card["texture_path"]
			if card.has("face_texture"):
				clean_card["face_texture"] = card["face_texture"]
			sanitized_hand.append(clean_card)

	view["hand"] = sanitized_hand
	view["my_hand"] = sanitized_hand

	var opponent_hands: Dictionary = {}
	if "players" in game and game.players is Array:
		for p in game.players:
			if p is Dictionary:
				var p_id = str(p.get("player_id", ""))
				if p_id != player_id:
					var opp_seat = int(p.get("seat", 0))
					var opp_count = 0
					if game.has_method("get_player_card_count"):
						opp_count = game.get_player_card_count(p_id)
					elif "player_hands" in game and game.player_hands is Dictionary and game.player_hands.has(p_id):
						opp_count = game.player_hands[p_id].size()
					elif "hands" in game and game.hands is Dictionary and game.hands.has(p_id):
						opp_count = game.hands[p_id].size()
					elif p.has("card_count"):
						opp_count = int(p.get("card_count", 0))

					var tokens: Array[Dictionary] = []
					for _i in range(opp_count):
						tokens.append({ "masked": true })
					opponent_hands["seat_%d" % opp_seat] = tokens

	view["opponent_hands"] = opponent_hands
	return view
