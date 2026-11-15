# core/qol/audio_controls.gd
# Manages AudioServer volume sliders (-80 dB silence floor), bus mute flags, and animation speed.
class_name AudioControls extends RefCounted

const BUS_NAMES: Array[String] = ["Master", "Music", "SFX", "Emotes"]
const SILENCE_DB: float = -80.0

var _animation_speed: float = 1.0
var _cached_volumes: Dictionary = {
	"Master": 1.0,
	"Music": 0.8,
	"SFX": 0.9,
	"Emotes": 0.7
}

func _init() -> void:
	ensure_buses_exist()

func ensure_buses_exist() -> void:
	for bus_name in BUS_NAMES:
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx = AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)

func set_bus_volume(bus_name: String, linear: float) -> void:
	var clamped_linear = clampf(linear, 0.0, 1.0)
	_cached_volumes[bus_name] = clamped_linear
	var bus_idx = AudioServer.get_bus_index(bus_name)
	if bus_idx != -1:
		var db = linear_to_db(clamped_linear) if clamped_linear > 0.0001 else SILENCE_DB
		AudioServer.set_bus_volume_db(bus_idx, db)

func get_bus_volume(bus_name: String) -> float:
	var bus_idx = AudioServer.get_bus_index(bus_name)
	if bus_idx != -1:
		var db = AudioServer.get_bus_volume_db(bus_idx)
		if db <= SILENCE_DB:
			return 0.0
		return db_to_linear(db)
	return _cached_volumes.get(bus_name, 1.0)

func set_bus_mute(bus_name: String, muted: bool) -> void:
	var bus_idx = AudioServer.get_bus_index(bus_name)
	if bus_idx != -1:
		AudioServer.set_bus_mute(bus_idx, muted)

func is_bus_muted(bus_name: String) -> bool:
	var bus_idx = AudioServer.get_bus_index(bus_name)
	if bus_idx != -1:
		return AudioServer.is_bus_mute(bus_idx)
	return false

func set_animation_speed(speed: float) -> void:
	_animation_speed = clampf(speed, 0.25, 4.0)

func get_animation_speed() -> float:
	return _animation_speed

func export_settings() -> Dictionary:
	return {
		"master_volume": get_bus_volume("Master"),
		"music_volume": get_bus_volume("Music"),
		"sfx_volume": get_bus_volume("SFX"),
		"emotes_volume": get_bus_volume("Emotes"),
		"animation_speed": _animation_speed
	}

func import_settings(data: Dictionary) -> void:
	if data.has("master_volume"):
		set_bus_volume("Master", float(data["master_volume"]))
	if data.has("music_volume"):
		set_bus_volume("Music", float(data["music_volume"]))
	if data.has("sfx_volume"):
		set_bus_volume("SFX", float(data["sfx_volume"]))
	if data.has("emotes_volume"):
		set_bus_volume("Emotes", float(data["emotes_volume"]))
	if data.has("animation_speed"):
		set_animation_speed(float(data["animation_speed"]))
