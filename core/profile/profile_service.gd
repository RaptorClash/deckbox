# core/profile/profile_service.gd
# Manages local player profile persistence, cryptographic identity, and schema migrations.
class_name ProfileService extends RefCounted

const CURRENT_SCHEMA_VERSION: int = 2
const DEFAULT_STORAGE_PATH: String = "user://database/profile.json"
const DEFAULT_THEME_PRESET: String = "arcade_ps5"
const DEFAULT_QUALITY_PRESET: String = "high"
const DEFAULT_AVATAR_ID: String = "avatar_default_01"
const DEFAULT_CARD_BACK: String = "classic_blue"

var _storage_path: String = DEFAULT_STORAGE_PATH
var _profile_data: Dictionary = {}
var _crypto: Crypto = Crypto.new()

func _init() -> void:
	pass

func set_storage_path(path: String) -> void:
	_storage_path = path

func get_storage_path() -> String:
	return _storage_path

func create_default_profile(display_name: String = "Player") -> Dictionary:
	var clean_name = display_name.strip_edges()
	if clean_name.is_empty():
		clean_name = "Player"

	var uuid_str = _generate_uuid_v4()
	var now = int(Time.get_unix_time_from_system())

	var keypair_data = _generate_keypair()

	var profile = {
		"schema_version": CURRENT_SCHEMA_VERSION,
		"player_id": uuid_str,
		"uuid": uuid_str,
		"display_name": clean_name,
		"avatar_id": DEFAULT_AVATAR_ID,
		"preferred_card_back": DEFAULT_CARD_BACK,
		"preferred_back": DEFAULT_CARD_BACK,
		"theme_preset": DEFAULT_THEME_PRESET,
		"quality_preset": DEFAULT_QUALITY_PRESET,
		"colorblind_mode": false,
		"created_at": now,
		"updated_at": now,
		"keypair": keypair_data
	}

	return profile

func save_profile(data: Dictionary) -> bool:
	var to_save = migrate_schema(data.duplicate(true))
	to_save["updated_at"] = int(Time.get_unix_time_from_system())

	# Ensure uuid and player_id match
	if to_save.has("player_id") and not to_save.has("uuid"):
		to_save["uuid"] = to_save["player_id"]
	elif to_save.has("uuid") and not to_save.has("player_id"):
		to_save["player_id"] = to_save["uuid"]

	# Ensure preferred_back and preferred_card_back match
	if to_save.has("preferred_card_back"):
		to_save["preferred_back"] = to_save["preferred_card_back"]
	elif to_save.has("preferred_back"):
		to_save["preferred_card_back"] = to_save["preferred_back"]

	var global_path = ProjectSettings.globalize_path(_storage_path)
	var dir_path = global_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir_path)

	var tmp_path = global_path + ".tmp"
	var bak_path = global_path + ".bak"

	var file = FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("ProfileService: Cannot open tmp file for writing: %s" % tmp_path)
		return false

	var json_str = JSON.stringify(to_save, "\t")
	file.store_string(json_str)
	file.flush()
	file.close()

	# Create .bak from existing main file before replacing
	if FileAccess.file_exists(global_path):
		DirAccess.copy_absolute(global_path, bak_path)

	# Atomic rename .tmp -> main
	var err = DirAccess.rename_absolute(tmp_path, global_path)
	if err != OK:
		# Windows retry fallback if lock occurred
		DirAccess.remove_absolute(global_path)
		err = DirAccess.rename_absolute(tmp_path, global_path)

	if err == OK:
		_profile_data = to_save.duplicate(true)
		return true
	else:
		push_error("ProfileService: Atomic rename failed with error code: %d" % err)
		return false

func load_profile() -> Dictionary:
	var global_path = ProjectSettings.globalize_path(_storage_path)
	var bak_path = global_path + ".bak"

	# Try primary file
	var loaded = _read_json_file(global_path)
	if loaded != null and loaded is Dictionary and not loaded.is_empty():
		_profile_data = migrate_schema(loaded)
		return _profile_data

	# Failover to .bak
	if FileAccess.file_exists(bak_path):
		var bak_loaded = _read_json_file(bak_path)
		if bak_loaded != null and bak_loaded is Dictionary and not bak_loaded.is_empty():
			push_warning("ProfileService: Recovered profile from .bak fallback.")
			_profile_data = migrate_schema(bak_loaded)
			# Re-save to restore primary file
			save_profile(_profile_data)
			return _profile_data

	# Both failed or nonexistent -> generate clean default
	push_warning("ProfileService: No valid profile found. Creating clean defaults.")
	var fresh = create_default_profile("Player")
	save_profile(fresh)
	_profile_data = fresh
	return _profile_data

func migrate_schema(data: Dictionary) -> Dictionary:
	var migrated = data.duplicate(true)
	var ver = int(migrated.get("schema_version", 1))

	if ver < 2:
		migrated["schema_version"] = CURRENT_SCHEMA_VERSION
		if not migrated.has("avatar_id"):
			migrated["avatar_id"] = DEFAULT_AVATAR_ID
		if not migrated.has("preferred_card_back"):
			migrated["preferred_card_back"] = DEFAULT_CARD_BACK
		if not migrated.has("preferred_back"):
			migrated["preferred_back"] = migrated.get("preferred_card_back", DEFAULT_CARD_BACK)
		if not migrated.has("theme_preset"):
			migrated["theme_preset"] = DEFAULT_THEME_PRESET
		if not migrated.has("quality_preset"):
			migrated["quality_preset"] = DEFAULT_QUALITY_PRESET
		if not migrated.has("colorblind_mode"):
			migrated["colorblind_mode"] = false
		if not migrated.has("updated_at"):
			migrated["updated_at"] = int(Time.get_unix_time_from_system())
		if not migrated.has("uuid") and migrated.has("player_id"):
			migrated["uuid"] = migrated["player_id"]
		if not migrated.has("keypair"):
			migrated["keypair"] = _generate_keypair()
	else:
		# Retain all future fields non-destructively
		if not migrated.has("preferred_back") and migrated.has("preferred_card_back"):
			migrated["preferred_back"] = migrated["preferred_card_back"]
		elif not migrated.has("preferred_card_back") and migrated.has("preferred_back"):
			migrated["preferred_card_back"] = migrated["preferred_back"]
		if not migrated.has("uuid") and migrated.has("player_id"):
			migrated["uuid"] = migrated["player_id"]

	return migrated

func update_profile(patch: Dictionary) -> bool:
	if _profile_data.is_empty():
		load_profile()

	var updated = _profile_data.duplicate(true)
	for key in patch:
		if patch[key] != null:
			updated[key] = patch[key]

	return save_profile(updated)

func get_profile() -> Dictionary:
	if _profile_data.is_empty():
		return load_profile()
	return _profile_data.duplicate(true)

func _read_json_file(path: String):
	if not FileAccess.file_exists(path):
		return null
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var content = file.get_as_text()
	file.close()

	var json = JSON.new()
	var err = json.parse(content)
	if err == OK:
		return json.data
	return null

func _generate_uuid_v4() -> String:
	var b = _crypto.generate_random_bytes(16)
	b[6] = (b[6] & 0x0F) | 0x40
	b[8] = (b[8] & 0x3F) | 0x80
	return "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x" % [
		b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
		b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]
	]

func _generate_keypair() -> Dictionary:
	var key = _crypto.generate_rsa(1024)
	if key == null:
		return {}
	var pub_pem = key.save_to_string(true)
	var priv_pem = key.save_to_string(false)
	var fp = _sha256(pub_pem.to_utf8_buffer()).hex_encode()
	return {
		"public_key": pub_pem,
		"private_key": priv_pem,
		"fingerprint": fp
	}

func _sha256(data: PackedByteArray) -> PackedByteArray:
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	return ctx.finish()
