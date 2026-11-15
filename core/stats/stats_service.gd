# core/stats/stats_service.gd
# Tracks player statistics, win/loss streaks, head-to-head opponent records, and match history.
class_name StatsService extends RefCounted

const CURRENT_SCHEMA_VERSION: int = 1
const DEFAULT_STORAGE_PATH: String = "user://database/stats.json"
const MAX_MATCH_HISTORY: int = 500

var _storage_path: String = DEFAULT_STORAGE_PATH
var _data: Dictionary = {}

func _init() -> void:
	_init_default_data()

func set_storage_path(path: String) -> void:
	_storage_path = path

func get_storage_path() -> String:
	return _storage_path

func _init_default_data() -> void:
	_data = {
		"schema_version": CURRENT_SCHEMA_VERSION,
		"updated_at": int(Time.get_unix_time_from_system()),
		"summary": {
			"total_matches": 0,
			"total_wins": 0,
			"total_losses": 0,
			"total_draws": 0,
			"win_rate": 0.0,
			"current_streak": 0,
			"current_win_streak": 0,
			"best_win_streak": 0,
			"total_play_time_seconds": 0,
			"average_match_duration": 0.0
		},
		"games": {},
		"opponents": {},
		"match_history": []
	}

func record_match_result(match_data: Dictionary) -> void:
	if match_data.is_empty():
		return

	if _data.is_empty() or not _data.has("summary"):
		_init_default_data()

	var summary = _data["summary"]
	var game_id = str(match_data.get("game_id", "uno"))
	var my_id = str(match_data.get("my_player_id", ""))
	var winner_id = str(match_data.get("winner_id", ""))
	var duration = maxi(0, int(match_data.get("duration_seconds", 0)))

	# Determine outcome
	var outcome: String = ""
	if match_data.has("result"):
		outcome = str(match_data["result"]).to_lower()
	elif not winner_id.is_empty() and not my_id.is_empty():
		outcome = "win" if winner_id == my_id else "loss"
	else:
		outcome = "loss"

	# Aggregate match counters
	summary["total_matches"] += 1
	summary["total_play_time_seconds"] += duration
	summary["average_match_duration"] = float(summary["total_play_time_seconds"]) / float(summary["total_matches"])

	if outcome == "win":
		summary["total_wins"] += 1
		summary["current_win_streak"] += 1
		summary["current_streak"] = maxi(0, summary["current_streak"]) + 1
		if summary["current_win_streak"] > summary["best_win_streak"]:
			summary["best_win_streak"] = summary["current_win_streak"]
	elif outcome == "draw":
		summary["total_draws"] += 1
		summary["current_win_streak"] = 0
		summary["current_streak"] = 0
	else:
		summary["total_losses"] += 1
		summary["current_win_streak"] = 0
		summary["current_streak"] = mini(0, summary["current_streak"]) - 1

	if summary["total_matches"] > 0:
		summary["win_rate"] = (float(summary["total_wins"]) / float(summary["total_matches"])) * 100.0

	# Game-specific tracking
	if not _data["games"].has(game_id):
		_data["games"][game_id] = {
			"total_matches": 0,
			"wins": 0,
			"losses": 0,
			"draws": 0,
			"win_rate": 0.0,
			"total_play_time_seconds": 0
		}
	var game_stats = _data["games"][game_id]
	game_stats["total_matches"] += 1
	game_stats["total_play_time_seconds"] += duration
	if outcome == "win":
		game_stats["wins"] += 1
	elif outcome == "draw":
		game_stats["draws"] += 1
	else:
		game_stats["losses"] += 1
	if game_stats["total_matches"] > 0:
		game_stats["win_rate"] = (float(game_stats["wins"]) / float(game_stats["total_matches"])) * 100.0

	# Opponent head-to-head tracking
	var opponents = match_data.get("opponents", [])
	if opponents is Array:
		for opp in opponents:
			var opp_id = str(opp)
			if opp_id.is_empty() or opp_id == my_id:
				continue
			if not _data["opponents"].has(opp_id):
				_data["opponents"][opp_id] = {
					"opponent_uuid": opp_id,
					"matches_against": 0,
					"wins_against": 0,
					"losses_against": 0,
					"win_rate": 0.0,
					"last_played_timestamp": int(Time.get_unix_time_from_system())
				}
			var opp_entry = _data["opponents"][opp_id]
			opp_entry["matches_against"] += 1
			if outcome == "win":
				opp_entry["wins_against"] += 1
			elif outcome == "loss":
				opp_entry["losses_against"] += 1
			if opp_entry["matches_against"] > 0:
				opp_entry["win_rate"] = (float(opp_entry["wins_against"]) / float(opp_entry["matches_against"])) * 100.0
			opp_entry["last_played_timestamp"] = int(Time.get_unix_time_from_system())

	# Match History entry
	var history_entry = {
		"match_id": match_data.get("match_id", str(Time.get_unix_time_from_system())),
		"game_id": game_id,
		"result": outcome,
		"timestamp": int(Time.get_unix_time_from_system()),
		"duration_seconds": duration,
		"winner_id": winner_id
	}
	var history: Array = _data.get("match_history", [])
	history.push_front(history_entry)
	if history.size() > MAX_MATCH_HISTORY:
		history.resize(MAX_MATCH_HISTORY)
	_data["match_history"] = history

	_data["updated_at"] = int(Time.get_unix_time_from_system())
	save_stats()

func get_summary_stats() -> Dictionary:
	if _data.is_empty() or not _data.has("summary"):
		load_stats()
	return _data.get("summary", {}).duplicate(true)

func get_opponent_history(friend_uuid: String) -> Dictionary:
	if _data.is_empty() or not _data.has("opponents"):
		load_stats()
	var opps: Dictionary = _data.get("opponents", {})
	if opps.has(friend_uuid):
		return opps[friend_uuid].duplicate(true)
	return {
		"opponent_uuid": friend_uuid,
		"matches_against": 0,
		"wins_against": 0,
		"losses_against": 0,
		"win_rate": 0.0,
		"last_played_timestamp": 0
	}

func get_recent_matches(limit: int = 20) -> Array[Dictionary]:
	if _data.is_empty() or not _data.has("match_history"):
		load_stats()
	var history: Array = _data.get("match_history", [])
	var count = mini(limit, history.size())
	var slice: Array[Dictionary] = []
	for i in range(count):
		slice.append(history[i])
	return slice

func save_stats() -> bool:
	var global_path = ProjectSettings.globalize_path(_storage_path)
	var dir_path = global_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir_path)

	var tmp_path = global_path + ".tmp"
	var bak_path = global_path + ".bak"

	var file = FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("StatsService: Cannot open tmp file for writing: %s" % tmp_path)
		return false

	file.store_string(JSON.stringify(_data, "\t"))
	file.flush()
	file.close()

	if FileAccess.file_exists(global_path):
		DirAccess.copy_absolute(global_path, bak_path)

	var err = DirAccess.rename_absolute(tmp_path, global_path)
	if err != OK:
		DirAccess.remove_absolute(global_path)
		err = DirAccess.rename_absolute(tmp_path, global_path)

	return err == OK

func load_stats() -> bool:
	var global_path = ProjectSettings.globalize_path(_storage_path)
	var bak_path = global_path + ".bak"

	var loaded = _read_json_file(global_path)
	if loaded != null and loaded is Dictionary and loaded.has("summary"):
		_data = loaded
		return true

	if FileAccess.file_exists(bak_path):
		var bak_loaded = _read_json_file(bak_path)
		if bak_loaded != null and bak_loaded is Dictionary and bak_loaded.has("summary"):
			push_warning("StatsService: Restored stats from .bak fallback.")
			_data = bak_loaded
			save_stats()
			return true

	_init_default_data()
	return false

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
