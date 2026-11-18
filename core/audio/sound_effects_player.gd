# core/audio/sound_effects_player.gd
# Procedural PCM AudioStreamWAV Synthesizer & Playback Controller for DeckBox
class_name SoundEffectsPlayer
extends Node

const AudioControlsScript = preload("res://core/qol/audio_controls.gd")
const SAMPLE_RATE: int = 22050

var _clips: Dictionary = {}
var _audio_controls: RefCounted = null
var _ambient_player: AudioStreamPlayer = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _init() -> void:
	_rng.seed = 42069
	_audio_controls = AudioControlsScript.new()
	_generate_all_clips()

func _ready() -> void:
	if _audio_controls != null:
		_audio_controls.ensure_buses_exist()

func get_clip(clip_name: String) -> AudioStreamWAV:
	return _clips.get(clip_name, null)

func _generate_all_clips() -> void:
	_clips["card_swoosh"] = _synth_swoosh(0.16)
	_clips["card_snap"] = _synth_snap(0.09)
	_clips["draw_pop"] = _synth_pop(0.11)
	_clips["special_impact"] = _synth_special_impact(0.32)
	_clips["uno_fanfare"] = _synth_uno_fanfare(0.48)
	_clips["table_knock"] = _synth_knock(0.28)
	_clips["ambient_lounge"] = _synth_ambient_lounge(2.0)

func _make_wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var bytes = PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in range(samples.size()):
		var s = clampf(samples[i], -0.98, 0.98)
		bytes.encode_s16(i * 2, int(s * 32767.0))

	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav

func _synth_swoosh(duration: float) -> AudioStreamWAV:
	var count = int(duration * SAMPLE_RATE)
	var samples = PackedFloat32Array()
	samples.resize(count)
	var lp: float = 0.0
	for i in range(count):
		var t = float(i) / float(count)
		var env = sin(t * PI) * (1.0 - t * 0.35)
		var noise = _rng.randf_range(-1.0, 1.0)
		lp = lp * 0.72 + noise * 0.28
		samples[i] = lp * env * 0.42
	return _make_wav(samples)

func _synth_snap(duration: float) -> AudioStreamWAV:
	var count = int(duration * SAMPLE_RATE)
	var samples = PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		var sec = float(i) / float(SAMPLE_RATE)
		var t = float(i) / float(count)
		var env = exp(-t * 11.0)
		var freq = lerpf(240.0, 75.0, minf(1.0, t * 2.5))
		var body = sin(TAU * freq * sec) * 0.65
		var click = _rng.randf_range(-0.4, 0.4) * exp(-t * 28.0)
		samples[i] = (body + click) * env * 0.75
	return _make_wav(samples)

func _synth_pop(duration: float) -> AudioStreamWAV:
	var count = int(duration * SAMPLE_RATE)
	var samples = PackedFloat32Array()
	samples.resize(count)
	var phase: float = 0.0
	for i in range(count):
		var t = float(i) / float(count)
		var env = sin(t * PI) * exp(-t * 4.0)
		var freq = lerpf(320.0, 620.0, t)
		phase += TAU * freq / float(SAMPLE_RATE)
		samples[i] = sin(phase) * env * 0.55
	return _make_wav(samples)

func _synth_special_impact(duration: float) -> AudioStreamWAV:
	var count = int(duration * SAMPLE_RATE)
	var samples = PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		var sec = float(i) / float(SAMPLE_RATE)
		var t = float(i) / float(count)
		var sub_env = exp(-t * 6.5)
		var chime_env = exp(-t * 4.5) * sin(minf(1.0, t * 8.0) * PI * 0.5)
		var sub = sin(TAU * lerpf(130.0, 52.0, minf(1.0, t * 1.8)) * sec) * 0.55 * sub_env
		var chime = (sin(TAU * 523.25 * sec) + 0.6 * sin(TAU * 783.99 * sec)) * 0.25 * chime_env
		samples[i] = sub + chime
	return _make_wav(samples)

func _synth_uno_fanfare(duration: float) -> AudioStreamWAV:
	var count = int(duration * SAMPLE_RATE)
	var samples = PackedFloat32Array()
	samples.resize(count)
	var notes = [523.25, 659.25, 783.99, 1046.50] # C5 E5 G5 C6
	var step_len = duration / float(notes.size())
	for i in range(count):
		var sec = float(i) / float(SAMPLE_RATE)
		var val: float = 0.0
		for n_idx in range(notes.size()):
			var start_t = float(n_idx) * step_len * 0.72
			if sec >= start_t:
				var dt = sec - start_t
				var env = exp(-dt * 7.0) * minf(1.0, dt * 60.0)
				var f = notes[n_idx]
				val += (sin(TAU * f * dt) + 0.35 * sin(TAU * f * 2.0 * dt)) * env * 0.26
		samples[i] = val
	return _make_wav(samples)

func _synth_knock(duration: float) -> AudioStreamWAV:
	var count = int(duration * SAMPLE_RATE)
	var samples = PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		var sec = float(i) / float(SAMPLE_RATE)
		var val: float = 0.0
		for hit_t in [0.0, 0.13]:
			if sec >= hit_t:
				var dt = sec - hit_t
				var env = exp(-dt * 34.0)
				val += (sin(TAU * 165.0 * dt) + 0.45 * sin(TAU * 290.0 * dt)) * env * 0.6
		samples[i] = val
	return _make_wav(samples)

func _synth_ambient_lounge(duration: float) -> AudioStreamWAV:
	var count = int(duration * SAMPLE_RATE)
	var samples = PackedFloat32Array()
	samples.resize(count)
	# Warm seamless harmonics aligned to exact integer cycles over 2.0 seconds
	var freqs = [130.0, 195.0, 260.0, 325.0]
	for i in range(count):
		var sec = float(i) / float(SAMPLE_RATE)
		var val: float = 0.0
		for idx in range(freqs.size()):
			val += sin(TAU * freqs[idx] * sec) * (0.045 / float(idx + 1))
		var swell = 0.8 + 0.2 * sin(TAU * 0.5 * sec)
		samples[i] = val * swell
	return _make_wav(samples, true)

func play_clip(clip_name: String, bus_name: String = "SFX", volume_db: float = -4.0) -> void:
	if not is_inside_tree():
		return
	var stream: AudioStreamWAV = _clips.get(clip_name, null)
	if stream == null:
		return

	var player = AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.bus = bus_name if AudioServer.get_bus_index(bus_name) != -1 else "Master"
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

func play_card_swoosh() -> void:
	play_clip("card_swoosh", "SFX", -6.0)

func play_card_snap() -> void:
	play_clip("card_snap", "SFX", -3.0)

func play_draw_pop() -> void:
	play_clip("draw_pop", "SFX", -5.0)

func play_special_impact() -> void:
	play_clip("special_impact", "SFX", -2.5)

func play_uno_fanfare() -> void:
	play_clip("uno_fanfare", "Emotes", -2.0)

func play_table_knock() -> void:
	play_clip("table_knock", "Emotes", -2.0)

func start_ambient_lounge() -> void:
	if not is_inside_tree():
		return
	if _ambient_player != null and is_instance_valid(_ambient_player):
		if not _ambient_player.playing:
			_ambient_player.play()
		return
	var stream = get_clip("ambient_lounge")
	if stream == null:
		return
	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.stream = stream
	_ambient_player.volume_db = -18.0
	_ambient_player.bus = "Music" if AudioServer.get_bus_index("Music") != -1 else "Master"
	add_child(_ambient_player)
	_ambient_player.play()

func stop_ambient_lounge() -> void:
	if _ambient_player != null and is_instance_valid(_ambient_player):
		_ambient_player.stop()
