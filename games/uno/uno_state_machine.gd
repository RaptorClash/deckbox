# uno_state_machine.gd
# UNO Turn and Phase State Machine
class_name UnoStateMachine
extends RefCounted

enum State {
	STATE_ROUND_START,
	STATE_AWAIT_ACTION,
	STATE_AWAIT_COLOR_CHOICE,
	STATE_AWAIT_SWAP_TARGET,
	STATE_AWAIT_CHALLENGE,
	STATE_ROUND_END,
	STATE_MATCH_END
}

var current_state: int = State.STATE_ROUND_START

func set_state(s: int) -> void:
	current_state = s

func get_state() -> int:
	return current_state

func get_state_name() -> String:
	match current_state:
		State.STATE_ROUND_START:
			return "STATE_ROUND_START"
		State.STATE_AWAIT_ACTION:
			return "STATE_AWAIT_ACTION"
		State.STATE_AWAIT_COLOR_CHOICE:
			return "STATE_AWAIT_COLOR_CHOICE"
		State.STATE_AWAIT_SWAP_TARGET:
			return "STATE_AWAIT_SWAP_TARGET"
		State.STATE_AWAIT_CHALLENGE:
			return "STATE_AWAIT_CHALLENGE"
		State.STATE_ROUND_END:
			return "STATE_ROUND_END"
		State.STATE_MATCH_END:
			return "STATE_MATCH_END"
		_:
			return "STATE_UNKNOWN"

func resolve_timeout(_state: int, context: Dictionary) -> Dictionary:
	# Clean timeout resolution returning fallback action
	match current_state:
		State.STATE_AWAIT_COLOR_CHOICE:
			current_state = State.STATE_AWAIT_ACTION
			return { "action": "set_color", "color": "red" }
		State.STATE_AWAIT_SWAP_TARGET:
			current_state = State.STATE_AWAIT_ACTION
			var next_s = (int(context.get("current_seat", 0)) + 1) % int(context.get("player_count", 2))
			return { "action": "swap_target", "seat": next_s }
		_:
			return { "action": "draw_card" }
