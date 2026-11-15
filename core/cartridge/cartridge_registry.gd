# cartridge_registry.gd
# Central Registry & Factory for Modular Game Cartridges
class_name CartridgeRegistry
extends RefCounted

var _cartridges: Dictionary = {} # game_id -> { "script": GDScript, "manifest": Dictionary }

func register_cartridge(game_id: String, script: GDScript, manifest: Dictionary = {}) -> bool:
	if game_id.is_empty() or script == null:
		return false
	if not script.can_instantiate():
		return false

	var effective_manifest = manifest.duplicate(true)
	if not effective_manifest.has("game_id"):
		effective_manifest["game_id"] = game_id

	_cartridges[game_id] = {
		"script": script,
		"manifest": effective_manifest
	}
	return true

func unregister_cartridge(game_id: String) -> bool:
	if not _cartridges.has(game_id):
		return false
	_cartridges.erase(game_id)
	return true

func has_cartridge(game_id: String) -> bool:
	return _cartridges.has(game_id)

func get_cartridge_manifest(game_id: String) -> Dictionary:
	if _cartridges.has(game_id):
		return _cartridges[game_id].get("manifest", {})
	return {}

func get_available_cartridges() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for gid in _cartridges.keys():
		var m = _cartridges[gid].get("manifest", {}).duplicate(true)
		if not m.has("game_id"):
			m["game_id"] = gid
		list.append(m)
	return list

func create_cartridge(game_id: String) -> RefCounted:
	if not _cartridges.has(game_id):
		return null
	var entry = _cartridges[game_id]
	var script: GDScript = entry.get("script")
	if script == null or not script.can_instantiate():
		return null
	return script.new()

func auto_register_builtin_cartridges() -> void:
	const BASE_PATH = "res://core/cartridge/game_cartridge.gd"
	if ResourceLoader.exists(BASE_PATH):
		var base_script = load(BASE_PATH)
		if base_script != null:
			register_cartridge("base_cartridge", base_script, {
				"game_id": "base_cartridge",
				"display_name": "Base Game Cartridge",
				"min_players": 2,
				"max_players": 4
			})

	const UNO_PATH = "res://games/uno/uno_cartridge.gd"
	if ResourceLoader.exists(UNO_PATH):
		var uno_script = load(UNO_PATH)
		if uno_script != null:
			register_cartridge("uno", uno_script, {
				"game_id": "uno",
				"display_name": "UNO Reference Game",
				"min_players": 2,
				"max_players": 4
			})
