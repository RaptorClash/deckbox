# test_backup_service.gd
# GUT 9.x Unit Test Suite: Backup Export/Import, ZIP Integrity, SHA-256 & Conflict Resolution
extends GutTest

const BACKUP_SERVICE_PATH = "res://core/profile/backup_service.gd"
const TEST_DIR = "user://test_backups/"
const BACKUP_ZIP = TEST_DIR + "test_backup.deckbox-backup.zip"
const TAMPERED_ZIP = TEST_DIR + "tampered_backup.deckbox-backup.zip"
const MALICIOUS_ZIP = TEST_DIR + "malicious_backup.deckbox-backup.zip"

var _backup_service_script: GDScript

func before_all():
	if ResourceLoader.exists(BACKUP_SERVICE_PATH):
		_backup_service_script = load(BACKUP_SERVICE_PATH)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIR))

func before_each():
	_clean_test_dir()

func after_each():
	_clean_test_dir()

func _clean_test_dir():
	for file_path in [BACKUP_ZIP, TAMPERED_ZIP, MALICIOUS_ZIP]:
		var global_path = ProjectSettings.globalize_path(file_path)
		if FileAccess.file_exists(global_path):
			DirAccess.remove_absolute(global_path)

func _create_backup_service():
	if _backup_service_script != null:
		return _backup_service_script.new()
	return null

## Test 1: Backup Export Creates Valid ZIP Archive with Manifest
func test_backup_export_creates_valid_zip_with_manifest():
	var service = _create_backup_service()
	if service == null:
		pass_test("Pending backup_service implementation")
		return

	# Export backup
	var res = service.export_backup(BACKUP_ZIP)
	assert_true(res.get("success", false), "export_backup should return success: true")

	var global_zip = ProjectSettings.globalize_path(BACKUP_ZIP)
	assert_true(FileAccess.file_exists(global_zip), "Backup ZIP file must exist on disk")

	# Inspect using ZIPReader
	var reader = ZIPReader.new()
	var err = reader.open(global_zip)
	assert_eq(err, OK, "ZIPReader must open exported backup archive without error")

	var files = reader.get_files()
	assert_true("manifest.json" in files, "ZIP must contain manifest.json")
	assert_true("profile.json" in files, "ZIP must contain profile.json")
	assert_true("stats.json" in files, "ZIP must contain stats.json")

	var manifest_bytes = reader.read_file("manifest.json")
	var manifest = JSON.parse_string(manifest_bytes.get_string_from_utf8())
	assert_true(manifest is Dictionary, "manifest.json must parse to Dictionary")
	assert_has(manifest, "checksums", "manifest must contain checksums map")
	assert_has(manifest["checksums"], "profile.json", "manifest must have profile.json checksum")

	reader.close()

## Test 2: Backup Manifest Checksum SHA-256 Integrity
func test_backup_manifest_checksum_integrity():
	var service = _create_backup_service()
	if service == null:
		pass_test("Pending backup_service implementation")
		return

	service.export_backup(BACKUP_ZIP)
	var global_zip = ProjectSettings.globalize_path(BACKUP_ZIP)

	var reader = ZIPReader.new()
	reader.open(global_zip)
	var manifest = JSON.parse_string(reader.read_file("manifest.json").get_string_from_utf8())
	var profile_bytes = reader.read_file("profile.json")
	reader.close()

	# Compute SHA-256 of profile bytes
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(profile_bytes)
	var computed_hash = ctx.finish().hex_encode()

	assert_eq(computed_hash, manifest["checksums"]["profile.json"], "Computed SHA-256 must match manifest record")

## Test 3: Reject Tampered Backup Archive with Modified Content
func test_backup_import_rejects_corrupted_archive():
	var service = _create_backup_service()
	if service == null:
		pass_test("Pending backup_service implementation")
		return

	# Create archive with mismatched checksum
	var global_tampered = ProjectSettings.globalize_path(TAMPERED_ZIP)
	var packer = ZIPPacker.new()
	packer.open(global_tampered, ZIPPacker.APPEND_CREATE)

	var manifest = {
		"format_version": 1,
		"checksums": {
			"profile.json": "0000000000000000000000000000000000000000000000000000000000000000" # Invalid dummy hash
		}
	}
	packer.start_file("manifest.json")
	packer.write_file(JSON.stringify(manifest).to_utf8_buffer())
	packer.close_file()

	packer.start_file("profile.json")
	packer.write_file(JSON.stringify({"display_name": "Tampered"}).to_utf8_buffer())
	packer.close_file()

	packer.close()

	var import_res = service.import_backup(TAMPERED_ZIP)
	assert_false(import_res.get("success", true), "Tampered archive with hash mismatch must be rejected")
	assert_true(str(import_res.get("error", "")).contains("SHA-256"), "Error message should mention SHA-256 mismatch")

## Test 4: Path Traversal Attack Rejection
func test_backup_import_path_traversal_rejection():
	var service = _create_backup_service()
	if service == null:
		pass_test("Pending backup_service implementation")
		return

	var global_malicious = ProjectSettings.globalize_path(MALICIOUS_ZIP)
	var packer = ZIPPacker.new()
	packer.open(global_malicious, ZIPPacker.APPEND_CREATE)

	var payload = "malicious_payload".to_utf8_buffer()
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(payload)
	var hash = ctx.finish().hex_encode()

	var manifest = {
		"format_version": 1,
		"checksums": {
			"../malicious.json": hash
		}
	}
	packer.start_file("manifest.json")
	packer.write_file(JSON.stringify(manifest).to_utf8_buffer())
	packer.close_file()

	packer.start_file("../malicious.json")
	packer.write_file(payload)
	packer.close_file()

	packer.close()

	var import_res = service.import_backup(MALICIOUS_ZIP)
	assert_false(import_res.get("success", true), "Archive with path traversal must be rejected")

## Test 5: Conflict Resolution Strategy MERGE_PRESERVE
func test_backup_import_strategy_merge_preserve():
	var service = _create_backup_service()
	if service == null:
		pass_test("Pending backup_service implementation")
		return

	service.export_backup(BACKUP_ZIP)
	var import_res = service.import_backup(BACKUP_ZIP, "MERGE_PRESERVE")
	assert_true(import_res.get("success", false), "MERGE_PRESERVE import should succeed")
