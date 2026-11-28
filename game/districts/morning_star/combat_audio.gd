extends Node

enum Cue { SWING, HIT, GUARD, IMMUNE, DODGE, HURT, BREAK, WALL, DASH, LOCK, BEAM, PULSE, SHIFT, WIN }

const RATE := 22050
const BEAT := 0.48
const BASS := [55.0, 55.0, 65.41, 55.0, 49.0, 55.0, 65.41, 49.0]
const HIGH := [164.81, 0.0, 196.0, 0.0, 146.83, 0.0, 196.0, 220.0]
# Duration, start and end pitch, noise share, and volume.
const VOICES := [
	[0.095, 270.0, 105.0, 0.66, 0.19], [0.125, 148.0, 62.0, 0.32, 0.32],
	[0.135, 780.0, 510.0, 0.11, 0.22], [0.105, 490.0, 235.0, 0.02, 0.12],
	[0.135, 440.0, 185.0, 0.59, 0.18], [0.18, 184.0, 66.0, 0.46, 0.30],
	[0.31, 510.0, 115.0, 0.34, 0.40], [0.30, 114.0, 49.0, 0.55, 0.28],
	[0.24, 340.0, 73.0, 0.48, 0.30], [0.145, 523.0, 783.0, 0.04, 0.15],
	[0.29, 243.0, 72.0, 0.39, 0.30], [0.28, 180.0, 43.0, 0.33, 0.28],
	[0.45, 284.0, 428.0, 0.17, 0.30], [0.67, 392.0, 261.6, 0.02, 0.22],
]

static var _streams: Array[AudioStreamWAV] = []
static var _bed_loop: AudioStreamWAV
static var _rhythm_loop: AudioStreamWAV
var _voices: Array[AudioStreamPlayer] = []
var _cursor := 0
var _bed: AudioStreamPlayer
var _rhythm: AudioStreamPlayer
var _music_mix: Tween


func build(music_override: AudioStream = null) -> void:
	if _streams.is_empty():
		for cue in VOICES:
			_streams.append(_synthesize(cue))
	if _bed_loop == null and music_override == null:
		_bed_loop = _music_loop(false)
	if _rhythm_loop == null:
		_rhythm_loop = _music_loop(true)
	for index in range(8):
		var voice := AudioStreamPlayer.new()
		voice.volume_db = -5.0
		add_child(voice)
		_voices.append(voice)
	_bed = AudioStreamPlayer.new()
	_bed.stream = music_override if music_override != null else _bed_loop
	_bed.volume_db = -23.0
	add_child(_bed)
	_rhythm = AudioStreamPlayer.new()
	_rhythm.stream = _rhythm_loop
	_rhythm.volume_db = -45.0
	add_child(_rhythm)


func play(cue: Cue) -> void:
	var voice := _voices[_cursor]
	_cursor = (_cursor + 1) % _voices.size()
	voice.stream = _streams[cue]
	voice.play()


func stop_cues() -> void:
	for voice in _voices:
		voice.stop()


func _exit_tree() -> void:
	if _music_mix:
		_music_mix.kill()
	for voice in _voices:
		voice.stop()
		voice.stream = null
	if is_instance_valid(_bed) and is_instance_valid(_rhythm):
		_stop_music()
		_bed.stream = null
		_rhythm.stream = null


func start_music() -> void:
	if _music_mix:
		_music_mix.kill()
	_bed.volume_db = -23.0
	_rhythm.volume_db = -45.0
	if not _bed.playing:
		_bed.play()
	if not _rhythm.playing:
		_rhythm.play()


func set_music_tier(tier: int) -> void:
	if _music_mix:
		_music_mix.kill()
	_music_mix = create_tween()
	var level := -29.0 if tier == 2 else -23.0
	_music_mix.tween_property(_rhythm, "volume_db", level, 0.52)


func finish_music() -> void:
	if _music_mix:
		_music_mix.kill()
	_music_mix = create_tween().set_parallel(true)
	_music_mix.tween_property(_bed, "volume_db", -52.0, 0.68)
	_music_mix.tween_property(_rhythm, "volume_db", -52.0, 0.50)
	_music_mix.chain().tween_callback(_stop_music)


func _stop_music() -> void:
	_bed.stop()
	_rhythm.stop()


func _music_loop(rhythm: bool) -> AudioStreamWAV:
	var beat_frames := roundi(RATE * BEAT)
	var frame_count := beat_frames * BASS.size()
	var bytes := PackedByteArray()
	bytes.resize(frame_count * 2)
	for frame in range(frame_count):
		var beat := floori(float(frame) / beat_frames)
		var fraction := float(frame % beat_frames) / beat_frames
		var time := float(frame % beat_frames) / RATE
		var frequency: float = HIGH[beat] if rhythm else BASS[beat]
		var envelope := minf(fraction * 44.0, 1.0) * pow(1.0 - fraction, 2.6)
		var pitch := time * frequency * TAU
		var pulse := sin(pitch) * 0.59 + sin(pitch * 2.02) * 0.17 if frequency > 0.0 else 0.0
		var tick := sin(TAU * time * 114.0 * (1.0 - fraction * 0.32)) * pow(maxf(0.0, 1.0 - fraction * 8.0), 3.0)
		var sample := (pulse * envelope + (tick * 0.17 if rhythm else tick * 0.40)) * 0.60
		bytes.encode_s16(frame * 2, roundi(clampf(sample, -1.0, 1.0) * 32767.0))
	var track := AudioStreamWAV.new()
	track.format = AudioStreamWAV.FORMAT_16_BITS
	track.mix_rate = RATE
	track.data = bytes
	track.loop_mode = AudioStreamWAV.LOOP_FORWARD
	track.loop_end = frame_count
	return track


func _synthesize(cue: Array) -> AudioStreamWAV:
	var frames := roundi(RATE * float(cue[0]))
	var bytes := PackedByteArray()
	bytes.resize(frames * 2)
	var phase := 0.0
	var noise := RandomNumberGenerator.new()
	noise.seed = 614
	for frame in range(frames):
		var position := float(frame) / frames
		phase += TAU * lerpf(cue[1], cue[2], position) / RATE
		var wave := sin(phase) * 0.80 + sin(phase * 1.99) * 0.15 + sin(phase * 3.01) * 0.05
		var envelope := minf(position * 58.0, 1.0) * pow(1.0 - position, 2.0)
		var sample := lerpf(wave, noise.randf_range(-1.0, 1.0), cue[3]) * envelope * float(cue[4])
		bytes.encode_s16(frame * 2, roundi(clampf(sample, -1.0, 1.0) * 32767.0))
	var clip := AudioStreamWAV.new()
	clip.format = AudioStreamWAV.FORMAT_16_BITS
	clip.mix_rate = RATE
	clip.data = bytes
	return clip
