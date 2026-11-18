# core/visuals/card_flight_animator.gd
# Parabolic 3D Card Flight Tweens & Floating Special-Card Callouts
class_name CardFlightAnimator
extends Node

const CardTextureGenScript = preload("res://core/visuals/card_texture_generator.gd")
const UIThemeScript = preload("res://core/visuals/deckbox_ui_theme.gd")

var _speed_mode: String = "normal"

func set_speed_mode(mode: String) -> void:
	var m = mode.to_lower().strip_edges()
	if m in ["normal", "fast", "instant"]:
		_speed_mode = m
	else:
		_speed_mode = "normal"

func get_speed_mode() -> String:
	return _speed_mode

func get_flight_duration() -> float:
	match _speed_mode:
		"instant": return 0.0
		"fast": return 0.14
		_: return 0.28

func get_bot_delay() -> float:
	match _speed_mode:
		"instant": return 0.0
		"fast": return 0.24
		_: return 0.65

func animate_3d_card_arc(
	parent_3d: Node3D,
	card_scene: PackedScene,
	card_data: Dictionary,
	from_pos: Vector3,
	to_pos: Vector3,
	to_rot_deg: Vector3,
	card_scale: Vector3,
	skin_id: String = "classic_arcade",
	colorblind: bool = true,
	face_up: bool = true,
	on_complete: Callable = Callable()
) -> void:
	var dur = get_flight_duration()
	if dur <= 0.0 or not is_inside_tree() or parent_3d == null or not parent_3d.is_inside_tree() or card_scene == null:
		if on_complete.is_valid():
			on_complete.call()
		return

	var flying = card_scene.instantiate()
	if not (flying is Node3D):
		if on_complete.is_valid():
			on_complete.call()
		return

	flying.position = from_pos
	flying.rotation_degrees = Vector3(45.0, 0.0, 0.0 if face_up else 180.0)
	flying.scale = card_scale * 0.92
	CardTextureGenScript.apply_card_materials_to_mesh(flying, card_data, skin_id, colorblind, face_up)
	parent_3d.add_child(flying)

	var arc_height = 0.24
	var start_rot = flying.rotation_degrees
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_method(
		func(t: float):
			if not is_instance_valid(flying):
				return
			var pos = from_pos.lerp(to_pos, t)
			pos.y += sin(t * PI) * arc_height
			flying.position = pos
			flying.rotation_degrees = start_rot.lerp(to_rot_deg, t),
		0.0,
		1.0,
		dur
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(flying, "scale", card_scale, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	tween.chain().tween_callback(func():
		if is_instance_valid(flying):
			flying.queue_free()
		if on_complete.is_valid():
			on_complete.call()
	)

func animate_special_callout(parent_control: Control, text: String, accent_color: Color = Color(1.0, 0.82, 0.2)) -> void:
	var dur = get_flight_duration()
	if dur <= 0.0 or parent_control == null or not parent_control.is_inside_tree():
		return

	var pill = PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_theme_stylebox_override("panel", UIThemeScript.make_glass_panel(Color(0.06, 0.08, 0.14, 0.92), accent_color, 20, 14))

	var lbl = Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 28)
	lbl.add_theme_color_override("font_color", accent_color.lightened(0.35))
	pill.add_child(lbl)

	parent_control.add_child(pill)
	var vp_size = parent_control.size
	pill.reset_size()
	pill.position = Vector2((vp_size.x - pill.size.x) * 0.5, vp_size.y * 0.22)
	pill.pivot_offset = pill.size * 0.5
	pill.scale = Vector2(0.55, 0.55)
	pill.modulate.a = 0.0

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(pill, "scale", Vector2(1.06, 1.06), dur * 0.85).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(pill, "modulate:a", 1.0, dur * 0.5)
	tween.chain().tween_interval(dur * 1.4)
	tween.chain().tween_property(pill, "modulate:a", 0.0, dur * 0.8)
	tween.parallel().tween_property(pill, "position:y", pill.position.y - 26.0, dur * 0.8)
	tween.chain().tween_callback(func():
		if is_instance_valid(pill):
			pill.queue_free()
	)
