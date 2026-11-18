# games/uno/ui/radial_color_wheel.gd
# Interactive 4-Quadrant Radial Wild Color Wheel Overlay (Light Side & UNO Flip Dark Side)
class_name RadialColorWheel
extends Control

signal color_selected(color_name: String)
signal canceled

const LIGHT_QUADRANTS: Array[Dictionary] = [
	{ "id": "red",    "label": "RED ▲",    "color": Color(0.90, 0.16, 0.16), "start": PI,        "end": PI * 1.5 },
	{ "id": "blue",   "label": "BLUE ◆",   "color": Color(0.12, 0.44, 0.94), "start": PI * 1.5,  "end": TAU },
	{ "id": "green",  "label": "GREEN ●",  "color": Color(0.14, 0.72, 0.32), "start": 0.0,       "end": PI * 0.5 },
	{ "id": "yellow", "label": "YELLOW ★", "color": Color(0.96, 0.76, 0.08), "start": PI * 0.5,  "end": PI }
]

const DARK_QUADRANTS: Array[Dictionary] = [
	{ "id": "pink",   "label": "PINK ▲",   "color": Color(0.94, 0.18, 0.58), "start": PI,        "end": PI * 1.5 },
	{ "id": "teal",   "label": "TEAL ◆",   "color": Color(0.08, 0.78, 0.76), "start": PI * 1.5,  "end": TAU },
	{ "id": "purple", "label": "PURPLE ●", "color": Color(0.56, 0.20, 0.92), "start": 0.0,       "end": PI * 0.5 },
	{ "id": "orange", "label": "ORANGE ★", "color": Color(0.98, 0.46, 0.08), "start": PI * 0.5,  "end": PI }
]

const INNER_R: float = 48.0
const OUTER_R: float = 148.0

var is_dark_side: bool = false
var _hovered_id: String = ""
var _open_anim: float = 1.0

func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func set_dark_side(dark: bool) -> void:
	is_dark_side = dark
	queue_redraw()

func get_active_quadrants() -> Array[Dictionary]:
	return DARK_QUADRANTS if is_dark_side else LIGHT_QUADRANTS

func open_wheel() -> void:
	_hovered_id = ""
	visible = true
	if is_inside_tree():
		_open_anim = 0.35
		var tw = create_tween()
		tw.tween_method(
			func(v: float):
				_open_anim = v
				queue_redraw(),
			0.35, 1.0, 0.18
		).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_open_anim = 1.0
	queue_redraw()

func close_wheel() -> void:
	visible = false
	_hovered_id = ""

func choose_color(color_name: String) -> void:
	var c = color_name.to_lower().strip_edges()
	close_wheel()
	color_selected.emit(c)

func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	var center = size * 0.5
	if event is InputEventMouseMotion:
		var prev = _hovered_id
		_hovered_id = _hit_test(event.position - center)
		if prev != _hovered_id:
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var hit = _hit_test(event.position - center)
		if not hit.is_empty():
			choose_color(hit)
		elif (event.position - center).length() > OUTER_R + 28.0:
			close_wheel()
			canceled.emit()
		accept_event()

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close_wheel()
		canceled.emit()
		get_viewport().set_input_as_handled()

func _hit_test(delta: Vector2) -> String:
	var dist = delta.length()
	if dist < INNER_R or dist > OUTER_R + 18.0:
		return ""
	var ang = atan2(delta.y, delta.x)
	if ang < 0.0:
		ang += TAU
	for q in get_active_quadrants():
		if ang >= float(q["start"]) and ang < float(q["end"]):
			return str(q["id"])
	return ""

func _draw() -> void:
	if not visible:
		return
	var center = size * 0.5
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.06, 0.62))

	var font = ThemeDB.fallback_font
	var outer_base = OUTER_R * _open_anim
	var inner_base = INNER_R * _open_anim

	for q in get_active_quadrants():
		var qid = str(q["id"])
		var is_hov = (qid == _hovered_id)
		var r_out = outer_base + (12.0 if is_hov else 0.0)
		var col: Color = q["color"]
		if is_hov:
			col = col.lightened(0.18)

		var a0 = float(q["start"]) + 0.045
		var a1 = float(q["end"]) - 0.045
		var pts = PackedVector2Array()
		var segs = 20
		for i in range(segs + 1):
			var a = lerpf(a0, a1, float(i) / float(segs))
			pts.append(center + Vector2(cos(a), sin(a)) * r_out)
		for i in range(segs, -1, -1):
			var a = lerpf(a0, a1, float(i) / float(segs))
			pts.append(center + Vector2(cos(a), sin(a)) * inner_base)

		draw_colored_polygon(pts, col)
		if is_hov:
			draw_polyline(pts, Color.WHITE, 3.0, true)

		var mid_a = (a0 + a1) * 0.5
		var lbl_pos = center + Vector2(cos(mid_a), sin(mid_a)) * ((inner_base + r_out) * 0.5)
		var lbl = str(q["label"])
		var fsize = 14
		var tsize = font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_CENTER, -1, fsize)
		draw_string(font, lbl_pos - Vector2(tsize.x * 0.5, -tsize.y * 0.3), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color.WHITE)

	draw_circle(center, inner_base - 2.0, Color(0.06, 0.08, 0.14, 0.96))
	draw_arc(center, inner_base - 2.0, 0.0, TAU, 36, Color(0.98, 0.78, 0.24, 0.85), 2.5, true)
	var hub_txt = "DARK" if is_dark_side else "COLOR"
	var h_size = font.get_string_size(hub_txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
	draw_string(font, center - Vector2(h_size.x * 0.5, -h_size.y * 0.3), hub_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.95, 0.97, 1.0))
