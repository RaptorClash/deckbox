# test_scenes_instantiation.gd
# GUT 9.x Unit Test Suite: Verifies loading and instantiation of Milestone 5 scenes
extends GutTest

const ARCADE_SCENE = "res://scenes/tables/arcade_ps5.tscn"
const COZY_SCENE = "res://scenes/tables/cozy_wood.tscn"
const CLEAN_SCENE = "res://scenes/tables/clean_25d.tscn"
const PROFILE_SCENE = "res://scenes/main_hub/profile.tscn"
const STATS_SCENE = "res://scenes/main_hub/stats.tscn"

func test_arcade_table_scene_instantiation():
	assert_true(ResourceLoader.exists(ARCADE_SCENE), "arcade_ps5.tscn must exist")
	var scene = load(ARCADE_SCENE)
	assert_not_null(scene, "arcade_ps5.tscn must load")
	var instance = scene.instantiate()
	add_child_autofree(instance)
	assert_not_null(instance)
	assert_eq(instance.theme_id, "arcade_ps5")
	assert_not_null(instance.draw_pile_anchor)
	assert_not_null(instance.discard_pile_anchor)
	assert_not_null(instance.seats_container)
	assert_eq(instance.seats_container.get_child_count(), 4, "Must have 4 seat markers")

	# Test quality preset scaling
	instance.apply_quality_preset("low")
	instance.apply_quality_preset("high")

func test_cozy_table_scene_instantiation():
	assert_true(ResourceLoader.exists(COZY_SCENE), "cozy_wood.tscn must exist")
	var scene = load(COZY_SCENE)
	assert_not_null(scene, "cozy_wood.tscn must load")
	var instance = scene.instantiate()
	add_child_autofree(instance)
	assert_not_null(instance)
	assert_eq(instance.theme_id, "cozy_wood")
	assert_not_null(instance.draw_pile_anchor)
	assert_eq(instance.seats_container.get_child_count(), 4)

func test_clean_table_scene_instantiation():
	assert_true(ResourceLoader.exists(CLEAN_SCENE), "clean_25d.tscn must exist")
	var scene = load(CLEAN_SCENE)
	assert_not_null(scene, "clean_25d.tscn must load")
	var instance = scene.instantiate()
	add_child_autofree(instance)
	assert_not_null(instance)
	assert_eq(instance.theme_id, "clean_25d")
	assert_not_null(instance.draw_pile_anchor)
	assert_eq(instance.seats_container.get_child_count(), 4)

func test_profile_hub_scene_instantiation():
	assert_true(ResourceLoader.exists(PROFILE_SCENE), "profile.tscn must exist")
	var scene = load(PROFILE_SCENE)
	assert_not_null(scene, "profile.tscn must load")
	var instance = scene.instantiate()
	add_child_autofree(instance)
	assert_not_null(instance)
	assert_not_null(instance.name_input)
	assert_not_null(instance.theme_picker)

func test_stats_hub_scene_instantiation():
	assert_true(ResourceLoader.exists(STATS_SCENE), "stats.tscn must exist")
	var scene = load(STATS_SCENE)
	assert_not_null(scene, "stats.tscn must load")
	var instance = scene.instantiate()
	add_child_autofree(instance)
	assert_not_null(instance)
	assert_not_null(instance.matches_val)
	assert_not_null(instance.winrate_val)
