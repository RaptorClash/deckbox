# core/visuals/deckbox_ui_theme.gd
# Global Glassmorphism & Console-Grade UI Theme Builder for DeckBox
class_name DeckBoxUITheme
extends RefCounted

const COL_GLASS_BG := Color(0.055, 0.075, 0.135, 0.84)
const COL_GLASS_SURFACE := Color(0.085, 0.115, 0.20, 0.90)
const COL_BORDER_CYAN := Color(0.28, 0.72, 1.0, 0.38)
const COL_BORDER_GOLD := Color(0.98, 0.78, 0.24, 0.85)
const COL_BTN_NORMAL := Color(0.11, 0.15, 0.26, 0.92)
const COL_BTN_HOVER := Color(0.17, 0.24, 0.39, 0.96)
const COL_BTN_PRESSED := Color(0.08, 0.11, 0.20, 0.98)
const COL_TEXT_PRIMARY := Color(0.94, 0.96, 1.0, 1.0)
const COL_TEXT_MUTED := Color(0.68, 0.75, 0.88, 1.0)

static func make_glass_panel(
	bg_color: Color = COL_GLASS_BG,
	border_color: Color = COL_BORDER_CYAN,
	corner_radius: int = 16,
	pad: int = 14
) -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = bg_color
	sb.border_color = border_color
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(corner_radius)
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	sb.shadow_size = 12
	sb.shadow_offset = Vector2(0, 4)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	return sb

static func make_pill_button(
	bg_color: Color = COL_BTN_NORMAL,
	border_color: Color = COL_BORDER_CYAN,
	corner_radius: int = 12,
	pad_x: int = 16,
	pad_y: int = 9
) -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = bg_color
	sb.border_color = border_color
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(corner_radius)
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y
	sb.content_margin_bottom = pad_y
	return sb

static func make_accent_button(
	bg_color: Color = Color(0.92, 0.48, 0.14, 0.96),
	border_color: Color = COL_BORDER_GOLD,
	corner_radius: int = 14
) -> StyleBoxFlat:
	var sb = make_pill_button(bg_color, border_color, corner_radius, 20, 12)
	sb.set_border_width_all(2)
	sb.shadow_color = Color(bg_color.r, bg_color.g, bg_color.b, 0.4)
	sb.shadow_size = 10
	return sb

static func make_badge_style(accent: Color = Color(0.28, 0.78, 1.0, 0.65), is_active: bool = false) -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.09, 0.16, 0.88) if not is_active else Color(0.12, 0.17, 0.28, 0.96)
	sb.border_color = COL_BORDER_GOLD if is_active else accent
	sb.set_border_width_all(2 if is_active else 1)
	sb.set_corner_radius_all(14)
	if is_active:
		sb.shadow_color = Color(COL_BORDER_GOLD.r, COL_BORDER_GOLD.g, COL_BORDER_GOLD.b, 0.45)
		sb.shadow_size = 10
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb

static func create_theme() -> Theme:
	var theme = Theme.new()

	# Panels
	theme.set_stylebox("panel", "PanelContainer", make_glass_panel())
	theme.set_stylebox("panel", "TabContainer", make_glass_panel(COL_GLASS_SURFACE, COL_BORDER_CYAN, 14, 12))

	# Buttons
	var btn_norm = make_pill_button(COL_BTN_NORMAL, COL_BORDER_CYAN)
	var btn_hover = make_pill_button(COL_BTN_HOVER, Color(0.45, 0.84, 1.0, 0.85))
	var btn_press = make_pill_button(COL_BTN_PRESSED, COL_BORDER_GOLD)
	var btn_dis = make_pill_button(Color(0.07, 0.09, 0.14, 0.55), Color(0.25, 0.30, 0.40, 0.25))
	var btn_focus = make_pill_button(Color(0, 0, 0, 0), Color(0.4, 0.85, 1.0, 0.5))

	for ctrl_type in ["Button", "OptionButton", "CheckButton", "CheckBox"]:
		theme.set_stylebox("normal", ctrl_type, btn_norm)
		theme.set_stylebox("hover", ctrl_type, btn_hover)
		theme.set_stylebox("pressed", ctrl_type, btn_press)
		theme.set_stylebox("disabled", ctrl_type, btn_dis)
		theme.set_stylebox("focus", ctrl_type, btn_focus)
		theme.set_color("font_color", ctrl_type, COL_TEXT_PRIMARY)
		theme.set_color("font_hover_color", ctrl_type, Color.WHITE)
		theme.set_color("font_pressed_color", ctrl_type, COL_BORDER_GOLD)
		theme.set_color("font_disabled_color", ctrl_type, Color(0.55, 0.60, 0.70, 0.65))

	# Inputs
	var input_norm = make_pill_button(Color(0.04, 0.06, 0.11, 0.90), Color(0.28, 0.48, 0.75, 0.45), 10, 12, 8)
	var input_focus = make_pill_button(Color(0.06, 0.09, 0.16, 0.96), Color(0.35, 0.82, 1.0, 0.85), 10, 12, 8)
	for inp_type in ["LineEdit", "TextEdit"]:
		theme.set_stylebox("normal", inp_type, input_norm)
		theme.set_stylebox("focus", inp_type, input_focus)
		theme.set_stylebox("read_only", inp_type, input_norm)
		theme.set_color("font_color", inp_type, COL_TEXT_PRIMARY)

	# ItemList & PopupMenu
	var list_panel = make_glass_panel(Color(0.045, 0.065, 0.12, 0.95), COL_BORDER_CYAN, 12, 8)
	theme.set_stylebox("panel", "ItemList", list_panel)
	theme.set_stylebox("panel", "PopupMenu", list_panel)
	theme.set_color("font_color", "ItemList", COL_TEXT_PRIMARY)
	theme.set_color("font_color", "PopupMenu", COL_TEXT_PRIMARY)

	# Tabs
	theme.set_stylebox("tab_selected", "TabContainer", make_pill_button(Color(0.15, 0.24, 0.40, 0.95), COL_BORDER_GOLD, 10, 14, 7))
	theme.set_stylebox("tab_unselected", "TabContainer", make_pill_button(Color(0.07, 0.10, 0.18, 0.75), Color(0.25, 0.40, 0.60, 0.3), 10, 14, 7))
	theme.set_stylebox("tab_hovered", "TabContainer", make_pill_button(Color(0.12, 0.18, 0.30, 0.90), COL_BORDER_CYAN, 10, 14, 7))

	# Labels
	theme.set_color("font_color", "Label", COL_TEXT_PRIMARY)

	return theme
