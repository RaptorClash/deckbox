# core/qol/accessibility_symbols.gd
# Standardized geometric symbols, accessible screen-reader labels, and playable card highlights.
class_name AccessibilitySymbols extends RefCounted

const SYMBOL_MAP = {
	"red":    { "shape": "triangle", "char": "▲", "name": "Triangle", "color": Color(0.92, 0.22, 0.22) },
	"blue":   { "shape": "diamond",  "char": "◆", "name": "Diamond",  "color": Color(0.18, 0.45, 0.95) },
	"green":  { "shape": "circle",   "char": "●", "name": "Circle",   "color": Color(0.18, 0.75, 0.32) },
	"yellow": { "shape": "star",     "char": "★", "name": "Star",     "color": Color(0.95, 0.82, 0.10) },
	"pink":   { "shape": "triangle", "char": "▲", "name": "Triangle", "color": Color(0.96, 0.25, 0.65) },
	"teal":   { "shape": "diamond",  "char": "◆", "name": "Diamond",  "color": Color(0.10, 0.82, 0.80) },
	"purple": { "shape": "circle",   "char": "●", "name": "Circle",   "color": Color(0.62, 0.24, 0.95) },
	"orange": { "shape": "star",     "char": "★", "name": "Star",     "color": Color(1.00, 0.52, 0.10) },
	"wild":   { "shape": "asterisk", "char": "✱", "name": "Asterisk", "color": Color(0.65, 0.25, 0.85) }
}

static func get_symbol(color_name: String) -> Dictionary:
	var key = color_name.to_lower()
	if SYMBOL_MAP.has(key):
		return SYMBOL_MAP[key]
	return { "shape": "unknown", "char": "?", "name": "Unknown", "color": Color.WHITE }

static func get_char(color_name: String) -> String:
	return str(get_symbol(color_name).get("char", "?"))

static func get_shape_name(color_name: String) -> String:
	return str(get_symbol(color_name).get("name", "Unknown"))

static func get_accessible_label(card: Dictionary) -> String:
	var color = str(card.get("color", "wild")).to_lower()
	var sym = get_symbol(color)
	var shape = sym.get("name", "Unknown")
	var type = str(card.get("type", "number")).replace("_", " ").capitalize()
	var value = card.get("value")

	var color_cap = color.capitalize()

	if color == "wild":
		if type == "Wild Draw Four":
			return "Wild Draw Four (Asterisk, +4 to next player)"
		return "Wild Card (Asterisk, choose color)"

	if value != null:
		return "%s %s (%s %s)" % [color_cap, str(value), shape, type]
	else:
		return "%s %s (%s)" % [color_cap, type, shape]

static func get_highlight_border_color(playable: bool, high_contrast: bool = false) -> Color:
	if not playable:
		return Color(0.2, 0.2, 0.25, 0.5)
	if high_contrast:
		return Color(1.0, 1.0, 0.0, 1.0) # High-contrast yellow
	return Color(0.2, 0.85, 1.0, 0.9)     # Electric cyan highlight

static func calculate_pulse_alpha(pulse_time: float, min_alpha: float = 0.4, max_alpha: float = 1.0, freq: float = 2.0) -> float:
	var wave = (sin(pulse_time * freq * TAU) + 1.0) / 2.0
	return lerpf(min_alpha, max_alpha, wave)

static func draw_card_symbol(canvas: CanvasItem, center: Vector2, radius: float, color_name: String, fill_color: Color = Color.WHITE) -> void:
	if canvas == null:
		return
	var key = color_name.to_lower()
	match key:
		"red", "pink": # Triangle
			var pts = PackedVector2Array([
				center + Vector2(0, -radius),
				center + Vector2(-radius * 0.866, radius * 0.5),
				center + Vector2(radius * 0.866, radius * 0.5)
			])
			canvas.draw_colored_polygon(pts, fill_color)

		"blue", "teal": # Diamond
			var pts = PackedVector2Array([
				center + Vector2(0, -radius),
				center + Vector2(radius * 0.75, 0),
				center + Vector2(0, radius),
				center + Vector2(-radius * 0.75, 0)
			])
			canvas.draw_colored_polygon(pts, fill_color)

		"green", "purple": # Circle
			canvas.draw_circle(center, radius, fill_color)

		"yellow", "orange": # Star (5 points)
			var pts = PackedVector2Array()
			var inner_r = radius * 0.4
			for i in range(10):
				var ang = -PI / 2.0 + i * (TAU / 10.0)
				var r = radius if i % 2 == 0 else inner_r
				pts.append(center + Vector2(cos(ang) * r, sin(ang) * r))
			canvas.draw_colored_polygon(pts, fill_color)

		"wild", _: # Asterisk (3 intersecting lines)
			var w = maxf(1.5, radius * 0.25)
			for i in range(3):
				var ang = i * (PI / 3.0)
				var offset = Vector2(cos(ang) * radius, sin(ang) * radius)
				canvas.draw_line(center - offset, center + offset, fill_color, w, true)
