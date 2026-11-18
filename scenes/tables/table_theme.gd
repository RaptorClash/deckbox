# scenes/tables/table_theme.gd
# Base controller for dynamic N-player 3D table scenes supporting quality presets, view modes, and card anchors.
class_name TableTheme
extends Node3D

@export var theme_id: String = "arcade_ps5"
@export var theme_display_name: String = "Arcade PS5"

@onready var draw_pile_anchor: Marker3D = $Anchors/DrawPileAnchor
@onready var discard_pile_anchor: Marker3D = $Anchors/DiscardPileAnchor
@onready var seats_container: Node3D = $Anchors/Seats
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var key_light: DirectionalLight3D = $Lighting/KeyLight
@onready var table_mesh: Node3D = $TableMesh
@onready var camera_3d: Camera3D = $Camera3D

var _total_players: int = 4
var _scale_xz: float = 1.0
var _view_mode: String = "full_3d"
var _is_table_role: bool = false

func _ready() -> void:
	apply_quality_preset("high")
	configure_for_player_count(_total_players, _view_mode, _is_table_role)

func apply_quality_preset(preset: String) -> void:
	var p = preset.to_lower()
	match p:
		"low":
			if key_light:
				key_light.shadow_enabled = false
			if world_env and world_env.environment:
				world_env.environment.glow_enabled = false
				world_env.environment.ssao_enabled = false
		"medium":
			if key_light:
				key_light.shadow_enabled = true
			if world_env and world_env.environment:
				world_env.environment.glow_enabled = (theme_id == "arcade_ps5")
				world_env.environment.ssao_enabled = false
		"high", _:
			if key_light:
				key_light.shadow_enabled = true
			if world_env and world_env.environment:
				world_env.environment.glow_enabled = (theme_id == "arcade_ps5")
				world_env.environment.ssao_enabled = false

func configure_for_player_count(player_count: int, view_mode: String = "full_3d", is_table_role: bool = false) -> void:
	_total_players = maxi(2, player_count)
	_view_mode = view_mode
	_is_table_role = is_table_role

	# Scale table horizontally so large groups (5..32+) have generous space around the stadium perimeter
	_scale_xz = 1.0 + clampf(float(maxi(0, _total_players - 4)) * 0.14, 0.0, 2.35)
	if table_mesh != null:
		table_mesh.scale = Vector3(_scale_xz, 1.0, _scale_xz)

	if draw_pile_anchor != null:
		draw_pile_anchor.position = Vector3(-0.145, 0.755, 0.0)
	if discard_pile_anchor != null:
		discard_pile_anchor.position = Vector3(0.145, 0.755, 0.0)

	_update_camera_rig()

func _update_camera_rig() -> void:
	if camera_3d == null:
		return

	var cam_pos: Vector3
	var target: Vector3
	var cam_fov: float = 54.0
	var cam_scale = lerpf(1.0, _scale_xz, 0.72)

	if _is_table_role or _view_mode == "table_role":
		# Symmetric arena view for TV / shared tabletop displays
		cam_pos = Vector3(0.0, 2.34 * cam_scale, 0.44 * cam_scale)
		target = Vector3(0.0, 0.75, 0.0)
		cam_fov = 54.0
	elif _view_mode == "clean_25d":
		# Crisp high-angle 2.5D top-down overview
		cam_pos = Vector3(0.0, 2.28 * cam_scale, 0.70 * cam_scale)
		target = Vector3(0.0, 0.75, 0.08)
		cam_fov = 52.0
	elif _view_mode == "hybrid_25d":
		# Slightly higher view leaving clean foreground room for the 2.5D curved hand fan
		cam_pos = Vector3(0.0, 1.92 * cam_scale, 1.32 * cam_scale)
		target = Vector3(0.0, 0.72, 0.14)
		cam_fov = 56.0
	else:
		# Full 3D Immersive over-the-hand perspective
		var extra_h = (cam_scale - 1.0) * 0.75
		cam_pos = Vector3(0.0, 1.62 + extra_h, 1.28 * cam_scale)
		target = Vector3(0.0, 0.74, 0.08)
		cam_fov = 58.0

	camera_3d.fov = cam_fov
	var dir = (target - cam_pos).normalized()
	if not dir.is_zero_approx():
		var basis = Basis.looking_at(dir, Vector3.UP)
		camera_3d.transform = Transform3D(basis, cam_pos)

func get_camera() -> Camera3D:
	return camera_3d

func get_table_scale() -> float:
	return _scale_xz

func get_draw_pile_position() -> Vector3:
	return draw_pile_anchor.global_position if (draw_pile_anchor and draw_pile_anchor.is_inside_tree()) else (draw_pile_anchor.position if draw_pile_anchor else Vector3(-0.145, 0.755, 0.0))

func get_discard_pile_position() -> Vector3:
	return discard_pile_anchor.global_position if (discard_pile_anchor and discard_pile_anchor.is_inside_tree()) else (discard_pile_anchor.position if discard_pile_anchor else Vector3(0.145, 0.755, 0.0))

func get_seat_position(seat_index: int, total_players: int = -1, local_seat: int = 0) -> Vector3:
	var count = _total_players if total_players <= 0 else maxi(2, total_players)
	var rel_idx = ((seat_index - local_seat) % count + count) % count
	var angle = PI * 0.5 + float(rel_idx) * TAU / float(count)
	var rx = 0.94 * _scale_xz
	var rz = 0.54 * _scale_xz
	return Vector3(cos(angle) * rx, 0.755, sin(angle) * rz)
