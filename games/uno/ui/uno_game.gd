# uno_game.gd
# Full-Screen 3D/Hybrid/2.5D Interactive UNO Table Controller with N-Player Scaling,
# Procedural Card Skins, 3D Raycasting, Parabolic Card Flight & Sound Engine.
extends Control

signal back_requested
signal match_state_changed(pub_state: Dictionary)

const UnoCartridgeScript = preload("res://games/uno/uno_cartridge.gd")
const UnoRulesScript = preload("res://games/uno/uno_rules.gd")
const PassAndPlayScript = preload("res://core/qol/pass_and_play.gd")
const AccessibilitySymbolsScript = preload("res://core/qol/accessibility_symbols.gd")
const StatsServiceScript = preload("res://core/stats/stats_service.gd")
const CardTextureGenScript = preload("res://core/visuals/card_texture_generator.gd")
const UIThemeScript = preload("res://core/visuals/deckbox_ui_theme.gd")
const CardFlightAnimatorScript = preload("res://core/visuals/card_flight_animator.gd")
const SoundEffectsPlayerScript = preload("res://core/audio/sound_effects_player.gd")
const QRCodeScript = preload("res://core/network/qr_code.gd")
const I18nServiceScript = preload("res://core/i18n/i18n_service.gd")
const KeybindServiceScript = preload("res://core/input/keybind_service.gd")
const ProfileServiceScript = preload("res://core/profile/profile_service.gd")
const CardMeshScene = preload("res://assets/3d/card_rounded.glb")

const REACTION_WINDOW_SEC: float = 4.0

const TABLE_SCENES: Dictionary = {
	"arcade_ps5": "res://scenes/tables/arcade_ps5.tscn",
	"cozy_wood": "res://scenes/tables/cozy_wood.tscn",
	"clean_25d": "res://scenes/tables/clean_25d.tscn"
}

const CARD_COLORS: Dictionary = {
	"red": Color(0.90, 0.16, 0.16),
	"blue": Color(0.12, 0.44, 0.94),
	"green": Color(0.14, 0.70, 0.30),
	"yellow": Color(0.94, 0.74, 0.08),
	"pink": Color(0.94, 0.18, 0.58),
	"teal": Color(0.08, 0.78, 0.76),
	"purple": Color(0.56, 0.20, 0.92),
	"orange": Color(0.98, 0.46, 0.08),
	"wild": Color(0.45, 0.25, 0.72)
}

const VALID_VIEW_MODES: Array[String] = ["full_3d", "hybrid_25d", "clean_25d", "table_role"]
const VIEW_MODE_LABELS: Dictionary = {
	"full_3d": "Full 3D",
	"hybrid_25d": "Hybrid 2.5D",
	"clean_25d": "Clean 2.5D",
	"table_role": "TV-Tisch"
}

var cartridge: RefCounted = null
var pass_and_play_ctrl: RefCounted = null
var stats_svc: RefCounted = null
var animator: Node = null
var sfx_player: Node = null

var current_player_id: String = "p0"
var match_mode: String = "solo"
var active_theme_id: String = "arcade_ps5"
var active_quality_preset: String = "high"
var active_view_mode: String = "full_3d"
var active_card_skin: String = "classic_arcade"
var active_bot_speed: String = "normal"
var active_bot_difficulty: String = "normal"
var active_location_id: String = "cozy_house"
var active_jukebox_mode: String = "auto"
var colorblind_mode: bool = true
var pending_wild_card_id: String = ""
var _local_human_ids: Array[String] = []
var _last_revealed_human_id: String = ""
var _keybind_svc: RefCounted = null
var _keyboard_selected_idx: int = -1
var _reaction_time_left: float = 0.0
var _reaction_signature: String = ""
var _expired_reaction_signatures: Dictionary = {}
var _pending_jump_in_card: Dictionary = {}
var _last_skipped_seat: int = -1
var _skip_banner_time_left: float = 0.0

var active_table_3d: Node3D = null
var direction_ring_3d: Node3D = null
var draw_pile_3d_root: Node3D = null
var discard_pile_3d_root: Node3D = null
var opponent_hands_3d_root: Node3D = null
var player_hand_3d_root: Node3D = null
var seat_turn_beacon_3d: OmniLight3D = null
var seat_turn_halo_3d: MeshInstance3D = null
var _ring_mesh_instance: MeshInstance3D = null
var _turn_direction: int = 1

# Interactive 3D hand picking state
var _player_3d_cards: Array[Dictionary] = []
var _hovered_3d_index: int = -1
var _hovered_draw_pile_3d: bool = false
var _last_handled_event: InputEvent = null

var _match_start_unix: int = 0
var _round_recorded: bool = false
var _last_options: Dictionary = {}
var _match_gen_id: int = 0
var _bot_sequence_running: bool = false
var _bot_turn_timer: Timer = null
var _rng_visual: RandomNumberGenerator = RandomNumberGenerator.new()

@onready var table_viewport: SubViewport = $TableViewportContainer/SubViewport
@onready var hud_layer: Control = $HudLayer
@onready var opponent_badges_root: Control = $HudLayer/OpponentsOverlay
@onready var hand_fan_root: Control = $HudLayer/HandFanRoot
@onready var hand_cards_layer: Control = $HudLayer/HandFanRoot/HandCardsLayer
@onready var turn_label: Label = $HudLayer/TopLeftBar/TurnPill/TurnLabel
@onready var color_dot: ColorRect = $HudLayer/TopLeftBar/StatusPill/StatusBox/ColorDot
@onready var active_color_label: Label = $HudLayer/TopLeftBar/StatusPill/StatusBox/ActiveColorLabel
@onready var penalty_label: Label = $HudLayer/TopLeftBar/StatusPill/StatusBox/PenaltyLabel
@onready var view_mode_quick_btn: Button = $HudLayer/TopRightControls/ViewModeQuickBtn
@onready var quick_drawer: PanelContainer = $HudLayer/QuickSettingsDrawer
@onready var view_mode_option: OptionButton = $HudLayer/QuickSettingsDrawer/DrawerBox/ViewModeRow/ViewModeOption
@onready var skin_option: OptionButton = $HudLayer/QuickSettingsDrawer/DrawerBox/SkinRow/SkinOption
@onready var theme_option: OptionButton = $HudLayer/QuickSettingsDrawer/DrawerBox/ThemeRow/ThemeOption
@onready var speed_option: OptionButton = $HudLayer/QuickSettingsDrawer/DrawerBox/SpeedRow/SpeedOption
@onready var quality_option: OptionButton = $HudLayer/QuickSettingsDrawer/DrawerBox/QualityRow/QualityOption
@onready var colorblind_btn: CheckButton = $HudLayer/QuickSettingsDrawer/DrawerBox/ColorblindBtn
@onready var bottom_right_actions: VBoxContainer = $HudLayer/BottomRightActions
@onready var catch_uno_btn: Button = $HudLayer/BottomRightActions/CatchUnoBtn
@onready var challenge_p4_btn: Button = $HudLayer/BottomRightActions/ChallengePlusFourBtn
@onready var uno_call_btn: Button = $HudLayer/BottomRightActions/CallUnoButton
@onready var draw_pile_btn: Button = $HudLayer/BottomRightActions/DrawPileBtn
@onready var sort_hand_btn: Button = $HudLayer/BottomRightActions/HandToolsRow/SortHandBtn
@onready var shuffle_hand_btn: Button = $HudLayer/BottomRightActions/HandToolsRow/ShuffleHandBtn
@onready var table_qr_badge: PanelContainer = $HudLayer/TableQrBadge
@onready var table_qr_rect: TextureRect = $HudLayer/TableQrBadge/QrBox/QrRect
@onready var table_qr_pin: Label = $HudLayer/TableQrBadge/QrBox/QrPinLabel
@onready var skip_banner_panel: PanelContainer = $HudLayer/SkipBannerPanel
@onready var skip_banner_label: Label = $HudLayer/SkipBannerPanel/SkipBannerLabel
@onready var center_reaction_panel: PanelContainer = $HudLayer/CenterReactionPanel
@onready var reaction_title_label: Label = $HudLayer/CenterReactionPanel/ReactionBox/ReactionTitleLabel
@onready var reaction_timer_bar: ProgressBar = $HudLayer/CenterReactionPanel/ReactionBox/ReactionTimerBar
@onready var catch_uno_popup_btn: Button = $HudLayer/CenterReactionPanel/ReactionBox/CatchUnoPopupBtn
@onready var jump_in_popup_btn: Button = $HudLayer/CenterReactionPanel/ReactionBox/JumpInPopupBtn
@onready var challenge_p4_popup_btn: Button = $HudLayer/CenterReactionPanel/ReactionBox/ChallengeP4PopupBtn
@onready var emote_toast: PanelContainer = $HudLayer/EmoteToast
@onready var emote_banner: Label = $HudLayer/EmoteToast/EmoteBanner
@onready var color_wheel: Control = $RadialColorWheel
@onready var curtain_overlay: PanelContainer = $CurtainOverlay
@onready var curtain_title: Label = $CurtainOverlay/CurtainBox/CurtainTitle
@onready var round_over_overlay: PanelContainer = $RoundOverOverlay
@onready var winner_label: Label = $RoundOverOverlay/RoundBox/WinnerLabel
@onready var challenge_reveal_overlay: PanelContainer = $ChallengeRevealOverlay
@onready var challenge_result_title: Label = $ChallengeRevealOverlay/RevealBox/ChallengeResultTitle
@onready var challenge_result_subtitle: Label = $ChallengeRevealOverlay/RevealBox/ChallengeResultSubtitle
@onready var revealed_cards_row: HBoxContainer = $ChallengeRevealOverlay/RevealBox/RevealedCardsRow
@onready var close_challenge_btn: Button = $ChallengeRevealOverlay/RevealBox/CloseChallengeBtn

func _ready() -> void:
	_rng_visual.seed = 1337
	theme = UIThemeScript.create_theme()
	_apply_hud_accent_styles()

	pass_and_play_ctrl = PassAndPlayScript.new()
	stats_svc = StatsServiceScript.new()
	stats_svc.load_stats()

	animator = CardFlightAnimatorScript.new()
	add_child(animator)

	_keybind_svc = KeybindServiceScript.new()
	var prof_svc = ProfileServiceScript.new()
	var prof = prof_svc.load_profile()
	if prof is Dictionary:
		active_location_id = str(prof.get("location_id", active_location_id))
		active_jukebox_mode = str(prof.get("jukebox_mode", active_jukebox_mode))
		if prof.get("keybinds", null) is Dictionary:
			_keybind_svc.load_from_dict(prof["keybinds"])

	sfx_player = SoundEffectsPlayerScript.new()
	add_child(sfx_player)
	sfx_player.play_jukebox(active_jukebox_mode, active_location_id)

	_bot_turn_timer = Timer.new()
	_bot_turn_timer.one_shot = true
	_bot_turn_timer.timeout.connect(_on_bot_turn_timer_timeout)
	add_child(_bot_turn_timer)

	_init_drawer_controls()
	configure_match({ "mode": "solo", "theme": active_theme_id, "quality": active_quality_preset, "location_id": active_location_id, "jukebox_mode": active_jukebox_mode })
	apply_language()

func _set_rel_text(rel_path: String, key: String, params: Dictionary = {}) -> void:
	var n = get_node_or_null(rel_path)
	if n != null and "text" in n:
		n.text = I18nServiceScript.t(key, params)

func apply_language() -> void:
	_set_rel_text("HudLayer/TopLeftBar/BackButton", "hud.hub_btn")
	_set_rel_text("HudLayer/TopRightControls/SettingsToggleBtn", "hud.options_btn")
	_set_rel_text("HudLayer/QuickSettingsDrawer/DrawerBox/DrawerTitle", "hud.drawer_title")
	_set_rel_text("HudLayer/QuickSettingsDrawer/DrawerBox/ViewModeRow/Lbl", "settings.view_mode")
	_set_rel_text("HudLayer/QuickSettingsDrawer/DrawerBox/SkinRow/Lbl", "settings.card_skin")
	_set_rel_text("HudLayer/QuickSettingsDrawer/DrawerBox/ThemeRow/Lbl", "settings.table_theme")
	_set_rel_text("HudLayer/QuickSettingsDrawer/DrawerBox/SpeedRow/Lbl", "settings.bot_speed")
	_set_rel_text("HudLayer/QuickSettingsDrawer/DrawerBox/QualityRow/Lbl", "settings.quality")
	if uno_call_btn != null:
		uno_call_btn.text = I18nServiceScript.t("hud.call_last")
	if catch_uno_btn != null:
		catch_uno_btn.text = I18nServiceScript.t("hud.catch_uno_btn")
	if challenge_p4_btn != null:
		challenge_p4_btn.text = I18nServiceScript.t("hud.challenge_p4_btn")
	if sort_hand_btn != null:
		sort_hand_btn.text = I18nServiceScript.t("hud.sort_btn")
	if shuffle_hand_btn != null:
		shuffle_hand_btn.text = I18nServiceScript.t("hud.shuffle_btn")
	if close_challenge_btn != null:
		close_challenge_btn.text = I18nServiceScript.t("hud.challenge_close_btn")
	_set_rel_text("HudLayer/BottomRightActions/EmoteRow/EmoteTapBtn", "hud.knock_btn")
	_set_rel_text("HudLayer/BottomRightActions/EmoteRow/EmoteNiceBtn", "hud.nice_btn")
	_set_rel_text("CurtainOverlay/CurtainBox/CurtainHint", "hud.curtain_hint")
	_set_rel_text("CurtainOverlay/CurtainBox/RevealButton", "hud.curtain_reveal")
	_set_rel_text("RoundOverOverlay/RoundBox/Actions/PlayAgainBtn", "hud.play_again")
	_set_rel_text("RoundOverOverlay/RoundBox/Actions/BackHubBtn", "hud.back_hub")
	if view_mode_quick_btn != null:
		view_mode_quick_btn.text = I18nServiceScript.t("hud.view_prefix", {"mode": VIEW_MODE_LABELS.get(active_view_mode, "Full 3D")})
	if cartridge != null:
		refresh_display()

func _apply_hud_accent_styles() -> void:
	if uno_call_btn != null:
		uno_call_btn.add_theme_stylebox_override("normal", UIThemeScript.make_accent_button(Color(0.92, 0.30, 0.16, 0.96), Color(1.0, 0.85, 0.25, 0.95), 24))
		uno_call_btn.add_theme_stylebox_override("hover", UIThemeScript.make_accent_button(Color(1.0, 0.38, 0.20, 1.0), Color.WHITE, 24))
	if catch_uno_btn != null:
		catch_uno_btn.add_theme_stylebox_override("normal", UIThemeScript.make_accent_button(Color(0.86, 0.56, 0.10, 0.96), Color(1.0, 0.90, 0.35, 0.95), 14))
	if challenge_p4_btn != null:
		challenge_p4_btn.add_theme_stylebox_override("normal", UIThemeScript.make_accent_button(Color(0.68, 0.20, 0.86, 0.96), Color(1.0, 0.55, 0.95, 0.95), 14))
	if center_reaction_panel != null:
		center_reaction_panel.add_theme_stylebox_override("panel", UIThemeScript.make_glass_panel(Color(0.05, 0.07, 0.14, 0.92), Color(1.0, 0.78, 0.20, 0.95), 14, 14))
	if catch_uno_popup_btn != null:
		catch_uno_popup_btn.add_theme_stylebox_override("normal", UIThemeScript.make_accent_button(Color(0.88, 0.56, 0.10, 0.96), Color(1.0, 0.90, 0.35, 0.95), 12))
	if jump_in_popup_btn != null:
		jump_in_popup_btn.add_theme_stylebox_override("normal", UIThemeScript.make_accent_button(Color(0.14, 0.62, 0.92, 0.96), Color(0.55, 0.92, 1.0, 0.95), 12))
	if challenge_p4_popup_btn != null:
		challenge_p4_popup_btn.add_theme_stylebox_override("normal", UIThemeScript.make_accent_button(Color(0.68, 0.20, 0.86, 0.96), Color(1.0, 0.55, 0.95, 0.95), 12))
	if skip_banner_panel != null:
		skip_banner_panel.add_theme_stylebox_override("panel", UIThemeScript.make_glass_panel(Color(0.45, 0.10, 0.12, 0.92), Color(1.0, 0.45, 0.35, 0.95), 10, 12))
	if curtain_overlay != null:
		curtain_overlay.add_theme_stylebox_override("panel", UIThemeScript.make_glass_panel(Color(0.03, 0.04, 0.09, 0.96), UIThemeScript.COL_BORDER_GOLD, 0, 24))
	if round_over_overlay != null:
		round_over_overlay.add_theme_stylebox_override("panel", UIThemeScript.make_glass_panel(Color(0.04, 0.06, 0.12, 0.92), UIThemeScript.COL_BORDER_GOLD, 0, 24))
	if challenge_reveal_overlay != null:
		challenge_reveal_overlay.add_theme_stylebox_override("panel", UIThemeScript.make_glass_panel(Color(0.04, 0.06, 0.12, 0.94), Color(0.75, 0.35, 1.0, 0.85), 0, 24))

func _process(delta: float) -> void:
	if direction_ring_3d != null and is_instance_valid(direction_ring_3d):
		direction_ring_3d.rotate_y(-float(_turn_direction) * delta * 0.95)
	_animate_3d_player_hand_hover(delta)
	_tick_reaction_timer(delta)
	if _skip_banner_time_left > 0.0:
		_skip_banner_time_left = maxf(0.0, _skip_banner_time_left - delta)
		if _skip_banner_time_left <= 0.0 and skip_banner_panel != null:
			skip_banner_panel.visible = false
			_last_skipped_seat = -1

func _animate_3d_player_hand_hover(delta: float) -> void:
	if _player_3d_cards.is_empty():
		return
	var lerp_w = clampf(delta * 16.0, 0.0, 1.0)
	for i in range(_player_3d_cards.size()):
		var entry = _player_3d_cards[i]
		var node: Node3D = entry.get("node", null)
		if node == null or not is_instance_valid(node):
			continue
		var is_hov = (i == _hovered_3d_index)
		var is_play = bool(entry.get("playable", false))
		var base_pos: Vector3 = entry["base_pos"]
		var base_scale: Vector3 = entry["base_scale"]
		var lift_y = 0.045 if (is_hov and is_play) else (0.022 if is_hov else (0.012 if is_play else 0.0))
		var pop_z = 0.032 if (is_hov and is_play) else (0.016 if is_hov else 0.0)
		var x_part = 0.0
		if _hovered_3d_index >= 0 and not is_hov:
			var d_idx = i - _hovered_3d_index
			if absi(d_idx) <= 3:
				x_part = signf(float(d_idx)) * (0.028 / float(absi(d_idx)))
		var target_pos = base_pos + Vector3(x_part, lift_y, pop_z)
		var target_scale = base_scale * (1.12 if (is_hov and is_play) else (1.05 if is_hov else 1.0))
		node.position = node.position.lerp(target_pos, lerp_w)
		node.scale = node.scale.lerp(target_scale, lerp_w)

func _init_drawer_controls() -> void:
	if view_mode_option != null:
		view_mode_option.clear()
		view_mode_option.add_item("Full 3D (Immersive)", 0)
		view_mode_option.set_item_metadata(0, "full_3d")
		view_mode_option.add_item("Hybrid 3D + 2.5D Fächer", 1)
		view_mode_option.set_item_metadata(1, "hybrid_25d")
		view_mode_option.add_item("Clean 2.5D (Low-Spec)", 2)
		view_mode_option.set_item_metadata(2, "clean_25d")
		view_mode_option.add_item("TV-Tisch-Modus", 3)
		view_mode_option.set_item_metadata(3, "table_role")

	if skin_option != null:
		skin_option.clear()
		skin_option.add_item("Classic Arcade", 0)
		skin_option.set_item_metadata(0, "classic_arcade")
		skin_option.add_item("Minimal Dark", 1)
		skin_option.set_item_metadata(1, "minimal_dark")

	if theme_option != null:
		theme_option.clear()
		theme_option.add_item("Arcade PS5", 0)
		theme_option.set_item_metadata(0, "arcade_ps5")
		theme_option.add_item("Cozy Wood", 1)
		theme_option.set_item_metadata(1, "cozy_wood")
		theme_option.add_item("Clean 2.5D", 2)
		theme_option.set_item_metadata(2, "clean_25d")

	if speed_option != null:
		speed_option.clear()
		speed_option.add_item("Normal (0.7s)", 0)
		speed_option.set_item_metadata(0, "normal")
		speed_option.add_item("Schnell (0.25s)", 1)
		speed_option.set_item_metadata(1, "fast")
		speed_option.add_item("Sofort (0s)", 2)
		speed_option.set_item_metadata(2, "instant")

	if quality_option != null:
		quality_option.clear()
		quality_option.add_item("High", 0)
		quality_option.set_item_metadata(0, "high")
		quality_option.add_item("Medium", 1)
		quality_option.set_item_metadata(1, "medium")
		quality_option.add_item("Low", 2)
		quality_option.set_item_metadata(2, "low")

	if colorblind_btn != null:
		colorblind_btn.set_pressed_no_signal(colorblind_mode)

func configure_match(options: Dictionary = {}) -> void:
	_match_gen_id += 1
	_bot_sequence_running = false
	if _bot_turn_timer != null:
		_bot_turn_timer.stop()
	_last_options = options.duplicate(true)
	match_mode = str(options.get("mode", "solo"))

	var theme_id = str(options.get("theme", active_theme_id))
	var quality = str(options.get("quality", active_quality_preset))
	var view_m = str(options.get("view_mode", active_view_mode))
	var skin_m = str(options.get("card_skin", active_card_skin))
	var speed_m = str(options.get("bot_speed", active_bot_speed))
	active_location_id = str(options.get("location_id", active_location_id))
	active_jukebox_mode = str(options.get("jukebox_mode", active_jukebox_mode))
	if _keybind_svc != null and options.has("keybinds") and options["keybinds"] is Dictionary:
		_keybind_svc.load_from_dict(options["keybinds"])
	active_bot_difficulty = str(options.get("bot_difficulty", active_bot_difficulty)).to_lower().strip_edges()
	if not (active_bot_difficulty in ["easy", "normal", "hard", "tactical"]):
		active_bot_difficulty = "normal"
	var rules = options.get("rules", {})

	if options.has("colorblind_mode"):
		colorblind_mode = bool(options["colorblind_mode"])
		if colorblind_btn != null:
			colorblind_btn.set_pressed_no_signal(colorblind_mode)

	cartridge = UnoCartridgeScript.new()
	var players: Array[Dictionary] = []
	var explicit_roster = options.get("players_roster", options.get("players", []))
	if explicit_roster is Array and not explicit_roster.is_empty():
		for i in range(explicit_roster.size()):
			var p = explicit_roster[i]
			if p is Dictionary:
				var copy_p = p.duplicate(true)
				if not copy_p.has("seat"):
					copy_p["seat"] = i
				if not copy_p.has("player_id"):
					copy_p["player_id"] = "p%d" % i
				players.append(copy_p)
	elif options.has("human_names") and options["human_names"] is Array and not options["human_names"].is_empty():
		var h_names: Array = options["human_names"]
		var b_count = maxi(0, int(options.get("bot_count", 0)))
		var seat_i = 0
		for hn in h_names:
			players.append({
				"player_id": "p%d" % seat_i,
				"seat": seat_i,
				"name": str(hn),
				"is_bot": false,
				"is_remote": false
			})
			seat_i += 1
		for bi in range(b_count):
			players.append({
				"player_id": "p%d" % seat_i,
				"seat": seat_i,
				"name": "Bot %d" % (bi + 1),
				"is_bot": true,
				"is_remote": false
			})
			seat_i += 1
	elif match_mode == "pass_and_play":
		var p_count = maxi(2, int(options.get("player_count", 2)))
		var bot_c = maxi(0, int(options.get("bot_count", 0)))
		for i in range(p_count):
			players.append({
				"player_id": "p%d" % i,
				"seat": i,
				"name": "Spieler %d" % (i + 1),
				"is_bot": false,
				"is_remote": false
			})
		for bi in range(bot_c):
			var s_idx = players.size()
			players.append({
				"player_id": "p%d" % s_idx,
				"seat": s_idx,
				"name": "Bot %d" % (bi + 1),
				"is_bot": true,
				"is_remote": false
			})
	else:
		var total_count = maxi(2, int(options.get("player_count", 4)))
		players.append({
			"player_id": "p0",
			"seat": 0,
			"name": str(options.get("player_name", "Du")),
			"is_bot": false,
			"is_remote": false
		})
		for i in range(1, total_count):
			players.append({
				"player_id": "p%d" % i,
				"seat": i,
				"name": "Bot %d" % i,
				"is_bot": true,
				"is_remote": false
			})

	if players.size() < 2:
		var bot_idx = players.size()
		players.append({ "player_id": "p%d" % bot_idx, "seat": bot_idx, "name": "Bot 1", "is_bot": true, "is_remote": false })

	_local_human_ids.clear()
	for p in players:
		if not bool(p.get("is_bot", false)) and not bool(p.get("is_remote", false)):
			_local_human_ids.append(str(p.get("player_id", "")))

	var match_seed = int(options.get("seed", Time.get_unix_time_from_system()))
	cartridge.init_match("match_ui_%d" % match_seed, players, rules if rules is Dictionary else {}, match_seed)
	cartridge.start_round()

	current_player_id = _local_human_ids[0] if not _local_human_ids.is_empty() else str(players[0].get("player_id", "p0"))
	_last_revealed_human_id = current_player_id
	pending_wild_card_id = ""
	_hovered_3d_index = -1
	_keyboard_selected_idx = -1
	_reaction_time_left = 0.0
	_reaction_signature = ""
	_expired_reaction_signatures.clear()
	_pending_jump_in_card = {}
	_last_skipped_seat = -1
	_skip_banner_time_left = 0.0
	if skip_banner_panel != null:
		skip_banner_panel.visible = false
	if center_reaction_panel != null:
		center_reaction_panel.visible = false
	_round_recorded = false
	_match_start_unix = int(Time.get_unix_time_from_system())

	if round_over_overlay != null:
		round_over_overlay.visible = false
	if challenge_reveal_overlay != null:
		challenge_reveal_overlay.visible = false
	if color_wheel != null:
		color_wheel.close_wheel()
	if quick_drawer != null:
		quick_drawer.visible = false

	if pass_and_play_ctrl != null:
		pass_and_play_ctrl.init_session(players, 0)
		if _local_human_ids.size() <= 1 or view_m == "table_role":
			pass_and_play_ctrl.request_reveal(str(players[0].get("player_id", "p0")))

	_update_table_qr_badge(options)
	set_bot_speed(speed_m)
	active_card_skin = CardTextureGenScript.normalize_skin(skin_m)
	_sync_option_by_meta(skin_option, active_card_skin)
	active_view_mode = view_m if view_m in VALID_VIEW_MODES else "full_3d"
	set_table_theme(theme_id)
	set_quality_preset(quality)
	set_view_mode(active_view_mode)
	if sfx_player != null:
		sfx_player.play_jukebox(active_jukebox_mode, active_location_id)
	if cartridge != null and not cartridge.is_round_over():
		var start_p = cartridge.get_player_by_seat(cartridge.current_turn_seat)
		if bool(start_p.get("is_bot", false)):
			_post_human_turn()

func _update_table_qr_badge(options: Dictionary) -> void:
	if table_qr_badge == null:
		return
	var join_url = str(options.get("join_url", ""))
	var pin = str(options.get("room_code", ""))
	if not join_url.is_empty() and table_qr_rect != null:
		table_qr_rect.texture = QRCodeScript.generate_texture(join_url, 4, 2)
		if table_qr_pin != null:
			table_qr_pin.text = "PIN: %s" % (pin if not pin.is_empty() else "LAN")
	else:
		if table_qr_pin != null:
			table_qr_pin.text = "TV-Tisch-Ansicht"

func set_view_mode(mode: String) -> void:
	var m = mode.to_lower().strip_edges()
	if not (m in VALID_VIEW_MODES):
		m = "full_3d"
	active_view_mode = m

	_sync_option_by_meta(view_mode_option, active_view_mode)
	if view_mode_quick_btn != null:
		view_mode_quick_btn.text = I18nServiceScript.t("hud.view_prefix", {"mode": VIEW_MODE_LABELS.get(active_view_mode, "Full 3D")})

	var show_25d_fan = (active_view_mode == "hybrid_25d" or active_view_mode == "clean_25d")
	if hand_fan_root != null:
		hand_fan_root.visible = show_25d_fan
	if bottom_right_actions != null:
		bottom_right_actions.visible = (active_view_mode != "table_role")
	if table_qr_badge != null:
		table_qr_badge.visible = (active_view_mode == "table_role")

	if active_view_mode == "clean_25d" and active_theme_id != "clean_25d":
		set_table_theme("clean_25d")
	elif active_table_3d != null and active_table_3d.has_method("configure_for_player_count"):
		var count = cartridge.players.size() if cartridge != null else 4
		active_table_3d.configure_for_player_count(count, active_view_mode, active_view_mode == "table_role")

	refresh_display()

func set_card_skin(skin_id: String) -> void:
	active_card_skin = CardTextureGenScript.normalize_skin(skin_id)
	_sync_option_by_meta(skin_option, active_card_skin)
	_rebuild_draw_pile_3d_materials()
	refresh_display()

func set_bot_speed(speed_id: String) -> void:
	var s = speed_id.to_lower().strip_edges()
	if not (s in ["normal", "fast", "instant"]):
		s = "normal"
	active_bot_speed = s
	_sync_option_by_meta(speed_option, s)
	if animator != null:
		animator.set_speed_mode(s)

func set_table_theme(theme_id: String) -> void:
	if not TABLE_SCENES.has(theme_id):
		theme_id = "arcade_ps5"
	active_theme_id = theme_id
	_sync_option_by_meta(theme_option, theme_id)

	if table_viewport == null:
		return

	if active_table_3d != null:
		if active_table_3d.get_parent() == table_viewport:
			table_viewport.remove_child(active_table_3d)
		active_table_3d.queue_free()
		active_table_3d = null
		direction_ring_3d = null
		draw_pile_3d_root = null
		discard_pile_3d_root = null
		opponent_hands_3d_root = null
		player_hand_3d_root = null
		seat_turn_beacon_3d = null
		seat_turn_halo_3d = null
		_ring_mesh_instance = null
		_player_3d_cards.clear()

	var scene_path = TABLE_SCENES[theme_id]
	if ResourceLoader.exists(scene_path):
		var packed = load(scene_path)
		if packed is PackedScene:
			var inst = packed.instantiate()
			if inst is Node3D:
				active_table_3d = inst
				table_viewport.add_child(active_table_3d)
				if active_table_3d.has_method("apply_location_environment"):
					active_table_3d.apply_location_environment(active_location_id)
				if active_table_3d.has_method("apply_quality_preset"):
					active_table_3d.apply_quality_preset(active_quality_preset)
				if active_table_3d.has_method("configure_for_player_count"):
					var count = cartridge.players.size() if cartridge != null else 4
					active_table_3d.configure_for_player_count(count, active_view_mode, active_view_mode == "table_role")
				_setup_3d_table_elements()
				if cartridge != null:
					_sync_3d_table_state(cartridge.get_public_state(), cartridge.get_player_view(current_player_id))

func set_quality_preset(preset: String) -> void:
	active_quality_preset = preset.to_lower()
	_sync_option_by_meta(quality_option, active_quality_preset)
	if active_table_3d != null and active_table_3d.has_method("apply_quality_preset"):
		active_table_3d.apply_quality_preset(active_quality_preset)
	if table_viewport != null:
		table_viewport.msaa_3d = Viewport.MSAA_4X if active_quality_preset == "high" else (Viewport.MSAA_2X if active_quality_preset == "medium" else Viewport.MSAA_DISABLED)

func _sync_option_by_meta(opt: OptionButton, meta_val: String) -> void:
	if opt == null:
		return
	for i in range(opt.item_count):
		if str(opt.get_item_metadata(i)) == meta_val:
			opt.select(i)
			return

func _setup_3d_table_elements() -> void:
	if active_table_3d == null or CardMeshScene == null:
		return

	var draw_pos = Vector3(-0.145, 0.755, 0.0)
	var discard_pos = Vector3(0.145, 0.755, 0.0)
	if active_table_3d.has_method("get_draw_pile_position"):
		draw_pos = active_table_3d.get_draw_pile_position()
	if active_table_3d.has_method("get_discard_pile_position"):
		discard_pos = active_table_3d.get_discard_pile_position()

	# 1. 3D Turn Direction Ring
	direction_ring_3d = Node3D.new()
	direction_ring_3d.name = "DirectionRing3D"
	direction_ring_3d.position = Vector3(0.0, draw_pos.y + 0.002, 0.0)
	active_table_3d.add_child(direction_ring_3d)

	_ring_mesh_instance = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 0.35
	torus.outer_radius = 0.375
	torus.rings = 36
	torus.ring_segments = 14
	_ring_mesh_instance.mesh = torus
	direction_ring_3d.add_child(_ring_mesh_instance)

	for i in range(4):
		var marker_orb = MeshInstance3D.new()
		var sphere = SphereMesh.new()
		sphere.radius = 0.016
		sphere.height = 0.032
		marker_orb.mesh = sphere
		var angle = float(i) * PI * 0.5
		marker_orb.position = Vector3(cos(angle) * 0.362, 0.008, sin(angle) * 0.362)
		direction_ring_3d.add_child(marker_orb)

	# 2. 3D Draw Pile Stack (textured card backs)
	draw_pile_3d_root = Node3D.new()
	draw_pile_3d_root.name = "DrawPile3DStack"
	draw_pile_3d_root.position = draw_pos
	active_table_3d.add_child(draw_pile_3d_root)

	for i in range(10):
		var stack_card = CardMeshScene.instantiate()
		if stack_card != null:
			stack_card.position = Vector3(0.0, 0.004 + float(i) * 0.0028, 0.0)
			stack_card.rotation_degrees = Vector3(0.0, float((i % 3) - 1) * 1.4, 180.0)
			stack_card.scale = Vector3.ONE * 2.15
			CardTextureGenScript.apply_card_materials_to_mesh(stack_card, { "masked": true }, active_card_skin, colorblind_mode, false)
			draw_pile_3d_root.add_child(stack_card)

	# 3. 3D Discard Pile Stack (dynamically rebuilt with actual played cards)
	discard_pile_3d_root = Node3D.new()
	discard_pile_3d_root.name = "DiscardPile3DStack"
	discard_pile_3d_root.position = discard_pos
	active_table_3d.add_child(discard_pile_3d_root)

	# 4. 3D Opponent Card Fans Root & Player 3D Hand Root
	opponent_hands_3d_root = Node3D.new()
	opponent_hands_3d_root.name = "OpponentHands3DRoot"
	active_table_3d.add_child(opponent_hands_3d_root)

	player_hand_3d_root = Node3D.new()
	player_hand_3d_root.name = "PlayerHand3DRoot"
	active_table_3d.add_child(player_hand_3d_root)

	# 5. Active Seat Spotlight & Floor Halo Ring
	seat_turn_beacon_3d = OmniLight3D.new()
	seat_turn_beacon_3d.name = "SeatTurnBeacon3D"
	seat_turn_beacon_3d.light_energy = 1.4
	seat_turn_beacon_3d.omni_range = 1.15
	seat_turn_beacon_3d.position = Vector3(0.0, 1.05, 0.52)
	active_table_3d.add_child(seat_turn_beacon_3d)

	seat_turn_halo_3d = MeshInstance3D.new()
	var halo = TorusMesh.new()
	halo.inner_radius = 0.058
	halo.outer_radius = 0.072
	halo.rings = 24
	halo.ring_segments = 10
	seat_turn_halo_3d.mesh = halo
	active_table_3d.add_child(seat_turn_halo_3d)

	_update_3d_discard_tint("wild")

func _is_flip_enabled() -> bool:
	if cartridge == null:
		return false
	return bool(cartridge.rules_config.get("expansion_flip", false)) or str(cartridge.active_side) == "dark"

func _rebuild_draw_pile_3d_materials() -> void:
	if draw_pile_3d_root == null:
		return
	var is_flip = _is_flip_enabled()
	var cur_side = str(cartridge.active_side) if cartridge != null else "light"
	var opp_draw: Dictionary = {}
	if is_flip:
		if cartridge != null and not cartridge.draw_pile.is_empty() and cartridge.draw_pile.back() is Dictionary:
			opp_draw = UnoRulesScript.get_opposite_side_card(cartridge.draw_pile.back(), cur_side)
		else:
			opp_draw = { "color": "pink" if cur_side == "light" else "red", "value": "flip" }
	for child in draw_pile_3d_root.get_children():
		CardTextureGenScript.apply_card_materials_to_mesh(child, { "masked": true }, active_card_skin, colorblind_mode, false, opp_draw)

func _sync_3d_table_state(pub_state: Dictionary, my_view: Dictionary) -> void:
	if active_table_3d == null or CardMeshScene == null:
		return

	_turn_direction = int(pub_state.get("direction", 1))
	var total_players = maxi(2, pub_state.get("players", []).size())
	var my_seat = int(my_view.get("my_seat", 0))
	if active_view_mode == "table_role":
		my_seat = 0
	var is_flip = _is_flip_enabled()
	var cur_side = str(pub_state.get("active_side", "light"))

	# 1. Scale Draw Pile Stack visibility & apply Flip opposite face when active
	if draw_pile_3d_root != null:
		var draw_count = int(pub_state.get("draw_pile_count", 0))
		var visible_layers = clampi(int(ceil(float(draw_count) / 12.0)), 1 if draw_count > 0 else 0, draw_pile_3d_root.get_child_count())
		var opp_draw: Dictionary = {}
		if is_flip:
			if cartridge != null and not cartridge.draw_pile.is_empty() and cartridge.draw_pile.back() is Dictionary:
				opp_draw = UnoRulesScript.get_opposite_side_card(cartridge.draw_pile.back(), cur_side)
			else:
				opp_draw = { "color": "pink" if cur_side == "light" else "red", "value": "flip" }
		for i in range(draw_pile_3d_root.get_child_count()):
			var child = draw_pile_3d_root.get_child(i)
			if child is Node3D:
				child.visible = (i < visible_layers)
				if child.visible:
					CardTextureGenScript.apply_card_materials_to_mesh(child, { "masked": true }, active_card_skin, colorblind_mode, false, opp_draw)

	# 2. Rebuild 3D Discard Stack from recent cards in cartridge.discard_pile
	if discard_pile_3d_root != null:
		for child in discard_pile_3d_root.get_children():
			discard_pile_3d_root.remove_child(child)
			child.queue_free()

		var pile: Array = cartridge.discard_pile if cartridge != null else []
		var start_idx = maxi(0, pile.size() - 5)
		var layer_i = 0
		for idx in range(start_idx, pile.size()):
			var c_data = pile[idx]
			if not (c_data is Dictionary):
				continue
			var card_3d = CardMeshScene.instantiate()
			if card_3d != null:
				var jitter_ang = float(((idx * 37) % 29) - 14)
				var jitter_x = float(((idx * 17) % 11) - 5) * 0.0018
				var jitter_z = float(((idx * 23) % 11) - 5) * 0.0018
				card_3d.position = Vector3(jitter_x, 0.004 + float(layer_i) * 0.0028, jitter_z)
				card_3d.rotation_degrees = Vector3(0.0, jitter_ang, 0.0)
				card_3d.scale = Vector3.ONE * 2.15
				var opp_discard = UnoRulesScript.get_opposite_side_card(c_data, cur_side) if is_flip else {}
				CardTextureGenScript.apply_card_materials_to_mesh(card_3d, c_data, active_card_skin, colorblind_mode, true, opp_discard)
				discard_pile_3d_root.add_child(card_3d)
				layer_i += 1

	# 3. 3D Opponent Card Fans around the stadium table
	if opponent_hands_3d_root != null:
		for child in opponent_hands_3d_root.get_children():
			opponent_hands_3d_root.remove_child(child)
			child.queue_free()

		var players_list = pub_state.get("players", [])
		var max_fan_cards = 5 if total_players > 10 else 8
		var opp_scale = 1.45 if total_players > 10 else 1.85
		for p in players_list:
			var seat_idx = int(p.get("seat", 0))
			if active_view_mode != "table_role" and seat_idx == my_seat:
				continue

			var seat_pos = _get_seat_3d_anchor(seat_idx, total_players, my_seat)
			var fan_holder = Node3D.new()
			fan_holder.name = "SeatFan_%d" % seat_idx
			fan_holder.position = seat_pos
			var dir_to_center = Vector3(0.0, seat_pos.y, 0.0) - seat_pos
			if not dir_to_center.is_zero_approx():
				fan_holder.transform.basis = Basis.looking_at(dir_to_center.normalized(), Vector3.UP)
			opponent_hands_3d_root.add_child(fan_holder)

			var opp_real_hand: Array = []
			if is_flip and cartridge != null:
				var p_obj = cartridge.get_player_by_seat(seat_idx)
				var p_id = str(p_obj.get("player_id", ""))
				opp_real_hand = cartridge.player_hands.get(p_id, [])

			var c_count = clampi(int(p.get("card_count", 0)), 0, max_fan_cards)
			var spacing = 0.036 if total_players > 10 else 0.048
			for c_idx in range(c_count):
				var card_3d = CardMeshScene.instantiate()
				if card_3d != null:
					var offset_norm = float(c_idx) - float(maxi(0, c_count - 1)) * 0.5
					card_3d.position = Vector3(offset_norm * spacing, 0.055, abs(offset_norm) * 0.007)
					card_3d.transform.basis = Basis(Vector3.RIGHT, deg_to_rad(64.0)) * Basis(Vector3.UP, deg_to_rad(-offset_norm * 4.5))
					card_3d.scale = Vector3.ONE * opp_scale
					var opp_back: Dictionary = {}
					if is_flip:
						if c_idx < opp_real_hand.size() and opp_real_hand[c_idx] is Dictionary:
							opp_back = UnoRulesScript.get_opposite_side_card(opp_real_hand[c_idx], cur_side)
						else:
							opp_back = { "color": "pink" if cur_side == "light" else "red", "value": "1" }
					CardTextureGenScript.apply_card_materials_to_mesh(card_3d, { "masked": true }, active_card_skin, colorblind_mode, false, opp_back)
					fan_holder.add_child(card_3d)

	# 4. 3D Local Player Hand Arc (in Full 3D mode)
	_rebuild_player_hand_3d(my_view, total_players, my_seat, cur_side)

	# 5. Move Active Seat Spotlight & Halo
	var active_seat = int(pub_state.get("current_turn_seat", 0))
	var target_seat_pos = _get_seat_3d_anchor(active_seat, total_players, my_seat)
	if seat_turn_beacon_3d != null:
		seat_turn_beacon_3d.position = target_seat_pos + Vector3(0.0, 0.34, 0.0)
	if seat_turn_halo_3d != null:
		seat_turn_halo_3d.position = target_seat_pos + Vector3(0.0, 0.004, 0.0)

func _rebuild_player_hand_3d(my_view: Dictionary, total_players: int, my_seat: int, cur_side: String = "light") -> void:
	_player_3d_cards.clear()
	if player_hand_3d_root == null:
		return
	for child in player_hand_3d_root.get_children():
		player_hand_3d_root.remove_child(child)
		child.queue_free()

	if active_view_mode != "full_3d":
		return

	var table_scale = active_table_3d.get_table_scale() if (active_table_3d != null and active_table_3d.has_method("get_table_scale")) else 1.0
	var hand_cam_scale = lerpf(1.0, table_scale, 0.45)
	var seat0_pos = _get_seat_3d_anchor(my_seat, total_players, my_seat)
	var hand_cards: Array = my_view.get("hand", [])
	var hand_len = hand_cards.size()
	if hand_len == 0:
		return

	var is_flip = _is_flip_enabled()
	var max_span = 1.06 * minf(table_scale, 1.85)
	var spacing = minf(0.102 * hand_cam_scale, max_span / float(maxi(1, hand_len)))
	var card_scale_val = clampf(2.25 - float(maxi(0, hand_len - 10)) * 0.045, 1.45, 2.25) * hand_cam_scale

	for idx in range(hand_len):
		var c_data = hand_cards[idx]
		if not (c_data is Dictionary):
			continue
		var c_node = CardMeshScene.instantiate()
		if c_node == null:
			continue

		var off = float(idx) - float(hand_len - 1) * 0.5
		var is_masked = bool(c_data.get("masked", false))
		var playable = bool(c_data.get("playable", false)) and not is_masked
		var arch_y = -absf(off) * 0.0045
		var shingle_z = float(idx) * 0.0024 + (0.014 if playable else -0.006)
		var base_pos = seat0_pos + Vector3(off * spacing, 0.14 * hand_cam_scale + arch_y + (0.016 if playable else 0.0), 0.14 + shingle_z)
		var roll_deg = -off * clampf(3.8, 1.2, 32.0 / float(maxi(1, hand_len)))
		var card_basis = Basis(Vector3.RIGHT, deg_to_rad(52.0)) * Basis(Vector3.UP, deg_to_rad(roll_deg))
		if is_masked:
			card_basis = card_basis * Basis(Vector3.FORWARD, PI)
		var base_scale = Vector3.ONE * card_scale_val

		c_node.position = base_pos
		c_node.transform.basis = card_basis
		c_node.scale = base_scale
		var base_rot = c_node.rotation_degrees
		var opp_card: Dictionary = {}
		if is_flip:
			if is_masked:
				opp_card = { "color": "pink" if cur_side == "light" else "red", "value": "1" }
			else:
				var raw_card = c_data
				if cartridge != null:
					var real_hand: Array = cartridge.player_hands.get(current_player_id, [])
					if idx < real_hand.size() and real_hand[idx] is Dictionary:
						raw_card = real_hand[idx]
				opp_card = UnoRulesScript.get_opposite_side_card(raw_card, cur_side)
		CardTextureGenScript.apply_card_materials_to_mesh(c_node, c_data, active_card_skin, colorblind_mode, not is_masked, opp_card)
		if not is_masked:
			CardTextureGenScript.set_card_mesh_playable_state(c_node, playable)
		player_hand_3d_root.add_child(c_node)

		_player_3d_cards.append({
			"node": c_node,
			"card": c_data,
			"base_pos": base_pos,
			"base_rot": base_rot,
			"base_scale": base_scale,
			"playable": playable
		})

func _get_seat_3d_anchor(seat_index: int, total_players: int = 4, local_seat: int = 0) -> Vector3:
	if active_table_3d != null and active_table_3d.has_method("get_seat_position"):
		var pos = active_table_3d.get_seat_position(seat_index, total_players, local_seat)
		if pos != Vector3.ZERO:
			return pos
	var rel = ((seat_index - local_seat) % maxi(2, total_players) + maxi(2, total_players)) % maxi(2, total_players)
	var ang = PI * 0.5 + float(rel) * TAU / float(maxi(2, total_players))
	return Vector3(cos(ang) * 0.78, 0.755, sin(ang) * 0.47)

func _update_3d_discard_tint(color_name: String) -> void:
	var tint: Color = CARD_COLORS.get(color_name.to_lower(), CARD_COLORS["wild"])
	if _ring_mesh_instance != null:
		var ring_mat = StandardMaterial3D.new()
		ring_mat.albedo_color = tint
		ring_mat.emission_enabled = true
		ring_mat.emission = tint
		ring_mat.emission_energy_multiplier = 2.0
		ring_mat.roughness = 0.22
		_ring_mesh_instance.material_override = ring_mat

		if direction_ring_3d != null:
			for child in direction_ring_3d.get_children():
				if child is MeshInstance3D and child != _ring_mesh_instance:
					child.material_override = ring_mat

	if seat_turn_beacon_3d != null:
		seat_turn_beacon_3d.light_color = tint.lightened(0.25)
	if seat_turn_halo_3d != null:
		var halo_mat = StandardMaterial3D.new()
		halo_mat.albedo_color = Color(1.0, 0.82, 0.25)
		halo_mat.emission_enabled = true
		halo_mat.emission = Color(1.0, 0.78, 0.20)
		halo_mat.emission_energy_multiplier = 2.2
		seat_turn_halo_3d.material_override = halo_mat

# --- 3D Raycast & Screen-Space Picking Interaction for Full 3D Mode ---

func _gui_input(event: InputEvent) -> void:
	if _handle_3d_pointer_event(event):
		accept_event()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if _handle_keyboard_shortcut(event as InputEventKey):
			if get_viewport() != null:
				get_viewport().set_input_as_handled()
			return
	if _handle_3d_pointer_event(event):
		if get_viewport() != null:
			get_viewport().set_input_as_handled()

func _handle_keyboard_shortcut(event: InputEventKey) -> bool:
	if cartridge == null or _keybind_svc == null:
		return false
	var focus_owner = get_viewport().gui_get_focus_owner() if get_viewport() != null else null
	if focus_owner is LineEdit or focus_owner is TextEdit:
		return false
	if event.keycode == KEY_ESCAPE:
		if color_wheel != null and color_wheel.visible and color_wheel.has_method("close_wheel"):
			color_wheel.close_wheel()
			_on_color_choice_canceled()
			return true
		if quick_drawer != null and quick_drawer.visible:
			quick_drawer.visible = false
			return true
		return false
	if (curtain_overlay != null and curtain_overlay.visible) or (round_over_overlay != null and round_over_overlay.visible) or (challenge_reveal_overlay != null and challenge_reveal_overlay.visible):
		return false

	if _keybind_svc.matches_event("jukebox_next", event):
		if sfx_player != null:
			var next_t: String = sfx_player.next_jukebox_track()
			_show_status_toast("🎵 Jukebox: %s" % next_t)
		return true
	if _keybind_svc.matches_event("cycle_view", event):
		_on_cycle_view_mode_pressed()
		return true
	if _keybind_svc.matches_event("reaction_action", event):
		if jump_in_popup_btn != null and jump_in_popup_btn.visible:
			_on_jump_in_popup_btn_pressed()
			return true
		if catch_uno_popup_btn != null and catch_uno_popup_btn.visible:
			_on_catch_uno_btn_pressed()
			return true
		if challenge_p4_popup_btn != null and challenge_p4_popup_btn.visible:
			_on_challenge_plus_four_btn_pressed()
			return true
		return false
	if _keybind_svc.matches_event("call_uno", event):
		_on_call_uno_button_pressed()
		return true
	if _keybind_svc.matches_event("draw_card", event):
		_on_draw_pile_btn_pressed()
		return true
	if _keybind_svc.matches_event("sort_hand", event):
		_on_sort_hand_btn_pressed()
		return true
	if _keybind_svc.matches_event("shuffle_hand", event):
		_on_shuffle_hand_btn_pressed()
		return true

	var my_view: Dictionary = cartridge.get_player_view(current_player_id)
	var hand: Array = my_view.get("hand", [])
	if hand.is_empty():
		return false

	if _keybind_svc.matches_event("nav_left", event):
		_keyboard_selected_idx = (hand.size() - 1) if _keyboard_selected_idx < 0 else clampi(_keyboard_selected_idx - 1, 0, hand.size() - 1)
		_hovered_3d_index = _keyboard_selected_idx
		_rebuild_25d_hand_fan(my_view)
		return true
	if _keybind_svc.matches_event("nav_right", event):
		_keyboard_selected_idx = 0 if _keyboard_selected_idx < 0 else clampi(_keyboard_selected_idx + 1, 0, hand.size() - 1)
		_hovered_3d_index = _keyboard_selected_idx
		_rebuild_25d_hand_fan(my_view)
		return true

	# Number keys 1..9 quick select card
	var kcode: int = int(event.keycode)
	if kcode >= KEY_1 and kcode <= KEY_9:
		var num_idx := clampi(kcode - KEY_1, 0, hand.size() - 1)
		_keyboard_selected_idx = num_idx
		_hovered_3d_index = num_idx
		_rebuild_25d_hand_fan(my_view)
		return true

	if _keybind_svc.matches_event("play_card", event):
		if _keyboard_selected_idx < 0 or _keyboard_selected_idx >= hand.size():
			for hi in range(hand.size()):
				if hand[hi] is Dictionary and bool(hand[hi].get("playable", false)):
					_keyboard_selected_idx = hi
					break
		if _keyboard_selected_idx >= 0 and _keyboard_selected_idx < hand.size():
			var sel_card: Dictionary = hand[_keyboard_selected_idx]
			if bool(sel_card.get("playable", false)):
				_on_card_pressed(str(sel_card.get("id", "")), sel_card)
			else:
				_show_status_toast(I18nServiceScript.t("hud.card_mismatch_toast"))
			return true
	return false

func _handle_3d_pointer_event(event: InputEvent) -> bool:
	if event == null or event == _last_handled_event:
		return false
	if active_view_mode != "full_3d":
		_hovered_3d_index = -1
		return false
	if (curtain_overlay != null and curtain_overlay.visible) or (round_over_overlay != null and round_over_overlay.visible) or (challenge_reveal_overlay != null and challenge_reveal_overlay.visible) or (color_wheel != null and color_wheel.visible):
		return false

	if event is InputEventMouseMotion:
		_last_handled_event = event
		_update_3d_hover(event.position)
		return false
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_last_handled_event = event
		_update_3d_hover(event.position)
		if _hovered_3d_index >= 0 and _hovered_3d_index < _player_3d_cards.size():
			var entry = _player_3d_cards[_hovered_3d_index]
			if bool(entry.get("playable", false)):
				var card_dict: Dictionary = entry["card"]
				_on_card_pressed(str(card_dict.get("id", "")), card_dict)
			else:
				var pub = cartridge.get_public_state() if cartridge != null else {}
				var turn_seat = int(pub.get("current_turn_seat", 0))
				var my_seat = int(cartridge.get_player_view(current_player_id).get("my_seat", 0)) if cartridge != null else 0
				if _bot_sequence_running or turn_seat != my_seat:
					_show_status_toast(I18nServiceScript.t("hud.wait_turn_toast"))
				else:
					_show_status_toast(I18nServiceScript.t("hud.card_mismatch_toast"))
			return true
		elif _hovered_draw_pile_3d:
			_on_draw_pile_btn_pressed()
			return true
	return false

func _update_3d_hover(screen_pos: Vector2) -> void:
	if active_table_3d == null or not active_table_3d.has_method("get_camera"):
		_hovered_3d_index = -1
		_hovered_draw_pile_3d = false
		return
	var cam: Camera3D = active_table_3d.get_camera()
	if cam == null or table_viewport == null:
		return

	var vp_rect = size if (size.x > 10.0 and size.y > 10.0) else get_viewport_rect().size
	if vp_rect.x <= 0.0 or vp_rect.y <= 0.0:
		vp_rect = Vector2(float(table_viewport.size.x), float(table_viewport.size.y))
	if vp_rect.x <= 0.0 or vp_rect.y <= 0.0:
		return
	var norm_pos = Vector2(
		(screen_pos.x / vp_rect.x) * float(table_viewport.size.x),
		(screen_pos.y / vp_rect.y) * float(table_viewport.size.y)
	)
	var ray_origin = cam.project_ray_origin(norm_pos)
	var ray_dir = cam.project_ray_normal(norm_pos)

	# 1. Pick 3D hand card via ray-plane intersection using base_pos + smallest distance to card centerline
	var best_idx = -1
	var best_dist = 999.0
	var best_x_score = 999.0
	var parent_xform: Transform3D = player_hand_3d_root.global_transform if (player_hand_3d_root != null and player_hand_3d_root.is_inside_tree()) else Transform3D.IDENTITY
	for i in range(_player_3d_cards.size() - 1, -1, -1):
		var entry = _player_3d_cards[i]
		var node: Node3D = entry.get("node", null)
		if node == null or not is_instance_valid(node):
			continue
		var base_local = Transform3D(node.transform.basis, entry["base_pos"])
		var card_xform: Transform3D = parent_xform * base_local
		var normal = card_xform.basis.y.normalized()
		var denom = ray_dir.dot(normal)
		if absf(denom) < 0.001:
			continue
		var t = (card_xform.origin - ray_origin).dot(normal) / denom
		if t <= 0.0:
			continue
		var hit_world = ray_origin + ray_dir * t
		var local_hit = card_xform.affine_inverse() * hit_world
		var abs_lx = absf(local_hit.x)
		if abs_lx <= 0.044 and absf(local_hit.z) <= 0.058:
			if abs_lx < best_x_score - 0.002 or (absf(abs_lx - best_x_score) <= 0.002 and t < best_dist):
				best_x_score = abs_lx
				best_dist = t
				best_idx = i

	# 2. Screen-space 2D unproject fallback so slight camera angles/overlap never miss clicks
	if best_idx == -1 and table_viewport.size.x > 0 and table_viewport.size.y > 0:
		var best_2d_dist = 99999.0
		for i in range(_player_3d_cards.size() - 1, -1, -1):
			var entry = _player_3d_cards[i]
			var node: Node3D = entry.get("node", null)
			if node == null or not is_instance_valid(node):
				continue
			var world_center = node.global_position if node.is_inside_tree() else node.position
			if cam.is_position_behind(world_center):
				continue
			var proj_vp = cam.unproject_position(world_center)
			var proj_screen = Vector2(
				(proj_vp.x / float(table_viewport.size.x)) * vp_rect.x,
				(proj_vp.y / float(table_viewport.size.y)) * vp_rect.y
			)
			var dx = absf(screen_pos.x - proj_screen.x)
			var dy = absf(screen_pos.y - proj_screen.y)
			if dx <= 46.0 and dy <= 68.0:
				var d2 = screen_pos.distance_squared_to(proj_screen)
				if d2 < best_2d_dist:
					best_2d_dist = d2
					best_idx = i

	_hovered_3d_index = best_idx

	# 3. Also check 3D Draw Pile stack (ray-plane + 2D unproject fallback)
	_hovered_draw_pile_3d = false
	if best_idx == -1 and draw_pile_3d_root != null:
		var dp_world = draw_pile_3d_root.global_position if draw_pile_3d_root.is_inside_tree() else draw_pile_3d_root.position
		if absf(ray_dir.y) > 0.01:
			var plane_y = dp_world.y + 0.02
			var t_dp = (plane_y - ray_origin.y) / ray_dir.y
			if t_dp > 0.0:
				var hit_dp = ray_origin + ray_dir * t_dp
				var dx = absf(hit_dp.x - dp_world.x)
				var dz = absf(hit_dp.z - dp_world.z)
				_hovered_draw_pile_3d = (dx <= 0.11 and dz <= 0.14)
		if not _hovered_draw_pile_3d and table_viewport.size.x > 0 and table_viewport.size.y > 0 and not cam.is_position_behind(dp_world):
			var dp_vp = cam.unproject_position(dp_world)
			var dp_screen = Vector2(
				(dp_vp.x / float(table_viewport.size.x)) * vp_rect.x,
				(dp_vp.y / float(table_viewport.size.y)) * vp_rect.y
			)
			if screen_pos.distance_to(dp_screen) <= 58.0:
				_hovered_draw_pile_3d = true

# --- Display Refresh & 2.5D Curved Fan ---

func reveal_pass_and_play() -> void:
	if pass_and_play_ctrl != null:
		pass_and_play_ctrl.request_reveal(current_player_id)
	_last_revealed_human_id = current_player_id
	refresh_display()

func refresh_display() -> void:
	if cartridge == null:
		return

	var use_curtain = (_local_human_ids.size() > 1 and active_view_mode != "table_role")
	var pub_state = cartridge.get_public_state()
	var my_view = cartridge.get_player_view(current_player_id)
	if use_curtain and pass_and_play_ctrl != null:
		my_view = pass_and_play_ctrl.filter_view_for_curtain(my_view)

	# 1. Pass-and-Play Curtain
	var curtain_shown = false
	if curtain_overlay != null:
		curtain_shown = (use_curtain and pass_and_play_ctrl != null and pass_and_play_ctrl.is_curtain_active() and not cartridge.is_round_over())
		curtain_overlay.visible = curtain_shown
		if curtain_shown and curtain_title != null:
			var active_p = cartridge.get_player_by_seat(int(pub_state.get("current_turn_seat", 0)))
			curtain_title.text = I18nServiceScript.t("hud.curtain_title", {"player": str(active_p.get("name", current_player_id))})

	# 2. Top Status Pill
	var top = pub_state.get("top_discard", {})
	var raw_col = str(top.get("color", "wild")).to_lower()
	var eff_col = str(pub_state.get("active_color", "")).to_lower()
	var display_col = eff_col if not eff_col.is_empty() else raw_col
	var sym = AccessibilitySymbolsScript.get_char(display_col) if colorblind_mode else ""
	var draw_cnt = int(pub_state.get("draw_pile_count", 0))
	var pen = int(pub_state.get("pending_penalty_draws", 0))
	var cur_side = str(pub_state.get("active_side", "light"))
	if color_wheel != null and color_wheel.has_method("set_dark_side"):
		color_wheel.set_dark_side(cur_side == "dark")

	if color_dot != null:
		color_dot.color = CARD_COLORS.get(display_col, CARD_COLORS["wild"])
	if active_color_label != null:
		var side_tag = I18nServiceScript.t("hud.dark_tag") if cur_side == "dark" else ""
		active_color_label.text = I18nServiceScript.t("hud.deck_status", {"color": display_col.to_upper(), "sym": sym, "count": draw_cnt, "side": side_tag})
	if penalty_label != null:
		penalty_label.visible = pen > 0
		penalty_label.text = I18nServiceScript.t("hud.penalty_label", {"count": pen})

	if turn_label != null:
		var turn_s = int(pub_state.get("current_turn_seat", 0))
		var active_p = cartridge.get_player_by_seat(turn_s)
		var dir_text = "↻" if int(pub_state.get("direction", 1)) == 1 else "↺"
		turn_label.text = I18nServiceScript.t("hud.turn_label", {"player": str(active_p.get("name", "Player")), "dir": dir_text})

	if draw_pile_btn != null:
		draw_pile_btn.text = I18nServiceScript.t("hud.draw_penalty_btn", {"count": pen}) if pen > 0 else I18nServiceScript.t("hud.draw_btn", {"count": draw_cnt})

	# 3. 3D Table Update
	_update_3d_discard_tint(display_col)
	_sync_3d_table_state(pub_state, my_view)

	# 4. 2.5D Curved Hand Fan (Hybrid & Clean 2.5D)
	_rebuild_25d_hand_fan(my_view)

	# 5. Floating Opponent Badges
	_rebuild_opponent_badges(pub_state, my_view)

	# 6. Highlight UNO button & update Challenge / Hand Tools visibility
	if uno_call_btn != null:
		var my_len = my_view.get("hand", []).size()
		uno_call_btn.modulate = Color(1.15, 1.15, 1.15) if my_len <= 2 else Color(0.92, 0.92, 0.96, 0.85)

	if catch_uno_btn != null:
		var can_catch = (not curtain_shown) and (active_view_mode != "table_role") and (not cartridge.is_round_over()) and (not cartridge.get_catchable_uno_players(current_player_id).is_empty())
		catch_uno_btn.visible = can_catch

	if challenge_p4_btn != null:
		var can_chal = (not curtain_shown) and (active_view_mode != "table_role") and (not cartridge.is_round_over()) and cartridge.can_challenge_plus_four(current_player_id)
		challenge_p4_btn.visible = can_chal

	_update_reaction_window(curtain_shown)
	_check_round_over()
	match_state_changed.emit(pub_state)

func _update_reaction_window(curtain_shown: bool) -> void:
	if center_reaction_panel == null or cartridge == null:
		return
	var blocked: bool = curtain_shown or (active_view_mode == "table_role") or bool(cartridge.is_round_over())
	if blocked:
		center_reaction_panel.visible = false
		return

	var catch_list: Array = cartridge.get_catchable_uno_players(current_player_id)
	var jump_list: Array = cartridge.get_jump_in_cards(current_player_id)
	var can_chal: bool = cartridge.can_challenge_plus_four(current_player_id)

	var has_catch := not catch_list.is_empty()
	var has_jump := not jump_list.is_empty()
	if not has_catch and not has_jump and not can_chal:
		center_reaction_panel.visible = false
		_reaction_time_left = 0.0
		_reaction_signature = ""
		_pending_jump_in_card = {}
		if catch_uno_btn != null:
			catch_uno_btn.visible = false
		return

	var catch_id := str(catch_list[0].get("player_id", "")) if has_catch else ""
	var jump_id := str(jump_list[0].get("id", "")) if has_jump else ""
	_pending_jump_in_card = jump_list[0] if has_jump else {}
	var sig := "C:%s|J:%s|P4:%s|D:%d" % [catch_id, jump_id, str(can_chal), cartridge.discard_pile.size()]

	if _expired_reaction_signatures.has(sig):
		center_reaction_panel.visible = false
		if catch_uno_btn != null:
			catch_uno_btn.visible = false
		return

	if sig != _reaction_signature:
		_reaction_signature = sig
		_reaction_time_left = REACTION_WINDOW_SEC

	center_reaction_panel.visible = (_reaction_time_left > 0.0)
	if catch_uno_popup_btn != null:
		catch_uno_popup_btn.visible = has_catch
		catch_uno_popup_btn.text = I18nServiceScript.t("hud.catch_uno_btn")
	if jump_in_popup_btn != null:
		jump_in_popup_btn.visible = has_jump
		if has_jump:
			jump_in_popup_btn.text = I18nServiceScript.t("ui.game.jump_in_btn", { "card": "%s %s" % [str(_pending_jump_in_card.get("color", "")).to_upper(), str(_pending_jump_in_card.get("value", "")).to_upper()] })
	if challenge_p4_popup_btn != null:
		challenge_p4_popup_btn.visible = can_chal
		challenge_p4_popup_btn.text = I18nServiceScript.t("hud.challenge_p4_btn")
	_sync_reaction_timer_widgets()

func _tick_reaction_timer(delta: float) -> void:
	if _reaction_time_left <= 0.0:
		return
	_reaction_time_left = maxf(0.0, _reaction_time_left - delta)
	_sync_reaction_timer_widgets()
	if _reaction_time_left <= 0.0:
		if not _reaction_signature.is_empty():
			_expired_reaction_signatures[_reaction_signature] = true
		if center_reaction_panel != null:
			center_reaction_panel.visible = false
		if catch_uno_btn != null:
			catch_uno_btn.visible = false

func _sync_reaction_timer_widgets() -> void:
	if reaction_title_label != null:
		reaction_title_label.text = I18nServiceScript.t("ui.game.reaction_title", { "sec": "%.1f" % _reaction_time_left })
	if reaction_timer_bar != null:
		reaction_timer_bar.value = clampf((_reaction_time_left / REACTION_WINDOW_SEC) * 100.0, 0.0, 100.0)

func _on_jump_in_popup_btn_pressed() -> void:
	if cartridge == null or _pending_jump_in_card.is_empty():
		return
	var cid := str(_pending_jump_in_card.get("id", _pending_jump_in_card.get("uid", "")))
	if cid.is_empty():
		return
	var res: Dictionary = cartridge.handle_action(current_player_id, { "type": "ACTION_JUMP_IN", "card_id": cid })
	if res.get("success", false):
		if not _reaction_signature.is_empty():
			_expired_reaction_signatures[_reaction_signature] = true
		_reaction_time_left = 0.0
		if center_reaction_panel != null:
			center_reaction_panel.visible = false
		var pub_after = cartridge.get_public_state()
		_trigger_action_feedback(res.get("events", []), int(pub_after.get("current_turn_seat", 0)), _pending_jump_in_card, true)
		_post_human_turn()
	else:
		_show_status_toast(str(res.get("error", "")))
	refresh_display()

func _rebuild_25d_hand_fan(my_view: Dictionary) -> void:
	if hand_cards_layer == null:
		return
	for child in hand_cards_layer.get_children():
		hand_cards_layer.remove_child(child)
		child.queue_free()

	if active_view_mode != "hybrid_25d" and active_view_mode != "clean_25d":
		return

	var hand: Array = my_view.get("hand", [])
	var count = hand.size()
	if count == 0:
		return

	var layer_w = hand_cards_layer.size.x if hand_cards_layer.size.x > 100.0 else 1100.0
	var card_w = 104.0
	var card_h = 148.0
	var max_total_w = minf(layer_w - 220.0, 960.0)
	var step_x = minf(74.0, max_total_w / float(maxi(1, count)))
	var total_span = float(count - 1) * step_x + card_w
	var start_x = (layer_w - total_span) * 0.5

	for idx in range(count):
		var card = hand[idx]
		if not (card is Dictionary):
			continue
		var is_masked = bool(card.get("masked", false))
		var playable = bool(card.get("playable", false)) and not is_masked
		var c_id = str(card.get("id", ""))

		var card_btn = TextureButton.new()
		card_btn.custom_minimum_size = Vector2(card_w, card_h)
		card_btn.size = Vector2(card_w, card_h)
		card_btn.ignore_texture_size = true
		card_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		card_btn.texture_normal = CardTextureGenScript.get_card_back_texture(active_card_skin) if is_masked else CardTextureGenScript.get_card_front_texture(card, active_card_skin, colorblind_mode)

		var off = float(idx) - float(count - 1) * 0.5
		var is_kb_sel := (idx == _keyboard_selected_idx)
		var base_y = 24.0 + absf(off) * 2.2 - (14.0 if playable else 0.0) - (14.0 if is_kb_sel else 0.0)
		card_btn.position = Vector2(start_x + float(idx) * step_x, base_y)
		card_btn.pivot_offset = Vector2(card_w * 0.5, card_h)
		card_btn.rotation_degrees = clampf(off * 2.1, -18.0, 18.0)
		card_btn.modulate = Color.WHITE if (playable or is_masked) else Color(0.42, 0.45, 0.52, 0.58)
		card_btn.disabled = (not playable) or is_masked

		if not is_masked:
			card_btn.tooltip_text = AccessibilitySymbolsScript.get_accessible_label(card)
			if playable:
				var glow_frame = Panel.new()
				glow_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
				glow_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
				var sb = StyleBoxFlat.new()
				sb.draw_center = false
				sb.border_color = AccessibilitySymbolsScript.get_highlight_border_color(true, colorblind_mode)
				sb.set_border_width_all(3)
				sb.set_corner_radius_all(10)
				glow_frame.add_theme_stylebox_override("panel", sb)
				card_btn.add_child(glow_frame)

				card_btn.mouse_entered.connect(func():
					card_btn.position.y = base_y - 22.0
					card_btn.z_index = 40
				)
				card_btn.mouse_exited.connect(func():
					card_btn.position.y = base_y
					card_btn.z_index = idx
				)
				card_btn.pressed.connect(_on_card_pressed.bind(c_id, card))

		card_btn.z_index = idx
		hand_cards_layer.add_child(card_btn)

func _rebuild_opponent_badges(pub_state: Dictionary, my_view: Dictionary) -> void:
	if opponent_badges_root == null:
		return
	for child in opponent_badges_root.get_children():
		opponent_badges_root.remove_child(child)
		child.queue_free()

	var players_list: Array = pub_state.get("players", [])
	var total_players = maxi(2, players_list.size())
	var my_seat = int(my_view.get("my_seat", 0))
	if active_view_mode == "table_role":
		my_seat = 0

	var active_turn_seat = int(pub_state.get("current_turn_seat", 0))
	var compact = (total_players > 8)
	var vp_size = size if size.x > 100.0 else Vector2(1280.0, 720.0)

	for p in players_list:
		var p_seat = int(p.get("seat", 0))
		if active_view_mode != "table_role" and p_seat == my_seat:
			continue

		var is_active = (p_seat == active_turn_seat)
		var is_elim = bool(p.get("eliminated", false))
		var is_fin = bool(p.get("finished", false))
		var is_skipped = (p_seat == _last_skipped_seat and _skip_banner_time_left > 0.0)
		var badge = PanelContainer.new()
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_theme_stylebox_override("panel", UIThemeScript.make_badge_style(Color(1.0, 0.35, 0.35, 0.85) if is_skipped else Color(0.32, 0.72, 1.0, 0.55), is_active))
		if is_elim or is_fin:
			badge.modulate = Color(0.58, 0.58, 0.62, 0.78)

		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 6)
		var name_lbl = Label.new()
		var p_name = str(p.get("name", "P%d" % p_seat))
		var uno_flag = " 💀KO" if is_elim else (" 🏁 #%d" % int(p.get("placement", 1)) if is_fin else (" 🚫" if is_skipped else (" 🔥%s" % I18nServiceScript.t("hud.call_last") if bool(p.get("called_uno", false)) else (" ⚠!" if int(p.get("card_count", 0)) == 1 else ""))))
		name_lbl.text = ("%s" % p_name) if compact else ("%s%s" % [p_name, " 🤖" if p.get("is_bot", false) else ""])
		name_lbl.add_theme_font_size_override("font_size", 12 if compact else 14)
		hbox.add_child(name_lbl)

		var count_lbl = Label.new()
		count_lbl.text = "💀 KO" if is_elim else ("🏁 #%d" % int(p.get("placement", 1)) if is_fin else ("🃏 %d%s" % [int(p.get("card_count", 0)), uno_flag]))
		count_lbl.add_theme_font_size_override("font_size", 12 if compact else 14)
		count_lbl.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35) if is_skipped else (Color(1.0, 0.85, 0.35) if is_active else Color(0.75, 0.90, 1.0)))
		hbox.add_child(count_lbl)

		badge.add_child(hbox)
		opponent_badges_root.add_child(badge)

		# Position badge outside the stadium table rim via Camera3D projection
		var rel_idx = ((p_seat - my_seat) % total_players + total_players) % total_players
		var ang = PI * 0.5 + float(rel_idx) * TAU / float(total_players)
		var rx = vp_size.x * 0.42
		var ry = vp_size.y * 0.36
		var cx = vp_size.x * 0.5 + cos(ang) * rx
		var cy = vp_size.y * 0.43 + sin(ang) * ry
		if active_table_3d != null and active_table_3d.has_method("get_camera"):
			var cam: Camera3D = active_table_3d.get_camera()
			var seat_raw = _get_seat_3d_anchor(p_seat, total_players, my_seat)
			var radial_out = Vector3(seat_raw.x * 1.18, seat_raw.y + 0.08, seat_raw.z * 1.28)
			if cam != null and table_viewport != null and table_viewport.size.x > 0 and table_viewport.size.y > 0 and not cam.is_position_behind(radial_out):
				var vp_proj = cam.unproject_position(radial_out)
				cx = (vp_proj.x / float(table_viewport.size.x)) * vp_size.x
				cy = (vp_proj.y / float(table_viewport.size.y)) * vp_size.y
		cy = clampf(cy, 68.0, vp_size.y - 185.0)
		cx = clampf(cx, 78.0, vp_size.x - 140.0)
		badge.position = Vector2(cx - 58.0, cy - 22.0)

# --- Card Play, Wild Wheel & Animations ---

func _on_card_pressed(card_id: String, card: Dictionary) -> void:
	if str(card.get("color", "")) in ["wild", "special", "colorless"]:
		pending_wild_card_id = card_id
		if color_wheel != null and color_wheel.has_method("open_wheel"):
			color_wheel.open_wheel()
	else:
		_play_card(card_id, "", card)

func select_wild_color(chosen_color: String) -> void:
	var cid = pending_wild_card_id
	pending_wild_card_id = ""
	if color_wheel != null and color_wheel.visible:
		color_wheel.close_wheel()
	if not cid.is_empty():
		_play_card(cid, chosen_color.to_lower(), { "id": cid, "color": "wild", "value": "wild" })

func _on_color_choice_canceled() -> void:
	pending_wild_card_id = ""

func _play_card(card_id: String, chosen_color: String, visual_card: Dictionary = {}) -> void:
	if _bot_sequence_running:
		return
	var pub_before = cartridge.get_public_state()
	var from_seat = int(pub_before.get("current_turn_seat", 0))
	var action: Dictionary = {
		"type": "ACTION_PLAY_CARD",
		"card_id": card_id
	}
	if not chosen_color.is_empty():
		action["chosen_color"] = chosen_color

	var res = cartridge.handle_action(current_player_id, action)
	if res.get("success", false):
		_trigger_action_feedback(res.get("events", []), from_seat, visual_card, true)
		_post_human_turn()
	else:
		_show_status_toast(str(res.get("error", I18nServiceScript.t("hud.card_mismatch_toast"))))
	refresh_display()

func _on_draw_pile_btn_pressed() -> void:
	if _bot_sequence_running:
		return
	var pub_before = cartridge.get_public_state()
	var from_seat = int(pub_before.get("current_turn_seat", 0))
	var res = cartridge.handle_action(current_player_id, { "type": "ACTION_DRAW_CARD" })
	if res.get("success", false):
		if sfx_player != null:
			sfx_player.play_draw_pop()
		_animate_draw_to_seat(from_seat, true)
		_post_human_turn()
	else:
		_show_status_toast(str(res.get("error", I18nServiceScript.t("hud.draw_blocked_toast"))))
	refresh_display()

func _on_call_uno_button_pressed() -> void:
	cartridge.handle_action(current_player_id, { "type": "ACTION_CALL_UNO" })
	if sfx_player != null:
		sfx_player.play_uno_fanfare()
	var call_txt = I18nServiceScript.t("hud.call_last")
	if animator != null:
		animator.animate_special_callout(hud_layer, call_txt, Color(1.0, 0.35, 0.20))
	_on_emote_pressed(call_txt)
	refresh_display()

func _show_status_toast(msg: String) -> void:
	if emote_banner == null or emote_toast == null:
		return
	emote_banner.text = msg
	emote_toast.visible = true
	if is_inside_tree():
		var gen = _match_gen_id
		get_tree().create_timer(1.8).timeout.connect(func():
			if gen == _match_gen_id and is_instance_valid(emote_toast):
				emote_toast.visible = false
		)

func _on_emote_pressed(emote_text: String) -> void:
	if sfx_player != null and "Klopf" in emote_text:
		sfx_player.play_table_knock()
	if emote_banner != null and emote_toast != null:
		emote_banner.text = "%s: %s" % [current_player_id, emote_text]
		emote_toast.visible = true
		if is_inside_tree() and animator != null and animator.get_flight_duration() > 0.0:
			var gen = _match_gen_id
			get_tree().create_timer(1.8).timeout.connect(func():
				if gen == _match_gen_id and is_instance_valid(emote_toast):
					emote_toast.visible = false
			)

func _trigger_action_feedback(events: Array, seat_idx: int, fallback_card: Dictionary = {}, face_up: bool = true) -> void:
	var played_card: Dictionary = fallback_card
	var is_special = false
	for ev in events:
		if ev is Dictionary:
			if ev.has("card") and ev["card"] is Dictionary:
				played_card = ev["card"]
			var ev_type = str(ev.get("type", ""))
			if ev_type == "CARD_STACKED":
				is_special = true
				if animator != null:
					animator.animate_special_callout(hud_layer, "+%d STAPEL!" % int(ev.get("penalty", 2)), Color(1.0, 0.42, 0.16))
			elif ev_type == "PENALTY_DRAWN":
				is_special = true
				if animator != null:
					animator.animate_special_callout(hud_layer, "+%d KARTEN!" % int(ev.get("count", 2)), Color(1.0, 0.30, 0.25))
			elif ev_type == "DECK_FLIPPED":
				is_special = true
				if animator != null:
					var side = str(ev.get("active_side", "dark"))
					animator.animate_special_callout(hud_layer, "FLIP! 🌑 DUNKLE SEITE" if side == "dark" else "FLIP! ☀ HELLE SEITE", Color(0.85, 0.35, 1.0))
			elif ev_type == "SKIP_EVERYONE":
				is_special = true
				if animator != null:
					animator.animate_special_callout(hud_layer, "ALLE ÜBERSPRUNGEN ⏭", Color(0.28, 0.88, 1.0))
			elif ev_type == "DISCARD_ALL":
				is_special = true
				if animator != null:
					animator.animate_special_callout(hud_layer, "FARBE ABGELEGT! ▤", Color(0.30, 0.95, 0.55))
			elif ev_type == "PLAYER_ELIMINATED":
				is_special = true
				if animator != null:
					animator.animate_special_callout(hud_layer, "💀 KNOCKOUT (%s)!" % str(ev.get("player_id", "")), Color(1.0, 0.20, 0.20))
			elif ev_type == "PENALTY_NEGATED":
				is_special = true
				if animator != null:
					animator.animate_special_callout(hud_layer, "🛡 STRAFE ABGEWEHRT!", Color(0.25, 0.95, 0.70))
			elif ev_type == "PLAYER_SKIPPED":
				is_special = true
				_last_skipped_seat = int(ev.get("skipped_seat", -1))
				_skip_banner_time_left = 2.4
				var sk_name := str(ev.get("skipped_name", "Player"))
				if skip_banner_panel != null and skip_banner_label != null:
					skip_banner_label.text = I18nServiceScript.t("ui.game.skip_banner", { "player": sk_name })
					skip_banner_panel.visible = true
			elif ev_type == "PLAYER_FINISHED":
				is_special = true
				_show_status_toast(I18nServiceScript.t("ui.game.player_finished_toast", {
					"player": str(ev.get("name", ev.get("player_id", ""))),
					"place": int(ev.get("placement", 1))
				}))

	var val_str = str(played_card.get("value", "")).to_lower()
	if val_str in ["skip", "skip_everyone", "reverse", "draw_two", "draw_four", "draw_five", "wild", "wild_draw_four", "wild_reverse_draw_four", "wild_draw_six", "wild_draw_ten", "flip", "discard_all"]:
		is_special = true
		if animator != null:
			match val_str:
				"skip": animator.animate_special_callout(hud_layer, "AUSSETZEN ⊘", Color(0.95, 0.35, 0.35))
				"reverse": animator.animate_special_callout(hud_layer, "RICHTUNGSWECHSEL ⇄", Color(0.28, 0.80, 1.0))
				"draw_two": animator.animate_special_callout(hud_layer, "+2 ZIEHEN!", Color(1.0, 0.65, 0.15))
				"draw_four", "wild_reverse_draw_four": animator.animate_special_callout(hud_layer, "+4 BRUTAL!", Color(1.0, 0.40, 0.16))
				"draw_five": animator.animate_special_callout(hud_layer, "+5 DUNKEL!", Color(0.96, 0.25, 0.65))
				"wild_draw_six": animator.animate_special_callout(hud_layer, "+6 GNADENLOS!", Color(1.0, 0.25, 0.35))
				"wild_draw_ten": animator.animate_special_callout(hud_layer, "+10 GNADENLOS!!", Color(1.0, 0.15, 0.22))
				"wild_draw_four": animator.animate_special_callout(hud_layer, "+4 FARBWAHL!", Color(0.82, 0.36, 1.0))

	if sfx_player != null:
		sfx_player.play_card_swoosh()
		if is_special:
			sfx_player.play_special_impact()
		else:
			sfx_player.play_card_snap()

	if animator != null and active_table_3d != null and discard_pile_3d_root != null:
		var total_p = maxi(2, cartridge.players.size()) if cartridge != null else 4
		var from_pos = _get_seat_3d_anchor(seat_idx, total_p, 0) + Vector3(0.0, 0.08, 0.0)
		var to_pos = discard_pile_3d_root.global_position + Vector3(0.0, 0.025, 0.0)
		var to_rot = Vector3(0.0, _rng_visual.randf_range(-14.0, 14.0), 0.0)
		animator.animate_3d_card_arc(active_table_3d, CardMeshScene, played_card, from_pos, to_pos, to_rot, Vector3.ONE * 2.15, active_card_skin, colorblind_mode, face_up)

func _animate_draw_to_seat(seat_idx: int, face_up: bool) -> void:
	if animator == null or active_table_3d == null or draw_pile_3d_root == null:
		return
	var total_p = maxi(2, cartridge.players.size()) if cartridge != null else 4
	var from_pos = draw_pile_3d_root.global_position + Vector3(0.0, 0.03, 0.0)
	var to_pos = _get_seat_3d_anchor(seat_idx, total_p, 0) + Vector3(0.0, 0.08, 0.0)
	animator.animate_3d_card_arc(active_table_3d, CardMeshScene, { "masked": true }, from_pos, to_pos, Vector3(45.0, 0.0, 0.0 if face_up else 180.0), Vector3.ONE * 1.9, active_card_skin, colorblind_mode, false)

# --- Paced Bot Turn Sequencer ---

func _post_human_turn() -> void:
	if cartridge == null or cartridge.is_round_over():
		return

	var bot_delay = animator.get_bot_delay() if animator != null else 0.0
	if bot_delay <= 0.0 or not is_inside_tree() or _bot_turn_timer == null:
		_run_bot_turns_sync()
		_finish_turn_cycle()
	else:
		var pub = cartridge.get_public_state()
		var turn_seat = int(pub.get("current_turn_seat", 0))
		var active_player = cartridge.get_player_by_seat(turn_seat)
		if bool(active_player.get("is_bot", false)):
			_bot_sequence_running = true
			_bot_turn_timer.start(bot_delay)
		else:
			_finish_turn_cycle()

func _run_bot_turns_sync() -> void:
	for _i in range(64):
		if cartridge.is_round_over():
			break
		var pub = cartridge.get_public_state()
		var turn_seat = int(pub.get("current_turn_seat", 0))
		var active_player = cartridge.get_player_by_seat(turn_seat)
		if bool(active_player.get("is_bot", false)):
			var pid = str(active_player.get("player_id", ""))
			var bot_act = cartridge.get_bot_action(pid, active_bot_difficulty)
			cartridge.handle_action(pid, bot_act)
		else:
			break

func _has_local_challenge_opportunity() -> bool:
	if cartridge == null:
		return false
	for hid in _local_human_ids:
		if cartridge.can_challenge_plus_four(hid):
			return true
	return false

func _on_bot_turn_timer_timeout() -> void:
	if cartridge == null or cartridge.is_round_over() or not is_inside_tree():
		_bot_sequence_running = false
		_finish_turn_cycle()
		return

	var pub = cartridge.get_public_state()
	var turn_seat = int(pub.get("current_turn_seat", 0))
	var active_player = cartridge.get_player_by_seat(turn_seat)
	if not bool(active_player.get("is_bot", false)):
		_bot_sequence_running = false
		_finish_turn_cycle()
		return

	var pid = str(active_player.get("player_id", ""))
	var bot_act = cartridge.get_bot_action(pid, active_bot_difficulty)
	var res = cartridge.handle_action(pid, bot_act)
	if res.get("success", false):
		if str(bot_act.get("type", "")) == "ACTION_DRAW_CARD":
			if sfx_player != null:
				sfx_player.play_draw_pop()
			_animate_draw_to_seat(turn_seat, false)
		else:
			_trigger_action_feedback(res.get("events", []), turn_seat, cartridge.get_top_discard(), true)
	refresh_display()

	if cartridge.is_round_over():
		_bot_sequence_running = false
		return

	var next_pub = cartridge.get_public_state()
	var next_seat = int(next_pub.get("current_turn_seat", 0))
	var next_p = cartridge.get_player_by_seat(next_seat)
	var bot_delay = animator.get_bot_delay() if animator != null else 0.0
	if bool(next_p.get("is_bot", false)):
		if bot_delay > 0.0:
			var reaction_open := (center_reaction_panel != null and center_reaction_panel.visible) or (_skip_banner_time_left > 0.0)
			var need_pause = (not cartridge.get_catchable_uno_players("").is_empty()) or _has_local_challenge_opportunity() or reaction_open
			_bot_turn_timer.start(maxf(bot_delay, 2.2) if need_pause else bot_delay)
		else:
			_run_bot_turns_sync()
			_bot_sequence_running = false
			_finish_turn_cycle()
	else:
		_bot_sequence_running = false
		_finish_turn_cycle()

func _finish_turn_cycle() -> void:
	if cartridge == null or cartridge.is_round_over():
		refresh_display()
		return
	var pub = cartridge.get_public_state()
	var next_seat = int(pub.get("current_turn_seat", 0))
	var next_p = cartridge.get_player_by_seat(next_seat)
	var next_pid = str(next_p.get("player_id", current_player_id))
	if next_pid in _local_human_ids:
		var use_curtain = (_local_human_ids.size() > 1 and active_view_mode != "table_role")
		current_player_id = next_pid
		if use_curtain and next_pid != _last_revealed_human_id and pass_and_play_ctrl != null:
			pass_and_play_ctrl.advance_to_seat(next_seat, next_pid, false)
	refresh_display()

func _on_sort_hand_btn_pressed() -> void:
	if cartridge == null:
		return
	cartridge.handle_action(current_player_id, { "type": "ACTION_SORT_HAND", "mode": "auto" })
	refresh_display()

func _on_shuffle_hand_btn_pressed() -> void:
	if cartridge == null:
		return
	cartridge.handle_action(current_player_id, { "type": "ACTION_SHUFFLE_HAND" })
	refresh_display()

func _on_catch_uno_btn_pressed() -> void:
	if cartridge == null:
		return
	var candidates = cartridge.get_catchable_uno_players(current_player_id)
	if candidates.is_empty():
		return
	var target_id = str(candidates[0].get("player_id", ""))
	var target_name = str(candidates[0].get("name", target_id))
	var res = cartridge.handle_action(current_player_id, { "type": "ACTION_CATCH_UNO", "target_player_id": target_id })
	if res.get("success", false):
		_show_status_toast(I18nServiceScript.t("hud.uno_caught_toast", { "target": target_name, "count": 2 }))
		if sfx_player != null:
			sfx_player.play_special_impact()
	refresh_display()

func _on_challenge_plus_four_btn_pressed() -> void:
	if cartridge == null:
		return
	var res = cartridge.handle_action(current_player_id, { "type": "ACTION_CHALLENGE_PLUS_FOUR" })
	if res.get("success", false):
		_show_challenge_reveal_overlay(res)
		_finish_turn_cycle()
	else:
		_show_status_toast(str(res.get("error", "")))
		refresh_display()

func _show_challenge_reveal_overlay(res: Dictionary) -> void:
	if challenge_reveal_overlay == null:
		return
	var won = bool(res.get("challenge_won", false))
	var offender_name = str(res.get("offender_name", res.get("offender_id", "Player")))
	var challenger_id = str(res.get("challenger_id", current_player_id))
	var challenger_p = cartridge.player_map.get(challenger_id, {}) if cartridge != null else {}
	var challenger_name = str(challenger_p.get("name", challenger_id))
	var applied = int(res.get("penalty_applied", 4))

	if challenge_result_title != null:
		if won:
			challenge_result_title.text = I18nServiceScript.t("hud.challenge_won_title", { "offender": offender_name, "count": applied })
		else:
			challenge_result_title.text = I18nServiceScript.t("hud.challenge_lost_title", { "challenger": challenger_name, "count": applied })
	if challenge_result_subtitle != null:
		challenge_result_subtitle.text = I18nServiceScript.t("hud.challenge_hand_subtitle", { "offender": offender_name })

	if revealed_cards_row != null:
		for child in revealed_cards_row.get_children():
			child.queue_free()
		var revealed: Array = res.get("offender_hand", [])
		for c_dict in revealed:
			if not (c_dict is Dictionary):
				continue
			var frame = PanelContainer.new()
			var guilty = bool(c_dict.get("could_have_played", false))
			var border_col = Color(1.0, 0.84, 0.16, 1.0) if guilty else Color(0.28, 0.42, 0.62, 0.65)
			frame.add_theme_stylebox_override("panel", UIThemeScript.make_glass_panel(Color(0.06, 0.09, 0.16, 0.95), border_col, 10, 6))
			var tex_rect = TextureRect.new()
			tex_rect.custom_minimum_size = Vector2(96, 136)
			tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex_rect.texture = CardTextureGenScript.get_card_front_texture(c_dict, active_card_skin, colorblind_mode)
			if not guilty:
				tex_rect.modulate = Color(0.75, 0.78, 0.85, 0.90)
			frame.add_child(tex_rect)
			revealed_cards_row.add_child(frame)

	challenge_reveal_overlay.visible = true

func _on_close_challenge_overlay_pressed() -> void:
	if challenge_reveal_overlay != null:
		challenge_reveal_overlay.visible = false
	if cartridge != null and not cartridge.is_round_over():
		var pub = cartridge.get_public_state()
		var cur_p = cartridge.get_player_by_seat(int(pub.get("current_turn_seat", 0)))
		if bool(cur_p.get("is_bot", false)):
			_post_human_turn()

func execute_remote_player_action(player_id: String, action_type: String, payload: Dictionary = {}) -> Dictionary:
	if cartridge == null:
		return { "success": false, "error": "No active match" }
	if action_type == "ACTION_SEND_EMOTE":
		var emote_id = str(payload.get("emote_id", "👋"))
		_on_emote_pressed(emote_id)
		return { "success": true }

	var act: Dictionary = { "type": action_type }
	for k in payload.keys():
		act[k] = payload[k]

	var pub_before = cartridge.get_public_state()
	var turn_before = int(pub_before.get("current_turn_seat", 0))
	var res = cartridge.handle_action(player_id, act)
	if res.get("success", false):
		if action_type == "ACTION_PLAY_CARD":
			_trigger_action_feedback(res.get("events", []), turn_before, cartridge.get_top_discard(), true)
		elif action_type == "ACTION_DRAW_CARD":
			if sfx_player != null:
				sfx_player.play_draw_pop()
			_animate_draw_to_seat(turn_before, false)
		elif action_type == "ACTION_CALL_UNO":
			if sfx_player != null:
				sfx_player.play_uno_fanfare()
		elif action_type == "ACTION_CHALLENGE_PLUS_FOUR" and _local_human_ids.size() > 0:
			_show_challenge_reveal_overlay(res)
		_post_human_turn()
	refresh_display()
	return res

func _check_round_over() -> void:
	if cartridge == null or not cartridge.is_round_over():
		return
	var res = cartridge.get_round_results()
	var winner_id = str(res.get("winner_player_id", ""))
	var score = int(res.get("score_earned", 0))
	if round_over_overlay != null:
		round_over_overlay.visible = true
		if winner_label != null:
			var win_p = cartridge.player_map.get(winner_id, {})
			var win_name = str(win_p.get("name", winner_id))
			var base_win_txt := I18nServiceScript.t("hud.round_over_win", {"player": win_name, "score": score})
			var placements: Array = res.get("placements", [])
			if not placements.is_empty():
				var lines: Array[String] = [base_win_txt, "", I18nServiceScript.t("ui.game.podium_header")]
				for idx in range(placements.size()):
					var pid := str(placements[idx])
					var p_name := str(cartridge.player_map.get(pid, {}).get("name", pid))
					lines.append("#%d  %s" % [idx + 1, p_name])
				winner_label.text = "\n".join(lines)
			else:
				winner_label.text = base_win_txt
	if not _round_recorded and stats_svc != null:
		_round_recorded = true
		if sfx_player != null:
			sfx_player.play_uno_fanfare()
		var elapsed = maxi(1, int(Time.get_unix_time_from_system()) - _match_start_unix)
		stats_svc.record_match_result({
			"game_id": "uno",
			"my_player_id": "p0",
			"winner_id": winner_id,
			"duration_seconds": elapsed
		})

# --- Signals & Quick Controls ---

func _on_play_again_pressed() -> void:
	configure_match(_last_options)

func _on_back_button_pressed() -> void:
	_match_gen_id += 1
	_bot_sequence_running = false
	if _bot_turn_timer != null:
		_bot_turn_timer.stop()
	if sfx_player != null:
		sfx_player.stop_ambient_lounge()
	back_requested.emit()

func _on_settings_toggle_pressed() -> void:
	if quick_drawer != null:
		quick_drawer.visible = not quick_drawer.visible

func _on_cycle_view_mode_pressed() -> void:
	var idx = VALID_VIEW_MODES.find(active_view_mode)
	var next_idx = (idx + 1) % VALID_VIEW_MODES.size()
	set_view_mode(VALID_VIEW_MODES[next_idx])

func _on_view_mode_option_selected(index: int) -> void:
	if view_mode_option != null:
		set_view_mode(str(view_mode_option.get_item_metadata(index)))

func _on_skin_option_selected(index: int) -> void:
	if skin_option != null:
		set_card_skin(str(skin_option.get_item_metadata(index)))

func _on_theme_option_selected(index: int) -> void:
	if theme_option != null:
		set_table_theme(str(theme_option.get_item_metadata(index)))

func _on_speed_option_selected(index: int) -> void:
	if speed_option != null:
		set_bot_speed(str(speed_option.get_item_metadata(index)))

func _on_quality_option_selected(index: int) -> void:
	if quality_option != null:
		set_quality_preset(str(quality_option.get_item_metadata(index)))

func _on_colorblind_toggled(toggled_on: bool) -> void:
	colorblind_mode = toggled_on
	refresh_display()
