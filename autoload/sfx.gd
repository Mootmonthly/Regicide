extends Node
## Procedurally synthesized sound effects, so the game needs no audio assets yet.
## Sfx.play_at("hit", pos) for positional sounds, Sfx.play("capture") for UI/2D.

const RATE := 22050
const MAX_3D_VOICES := 24
const MAX_NEW_PER_FRAME := 6
const HEARING_DISTANCE := 50.0

var _streams: Dictionary = {}
var _voices_3d: Array[AudioStreamPlayer3D] = []
var _voices_2d: Array[AudioStreamPlayer] = []
var _started_this_frame := 0
var _enabled := true


func _ready() -> void:
	_enabled = DisplayServer.get_name() != "headless"
	if not _enabled:
		return
	_build_sounds()
	for i in MAX_3D_VOICES:
		var p := AudioStreamPlayer3D.new()
		p.max_distance = HEARING_DISTANCE
		p.unit_size = 6.0
		add_child(p)
		_voices_3d.append(p)
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_voices_2d.append(p)


func _process(_delta: float) -> void:
	_started_this_frame = 0


func play_at(sound: String, pos: Vector3, volume_db := 0.0) -> void:
	if not _enabled or not _streams.has(sound) or _started_this_frame >= MAX_NEW_PER_FRAME:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.global_position.distance_to(pos) > HEARING_DISTANCE:
		return
	var voice: AudioStreamPlayer3D = null
	for v in _voices_3d:
		if not v.playing:
			voice = v
			break
	if voice == null:
		return
	_started_this_frame += 1
	voice.stream = _streams[sound]
	voice.global_position = pos
	voice.volume_db = volume_db
	voice.pitch_scale = randf_range(0.92, 1.08)
	voice.play()


func play(sound: String, volume_db := 0.0) -> void:
	if not _enabled or not _streams.has(sound):
		return
	for v in _voices_2d:
		if not v.playing:
			v.stream = _streams[sound]
			v.volume_db = volume_db
			v.play()
			return


# --- Synthesis -----------------------------------------------------------------

func _build_sounds() -> void:
	_streams["swing"] = _make(0.16, func(t: float, d: float) -> float:
		return _noise() * sin(PI * t / d) * 0.5, 0.25)
	_streams["hit"] = _make(0.14, func(t: float, d: float) -> float:
		return (sin(TAU * lerpf(160.0, 60.0, t / d) * t) * 0.8 + _noise() * 0.4) * _decay(t, 25.0))
	_streams["hit_wood"] = _make(0.1, func(t: float, _d: float) -> float:
		return (sin(TAU * 180.0 * t) * 0.6 + _noise() * 0.5) * _decay(t, 35.0), 0.4)
	_streams["chop"] = _make(0.12, func(t: float, _d: float) -> float:
		return (sin(TAU * 420.0 * t) * 0.4 + _noise() * 0.6) * _decay(t, 40.0), 0.35)
	_streams["mine"] = _make(0.35, func(t: float, _d: float) -> float:
		return (sin(TAU * 1250.0 * t) + sin(TAU * 1870.0 * t) * 0.6 + sin(TAU * 2730.0 * t) * 0.3) * 0.35 * _decay(t, 14.0))
	_streams["build"] = _make(0.3, func(t: float, _d: float) -> float:
		return (sin(TAU * 95.0 * t) * 0.9 + _noise() * 0.3) * _decay(t, 12.0))
	_streams["break"] = _make(0.5, func(t: float, _d: float) -> float:
		return (_noise() * 0.7 + sin(TAU * 70.0 * t) * 0.5) * _decay(t, 7.0), 0.5)
	_streams["death"] = _make(0.55, func(t: float, d: float) -> float:
		return _square(lerpf(320.0, 70.0, t / d), t) * 0.25 * _decay(t, 4.0))
	_streams["bow"] = _make(0.22, func(t: float, _d: float) -> float:
		return (sin(TAU * (210.0 + 15.0 * sin(TAU * 30.0 * t)) * t) * 0.6 + _noise() * 0.25) * _decay(t, 16.0))
	_streams["bolt"] = _make(0.3, func(t: float, _d: float) -> float:
		return (sin(TAU * 110.0 * t) * 0.7 + _noise() * 0.4) * _decay(t, 10.0))
	_streams["fireball"] = _make(0.8, func(t: float, d: float) -> float:
		return _noise() * sin(PI * t / d) * 0.7, 0.12)
	_streams["boom"] = _make(0.7, func(t: float, _d: float) -> float:
		return (_noise() * 0.8 + sin(TAU * 50.0 * t) * 0.6) * _decay(t, 5.0), 0.2)
	_streams["drawbridge"] = _make(1.2, func(t: float, _d: float) -> float:
		# Chain rattle over a creaking groan.
		var rattle := _noise() * (0.5 + 0.5 * sin(TAU * 18.0 * t)) * 0.35
		return (rattle + sin(TAU * (70.0 + 20.0 * sin(TAU * 1.5 * t)) * t) * 0.3) * minf(1.0, (1.2 - t) * 3.0), 0.5)
	_streams["catapult"] = _make(0.5, func(t: float, _d: float) -> float:
		return (sin(TAU * 60.0 * t) * 0.8 + _noise() * 0.4) * _decay(t, 9.0), 0.4)
	_streams["ram"] = _make(0.6, func(t: float, _d: float) -> float:
		return (sin(TAU * 45.0 * t) * 0.9 + _noise() * 0.5) * _decay(t, 6.0), 0.3)
	_streams["repair"] = _make(0.15, func(t: float, _d: float) -> float:
		return (sin(TAU * 800.0 * t) * 0.4 + _noise() * 0.2) * _decay(t, 30.0))
	_streams["frost"] = _make(0.35, func(t: float, _d: float) -> float:
		return (sin(TAU * (1400.0 - 1800.0 * t) * t) * 0.3 + _noise() * 0.2) * _decay(t, 7.0))
	_streams["lightning"] = _make(0.6, func(t: float, _d: float) -> float:
		return (_noise() * 0.9 + _square(55.0, t) * 0.2) * _decay(t, 5.0), 0.6)
	_streams["heal"] = _arpeggio([659.0, 880.0, 1175.0], 0.08)
	_streams["blink"] = _make(0.25, func(t: float, d: float) -> float:
		return sin(TAU * lerpf(300.0, 1600.0, t / d) * t) * 0.3 * _decay(t, 8.0))
	_streams["block"] = _make(0.18, func(t: float, _d: float) -> float:
		return (sin(TAU * 520.0 * t) * 0.4 + sin(TAU * 830.0 * t) * 0.3 + _noise() * 0.3) * _decay(t, 22.0))
	_streams["parry"] = _make(0.5, func(t: float, _d: float) -> float:
		return (sin(TAU * 1320.0 * t) + sin(TAU * 1980.0 * t) * 0.7 + sin(TAU * 2640.0 * t) * 0.4) * 0.3 * _decay(t, 6.0))
	_streams["hitmarker"] = _make(0.05, func(t: float, _d: float) -> float:
		return sin(TAU * 2200.0 * t) * 0.35 * _decay(t, 60.0))
	_streams["click"] = _make(0.04, func(t: float, _d: float) -> float:
		return sin(TAU * 900.0 * t) * 0.3 * _decay(t, 80.0))
	_streams["steal"] = _arpeggio([523.0, 659.0, 784.0, 1047.0], 0.09)
	_streams["alarm"] = _arpeggio([880.0, 660.0, 880.0, 660.0], 0.12)
	_streams["return"] = _arpeggio([784.0, 659.0, 523.0], 0.1)
	_streams["capture"] = _arpeggio([523.0, 659.0, 784.0, 1047.0, 784.0, 1047.0], 0.13)
	_streams["victory"] = _arpeggio([392.0, 523.0, 659.0, 784.0, 659.0, 784.0, 1047.0], 0.18)


var _lowpass_state := 0.0


## Builds a mono 16-bit stream from f(t, duration). lowpass < 1 softens noise.
func _make(duration: float, f: Callable, lowpass := 1.0) -> AudioStreamWAV:
	var count := int(duration * RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	_lowpass_state = 0.0
	for i in count:
		var t := float(i) / RATE
		var v: float = f.call(t, duration)
		_lowpass_state += (v - _lowpass_state) * lowpass
		var fade := clampf((duration - t) * 200.0, 0.0, 1.0)  # avoid end clicks
		data.encode_s16(i * 2, int(clampf(_lowpass_state * fade, -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.data = data
	return s


func _arpeggio(notes: Array, note_len: float) -> AudioStreamWAV:
	var total := note_len * notes.size() + 0.25
	return _make(total, func(t: float, _d: float) -> float:
		var idx := mini(int(t / note_len), notes.size() - 1)
		var local := t - idx * note_len
		var freq: float = notes[idx]
		return (_square(freq, t) * 0.15 + sin(TAU * freq * t) * 0.25) * _decay(local, 5.0))


func _noise() -> float:
	return randf() * 2.0 - 1.0


func _decay(t: float, rate: float) -> float:
	return exp(-t * rate)


func _square(freq: float, t: float) -> float:
	return 1.0 if fmod(t * freq, 1.0) < 0.5 else -1.0
