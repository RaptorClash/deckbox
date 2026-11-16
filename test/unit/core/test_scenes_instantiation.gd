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

func test_main_menu_scene_instantiation():
	var main_menu_path = "res://scenes/main_hub/main_menu.tscn"
	assert_true(ResourceLoader.exists(main_menu_path), "main_menu.tscn must exist")
	var scene = load(main_menu_path)
	assert_not_null(scene, "main_menu.tscn must load")
	var instance = scene.instantiate()
	add_child_autofree(instance)
	assert_not_null(instance)

	# Verify hub tabs and embedded screens
	for tab_id in ["play", "friends", "pack_editor", "profile", "stats", "updater"]:
		assert_true(instance.select_tab(tab_id), "Should switch to tab: %s" % tab_id)

	# Verify LAN Host & QR Code generation
	var host_res = instance.start_lan_host(0, 0)
	assert_true(host_res.get("success", false), "LAN host should start cleanly on ephemeral ports")
	assert_true(instance.is_hosting_lan(), "Hosting flag should be active")
	assert_not_null(instance.qr_texture_rect.texture, "QR texture must be generated")
	assert_false(str(host_res.get("room_code", "")).is_empty(), "Room code must not be empty")
	instance.stop_lan_host()
	assert_false(instance.is_hosting_lan(), "Hosting should stop cleanly")

	# Verify launching an UNO match from the hub
	var launched = instance.start_uno_match({
		"mode": "solo",
		"theme": "cozy_wood",
		"quality": "medium",
		"rules": { "stacking_draw_two": true }
	})
	assert_true(launched, "Should launch UNO match view from main menu")

func test_uno_main_standalone_scene_instantiation():
	var uno_main_path = "res://games/uno/ui/uno_main.tscn"
	assert_true(ResourceLoader.exists(uno_main_path), "uno_main.tscn must exist for standalone uno target")
	var scene = load(uno_main_path)
	assert_not_null(scene, "uno_main.tscn must load")
	var instance = scene.instantiate()
	add_child_autofree(instance)
	assert_not_null(instance)
	assert_true(instance.has_method("launch_match"), "UnoMain must expose launch_match()")

func test_uno_game_scene_3d_table_and_wild_color_choice():
	var uno_game_path = "res://games/uno/ui/uno_game.tscn"
	assert_true(ResourceLoader.exists(uno_game_path), "uno_game.tscn must exist")
	var scene = load(uno_game_path)
	assert_not_null(scene, "uno_game.tscn must load")
	var instance = scene.instantiate()
	add_child_autofree(instance)
	assert_not_null(instance)

	# 1. Verify 3D table SubViewport, 3D card stacks, 3D direction ring & opponent 3D fans
	assert_not_null(instance.table_viewport, "3D SubViewport must be wired")
	assert_not_null(instance.active_table_3d, "Default 3D table scene must be mounted")
	assert_eq(instance.active_table_3d.theme_id, "arcade_ps5")
	assert_not_null(instance.direction_ring_3d, "3D turn direction ring must be mounted on table")
	assert_not_null(instance.opponent_hands_3d_root, "3D opponent hands root must be mounted on table")
	assert_gt(instance.opponent_hands_3d_root.get_child_count(), 0, "3D opponent card fans must be spawned for seats")

	instance.set_table_theme("cozy_wood")
	assert_eq(instance.active_table_3d.theme_id, "cozy_wood")
	instance.set_table_theme("clean_25d")
	assert_eq(instance.active_table_3d.theme_id, "clean_25d")
	instance.set_quality_preset("low")

	# 2. Verify Wild card opens color choice instead of hardcoding 'red'
	var wild_card = { "id": "test_wild_blue", "uid": "test_wild_blue", "color": "wild", "value": "wild" }
	instance.cartridge.debug_set_state({
		"top_discard": { "id": "top_g5", "color": "green", "value": "5" },
		"active_color": "",
		"current_turn_seat": 0
	})
	instance.cartridge.player_hands["p0"] = [wild_card]
	instance.current_player_id = "p0"
	instance.refresh_display()

	instance._on_card_pressed("test_wild_blue", wild_card)
	assert_eq(instance.pending_wild_card_id, "test_wild_blue", "Wild play must pause for color selection")
	instance.select_wild_color("blue")
	assert_eq(instance.cartridge.active_color, "blue", "Selected wild color 'blue' must apply instead of hardcoded 'red'")

	# 3. Verify Pass-and-Play privacy curtain toggles cleanly
	instance.configure_match({
		"mode": "pass_and_play",
		"player_count": 2,
		"theme": "arcade_ps5"
	})
	assert_true(instance.pass_and_play_ctrl.is_curtain_active(), "Pass-and-play curtain must start down")
	assert_true(instance.curtain_overlay.visible, "Curtain overlay must be visible initially")
	instance.reveal_pass_and_play()
	assert_false(instance.pass_and_play_ctrl.is_curtain_active(), "Curtain must lift after reveal")
	assert_false(instance.curtain_overlay.visible, "Curtain overlay must hide after reveal")
