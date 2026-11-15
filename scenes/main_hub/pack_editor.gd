# pack_editor.gd
# In-App Card Pack Editor UI Controller
extends Control

const PackEditorModelScript = preload("res://core/packs/pack_editor/pack_editor_model.gd")
const CardPackManagerScript = preload("res://core/packs/card_pack_manager.gd")

var model: RefCounted = null
var pack_manager: RefCounted = null

@onready var status_label: Label = $VBoxContainer/Footer/StatusLabel
@onready var id_input: LineEdit = $VBoxContainer/TabContainer/Metadata/GridContainer/IdEdit
@onready var name_input: LineEdit = $VBoxContainer/TabContainer/Metadata/GridContainer/NameEdit
@onready var author_input: LineEdit = $VBoxContainer/TabContainer/Metadata/GridContainer/AuthorEdit
@onready var version_input: LineEdit = $VBoxContainer/TabContainer/Metadata/GridContainer/VersionEdit
@onready var desc_input: TextEdit = $VBoxContainer/TabContainer/Metadata/GridContainer/DescEdit

@onready var card_list: ItemList = $VBoxContainer/TabContainer/Cards/HSplitContainer/CardList
@onready var card_id_edit: LineEdit = $VBoxContainer/TabContainer/Cards/HSplitContainer/CardDetails/CardIdEdit
@onready var card_name_edit: LineEdit = $VBoxContainer/TabContainer/Cards/HSplitContainer/CardDetails/CardNameEdit
@onready var card_color_opt: OptionButton = $VBoxContainer/TabContainer/Cards/HSplitContainer/CardDetails/CardColorOpt
@onready var card_count_spin: SpinBox = $VBoxContainer/TabContainer/Cards/HSplitContainer/CardDetails/CardCountSpin

func _ready() -> void:
	model = PackEditorModelScript.new()
	pack_manager = CardPackManagerScript.new()
	_setup_color_options()
	_sync_ui_from_model()

func _setup_color_options() -> void:
	if card_color_opt != null:
		card_color_opt.clear()
		var colors = ["red", "blue", "green", "yellow", "wild", "special", "colorless"]
		for c in colors:
			card_color_opt.add_item(c)

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
		var txt = "%s (%s, %s)" % [c.get("name", ""), c.get("color", ""), c.get("id", "")]
		card_list.add_item(txt)

func _on_new_button_pressed() -> void:
	model.new_pack("new_pack", "New Card Pack", "Author")
	_sync_ui_from_model()
	_set_status("Created new draft pack.")

func _on_validate_button_pressed() -> void:
	_sync_model_from_ui()
	var res = model.validate_current_draft()
	if res.get("valid", false):
		_set_status("Pack validation passed! (0 errors)")
	else:
		_set_status("Validation failed: " + ", ".join(res.get("errors", [])))

func _on_export_button_pressed() -> void:
	_sync_model_from_ui()
	var pid = model.get_pack_data().get("id", "pack")
	var export_path = "user://packs/%s.cardpack" % pid
	var res = model.export_to_file(pack_manager, export_path)
	if res.get("success", false):
		_set_status("Successfully exported pack to %s" % export_path)
	else:
		_set_status("Export failed: " + str(res.get("error", "")))

func _on_add_card_pressed() -> void:
	if card_id_edit == null or card_name_edit == null:
		return
	var cid = card_id_edit.text.strip_edges()
	var cname = card_name_edit.text.strip_edges()
	var color = card_color_opt.get_item_text(card_color_opt.selected)
	var count = int(card_count_spin.value)

	var card_dict = {
		"id": cid,
		"name": cname,
		"color": color,
		"count": count,
		"actions": [{ "type": "draw_cards", "count": 2, "target": "next" }]
	}

	var ok = model.add_custom_card(card_dict)
	if ok:
		_refresh_card_list()
		_set_status("Card '%s' added." % cid)
	else:
		_set_status("Failed to add card '%s' (validation or duplicate ID error)." % cid)

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
