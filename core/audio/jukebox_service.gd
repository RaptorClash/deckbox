# core/audio/jukebox_service.gd
# Royalty-free procedural relaxed ambient/lo-fi Jukebox synthesizer for DeckBox.
# Generates seamless 8-second multi-chord AudioStreamWAV loops tailored to each 3D location.
class_name JukeboxService
extends RefCounted

const SAMPLE_RATE: int = 22050
const TRACK_DURATION_SEC: float = 8.0

const TRACKS: Array[String] = [
	"cozy_house",
	"forest_glade",
	"neon_club",
	"bowling_alley",
	"rustic_pub"
]

static var _stream_cache: Dictionary = {}

static func get_available_tracks() -> Array[String]:
	return TRACKS.duplicate()

func resolve_track_for_mode(mode: String, location_id: String = "cozy_house") -> String:
	var clean_mode := mode.strip_edges().to_lower()
	if clean_mode == "off" or clean_mode == "mute":
		return "off"
	if clean_mode == "auto" or clean_mode.is_empty():
		var loc := location_id.strip_edges().to_lower()
		if loc in TRACKS:
			return loc
		return "cozy_house"
	if clean_mode == "shuffle":
		return TRACKS[0]
	if clean_mode in TRACKS:
		return clean_mode
	return "cozy_house"

func next_shuffle_track(current_track: String) -> String:
	if TRACKS.is_empty():
		return "cozy_house"
	var idx := TRACKS.find(current_track)
	if idx == -1:
		return TRACKS[0]
	return TRACKS[(idx + 1) % TRACKS.size()]

func get_track_stream(track_id: String) -> AudioStreamWAV:
	var tid := track_id.strip_edges().to_lower()
	if not (tid in TRACKS):
		tid = "cozy_house"
	if _stream_cache.has(tid):
		return _stream_cache[tid]
	var wav := _synthesize_track(tid)
	_stream_cache[tid] = wav
	return wav

func _synthesize_track(tid: String) -> AudioStreamWAV:
	var total_samples := int(TRACK_DURATION_SEC * float(SAMPLE_RATE))
	var samples := PackedFloat32Array()
	samples.resize(total_samples)

	var chords := _get_chord_progression(tid)
	var melody := _get_melody_notes(tid)
	var timbre := _get_timbre_profile(tid)
	var num_chords := chords.size()
	var chord_len_samples := total_samples / num_chords

	var lp: float = 0.0
	var lp_alpha: float = float(timbre["lp_alpha"])
	var warmth: float = float(timbre["warmth"])
	var step_count := melody.size()
	var step_samples := total_samples / step_count

	for i in range(total_samples):
		var sec := float(i) / float(SAMPLE_RATE)
		var chord_idx := mini(num_chords - 1, i / chord_len_samples)
		var local_c_t := float(i % chord_len_samples) / float(chord_len_samples)
		# Soft chord cross-envelope avoids clicks on chord transitions and loop seam
		var c_env := sin(PI * clampf(local_c_t, 0.0, 1.0))
		c_env = pow(maxf(0.0, c_env), 0.35)

		var pad_sum: float = 0.0
		var chord: Array = chords[chord_idx]
		for f_idx in range(chord.size()):
			var freq: float = float(chord[f_idx])
			# Quantize to integer cycles over segment for seamless continuity
			var osc := sin(TAU * freq * sec) + warmth * sin(TAU * freq * 2.0 * sec)
			pad_sum += osc / float(chord.size())

		var step_idx := mini(step_count - 1, i / step_samples)
		var step_t := float(i % step_samples) / float(step_samples)
		var m_freq: float = float(melody[step_idx])
		var mel_sig: float = 0.0
		if m_freq > 1.0:
			var attack := minf(1.0, step_t / 0.06)
			var decay := exp(-step_t * float(timbre["mel_decay"]))
			var tail_fade := minf(1.0, (1.0 - step_t) / 0.05)
			var m_env := attack * decay * tail_fade
			var m_wave := sin(TAU * m_freq * sec) * 0.72 + sin(TAU * m_freq * 2.0 * sec) * float(timbre["mel_overtone"])
			mel_sig = m_wave * m_env * float(timbre["mel_gain"])

		# Subtle warm pulse on quarter-beats
		var beat_t := fmod(sec * float(timbre["pulse_hz"]), 1.0)
		var pulse_env := exp(-beat_t * 9.0) * sin(PI * minf(1.0, beat_t * 6.0))
		var bass_freq: float = float(chord[0]) * 0.5
		var bass_sig := sin(TAU * bass_freq * sec) * pulse_env * float(timbre["bass_gain"])

		var raw := pad_sum * c_env * float(timbre["pad_gain"]) + mel_sig + bass_sig
		lp = lp + lp_alpha * (raw - lp)

		# Global 25ms loop edge taper guarantees zero click at 8.0s loop wrap
		var edge_fade: float = 1.0
		var edge_len := mini(550, total_samples / 8)
		if i < edge_len:
			edge_fade = float(i) / float(edge_len)
		elif i >= total_samples - edge_len:
			edge_fade = float(total_samples - 1 - i) / float(edge_len)
		samples[i] = clampf(lp * edge_fade * 0.78, -0.92, 0.92)

	var bytes := PackedByteArray()
	bytes.resize(total_samples * 2)
	for i in range(total_samples):
		bytes.encode_s16(i * 2, int(clampf(samples[i], -0.98, 0.98) * 32767.0))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = bytes
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = total_samples
	return wav

func _get_chord_progression(tid: String) -> Array:
	match tid:
		"forest_glade":
			return [
				[261.63, 329.63, 392.00, 493.88], # Cmaj7
				[220.00, 261.63, 329.63, 392.00], # Am7
				[174.61, 220.00, 261.63, 329.63], # Fmaj7
				[196.00, 246.94, 293.66, 329.63]  # G6
			]
		"neon_club":
			return [
				[146.83, 220.00, 261.63, 329.63], # Dm9
				[233.08, 293.66, 349.23, 440.00], # Bbmaj7
				[196.00, 233.08, 293.66, 349.23], # Gm7
				[220.00, 293.66, 329.63, 392.00]  # A7sus4
			]
		"bowling_alley":
			return [
				[155.56, 233.08, 293.66, 349.23], # Ebmaj7
				[130.81, 196.00, 233.08, 293.66], # Cm7
				[174.61, 207.65, 261.63, 311.13], # Fm7
				[233.08, 293.66, 349.23, 392.00]  # Bb6
			]
		"rustic_pub":
			return [
				[196.00, 246.94, 293.66, 392.00], # G
				[164.81, 246.94, 293.66, 392.00], # Em7
				[261.63, 329.63, 392.00, 493.88], # Cmaj7
				[146.83, 220.00, 293.66, 370.00]  # D6
			]
		_: # cozy_house
			return [
				[174.61, 220.00, 261.63, 329.63], # Fmaj7
				[146.83, 220.00, 261.63, 349.23], # Dm7
				[196.00, 233.08, 293.66, 349.23], # Gm7
				[130.81, 196.00, 233.08, 293.66]  # C9
			]

func _get_melody_notes(tid: String) -> Array:
	match tid:
		"forest_glade":
			return [523.25, 659.25, 783.99, 659.25, 440.0, 523.25, 659.25, 0.0, 349.23, 440.0, 523.25, 659.25, 587.33, 493.88, 392.0, 0.0]
		"neon_club":
			return [440.0, 0.0, 523.25, 440.0, 349.23, 440.0, 587.33, 0.0, 392.0, 466.16, 587.33, 523.25, 440.0, 329.63, 392.0, 0.0]
		"bowling_alley":
			return [311.13, 466.16, 587.33, 0.0, 523.25, 466.16, 392.0, 466.16, 349.23, 523.25, 622.25, 0.0, 587.33, 466.16, 392.0, 0.0]
		"rustic_pub":
			return [392.0, 493.88, 587.33, 493.88, 329.63, 392.0, 493.88, 587.33, 523.25, 493.88, 392.0, 0.0, 293.66, 369.99, 440.0, 587.33]
		_: # cozy_house
			return [523.25, 440.0, 349.23, 0.0, 587.33, 523.25, 440.0, 349.23, 466.16, 392.0, 349.23, 0.0, 440.0, 392.0, 329.63, 0.0]

func _get_timbre_profile(tid: String) -> Dictionary:
	match tid:
		"forest_glade":
			return { "lp_alpha": 0.24, "warmth": 0.12, "pad_gain": 0.22, "mel_gain": 0.16, "mel_decay": 4.2, "mel_overtone": 0.10, "bass_gain": 0.08, "pulse_hz": 1.0 }
		"neon_club":
			return { "lp_alpha": 0.18, "warmth": 0.28, "pad_gain": 0.25, "mel_gain": 0.15, "mel_decay": 3.0, "mel_overtone": 0.22, "bass_gain": 0.20, "pulse_hz": 2.0 }
		"bowling_alley":
			return { "lp_alpha": 0.22, "warmth": 0.22, "pad_gain": 0.23, "mel_gain": 0.16, "mel_decay": 3.8, "mel_overtone": 0.18, "bass_gain": 0.16, "pulse_hz": 2.0 }
		"rustic_pub":
			return { "lp_alpha": 0.28, "warmth": 0.18, "pad_gain": 0.20, "mel_gain": 0.18, "mel_decay": 5.2, "mel_overtone": 0.25, "bass_gain": 0.12, "pulse_hz": 1.5 }
		_: # cozy_house
			return { "lp_alpha": 0.19, "warmth": 0.16, "pad_gain": 0.24, "mel_gain": 0.15, "mel_decay": 3.6, "mel_overtone": 0.12, "bass_gain": 0.11, "pulse_hz": 1.0 }
