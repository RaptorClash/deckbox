# friends_service.gd
# Decentralized cryptographic identity, digital signatures, and friends persistence (Rule 02 compliant)
class_name FriendsService
extends RefCounted

const CURRENT_SCHEMA_VERSION: int = 1
const DEFAULT_STORAGE_PATH: String = "user://database/friends.json"

var _storage_path: String = DEFAULT_STORAGE_PATH
var _my_identity: Dictionary = {}
var _friends: Array[Dictionary] = []
var _crypto: Crypto = Crypto.new()

func set_storage_path(path: String) -> void:
	_storage_path = path

func init_identity(display_name: String = "Player") -> Dictionary:
	if not _my_identity.is_empty():
		return _my_identity

	var uuid = _generate_uuid_v4()
	var key = _crypto.generate_rsa(1024)
	var pub_pem = key.save_to_string(true)
	var priv_pem = key.save_to_string(false)
	var fp = _sha256(pub_pem.to_utf8_buffer()).hex_encode()

	_my_identity = {
		"uuid": uuid,
		"display_name": display_name,
		"public_key": pub_pem,
		"private_key": priv_pem,
		"fingerprint": fp,
		"created_at": int(Time.get_unix_time_from_system())
	}
	return _my_identity

func get_identity() -> Dictionary:
	if _my_identity.is_empty():
		init_identity()
	return _my_identity

func add_friend(friend_dict: Dictionary) -> bool:
	var uuid = str(friend_dict.get("uuid", "")).strip_edges()
	if uuid.length() != 36:
		return false

	var display_name = str(friend_dict.get("display_name", "Friend")).strip_edges()
	if display_name.is_empty():
		display_name = "Friend"

	# Check for existing friend by UUID (deduplicate)
	for i in range(_friends.size()):
		if _friends[i].get("uuid", "") == uuid:
			_friends[i]["display_name"] = display_name
			if friend_dict.has("fingerprint"):
				_friends[i]["fingerprint"] = friend_dict["fingerprint"]
			if friend_dict.has("public_key"):
				_friends[i]["public_key"] = friend_dict["public_key"]
			_friends[i]["updated_at"] = int(Time.get_unix_time_from_system())
			return true

	var new_friend = {
		"uuid": uuid,
		"display_name": display_name,
		"fingerprint": str(friend_dict.get("fingerprint", "")),
		"public_key": str(friend_dict.get("public_key", "")),
		"favorite": bool(friend_dict.get("favorite", false)),
		"added_at": int(Time.get_unix_time_from_system()),
		"last_played": int(Time.get_unix_time_from_system())
	}
	_friends.append(new_friend)
	return true

func get_friend(uuid: String) -> Variant:
	for f in _friends:
		if f.get("uuid", "") == uuid:
			return f
	return null

func get_friends() -> Array[Dictionary]:
	return _friends.duplicate(true)

func remove_friend(uuid: String) -> bool:
	for i in range(_friends.size()):
		if _friends[i].get("uuid", "") == uuid:
			_friends.remove_at(i)
			return true
	return false

func toggle_favorite(uuid: String) -> bool:
	for i in range(_friends.size()):
		if _friends[i].get("uuid", "") == uuid:
			_friends[i]["favorite"] = not _friends[i].get("favorite", false)
			return true
	return false

func generate_qr_payload() -> String:
	if _my_identity.is_empty():
		init_identity()

	return JSON.stringify({
		"t": "db_friend",
		"v": 1,
		"u": _my_identity.get("uuid", ""),
		"n": _my_identity.get("display_name", ""),
		"fp": _my_identity.get("fingerprint", ""),
		"k": _my_identity.get("public_key", "")
	})

func parse_qr_payload(json_str: String) -> Dictionary:
	var p = _safe_parse_json(json_str)
	if not (p is Dictionary):
		return { "success": false, "error": "Not a JSON object" }
	if p.get("t") != "db_friend":
		return { "success": false, "error": "Missing db_friend tag" }

	var u = str(p.get("u", "")).strip_edges()
	if u.length() != 36:
		return { "success": false, "error": "Invalid UUID length" }

	return {
		"success": true,
		"friend": {
			"uuid": u,
			"display_name": str(p.get("n", "Friend")),
			"fingerprint": str(p.get("fp", "")),
			"public_key": str(p.get("k", "")),
			"added_at": int(Time.get_unix_time_from_system()),
			"favorite": false
		}
	}

func sign_string(message: String) -> String:
	if _my_identity.is_empty():
		init_identity()
	var priv_pem = _my_identity.get("private_key", "")
	if priv_pem.is_empty():
		return ""

	var key = CryptoKey.new()
	var err = key.load_from_string(priv_pem, false)
	if err != OK:
		return ""

	var digest = _sha256(message.to_utf8_buffer())
	var sig = _crypto.sign(HashingContext.HASH_SHA256, digest, key)
	return Marshalls.raw_to_base64(sig)

func verify_signature(message: String, signature_b64: String, pub_pem: String) -> bool:
	if pub_pem.is_empty() or signature_b64.is_empty():
		return false

	var key = CryptoKey.new()
	var err = key.load_from_string(pub_pem, true)
	if err != OK:
		return false

	var digest = _sha256(message.to_utf8_buffer())
	var raw_sig = Marshalls.base64_to_raw(signature_b64)
	return _crypto.verify(HashingContext.HASH_SHA256, digest, raw_sig, key)

func save_friends() -> bool:
	var global_path = ProjectSettings.globalize_path(_storage_path)
	var base_dir = global_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(base_dir)

	var global_tmp = global_path + ".tmp"
	var global_bak = global_path + ".bak"

	var f = FileAccess.open(global_tmp, FileAccess.WRITE)
	if f == null:
		return false

	var payload = {
		"schema_version": CURRENT_SCHEMA_VERSION,
		"my_identity": _my_identity,
		"friends": _friends
	}
	f.store_string(JSON.stringify(payload, "\t"))
	f.flush()
	f.close()

	# Rotate existing to .bak
	if FileAccess.file_exists(global_path):
		if FileAccess.file_exists(global_bak):
			DirAccess.remove_absolute(global_bak)
		DirAccess.copy_absolute(global_path, global_bak)

	# Atomic rename .tmp to target
	var rename_err = DirAccess.rename_absolute(global_tmp, global_path)
	return rename_err == OK

func load_friends() -> bool:
	var global_path = ProjectSettings.globalize_path(_storage_path)
	var global_bak = global_path + ".bak"

	for path in [global_path, global_bak]:
		if FileAccess.file_exists(path):
			var content = FileAccess.get_file_as_string(path)
			var parsed = _safe_parse_json(content)
			if parsed is Dictionary and parsed.has("my_identity") and parsed.has("friends"):
				_my_identity = parsed["my_identity"]
				_friends.clear()
				for item in parsed["friends"]:
					if item is Dictionary:
						_friends.append(item)
				return true

	# Clean fallback
	init_identity()
	_friends.clear()
	return false

static func _safe_parse_json(text: String) -> Variant:
	var json = JSON.new()
	var err = json.parse(text)
	if err == OK:
		return json.data
	return null

func _generate_uuid_v4() -> String:
	var b = _crypto.generate_random_bytes(16)
	b[6] = (b[6] & 0x0F) | 0x40 # version 4
	b[8] = (b[8] & 0x3F) | 0x80 # variant RFC 4122
	return "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x" % [
		b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
		b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]
	]

func _sha256(data: PackedByteArray) -> PackedByteArray:
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	return ctx.finish()
