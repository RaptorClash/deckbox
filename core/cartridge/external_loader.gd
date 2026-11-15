# external_loader.gd
# Safe Mounting & Validation of External .pck Cartridges
class_name ExternalLoader
extends RefCounted

const MAX_PACKAGE_SIZE_BYTES: int = 100 * 1024 * 1024 # 100 MB

func validate_package_path(pck_path: String) -> Dictionary:
	if pck_path.is_empty():
		return { "valid": false, "error": "Empty package path" }
	if pck_path.contains("..") or pck_path.contains(char(0)):
		return { "valid": false, "error": "Path traversal rejected: '..' or null bytes detected" }
	if not pck_path.to_lower().ends_with(".pck"):
		return { "valid": false, "error": "Invalid file extension; must end with .pck" }
	if not FileAccess.file_exists(pck_path):
		return { "valid": false, "error": "Package file does not exist: %s" % pck_path }

	var fa = FileAccess.open(pck_path, FileAccess.READ)
	if fa != null:
		var sz = fa.get_length()
		fa.close()
		if sz > MAX_PACKAGE_SIZE_BYTES:
			return { "valid": false, "error": "Package size %d exceeds limit of %d bytes" % [sz, MAX_PACKAGE_SIZE_BYTES] }

	return { "valid": true }

func validate_manifest(manifest: Variant) -> Dictionary:
	if not (manifest is Dictionary):
		return { "valid": false, "error": "Manifest must be a Dictionary" }

	var required_keys = ["game_id", "display_name", "version", "min_players", "max_players", "entry_script"]
	for k in required_keys:
		if not manifest.has(k):
			return { "valid": false, "error": "Missing required manifest key: %s" % k }

	var min_p = int(manifest.get("min_players", 0))
	var max_p = int(manifest.get("max_players", 0))
	if min_p < 2:
		return { "valid": false, "error": "min_players must be at least 2, got %d" % min_p }
	if max_p < min_p:
		return { "valid": false, "error": "max_players (%d) must be >= min_players (%d)" % [max_p, min_p] }

	var gid = str(manifest.get("game_id", ""))
	if gid.is_empty():
		return { "valid": false, "error": "game_id cannot be empty" }

	var entry = str(manifest.get("entry_script", ""))
	if entry.is_empty():
		return { "valid": false, "error": "entry_script cannot be empty" }

	return { "valid": true }

func load_cartridge_package(pck_path: String, registry: RefCounted = null) -> Dictionary:
	var path_val = validate_package_path(pck_path)
	if not path_val.get("valid", false):
		return { "success": false, "error": path_val.get("error", "Invalid path") }

	var mount_ok = ProjectSettings.load_resource_pack(pck_path, false)
	if not mount_ok:
		return { "success": false, "error": "ProjectSettings.load_resource_pack failed to mount %s" % pck_path }

	# Read manifest if present
	var manifest_path = "res://cartridge.json"
	var manifest = {}
	if FileAccess.file_exists(manifest_path):
		var file = FileAccess.open(manifest_path, FileAccess.READ)
		if file != null:
			var txt = file.get_as_text()
			file.close()
			var parsed = JSON.parse_string(txt)
			if parsed is Dictionary:
				manifest = parsed

	var val_res = validate_manifest(manifest)
	if not val_res.get("valid", false):
		return { "success": false, "error": "Mounted cartridge has invalid manifest: %s" % val_res.get("error", "") }

	var entry_script_path = str(manifest.get("entry_script", ""))
	if not ResourceLoader.exists(entry_script_path):
		return { "success": false, "error": "Entry script does not exist: %s" % entry_script_path }

	var script = load(entry_script_path)
	if script == null or not script.can_instantiate():
		return { "success": false, "error": "Cannot instantiate entry script: %s" % entry_script_path }

	var gid = str(manifest.get("game_id", ""))
	if registry != null:
		registry.register_cartridge(gid, script, manifest)

	return {
		"success": true,
		"game_id": gid,
		"manifest": manifest
	}
