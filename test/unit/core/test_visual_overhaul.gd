# test_visual_overhaul.gd
# GUT 9.x Headless Test Suite: UI Theme, Animator, Radial Color Wheel, Sound Engine & View Modes
extends GutTest

const UI_THEME_PATH = "res://core/visuals/deckbox_ui_theme.gd"
const ANIMATOR_PATH = "res://core/visuals/card_flight_animator.gd"
const COLOR_WHEEL_PATH = "res://games/uno/ui/radial_color_wheel.gd"
const SOUND_PLAYER_PATH = "res://core/audio/sound_effects_player.gd"
const UNO_GAME_PATH = "res://games/uno/ui/uno_game.tscn"
const MAIN_MENU_PATH = "res://scenes/main_hub/main_menu.tscn"

func test_deckbox_ui_theme_creation() -> void:
	var theme_script = load(UI_THEME_PATH)
	assert_not_null(theme_script, "DeckBoxUITheme script must exist")
	var theme: Theme = theme_script.create_theme()
	assert_not_null(theme, "create_theme() must return a valid Theme")
	assert_true(theme is Theme, "Result must be Theme")
	assert_true(theme.has_stylebox("panel", "PanelContainer"), "Theme must style PanelContainer")
	assert_true(theme.has_stylebox("normal", "Button"), "Theme must style Button normal")
	assert_true(theme.has_stylebox("hover", "Button"), "Theme must style Button hover")
	assert_true(theme.has_stylebox("normal", "LineEdit"), "Theme must style LineEdit")

func test_card_flight_animator_speed_modes() -> void:
	var anim_script = load(ANIMATOR_PATH)
	assert_not_null(anim_script, "CardFlightAnimator script must exist")
	var anim = anim_script.new()
	add_child_autofree(anim)

	anim.set_speed_mode("normal")
	assert_almost_eq(anim.get_flight_duration(), 0.28, 0.15, "Normal flight duration should be ~0.28s")
	anim.set_speed_mode("fast")
	assert_lt(anim.get_flight_duration(), 0.20, "Fast flight duration should be faster than normal")
	anim.set_speed_mode("instant")
	assert_eq(anim.get_flight_duration(), 0.0, "Instant mode must have 0.0s flight duration")

func test_radial_color_wheel_selection() -> void:
	var wheel_script = load(COLOR_WHEEL_PATH)
	assert_not_null(wheel_script, "RadialColorWheel script must exist")
	var wheel = wheel_script.new()
	add_child_autofree(wheel)

	watch_signals(wheel)
	wheel.open_wheel()
	assert_true(wheel.visible, "open_wheel() must show RadialColorWheel")
	wheel.choose_color("green")
	assert_signal_emitted_with_parameters(wheel, "color_selected", ["green"])
	assert_false(wheel.visible, "Choosing a color must close the wheel")

func test_sound_effects_player_generates_streams() -> void:
	var sfx_script = load(SOUND_PLAYER_PATH)
	assert_not_null(sfx_script, "SoundEffectsPlayer script must exist")
	var sfx = sfx_script.new()
	add_child_autofree(sfx)

	var expected_clips = ["card_swoosh", "card_snap", "draw_pop", "special_impact", "uno_fanfare", "table_knock", "ambient_lounge"]
	for clip_name in expected_clips:
		var stream = sfx.get_clip(clip_name)
		assert_not_null(stream, "Sound clip '%s' must be generated" % clip_name)
		assert_true(stream is AudioStreamWAV, "Sound clip '%s' must be AudioStreamWAV" % clip_name)
		assert_gt(stream.data.size(), 100, "Sound clip '%s' must have non-empty PCM samples" % clip_name)

	# Triggering playback must not crash even in headless dummy audio driver
	sfx.play_card_swoosh()
	sfx.play_card_snap()
	sfx.play_uno_fanfare()

func test_uno_game_view_modes_skins_and_n_player_scaling() -> void:
	var scene = load(UNO_GAME_PATH)
	assert_not_null(scene, "uno_game.tscn must load")
	var game = scene.instantiate()
	add_child_autofree(game)

	# View modes switching
	assert_true(game.has_method("set_view_mode"), "UnoGame must support set_view_mode()")
	game.set_view_mode("full_3d")
	assert_eq(game.active_view_mode, "full_3d")
	game.set_view_mode("hybrid_25d")
	assert_eq(game.active_view_mode, "hybrid_25d")
	assert_true(game.hand_fan_root.visible, "Hybrid mode must show 2.5D hand fan")
	game.set_view_mode("clean_25d")
	assert_eq(game.active_view_mode, "clean_25d")
	game.set_view_mode("table_role")
	assert_eq(game.active_view_mode, "table_role")
	assert_false(game.hand_fan_root.visible, "TV Table mode must hide private hand fan")

	# Card skin switching
	assert_true(game.has_method("set_card_skin"), "UnoGame must support set_card_skin()")
	game.set_card_skin("minimal_dark")
	assert_eq(game.active_card_skin, "minimal_dark")
	game.set_card_skin("classic_arcade")
	assert_eq(game.active_card_skin, "classic_arcade")

	# Invalid fallback
	game.set_view_mode("invalid_mode_xyz")
	assert_eq(game.active_view_mode, "full_3d", "Invalid view mode must fall back safely to full_3d")

	# N-player match with 10 players
	game.configure_match({
		"mode": "solo",
		"player_count": 10,
		"theme": "arcade_ps5",
		"view_mode": "hybrid_25d",
		"card_skin": "minimal_dark",
		"bot_speed": "instant"
	})
	assert_eq(game.cartridge.players.size(), 10, "Solo match must support 10 players (1 human + 9 bots)")
	assert_eq(game.opponent_badges_root.get_child_count(), 9, "Must render 9 floating opponent badges")
	assert_eq(game.opponent_hands_3d_root.get_child_count(), 9, "Must render 9 3D opponent card fans around the table")

func test_main_menu_supports_large_player_counts_and_fullscreen_3d_lounge() -> void:
	var scene = load(MAIN_MENU_PATH)
	assert_not_null(scene, "main_menu.tscn must load")
	var menu = scene.instantiate()
	add_child_autofree(menu)

	assert_gte(menu.player_count_spin.max_value, 24.0, "Lobby player count SpinBox must allow large groups (>= 24)")
	assert_not_null(menu.preview_viewport, "Fullscreen live 3D background viewport must exist")
	assert_not_null(menu.active_preview_table_3d, "Live 3D background table must be mounted in hub")

func test_uno_game_3d_card_click_plays_card_and_flip_renders_opposite_sides() -> void:
	var scene = load(UNO_GAME_PATH)
	var game = scene.instantiate()
	add_child_autofree(game)

	assert_eq(game.mouse_filter, Control.MOUSE_FILTER_PASS, "UnoGame root must use MOUSE_FILTER_PASS so clicks reach 3D picking")

	game.configure_match({
		"mode": "solo",
		"player_count": 4,
		"theme": "arcade_ps5",
		"view_mode": "full_3d",
		"bot_speed": "normal",
		"rules": { "expansion_flip": true }
	})

	game.cartridge.debug_set_state({
		"top_discard": { "id": "top_r5", "color": "red", "value": "5", "light_color": "red", "light_value": "5", "dark_color": "pink", "dark_value": "5" },
		"active_color": "",
		"active_side": "light",
		"current_turn_seat": 0
	})
	game.cartridge.player_hands["p0"] = [
		{ "id": "p0_play", "uid": "p0_play", "color": "red", "value": "7", "light_color": "red", "light_value": "7", "dark_color": "pink", "dark_value": "7" },
		{ "id": "p0_keep", "uid": "p0_keep", "color": "blue", "value": "9", "light_color": "blue", "light_value": "9", "dark_color": "teal", "dark_value": "9" }
	]
	game.refresh_display()

	# Verify Flip! mode renders opposite Flip face on 3D draw pile (not classic back)
	var tex_gen = load("res://core/visuals/card_texture_generator.gd")
	var classic_back = tex_gen.get_card_back_texture(game.active_card_skin)
	var draw_top_node = game.draw_pile_3d_root.get_child(0)
	var draw_mesh = _find_mesh_in_node(draw_top_node)
	assert_not_null(draw_mesh, "Draw pile 3D card mesh must exist")
	assert_ne(draw_mesh.get_surface_override_material(0).albedo_texture, classic_back, "In Flip! mode, 3D draw pile must show opposite Flip side instead of classic card back")

	# Verify 3D hand card click via projected screen coordinates plays the card!
	var cam: Camera3D = game.active_table_3d.get_camera()
	var card_node: Node3D = game._player_3d_cards[0]["node"]
	var vp_pos: Vector2 = cam.unproject_position(card_node.global_position)
	var vp_rect = game.size if (game.size.x > 10.0 and game.size.y > 10.0) else game.get_viewport_rect().size
	if vp_rect.x <= 0.0 or vp_rect.y <= 0.0:
		vp_rect = Vector2(float(game.table_viewport.size.x), float(game.table_viewport.size.y))
	var screen_pos = Vector2(
		(vp_pos.x / float(game.table_viewport.size.x)) * vp_rect.x,
		(vp_pos.y / float(game.table_viewport.size.y)) * vp_rect.y
	)
	var motion = InputEventMouseMotion.new()
	motion.position = screen_pos
	game._handle_3d_pointer_event(motion)
	assert_eq(game._hovered_3d_index, 0, "Hovering projected 3D card position must select card 0")

	var click = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = screen_pos
	game._gui_input(click)
	assert_eq(game.cartridge.get_player_card_count("p0"), 1, "Clicking playable 3D card via _gui_input must play it and leave 1 card")
	assert_eq(game.cartridge.current_turn_seat, 1, "Turn must advance to seat 1 after playing 3D card")

func test_main_menu_two_step_game_selector_and_settings_tab() -> void:
	var scene = load(MAIN_MENU_PATH)
	var menu = scene.instantiate()
	add_child_autofree(menu)

	assert_false(menu.is_game_selected(), "Main menu must start in game selector gallery, not straight in match setup")
	assert_true(menu.game_selector_view.visible, "Game selector view must be visible at startup")
	assert_false(menu.match_setup_view.visible, "Match setup view must be hidden until user selects a game")

	assert_true(menu.select_game("uno"), "Selecting 'uno' (Alle Ablegen!) must succeed")
	assert_true(menu.is_game_selected())
	assert_false(menu.game_selector_view.visible)
	assert_true(menu.match_setup_view.visible)

	menu.show_game_selector()
	assert_false(menu.is_game_selected())
	assert_true(menu.game_selector_view.visible)

	assert_true(menu.select_tab("settings"), "Settings tab must exist and be selectable")
	assert_not_null(menu.turn_url_edit, "Settings tab must expose TURN server URL input")
	menu.turn_url_edit.text = "turn:relay.example.org:3478"
	menu.turn_user_edit.text = "user1"
	menu.turn_pass_edit.text = "pass1"
	menu.save_settings()
	var ice = menu._webrtc.get_ice_servers()
	var has_custom = false
	for entry in ice:
		if entry is Dictionary and "turn:relay.example.org:3478" in entry.get("urls", []):
			has_custom = true
	assert_true(has_custom, "Saving settings must apply custom TURN server to WebRtcManager")

	# Verify Language selector & live UI translation switching
	assert_not_null(menu.language_option, "Settings tab must expose Language selection OptionButton")
	assert_gte(menu.language_option.item_count, 13, "Language selector must include all 13 supported languages")
	menu.set_language("en")
	var en_play_text = menu.play_tab_btn.text
	menu.set_language("de")
	var de_play_text = menu.play_tab_btn.text
	assert_ne(en_play_text, de_play_text, "Switching language between English and German must update UI text live")
	menu.set_language("fr")
	assert_ne(menu.play_tab_btn.text, de_play_text, "Switching language to French must update UI text live")

func test_dimmed_cards_flip_obsidian_unlimited_seats_and_lobby_roster() -> void:
	# 1. CardTextureGenerator: unplayable 3D card dimming + Dark Side obsidian fill
	var tex_gen = load("res://core/visuals/card_texture_generator.gd")
	var dark_tex: ImageTexture = tex_gen.get_card_front_texture({ "color": "pink", "value": "5" }, "classic_arcade", true)
	var dark_img: Image = dark_tex.get_image()
	var body_px: Color = dark_img.get_pixel(24, 136)
	assert_lt(body_px.get_luminance(), 0.20, "Dark Side card body must be pitch-black obsidian so it is distinct from Light front cards")

	var card_inst = load("res://assets/3d/card_rounded.glb").instantiate()
	add_child_autofree(card_inst)
	tex_gen.apply_card_materials_to_mesh(card_inst, { "color": "red", "value": "7" }, "classic_arcade", true, true)
	tex_gen.set_card_mesh_playable_state(card_inst, false)
	var mesh_inst = _find_mesh_in_node(card_inst)
	var dim_mat: StandardMaterial3D = mesh_inst.get_surface_override_material(0)
	assert_lt(dim_mat.albedo_color.a, 0.99, "Unplayable 3D cards must be translucent/dimmed")
	tex_gen.set_card_mesh_playable_state(card_inst, true)
	var lit_mat: StandardMaterial3D = mesh_inst.get_surface_override_material(0)
	assert_almost_eq(lit_mat.albedo_color.a, 1.0, 0.01, "Playable 3D cards must restore full opacity")

	# 2. VersionHandshake unlimited max_players = 0 allocates seats >= 0
	var handshake = load("res://core/network/version_handshake.gd").new()
	handshake.configure_host({ "app_version": "0.1.0", "protocol_version": 1, "max_players": 0, "room_code": "1234" })
	var join_r1 = handshake.evaluate_join_request({
		"v": 1, "type": "JOIN_REQUEST", "seq": 1, "sender": "phone_a",
		"payload": { "app_version": "0.1.0", "protocol_version": 1, "role": "player" }
	})
	assert_eq(join_r1["payload"]["status"], "ACCEPTED", "Unlimited LAN room (max_players=0) must accept player joins")
	assert_gte(int(join_r1["payload"]["seat_index"]), 0, "Unlimited LAN must assign valid seat_index >= 0")

	# 3. MainMenu: scalable GridContainer, external mod help, named humans + bots + diff, lobby roster role management
	var menu = load(MAIN_MENU_PATH).instantiate()
	add_child_autofree(menu)
	assert_true(menu.games_grid is GridContainer, "GamesGrid must be a scalable GridContainer")
	assert_not_null(menu.human_count_spin, "MainMenu must expose human_count_spin")
	assert_not_null(menu.bot_count_spin, "MainMenu must expose bot_count_spin")
	assert_not_null(menu.bot_difficulty_option, "MainMenu must expose bot_difficulty_option")
	assert_gte(menu.bot_difficulty_option.item_count, 3, "Bot difficulty must offer easy, normal, hard")
	menu.set_human_player_names(["Alice", "Bob"])
	assert_eq(int(menu.human_count_spin.value), 2, "Setting 2 human names must sync human_count_spin")
	assert_false(menu.get_external_module_help_text().is_empty(), "External module & online play help text must exist")
	menu.register_lobby_client(42, "Handy Max", "player", 0)
	assert_true(menu.set_lobby_client_role(42, "table"), "Host must be able to reassign a connected client to table role")
	assert_eq(menu._connected_lobby_clients[42]["role"], "table")

func test_locations_jukebox_keybinds_timed_reactions_and_compact_gallery() -> void:
	# 1. LocationEnvironmentBuilder & TableTheme integration
	var loc_builder = load("res://core/visuals/location_environment_builder.gd")
	assert_not_null(loc_builder, "LocationEnvironmentBuilder script must exist")
	var locs: Array = loc_builder.get_available_locations()
	for lid in ["cozy_house", "forest_glade", "neon_club", "bowling_alley", "rustic_pub"]:
		assert_has(locs, lid, "Location '%s' must be supported" % lid)

	var table_inst = load("res://scenes/tables/cozy_wood.tscn").instantiate()
	add_child_autofree(table_inst)
	table_inst.apply_location_environment("forest_glade")
	assert_eq(table_inst.active_location_id, "forest_glade", "TableTheme must track active_location_id")
	assert_not_null(table_inst.get_node_or_null("LocationBackdrop3D"), "Applying location must spawn 3D environment backdrop around table")

	# 2. JukeboxService relaxed procedural tracks + auto/shuffle modes
	var jukebox_script = load("res://core/audio/jukebox_service.gd")
	assert_not_null(jukebox_script, "JukeboxService script must exist")
	var jukebox = jukebox_script.new()
	var tracks: Array = jukebox_script.get_available_tracks()
	for tid in ["cozy_house", "forest_glade", "neon_club", "bowling_alley", "rustic_pub"]:
		assert_has(tracks, tid, "Jukebox track for '%s' must exist" % tid)
	assert_eq(jukebox.resolve_track_for_mode("auto", "bowling_alley"), "bowling_alley", "Auto mode must match active location")
	var stream: AudioStreamWAV = jukebox.get_track_stream("cozy_house")
	assert_not_null(stream, "Jukebox must synthesize AudioStreamWAV for cozy_house")
	assert_gt(stream.data.size(), 1000, "Synthesized music stream must contain PCM audio frames")

	# 3. KeybindService defaults, remapping & reset
	var kb_script = load("res://core/input/keybind_service.gd")
	assert_not_null(kb_script, "KeybindService script must exist")
	var kb = kb_script.new()
	for act_id in ["nav_left", "nav_right", "play_card", "draw_card", "call_uno", "reaction_action", "sort_hand", "shuffle_hand", "cycle_view", "jukebox_next"]:
		assert_gt(kb.get_keybind(act_id), 0, "Default keybind must be set for %s" % act_id)
	kb.set_keybind("play_card", KEY_K)
	assert_eq(kb.get_keybind("play_card"), KEY_K, "Keybind must update when remapped")
	kb.reset_to_defaults()
	assert_eq(kb.get_keybind("play_card"), KEY_SPACE, "Resetting keybinds must restore default KEY_SPACE")

	# 4. MainMenuHub compact tiles, base_cartridge filtered out, PlayToEndCheck, Location/Jukebox/Keybinds UI
	var menu = load(MAIN_MENU_PATH).instantiate()
	add_child_autofree(menu)
	assert_null(menu.games_grid.get_node_or_null("DynCard_base_cartridge"), "base_cartridge must be filtered out of game gallery")
	assert_eq(menu.alle_ablegen_card.size_flags_horizontal, Control.SIZE_SHRINK_BEGIN, "Game tiles must stay compact (SIZE_SHRINK_BEGIN)")
	assert_not_null(menu.play_to_end_check, "Match setup must expose PlayToEndCheck")
	assert_not_null(menu.location_option, "Settings tab must expose LocationOption")
	assert_not_null(menu.jukebox_option, "Settings tab must expose JukeboxOption")
	assert_not_null(menu.keybinds_box, "Settings tab must expose KeybindsBox")

	# 5. UnoGame timed center reaction window & auto-expiration
	var game_scene = load("res://games/uno/ui/uno_game.tscn").instantiate()
	add_child_autofree(game_scene)
	game_scene.configure_match({
		"players": [
			{ "player_id": "p0", "name": "Player", "seat": 0, "is_bot": false },
			{ "player_id": "p1", "name": "Bot 1", "seat": 1, "is_bot": true }
		]
	})
	game_scene.cartridge.debug_set_state({
		"top_discard": { "id": "top", "color": "red", "value": "3" },
		"active_seat": 0,
		"player_hands": {
			"p0": [{ "id": "p0_r5", "uid": "p0_r5", "color": "red", "value": "5" }, { "id": "p0_b2", "uid": "p0_b2", "color": "blue", "value": "2" }],
			"p1": [{ "id": "p1_r8", "uid": "p1_r8", "color": "red", "value": "8" }]
		}
	})
	game_scene.cartridge.player_map["p1"]["called_uno"] = false
	game_scene.refresh_display()
	assert_true(game_scene.center_reaction_panel.visible, "Catchable LETZTE! opportunity must pop up CenterReactionPanel")
	assert_gt(game_scene._reaction_time_left, 0.5, "Reaction countdown timer must start positive")
	game_scene._tick_reaction_timer(5.0)
	assert_false(game_scene.center_reaction_panel.visible, "CenterReactionPanel must auto-hide once countdown expires")

func _find_mesh_in_node(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var m = _find_mesh_in_node(c)
		if m != null:
			return m
	return null
