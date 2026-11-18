# pack_editor.gd
# In-App Card Pack & Custom Card Creator with Effect Builder, Presets & Live Visual Card Preview
extends Control

const PackEditorModelScript = preload("res://core/packs/pack_editor/pack_editor_model.gd")
const CardPackManagerScript = preload("res://core/packs/card_pack_manager.gd")
const CardTextureGenScript = preload("res://core/visuals/card_texture_generator.gd")
const UIThemeScript = preload("res://core/visuals/deckbox_ui_theme.gd")

var model: RefCounted = null
var pack_manager: RefCounted = null

@onready var status_label: Label = $VBoxContainer/Footer/StatusLabel
@onready var id_input: LineEdit = $VBoxContainer/TabContainer/Metadata/GridContainer/IdEdit
@onready var name_input: LineEdit = $VBoxContainer/TabContainer/Metadata/GridContainer/NameEdit
@onready var author_input: LineEdit = $VBoxContainer/TabContainer/Metadata/GridContainer/AuthorEdit
@onready var version_input: LineEdit = $VBoxContainer/TabContainer/Metadata/GridContainer/VersionEdit
@onready var desc_input: TextEdit = $VBoxContainer/TabContainer/Metadata/GridContainer/DescEdit

@onready var card_list: ItemList = $VBoxContainer/TabContainer/Cards/HSplitContainer/CardList
@onready var card_id_edit: LineEdit = $VBoxContainer/TabContainer/Cards/HSplitContainer/CardDetails/PreviewRow/FieldsCol/CardIdEdit
@onready var card_name_edit: LineEdit = $VBoxContainer/TabContainer/Cards/HSplitContainer/CardDetails/PreviewRow/FieldsCol/CardNameEdit
@onready var card_color_opt: OptionButton = $VBoxContainer/TabContainer/Cards/HSplitContainer/CardDetails/PreviewRow/FieldsCol/ColorCountRow/CardColorOpt
@onready var card_count_spin: SpinBox = $VBoxContainer/TabContainer/Cards/HSplitContainer/CardDetails/PreviewRow/FieldsCol/ColorCountRow/CardCountSpin
@onready var card_effect_opt: OptionButton = $VBoxContainer/TabContainer/Cards/HSplitContainer/CardDetails/PreviewRow/FieldsCol/CardEffectOpt
@onready var card_power_spin: SpinBox = $VBoxContainer/TabContainer/Cards/HSplitContainer/CardDetails/PreviewRow/FieldsCol/PowerRow/CardPowerSpin
@onready var card_target_opt: OptionButton = $VBoxContainer/TabContainer/Cards/HSplitContainer/CardDetails/PreviewRow/FieldsCol/PowerRow/CardTargetOpt
@onready var card_preview_rect: TextureRect = $VBoxContainer/TabContainer/Cards/HSplitContainer/CardDetails/PreviewRow/CardPreviewBox/CardPreviewRect

func _ready() -> void:
	theme = UIThemeScript.create_theme()
	model = PackEditorModelScript.new()
	pack_manager = CardPackManagerScript.new()
	_setup_options()
	_sync_ui_from_model()
	_update_card_preview()

func _setup_options() -> void:
	if card_color_opt != null:
		card_color_opt.clear()
		for c in ["wild", "red", "blue", "green", "yellow", "pink", "teal", "purple", "orange"]:
			card_color_opt.add_item(c)

	if card_effect_opt != null:
		card_effect_opt.clear()
		var effects = [
			["Karten ziehen (+1 bis +20)", "draw_cards"],
			["Alle überspringen (Nochmal dran)", "skip_everyone"],
			["Spieler überspringen (1–4)", "skip_next"],
			["Richtungswechsel", "reverse"],
			["Hände tauschen", "swap_hands"],
			["Ganze Farbe ablegen", "discard_color"],
			["Strafe abwehren (Schild)", "negate_penalty"],
			["Deck umdrehen (FLIP!)", "flip_side"]
		]
		for i in range(effects.size()):
			card_effect_opt.add_item(effects[i][0], i)
			card_effect_opt.set_item_metadata(i, effects[i][1])

	if card_target_opt != null:
		card_target_opt.clear()
		card_target_opt.add_item("Nächster Spieler", 0)
		card_target_opt.set_item_metadata(0, "next")
		card_target_opt.add_item("Alle Gegner", 1)
		card_target_opt.set_item_metadata(1, "all_opponents")
		card_target_opt.add_item("Selbst", 2)
		card_target_opt.set_item_metadata(2, "self")

func _build_current_actions() -> Array:
	var eff = "draw_cards"
	if card_effect_opt != null and card_effect_opt.selected >= 0:
		eff = str(card_effect_opt.get_item_metadata(card_effect_opt.selected))
	var power = int(card_power_spin.value) if card_power_spin != null else 2
	var target = "next"
	if card_target_opt != null and card_target_opt.selected >= 0:
		target = str(card_target_opt.get_item_metadata(card_target_opt.selected))
	var col = "red"
	if card_color_opt != null and card_color_opt.selected >= 0:
		col = card_color_opt.get_item_text(card_color_opt.selected)

	match eff:
		"draw_cards":
			return [{ "type": "draw_cards", "count": clampi(power, 1, 20), "target": target }]
		"skip_next":
			return [{ "type": "skip_next", "count": clampi(power, 1, 4) }]
		"swap_hands":
			return [{ "type": "swap_hands", "target": "left" }]
		"discard_color":
			return [{ "type": "discard_color", "color": col if col != "wild" else "red" }]
		"skip_everyone":
			return [{ "type": "skip_everyone" }]
		"reverse":
			return [{ "type": "reverse" }]
		"negate_penalty":
			return [{ "type": "negate_penalty" }]
		"flip_side":
			return [{ "type": "flip_side" }]
		_:
			return [{ "type": "draw_cards", "count": 2, "target": "next" }]

func _preview_value_for_actions(actions: Array) -> String:
	for a in actions:
		if a is Dictionary:
			var t = str(a.get("type", ""))
			if t == "draw_cards":
				return "custom_draw_%d" % int(a.get("count", 2))
			if t == "negate_penalty":
				return "custom_shield"
			if t == "swap_hands":
				return "custom_swap"
			if t == "skip_everyone":
				return "skip_everyone"
			if t == "flip_side":
				return "flip"
	return "*"

func _update_card_preview() -> void:
	if card_preview_rect == null:
		return
	var col = "wild"
	if card_color_opt != null and card_color_opt.selected >= 0:
		col = card_color_opt.get_item_text(card_color_opt.selected)
	var cid = card_id_edit.text.strip_edges() if card_id_edit != null else ""
	var cname = card_name_edit.text.strip_edges() if card_name_edit != null else ""
	var actions = _build_current_actions()
	var sample = {
		"id": cid if not cid.is_empty() else "preview",
		"name": cname if not cname.is_empty() else "Custom",
		"color": col,
		"value": _preview_value_for_actions(actions),
		"actions": actions
	}
	card_preview_rect.texture = CardTextureGenScript.get_card_front_texture(sample, "classic_arcade", true)

func _on_preview_field_changed(_new_text: String) -> void:
	_update_card_preview()

func _on_preview_opt_changed(_index: int) -> void:
	_update_card_preview()

func _on_preview_val_changed(_val: float) -> void:
	_update_card_preview()

func _sync_ui_from_model() -> void:
	if model == null:
		return
	var data = model.get_pack_data()
	if id_input != null:
		id_input.text = str(data.get("id", ""))
	if name_input != null:
		name_input.text = str(data.get("name", ""))
	if author_input != null:
		author_input.text = str(data.get("author", ""))
	if version_input != null:
		version_input.text = str(data.get("version", ""))
	if desc_input != null:
		desc_input.text = str(data.get("description", ""))
	_refresh_card_list()

func _refresh_card_list() -> void:
	if card_list == null or model == null:
		return
	card_list.clear()
	var cards = model.get_custom_cards()
	for c in cards:
		var actions_desc = str(c.get("actions", [{}])[0].get("type", ""))
		var txt = "%s (%s • %s ×%d)" % [c.get("name", ""), c.get("color", ""), actions_desc, int(c.get("count", 1))]
		card_list.add_item(txt)

func _on_new_button_pressed() -> void:
	model.new_pack("new_pack", "New Card Pack", "Author")
	_sync_ui_from_model()
	_set_status("Neues Karten-Pack erstellt.")

func _on_validate_button_pressed() -> void:
	_sync_model_from_ui()
	var res = model.validate_current_draft()
	if res.get("valid", false):
		_set_status("Pack-Prüfung bestanden! (0 Fehler)")
	else:
		_set_status("Prüfung fehlgeschlagen: " + ", ".join(res.get("errors", [])))

func _on_export_button_pressed() -> void:
	_sync_model_from_ui()
	var pid = model.get_pack_data().get("id", "pack")
	var export_path = "user://packs/%s.cardpack" % pid
	var res = model.export_to_file(pack_manager, export_path)
	if res.get("success", false):
		_set_status("Pack exportiert nach %s" % export_path)
	else:
		_set_status("Export fehlgeschlagen: " + str(res.get("error", "")))

func _on_add_card_pressed() -> void:
	if card_id_edit == null or card_name_edit == null:
		return
	var cid = card_id_edit.text.strip_edges()
	var cname = card_name_edit.text.strip_edges()
	var color = card_color_opt.get_item_text(card_color_opt.selected)
	var count = int(card_count_spin.value)
	var actions = _build_current_actions()

	var card_dict = {
		"id": cid,
		"name": cname,
		"color": color,
		"count": count,
		"actions": actions
	}

	var ok = model.add_custom_card(card_dict)
	if ok:
		_refresh_card_list()
		_update_card_preview()
		_set_status("Custom-Karte '%s' hinzugefügt & fürs nächste Match aktiv!" % cname)
	else:
		_set_status("Fehler bei Karte '%s' (ID darf keine Leerzeichen haben / keine Duplikate)." % cid)

func _on_preset_plus8_pressed() -> void:
	_apply_preset("mega_plus_8", "Mega +8", 0, 0, 8, 2)

func _on_preset_shield_pressed() -> void:
	_apply_preset("penalty_shield", "Schild 0", 0, 6, 1, 2)

func _on_preset_swap_pressed() -> void:
	_apply_preset("chaos_swap", "Chaos-Tausch", 0, 4, 1, 2)

func _apply_preset(cid: String, cname: String, col_idx: int, eff_idx: int, power: int, cnt: int) -> void:
	if card_id_edit: card_id_edit.text = cid
	if card_name_edit: card_name_edit.text = cname
	if card_color_opt: card_color_opt.select(col_idx)
	if card_effect_opt: card_effect_opt.select(eff_idx)
	if card_power_spin: card_power_spin.value = float(power)
	if card_count_spin: card_count_spin.value = float(cnt)
	_update_card_preview()
	_on_add_card_pressed()

func _sync_model_from_ui() -> void:
	if model == null:
		return
	if id_input != null and not id_input.text.is_empty():
		model.set_pack_id(id_input.text)
	var n = name_input.text if name_input != null else ""
	var a = author_input.text if author_input != null else ""
	var v = version_input.text if version_input != null else ""
	var d = desc_input.text if desc_input != null else ""
	model.set_metadata(n, a, v, d)

func _set_status(msg: String) -> void:
	if status_label != null:
		status_label.text = msg
