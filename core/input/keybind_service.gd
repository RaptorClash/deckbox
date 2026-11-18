# core/input/keybind_service.gd
# Remappable keyboard shortcut configuration & matcher for DeckBox.
class_name KeybindService
extends RefCounted

const ACTION_ORDER: Array[String] = [
	"nav_left",
	"nav_right",
	"play_card",
	"draw_card",
	"call_uno",
	"reaction_action",
	"sort_hand",
	"shuffle_hand",
	"cycle_view",
	"jukebox_next"
]

const DEFAULT_BINDINGS: Dictionary = {
	"nav_left": KEY_LEFT,
	"nav_right": KEY_RIGHT,
	"play_card": KEY_SPACE,
	"draw_card": KEY_E,
	"call_uno": KEY_U,
	"reaction_action": KEY_C,
	"sort_hand": KEY_S,
	"shuffle_hand": KEY_R,
	"cycle_view": KEY_V,
	"jukebox_next": KEY_M
}

var _bindings: Dictionary = {}

func _init(initial: Dictionary = {}) -> void:
	reset_to_defaults()
	if not initial.is_empty():
		load_from_dict(initial)

static func get_action_order() -> Array[String]:
	return ACTION_ORDER.duplicate()

func get_keybind(action_id: String) -> int:
	if _bindings.has(action_id):
		return int(_bindings[action_id])
	return int(DEFAULT_BINDINGS.get(action_id, 0))

func set_keybind(action_id: String, keycode: int) -> void:
	if not DEFAULT_BINDINGS.has(action_id) or keycode <= 0:
		return
	_bindings[action_id] = keycode

func reset_to_defaults() -> void:
	_bindings.clear()
	for k in DEFAULT_BINDINGS.keys():
		_bindings[k] = int(DEFAULT_BINDINGS[k])

func load_from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	for k in DEFAULT_BINDINGS.keys():
		if d.has(k):
			var code := int(d[k])
			if code > 0:
				_bindings[k] = code

func to_dict() -> Dictionary:
	return _bindings.duplicate(true)

func matches_event(action_id: String, event: InputEventKey) -> bool:
	if event == null or not event.pressed or event.echo:
		return false
	var bound := get_keybind(action_id)
	var pressed_code: int = int(event.keycode)
	if pressed_code == 0:
		pressed_code = int(event.physical_keycode)
	if pressed_code == bound:
		return true
	# Helpful secondary aliases when action still uses factory default key
	if bound == int(DEFAULT_BINDINGS.get(action_id, 0)):
		match action_id:
			"nav_left":
				return pressed_code == KEY_A
			"nav_right":
				return pressed_code == KEY_D
			"play_card":
				return pressed_code == KEY_ENTER or pressed_code == KEY_KP_ENTER
	return false

static func get_key_display_name(keycode: int) -> String:
	if keycode <= 0:
		return "---"
	match keycode:
		KEY_SPACE:
			return "Space"
		KEY_ENTER, KEY_KP_ENTER:
			return "Enter"
		KEY_LEFT:
			return "← Left"
		KEY_RIGHT:
			return "→ Right"
		KEY_UP:
			return "↑ Up"
		KEY_DOWN:
			return "↓ Down"
	var txt := OS.get_keycode_string(keycode)
	return txt if not txt.is_empty() else str(keycode)
