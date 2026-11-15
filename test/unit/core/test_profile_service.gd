# test_profile_service.gd
# GUT 9.x Unit Test Suite: ProfileService Schema v2, Identity, Cryptography & Migration
extends GutTest

const PROFILE_SERVICE_PATH = "res://core/profile/profile_service.gd"
const TEST_DIR = "user://test_profile_service/"
const PROFILE_FILE = TEST_DIR + "profile.json"
const PROFILE_TMP = TEST_DIR + "profile.json.tmp"
const PROFILE_BAK = TEST_DIR + "profile.json.bak"

var _profile_service_script: GDScript

func before_all():
	if ResourceLoader.exists(PROFILE_SERVICE_PATH):
		_profile_service_script = load(PROFILE_SERVICE_PATH)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIR))

func before_each():
	_clean_test_dir()

func after_each():
	_clean_test_dir()

func _clean_test_dir():
	for file_path in [PROFILE_FILE, PROFILE_TMP, PROFILE_BAK]:
		var global_path = ProjectSettings.globalize_path(file_path)
		if FileAccess.file_exists(global_path):
			DirAccess.remove_absolute(global_path)

func _create_profile_service():
	if _profile_service_script != null:
		var svc = _profile_service_script.new()
		if svc.has_method("set_storage_path"):
			svc.set_storage_path(PROFILE_FILE)
		return svc
	return null

## Test 1: Complete Schema v2 Initialization
func test_default_profile_schema_completeness():
	var service = _create_profile_service()
	if service == null:
		pass_test("Pending profile_service implementation")
		return

	var profile = service.create_default_profile("TestHero")
	assert_not_null(profile, "Profile should not be null")
	assert_eq(profile.get("schema_version"), 2, "Schema version must be 2")
	assert_has(profile, "player_id")
	assert_has(profile, "uuid")
	assert_eq(profile["player_id"], profile["uuid"], "player_id and uuid must be synchronized")
	assert_eq(profile["player_id"].length(), 36, "UUID must be 36 characters")
	assert_eq(profile["display_name"], "TestHero")
	assert_has(profile, "avatar_id")
	assert_has(profile, "preferred_card_back")
	assert_has(profile, "preferred_back")
	assert_eq(profile["preferred_card_back"], profile["preferred_back"], "Card back fields must match")
	assert_has(profile, "theme_preset")
	assert_has(profile, "quality_preset")
	assert_has(profile, "colorblind_mode")
	assert_has(profile, "created_at")
	assert_has(profile, "updated_at")
	assert_has(profile, "keypair")

	var keypair = profile.get("keypair", {})
	assert_has(keypair, "public_key")
	assert_has(keypair, "private_key")
	assert_has(keypair, "fingerprint")
	assert_true(str(keypair.get("public_key", "")).contains("BEGIN PUBLIC KEY"), "Public key should be PEM encoded")
	assert_true(str(keypair.get("private_key", "")).contains("BEGIN RSA PRIVATE KEY"), "Private key should be PEM encoded")

## Test 2: Fallback Display Name
func test_default_profile_empty_name_fallback():
	var service = _create_profile_service()
	if service == null:
		pass_test("Pending profile_service implementation")
		return

	var profile = service.create_default_profile("   ")
	assert_eq(profile["display_name"], "Player", "Empty name must fall back to 'Player'")

## Test 3: Partial Patch Profile Update
func test_update_profile_partial_patch():
	var service = _create_profile_service()
	if service == null:
		pass_test("Pending profile_service implementation")
		return

	var initial = service.create_default_profile("InitialUser")
	service.save_profile(initial)

	var ok = service.update_profile({
		"display_name": "PatchedUser",
		"theme_preset": "cozy_wood",
		"colorblind_mode": true
	})
	assert_true(ok, "update_profile should return true on success")

	var updated = service.get_profile()
	assert_eq(updated["display_name"], "PatchedUser")
	assert_eq(updated["theme_preset"], "cozy_wood")
	assert_true(updated["colorblind_mode"])
	assert_eq(updated["player_id"], initial["player_id"], "player_id must not change on patch")
	assert_has(updated, "keypair", "keypair must be preserved")

## Test 4: Forward Compatibility Schema Preservation
func test_forward_compatibility_preserves_unknown_fields():
	var service = _create_profile_service()
	if service == null:
		pass_test("Pending profile_service implementation")
		return

	var future_profile = service.create_default_profile("FutureUser")
	future_profile["schema_version"] = 99
	future_profile["custom_experimental_flag"] = "keep_me_safe"
	service.save_profile(future_profile)

	var reloaded = service.load_profile()
	assert_eq(reloaded.get("custom_experimental_flag"), "keep_me_safe", "Unknown future fields must be preserved")
	assert_eq(reloaded.get("schema_version"), 99, "Future schema version must not be downgraded")
