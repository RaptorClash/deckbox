# core/profile/backup_service.gd
# Exports and imports .deckbox-backup.zip packages with SHA-256 verification and conflict resolution.
class_name BackupService extends RefCounted

const BACKUP_FORMAT_VERSION: int = 1
const APP_NAME: String = "DeckBox"
const APP_VERSION: String = "0.1.0"

const ProfileServiceScript = preload("res://core/profile/profile_service.gd")
const StatsServiceScript = preload("res://core/stats/stats_service.gd")

enum ConflictStrategy {
	OVERWRITE,
	MERGE_PRESERVE,
	MERGE_OVERWRITE
}

func export_backup(target_path: String) -> Dictionary:
	var global_target = ProjectSettings.globalize_path(target_path)
	var dir_path = global_target.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir_path)

	var files_to_bundle: Dictionary = {}

	# 1. Gather profile.json
	var profile_bytes = _read_file_bytes("user://database/profile.json")
	if profile_bytes.is_empty():
		# Fallback to default profile if file not yet on disk
		var default_prof = ProfileServiceScript.new().create_default_profile("Player")
		profile_bytes = JSON.stringify(default_prof, "\t").to_utf8_buffer()
	files_to_bundle["profile.json"] = profile_bytes

	# 2. Gather stats.json
	var stats_bytes = _read_file_bytes("user://database/stats.json")
	if stats_bytes.is_empty():
		var stats_svc = StatsServiceScript.new()
		stats_bytes = JSON.stringify(stats_svc._data, "\t").to_utf8_buffer()
	files_to_bundle["stats.json"] = stats_bytes

	# 3. Gather friends.json if present
	var friends_bytes = _read_file_bytes("user://database/friends.json")
	if not friends_bytes.is_empty():
		files_to_bundle["friends.json"] = friends_bytes

	# 4. Compute SHA-256 checksums
	var checksums: Dictionary = {}
	var file_list: Array[String] = []
	for fname in files_to_bundle:
		file_list.append(fname)
		checksums[fname] = _sha256(files_to_bundle[fname]).hex_encode()

	# 5. Build manifest.json
	var profile_json = JSON.parse_string(profile_bytes.get_string_from_utf8())
	var profile_uuid = profile_json.get("player_id", "") if profile_json is Dictionary else ""
	var display_name = profile_json.get("display_name", "") if profile_json is Dictionary else ""

	var manifest = {
		"app_name": APP_NAME,
		"app_version": APP_VERSION,
		"format_version": BACKUP_FORMAT_VERSION,
		"created_at": int(Time.get_unix_time_from_system()),
		"profile_uuid": profile_uuid,
		"display_name": display_name,
		"included_files": file_list,
		"checksums": checksums
	}

	# 6. Stream into ZIP using ZIPPacker
	var packer = ZIPPacker.new()
	var err = packer.open(global_target, ZIPPacker.APPEND_CREATE)
	if err != OK:
		return {"success": false, "error": "Cannot open ZIPPacker: %d" % err}

	# Write manifest.json first
	var manifest_bytes = JSON.stringify(manifest, "\t").to_utf8_buffer()
	packer.start_file("manifest.json")
	packer.write_file(manifest_bytes)
	packer.close_file()

	# Write payload files
	for fname in files_to_bundle:
		packer.start_file(fname)
		packer.write_file(files_to_bundle[fname])
		packer.close_file()

	packer.close()

	var archive_hash = FileAccess.get_sha256(global_target)
	return {
		"success": true,
		"path": global_target,
		"sha256": archive_hash,
		"files_count": files_to_bundle.size() + 1
	}

func import_backup(source_path: String, strategy: Variant = "MERGE_PRESERVE") -> Dictionary:
	var global_source = ProjectSettings.globalize_path(source_path)
	if not FileAccess.file_exists(global_source):
		return {"success": false, "error": "Backup file not found: %s" % global_source}

	var reader = ZIPReader.new()
	var err = reader.open(global_source)
	if err != OK:
		return {"success": false, "error": "Invalid or corrupt backup ZIP (err: %d)" % err}

	var files = reader.get_files()
	if not "manifest.json" in files:
		reader.close()
		return {"success": false, "error": "Missing manifest.json in backup archive"}

	# Read & validate manifest
	var manifest_bytes = reader.read_file("manifest.json")
	var manifest = JSON.parse_string(manifest_bytes.get_string_from_utf8())
	if manifest == null or not manifest is Dictionary:
		reader.close()
		return {"success": false, "error": "Corrupt or unparseable manifest.json"}

	var checksums = manifest.get("checksums", {})

	# Adversarial verification: path traversal and SHA-256 checksums
	for fname in files:
		if fname == "manifest.json":
			continue
		# Path traversal defense
		if not _is_safe_relative_path(fname):
			reader.close()
			return {"success": false, "error": "Security alert: Malicious path traversal rejected: %s" % fname}

		# SHA-256 checksum integrity verification
		if checksums.has(fname):
			var expected_hash = checksums[fname]
			var file_data = reader.read_file(fname)
			var actual_hash = _sha256(file_data).hex_encode()
			if expected_hash != actual_hash:
				reader.close()
				return {"success": false, "error": "SHA-256 checksum mismatch for %s (corrupted or tampered)" % fname}

	# Conflict resolution
	var strat_str = str(strategy).to_upper()
	var restored_files: Array[String] = []

	var db_dir = ProjectSettings.globalize_path("user://database/")
	DirAccess.make_dir_recursive_absolute(db_dir)

	if strat_str == "OVERWRITE":
		# Backup existing to rollback directory
		var rollback_dir = ProjectSettings.globalize_path("user://database_rollback/")
		DirAccess.make_dir_recursive_absolute(rollback_dir)
		for fname in ["profile.json", "stats.json", "friends.json"]:
			var curr = db_dir.path_join(fname)
			if FileAccess.file_exists(curr):
				DirAccess.copy_absolute(curr, rollback_dir.path_join(fname))

		# Overwrite
		for fname in files:
			if fname == "manifest.json":
				continue
			var out_path = db_dir.path_join(fname)
			var data = reader.read_file(fname)
			var f = FileAccess.open(out_path, FileAccess.WRITE)
			if f != null:
				f.store_buffer(data)
				f.close()
				restored_files.append(fname)

	elif strat_str == "MERGE_PRESERVE":
		# Preserve local profile and max streaks, add missing fields/opponents
		for fname in files:
			if fname == "manifest.json":
				continue
			var out_path = db_dir.path_join(fname)
			var backup_data = reader.read_file(fname)
			if not FileAccess.file_exists(out_path):
				var f = FileAccess.open(out_path, FileAccess.WRITE)
				if f != null:
					f.store_buffer(backup_data)
					f.close()
					restored_files.append(fname)
			else:
				# Merge stats or friends if file exists
				if fname == "stats.json":
					_merge_stats(out_path, backup_data, false)
					restored_files.append(fname)
				elif fname == "friends.json":
					_merge_friends(out_path, backup_data, false)
					restored_files.append(fname)

	else: # MERGE_OVERWRITE
		for fname in files:
			if fname == "manifest.json":
				continue
			var out_path = db_dir.path_join(fname)
			var backup_data = reader.read_file(fname)
			if not FileAccess.file_exists(out_path):
				var f = FileAccess.open(out_path, FileAccess.WRITE)
				if f != null:
					f.store_buffer(backup_data)
					f.close()
					restored_files.append(fname)
			else:
				if fname == "stats.json":
					_merge_stats(out_path, backup_data, true)
				elif fname == "friends.json":
					_merge_friends(out_path, backup_data, true)
				elif fname == "profile.json":
					var f = FileAccess.open(out_path, FileAccess.WRITE)
					if f != null:
						f.store_buffer(backup_data)
						f.close()
				restored_files.append(fname)

	reader.close()
	return {
		"success": true,
		"strategy": strat_str,
		"restored_files": restored_files
	}

func _merge_stats(local_file_path: String, backup_bytes: PackedByteArray, overwrite_summary: bool) -> void:
	var local_text = FileAccess.get_file_as_string(local_file_path)
	var local_json = JSON.parse_string(local_text)
	var backup_json = JSON.parse_string(backup_bytes.get_string_from_utf8())
	if not (local_json is Dictionary and backup_json is Dictionary):
		return

	var loc_sum = local_json.get("summary", {})
	var bkp_sum = backup_json.get("summary", {})

	if not overwrite_summary:
		loc_sum["total_matches"] = loc_sum.get("total_matches", 0) + bkp_sum.get("total_matches", 0)
		loc_sum["total_wins"] = loc_sum.get("total_wins", 0) + bkp_sum.get("total_wins", 0)
		loc_sum["total_losses"] = loc_sum.get("total_losses", 0) + bkp_sum.get("total_losses", 0)
		loc_sum["best_win_streak"] = maxi(loc_sum.get("best_win_streak", 0), bkp_sum.get("best_win_streak", 0))
		if loc_sum["total_matches"] > 0:
			loc_sum["win_rate"] = (float(loc_sum["total_wins"]) / float(loc_sum["total_matches"])) * 100.0
	else:
		local_json["summary"] = bkp_sum

	var loc_opps = local_json.get("opponents", {})
	var bkp_opps = backup_json.get("opponents", {})
	for opp_id in bkp_opps:
		if not loc_opps.has(opp_id) or overwrite_summary:
			loc_opps[opp_id] = bkp_opps[opp_id]

	var f = FileAccess.open(local_file_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(local_json, "\t"))
		f.close()

func _merge_friends(local_file_path: String, backup_bytes: PackedByteArray, overwrite_existing: bool) -> void:
	var local_text = FileAccess.get_file_as_string(local_file_path)
	var local_json = JSON.parse_string(local_text)
	var backup_json = JSON.parse_string(backup_bytes.get_string_from_utf8())
	if not (local_json is Dictionary and backup_json is Dictionary):
		return

	var loc_friends = local_json.get("friends", {})
	var bkp_friends = backup_json.get("friends", {})
	for f_id in bkp_friends:
		if not loc_friends.has(f_id) or overwrite_existing:
			loc_friends[f_id] = bkp_friends[f_id]

	var f = FileAccess.open(local_file_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(local_json, "\t"))
		f.close()

func _is_safe_relative_path(path: String) -> bool:
	if path.is_empty():
		return false
	if path.contains("\\"):
		return false
	if path.begins_with("/") or path.contains("://") or path.contains(":"):
		return false
	var segments = path.split("/")
	for seg in segments:
		if seg == ".." or seg == "." or seg.contains("\u0000"):
			return false
	return true

func _read_file_bytes(res_path: String) -> PackedByteArray:
	var global_path = ProjectSettings.globalize_path(res_path)
	if not FileAccess.file_exists(global_path):
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(global_path)

func _sha256(data: PackedByteArray) -> PackedByteArray:
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	return ctx.finish()
