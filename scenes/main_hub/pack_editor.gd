# pack_editor.gd
# In-App 3D Card & Card-Design Studio with Game Assignment, Explanatory Icons & Import/Export Sharing
extends Control

signal design_saved(skin_id: String)

const PackEditorModelScript = preload("res://core/packs/pack_editor/pack_editor_model.gd")
const CardPackManagerScript = preload("res://core/packs/card_pack_manager.gd")
const CardPackSchemaScript = preload("res://core/packs/card_pack_schema.gd")
const CardTextureGenScript = preload("res://core/visuals/card_texture_generator.gd")
const UIThemeScript = preload("res://core/visuals/deckbox_ui_theme.gd")
const CartridgeRegistryScript = preload("res://core/cartridge/cartridge_registry.gd")
const CardMeshScene = preload("res://assets/3d/card_rounded.glb")

const EFFECT_INFO: Array = [
	["draw_cards", "➕🃏 Strafkarten ziehen (+1 bis +20)", "Der gewählte Zielspieler muss X Strafkarten vom Stapel ziehen."],
	["skip_everyone", "⏭🚫 Alle aussetzen (Nochmal dran)", "Überspringt alle Gegner — du bist sofort nochmal am Zug!"],
	["skip_next", "🚫⏭ Spieler überspringen (1–4 Plätze)", "Überspringt die nächsten X Spieler in aktueller Spielrichtung."],
	["reverse", "⇄🔄 Richtung umkehren", "Dreht die Zug-Reihenfolge am Tisch um (im 2-Spieler wie Aussetzen)."],
	["swap_hands", "🤝🃏 Hände tauschen", "Tauscht alle Handkarten mit einem Mitspieler."],
	["discard_color", "🗑🎨 Ganze Farbe abwerfen", "Legt alle Karten dieser Farbe aus deiner Hand auf einmal ab."],
	["negate_penalty", "🛡❌ Strafe abwehren (Schild)", "Blockiert eine laufende +2/+4/+6/+10 Ziehstrafe auf null."],
	["flip_side", "🌓🔄 Seite wechseln (FLIP!)", "Dreht alle Karten & Ablagestapel zwischen Hell und Dunkel um."]
]

var model: RefCounted = null
var pack_manager: RefCounted = null

var _preview_card_node: Node3D = null
var _preview_cam: Camera3D = null
var _show_card_back: bool = false
var _spin_angle: float = 0.0
var _target_flip_angle: float = 0.0
var _cur_flip_angle: float = 0.0

@onready var status_label: Label = $VBoxContainer/Footer/StatusLabel
@onready var share_path_edit: LineEdit = $VBoxContainer/SharePathRow/SharePathEdit
@onready var target_game_opt: OptionButton = $VBoxContainer/Header/TargetGameOpt

@onready var tab_container: TabContainer = $VBoxContainer/MainColumns/TabContainer
@onready var id_input: LineEdit = $VBoxContainer/MainColumns/TabContainer/Metadata/GridContainer/IdEdit
@onready var name_input: LineEdit = $VBoxContainer/MainColumns/TabContainer/Metadata/GridContainer/NameEdit
@onready var author_input: LineEdit = $VBoxContainer/MainColumns/TabContainer/Metadata/GridContainer/AuthorEdit
@onready var version_input: LineEdit = $VBoxContainer/MainColumns/TabContainer/Metadata/GridContainer/VersionEdit
@onready var desc_input: TextEdit = $VBoxContainer/MainColumns/TabContainer/Metadata/GridContainer/DescEdit

@onready var card_list: ItemList = $VBoxContainer/MainColumns/TabContainer/Cards/HSplitContainer/CardListCol/CardList
@onready var card_id_edit: LineEdit = $VBoxContainer/MainColumns/TabContainer/Cards/HSplitContainer/CardDetails/PreviewRow/FieldsCol/CardIdEdit
@onready var card_name_edit: LineEdit = $VBoxContainer/MainColumns/TabContainer/Cards/HSplitContainer/CardDetails/PreviewRow/FieldsCol/CardNameEdit
@onready var card_color_opt: OptionButton = $VBoxContainer/MainColumns/TabContainer/Cards/HSplitContainer/CardDetails/PreviewRow/FieldsCol/ColorCountRow/CardColorOpt
@onready var card_count_spin: SpinBox = $VBoxContainer/MainColumns/TabContainer/Cards/HSplitContainer/CardDetails/PreviewRow/FieldsCol/ColorCountRow/CardCountSpin
@onready var card_effect_opt: OptionButton = $VBoxContainer/MainColumns/TabContainer/Cards/HSplitContainer/CardDetails/PreviewRow/FieldsCol/CardEffectOpt
@onready var effect_explain_lbl: Label = $VBoxContainer/MainColumns/TabContainer/Cards/HSplitContainer/CardDetails/PreviewRow/FieldsCol/EffectExplainLbl
@onready var card_power_spin: SpinBox = $VBoxContainer/MainColumns/TabContainer/Cards/HSplitContainer/CardDetails/PreviewRow/FieldsCol/PowerRow/CardPowerSpin
@onready var card_target_opt: OptionButton = $VBoxContainer/MainColumns/TabContainer/Cards/HSplitContainer/CardDetails/PreviewRow/FieldsCol/PowerRow/CardTargetOpt

@onready var design_tab: MarginContainer = $VBoxContainer/MainColumns/TabContainer/Design
@onready var design_id_edit: LineEdit = $VBoxContainer/MainColumns/TabContainer/Design/DesignScroll/DesignBox/DesignIdRow/DesignIdEdit
@onready var design_name_edit: LineEdit = $VBoxContainer/MainColumns/TabContainer/Design/DesignScroll/DesignBox/DesignIdRow/DesignNameEdit
@onready var design_emblem_edit: LineEdit = $VBoxContainer/MainColumns/TabContainer/Design/DesignScroll/DesignBox/DesignIdRow/DesignEmblemEdit
@onready var frame_color_picker: ColorPickerButton = $VBoxContainer/MainColumns/TabContainer/Design/DesignScroll/DesignBox/ColorsGrid/FrameColorPicker
@onready var bg_color_picker: ColorPickerButton = $VBoxContainer/MainColumns/TabContainer/Design/DesignScroll/DesignBox/ColorsGrid/BgColorPicker
@onready var accent_color_picker: ColorPickerButton = $VBoxContainer/MainColumns/TabContainer/Design/DesignScroll/DesignBox/ColorsGrid/AccentColorPicker
@onready var back_primary_picker: ColorPickerButton = $VBoxContainer/MainColumns/TabContainer/Design/DesignScroll/DesignBox/ColorsGrid/BackPrimaryPicker
@onready var back_secondary_picker: ColorPickerButton = $VBoxContainer/MainColumns/TabContainer/Design/DesignScroll/DesignBox/ColorsGrid/BackSecondaryPicker

@onready var card_preview_3d_viewport: SubViewport = $VBoxContainer/MainColumns/CardPreviewPanel/PreviewBox/CardPreview3DContainer/CardPreview3DViewport
@onready var preview_flip_btn: Button = $VBoxContainer/MainColumns/CardPreviewPanel/PreviewBox/PreviewControlsRow/PreviewFlipBtn
@onready var preview_rotate_check: CheckButton = $VBoxContainer/MainColumns/CardPreviewPanel/PreviewBox/PreviewControlsRow/PreviewRotateCheck

func _ready() -> void:
	theme = UIThemeScript.create_theme()
	model = PackEditorModelScript.new()
	pack_manager = CardPackManagerScript.new()
	_setup_options()
	_setup_3d_card_stage()
	_sync_ui_from_model()
	_update_card_preview()

func _process(delta: float) -> void:
	if _preview_card_node == null or not is_instance_valid(_preview_card_node):
		return
	if preview_rotate_check != null and preview_rotate_check.button_pressed:
		_spin_angle = fmod(_spin_angle + delta * 0.55, TAU)
	else:
		_spin_angle = lerpf(_spin_angle, 0.0, minf(1.0, delta * 8.0))
	_cur_flip_angle = lerpf(_cur_flip_angle, _target_flip_angle, minf(1.0, delta * 10.0))
	var sway_y := sin(_spin_angle) * 0.35 if (preview_rotate_check != null and preview_rotate_check.button_pressed) else 0.0
	_preview_card_node.transform.basis = Basis(Vector3.UP, sway_y + _cur_flip_angle) * Basis(Vector3.RIGHT, deg_to_rad(82.0))

func _setup_3d_card_stage() -> void:
	if card_preview_3d_viewport == null or CardMeshScene == null:
		return
	for ch in card_preview_3d_viewport.get_children():
		ch.queue_free()

	_preview_cam = Camera3D.new()
	_preview_cam.position = Vector3(0.0, 0.0, 0.24)
	_preview_cam.fov = 38.0
	card_preview_3d_viewport.add_child(_preview_cam)
	_preview_cam.look_at(Vector3.ZERO, Vector3.UP)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.25
	key.rotation_degrees = Vector3(-28.0, 26.0, 0.0)
	card_preview_3d_viewport.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.55
	fill.rotation_degrees = Vector3(22.0, -35.0, 0.0)
	card_preview_3d_viewport.add_child(fill)

	var inst = CardMeshScene.instantiate()
	if inst is Node3D:
		_preview_card_node = inst
		_preview_card_node.scale = Vector3.ONE * 1.45
		_preview_card_node.transform.basis = Basis(Vector3.RIGHT, deg_to_rad(82.0))
		card_preview_3d_viewport.add_child(_preview_card_node)

func _setup_options() -> void:
	if target_game_opt != null:
		target_game_opt.clear()
		var games: Array = [
			["uno", "🃏 Alle Ablegen! (uno)"],
			["wizard", "🧙 Zauber-Stiche (wizard)"],
			["doppelkopf", "👑 Doppelkopf (doppelkopf)"]
		]
		var reg := CartridgeRegistryScript.new()
		reg.auto_register_builtin_cartridges()
		for info in reg.get_available_cartridges():
			if info is Dictionary:
				var gid := str(info.get("game_id", "")).to_lower()
				if gid.is_empty() or gid in ["uno", "wizard", "doppelkopf", "base_cartridge"]:
					continue
				games.append([gid, "📦 %s (%s)" % [str(info.get("display_name", gid)), gid]])
		for i in range(games.size()):
			target_game_opt.add_item(games[i][1], i)
			target_game_opt.set_item_metadata(i, games[i][0])

	if card_color_opt != null:
		card_color_opt.clear()
		var color_entries := [
			["wild", "🌈 Farbwahl (Wild — passt immer)"],
			["red", "🔴 Rot (▲)"],
			["blue", "🔵 Blau (◆)"],
			["green", "🟢 Grün (●)"],
			["yellow", "🟡 Gelb (★)"],
			["pink", "🩷 Pink / Flip! (♥)"],
			["teal", "🩵 Türkis / Flip! (◈)"],
			["purple", "🟣 Lila / Flip! (✿)"],
			["orange", "🟠 Orange / Flip! (✦)"]
		]
		for i in range(color_entries.size()):
			card_color_opt.add_item(color_entries[i][1], i)
			card_color_opt.set_item_metadata(i, color_entries[i][0])

	if card_effect_opt != null:
		card_effect_opt.clear()
		for i in range(EFFECT_INFO.size()):
			card_effect_opt.add_item(EFFECT_INFO[i][1], i)
			card_effect_opt.set_item_metadata(i, EFFECT_INFO[i][0])

	if card_target_opt != null:
		card_target_opt.clear()
		card_target_opt.add_item("➡ Nächster Spieler", 0)
		card_target_opt.set_item_metadata(0, "next")
		card_target_opt.add_item("👥 Alle Gegner", 1)
		card_target_opt.set_item_metadata(1, "all_opponents")
		card_target_opt.add_item("🙋 Selbst (Eigener Vorteil)", 2)
		card_target_opt.set_item_metadata(2, "self")

func _selected_color_id() -> String:
	if card_color_opt != null and card_color_opt.selected >= 0:
		return str(card_color_opt.get_item_metadata(card_color_opt.selected))
	return "wild"

func _build_current_actions() -> Array:
	var eff := "draw_cards"
	if card_effect_opt != null and card_effect_opt.selected >= 0:
		eff = str(card_effect_opt.get_item_metadata(card_effect_opt.selected))
	var power := int(card_power_spin.value) if card_power_spin != null else 2
	var target := "next"
	if card_target_opt != null and card_target_opt.selected >= 0:
		target = str(card_target_opt.get_item_metadata(card_target_opt.selected))
	var col := _selected_color_id()

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
			var t := str(a.get("type", ""))
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

func _build_current_design_dict() -> Dictionary:
	var did := design_id_edit.text.strip_edges().to_lower() if design_id_edit != null else "preview_design"
	if did.is_empty():
		did = "preview_design"
	var dname := design_name_edit.text.strip_edges() if design_name_edit != null else did
	if dname.is_empty():
		dname = did
	var emblem := design_emblem_edit.text.strip_edges().to_upper() if design_emblem_edit != null else "DB"
	if emblem.is_empty():
		emblem = "DB"
	return {
		"id": did,
		"name": dname,
		"frame_color": "#" + (frame_color_picker.color.to_html(false) if frame_color_picker != null else "F5F5F0"),
		"bg_color": "#" + (bg_color_picker.color.to_html(false) if bg_color_picker != null else "141824"),
		"accent_color": "#" + (accent_color_picker.color.to_html(false) if accent_color_picker != null else "F2C138"),
		"back_primary": "#" + (back_primary_picker.color.to_html(false) if back_primary_picker != null else "18243E"),
		"back_secondary": "#" + (back_secondary_picker.color.to_html(false) if back_secondary_picker != null else "F2C138"),
		"back_emblem": emblem.substr(0, 3)
	}

func _update_card_preview() -> void:
	if effect_explain_lbl != null and card_effect_opt != null and card_effect_opt.selected >= 0 and card_effect_opt.selected < EFFECT_INFO.size():
		effect_explain_lbl.text = "ℹ " + EFFECT_INFO[card_effect_opt.selected][2]

	if _preview_card_node == null:
		return
	var col := _selected_color_id()
	var cid := card_id_edit.text.strip_edges() if card_id_edit != null else ""
	var cname := card_name_edit.text.strip_edges() if card_name_edit != null else ""
	var actions := _build_current_actions()
	var sample := {
		"id": cid if not cid.is_empty() else "preview",
		"name": cname if not cname.is_empty() else "Custom",
		"color": col,
		"value": _preview_value_for_actions(actions),
		"actions": actions
	}
	var skin_to_use := "classic_arcade"
	if tab_container != null and design_tab != null and tab_container.get_current_tab_control() == design_tab:
		var preview_skin := _build_current_design_dict()
		preview_skin["id"] = "__live_preview__"
		CardTextureGenScript.register_custom_skin(preview_skin, false)
		skin_to_use = "__live_preview__"
	CardTextureGenScript.apply_card_materials_to_mesh(_preview_card_node, sample, skin_to_use, true, true)

func _on_editor_tab_changed(_tab: int) -> void:
	_update_card_preview()

func _on_preview_flip_toggled() -> void:
	_show_card_back = not _show_card_back
	_target_flip_angle = PI if _show_card_back else 0.0
	if preview_flip_btn != null:
		preview_flip_btn.text = "🔄 Vorderseite zeigen" if _show_card_back else "🔄 Rückseite zeigen"

func _on_design_color_changed(_c: Color) -> void:
	_update_card_preview()

func _on_target_game_selected(index: int) -> void:
	if model != null and target_game_opt != null and index >= 0:
		model.set_target_game(str(target_game_opt.get_item_metadata(index)))
		_set_status("Zielspiel gesetzt: %s" % target_game_opt.get_item_text(index))

func _on_preview_field_changed(_new_text: String) -> void:
	_update_card_preview()

func _on_preview_opt_changed(_index: int) -> void:
	_update_card_preview()

func _on_preview_val_changed(_val: float) -> void:
	_update_card_preview()

func _sync_ui_from_model() -> void:
	if model == null:
		return
	var data: Dictionary = model.get_pack_data()
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
	if target_game_opt != null:
		var tg := str(data.get("target_game", "uno"))
		for i in range(target_game_opt.item_count):
			if str(target_game_opt.get_item_metadata(i)) == tg:
				target_game_opt.select(i)
				break
	_refresh_card_list()

func _refresh_card_list() -> void:
	if card_list == null or model == null:
		return
	card_list.clear()
	var cards: Array = model.get_custom_cards()
	for c in cards:
		var actions_desc := str(c.get("actions", [{}])[0].get("type", ""))
		var g_tag := str(c.get("target_game", model.get_target_game()))
		var txt := "%s [%s] (%s • %s ×%d)" % [c.get("name", ""), g_tag, c.get("color", ""), actions_desc, int(c.get("count", 1))]
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
	var p := share_path_edit.text.strip_edges() if share_path_edit != null else ""
	if p.is_empty():
		_sync_model_from_ui()
		var pid := str(model.get_pack_data().get("id", "pack"))
		p = "user://packs/%s.cardpack" % pid
	var res := export_pack_or_design_to_file(p, "pack")
	if share_path_edit != null and res.get("success", false):
		share_path_edit.text = ProjectSettings.globalize_path(p)

func _on_import_button_pressed() -> void:
	var p := share_path_edit.text.strip_edges() if share_path_edit != null else ""
	if p.is_empty():
		_set_status("Bitte Dateipfad (.cardpack oder .json) oben im Import/Export-Feld angeben.")
		return
	import_pack_or_design_from_file(p)

func _on_save_design_pressed() -> void:
	var d := _build_current_design_dict()
	if CardTextureGenScript.register_custom_skin(d, true):
		_set_status("🎨 Karten-Design '%s' gespeichert & in Einstellungen auswählbar!" % d["name"])
		design_saved.emit(str(d["id"]))
	else:
		_set_status("❌ Design-ID darf nur a-z, 0-9, _ und - enthalten.")

func _on_export_design_pressed() -> void:
	var d := _build_current_design_dict()
	var p := share_path_edit.text.strip_edges() if (share_path_edit != null and not share_path_edit.text.strip_edges().is_empty()) else ("user://packs/%s.deckbox-design.json" % d["id"])
	var res := export_design_to_file(p)
	if share_path_edit != null and res.get("success", false):
		share_path_edit.text = ProjectSettings.globalize_path(p)

func export_design_to_file(output_path: String) -> Dictionary:
	return export_pack_or_design_to_file(output_path, "design")

func export_pack_or_design_to_file(output_path: String, kind: String = "pack") -> Dictionary:
	var gpath := ProjectSettings.globalize_path(output_path)
	DirAccess.make_dir_recursive_absolute(gpath.get_base_dir())
	if kind == "design" or output_path.ends_with(".deckbox-design.json"):
		var d := _build_current_design_dict()
		CardTextureGenScript.register_custom_skin(d, true)
		var f := FileAccess.open(gpath, FileAccess.WRITE)
		if f == null:
			_set_status("Design-Export fehlgeschlagen.")
			return { "success": false, "error": "Cannot open file" }
		var payload := { "deckbox_type": "card_design", "design": d }
		f.store_string(JSON.stringify(payload, "\t"))
		f.close()
		_set_status("📤 Karten-Design exportiert: %s" % gpath)
		return { "success": true, "path": gpath }

	_sync_model_from_ui()
	if output_path.ends_with(".json"):
		var f2 := FileAccess.open(gpath, FileAccess.WRITE)
		if f2 == null:
			return { "success": false, "error": "Cannot open JSON file" }
		f2.store_string(JSON.stringify(model.get_pack_data(), "\t"))
		f2.close()
		_set_status("📤 Karten-Pack als JSON exportiert: %s" % gpath)
		return { "success": true, "path": gpath }

	var res = model.export_to_file(pack_manager, gpath)
	if res.get("success", false):
		_set_status("📤 Pack exportiert nach %s" % gpath)
	else:
		_set_status("❌ Export fehlgeschlagen: " + str(res.get("error", "")))
	return res

func import_pack_or_design_from_file(input_path: String) -> Dictionary:
	var gpath := ProjectSettings.globalize_path(input_path.strip_edges())
	if not FileAccess.file_exists(gpath):
		_set_status("❌ Datei nicht gefunden: %s" % gpath)
		return { "success": false, "error": "File not found" }
	if gpath.ends_with(".cardpack") or gpath.ends_with(".zip"):
		var zip_res: Dictionary = pack_manager.load_pack_from_zip(gpath)
		if zip_res.get("success", false):
			model.load_from_dict(zip_res.get("metadata", {}))
			_sync_ui_from_model()
			_update_card_preview()
			_set_status("📥 Karten-Pack importiert: %s" % str(zip_res.get("pack_id", "")))
		else:
			_set_status("❌ Import-Fehler: %s" % str(zip_res.get("error", "")))
		return zip_res

	var f := FileAccess.open(gpath, FileAccess.READ)
	if f == null:
		return { "success": false, "error": "Cannot read file" }
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		_set_status("❌ Ungültiges JSON-Format.")
		return { "success": false, "error": "Invalid JSON" }

	if str(parsed.get("deckbox_type", "")) == "card_design" or parsed.has("design"):
		var d: Dictionary = parsed.get("design", parsed)
		if CardTextureGenScript.register_custom_skin(d, true):
			if design_id_edit != null:
				design_id_edit.text = str(d.get("id", ""))
			if design_name_edit != null:
				design_name_edit.text = str(d.get("name", ""))
			if design_emblem_edit != null:
				design_emblem_edit.text = str(d.get("back_emblem", "DB"))
			_update_card_preview()
			design_saved.emit(str(d.get("id", "")))
			_set_status("📥 Design '%s' importiert & aktiviert!" % str(d.get("name", d.get("id", ""))))
			return { "success": true, "type": "design", "skin_id": str(d.get("id", "")) }
		return { "success": false, "error": "Invalid design data" }

	var val: Dictionary = CardPackSchemaScript.validate_pack(parsed)
	if val.get("valid", false):
		model.load_from_dict(parsed)
		_sync_ui_from_model()
		_update_card_preview()
		_set_status("📥 Karten-Pack JSON importiert!")
		return { "success": true, "type": "pack" }
	_set_status("❌ Pack-Validierung fehlgeschlagen: " + ", ".join(val.get("errors", [])))
	return { "success": false, "errors": val.get("errors", []) }

func _on_add_card_pressed() -> void:
	if card_id_edit == null or card_name_edit == null:
		return
	var cid := card_id_edit.text.strip_edges()
	var cname := card_name_edit.text.strip_edges()
	var color := _selected_color_id()
	var count := int(card_count_spin.value)
	var actions := _build_current_actions()
	var target_game: String = str(model.get_target_game()) if model != null else "uno"

	var card_dict := {
		"id": cid,
		"name": cname,
		"color": color,
		"count": count,
		"target_game": target_game,
		"actions": actions
	}

	var ok: bool = model.add_custom_card(card_dict)
	if ok:
		_refresh_card_list()
		_update_card_preview()
		_set_status("Custom-Karte '%s' [%s] hinzugefügt & fürs nächste Match aktiv!" % [cname, target_game])
	else:
		_set_status("Fehler bei Karte '%s' (ID darf keine Leerzeichen haben / keine Duplikate)." % cid)

func _on_remove_card_pressed() -> void:
	if card_list == null or model == null:
		return
	var sel := card_list.get_selected_items()
	if sel.is_empty():
		return
	var cards: Array = model.get_custom_cards()
	var idx := int(sel[0])
	if idx >= 0 and idx < cards.size():
		var cid := str(cards[idx].get("id", ""))
		if model.remove_custom_card(cid):
			_refresh_card_list()
			_set_status("Karte '%s' entfernt." % cid)

func _sync_model_from_ui() -> void:
	if model == null:
		return
	if id_input != null and not id_input.text.is_empty():
		model.set_pack_id(id_input.text)
	var n := name_input.text if name_input != null else ""
	var a := author_input.text if author_input != null else ""
	var v := version_input.text if version_input != null else ""
	var d := desc_input.text if desc_input != null else ""
	model.set_metadata(n, a, v, d)

func _set_status(msg: String) -> void:
	if status_label != null:
		status_label.text = msg
