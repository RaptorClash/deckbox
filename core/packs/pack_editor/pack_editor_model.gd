# pack_editor_model.gd
# RefCounted Data Model & Controller Logic for In-App Card Pack Editor
class_name PackEditorModel
extends RefCounted

const CardPackSchemaScript = preload("res://core/packs/card_pack_schema.gd")

var _draft_pack: Dictionary = {}
var _is_dirty: bool = false
var _asset_bytes: Dictionary = {} # relative_path -> PackedByteArray

func _init() -> void:
	new_pack("custom_pack", "My Custom Pack", "Anonymous")

func new_pack(id: String, name: String, author: String) -> void:
	_draft_pack = {
		"schema_version": CardPackSchemaScript.CURRENT_SCHEMA_VERSION,
		"id": id,
		"name": name,
		"author": author,
		"version": "1.0.0",
		"description": "",
		"colors": {
			"red": "#FF4444",
			"blue": "#3388FF",
			"green": "#22CC55",
			"yellow": "#FFCC00"
		},
		"assets": {
			"card_back": "backs/back_default.png"
		},
		"custom_cards": []
	}
	_asset_bytes = {}
	_is_dirty = false

func load_from_dict(data: Dictionary) -> void:
	_draft_pack = data.duplicate(true)
	if not _draft_pack.has("custom_cards") or not (_draft_pack["custom_cards"] is Array):
		_draft_pack["custom_cards"] = []
	if not _draft_pack.has("assets") or not (_draft_pack["assets"] is Dictionary):
		_draft_pack["assets"] = {}
	_asset_bytes = {}
	_is_dirty = false

func get_pack_data() -> Dictionary:
	return _draft_pack.duplicate(true)

func set_pack_id(new_id: String) -> bool:
	var clean_id = new_id.strip_edges()
	if clean_id.is_empty():
		return false
	var regex = RegEx.new()
	regex.compile("^[a-zA-Z0-9_-]+$")
	if not regex.search(clean_id):
		return false
	_draft_pack["id"] = clean_id
	_is_dirty = true
	return true

func set_metadata(p_name: String, p_author: String, p_version: String, p_desc: String) -> void:
	_draft_pack["name"] = p_name
	_draft_pack["author"] = p_author
	_draft_pack["version"] = p_version
	_draft_pack["description"] = p_desc
	_is_dirty = true

func set_color_theme(color_key: String, hex_color: String, _display_name: String = "", _symbol: String = "") -> void:
	if not _draft_pack.has("colors") or not (_draft_pack["colors"] is Dictionary):
		_draft_pack["colors"] = {}
	_draft_pack["colors"][color_key] = hex_color
	_is_dirty = true

func add_custom_card(card: Dictionary) -> bool:
	var val_res = CardPackSchemaScript.validate_custom_card(card)
	if not val_res.get("valid", false):
		return false

	var cid = str(card.get("id", card.get("card_id", "")))
	var cards: Array = _draft_pack.get("custom_cards", [])
	for existing in cards:
		if str(existing.get("id", existing.get("card_id", ""))) == cid:
			return false # Duplicate

	cards.append(card.duplicate(true))
	_draft_pack["custom_cards"] = cards
	_is_dirty = true
	return true

func update_custom_card(card_id: String, updated_card: Dictionary) -> bool:
	var val_res = CardPackSchemaScript.validate_custom_card(updated_card)
	if not val_res.get("valid", false):
		return false

	var cards: Array = _draft_pack.get("custom_cards", [])
	var found_idx = -1
	for i in range(cards.size()):
		if str(cards[i].get("id", cards[i].get("card_id", ""))) == card_id:
			found_idx = i
			break

	if found_idx == -1:
		return false

	cards[found_idx] = updated_card.duplicate(true)
	_draft_pack["custom_cards"] = cards
	_is_dirty = true
	return true

func remove_custom_card(card_id: String) -> bool:
	var cards: Array = _draft_pack.get("custom_cards", [])
	var found_idx = -1
	for i in range(cards.size()):
		if str(cards[i].get("id", cards[i].get("card_id", ""))) == card_id:
			found_idx = i
			break

	if found_idx == -1:
		return false

	cards.remove_at(found_idx)
	_draft_pack["custom_cards"] = cards
	_is_dirty = true
	return true

func get_custom_cards() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for c in _draft_pack.get("custom_cards", []):
		if c is Dictionary:
			list.append(c.duplicate(true))
	return list

func set_asset(relative_path: String, bytes: PackedByteArray) -> void:
	if CardPackSchemaScript.is_safe_relative_path(relative_path):
		_asset_bytes[relative_path] = bytes
		_is_dirty = true

func get_asset(relative_path: String) -> PackedByteArray:
	return _asset_bytes.get(relative_path, PackedByteArray())

func validate_current_draft() -> Dictionary:
	return CardPackSchemaScript.validate_pack(_draft_pack)

func export_to_file(manager: RefCounted, output_path: String) -> Dictionary:
	if manager == null:
		return { "success": false, "error": "CardPackManager is null" }
	var res = manager.export_pack_to_zip(_draft_pack, output_path, _asset_bytes)
	if res.get("success", false):
		_is_dirty = false
	return res

func is_dirty() -> bool:
	return _is_dirty
