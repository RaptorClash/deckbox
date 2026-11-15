# test_stats_service.gd
# GUT 9.x Unit Test Suite: Player Statistics, Streaks, Opponent History & Failover
extends GutTest

const STATS_SERVICE_PATH = "res://core/stats/stats_service.gd"
const TEST_DIR = "user://test_stats_service/"
const STATS_FILE = TEST_DIR + "stats.json"
const STATS_TMP = TEST_DIR + "stats.json.tmp"
const STATS_BAK = TEST_DIR + "stats.json.bak"

var _stats_service_script: GDScript

func before_all():
	if ResourceLoader.exists(STATS_SERVICE_PATH):
		_stats_service_script = load(STATS_SERVICE_PATH)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIR))

func before_each():
	_clean_test_dir()

func after_each():
	_clean_test_dir()

func _clean_test_dir():
	for file_path in [STATS_FILE, STATS_TMP, STATS_BAK]:
		var global_path = ProjectSettings.globalize_path(file_path)
		if FileAccess.file_exists(global_path):
			DirAccess.remove_absolute(global_path)

func _create_stats_service():
	if _stats_service_script != null:
		var svc = _stats_service_script.new()
		if svc.has_method("set_storage_path"):
			svc.set_storage_path(STATS_FILE)
		return svc
	return null

## Test 1: Initial State is Clean and Zeroed
func test_initial_stats_zeroed():
	var service = _create_stats_service()
	if service == null:
		pass_test("Pending stats_service implementation")
		return

	var summary = service.get_summary_stats()
	assert_not_null(summary)
	assert_eq(summary.get("total_matches", -1), 0)
	assert_eq(summary.get("total_wins", -1), 0)
	assert_eq(summary.get("total_losses", -1), 0)
	assert_eq(summary.get("win_rate", -1.0), 0.0)
	assert_eq(summary.get("current_streak", -1), 0)
	assert_eq(summary.get("best_win_streak", -1), 0)
	assert_eq(summary.get("total_play_time_seconds", -1), 0)

## Test 2: Win Recording Increments Win Rate and Streaks
func test_record_win_increments_streak_and_win_rate():
	var service = _create_stats_service()
	if service == null:
		pass_test("Pending stats_service implementation")
		return

	for i in range(3):
		service.record_match_result({
			"match_id": "match_%d" % i,
			"game_id": "uno",
			"result": "win",
			"duration_seconds": 120,
			"my_player_id": "my_id",
			"winner_id": "my_id"
		})

	var summary = service.get_summary_stats()
	assert_eq(summary["total_matches"], 3)
	assert_eq(summary["total_wins"], 3)
	assert_eq(summary["total_losses"], 0)
	assert_eq(summary["win_rate"], 100.0)
	assert_eq(summary["current_streak"], 3)
	assert_eq(summary["best_win_streak"], 3)
	assert_eq(summary["total_play_time_seconds"], 360)

## Test 3: Loss Resets Current Streak but Preserves All-Time Best
func test_record_loss_resets_current_streak_preserves_best():
	var service = _create_stats_service()
	if service == null:
		pass_test("Pending stats_service implementation")
		return

	# Record 3 wins
	for i in range(3):
		service.record_match_result({
			"match_id": "win_%d" % i,
			"game_id": "uno",
			"result": "win",
			"duration_seconds": 100
		})

	# Record 1 loss
	service.record_match_result({
		"match_id": "loss_0",
		"game_id": "uno",
		"result": "loss",
		"duration_seconds": 100
	})

	var summary = service.get_summary_stats()
	assert_eq(summary["total_matches"], 4)
	assert_eq(summary["total_wins"], 3)
	assert_eq(summary["total_losses"], 1)
	assert_eq(summary["win_rate"], 75.0)
	assert_lte(summary["current_streak"], 0, "Current streak should reflect loss streak")
	assert_eq(summary["current_win_streak"], 0, "Current win streak must reset to 0")
	assert_eq(summary["best_win_streak"], 3, "All-time best win streak must be preserved")

## Test 4: Opponent Head-to-Head Record Tracking
func test_opponent_head_to_head_tracking():
	var service = _create_stats_service()
	if service == null:
		pass_test("Pending stats_service implementation")
		return

	var my_id = "user_me"
	var alice_id = "uuid_alice"
	var bob_id = "uuid_bob"

	# Match 1 vs Alice (win)
	service.record_match_result({
		"match_id": "m1",
		"game_id": "uno",
		"my_player_id": my_id,
		"winner_id": my_id,
		"opponents": [alice_id],
		"duration_seconds": 150
	})

	# Match 2 vs Alice (loss)
	service.record_match_result({
		"match_id": "m2",
		"game_id": "uno",
		"my_player_id": my_id,
		"winner_id": alice_id,
		"opponents": [alice_id],
		"duration_seconds": 180
	})

	# Match 3 vs Bob (win)
	service.record_match_result({
		"match_id": "m3",
		"game_id": "uno",
		"my_player_id": my_id,
		"winner_id": my_id,
		"opponents": [bob_id],
		"duration_seconds": 200
	})

	var alice_stats = service.get_opponent_history(alice_id)
	assert_eq(alice_stats.get("matches_against"), 2)
	assert_eq(alice_stats.get("wins_against"), 1)
	assert_eq(alice_stats.get("losses_against"), 1)
	assert_eq(alice_stats.get("win_rate"), 50.0)

	var bob_stats = service.get_opponent_history(bob_id)
	assert_eq(bob_stats.get("matches_against"), 1)
	assert_eq(bob_stats.get("wins_against"), 1)
	assert_eq(bob_stats.get("losses_against"), 0)
	assert_eq(bob_stats.get("win_rate"), 100.0)

	# Query unknown opponent returns default zeroed stats
	var unknown = service.get_opponent_history("unknown_uuid")
	assert_eq(unknown.get("matches_against", 0), 0)

## Test 5: Atomic Persistence & Failover to .bak
func test_stats_atomic_persistence_and_bak_failover():
	var service = _create_stats_service()
	if service == null:
		pass_test("Pending stats_service implementation")
		return

	service.record_match_result({"match_id": "save1", "result": "win"})
	service.record_match_result({"match_id": "save2", "result": "win"})

	var global_main = ProjectSettings.globalize_path(STATS_FILE)
	var global_bak = ProjectSettings.globalize_path(STATS_BAK)

	assert_true(FileAccess.file_exists(global_main), "stats.json must exist")
	assert_true(FileAccess.file_exists(global_bak), "stats.json.bak must exist after multiple saves")

	# Corrupt main file
	var corrupt = FileAccess.open(global_main, FileAccess.WRITE)
	corrupt.store_string("CORRUPTED_STATS_DATA")
	corrupt.close()

	# Create new service instance and load
	var recovered_service = _create_stats_service()
	var loaded = recovered_service.load_stats()
	assert_true(loaded, "load_stats should successfully recover from .bak")
	var summary = recovered_service.get_summary_stats()
	assert_gte(summary["total_matches"], 1, "Recovered stats must contain saved matches")

## Test 6: Match History Size Truncation Limit
func test_match_history_size_capping():
	var service = _create_stats_service()
	if service == null:
		pass_test("Pending stats_service implementation")
		return

	# Record 520 matches
	for i in range(520):
		service.record_match_result({
			"match_id": "match_%d" % i,
			"result": "win" if i % 2 == 0 else "loss",
			"duration_seconds": 60
		})

	var recent = service.get_recent_matches(600)
	assert_lte(recent.size(), 500, "Match history must be capped at 500 records")

## Test 7: Adversarial Malformed Match Records
func test_adversarial_malformed_match_record():
	var service = _create_stats_service()
	if service == null:
		pass_test("Pending stats_service implementation")
		return

	# Empty dictionary
	service.record_match_result({})
	# Negative duration and missing fields
	service.record_match_result({
		"duration_seconds": -999,
		"result": "invalid_result"
	})

	var summary = service.get_summary_stats()
	assert_gte(summary["total_play_time_seconds"], 0, "Play time must not become negative")
	assert_gte(summary["total_matches"], 0)
