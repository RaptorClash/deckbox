# custom_card_interpreter.gd
# Sandboxed Declarative Action Interpreter with Zero Dynamic GDScript Execution
class_name CustomCardInterpreter
extends RefCounted

const CardPackSchemaScript = preload("res://core/packs/card_pack_schema.gd")

static func execute_card_actions(actions: Array, context: Dictionary) -> Dictionary:
	var accumulated_events: Array[Dictionary] = []
	for i in range(actions.size()):
		var act = actions[i]
		if not (act is Dictionary):
			return {
				"success": false,
				"error": "Action at index %d is not a Dictionary" % i,
				"events": accumulated_events,
				"context": context
			}
		var res = execute_action(act, context)
		if not res.get("success", false):
			return {
				"success": false,
				"error": res.get("error", "Unknown error in action execution"),
				"events": accumulated_events,
				"context": context
			}
		accumulated_events.append_array(res.get("events", []))

	return {
		"success": true,
		"events": accumulated_events,
		"context": context
	}

static func execute_action(action: Dictionary, context: Dictionary) -> Dictionary:
	var val_res = CardPackSchemaScript.validate_action(action)
	if not val_res.get("valid", false):
		return {
			"success": false,
			"error": "Action schema validation failed: %s" % str(val_res.get("errors", [])),
			"events": []
		}

	var action_type = str(action.get("type", ""))
	var events: Array[Dictionary] = []

	var n = int(context.get("player_count", 2))
	if n < 2:
		n = 2
	var current_seat = int(context.get("current_seat", 0))
	var dir = int(context.get("direction", 1))

	match action_type:
		"draw_cards":
			var count = int(action.get("count", 1))
			var target = str(action.get("target", "next"))
			var target_seats: Array[int] = []

			match target:
				"next":
					var next_s = (current_seat + dir + n) % n
					target_seats.append(next_s)
				"all_opponents":
					for s in range(n):
						if s != current_seat:
							target_seats.append(s)
				"chosen":
					var chosen_s = int(action.get("target_seat", (current_seat + dir + n) % n))
					target_seats.append(chosen_s)
				"self":
					target_seats.append(current_seat)

			if context.has("draw_pile") and context.has("hands"):
				for s in target_seats:
					for _c in range(count):
						if context["draw_pile"].size() > 0:
							var drawn = context["draw_pile"].pop_back()
							if context["hands"].has(s):
								context["hands"][s].append(drawn)

			events.append({
				"event": "draw_cards",
				"count": count,
				"target": target,
				"target_seats": target_seats
			})

		"skip_next":
			var count = int(action.get("count", 1))
			context["skip_count"] = int(context.get("skip_count", 0)) + count
			events.append({
				"event": "skip_next",
				"count": count
			})

		"reverse":
			dir = dir * -1
			context["direction"] = dir
			if n == 2:
				context["skip_count"] = int(context.get("skip_count", 0)) + 1
			events.append({
				"event": "reverse",
				"direction": dir
			})

		"choose_color":
			if action.has("chosen_color") and not str(action["chosen_color"]).is_empty():
				var col = str(action["chosen_color"])
				context["active_color"] = col
				events.append({ "event": "choose_color", "color": col })
			else:
				context["awaiting_choice"] = "color"
				events.append({ "event": "choose_color", "awaiting": true })

		"swap_hands":
			var target = str(action.get("target", "choose_opponent"))
			var target_seat = current_seat
			match target:
				"left":
					target_seat = (current_seat + dir + n) % n
				"right":
					target_seat = (current_seat - dir + n) % n
				"choose_opponent":
					target_seat = int(action.get("target_seat", (current_seat + dir + n) % n))

			if context.has("hands") and context["hands"].has(current_seat) and context["hands"].has(target_seat):
				var tmp = context["hands"][current_seat]
				context["hands"][current_seat] = context["hands"][target_seat]
				context["hands"][target_seat] = tmp

			events.append({
				"event": "swap_hands",
				"seat_a": current_seat,
				"seat_b": target_seat,
				"target": target
			})

		"discard_color":
			var color = str(action.get("color", ""))
			var discarded_count = 0
			if context.has("hands") and context["hands"].has(current_seat):
				var hand = context["hands"][current_seat]
				var kept: Array = []
				for c in hand:
					if c is Dictionary and str(c.get("color", "")) == color:
						discarded_count += 1
						if context.has("discard_pile"):
							context["discard_pile"].append(c)
					else:
						kept.append(c)
				context["hands"][current_seat] = kept

			events.append({
				"event": "discard_color",
				"color": color,
				"discarded_count": discarded_count
			})

		"negate_penalty":
			var cancelled = int(context.get("pending_penalty", context.get("pending_penalty_draws", 0)))
			context["pending_penalty"] = 0
			context["pending_penalty_draws"] = 0
			events.append({
				"event": "negate_penalty",
				"cancelled_penalty": cancelled
			})

		"custom_prompt":
			var text = str(action.get("text", ""))
			events.append({
				"event": "custom_prompt",
				"text": text
			})

		"flip_side":
			var cur_side = str(context.get("active_side", "light"))
			var next_side = "dark" if cur_side == "light" else "light"
			context["active_side"] = next_side
			events.append({
				"event": "flip_side",
				"active_side": next_side
			})

		"skip_everyone":
			context["skip_everyone"] = true
			events.append({
				"event": "skip_everyone"
			})

		_:
			return {
				"success": false,
				"error": "Unhandled primitive type: %s" % action_type,
				"events": []
			}

	return {
		"success": true,
		"events": events,
		"context": context
	}
