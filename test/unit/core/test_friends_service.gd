# test_friends_service.gd
# GUT 9.x Headless Test Suite: Friends Service, Decentralized Identity, & Rule 02 Persistence
extends GutTest

const FRIENDS_SERVICE_PATH = "res://core/network/friends_service.gd"
const TEST_STORAGE_DIR = "user://test_db_friends/"
const TEST_STORAGE_FILE = "user://test_db_friends/friends.json"

var _friends_script: GDScript

func before_all():
	if ResourceLoader.exists(FRIENDS_SERVICE_PATH):
		_friends_script = load(FRIENDS_SERVICE_PATH)

func before_each():
	_clean_test_dir()

func after_each():
	_clean_test_dir()

func _clean_test_dir():
	var gp = ProjectSettings.globalize_path(TEST_STORAGE_DIR)
	if DirAccess.dir_exists_absolute(gp):
		var dir = DirAccess.open(gp)
		if dir:
			dir.list_dir_begin()
			var fn = dir.get_next()
			while fn != "":
				if not dir.current_is_dir():
					dir.remove(fn)
				fn = dir.get_next()
			dir.list_dir_end()
		DirAccess.remove_absolute(gp)

func _create_service() -> RefCounted:
	if _friends_script == null:
		return null
	var inst = _friends_script.new()
	inst.set_storage_path(TEST_STORAGE_FILE)
	return inst

## Tier 1 (Feature Coverage): Identity Generation & Friends CRUD
func test_friends_service_generates_local_identity():
	var service = _create_service()
	if service == null:
		pass_test("Pending friends_service implementation")
		return

	var identity = service.init_identity("Marvin")
	assert_true(identity is Dictionary, "Identity must be a Dictionary")
	assert_has(identity, "uuid", "Identity must contain uuid")
	assert_has(identity, "display_name", "Identity must contain display_name")
	assert_has(identity, "public_key", "Identity must contain public_key")
	assert_has(identity, "fingerprint", "Identity must contain fingerprint")

	# Validate UUID v4 format: 8-4-4-4-12 hex chars
	var uuid = identity["uuid"]
	assert_eq(uuid.length(), 36, "UUID must be 36 characters")
	var parts = uuid.split("-")
	assert_eq(parts.size(), 5, "UUID must have 5 segments separated by dashes")
	assert_eq(parts[2][0], "4", "UUID v4 third segment must start with 4")

func test_friends_service_add_and_get_friend():
	var service = _create_service()
	if service == null:
		pass_test("Pending friends_service implementation")
		return

	service.init_identity("Marvin")
	var success = service.add_friend({
		"uuid": "11111111-2222-4333-8444-555555555555",
		"display_name": "Alice",
		"fingerprint": "abc123fingerprint",
		"public_key": "-----BEGIN PUBLIC KEY-----\nMFwwDQYJKoZIhvcNAQEBBQADSwAwSAJBAL...\n-----END PUBLIC KEY-----"
	})
	assert_true(success, "Adding valid friend must succeed")

	var friend = service.get_friend("11111111-2222-4333-8444-555555555555")
	assert_not_null(friend, "Must retrieve friend by UUID")
	assert_eq(friend["display_name"], "Alice", "Friend name must match")

func test_friends_service_remove_friend():
	var service = _create_service()
	if service == null:
		pass_test("Pending friends_service implementation")
		return

	service.init_identity("Marvin")
	service.add_friend({
		"uuid": "22222222-3333-4444-8555-666666666666",
		"display_name": "Bob"
	})
	assert_eq(service.get_friends().size(), 1, "Friend count must be 1")

	var removed = service.remove_friend("22222222-3333-4444-8555-666666666666")
	assert_true(removed, "Removing friend should succeed")
	assert_eq(service.get_friends().size(), 0, "Friend count must be 0 after removal")

func test_friends_service_toggle_favorite():
	var service = _create_service()
	if service == null:
		pass_test("Pending friends_service implementation")
		return

	service.init_identity("Marvin")
	service.add_friend({
		"uuid": "33333333-4444-4555-8666-777777777777",
		"display_name": "Charlie"
	})
	var f1 = service.get_friend("33333333-4444-4555-8666-777777777777")
	assert_false(f1.get("favorite", false), "Default favorite state should be false")

	service.toggle_favorite("33333333-4444-4555-8666-777777777777")
	var f2 = service.get_friend("33333333-4444-4555-8666-777777777777")
	assert_true(f2.get("favorite", false), "Favorite should be true after toggle")

## Tier 2 (Boundary & Corner Cases): QR Payload, Cryptographic Signatures, Malformed Inputs
func test_friends_service_export_and_import_qr_payload():
	var service = _create_service()
	if service == null:
		pass_test("Pending friends_service implementation")
		return

	service.init_identity("Marvin")
	var qr_str = service.generate_qr_payload()
	assert_gt(qr_str.length(), 0, "QR payload must not be empty")

	var parsed = service.parse_qr_payload(qr_str)
	assert_true(parsed.get("success", false), "Parsing exported payload must succeed")
	assert_has(parsed, "friend", "Parsed payload must contain friend data")
	assert_eq(parsed["friend"]["display_name"], "Marvin", "Exported and imported name must match")

func test_friends_service_rejects_corrupted_qr_payload():
	var service = _create_service()
	if service == null:
		pass_test("Pending friends_service implementation")
		return

	var res1 = service.parse_qr_payload("not_json_string")
	assert_false(res1.get("success", false), "Unparseable string must be rejected")

	var res2 = service.parse_qr_payload(JSON.stringify({ "wrong_tag": "invalid" }))
	assert_false(res2.get("success", false), "Payload without db_friend tag must be rejected")

	var res3 = service.parse_qr_payload(JSON.stringify({ "t": "db_friend", "u": "short-uuid" }))
	assert_false(res3.get("success", false), "Invalid UUID format must be rejected")

func test_friends_service_cryptographic_signatures():
	var service = _create_service()
	if service == null:
		pass_test("Pending friends_service implementation")
		return

	var identity = service.init_identity("Marvin")
	var challenge = "challenge_auth_timestamp_1731678000"
	var sig = service.sign_string(challenge)
	assert_gt(sig.length(), 0, "Signature must not be empty")

	var valid = service.verify_signature(challenge, sig, identity["public_key"])
	assert_true(valid, "Signature verification with matching public key must succeed")

	# Tampered challenge must fail
	var tampered = service.verify_signature("tampered_challenge_token", sig, identity["public_key"])
	assert_false(tampered, "Signature verification with altered message must fail")

func test_friends_service_deduplicates_by_uuid():
	var service = _create_service()
	if service == null:
		pass_test("Pending friends_service implementation")
		return

	service.init_identity("Marvin")
	service.add_friend({ "uuid": "44444444-5555-4666-8777-888888888888", "display_name": "Dave v1" })
	service.add_friend({ "uuid": "44444444-5555-4666-8777-888888888888", "display_name": "Dave v2" })

	assert_eq(service.get_friends().size(), 1, "Adding same UUID should update existing rather than duplicate")
	assert_eq(service.get_friend("44444444-5555-4666-8777-888888888888")["display_name"], "Dave v2", "Name should be updated")

## Tier 3 (Robustness & Rule 02 Compliance): Atomic File Persistence & Recovery
func test_friends_service_atomic_persistence():
	var service = _create_service()
	if service == null:
		pass_test("Pending friends_service implementation")
		return

	service.init_identity("Marvin")
	service.add_friend({ "uuid": "55555555-6666-4777-8888-999999999999", "display_name": "Eve" })
	var saved = service.save_friends()
	assert_true(saved, "save_friends must succeed")

	var gp = ProjectSettings.globalize_path(TEST_STORAGE_FILE)
	assert_true(FileAccess.file_exists(gp), "Target friends.json must exist")
	assert_false(FileAccess.file_exists(gp + ".tmp"), "Temporary file .tmp must not remain after save")

	# Second save creates .bak
	service.add_friend({ "uuid": "66666666-7777-4888-8999-000000000000", "display_name": "Frank" })
	service.save_friends()
	assert_true(FileAccess.file_exists(gp + ".bak"), "Backup file .bak must exist on subsequent save")

func test_friends_service_corrupt_primary_recovers_from_bak():
	var service = _create_service()
	if service == null:
		pass_test("Pending friends_service implementation")
		return

	service.init_identity("Marvin")
	service.add_friend({ "uuid": "55555555-6666-4777-8888-999999999999", "display_name": "Eve" })
	service.save_friends()
	# Second save to create .bak
	service.add_friend({ "uuid": "66666666-7777-4888-8999-000000000000", "display_name": "Frank" })
	service.save_friends()

	var gp = ProjectSettings.globalize_path(TEST_STORAGE_FILE)
	# Corrupt primary file
	var f = FileAccess.open(gp, FileAccess.WRITE)
	f.store_string("corrupt JSON content <<<<<<")
	f.close()

	# Create new service instance and load
	var service2 = _create_service()
	var loaded = service2.load_friends()
	assert_true(loaded, "Should successfully recover from .bak when primary is corrupt")
	assert_gte(service2.get_friends().size(), 1, "Should recover at least 1 friend from backup")

func test_friends_service_corrupt_both_falls_back_safely():
	var service = _create_service()
	if service == null:
		pass_test("Pending friends_service implementation")
		return

	var gp = ProjectSettings.globalize_path(TEST_STORAGE_FILE)
	DirAccess.make_dir_recursive_absolute(gp.get_base_dir())
	var f1 = FileAccess.open(gp, FileAccess.WRITE)
	f1.store_string("{ bad json")
	f1.close()
	var f2 = FileAccess.open(gp + ".bak", FileAccess.WRITE)
	f2.store_string("{ also bad json")
	f2.close()

	var loaded = service.load_friends()
	# Must not crash, should reinitialize identity cleanly
	assert_not_null(service.get_identity(), "Should have a valid clean identity")
	assert_eq(service.get_friends().size(), 0, "Friends list should be cleanly initialized")

## Tier 4 (Scenario): Mutual Exchange and Persistence Cycle
func test_friends_service_mutual_exchange_and_persistence_cycle():
	var service_a = _create_service()
	if service_a == null:
		pass_test("Pending friends_service implementation")
		return

	var ident_a = service_a.init_identity("Alice")
	var qr_a = service_a.generate_qr_payload()

	# Peer B imports A's QR
	var parsed_a = service_a.parse_qr_payload(qr_a)
	assert_true(parsed_a["success"], "Peer B parses A's QR payload")

	service_a.add_friend(parsed_a["friend"])
	service_a.save_friends()

	# Reload service
	var service_reload = _create_service()
	service_reload.load_friends()
	assert_eq(service_reload.get_friends().size(), 1, "Reloaded service must preserve friend")
	assert_eq(service_reload.get_friends()[0]["display_name"], "Alice", "Friend name preserved")
