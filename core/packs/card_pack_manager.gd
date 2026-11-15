# card_pack_manager.gd
# Manager for .cardpack ZIP Bundles, SHA-256 Hashing, Asset Extraction & Pack Discovery
class_name CardPackManager
extends RefCounted

const CardPackSchemaScript = preload("res://core/packs/card_pack_schema.gd")

var _loaded_packs: Dictionary = {} # pack_id -> { "metadata": Dictionary, "hash": String, "zip_path": String }
var _hash_to_id: Dictionary = {}   # sha256 -> pack_id
var _staging_dir: String = "user://packs_staging/"
var _installed_packs_dir: String = "user://packs/"

func _init() -> void:
	_ensure_directory(_staging_dir)
	_ensure_directory(_installed_packs_dir)

func _ensure_directory(dir_path: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

func load_pack_from_zip(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return { "success": false, "error": "Pack file does not exist: %s" % path }

	var sha256_hash = FileAccess.get_sha256(path)
	if sha256_hash.is_empty():
		return { "success": false, "error": "Failed to compute SHA-256 for file: %s" % path }

	var reader = ZIPReader.new()
	var err = reader.open(path)
	if err != OK:
		return { "success": false, "error": "Corrupt or invalid ZIP archive (error code %d)" % err }

	var files = reader.get_files()
	if not files.has("pack.json"):
		reader.close()
		return { "success": false, "error": "Archive missing required 'pack.json' manifest" }

	var manifest_bytes = reader.read_file("pack.json")
	reader.close()

	var manifest_str = manifest_bytes.get_string_from_utf8()
	var pack_data = JSON.parse_string(manifest_str)
	if not (pack_data is Dictionary):
		return { "success": false, "error": "Failed to parse 'pack.json' as valid JSON dictionary" }

	var val_res = CardPackSchemaScript.validate_pack(pack_data)
	if not val_res.get("valid", false):
		return { "success": false, "error": "Pack schema validation failed: %s" % str(val_res.get("errors", [])) }

	var pack_id = str(pack_data.get("id", pack_data.get("pack_id", "")))

	_loaded_packs[pack_id] = {
		"metadata": pack_data,
		"hash": sha256_hash,
		"zip_path": path
	}
	_hash_to_id[sha256_hash] = pack_id

	return {
		"success": true,
		"pack_id": pack_id,
		"hash": sha256_hash,
		"metadata": pack_data
	}

func load_pack_from_bytes(bytes: PackedByteArray, filename: String = "") -> Dictionary:
	if bytes.is_empty():
		return { "success": false, "error": "Pack bytes cannot be empty" }

	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	var hash_bytes = ctx.finish()
	var sha256_hash = hash_bytes.hex_encode()

	if _hash_to_id.has(sha256_hash):
		var pid = _hash_to_id[sha256_hash]
		return {
			"success": true,
			"pack_id": pid,
			"hash": sha256_hash,
			"metadata": _loaded_packs[pid]["metadata"]
		}

	_ensure_directory(_staging_dir)
	var clean_name = filename.get_file().strip_edges()
	if clean_name.is_empty() or clean_name == ".." or not CardPackSchemaScript.is_safe_relative_path(clean_name):
		clean_name = sha256_hash + ".cardpack"
	var staging_path = _staging_dir.path_join(clean_name)

	var fa = FileAccess.open(staging_path, FileAccess.WRITE)
	if fa == null:
		return { "success": false, "error": "Failed to write staging file: %s" % staging_path }
	fa.store_buffer(bytes)
	fa.close()

	return load_pack_from_zip(staging_path)

func export_pack_to_zip(pack_data: Dictionary, output_path: String, asset_bytes_map: Dictionary = {}) -> Dictionary:
	var val_res = CardPackSchemaScript.validate_pack(pack_data)
	if not val_res.get("valid", false):
		return { "success": false, "error": "Cannot export invalid pack: %s" % str(val_res.get("errors", [])) }

	var out_dir = output_path.get_base_dir()
	if not out_dir.is_empty():
		_ensure_directory(out_dir)

	var packer = ZIPPacker.new()
	var err = packer.open(output_path, ZIPPacker.APPEND_CREATE)
	if err != OK:
		return { "success": false, "error": "ZIPPacker failed to create %s (code %d)" % [output_path, err] }

	# Write pack.json
	packer.start_file("pack.json")
	var json_str = JSON.stringify(pack_data, "\t")
	packer.write_file(json_str.to_utf8_buffer())
	packer.close_file()

	# Write assets
	for rel_path in asset_bytes_map.keys():
		if not CardPackSchemaScript.is_safe_relative_path(rel_path):
			packer.close()
			return { "success": false, "error": "Unsafe asset path rejected in export: '%s'" % rel_path }
		var bytes = asset_bytes_map[rel_path]
		packer.start_file(rel_path)
		if bytes is PackedByteArray:
			packer.write_file(bytes)
		elif bytes is String:
			packer.write_file(bytes.to_utf8_buffer())
		packer.close_file()

	packer.close()

	var sha256_hash = FileAccess.get_sha256(output_path)
	var pack_id = str(pack_data.get("id", pack_data.get("pack_id", "")))

	_loaded_packs[pack_id] = {
		"metadata": pack_data,
		"hash": sha256_hash,
		"zip_path": output_path
	}
	_hash_to_id[sha256_hash] = pack_id

	return {
		"success": true,
		"path": output_path,
		"hash": sha256_hash,
		"pack_id": pack_id
	}

func read_pack_asset(pack_id: String, relative_path: String) -> PackedByteArray:
	if not CardPackSchemaScript.is_safe_relative_path(relative_path):
		return PackedByteArray()
	if not _loaded_packs.has(pack_id):
		return PackedByteArray()

	var zip_path = _loaded_packs[pack_id].get("zip_path", "")
	if not FileAccess.file_exists(zip_path):
		return PackedByteArray()

	var reader = ZIPReader.new()
	var err = reader.open(zip_path)
	if err != OK:
		return PackedByteArray()

	if not reader.get_files().has(relative_path):
		reader.close()
		return PackedByteArray()

	var bytes = reader.read_file(relative_path)
	reader.close()
	return bytes

func get_card_back_texture_data(pack_id: String) -> PackedByteArray:
	if not _loaded_packs.has(pack_id):
		return PackedByteArray()
	var meta = _loaded_packs[pack_id].get("metadata", {})
	var assets = meta.get("assets", {})
	var back_path = str(assets.get("card_back", ""))
	if back_path.is_empty():
		return PackedByteArray()
	return read_pack_asset(pack_id, back_path)

func has_pack(pack_id: String) -> bool:
	return _loaded_packs.has(pack_id)

func has_pack_hash(hash: String) -> bool:
	return _hash_to_id.has(hash)

func get_pack(pack_id: String) -> Dictionary:
	if _loaded_packs.has(pack_id):
		return _loaded_packs[pack_id].get("metadata", {})
	return {}

func get_pack_by_hash(hash: String) -> Dictionary:
	if _hash_to_id.has(hash):
		var pid = _hash_to_id[hash]
		return get_pack(pid)
	return {}

func get_rules_hash(pack_id: String) -> String:
	if _loaded_packs.has(pack_id):
		return _loaded_packs[pack_id].get("hash", "")
	return ""

func scan_installed_packs(dir_path: String = "") -> Array[Dictionary]:
	var target_dir = dir_path if not dir_path.is_empty() else _installed_packs_dir
	var result: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(target_dir):
		return result

	var dir = DirAccess.open(target_dir)
	if dir != null:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while not file_name.is_empty():
			if not dir.current_is_dir() and (file_name.ends_with(".cardpack") or file_name.ends_with(".zip")):
				var full_p = target_dir.path_join(file_name)
				var load_res = load_pack_from_zip(full_p)
				if load_res.get("success", false):
					result.append(load_res.get("metadata", {}))
			file_name = dir.get_next()
		dir.list_dir_end()
	return result
