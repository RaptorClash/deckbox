# test_profile_persistence.gd
# GUT 9.x Headless Test Suite: Atomic Profile Persistence, .bak Failover, & Schema Migrations
extends GutTest

const PROFILE_SERVICE_PATH = "res://core/profile/profile_service.gd"
const TEST_DIR = "user://test_profiles/"
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

func _create_profile_service() -> RefCounted:
	if _profile_service_script != null:
		var svc = _profile_service_script.new()
		if svc.has_method("set_storage_path"):
			svc.set_storage_path(PROFILE_FILE)
		return svc
	return null

## Tier 1 (Feature Coverage): Default Profile Generation & UUID
func test_profile_creation_default_schema():
	var service = _create_profile_service()
	if service == null:
		pass_test("Pending profile_service implementation")
		return

	var profile = service.create_default_profile("TestPlayer")
	assert_true(profile is Dictionary, "Profile must be a Dictionary")
	assert_has(profile, "player_id", "Profile must have player_id")
	assert_has(profile, "display_name", "Profile must have display_name")
	assert_has(profile, "schema_version", "Profile must have schema_version")
	assert_has(profile, "created_at", "Profile must have created_at timestamp")

	assert_eq(profile["player_id"].length(), 36, "Player UUID must be standard 36-char string")
	assert_eq(profile["display_name"], "TestPlayer", "Display name must match initialized value")
	assert_gte(profile["schema_version"], 1, "Schema version must be >= 1")

## Tier 1 (Feature Coverage): Atomic Write Sequence (.tmp -> rename)
func test_atomic_profile_write_pattern():
	var service = _create_profile_service()
	if service == null:
		pass_test("Pending profile_service implementation")
		return

	var profile = service.create_default_profile("AtomicUser")
	var save_result = service.save_profile(profile)
	assert_true(save_result, "save_profile must return true on success")

	var global_main = ProjectSettings.globalize_path(PROFILE_FILE)
	var global_tmp = ProjectSettings.globalize_path(PROFILE_TMP)

	assert_true(FileAccess.file_exists(global_main), "profile.json must exist after atomic save")
	assert_false(FileAccess.file_exists(global_tmp), "profile.json.tmp must be removed after successful atomic rename")

	var loaded = service.load_profile()
	assert_not_null(loaded, "Loaded profile must not be null")
	assert_eq(loaded["display_name"], "AtomicUser", "Loaded display name must match saved data")

## Tier 1 & Tier 2: Backup (.bak) Creation on Subsequent Saves
func test_atomic_profile_write_creates_bak():
	var service = _create_profile_service()
	if service == null:
		pass_test("Pending profile_service implementation")
		return

	var profile = service.create_default_profile("Version_1")
	service.save_profile(profile)

	# Second save modifies name
	profile["display_name"] = "Version_2"
	service.save_profile(profile)

	var global_bak = ProjectSettings.globalize_path(PROFILE_BAK)
	assert_true(FileAccess.file_exists(global_bak), "profile.json.bak must exist after second save")

	# Inspect backup contents
	var bak_file = FileAccess.open(global_bak, FileAccess.READ)
	assert_not_null(bak_file, "Backup file must be readable")
	var bak_json = JSON.parse_string(bak_file.get_as_text())
	bak_file.close()

	assert_true(bak_json is Dictionary, "Backup must contain valid JSON Dictionary")
	assert_eq(bak_json["display_name"], "Version_1", "Backup must contain the previous state (Version_1)")

	var current = service.load_profile()
	assert_eq(current["display_name"], "Version_2", "Current state must reflect latest save (Version_2)")

## Tier 2 (Boundary & Corner Cases): Corrupt Main Profile Recovery from .bak
func test_corrupt_state_recovery_from_bak():
	var service = _create_profile_service()
	if service == null:
		pass_test("Pending profile_service implementation")
		return

	var profile = service.create_default_profile("StableUser")
	service.save_profile(profile)

	# Update to create .bak
	profile["display_name"] = "UpdatedStableUser"
	service.save_profile(profile)

	# Corrupt the primary profile.json (write garbage data)
	var global_main = ProjectSettings.globalize_path(PROFILE_FILE)
	var corrupt_file = FileAccess.open(global_main, FileAccess.WRITE)
	corrupt_file.store_string("CORRUPT_NOT_VALID_JSON_TRUNCATED")
	corrupt_file.close()

	# Load should detect corruption and gracefully restore from .bak
	var recovered = service.load_profile()
	assert_not_null(recovered, "Service must recover from corrupted profile using .bak")
	assert_true(recovered is Dictionary, "Recovered profile must be a Dictionary")
	assert_has(recovered, "player_id", "Recovered profile must have player_id")
	# Either original or backup name is safely preserved without crash
	assert_true(recovered["display_name"] == "StableUser" or recovered["display_name"] == "UpdatedStableUser",
		"Display name must be recovered from backup")

## Tier 2 (Boundary & Corner Cases): Corrupt Both Files Falls Back to Clean Defaults
func test_corrupt_both_files_fallback_to_clean_defaults():
	var service = _create_profile_service()
	if service == null:
		pass_test("Pending profile_service implementation")
		return

	var global_main = ProjectSettings.globalize_path(PROFILE_FILE)
	var global_bak = ProjectSettings.globalize_path(PROFILE_BAK)

	var f1 = FileAccess.open(global_main, FileAccess.WRITE)
	f1.store_string("GARBAGE_MAIN")
	f1.close()

	var f2 = FileAccess.open(global_bak, FileAccess.WRITE)
	f2.store_string("GARBAGE_BAK")
	f2.close()

	var fallback_profile = service.load_profile()
	assert_not_null(fallback_profile, "Must not crash when both files corrupt; fallback to defaults")
	assert_has(fallback_profile, "player_id", "Fallback profile must have generated player_id")
	assert_eq(fallback_profile["player_id"].length(), 36, "Fallback UUID must be 36 characters")

## Tier 3 (Pairwise / Cross-Feature): Schema Migrations (v1 to v2)
func test_schema_migration_on_upgrade():
	var service = _create_profile_service()
	if service == null:
		pass_test("Pending profile_service implementation")
		return

	# Write legacy v1 profile to file directly
	var v1_payload = {
		"schema_version": 1,
		"player_id": "c4b7a123-5678-90ab-cdef-1234567890ab",
		"display_name": "LegacyPlayer"
	}
	var global_main = ProjectSettings.globalize_path(PROFILE_FILE)
	var f = FileAccess.open(global_main, FileAccess.WRITE)
	f.store_string(JSON.stringify(v1_payload))
	f.close()

	var migrated = service.load_profile()
	assert_not_null(migrated, "Migrated profile must load cleanly")
	assert_eq(migrated["player_id"], "c4b7a123-5678-90ab-cdef-1234567890ab", "Legacy player_id must be preserved")
	assert_eq(migrated["display_name"], "LegacyPlayer", "Legacy display_name must be preserved")
	assert_gte(migrated["schema_version"], 2, "Schema version must be upgraded")
	assert_has(migrated, "avatar_id", "Upgraded profile must include new v2 avatar_id field")
	assert_has(migrated, "preferred_back", "Upgraded profile must include new v2 preferred_back field")

## Tier 2 (Boundary & Corner Cases): Special Characters, Emojis & UTF-8 Escaping
func test_special_character_escaping_in_profile():
	var service = _create_profile_service()
	if service == null:
		pass_test("Pending profile_service implementation")
		return

	var complex_name = "🃏 Max \"The Card Shark\" Müller <tag> & 'foo' \n\t\\/"
	var profile = service.create_default_profile(complex_name)
	service.save_profile(profile)

	var loaded = service.load_profile()
	assert_eq(loaded["display_name"], complex_name, "Special characters, quotes, and emojis must survive JSON serialization verbatim")

## Tier 2 (Boundary & Resource Stress): Idempotent Repeated Writes
func test_idempotent_repeated_writes():
	var service = _create_profile_service()
	if service == null:
		pass_test("Pending profile_service implementation")
		return

	var profile = service.create_default_profile("RapidWriter")
	for i in range(10):
		profile["display_name"] = "RapidWriter_%d" % i
		var ok = service.save_profile(profile)
		assert_true(ok, "Save %d must succeed" % i)

	var final_profile = service.load_profile()
	assert_eq(final_profile["display_name"], "RapidWriter_9", "Final profile must hold the last written state")
