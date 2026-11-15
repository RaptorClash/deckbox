# scenes/tables/table_theme.gd
# Base controller for 3D table scenes supporting quality presets and card anchors.
class_name TableTheme extends Node3D

@export var theme_id: String = "arcade_ps5"
@export var theme_display_name: String = "Arcade PS5"

@onready var draw_pile_anchor: Marker3D = $Anchors/DrawPileAnchor
@onready var discard_pile_anchor: Marker3D = $Anchors/DiscardPileAnchor
@onready var seats_container: Node3D = $Anchors/Seats
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var key_light: DirectionalLight3D = $Lighting/KeyLight

func _ready() -> void:
	apply_quality_preset("high")

func apply_quality_preset(preset: String) -> void:
	var p = preset.to_lower()
	match p:
		"low":
			if key_light:
				key_light.shadow_enabled = false
			if world_env and world_env.environment:
				world_env.environment.glow_enabled = false
		"medium":
			if key_light:
				key_light.shadow_enabled = false
			if world_env and world_env.environment:
				world_env.environment.glow_enabled = (theme_id == "arcade_ps5")
		"high", _:
			if key_light:
				key_light.shadow_enabled = true
			if world_env and world_env.environment:
				world_env.environment.glow_enabled = (theme_id == "arcade_ps5")

func get_draw_pile_position() -> Vector3:
	return draw_pile_anchor.global_position if draw_pile_anchor else Vector3(-0.15, 0.75, 0)

func get_discard_pile_position() -> Vector3:
	return discard_pile_anchor.global_position if discard_pile_anchor else Vector3(0.15, 0.75, 0)

func get_seat_position(seat_index: int) -> Vector3:
	if seats_container and seat_index >= 0 and seat_index < seats_container.get_child_count():
		var child = seats_container.get_child(seat_index)
		if child is Marker3D:
			return child.global_position
	return Vector3.ZERO
