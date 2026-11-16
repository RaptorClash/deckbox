# uno_game.gd
# Godot 4 Control + Full 3D Table SubViewport Scene for UNO Gameplay
extends Control

signal back_requested

const UnoCartridgeScript = preload("res://games/uno/uno_cartridge.gd")
const PassAndPlayScript = preload("res://core/qol/pass_and_play.gd")
const AccessibilitySymbolsScript = preload("res://core/qol/accessibility_symbols.gd")
const StatsServiceScript = preload("res://core/stats/stats_service.gd")
const CardMeshScene = preload("res://assets/3d/card_rounded.glb")

const TABLE_SCENES: Dictionary = {
	"arcade_ps5": "res://scenes/tables/arcade_ps5.tscn",
	"cozy_wood": "res://scenes/tables/cozy_wood.tscn",
	"clean_25d": "res://scenes/tables/clean_25d.tscn"
}

const CARD_COLORS: Dictionary = {
	"red": Color(0.86, 0.16, 0.18),
	"blue": Color(0.14, 0.42, 0.90),
	"green": Color(0.14, 0.68, 0.30),
	"yellow": Color(0.88, 0.70, 0.08),
	"wild": Color(0.32, 0.22, 0.48)
}

var cartridge: RefCounted = null
var pass_and_play_ctrl: RefCounted = null
var stats_svc: RefCounted = null

var current_player_id: String = "p0"
var match_mode: String = "solo"
var active_theme_id: String = "arcade_ps5"
var active_quality_preset: String = "high"
var colorblind_mode: bool = true
var pending_wild_card_id: String = ""

var active_table_3d: Node3D = null
var direction_ring_3d: Node3D = null
var draw_pile_3d_root: Node3D = null
var discard_pile_3d_root: Node3D = null
var opponent_hands_3d_root: Node3D = null
var player_hand_3d_root: Node3D = null
var seat_turn_beacon_3d: OmniLight3D = null
var _discard_3d_card: Node3D = null
var _draw_3d_card: Node3D = null
var _ring_mesh_instance: MeshInstance3D = null
var _turn_direction: int = 1

var _match_start_unix: int = 0
var _round_recorded: bool = false
var _last_options: Dictionary = {}

@onready var discard_label: Label = $VBoxContainer/TableArea/CenterTable/DiscardCard/DiscardLabel
@onready var discard_card_panel: PanelContainer = $VBoxContainer/TableArea/CenterTable/DiscardCard
@onready var draw_pile_btn: Button = $VBoxContainer/TableArea/CenterTable/DrawPileBtn
@onready var turn_label: Label = $VBoxContainer/Header/TurnLabel
@onready var hand_container: HBoxContainer = $VBoxContainer/PlayerArea/HandScroll/HandContainer
@onready var uno_call_btn: Button = $VBoxContainer/PlayerArea/ActionButtons/CallUnoButton
@onready var opponents_container: HBoxContainer = $VBoxContainer/OpponentsArea/OpponentsContainer
@onready var color_choice_dialog: ConfirmationDialog = $ColorChoiceDialog
@onready var table_viewport: SubViewport = $VBoxContainer/TableArea/TableViewportContainer/SubViewport
@onready var theme_option: OptionButton = $VBoxContainer/Header/ThemeOption
@onready var quality_option: OptionButton = $VBoxContainer/Header/QualityOption
@onready var colorblind_btn: CheckButton = $VBoxContainer/Header/ColorblindBtn
@onready var emote_banner: Label = $VBoxContainer/TableArea/EmoteBanner
@onready var curtain_overlay: PanelContainer = $CurtainOverlay
@onready var curtain_title: Label = $CurtainOverlay/CurtainBox/CurtainTitle
@onready var round_over_overlay: PanelContainer = $RoundOverOverlay
@onready var winner_label: Label = $RoundOverOverlay/RoundBox/WinnerLabel

func _ready() -> void:
	pass_and_play_ctrl = PassAndPlayScript.new()
	stats_svc = StatsServiceScript.new()
	stats_svc.load_stats()
	_init_header_controls()
	configure_match({ "mode": "solo", "theme": active_theme_id, "quality": active_quality_preset })

func _process(delta: float) -> void:
	if direction_ring_3d != null and is_instance_valid(direction_ring_3d):
		direction_ring_3d.rotate_y(-float(_turn_direction) * delta * 0.85)

func _init_header_controls() -> void:
	if theme_option != null:
		theme_option.clear()
		theme_option.add_item("Arcade PS5", 0)
		theme_option.set_item_metadata(0, "arcade_ps5")
		theme_option.add_item("Cozy Wood", 1)
		theme_option.set_item_metadata(1, "cozy_wood")
		theme_option.add_item("Clean 2.5D", 2)
		theme_option.set_item_metadata(2, "clean_25d")

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
	_last_options = options.duplicate(true)
	match_mode = str(options.get("mode", "solo"))
	var theme_id = str(options.get("theme", active_theme_id))
	var quality = str(options.get("quality", active_quality_preset))
	var rules = options.get("rules", {})
	if options.has("colorblind_mode"):
		colorblind_mode = bool(options["colorblind_mode"])
		if colorblind_btn != null:
			colorblind_btn.set_pressed_no_signal(colorblind_mode)

	cartridge = UnoCartridgeScript.new()
	var players: Array[Dictionary] = []
	if options.has("players") and options["players"] is Array and not options["players"].is_empty():
		for p in options["players"]:
			if p is Dictionary:
				players.append(p)
	elif match_mode == "pass_and_play":
		var p_count = clampi(int(options.get("player_count", 2)), 2, 4)
		for i in range(p_count):
			players.append({
				"player_id": "p%d" % i,
				"seat": i,
				"name": "Player %d" % (i + 1),
				"is_bot": false
			})
	else:
		players = [
			{ "player_id": "p0", "seat": 0, "name": str(options.get("player_name", "You")), "is_bot": false },
			{ "player_id": "p1", "seat": 1, "name": "Bot 1", "is_bot": true },
			{ "player_id": "p2", "seat": 2, "name": "Bot 2", "is_bot": true },
			{ "player_id": "p3", "seat": 3, "name": "Bot 3", "is_bot": true }
		]

	var match_seed = int(options.get("seed", Time.get_unix_time_from_system()))
	cartridge.init_match("match_ui_%d" % match_seed, players, rules if rules is Dictionary else {}, match_seed)
	cartridge.start_round()

	current_player_id = str(players[0].get("player_id", "p0"))
	pending_wild_card_id = ""
	_round_recorded = false
	_match_start_unix = int(Time.get_unix_time_from_system())

	if round_over_overlay != null:
		round_over_overlay.visible = false

	if pass_and_play_ctrl != null:
		pass_and_play_ctrl.init_session(players, 0)
		if match_mode != "pass_and_play":
			pass_and_play_ctrl.request_reveal(current_player_id)

	set_table_theme(theme_id)
	set_quality_preset(quality)
	refresh_display()

func set_table_theme(theme_id: String) -> void:
	if not TABLE_SCENES.has(theme_id):
		theme_id = "arcade_ps5"
	active_theme_id = theme_id

	if theme_option != null:
		for i in range(theme_option.item_count):
			if str(theme_option.get_item_metadata(i)) == theme_id:
				theme_option.select(i)
				break

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
		_discard_3d_card = null
		_draw_3d_card = null
		_ring_mesh_instance = null

	var scene_path = TABLE_SCENES[theme_id]
	if ResourceLoader.exists(scene_path):
		var packed = load(scene_path)
		if packed is PackedScene:
			var inst = packed.instantiate()
			if inst is Node3D:
				active_table_3d = inst
				table_viewport.add_child(active_table_3d)
				if active_table_3d.has_method("apply_quality_preset"):
					active_table_3d.apply_quality_preset(active_quality_preset)
				_setup_3d_table_elements()
				if cartridge != null:
					_sync_3d_table_state(cartridge.get_public_state(), cartridge.get_player_view(current_player_id))

func set_quality_preset(preset: String) -> void:
	active_quality_preset = preset.to_lower()
	if quality_option != null:
		for i in range(quality_option.item_count):
			if str(quality_option.get_item_metadata(i)) == active_quality_preset:
				quality_option.select(i)
				break
	if active_table_3d != null and active_table_3d.has_method("apply_quality_preset"):
		active_table_3d.apply_quality_preset(active_quality_preset)

func _setup_3d_table_elements() -> void:
	if active_table_3d == null or CardMeshScene == null:
		return

	var draw_pos = Vector3(-0.18, 0.755, 0.0)
	var discard_pos = Vector3(0.18, 0.755, 0.0)
	if active_table_3d.has_method("get_draw_pile_position"):
		draw_pos = active_table_3d.get_draw_pile_position()
	if active_table_3d.has_method("get_discard_pile_position"):
		discard_pos = active_table_3d.get_discard_pile_position()

	# 1. 3D Turn Direction Ring around center piles
	direction_ring_3d = Node3D.new()
	direction_ring_3d.name = "DirectionRing3D"
	direction_ring_3d.position = Vector3(0.0, draw_pos.y + 0.004, 0.0)
	active_table_3d.add_child(direction_ring_3d)

	_ring_mesh_instance = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 0.34
	torus.outer_radius = 0.38
	torus.rings = 32
	torus.ring_segments = 16
	_ring_mesh_instance.mesh = torus
	direction_ring_3d.add_child(_ring_mesh_instance)

	# Add 4 directional orbs on the ring so rotation is clearly visible in 3D
	for i in range(4):
		var marker_orb = MeshInstance3D.new()
		var sphere = SphereMesh.new()
		sphere.radius = 0.022
		sphere.height = 0.044
		marker_orb.mesh = sphere
		var angle = float(i) * PI * 0.5
		marker_orb.position = Vector3(cos(angle) * 0.36, 0.01, sin(angle) * 0.36)
		direction_ring_3d.add_child(marker_orb)

	# 2. 3D Draw Pile Stack
	draw_pile_3d_root = Node3D.new()
	draw_pile_3d_root.name = "DrawPile3DStack"
	draw_pile_3d_root.position = draw_pos
	active_table_3d.add_child(draw_pile_3d_root)

	for i in range(8):
		var stack_card = CardMeshScene.instantiate()
		if stack_card != null:
			stack_card.position = Vector3(0.0, 0.008 + float(i) * 0.004, 0.0)
			stack_card.rotation_degrees = Vector3(-90.0, float(i % 3 - 1) * 1.5, 180.0)
			stack_card.scale = Vector3.ONE * 2.4
			_tint_card_instance(stack_card, Color(0.10, 0.18, 0.42), 1)
			draw_pile_3d_root.add_child(stack_card)
			_draw_3d_card = stack_card

	# 3. 3D Discard Pile Stack
	discard_pile_3d_root = Node3D.new()
	discard_pile_3d_root.name = "DiscardPile3DStack"
	discard_pile_3d_root.position = discard_pos
	active_table_3d.add_child(discard_pile_3d_root)

	for i in range(3):
		var base_discard = CardMeshScene.instantiate()
		if base_discard != null:
			base_discard.position = Vector3(0.0, 0.008 + float(i) * 0.004, 0.0)
			base_discard.rotation_degrees = Vector3(-90.0, float(i * 12 - 12), 0.0)
			base_discard.scale = Vector3.ONE * 2.4
			discard_pile_3d_root.add_child(base_discard)
			_discard_3d_card = base_discard

	# 4. 3D Opponent Card Fans Root & Player 3D Hand Root
	opponent_hands_3d_root = Node3D.new()
	opponent_hands_3d_root.name = "OpponentHands3DRoot"
	active_table_3d.add_child(opponent_hands_3d_root)

	player_hand_3d_root = Node3D.new()
	player_hand_3d_root.name = "PlayerHand3DRoot"
	active_table_3d.add_child(player_hand_3d_root)

	# 5. Active Seat Spotlight Beacon
	seat_turn_beacon_3d = OmniLight3D.new()
	seat_turn_beacon_3d.name = "SeatTurnBeacon3D"
	seat_turn_beacon_3d.light_energy = 1.6
	seat_turn_beacon_3d.omni_range = 1.4
	seat_turn_beacon_3d.position = Vector3(0.0, 1.15, 0.6)
	active_table_3d.add_child(seat_turn_beacon_3d)

	_update_3d_discard_tint("wild")

func _sync_3d_table_state(pub_state: Dictionary, my_view: Dictionary) -> void:
	if active_table_3d == null or CardMeshScene == null:
		return

	_turn_direction = int(pub_state.get("direction", 1))

	# Scale draw pile stack visibility based on remaining cards
	if draw_pile_3d_root != null:
		var draw_count = int(pub_state.get("draw_pile_count", 0))
		var visible_layers = clampi(int(ceil(float(draw_count) / 10.0)), 1 if draw_count > 0 else 0, draw_pile_3d_root.get_child_count())
		for i in range(draw_pile_3d_root.get_child_count()):
			var child = draw_pile_3d_root.get_child(i)
			if child is Node3D:
				child.visible = (i < visible_layers)

	# Update 3D Opponent Card Fans at Seats 1, 2, 3
	if opponent_hands_3d_root != null:
		for child in opponent_hands_3d_root.get_children():
			opponent_hands_3d_root.remove_child(child)
			child.queue_free()

		var players_list = pub_state.get("players", [])
		for p in players_list:
			var seat_idx = int(p.get("seat", 0))
			var full_p = cartridge.get_player_by_seat(seat_idx) if cartridge != null else p
			var pid = str(full_p.get("player_id", ""))
			if pid == current_player_id and seat_idx == 0:
				continue

			var seat_pos = _get_seat_3d_anchor(seat_idx)
			var fan_holder = Node3D.new()
			fan_holder.name = "SeatFan_%d" % seat_idx
			fan_holder.position = seat_pos
			opponent_hands_3d_root.add_child(fan_holder)
			fan_holder.look_at(Vector3(0.0, seat_pos.y, 0.0), Vector3.UP)

			var c_count = clampi(int(p.get("card_count", 0)), 0, 10)
			for c_idx in range(c_count):
				var card_3d = CardMeshScene.instantiate()
				if card_3d != null:
					var offset_norm = float(c_idx) - float(maxi(0, c_count - 1)) * 0.5
					card_3d.position = Vector3(offset_norm * 0.055, 0.07, abs(offset_norm) * 0.008)
					card_3d.rotation_degrees = Vector3(-25.0, 180.0, -offset_norm * 5.0)
					card_3d.scale = Vector3.ONE * 1.9
					_tint_card_instance(card_3d, Color(0.12, 0.20, 0.48), 1)
					fan_holder.add_child(card_3d)

	# Update 3D Player Hand Fan at Seat 0
	if player_hand_3d_root != null:
		for child in player_hand_3d_root.get_children():
			player_hand_3d_root.remove_child(child)
			child.queue_free()

		var seat0_pos = _get_seat_3d_anchor(0)
		var hand_cards = my_view.get("hand", [])
		var hand_len = mini(hand_cards.size(), 12)
		for idx in range(hand_len):
			var c_data = hand_cards[idx]
			var c_node = CardMeshScene.instantiate()
			if c_node != null:
				var off = float(idx) - float(maxi(0, hand_len - 1)) * 0.5
				c_node.position = seat0_pos + Vector3(off * 0.075, 0.05, abs(off) * 0.01)
				var is_masked = bool(c_data.get("masked", false))
				c_node.rotation_degrees = Vector3(-45.0, 180.0 if is_masked else 0.0, -off * 4.0)
				c_node.scale = Vector3.ONE * 2.0
				var c_col_name = str(c_data.get("color", "wild")).to_lower()
				var tint_col: Color = CARD_COLORS.get(c_col_name, CARD_COLORS["wild"])
				_tint_card_instance(c_node, tint_col, 0)
				player_hand_3d_root.add_child(c_node)

	# Move active seat turn beacon to highlight whose turn it is on the 3D table
	if seat_turn_beacon_3d != null:
		var active_seat = int(pub_state.get("current_turn_seat", 0))
		var target_seat_pos = _get_seat_3d_anchor(active_seat)
		seat_turn_beacon_3d.position = target_seat_pos + Vector3(0.0, 0.35, 0.0)

func _get_seat_3d_anchor(seat_index: int) -> Vector3:
	if active_table_3d != null and active_table_3d.has_method("get_seat_position"):
		var pos = active_table_3d.get_seat_position(seat_index)
		if pos != Vector3.ZERO:
			return pos
	match seat_index % 4:
		0: return Vector3(0.0, 0.755, 0.58)
		1: return Vector3(-0.92, 0.755, 0.0)
		2: return Vector3(0.0, 0.755, -0.55)
		_: return Vector3(0.92, 0.755, 0.0)

func _tint_card_instance(card_root: Node, tint: Color, surface_idx: int = 0) -> void:
	var mesh_node = _find_first_mesh_instance(card_root)
	if mesh_node == null or mesh_node.mesh == null:
		return
	var mat = StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.roughness = 0.32
	if surface_idx < mesh_node.mesh.get_surface_count():
		mesh_node.set_surface_override_material(surface_idx, mat)
	else:
		mesh_node.set_surface_override_material(0, mat)

func _update_3d_discard_tint(color_name: String) -> void:
	var tint: Color = CARD_COLORS.get(color_name.to_lower(), CARD_COLORS["wild"])
	if _discard_3d_card != null:
		_tint_card_instance(_discard_3d_card, tint, 0)

	if _ring_mesh_instance != null:
		var ring_mat = StandardMaterial3D.new()
		ring_mat.albedo_color = tint
		ring_mat.emission_enabled = true
		ring_mat.emission = tint
		ring_mat.emission_energy_multiplier = 1.8
		ring_mat.roughness = 0.25
		_ring_mesh_instance.material_override = ring_mat

		if direction_ring_3d != null:
			for child in direction_ring_3d.get_children():
				if child is MeshInstance3D and child != _ring_mesh_instance:
					child.material_override = ring_mat

	if seat_turn_beacon_3d != null:
		seat_turn_beacon_3d.light_color = tint.lightened(0.25)

func _find_first_mesh_instance(root: Node) -> MeshInstance3D:
	if root is MeshInstance3D:
		return root
	for child in root.get_children():
		var found = _find_first_mesh_instance(child)
		if found != null:
			return found
	return null

func reveal_pass_and_play() -> void:
	if pass_and_play_ctrl != null:
		pass_and_play_ctrl.request_reveal(current_player_id)
	refresh_display()

func refresh_display() -> void:
	if cartridge == null:
		return

	var pub_state = cartridge.get_public_state()
	var my_view = cartridge.get_player_view(current_player_id)
	if match_mode == "pass_and_play" and pass_and_play_ctrl != null:
		my_view = pass_and_play_ctrl.filter_view_for_curtain(my_view)

	# Update Curtain Overlay visibility
	if curtain_overlay != null:
		var show_curtain = (match_mode == "pass_and_play" and pass_and_play_ctrl != null and pass_and_play_ctrl.is_curtain_active() and not cartridge.is_round_over())
		curtain_overlay.visible = show_curtain
		if show_curtain and curtain_title != null:
			var active_p = cartridge.get_player_by_seat(int(pub_state.get("current_turn_seat", 0)))
			curtain_title.text = "Pass Device to %s" % str(active_p.get("name", current_player_id))

	# Update Top Discard & Active Color
	var top = pub_state.get("top_discard", {})
	var raw_col = str(top.get("color", "wild")).to_lower()
	var eff_col = str(pub_state.get("active_color", "")).to_lower()
	var display_col = eff_col if not eff_col.is_empty() else raw_col
	var sym = AccessibilitySymbolsScript.get_char(display_col) if colorblind_mode else ""
	var val = str(top.get("value", "-")).to_upper()
	if discard_label != null:
		var active_hint = " -> %s" % eff_col.to_upper() if (not eff_col.is_empty() and raw_col == "wild") else ""
		discard_label.text = "%s%s\n%s%s" % [raw_col.to_upper(), active_hint, val, (" " + sym) if not sym.is_empty() else ""]
	if discard_card_panel != null:
		_apply_card_panel_style(discard_card_panel, display_col, false)
	_update_3d_discard_tint(display_col)
	_sync_3d_table_state(pub_state, my_view)

	# Update Draw Pile Button
	if draw_pile_btn != null:
		var pen = int(pub_state.get("pending_penalty_draws", 0))
		var pen_suffix = "\n(+%d)" % pen if pen > 0 else ""
		draw_pile_btn.text = "Draw Card\n(%d)%s" % [int(pub_state.get("draw_pile_count", 0)), pen_suffix]

	# Update Turn Indicator
	if turn_label != null:
		var turn_s = int(pub_state.get("current_turn_seat", 0))
		var active_p = cartridge.get_player_by_seat(turn_s)
		var dir_text = "CW ↻" if int(pub_state.get("direction", 1)) == 1 else "CCW ↺"
		turn_label.text = "Turn: %s (Seat %d | %s)" % [str(active_p.get("name", "Player")), turn_s, dir_text]

	# Update Hand Cards
	if hand_container != null:
		for child in hand_container.get_children():
			child.queue_free()

		var hand = my_view.get("hand", [])
		for card in hand:
			var btn = Button.new()
			btn.custom_minimum_size = Vector2(82, 114)
			if bool(card.get("masked", false)):
				btn.text = "HIDDEN"
				btn.disabled = true
				_apply_card_button_style(btn, "wild", false)
			else:
				var c_id = str(card.get("id", ""))
				var c_col = str(card.get("color", "wild")).to_lower()
				var c_val = str(card.get("value", "")).to_upper()
				var c_sym = AccessibilitySymbolsScript.get_char(c_col) if colorblind_mode else ""
				var playable = bool(card.get("playable", false))
				btn.text = "%s %s\n%s" % [c_col.to_upper(), c_sym, c_val]
				btn.tooltip_text = AccessibilitySymbolsScript.get_accessible_label(card)
				btn.disabled = not playable
				_apply_card_button_style(btn, c_col, playable)
				btn.pressed.connect(_on_card_pressed.bind(c_id, card))
			hand_container.add_child(btn)

	# Update Opponents
	if opponents_container != null:
		for child in opponents_container.get_children():
			child.queue_free()

		var players_list = pub_state.get("players", [])
		var active_turn_seat = int(pub_state.get("current_turn_seat", 0))
		for p in players_list:
			var p_seat = int(p.get("seat", 0))
			var full_p = cartridge.get_player_by_seat(p_seat)
			if str(full_p.get("player_id", "")) != current_player_id:
				var panel = PanelContainer.new()
				_apply_card_panel_style(panel, display_col if p_seat == active_turn_seat else "wild", p_seat == active_turn_seat)
				var lbl = Label.new()
				var uno_badge = " [UNO!]" if bool(p.get("called_uno", false)) else ""
				lbl.text = " %s (Seat %d) \n Cards: %d%s%s " % [
					p.get("name", ""),
					p_seat,
					p.get("card_count", 0),
					" [BOT]" if p.get("is_bot", false) else "",
					uno_badge
				]
				panel.add_child(lbl)
				opponents_container.add_child(panel)

	_check_round_over()

func _apply_card_button_style(btn: Button, color_name: String, playable: bool) -> void:
	var sb = StyleBoxFlat.new()
	sb.bg_color = CARD_COLORS.get(color_name, CARD_COLORS["wild"])
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(3 if playable else 1)
	sb.border_color = AccessibilitySymbolsScript.get_highlight_border_color(playable, colorblind_mode)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)

func _apply_card_panel_style(panel: PanelContainer, color_name: String, highlight: bool) -> void:
	var sb = StyleBoxFlat.new()
	var base_c: Color = CARD_COLORS.get(color_name, CARD_COLORS["wild"])
	sb.bg_color = Color(base_c.r, base_c.g, base_c.b, 0.88)
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(3 if highlight else 2)
	sb.border_color = Color(1, 1, 1, 0.9)
	panel.add_theme_stylebox_override("panel", sb)

func _on_card_pressed(card_id: String, card: Dictionary) -> void:
	if str(card.get("color", "")) == "wild":
		pending_wild_card_id = card_id
		if color_choice_dialog != null:
			color_choice_dialog.popup_centered()
	else:
		_play_card(card_id, "")

func select_wild_color(chosen_color: String) -> void:
	var cid = pending_wild_card_id
	pending_wild_card_id = ""
	if color_choice_dialog != null and color_choice_dialog.visible:
		color_choice_dialog.hide()
	if not cid.is_empty():
		_play_card(cid, chosen_color.to_lower())

func _on_color_choice_canceled() -> void:
	pending_wild_card_id = ""

func _play_card(card_id: String, chosen_color: String) -> void:
	var action: Dictionary = {
		"type": "ACTION_PLAY_CARD",
		"card_id": card_id
	}
	if not chosen_color.is_empty():
		action["chosen_color"] = chosen_color

	var res = cartridge.handle_action(current_player_id, action)
	if res.get("success", false):
		_post_human_turn()
	refresh_display()

func _on_draw_pile_btn_pressed() -> void:
	var res = cartridge.handle_action(current_player_id, { "type": "ACTION_DRAW_CARD" })
	if res.get("success", false):
		_post_human_turn()
	refresh_display()

func _on_call_uno_button_pressed() -> void:
	cartridge.handle_action(current_player_id, { "type": "ACTION_CALL_UNO" })
	_on_emote_pressed("UNO!")
	refresh_display()

func _on_emote_pressed(emote_text: String) -> void:
	if emote_banner != null:
		emote_banner.text = "%s: %s" % [current_player_id, emote_text]

func _post_human_turn() -> void:
	if cartridge == null or cartridge.is_round_over():
		return
	_run_bot_turns()
	if cartridge.is_round_over():
		return
	if match_mode == "pass_and_play":
		var pub = cartridge.get_public_state()
		var next_seat = int(pub.get("current_turn_seat", 0))
		var next_p = cartridge.get_player_by_seat(next_seat)
		var next_pid = str(next_p.get("player_id", current_player_id))
		if next_pid != current_player_id:
			current_player_id = next_pid
			if pass_and_play_ctrl != null:
				pass_and_play_ctrl.advance_to_seat(next_seat, next_pid, false)

func _run_bot_turns() -> void:
	for _i in range(32):
		if cartridge.is_round_over():
			break
		var pub = cartridge.get_public_state()
		var turn_seat = int(pub.get("current_turn_seat", 0))
		var active_player = cartridge.get_player_by_seat(turn_seat)
		if bool(active_player.get("is_bot", false)):
			var pid = str(active_player.get("player_id", ""))
			var bot_act = cartridge.get_bot_action(pid)
			cartridge.handle_action(pid, bot_act)
		else:
			break

func _check_round_over() -> void:
	if cartridge == null or not cartridge.is_round_over():
		return
	var res = cartridge.get_round_results()
	var winner_id = str(res.get("winner_player_id", ""))
	var score = int(res.get("score_earned", 0))
	if round_over_overlay != null:
		round_over_overlay.visible = true
		if winner_label != null:
			winner_label.text = "Round Over! Winner: %s (+%d pts)" % [winner_id, score]
	if not _round_recorded and stats_svc != null:
		_round_recorded = true
		var elapsed = maxi(1, int(Time.get_unix_time_from_system()) - _match_start_unix)
		stats_svc.record_match_result({
			"game_id": "uno",
			"my_player_id": "p0",
			"winner_id": winner_id,
			"duration_seconds": elapsed
		})

func _on_play_again_pressed() -> void:
	configure_match(_last_options)

func _on_back_button_pressed() -> void:
	back_requested.emit()

func _on_theme_option_selected(index: int) -> void:
	if theme_option != null:
		set_table_theme(str(theme_option.get_item_metadata(index)))

func _on_quality_option_selected(index: int) -> void:
	if quality_option != null:
		set_quality_preset(str(quality_option.get_item_metadata(index)))

func _on_colorblind_toggled(toggled_on: bool) -> void:
	colorblind_mode = toggled_on
	refresh_display()
