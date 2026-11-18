# core/visuals/card_texture_generator.gd
# Procedural high-resolution UNO & Custom Card Texture & 3D Material Generator.
# Supports two built-in visual skins: "classic_arcade" and "minimal_dark".
class_name CardTextureGenerator
extends RefCounted

const TEX_W: int = 192
const TEX_H: int = 272

const CLASSIC_COLORS: Dictionary = {
	"red": Color(0.90, 0.15, 0.14, 1.0),
	"blue": Color(0.08, 0.39, 0.90, 1.0),
	"green": Color(0.11, 0.65, 0.28, 1.0),
	"yellow": Color(0.95, 0.75, 0.06, 1.0),
	"pink": Color(0.92, 0.16, 0.56, 1.0),
	"teal": Color(0.05, 0.72, 0.70, 1.0),
	"purple": Color(0.50, 0.16, 0.86, 1.0),
	"orange": Color(0.96, 0.44, 0.06, 1.0),
	"wild": Color(0.10, 0.11, 0.16, 1.0)
}

const MINIMAL_COLORS: Dictionary = {
	"red": Color(1.0, 0.28, 0.34, 1.0),
	"blue": Color(0.20, 0.56, 1.0, 1.0),
	"green": Color(0.18, 0.84, 0.45, 1.0),
	"yellow": Color(1.0, 0.72, 0.08, 1.0),
	"pink": Color(1.0, 0.32, 0.72, 1.0),
	"teal": Color(0.12, 0.90, 0.86, 1.0),
	"purple": Color(0.72, 0.36, 1.0, 1.0),
	"orange": Color(1.0, 0.54, 0.14, 1.0),
	"wild": Color(0.76, 0.44, 0.98, 1.0)
}

const DARK_SIDE_COLORS: Array[String] = ["pink", "teal", "purple", "orange"]

# 5x7 crisp bitmap font for digits & symbols used in corner indices and labels
const FONT_5X7: Dictionary = {
	"0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
	"1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
	"2": ["01110", "10001", "00001", "00110", "01000", "10000", "11111"],
	"3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
	"4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
	"5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
	"6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
	"7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
	"8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
	"9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
	"+": ["00000", "00100", "00100", "11111", "00100", "00100", "00000"],
	"-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
	"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
	"B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
	"C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
	"D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
	"E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
	"F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
	"G": ["01111", "10000", "10000", "10111", "10001", "10001", "01110"],
	"H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
	"I": ["01110", "00100", "00100", "00100", "00100", "00100", "01110"],
	"K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
	"L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
	"M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
	"N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
	"O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
	"P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
	"R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
	"S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
	"T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
	"U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
	"V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
	"W": ["10001", "10001", "10001", "10101", "10101", "11011", "10001"],
	"X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
	"Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
	"Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
	"!": ["00100", "00100", "00100", "00100", "00100", "00000", "00100"],
	"*": ["00100", "10101", "01110", "11111", "01110", "10101", "00100"],
	"?": ["01110", "10001", "00001", "00110", "00100", "00000", "00100"]
}

static var _front_tex_cache: Dictionary = {}
static var _back_tex_cache: Dictionary = {}
static var _mat_cache: Dictionary = {}

static func normalize_skin(skin_id: String) -> String:
	var s = skin_id.to_lower().strip_edges()
	if s == "minimal_dark" or s == "minimal":
		return "minimal_dark"
	return "classic_arcade"

static func clear_cache() -> void:
	_front_tex_cache.clear()
	_back_tex_cache.clear()
	_mat_cache.clear()

static func get_card_front_texture(card: Dictionary, skin_id: String = "classic_arcade", colorblind: bool = true) -> ImageTexture:
	var skin = normalize_skin(skin_id)
	var col_name = str(card.get("color", "wild")).to_lower()
	if not CLASSIC_COLORS.has(col_name):
		col_name = "wild"
	var val_name = str(card.get("value", card.get("name", "?"))).to_lower()
	if val_name.is_empty():
		val_name = "?"
	var cache_key = "%s|%s|%s|%s" % [skin, col_name, val_name, "cb1" if colorblind else "cb0"]
	if _front_tex_cache.has(cache_key):
		return _front_tex_cache[cache_key]

	var img = _render_front_image(col_name, val_name, skin, colorblind)
	var tex = ImageTexture.create_from_image(img)
	_front_tex_cache[cache_key] = tex
	return tex

static func get_card_back_texture(skin_id: String = "classic_arcade") -> ImageTexture:
	var skin = normalize_skin(skin_id)
	if _back_tex_cache.has(skin):
		return _back_tex_cache[skin]

	var img = _render_back_image(skin)
	var tex = ImageTexture.create_from_image(img)
	_back_tex_cache[skin] = tex
	return tex

static func apply_card_materials_to_mesh(card_root: Node, card_data: Dictionary, skin_id: String = "classic_arcade", colorblind: bool = true, face_up: bool = true, back_card_data: Dictionary = {}) -> void:
	var mesh_node = _find_first_mesh_instance(card_root)
	if mesh_node == null or mesh_node.mesh == null:
		return

	var skin = normalize_skin(skin_id)
	var is_masked = bool(card_data.get("masked", false)) or not face_up

	var back_tex: Texture2D
	var back_key: String
	var back_special: bool = false
	if not back_card_data.is_empty():
		var b_col = str(back_card_data.get("color", "wild")).to_lower()
		var b_val = str(back_card_data.get("value", back_card_data.get("name", "?"))).to_lower()
		back_tex = get_card_front_texture(back_card_data, skin, colorblind)
		back_key = "OPP|%s|%s|%s" % [b_col, b_val, "cb1" if colorblind else "cb0"]
		back_special = (b_col == "wild" or b_val in ["skip", "skip_everyone", "reverse", "draw_two", "draw_five", "wild", "wild_draw_four", "flip"])
	else:
		back_tex = get_card_back_texture(skin)
		back_key = "BACK"

	var front_mat: StandardMaterial3D
	if is_masked:
		var masked_key = "MASKED_" + back_key if not back_card_data.is_empty() else "MASKED"
		front_mat = _get_or_create_material(skin, masked_key, false, back_tex, false, Color(0.68, 0.72, 0.80, 1.0) if not back_card_data.is_empty() else Color(1, 1, 1, 1))
	else:
		var col_name = str(card_data.get("color", "wild")).to_lower()
		var val_name = str(card_data.get("value", card_data.get("name", "?"))).to_lower()
		var is_special = (col_name == "wild" or val_name in ["skip", "skip_everyone", "reverse", "draw_two", "draw_five", "wild", "wild_draw_four", "flip"])
		var front_tex = get_card_front_texture(card_data, skin, colorblind)
		front_mat = _get_or_create_material(skin, "%s|%s|%s" % [col_name, val_name, "cb1" if colorblind else "cb0"], is_special, front_tex, true)

	var back_tint = Color(0.68, 0.72, 0.80, 1.0) if not back_card_data.is_empty() else Color(1, 1, 1, 1)
	var back_mat = _get_or_create_material(skin, back_key, false if not back_card_data.is_empty() else back_special, back_tex, false, back_tint)
	var edge_mat = _get_or_create_edge_material(skin)

	var surf_count = mesh_node.mesh.get_surface_count()
	if surf_count >= 1:
		mesh_node.set_surface_override_material(0, front_mat)
	if surf_count >= 2:
		mesh_node.set_surface_override_material(1, back_mat)
	if surf_count >= 3:
		mesh_node.set_surface_override_material(2, edge_mat)

static func set_card_mesh_playable_state(card_root: Node, is_playable: bool) -> void:
	var mesh_node = _find_first_mesh_instance(card_root)
	if mesh_node == null or mesh_node.mesh == null:
		return
	var surf_count = mesh_node.mesh.get_surface_count()
	if surf_count >= 1:
		var raw_f = mesh_node.get_surface_override_material(0)
		if raw_f is StandardMaterial3D:
			var f_mat: StandardMaterial3D = raw_f.duplicate()
			if is_playable:
				f_mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
				f_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			else:
				f_mat.albedo_color = Color(0.42, 0.45, 0.52, 0.90)
				f_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				f_mat.roughness = 0.85
				f_mat.rim_enabled = false
			mesh_node.set_surface_override_material(0, f_mat)
	if surf_count >= 3:
		var raw_e = mesh_node.get_surface_override_material(2)
		if raw_e is StandardMaterial3D:
			var e_mat: StandardMaterial3D = raw_e.duplicate()
			if is_playable:
				e_mat.albedo_color = Color(e_mat.albedo_color.r, e_mat.albedo_color.g, e_mat.albedo_color.b, 1.0)
				e_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			else:
				e_mat.albedo_color = Color(0.42, 0.45, 0.52, 0.90)
				e_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mesh_node.set_surface_override_material(2, e_mat)

static func _get_or_create_material(skin: String, key: String, is_special: bool, tex: Texture2D, is_front: bool, tint: Color = Color(1.0, 1.0, 1.0, 1.0)) -> StandardMaterial3D:
	var cache_key = "%s|%s|%s|%s" % [skin, key, "F" if is_front else "B", str(tint)]
	if _mat_cache.has(cache_key):
		return _mat_cache[cache_key]
	var mat = StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.albedo_color = tint
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mat.roughness = 0.78 if tint != Color(1.0, 1.0, 1.0, 1.0) else (0.38 if is_special else 0.52)
	mat.metallic = 0.10 if (is_special and tint == Color(1.0, 1.0, 1.0, 1.0)) else 0.0
	if is_special and tint == Color(1.0, 1.0, 1.0, 1.0):
		mat.rim_enabled = true
		mat.rim = 0.25
		mat.rim_tint = 0.45
	_mat_cache[cache_key] = mat
	return mat

static func _get_or_create_edge_material(skin: String) -> StandardMaterial3D:
	var cache_key = "%s|EDGE" % skin
	if _mat_cache.has(cache_key):
		return _mat_cache[cache_key]
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.14, 0.20) if skin == "minimal_dark" else Color(0.95, 0.94, 0.91)
	mat.roughness = 0.5
	_mat_cache[cache_key] = mat
	return mat

static func _render_front_image(col_name: String, val_name: String, skin: String, colorblind: bool) -> Image:
	var img = Image.create(TEX_W, TEX_H, false, Image.FORMAT_RGBA8)
	if skin == "minimal_dark":
		_draw_minimal_dark_front(img, col_name, val_name, colorblind)
	else:
		_draw_classic_arcade_front(img, col_name, val_name, colorblind)
	return img

static func _draw_classic_arcade_front(img: Image, col_name: String, val_name: String, colorblind: bool) -> void:
	var is_dark_side = col_name in DARK_SIDE_COLORS
	var base_col: Color = CLASSIC_COLORS.get(col_name, CLASSIC_COLORS["wild"])
	var dark_col: Color = base_col.darkened(0.32)
	var white = Color(0.97, 0.97, 0.96, 1.0)
	var shadow = Color(0.05, 0.06, 0.09, 0.85)
	var cx = TEX_W * 0.5
	var cy = TEX_H * 0.5

	if is_dark_side:
		# Flip! Dark Side: glowing neon border around deep pitch-black obsidian body
		var neon = base_col.lightened(0.18)
		var symbol_neon = base_col.lightened(0.38)
		var obsidian = Color(0.05, 0.06, 0.10, 1.0)
		var oval_fill = Color(0.08, 0.10, 0.16, 1.0)
		var neon_rim = base_col.lightened(0.28)
		img.fill(neon)
		_fill_rounded_rect(img, Rect2i(10, 10, TEX_W - 20, TEX_H - 20), 14, obsidian)
		_fill_rounded_rect(img, Rect2i(12, TEX_H / 2, TEX_W - 24, TEX_H / 2 - 12), 12, Color(base_col.r * 0.16, base_col.g * 0.16, base_col.b * 0.16, 0.35))
		_draw_tilted_oval(img, cx, cy, 58.0, 86.0, -0.34, oval_fill, neon_rim, 6.5)
		_draw_center_symbol(img, val_name, cx, cy, symbol_neon, shadow, false)
		var corner_text = _get_corner_label(val_name)
		_draw_text(img, corner_text, 20, 20, 3, symbol_neon, shadow)
		_draw_text_rotated_180(img, corner_text, TEX_W - 20, TEX_H - 20, 3, symbol_neon, shadow)
		if colorblind:
			_draw_cb_shape(img, col_name, TEX_W - 30, 30, 9.0, symbol_neon)
			_draw_cb_shape(img, col_name, 30, TEX_H - 30, 9.0, symbol_neon)
		return

	# Light Side: Crisp white frame around vibrant colored card face
	var frame_col = Color(0.97, 0.97, 0.96, 1.0)
	var oval_rim = Color(0.97, 0.97, 0.96, 1.0)

	img.fill(frame_col)
	_fill_rounded_rect(img, Rect2i(10, 10, TEX_W - 20, TEX_H - 20), 14, base_col)
	_fill_rounded_rect(img, Rect2i(12, TEX_H / 2, TEX_W - 24, TEX_H / 2 - 12), 12, Color(dark_col.r, dark_col.g, dark_col.b, 0.45))

	# 2. Tilted central oval
	if col_name == "wild":
		_draw_wild_tilted_oval(img, cx, cy, 58.0, 86.0, -0.34, white, 5.0)
	else:
		_draw_tilted_oval(img, cx, cy, 58.0, 86.0, -0.34, base_col.darkened(0.12), oval_rim, 5.5)

	# 3. Center large symbol / number
	_draw_center_symbol(img, val_name, cx, cy, white, shadow, false)

	# 4. Corner indices (top-left & rotated bottom-right)
	var corner_text = _get_corner_label(val_name)
	_draw_text(img, corner_text, 20, 20, 3, white, shadow)
	_draw_text_rotated_180(img, corner_text, TEX_W - 20, TEX_H - 20, 3, white, shadow)

	# 5. Colorblind geometric symbol in upper-right & lower-left corners
	if colorblind:
		_draw_cb_shape(img, col_name, TEX_W - 30, 30, 9.0, white)
		_draw_cb_shape(img, col_name, 30, TEX_H - 30, 9.0, white)

static func _draw_minimal_dark_front(img: Image, col_name: String, val_name: String, colorblind: bool) -> void:
	var accent: Color = MINIMAL_COLORS.get(col_name, MINIMAL_COLORS["wild"])
	var bg = Color(0.065, 0.075, 0.115, 1.0)
	var inner_bg = Color(0.095, 0.115, 0.17, 1.0)
	var bright = Color(0.95, 0.97, 1.0, 1.0)
	var shadow = Color(0.02, 0.02, 0.04, 0.9)

	img.fill(bg)
	_fill_rounded_rect(img, Rect2i(8, 8, TEX_W - 16, TEX_H - 16), 16, accent)
	_fill_rounded_rect(img, Rect2i(13, 13, TEX_W - 26, TEX_H - 26), 12, inner_bg)

	var cx = TEX_W * 0.5
	var cy = TEX_H * 0.5
	if col_name == "wild":
		_draw_wild_ring(img, cx, cy, 50.0, 56.0)
	else:
		_draw_ring(img, cx, cy, 50.0, 55.0, accent)

	_draw_center_symbol(img, val_name, cx, cy, bright if col_name == "wild" else accent.lightened(0.25), shadow, true)

	var corner_text = _get_corner_label(val_name)
	_draw_text(img, corner_text, 22, 22, 3, accent.lightened(0.2), shadow)
	_draw_text_rotated_180(img, corner_text, TEX_W - 22, TEX_H - 22, 3, accent.lightened(0.2), shadow)

	if colorblind:
		_draw_cb_shape(img, col_name, TEX_W - 30, 30, 8.5, accent.lightened(0.2))
		_draw_cb_shape(img, col_name, 30, TEX_H - 30, 8.5, accent.lightened(0.2))

static func _render_back_image(skin: String) -> Image:
	var img = Image.create(TEX_W, TEX_H, false, Image.FORMAT_RGBA8)
	var cx = TEX_W * 0.5
	var cy = TEX_H * 0.5
	if skin == "minimal_dark":
		var bg = Color(0.055, 0.065, 0.105, 1.0)
		var cyan = Color(0.0, 0.85, 1.0, 1.0)
		var gold = Color(0.98, 0.78, 0.24, 1.0)
		img.fill(bg)
		_fill_rounded_rect(img, Rect2i(10, 10, TEX_W - 20, TEX_H - 20), 16, Color(0.14, 0.18, 0.28, 1.0))
		_fill_rounded_rect(img, Rect2i(14, 14, TEX_W - 28, TEX_H - 28), 13, bg)
		_draw_ring(img, cx, cy, 46.0, 50.0, cyan)
		_draw_ring(img, cx, cy, 33.0, 36.0, gold)
		_draw_text(img, "DB", int(cx) - 21, int(cy) - 14, 4, gold, Color(0, 0, 0, 0.8))
	else:
		var white = Color(0.97, 0.97, 0.96, 1.0)
		var navy = Color(0.07, 0.08, 0.14, 1.0)
		var crimson = Color(0.24, 0.34, 0.68, 1.0)
		var gold = Color(0.98, 0.80, 0.12, 1.0)
		img.fill(white)
		_fill_rounded_rect(img, Rect2i(10, 10, TEX_W - 20, TEX_H - 20), 14, navy)
		_draw_tilted_oval(img, cx, cy, 56.0, 82.0, -0.34, crimson, gold, 4.0)
		_draw_text(img, "DB", int(cx) - 27, int(cy) - 17, 5, gold, Color(0.05, 0.05, 0.08, 0.9))
	return img

static func _get_corner_label(val_name: String) -> String:
	if val_name.begins_with("custom_draw_"):
		return "+" + val_name.substr(12)
	match val_name:
		"skip": return "S"
		"skip_everyone": return "SS"
		"reverse": return "R"
		"draw_two": return "+2"
		"draw_four": return "+4"
		"draw_five": return "+5"
		"wild": return "W"
		"wild_draw_four": return "+4"
		"wild_reverse_draw_four": return "R4"
		"wild_draw_six": return "+6"
		"wild_draw_ten": return "+10"
		"wild_color_roulette", "wild_draw_color": return "+?"
		"discard_all": return "ALL"
		"flip": return "FL"
		"custom_shield": return "0"
		"custom_swap": return "SW"
		"0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
			return val_name
		_:
			return "*"

static func _draw_center_symbol(img: Image, val_name: String, cx: float, cy: float, fg: Color, shadow: Color, minimal: bool) -> void:
	match val_name:
		"skip":
			# Shadow then foreground circle + slash
			_draw_ring(img, cx + 3.0, cy + 4.0, 22.0, 32.0, shadow)
			_draw_thick_segment(img, Vector2(cx - 17.0, cy + 17.0) + Vector2(3, 4), Vector2(cx + 17.0, cy - 17.0) + Vector2(3, 4), 5.0, shadow)
			_draw_ring(img, cx, cy, 22.0, 32.0, fg)
			_draw_thick_segment(img, Vector2(cx - 17.0, cy + 17.0), Vector2(cx + 17.0, cy - 17.0), 5.0, fg)
		"reverse":
			# Two opposing diagonal arrows
			_draw_arrow(img, Vector2(cx - 24, cy - 10) + Vector2(3, 4), Vector2(cx + 22, cy - 10) + Vector2(3, 4), shadow)
			_draw_arrow(img, Vector2(cx + 24, cy + 12) + Vector2(3, 4), Vector2(cx - 22, cy + 12) + Vector2(3, 4), shadow)
			_draw_arrow(img, Vector2(cx - 24, cy - 10), Vector2(cx + 22, cy - 10), fg)
			_draw_arrow(img, Vector2(cx + 24, cy + 12), Vector2(cx - 22, cy + 12), fg)
		"draw_two":
			# Two overlapping mini cards inside center
			_fill_rounded_rect(img, Rect2i(int(cx) - 24, int(cy) - 10, 26, 36), 4, shadow)
			_fill_rounded_rect(img, Rect2i(int(cx) - 27, int(cy) - 13, 26, 36), 4, fg)
			_fill_rounded_rect(img, Rect2i(int(cx) - 23, int(cy) - 9, 18, 28), 2, CLASSIC_COLORS["blue"] if minimal else Color(0.2, 0.25, 0.35))
			_fill_rounded_rect(img, Rect2i(int(cx) + 1, int(cy) - 24, 26, 36), 4, shadow)
			_fill_rounded_rect(img, Rect2i(int(cx) - 2, int(cy) - 27, 26, 36), 4, fg)
			_fill_rounded_rect(img, Rect2i(int(cx) + 2, int(cy) - 23, 18, 28), 2, fg.darkened(0.2))
		"wild":
			_draw_text(img, "W", int(cx) - 20, int(cy) - 28, 8, fg, shadow)
		"wild_draw_four":
			var mini_cols = [CLASSIC_COLORS["red"], CLASSIC_COLORS["blue"], CLASSIC_COLORS["green"], CLASSIC_COLORS["yellow"]]
			var offsets = [Vector2i(-28, -8), Vector2i(-14, -22), Vector2i(0, -10), Vector2i(14, -24)]
			for i in range(4):
				var ox = int(cx) + offsets[i].x
				var oy = int(cy) + offsets[i].y
				_fill_rounded_rect(img, Rect2i(ox - 2, oy - 2, 22, 32), 4, fg)
				_fill_rounded_rect(img, Rect2i(ox + 1, oy + 1, 16, 26), 2, mini_cols[i])
		"skip_everyone":
			_draw_ring(img, cx + 3.0, cy + 4.0, 26.0, 35.0, shadow)
			_draw_ring(img, cx + 3.0, cy + 4.0, 12.0, 18.0, shadow)
			_draw_ring(img, cx, cy, 26.0, 35.0, fg)
			_draw_ring(img, cx, cy, 12.0, 18.0, fg)
			_draw_thick_segment(img, Vector2(cx - 21.0, cy + 21.0), Vector2(cx + 21.0, cy - 21.0), 4.8, fg)
		"discard_all":
			for off_i in range(3):
				var ox = int(cx) - 24 + off_i * 10
				var oy = int(cy) - 26 + off_i * 7
				_fill_rounded_rect(img, Rect2i(ox + 2, oy + 3, 28, 38), 4, shadow)
				_fill_rounded_rect(img, Rect2i(ox, oy, 28, 38), 4, fg)
				_fill_rounded_rect(img, Rect2i(ox + 4, oy + 4, 20, 30), 2, CLASSIC_COLORS["blue"] if minimal else Color(0.18, 0.22, 0.30))
		"flip":
			_draw_ring(img, cx + 3.0, cy + 4.0, 28.0, 36.0, shadow)
			_draw_ring(img, cx, cy, 28.0, 36.0, fg)
			_draw_text(img, "FL", int(cx) - 23, int(cy) - 14, 4, fg, shadow)
		"draw_four":
			_draw_text(img, "+4", int(cx) - 34, int(cy) - 21, 6, fg, shadow)
		"draw_five":
			_draw_text(img, "+5", int(cx) - 34, int(cy) - 21, 6, fg, shadow)
		"wild_draw_six":
			_draw_text(img, "+6", int(cx) - 34, int(cy) - 21, 6, fg, shadow)
		"wild_draw_ten":
			_draw_text(img, "+10", int(cx) - 42, int(cy) - 18, 5, Color(1.0, 0.90, 0.25), shadow)
		"wild_reverse_draw_four":
			_draw_arrow(img, Vector2(cx - 22, cy - 22), Vector2(cx + 22, cy - 22), fg)
			_draw_text(img, "+4", int(cx) - 26, int(cy) - 4, 5, fg, shadow)
		"wild_color_roulette", "wild_draw_color":
			_draw_wild_ring(img, cx, cy, 22.0, 34.0)
			_draw_text(img, "?", int(cx) - 11, int(cy) - 14, 4, fg, shadow)
		_:
			if val_name.begins_with("custom_draw_"):
				var amt = "+" + val_name.substr(12)
				var sc = 5 if amt.length() >= 3 else 6
				_draw_text(img, amt, int(cx) - (sc * amt.length() * 3), int(cy) - (sc * 3), sc, fg, shadow)
			elif val_name == "custom_shield":
				_draw_ring(img, cx, cy, 18.0, 28.0, fg)
				_draw_text(img, "0", int(cx) - 11, int(cy) - 14, 4, fg, shadow)
			elif val_name == "custom_swap":
				_draw_arrow(img, Vector2(cx - 22, cy - 10), Vector2(cx + 20, cy - 10), fg)
				_draw_arrow(img, Vector2(cx + 22, cy + 12), Vector2(cx - 20, cy + 12), fg)
			elif val_name.length() == 1 and val_name in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]:
				_draw_vector_digit(img, val_name, cx + 3.0, cy + 4.0, shadow)
				_draw_vector_digit(img, val_name, cx, cy, fg)
				if val_name == "6" or val_name == "9":
					_draw_thick_segment(img, Vector2(cx - 18.0, cy + 42.0) + Vector2(2, 3), Vector2(cx + 18.0, cy + 42.0) + Vector2(2, 3), 3.2, shadow)
					_draw_thick_segment(img, Vector2(cx - 18.0, cy + 42.0), Vector2(cx + 18.0, cy + 42.0), 3.2, fg)
			else:
				_draw_text(img, "*", int(cx) - 22, int(cy) - 31, 9, fg, shadow)

static func _draw_vector_digit(img: Image, digit: String, cx: float, cy: float, col: Color) -> void:
	var r = 6.2
	match digit:
		"0":
			_draw_tilted_oval(img, cx, cy, 22.0, 32.0, 0.0, Color(0, 0, 0, 0), col, 11.0)
		"1":
			_draw_thick_segment(img, Vector2(cx - 12.0, cy - 20.0), Vector2(cx + 2.0, cy - 32.0), r, col)
			_draw_thick_segment(img, Vector2(cx + 2.0, cy - 32.0), Vector2(cx + 2.0, cy + 32.0), r, col)
			_draw_thick_segment(img, Vector2(cx - 14.0, cy + 32.0), Vector2(cx + 16.0, cy + 32.0), r, col)
		"2":
			_draw_arc_band(img, cx, cy - 14.0, 12.0, 22.0, PI * 0.92, TAU + 0.25, col)
			_draw_thick_segment(img, Vector2(cx + 14.0, cy - 8.0), Vector2(cx - 18.0, cy + 31.0), r, col)
			_draw_thick_segment(img, Vector2(cx - 18.0, cy + 31.0), Vector2(cx + 18.0, cy + 31.0), r, col)
		"3":
			_draw_arc_band(img, cx - 2.0, cy - 15.0, 10.0, 20.0, PI * 0.85, TAU + PI * 0.45, col)
			_draw_arc_band(img, cx - 2.0, cy + 15.0, 10.0, 20.0, -PI * 0.45, PI * 1.15, col)
		"4":
			_draw_thick_segment(img, Vector2(cx + 8.0, cy - 32.0), Vector2(cx - 18.0, cy + 10.0), r, col)
			_draw_thick_segment(img, Vector2(cx - 18.0, cy + 10.0), Vector2(cx + 19.0, cy + 10.0), r, col)
			_draw_thick_segment(img, Vector2(cx + 9.0, cy - 32.0), Vector2(cx + 9.0, cy + 32.0), r, col)
		"5":
			_draw_thick_segment(img, Vector2(cx + 15.0, cy - 31.0), Vector2(cx - 14.0, cy - 31.0), r, col)
			_draw_thick_segment(img, Vector2(cx - 14.0, cy - 31.0), Vector2(cx - 15.0, cy - 4.0), r, col)
			_draw_arc_band(img, cx - 1.0, cy + 13.0, 11.0, 21.0, -PI * 0.72, PI * 0.88, col)
		"6":
			_draw_thick_segment(img, Vector2(cx + 10.0, cy - 32.0), Vector2(cx - 14.0, cy + 4.0), r, col)
			_draw_ring(img, cx, cy + 12.0, 10.0, 21.0, col)
		"7":
			_draw_thick_segment(img, Vector2(cx - 18.0, cy - 31.0), Vector2(cx + 18.0, cy - 31.0), r, col)
			_draw_thick_segment(img, Vector2(cx + 18.0, cy - 31.0), Vector2(cx - 8.0, cy + 32.0), r, col)
		"8":
			_draw_ring(img, cx, cy - 15.0, 8.5, 19.0, col)
			_draw_ring(img, cx, cy + 14.0, 9.5, 20.5, col)
		"9":
			_draw_ring(img, cx, cy - 13.0, 10.0, 21.0, col)
			_draw_thick_segment(img, Vector2(cx + 14.0, cy - 5.0), Vector2(cx - 10.0, cy + 31.0), r, col)

static func _draw_arc_band(img: Image, cx: float, cy: float, r_in: float, r_out: float, a_start: float, a_end: float, col: Color) -> void:
	var bound = int(r_out + 2.0)
	var x0 = maxi(0, int(cx) - bound)
	var x1 = mini(TEX_W - 1, int(cx) + bound)
	var y0 = maxi(0, int(cy) - bound)
	var y1 = mini(TEX_H - 1, int(cy) + bound)
	var r_in_sq = r_in * r_in
	var r_out_sq = r_out * r_out
	for py in range(y0, y1 + 1):
		var dy = float(py) - cy
		for px in range(x0, x1 + 1):
			var dx = float(px) - cx
			var d_sq = dx * dx + dy * dy
			if d_sq >= r_in_sq and d_sq <= r_out_sq:
				var ang = atan2(dy, dx)
				var matched = (ang >= a_start and ang <= a_end) or (ang + TAU >= a_start and ang + TAU <= a_end) or (ang - TAU >= a_start and ang - TAU <= a_end)
				if matched:
					if col.a < 0.99:
						img.set_pixel(px, py, img.get_pixel(px, py).lerp(col, col.a))
					else:
						img.set_pixel(px, py, col)

static func _draw_arrow(img: Image, p0: Vector2, p1: Vector2, col: Color) -> void:
	_draw_thick_segment(img, p0, p1, 4.5, col)
	var dir = (p1 - p0).normalized()
	var perp = Vector2(-dir.y, dir.x)
	_draw_thick_segment(img, p1, p1 - dir * 13.0 + perp * 10.0, 4.0, col)
	_draw_thick_segment(img, p1, p1 - dir * 13.0 - perp * 10.0, 4.0, col)

static func _draw_text(img: Image, txt: String, x0: int, y0: int, px_scale: int, fg: Color, shadow: Color) -> void:
	var cursor_x = x0
	for i in range(txt.length()):
		var ch = txt.substr(i, 1).to_upper()
		var rows = FONT_5X7.get(ch, FONT_5X7["?"])
		for ry in range(7):
			var row_str: String = rows[ry]
			for rx in range(5):
				if row_str.substr(rx, 1) == "1":
					var px = cursor_x + rx * px_scale
					var py = y0 + ry * px_scale
					_blend_rect(img, px + maxi(1, px_scale / 3), py + maxi(1, px_scale / 3), px_scale, px_scale, shadow)
					_blend_rect(img, px, py, px_scale, px_scale, fg)
		cursor_x += 6 * px_scale

static func _draw_text_rotated_180(img: Image, txt: String, x_end: int, y_end: int, px_scale: int, fg: Color, shadow: Color) -> void:
	var cursor_x = x_end
	for i in range(txt.length()):
		var ch = txt.substr(i, 1).to_upper()
		var rows = FONT_5X7.get(ch, FONT_5X7["?"])
		for ry in range(7):
			var row_str: String = rows[ry]
			for rx in range(5):
				if row_str.substr(rx, 1) == "1":
					var px = cursor_x - (rx + 1) * px_scale
					var py = y_end - (ry + 1) * px_scale
					_blend_rect(img, px - maxi(1, px_scale / 3), py - maxi(1, px_scale / 3), px_scale, px_scale, shadow)
					_blend_rect(img, px, py, px_scale, px_scale, fg)
		cursor_x -= 6 * px_scale

static func _blend_rect(img: Image, x0: int, y0: int, w: int, h: int, col: Color) -> void:
	var x_min = maxi(0, x0)
	var y_min = maxi(0, y0)
	var x_max = mini(TEX_W, x0 + w)
	var y_max = mini(TEX_H, y0 + h)
	if x_min >= x_max or y_min >= y_max:
		return
	if col.a >= 0.99:
		img.fill_rect(Rect2i(x_min, y_min, x_max - x_min, y_max - y_min), col)
		return
	for py in range(y_min, y_max):
		for px in range(x_min, x_max):
			var dst = img.get_pixel(px, py)
			img.set_pixel(px, py, dst.lerp(col, col.a))

static func _fill_rounded_rect(img: Image, rect: Rect2i, radius: int, col: Color) -> void:
	var x0 = maxi(0, rect.position.x)
	var y0 = maxi(0, rect.position.y)
	var x1 = mini(TEX_W - 1, rect.position.x + rect.size.x - 1)
	var y1 = mini(TEX_H - 1, rect.position.y + rect.size.y - 1)
	if x1 < x0 or y1 < y0:
		return
	var r = mini(radius, mini((x1 - x0) / 2, (y1 - y0) / 2))
	var r_sq = float(r * r)
	var use_blend = col.a < 0.99

	# Fast center bands
	if not use_blend and r > 0:
		img.fill_rect(Rect2i(x0 + r, y0, (x1 - x0 + 1) - 2 * r, y1 - y0 + 1), col)
		img.fill_rect(Rect2i(x0, y0 + r, x1 - x0 + 1, (y1 - y0 + 1) - 2 * r), col)

	for py in range(y0, y1 + 1):
		for px in range(x0, x1 + 1):
			var dx = 0.0
			var dy = 0.0
			var in_corner = false
			if px < x0 + r and py < y0 + r:
				dx = float(x0 + r - px)
				dy = float(y0 + r - py)
				in_corner = true
			elif px > x1 - r and py < y0 + r:
				dx = float(px - (x1 - r))
				dy = float(y0 + r - py)
				in_corner = true
			elif px < x0 + r and py > y1 - r:
				dx = float(x0 + r - px)
				dy = float(py - (y1 - r))
				in_corner = true
			elif px > x1 - r and py > y1 - r:
				dx = float(px - (x1 - r))
				dy = float(py - (y1 - r))
				in_corner = true
			elif not use_blend and r > 0:
				continue

			if not in_corner or (dx * dx + dy * dy <= r_sq):
				if use_blend:
					img.set_pixel(px, py, img.get_pixel(px, py).lerp(col, col.a))
				else:
					img.set_pixel(px, py, col)

static func _draw_tilted_oval(img: Image, cx: float, cy: float, rx: float, ry: float, angle_rad: float, fill_col: Color, border_col: Color, border_w: float) -> void:
	var cos_a = cos(-angle_rad)
	var sin_a = sin(-angle_rad)
	var bound = int(maxf(rx, ry) + border_w + 4.0)
	var x0 = maxi(0, int(cx) - bound)
	var x1 = mini(TEX_W - 1, int(cx) + bound)
	var y0 = maxi(0, int(cy) - bound)
	var y1 = mini(TEX_H - 1, int(cy) + bound)
	var inner_rx = maxf(1.0, rx - border_w)
	var inner_ry = maxf(1.0, ry - border_w)

	for py in range(y0, y1 + 1):
		var dy = float(py) - cy
		for px in range(x0, x1 + 1):
			var dx = float(px) - cx
			var lx = dx * cos_a - dy * sin_a
			var ly = dx * sin_a + dy * cos_a
			var d_outer = (lx * lx) / (rx * rx) + (ly * ly) / (ry * ry)
			if d_outer <= 1.0:
				var d_inner = (lx * lx) / (inner_rx * inner_rx) + (ly * ly) / (inner_ry * inner_ry)
				if d_inner <= 1.0:
					if fill_col.a > 0.01:
						if fill_col.a < 0.99:
							img.set_pixel(px, py, img.get_pixel(px, py).lerp(fill_col, fill_col.a))
						else:
							img.set_pixel(px, py, fill_col)
				else:
					if border_col.a < 0.99:
						img.set_pixel(px, py, img.get_pixel(px, py).lerp(border_col, border_col.a))
					else:
						img.set_pixel(px, py, border_col)

static func _draw_wild_tilted_oval(img: Image, cx: float, cy: float, rx: float, ry: float, angle_rad: float, border_col: Color, border_w: float) -> void:
	var cos_a = cos(-angle_rad)
	var sin_a = sin(-angle_rad)
	var bound = int(maxf(rx, ry) + border_w + 4.0)
	var x0 = maxi(0, int(cx) - bound)
	var x1 = mini(TEX_W - 1, int(cx) + bound)
	var y0 = maxi(0, int(cy) - bound)
	var y1 = mini(TEX_H - 1, int(cy) + bound)
	var inner_rx = maxf(1.0, rx - border_w)
	var inner_ry = maxf(1.0, ry - border_w)

	for py in range(y0, y1 + 1):
		var dy = float(py) - cy
		for px in range(x0, x1 + 1):
			var dx = float(px) - cx
			var lx = dx * cos_a - dy * sin_a
			var ly = dx * sin_a + dy * cos_a
			var d_outer = (lx * lx) / (rx * rx) + (ly * ly) / (ry * ry)
			if d_outer <= 1.0:
				var d_inner = (lx * lx) / (inner_rx * inner_rx) + (ly * ly) / (inner_ry * inner_ry)
				if d_inner <= 1.0:
					if lx < 0.0 and ly < 0.0:
						img.set_pixel(px, py, CLASSIC_COLORS["red"])
					elif lx >= 0.0 and ly < 0.0:
						img.set_pixel(px, py, CLASSIC_COLORS["blue"])
					elif lx < 0.0 and ly >= 0.0:
						img.set_pixel(px, py, CLASSIC_COLORS["yellow"])
					else:
						img.set_pixel(px, py, CLASSIC_COLORS["green"])
				else:
					img.set_pixel(px, py, border_col)

static func _draw_ring(img: Image, cx: float, cy: float, r_in: float, r_out: float, col: Color) -> void:
	var bound = int(r_out + 2.0)
	var x0 = maxi(0, int(cx) - bound)
	var x1 = mini(TEX_W - 1, int(cx) + bound)
	var y0 = maxi(0, int(cy) - bound)
	var y1 = mini(TEX_H - 1, int(cy) + bound)
	var r_in_sq = r_in * r_in
	var r_out_sq = r_out * r_out
	for py in range(y0, y1 + 1):
		var dy = float(py) - cy
		for px in range(x0, x1 + 1):
			var dx = float(px) - cx
			var d_sq = dx * dx + dy * dy
			if d_sq >= r_in_sq and d_sq <= r_out_sq:
				if col.a < 0.99:
					img.set_pixel(px, py, img.get_pixel(px, py).lerp(col, col.a))
				else:
					img.set_pixel(px, py, col)

static func _draw_wild_ring(img: Image, cx: float, cy: float, r_in: float, r_out: float) -> void:
	var bound = int(r_out + 2.0)
	var x0 = maxi(0, int(cx) - bound)
	var x1 = mini(TEX_W - 1, int(cx) + bound)
	var y0 = maxi(0, int(cy) - bound)
	var y1 = mini(TEX_H - 1, int(cy) + bound)
	var r_in_sq = r_in * r_in
	var r_out_sq = r_out * r_out
	for py in range(y0, y1 + 1):
		var dy = float(py) - cy
		for px in range(x0, x1 + 1):
			var dx = float(px) - cx
			var d_sq = dx * dx + dy * dy
			if d_sq >= r_in_sq and d_sq <= r_out_sq:
				var col: Color
				if dx < 0.0 and dy < 0.0:
					col = MINIMAL_COLORS["red"]
				elif dx >= 0.0 and dy < 0.0:
					col = MINIMAL_COLORS["blue"]
				elif dx < 0.0 and dy >= 0.0:
					col = MINIMAL_COLORS["yellow"]
				else:
					col = MINIMAL_COLORS["green"]
				img.set_pixel(px, py, col)

static func _draw_thick_segment(img: Image, p0: Vector2, p1: Vector2, radius: float, col: Color) -> void:
	var x0 = maxi(0, int(minf(p0.x, p1.x) - radius - 2.0))
	var x1 = mini(TEX_W - 1, int(maxf(p0.x, p1.x) + radius + 2.0))
	var y0 = maxi(0, int(minf(p0.y, p1.y) - radius - 2.0))
	var y1 = mini(TEX_H - 1, int(maxf(p0.y, p1.y) + radius + 2.0))
	var seg = p1 - p0
	var seg_len_sq = maxf(0.001, seg.length_squared())
	var r_sq = radius * radius
	for py in range(y0, y1 + 1):
		for px in range(x0, x1 + 1):
			var pt = Vector2(float(px), float(py))
			var t = clampf((pt - p0).dot(seg) / seg_len_sq, 0.0, 1.0)
			var proj = p0 + seg * t
			if pt.distance_squared_to(proj) <= r_sq:
				if col.a < 0.99:
					img.set_pixel(px, py, img.get_pixel(px, py).lerp(col, col.a))
				else:
					img.set_pixel(px, py, col)

static func _draw_cb_shape(img: Image, col_name: String, cx: int, cy: int, r: float, col: Color) -> void:
	var x0 = maxi(0, cx - int(r) - 2)
	var x1 = mini(TEX_W - 1, cx + int(r) + 2)
	var y0 = maxi(0, cy - int(r) - 2)
	var y1 = mini(TEX_H - 1, cy + int(r) + 2)
	match col_name:
		"red": # Triangle
			for py in range(y0, y1 + 1):
				var t = clampf((float(py) - (float(cy) - r)) / (2.0 * r), 0.0, 1.0)
				if float(py) >= float(cy) - r and float(py) <= float(cy) + r * 0.7:
					var half_w = t * r * 0.95
					for px in range(x0, x1 + 1):
						if absf(float(px - cx)) <= half_w:
							img.set_pixel(px, py, col)
		"blue": # Diamond
			for py in range(y0, y1 + 1):
				for px in range(x0, x1 + 1):
					if absf(float(px - cx)) / (r * 0.85) + absf(float(py - cy)) / r <= 1.0:
						img.set_pixel(px, py, col)
		"green": # Circle
			for py in range(y0, y1 + 1):
				for px in range(x0, x1 + 1):
					if Vector2(float(px - cx), float(py - cy)).length_squared() <= r * r:
						img.set_pixel(px, py, col)
		"yellow": # 4-point star / cross-diamond
			for py in range(y0, y1 + 1):
				for px in range(x0, x1 + 1):
					var dx = absf(float(px - cx)) / r
					var dy = absf(float(py - cy)) / r
					if (dx + dy <= 0.85) or (dx < 0.25 and dy <= 1.0) or (dy < 0.25 and dx <= 1.0):
						img.set_pixel(px, py, col)
		_:
			_draw_ring(img, float(cx), float(cy), r * 0.4, r * 0.85, col)

static func _find_first_mesh_instance(root: Node) -> MeshInstance3D:
	if root is MeshInstance3D:
		return root
	for c in root.get_children():
		var found = _find_first_mesh_instance(c)
		if found != null:
			return found
	return null
